#!/usr/bin/env python3
"""
Run Mio ingestion directly against the crawl pipeline.
Usage: python run_mio_ingestion.py [--limit N] [--dry-run]
"""
import argparse
import asyncio
import json
import os
import sys
import time

# Ensure app/ is on path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.discovery import discover_from_url
from app.http.fetcher import PoliteFetcher
from app.extractor.cascade import extract_product_from_html
from app.locator.sitemap import discover_from_sitemaps
from app.normalization import clean_title_text


# =============================================================================
# MIO SOURCE CONFIG
# =============================================================================
MIO_SOURCE = {
    "id": "mio-se",
    "name": "Mio (Sweden)",
    "mode": "crawl",
    "isEnabled": True,
    "baseUrl": "https://www.mio.se",
    "rateLimitRps": 1.5,
    "seedUrls": ["https://www.mio.se"],
    "seedType": "sitemap",
    "includeKeywords": [],
    "categoryFilter": [],
    "robotsRespect": True,
    "useBrowserFallback": False,
    "derived": {
        "domain": "www.mio.se",
        "baseUrl": "https://www.mio.se",
        "seedUrl": "https://www.mio.se",
        "seedPath": "",
        "seedPathPattern": "",
        "strategy": "sitemap",
        "sitemapUrls": [
            "https://www.mio.se/sitemap/sitemap_index.xml",
            "https://www.mio.se/sitemap/sitemap_1774569601726_0.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_1.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_2.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_3.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_4.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_5.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_6.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_7.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_8.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_9.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_10.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_11.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_12.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_13.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_14.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_15.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_16.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_17.txt",
            "https://www.mio.se/sitemap/sitemap_1774569601726_18.txt",
        ],
        "discoveredAt": "2026-03-27T15:00:00Z"
    }
}


def run_extraction_test(sample_urls: list[str], limit: int = 20) -> dict:
    """Test extraction on a sample of URLs."""
    fetcher = PoliteFetcher(user_agent="SwiperBot/0.1 (contact: johannes@branchandleaf.se)")
    
    results = {
        "total": 0,
        "success": 0,
        "failed": 0,
        "titles": [],
        "errors": [],
        "completeness_scores": [],
    }
    
    extracted = 0
    for url in sample_urls[:limit]:
        results["total"] += 1
        try:
            r = fetcher.fetch(url, base_url="https://www.mio.se", robots_respect=True, rate_limit_rps=1.5)
            extracted_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            
            product = extract_product_from_html(
                source_id="mio-se",
                fetched_url=url,
                final_url=r.final_url,
                html=r.text,
                extracted_at_iso=extracted_at,
            )
            
            if product and product.title:
                results["success"] += 1
                results["titles"].append(product.title[:60])
                results["completeness_scores"].append(product.completeness_score)
                print(f"  ✓ [{product.completeness_score:.2f}] {product.title[:60]}")
                print(f"    price={product.price_amount} {product.price_currency}, images={len(product.images)}")
                if product.dimensions_raw:
                    d = product.dimensions_raw
                    print(f"    dims={d.get('w',0)}x{d.get('h',0)}x{d.get('d',0)} cm")
                if product.material_raw:
                    print(f"    material={product.material_raw}")
                if product.color_raw:
                    print(f"    color={product.color_raw}")
            else:
                results["failed"] += 1
                results["errors"].append(f"No product extracted from {url}")
                print(f"  ✗ Failed: {url[:60]}")
        except Exception as e:
            results["failed"] += 1
            results["errors"].append(f"{url}: {e}")
            print(f"  ✗ Error: {url[:60]}: {e}")
    
    fetcher.close()
    return results


def main():
    parser = argparse.ArgumentParser(description="Run Mio ingestion test")
    parser.add_argument("--limit", type=int, default=20, help="Number of URLs to test")
    parser.add_argument("--dry-run", action="store_true", help="Only test extraction, don't write to Firestore")
    args = parser.parse_args()
    
    print("=" * 70)
    print("  MIO INGESTION TEST")
    print("=" * 70)
    
    # Step 1: Discovery
    print("\n[1] Running discovery...")
    discovery = discover_from_url("https://www.mio.se")
    print(f"    Domain: {discovery.domain}")
    print(f"    Sitemaps found: {discovery.sitemap_count}")
    print(f"    Product URLs estimated: {discovery.product_urls_estimated}")
    print(f"    Strategy: {discovery.suggested_strategy}")
    
    # Step 2: Discover sitemap URLs
    print("\n[2] Discovering sitemap URLs...")
    fetcher = PoliteFetcher(user_agent="SwiperBot/0.1 (contact: johannes@branchandleaf.se)")
    sitemap_urls = MIO_SOURCE["derived"]["sitemapUrls"]
    all_urls = []
    
    for sm_url in sitemap_urls[:5]:  # Sample first 5 sitemaps
        try:
            r = fetcher.fetch(sm_url, base_url="https://www.mio.se", robots_respect=False)
            lines = [u.strip() for u in r.text.splitlines() if u.strip().startswith("http")]
            all_urls.extend(lines)
            print(f"    {sm_url.split('/')[-1]}: {len(lines)} URLs")
        except Exception as e:
            print(f"    Error fetching {sm_url}: {e}")
    
    fetcher.close()
    
    # Dedupe
    seen = set()
    deduped = []
    for u in all_urls:
        if u not in seen:
            seen.add(u)
            deduped.append(u)
    all_urls = deduped
    print(f"\n    Total unique URLs: {len(all_urls)}")
    
    # Filter to product candidates (URLs with /p/ or numeric patterns)
    product_urls = [u for u in all_urls if "/p/" in u or ("/" in u and u.split("/")[-1].replace("-","").isdigit())]
    print(f"    Product-candidate URLs: {len(product_urls)}")
    
    if not product_urls:
        # Fall back to using all URLs as candidates
        product_urls = all_urls[:args.limit]
    
    # Step 3: Test extraction
    print(f"\n[3] Testing extraction on {min(args.limit, len(product_urls))} URLs...")
    results = run_extraction_test(product_urls, limit=args.limit)
    
    # Summary
    print("\n" + "=" * 70)
    print("  EXTRACTION SUMMARY")
    print("=" * 70)
    print(f"  Total tested:   {results['total']}")
    print(f"  Successful:     {results['success']}")
    print(f"  Failed:         {results['failed']}")
    
    if results["completeness_scores"]:
        avg_score = sum(results["completeness_scores"]) / len(results["completeness_scores"])
        print(f"  Avg completeness: {avg_score:.2f}")
        print(f"  Min completeness:  {min(results['completeness_scores']):.2f}")
        print(f"  Max completeness:  {max(results['completeness_scores']):.2f}")
    
    if results["errors"] and len(results["errors"]) <= 5:
        print(f"\n  Errors:")
        for e in results["errors"]:
            print(f"    - {e[:80]}")
    
    return results


if __name__ == "__main__":
    main()

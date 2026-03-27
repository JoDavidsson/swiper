#!/usr/bin/env python3
"""
Test Swiper crawl pipeline against real Swedish furniture retailers.
Tests discovery/preview against: Mio, Svenska Hem, Comfort, Skona Hem, IKEA SE.
"""
import sys
import os

# Add app to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import json
from app.discovery import discover_from_url
from app.http.fetcher import PoliteFetcher


RETAILERS = [
    ("Mio", "https://www.mio.se/soffor"),
    ("Svenska Hem", "https://www.svenskahem.se/soffor"),
    ("Comfort", "https://www.comfort.se/soffor"),
    ("Skona Hem", "https://www.skonahem.se/soffor"),
    ("IKEA SE", "https://www.ikea.se/soffor"),
]


def test_retailer(name: str, url: str) -> dict:
    """Run discovery against a single retailer. Returns result dict."""
    print(f"\n{'='*70}")
    print(f"  TESTING: {name}")
    print(f"  URL: {url}")
    print(f"{'='*70}")
    
    result = {
        "retailer": name,
        "input_url": url,
        "robots_found": False,
        "sitemap_count": 0,
        "sitemaps_found": [],
        "total_urls_sampled": 0,
        "product_urls_estimated": 0,
        "category_urls_estimated": 0,
        "matching_path_urls": 0,
        "suggested_strategy": "unknown",
        "strategy_reason": "",
        "errors": [],
        "warnings": [],
    }
    
    try:
        fetcher = PoliteFetcher(user_agent="Swiper-Discovery-Test/1.0")
        
        discovery = discover_from_url(
            url,
            fetcher=fetcher,
            rate_limit_rps=1.0,
        )
        
        result["robots_found"] = discovery.robots_found
        result["sitemap_count"] = discovery.sitemap_count
        result["sitemaps_found"] = discovery.sitemaps_found[:5]  # Cap for readability
        result["total_urls_sampled"] = discovery.total_urls_sampled
        result["product_urls_estimated"] = discovery.product_urls_estimated
        result["category_urls_estimated"] = discovery.category_urls_estimated
        result["matching_path_urls"] = discovery.matching_path_urls
        result["suggested_strategy"] = discovery.suggested_strategy
        result["strategy_reason"] = discovery.strategy_reason
        result["errors"] = discovery.errors
        result["warnings"] = discovery.warnings
        
        fetcher.close()
        
    except Exception as e:
        result["errors"].append(f"Exception: {str(e)}")
    
    return result


def main():
    print("Swiper Crawl Pipeline - Swedish Furniture Retailer Test")
    print("=" * 70)
    
    all_results = []
    
    for name, url in RETAILERS:
        r = test_retailer(name, url)
        all_results.append(r)
        
        # Print summary for this retailer
        print(f"\n  RESULTS for {name}:")
        print(f"  - robots.txt found: {r['robots_found']}")
        print(f"  - sitemaps found: {r['sitemap_count']}")
        if r['sitemaps_found']:
            for sm in r['sitemaps_found'][:3]:
                print(f"      {sm}")
        print(f"  - URLs sampled: {r['total_urls_sampled']}")
        print(f"  - Product URLs estimated: {r['product_urls_estimated']}")
        print(f"  - Category URLs estimated: {r['category_urls_estimated']}")
        print(f"  - Matching path URLs: {r['matching_path_urls']}")
        print(f"  - Suggested strategy: {r['suggested_strategy']}")
        print(f"  - Strategy reason: {r['strategy_reason']}")
        if r['errors']:
            print(f"  - ERRORS: {r['errors']}")
        if r['warnings']:
            print(f"  - WARNINGS: {r['warnings']}")
    
    # Summary table
    print(f"\n\n{'='*70}")
    print("  SUMMARY TABLE")
    print(f"{'='*70}")
    print(f"{'Retailer':<15} {'robots.txt':<10} {'sitemaps':<10} {'sampled':<10} {'products':<10} {'strategy':<10}")
    print("-" * 70)
    for r in all_results:
        print(f"{r['retailer']:<15} {str(r['robots_found']):<10} {r['sitemap_count']:<10} "
              f"{r['total_urls_sampled']:<10} {r['product_urls_estimated']:<10} {r['suggested_strategy']:<10}")
    
    # Save results
    output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "discovery_test_results.json")
    with open(output_path, "w") as f:
        json.dump(all_results, f, indent=2)
    print(f"\n\nDetailed results saved to: {output_path}")
    
    return all_results


if __name__ == "__main__":
    main()

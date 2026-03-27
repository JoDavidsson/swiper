#!/usr/bin/env python3
"""
Full Mio ingestion - extracts and writes all products to Firestore.
Uses GOOGLE_APPLICATION_CREDENTIALS env var for auth.
"""
import argparse
import asyncio
import os
import sys
import time
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.firestore_client import (
    get_firestore_client, create_run, update_run, write_items,
    upsert_crawl_url, record_extraction_failure, write_product_snapshot,
    upsert_metrics_daily,
)
from app.http.fetcher import PoliteFetcher, FetchError
from app.extractor.cascade import extract_product_from_html
from app.normalization import (
    clean_title_text, clean_description_text,
    infer_color_from_title, infer_size_from_title,
    normalize_color_family, normalize_material,
    normalize_price_amount, validate_currency,
)
from app.monitor.drift import check_drift

# ── GCP credentials ────────────────────────────────────────────────────────────
CREDS_PATH = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS", "")
if not CREDS_PATH or not os.path.isfile(CREDS_PATH):
    print(f"[FATAL] GOOGLE_APPLICATION_CREDENTIALS not set or file not found: {CREDS_PATH!r}")
    sys.exit(1)

# ── Source config ──────────────────────────────────────────────────────────────
MIO_SOURCE = {
    "id": "mio-se",
    "name": "Mio (Sweden)",
    "baseUrl": "https://www.mio.se",
    "rateLimitRps": 1.5,
    "robotsRespect": True,
    "useBrowserFallback": False,
    "sitemapUrls": [
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
    "categoryFilter": ["soff", "sofa", "fåtölj", "fatoelj", "divan", "stol", "möbel"],
}

PRODUCT_PATH_PATTERNS = ["/p/", "-p", "/produkt/", "/vara/", "/artikel/"]
NON_PRODUCT_EXTENSIONS = [".pdf", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg", ".css", ".js", ".xml", ".txt"]

def is_product_url(url: str) -> bool:
    """Fast gate: only URLs with a product-like path pattern."""
    if not url:
        return False
    url_lower = url.lower()
    # Drop non-product extensions
    if any(url_lower.endswith(ext) for ext in NON_PRODUCT_EXTENSIONS):
        return False
    # Must match at least one product pattern
    return any(pat in url_lower for pat in PRODUCT_PATH_PATTERNS)

def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def _utc_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")

def progress_bar(current, total, prefix="Progress", bar_len=30):
    pct = (current / total * 100) if total > 0 else 0
    filled = int(bar_len * current / total) if total > 0 else 0
    bar = "█" * filled + "░" * (bar_len - filled)
    elapsed = time.time()
    print(f"\r[{bar}] {current}/{total} ({pct:.0f}%) {prefix}", end="", flush=True)
    if current >= total:
        print()  # newline when done

def collect_sitemap_urls(fetcher: PoliteFetcher, sitemap_urls: list[str]) -> list[str]:
    """Fetch all sitemaps and collect product-candidate URLs."""
    all_urls = []
    for sm_url in sitemap_urls:
        try:
            r = fetcher.fetch(sm_url, base_url="https://www.mio.se", robots_respect=False, rate_limit_rps=2.0)
            lines = [u.strip() for u in r.text.splitlines() if u.strip().startswith("http")]
            all_urls.extend(lines)
        except Exception as e:
            print(f"  [sitemap error] {sm_url}: {e}")
    
    # Dedupe
    seen = set()
    deduped = []
    for u in all_urls:
        if u not in seen:
            seen.add(u)
            deduped.append(u)
    
    # Filter to product URLs
    product_urls = [u for u in deduped if is_product_url(u)]
    print(f"\n  Collected {len(deduped)} total URLs, {len(product_urls)} product candidates")
    return product_urls

def extract_one(args) -> dict | None:
    """Extract a single product from a URL. Returns item dict or None."""
    url, source_id = args
    fetcher = PoliteFetcher(user_agent="SwiperBot/0.1 (contact: johannes@branchandleaf.se)")
    try:
        r = fetcher.fetch(url, base_url="https://www.mio.se", robots_respect=True, rate_limit_rps=1.5)
        extracted_at = _utc_now_iso()
        product = extract_product_from_html(
            source_id=source_id,
            fetched_url=url,
            final_url=r.final_url,
            html=r.text,
            extracted_at_iso=extracted_at,
        )
        if not product or not product.title:
            return None
        
        # Build item dict
        item = {
            "id": None,  # Let firestore_client assign
            "sourceId": source_id,
            "sourceUrl": url,
            "canonicalUrl": getattr(product, 'canonical_url', url) or url,
            "title": clean_title_text(product.title),
            "description": clean_description_text(getattr(product, 'description', None) or ""),
            "descriptionShort": getattr(product, 'description_short', None),
            "brand": getattr(product, 'brand', None),
            "priceAmount": getattr(product, 'price_amount', None),
            "priceCurrency": getattr(product, 'price_currency', None),
            "priceRaw": getattr(product, 'price_raw', None),
            "images": getattr(product, 'images', []) or [],
            "dimensionsRaw": getattr(product, 'dimensions_raw', None),
            "materialRaw": getattr(product, 'material_raw', None),
            "colorRaw": getattr(product, 'color_raw', None),
            "completenessScore": getattr(product, 'completeness_score', 0.0),
            "firstSeenAt": extracted_at,
            "lastSeenAt": extracted_at,
            "lastUpdatedAt": extracted_at,
            "isActive": True,
        }
        
        # Normalize
        if item.get("colorRaw"):
            item["colorFamily"] = normalize_color_family(item["colorRaw"])
        if item.get("materialRaw"):
            item["materialNormalized"] = normalize_material(item["materialRaw"])
        if item.get("title"):
            item["colorInferred"] = infer_color_from_title(item["title"])
            item["sizeInferred"] = infer_size_from_title(item["title"])
        
        return item
    except FetchError as e:
        return None
    except Exception as e:
        return None
    finally:
        fetcher.close()

def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-size", type=int, default=50, help="Concurrent workers")
    parser.add_argument("--max-urls", type=int, default=0, help="Max URLs to process (0=all)")
    parser.add_argument("--dry-run", action="store_true", help="Extract only, skip Firestore write")
    args = parser.parse_args()

    source_id = MIO_SOURCE["id"]
    batch_size = args.batch_size

    print("=" * 60)
    print("  MIO FULL INGESTION")
    print("=" * 60)

    # ── Initialize Firestore ──────────────────────────────────────────────
    print("\n[1] Connecting to Firestore...")
    db = get_firestore_client()
    print("  ✓ Firestore connected")

    # ── Create ingestion run ───────────────────────────────────────────────
    run_id = create_run(db, source_id, "running")
    print(f"\n[2] Created run: {run_id}")

    # ── Discover URLs ──────────────────────────────────────────────────────
    print("\n[3] Discovering product URLs from sitemaps...")
    fetcher = PoliteFetcher(user_agent="SwiperBot/0.1 (contact: johannes@branchandleaf.se)")
    product_urls = collect_sitemap_urls(fetcher, MIO_SOURCE["sitemapUrls"])
    fetcher.close()

    if args.max_urls > 0:
        product_urls = product_urls[:args.max_urls]
    
    print(f"  Total to process: {len(product_urls)}")

    if not product_urls:
        update_run(db, run_id, "failed", {}, "No product URLs found")
        print("\n[FAIL] No product URLs found in sitemaps")
        return

    # ── Extract in batches ─────────────────────────────────────────────────
    print(f"\n[4] Extracting products ({batch_size} concurrent workers)...")
    all_items = []
    failed_urls = []
    start_time = time.time()
    total = len(product_urls)
    completed = 0
    batch_num = 0

    with ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = {executor.submit(extract_one, (url, source_id)): url for url in product_urls}
        
        for future in as_completed(futures):
            url = futures[future]
            completed += 1
            batch_num += 1
            
            try:
                item = future.result()
                if item:
                    all_items.append(item)
                else:
                    failed_urls.append(url)
            except Exception as e:
                failed_urls.append(url)
            
            if batch_num % 50 == 0 or batch_num == total:
                elapsed = time.time() - start_time
                rate = completed / elapsed if elapsed > 0 else 0
                remaining = (total - completed) / rate if rate > 0 else 0
                print(f"\n  [{completed}/{total}] Extracted: {len(all_items)}, Failed: {len(failed_urls)}, Rate: {rate:.1f}/s, ETA: {remaining:.0f}s")
            
            if completed >= (args.max_urls or float('inf')):
                break  # Stop when max_urls limit reached (0 = unlimited)

    print(f"\n  Extraction complete: {len(all_items)} items, {len(failed_urls)} failed")

    if args.dry_run:
        print("\n[DRY RUN] Skipping Firestore write")
        update_run(db, run_id, "stopped", {
            "urlsDiscovered": len(product_urls),
            "urlsExtracted": len(all_items),
            "failed": len(failed_urls),
        }, "Dry run")
        return

    # ── Write to Firestore ─────────────────────────────────────────────────
    print(f"\n[5] Writing {len(all_items)} items to Firestore...")
    if all_items:
        upserted, failed_write, item_ids = write_items(db, all_items, source_id)
        print(f"  ✓ Upserted: {upserted}, Failed: {failed_write}")
    else:
        upserted, failed_write = 0, 0

    # ── Write metrics ──────────────────────────────────────────────────────
    metrics = {
        "urlsDiscovered": len(product_urls),
        "urlsCandidateProducts": len(product_urls),
        "fetched": len(product_urls),
        "urlsExtracted": len(all_items),
        "success": len(all_items),
        "upserted": upserted,
        "failed": failed_write + len(failed_urls),
        "blockedCount": 0,
        "avgCompleteness": sum(i.get("completenessScore", 0) for i in all_items) / len(all_items) if all_items else 0,
        "descriptionRate": sum(1 for i in all_items if i.get("description")) / len(all_items) if all_items else 0,
        "dimensionsRate": sum(1 for i in all_items if i.get("dimensionsRaw")) / len(all_items) if all_items else 0,
        "materialRate": sum(1 for i in all_items if i.get("materialRaw")) / len(all_items) if all_items else 0,
    }
    doc_id = upsert_metrics_daily(db, source_id=source_id, date=_utc_date(), metrics=metrics)
    print(f"  ✓ Metrics saved: {doc_id}")

    # ── Complete run ──────────────────────────────────────────────────────
    stats = {
        "urlsDiscovered": len(product_urls),
        "urlsCandidateProducts": len(product_urls),
        "fetched": len(product_urls),
        "urlsExtracted": len(all_items),
        "success": len(all_items),
        "upserted": upserted,
        "failed": failed_write + len(failed_urls),
    }
    update_run(db, run_id, "succeeded", stats)
    
    elapsed_total = time.time() - start_time
    print(f"\n{'='*60}")
    print(f"  INGESTION COMPLETE in {elapsed_total:.1f}s")
    print(f"  Items written to Firestore: {upserted}")
    print(f"{'='*60}")

if __name__ == "__main__":
    run()

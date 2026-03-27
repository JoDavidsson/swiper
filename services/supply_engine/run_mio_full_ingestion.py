#!/usr/bin/env python3
"""
Full Mio ingestion - extracts and writes all products to Firestore in batches.
Uses GOOGLE_APPLICATION_CREDENTIALS env var for auth.
"""
import argparse
import os
import sys
import time
import gc
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app.firestore_client import (
    get_firestore_client, create_run, update_run, write_items,
    upsert_crawl_url, upsert_metrics_daily,
)
from app.http.fetcher import PoliteFetcher, FetchError
from app.extractor.cascade import extract_product_from_html
from app.normalization import (
    clean_title_text, clean_description_text,
    infer_color_from_title, infer_size_from_title,
    normalize_color_family, normalize_material,
    normalize_price_amount,
)
from app.recipes.mio import get_mio_recipe

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
}

PRODUCT_PATH_PATTERNS = ["/p/"]
NON_PRODUCT_EXTENSIONS = [".pdf", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".svg", ".css", ".js", ".xml", ".txt"]

def is_product_url(url: str) -> bool:
    if not url:
        return False
    url_lower = url.lower()
    if any(url_lower.endswith(ext) for ext in NON_PRODUCT_EXTENSIONS):
        return False
    return any(pat in url_lower for pat in PRODUCT_PATH_PATTERNS)

def _utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def _utc_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")

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

    seen = set()
    deduped = []
    for u in all_urls:
        if u not in seen:
            seen.add(u)
            deduped.append(u)

    product_urls = [u for u in deduped if is_product_url(u)]
    print(f"\n  Collected {len(deduped)} total URLs, {len(product_urls)} product candidates")
    return product_urls

def extract_one(args) -> dict | None:
    """Extract a single product from a URL. Returns item dict or None."""
    url, source_id, recipe = args
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
            recipe=recipe,
        )
        if not product or not product.title:
            return None

        item = {
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
            "images": [{"url": u, "alt": product.title[:200]} for u in (product.images or []) if isinstance(u, str) and u],
            "dimensionsCm": getattr(product, 'dimensions_raw', None),
            "material": normalize_material(getattr(product, 'material_raw', None)),
            "colorFamily": normalize_color_family(getattr(product, 'color_raw', None)),
            "completenessScore": getattr(product, 'completeness_score', 0.0),
            "firstSeenAt": extracted_at,
            "lastSeenAt": extracted_at,
            "lastUpdatedAt": extracted_at,
            "isActive": True,
            "sourceType": "crawl",
        }
        return item
    except FetchError:
        return None
    except Exception:
        return None
    finally:
        fetcher.close()

def run():
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch-size", type=int, default=30, help="Concurrent workers")
    parser.add_argument("--write-batch-size", type=int, default=200, help="Firestore write batch size")
    parser.add_argument("--max-urls", type=int, default=0, help="Max URLs to process (0=all)")
    parser.add_argument("--dry-run", action="store_true", help="Extract only, skip Firestore write")
    args = parser.parse_args()

    source_id = MIO_SOURCE["id"]
    batch_size = args.batch_size
    write_batch_size = args.write_batch_size
    max_urls = args.max_urls or float('inf')

    print("=" * 60)
    print("  MIO FULL INGESTION (batch writer)")
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
        return

    # ── Get Mio recipe ─────────────────────────────────────────────────────
    recipe = get_mio_recipe()
    print(f"\n[4] Extracting with recipe: {recipe['recipeId']} v{recipe['version']}")

    # ── Extract in batches, write incrementally ────────────────────────────
    all_items: list = []
    failed_urls: list = []
    total_upserted = 0
    total_failed_write = 0
    start_time = time.time()
    completed = 0
    urls_to_process = [u for u in product_urls if is_product_url(u)]

    with ThreadPoolExecutor(max_workers=batch_size) as executor:
        futures = {executor.submit(extract_one, (url, source_id, recipe)): url for url in urls_to_process}

        for future in as_completed(futures):
            url = futures[future]
            completed += 1

            try:
                item = future.result()
                if item:
                    all_items.append(item)
                else:
                    failed_urls.append(url)
            except Exception:
                failed_urls.append(url)

            # Progress every 50 URLs
            if completed % 50 == 0 or completed == len(urls_to_process):
                elapsed = time.time() - start_time
                rate = completed / elapsed if elapsed > 0 else 0
                eta = (len(urls_to_process) - completed) / rate if rate > 0 else 0
                mem_mb = 0  # can't easily get from subprocess
                print(f"\n  [{completed}/{len(urls_to_process)}] Extracted: {len(all_items)}, "
                      f"Failed: {len(failed_urls)}, Rate: {rate:.1f}/s, ETA: {eta:.0f}s")

            # Batch write every write_batch_size items
            if len(all_items) >= write_batch_size:
                if not args.dry_run:
                    upserted, failed_write, _ = write_items(db, all_items, source_id)
                    total_upserted += upserted
                    total_failed_write += failed_write
                    print(f"  ✓ Batch write: +{upserted} items (total: {total_upserted})")
                else:
                    print(f"  [DRY RUN] Would write {len(all_items)} items")
                all_items = []
                gc.collect()

            # Respect max_urls limit
            if completed >= max_urls:
                break

    # ── Final write ────────────────────────────────────────────────────────
    if all_items:
        if not args.dry_run:
            upserted, failed_write, _ = write_items(db, all_items, source_id)
            total_upserted += upserted
            total_failed_write += failed_write
            print(f"  ✓ Final batch write: +{upserted} items")
        else:
            print(f"  [DRY RUN] Would write final {len(all_items)} items")

    elapsed_total = time.time() - start_time
    print(f"\n  Extraction complete: {len(all_items)} remaining, {len(failed_urls)} failed")

    if args.dry_run:
        update_run(db, run_id, "stopped", {
            "urlsDiscovered": len(product_urls),
            "urlsExtracted": completed - len(failed_urls),
            "failed": len(failed_urls),
        }, "Dry run")
        return

    # ── Write metrics ──────────────────────────────────────────────────────
    total_extracted = completed - len(failed_urls)
    metrics = {
        "urlsDiscovered": len(product_urls),
        "urlsCandidateProducts": len(product_urls),
        "fetched": completed,
        "urlsExtracted": total_extracted,
        "success": total_extracted,
        "upserted": total_upserted,
        "failed": total_failed_write + len(failed_urls),
        "avgCompleteness": sum(i.get("completenessScore", 0) for i in all_items) / max(len(all_items), 1),
    }
    upsert_metrics_daily(db, source_id=source_id, date=_utc_date(), metrics=metrics)

    # ── Complete run ──────────────────────────────────────────────────────
    stats = {
        "urlsDiscovered": len(product_urls),
        "urlsCandidateProducts": len(product_urls),
        "fetched": completed,
        "urlsExtracted": total_extracted,
        "success": total_extracted,
        "upserted": total_upserted,
        "failed": total_failed_write + len(failed_urls),
    }
    update_run(db, run_id, "succeeded", stats)

    print(f"\n{'='*60}")
    print(f"  INGESTION COMPLETE in {elapsed_total:.1f}s")
    print(f"  Total items written to Firestore: {total_upserted}")
    print(f"{'='*60}")

if __name__ == "__main__":
    run()

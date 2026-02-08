#!/usr/bin/env python3
"""
One-time migration script: update 6 failing sources to use crawl strategy
with browser fallback enabled.

These sources have sitemaps that only contain category-level URLs (no product
pages), so sitemap-based discovery yields 0 products.  Switching to the
"crawl" strategy lets the category crawler visit listing pages and extract
product links from the rendered DOM.

Sources fixed:
  1. Sleepo            (JS-rendered SPA)
  2. Nordiska Galleriet (JS-rendered SPA)
  3. Homeroom           (JS-rendered SPA)
  4. SoffaDirekt        (sitemap has only category pages)
  5. Svenssons          (sitemap has only category pages)
  6. Newport            (sitemap has only category pages)

Usage:
  # Against the emulator
  FIRESTORE_EMULATOR_HOST=localhost:8080 python scripts/fix_spa_sources.py

  # Against production Firestore (requires credentials)
  GOOGLE_APPLICATION_CREDENTIALS=path/to/key.json python scripts/fix_spa_sources.py
"""

import os
import sys

# Allow importing from the supply engine package
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "services", "supply_engine"))

from app.firestore_client import get_firestore_client


# ──────────────────────────────────────────────────────────────────────────────
# Source configs to patch.  Keyed by domain (matched against baseUrl/url).
# ──────────────────────────────────────────────────────────────────────────────
SOURCES_TO_FIX = {
    "sleepo.se": {
        "seedUrls": ["https://www.sleepo.se/mobler/soffor-fatoljer/"],
        "seedType": "category",
        "useBrowserFallback": True,
        "maxPagesPerRun": 80,
        "maxDepth": 3,
    },
    "nordiskagalleriet.se": {
        "seedUrls": ["https://www.nordiskagalleriet.se/no-ga/soffor"],
        "seedType": "category",
        "useBrowserFallback": True,
        "maxPagesPerRun": 80,
        "maxDepth": 3,
    },
    "homeroom.se": {
        "seedUrls": ["https://www.homeroom.se/mobler/soffor-fatoljer/soffor"],
        "seedType": "category",
        "useBrowserFallback": True,
        "maxPagesPerRun": 80,
        "maxDepth": 3,
    },
    "soffadirekt.se": {
        "seedUrls": ["https://www.soffadirekt.se/"],
        "seedType": "category",
        "useBrowserFallback": True,
        "maxPagesPerRun": 100,
        "maxDepth": 3,
    },
    "svenssons.se": {
        "seedUrls": ["https://www.svenssons.se/mobler/soffor/"],
        "seedType": "category",
        "useBrowserFallback": True,
        "maxPagesPerRun": 80,
        "maxDepth": 3,
    },
    "newport.se": {
        "seedUrls": ["https://www.newport.se/shop/mobler/soffor"],
        "seedType": "category",
        "useBrowserFallback": True,
        "maxPagesPerRun": 80,
        "maxDepth": 3,
    },
}


def _domain_matches(url: str, target_domain: str) -> bool:
    """Check if a URL belongs to the target domain (ignoring www. prefix)."""
    if not url:
        return False
    url_lower = url.lower()
    bare = target_domain.lower().replace("www.", "")
    return bare in url_lower


def main():
    db = get_firestore_client()
    sources_ref = db.collection("sources")
    all_sources = sources_ref.stream()

    updated = 0
    skipped = 0

    print("=" * 60)
    print("  Fix SPA / category-only sources")
    print("=" * 60)
    print()

    for doc in all_sources:
        data = doc.to_dict() or {}
        source_url = data.get("url") or data.get("baseUrl") or ""
        source_name = data.get("name", "(unnamed)")

        # Check if this source matches any of the domains we want to fix
        matched_domain = None
        for domain in SOURCES_TO_FIX:
            if _domain_matches(source_url, domain):
                matched_domain = domain
                break

        if not matched_domain:
            continue

        patch = SOURCES_TO_FIX[matched_domain]
        print(f"  Updating: {source_name} ({matched_domain})")
        print(f"    ID:       {doc.id}")
        print(f"    URL:      {source_url}")
        print(f"    Strategy: → category crawl")
        print(f"    Browser:  → enabled")

        # Build the Firestore update.
        # We clear the 'derived' config so the engine falls back to legacy
        # fields (seedType + seedUrls), which we set to "category" + the
        # correct seed URLs.
        from google.cloud.firestore_v1 import DELETE_FIELD

        update_data = {
            # Force legacy mode with crawl strategy
            "seedType": patch["seedType"],
            "seedUrls": patch["seedUrls"],
            "useBrowserFallback": patch["useBrowserFallback"],
            "maxPagesPerRun": patch["maxPagesPerRun"],
            "maxDepth": patch["maxDepth"],
            # Remove derived config so legacy fields take precedence
            "derived": DELETE_FIELD,
        }

        sources_ref.document(doc.id).update(update_data)
        print(f"    ✓ Done")
        print()
        updated += 1

    # Report domains we expected to fix but didn't find
    if updated < len(SOURCES_TO_FIX):
        print(f"  Warning: only updated {updated}/{len(SOURCES_TO_FIX)} sources.")
        print(f"  Make sure all 6 sources exist in Firestore.")
    else:
        print(f"  All {updated} sources updated successfully!")

    print()
    print("=" * 60)
    print(f"  Result: {updated} updated, {len(SOURCES_TO_FIX) - updated} not found")
    print("=" * 60)


if __name__ == "__main__":
    main()

# Changelog

## 2026-02-07 – Full product description: remove truncation, show in detail sheet

- **Supply Engine**: Removed 500-character truncation on `descriptionShort` in both crawl and feed ingestion. Full product descriptions are now stored.
- **Detail Sheet**: Product description now displayed below the price on the product detail bottom sheet (secondary text color, 1.5 line height).
- **DATA_MODEL.md**: Updated `descriptionShort` field doc to reflect no truncation.

## 2026-02-07 – Recommendation Phase 1: Multi-Queue Retrieval + Batch Serving Upgrade

Implemented the first serving upgrade for recommendations to increase candidate breadth, improve exploration effectiveness, and add request-level observability for offline evaluation.

### Recommendation Engine Changes
- **Multi-queue retrieval in deck API**: candidates now come from six queues (`fresh_promoted`, `fresh_catalog`, `preference_match`, `persona_similar`, `long_tail`, `serendipity`) and are merged via adaptive per-queue quotas.
- **Wider retrieval and candidate caps**: dynamic defaults increased to improve recall (`itemsFetchLimit` and `candidateCap` scale higher with deck limit).
- **Persona-as-retrieval source**: top persona item IDs are now fetched directly and injected as their own queue, not only used during scoring.
- **Larger ranking window before slicing**: ranker now scores a broad `rankWindow` before `applyExploration`, so exploration can actually replace items from a meaningful pool.
- **Exploration policy naming alignment**: server now reports `sample_from_top_2limit` (matching implementation semantics).
- **Post-smoke tuning**: pass-2 candidate backfill now prioritizes `fresh_catalog/long_tail/serendipity` before `fresh_promoted`, and cold-start queue ratios were rebalanced to reduce promoted overflow and increase catalog variety.

### Client Serving and Telemetry
- **Deck batch size increased**: client now requests 30 items per deck call (up from 15).
- **Proactive refill**: background refill now triggers at 12 remaining cards (up from 6), reducing empty/flat deck transitions.
- **Prefetch depth increased**: image prefetch now covers top + next 7 cards.
- **Request correlation**: client sends `requestId` on `deck_request`, backend echoes it in response rank metadata, and deck/swipe/impression events propagate it.

### Event Schema / Validation
- Extended `rank` payload schema with optional: `requestId`, `candidateCount`, `rankWindow`, `retrievalQueues`.
- Tightened batch validation for these new optional rank fields on `deck_response`.

### Docs Updated
- `docs/RECOMMENDATIONS_ENGINE.md` – Added Phase 1 serving architecture and updated deck integration details.
- `docs/EVENT_SCHEMA_V1.md` – Added request correlation guidance and new rank metadata recommendations.
- `docs/EVENT_TRACKING.md` – Updated deck request/response field matrix.
- `docs/IMPLEMENTATION_PLAN.md` – Marked Phase 6.6–6.8 milestones complete.

## 2026-02-07 – Fix Deck Filters + Image URL Double-Encoding

Fixed three issues preventing deck filters from working, and resolved image display failures caused by double-encoded URLs in Firestore.

### Filter Fixes
- **`newUsed` missing from goldItems**: Gold promotion in `policy.py` did not copy the `newUsed` field. Added `"newUsed": item_data.get("newUsed", "new")` to the gold document builder. Backfilled all 5,386 existing goldItems.
- **`sizeClass` always "medium"**: Added `infer_size_from_title()` to `normalization.py` that extracts size from Swedish sofa title patterns (`2-sits`→small, `3-sits`→medium, `4-sits+`/`U-formad`/`hörnsoffa`→large). Updated `normalize_size_class()` to use title inference as fallback. Backfilled 2,662 goldItems (now: 15% small, 49% medium, 34% large).
- **`colorFamily`**: Already working correctly with good distribution.

### Image URL Fix
- **Root cause**: Image URLs stored in Firestore had double-encoded percent characters (`%25c3%25b6` instead of `%C3%B6`) and incorrect product-page-path prefixes before `/assets/blobs/`.
- **Fix**: Data migration script that fully decodes all URL encoding layers, extracts correct `/assets/blobs/` path for Chilli URLs, and re-encodes only non-ASCII characters. Fixed 5,446 items and 5,332 goldItems.

### Debug Instrumentation Cleanup
- Removed all debug logging from `deck.ts`, `image_proxy.ts`, and 5 Flutter files (`swipe_deck.dart`, `draggable_swipe_card.dart`, `deck_provider.dart`, `likes_screen.dart`, `event_tracker.dart`).

### Files Changed
- `services/supply_engine/app/normalization.py` – Added `infer_size_from_title()`, updated `normalize_size_class()` with title param
- `services/supply_engine/app/sorting/policy.py` – Added `newUsed` to gold document
- `services/supply_engine/app/crawl_ingestion.py` – Pass title to `normalize_size_class()`
- `services/supply_engine/app/feed_ingestion.py` – Pass title to `normalize_size_class()`
- `services/supply_engine/tests/test_normalization.py` – Added tests for title-based size inference
- `firebase/functions/src/api/deck.ts` – Removed debug instrumentation
- `firebase/functions/src/api/image_proxy.ts` – Removed debug instrumentation
- `apps/Swiper_flutter/lib/` – Removed debug instrumentation from 5 files

## 2026-02-07 – Embedded JS State Extractor + Image URL Encoding Fix

New extraction capability that pulls products directly from JavaScript state variables embedded in category page HTML, bypassing the need for headless browser rendering. Also fixed broken image URLs caused by unencoded Swedish characters.

### What's New
- **`signals.py`**: Detects `window.INITIAL_DATA`, `window.__INITIAL_STATE__`, `window.__NUXT__`, and `window.__PRELOADED_STATE__` patterns in `<script>` tags.
- **`embedded_state.py`** (new module): Retailer-specific handlers for Chilli (INITIAL_DATA) and RoyalDesign (__INITIAL_STATE__), plus a generic fallback that searches for product-like arrays in any state tree.
- **`cascade.py`**: New `extract_products_batch_from_html()` function, plus `_encode_non_ascii()` helper that properly percent-encodes Swedish characters (ö→%C3%B6, ä→%C3%A4) in image URLs using multi-round decode-then-reencode strategy.
- **`crawl_ingestion.py`**: Phase 1.5 added between URL Discovery and Per-Page Extraction. Fetches seed/category pages, batch-extracts products from embedded state, and deduplicates against the per-page extraction queue.

### Image URL Fix
- **Root cause**: Chilli's INITIAL_DATA returns relative image paths with raw Unicode characters (e.g., `/assets/blobs/möbler-soffor/...`). When joined with base URLs, the non-ASCII characters were not percent-encoded, causing browsers to fail loading the images.
- **Fix**: All URL resolution functions (`_absolute()`, `_safe_urljoin()`) now decode fully, then re-encode non-ASCII characters. Handles double-encoded, mixed-encoded, and raw Unicode URLs.

### Results
- **Chilli**: 24 products per category page, 100% completeness, all images loading
- **RoyalDesign**: 31 products per category page, 100% completeness
- **Deck**: 20/20 images verified loading (100% success rate)
- No headless browser (Playwright) required for these retailers

### Files Changed
- `services/supply_engine/app/extractor/signals.py` – Window state pattern detection
- `services/supply_engine/app/extractor/embedded_state.py` – New module
- `services/supply_engine/app/extractor/cascade.py` – Batch extraction + URL encoding fix
- `services/supply_engine/app/crawl_ingestion.py` – Phase 1.5 integration

## 2026-02-07 – Fix Sorting Engine Integration Bugs

Five integration bugs found during pipeline audit and fixed:

1. **Recipe extraction skipped enrichment** – Items extracted via the recipe runner path were returned without calling `_apply_enrichment()`, so they had no breadcrumbs, facets, identity keys, or offer data. Now all four extraction paths (JSON-LD, embedded JSON, recipe, DOM) pass through enrichment.
2. **Classification not auto-triggered after crawl** – Crawl ingestion wrote items to `items` but never classified or promoted them to `goldItems`. Added Phase 4 to the crawl pipeline: after upsert, each item is classified, written to `goldItems` if accepted, or to `reviewQueue` if uncertain. `write_items()` now returns item IDs to support this.
3. **`/kill-switch` params unreachable via Firebase proxy** – The endpoint used bare query parameters on a POST, but the Firebase proxy only forwards query params for GET. Converted to a `BaseModel` request body so the JSON body from the proxy is correctly parsed.
4. **Dead variables in extraction** – Removed unused `_jsonld_obj_for_enrichment` and `_embedded_node_for_enrichment` variables.
5. **Brittle `__import__` hack** – Replaced `__import__("app.sorting.classifier", ...)` with a standard `from app.sorting.classifier import classify_item`.

### Files Changed
- `services/supply_engine/app/extractor/cascade.py` – Bug 1 + 4
- `services/supply_engine/app/firestore_client.py` – Bug 2a (write_items returns IDs)
- `services/supply_engine/app/crawl_ingestion.py` – Bug 2b (Phase 4 auto-classify)
- `services/supply_engine/app/main.py` – Bug 3 (kill-switch BaseModel)
- `services/supply_engine/app/sorting/policy.py` – Bug 5 (clean import)

## 2026-02-07 – Implement "Crawl Wide, Show Narrow" Execution Plan

Full implementation of the 6-epic, 29-ticket plan for Bronze→Silver→Gold pipeline, classification engine, review queue, and observability.

### EPIC A: Ingestion Reliability
- **A3: Incremental recrawl** – `html_hash` skip logic prevents re-extracting unchanged pages. Known hashes stored in `crawlUrls` collection and checked before extraction. Stats track `skippedUnchanged` count.
- **A5: Per-domain retry/backoff** – Configurable retry policies per domain with separate handling for 429 (rate limit cooldown), 5xx (exponential backoff), and timeouts. Domain failure counters tracked for observability.

### EPIC B: Metadata Enrichment
- **B1: Breadcrumbs + categories** – Extracted from JSON-LD `BreadcrumbList` and DOM `<nav>` elements. Product type inferred from breadcrumbs + title using Swedish/English lexicon.
- **B2: Facets** – Extracted from JSON-LD `additionalProperty`, HTML `<dl>` definition lists, specification tables, and labeled spans.
- **B3: Variants** – Extracted from JSON-LD `hasVariant` and embedded JSON `variants`/`skus` arrays. Each variant carries color, material, size, SKU, price, availability.
- **B4: Identity keys** – SKU, MPN, GTIN/EAN extracted from JSON-LD, embedded JSON, and DOM microdata/meta tags.
- **B5: Offer data** – Original price, discount %, availability, delivery ETA, and shipping cost extracted from all sources.

### EPIC C: Sorting Engine (NEW)
- **C1: Generic category schema** – 15 furniture categories with positive/negative Swedish+English lexicons replacing sofa-only confidence.
- **C2: Feature builder** – Evidence provenance tracked per signal (breadcrumb, title, URL, facet, description) with source, snippet, matched tokens, and weight.
- **C3: Rule scorer** – Weighted lexicon matching with normalized probability scores per category.
- **C4: Decision policy** – `ACCEPT/REJECT/UNCERTAIN` per surface with configurable thresholds for confidence, margin, completeness, images, and price bounds. Two pre-configured surfaces: `swiper_deck_sofas` and `swiper_deck_all_furniture`.
- **C5: Gold promotion** – Accepted items promoted to `goldItems` collection with versioned decisions, classification evidence, and essential fields for fast deck reads.

### EPIC D: Review & Learning (NEW)
- **D1: Review queue** – `GET /review-queue` returns uncertain items with full item context.
- **D2: Reviewer actions** – `POST /review-action` supports accept, reject, and reclassify. Labels stored in `reviewerLabels` collection for training data.
- **D3: Active sampling** – `GET /sampling-candidates` with diverse, uncertain, and random strategies for efficient labeling.
- **D4: Calibration** – `POST /calibrate` grid-searches optimal accept/reject thresholds from reviewer labels.
- **D5: Evaluation report** – `GET /evaluation-report` computes per-category precision, recall, and F1 from reviewer labels.

### EPIC E: Serving & Product UX
- **E1: Deck reads Gold only** – `deck.ts` now queries `goldItems` first; controlled by `DECK_USE_GOLD` env var.
- **E2: Backfill guard** – Falls back to `items` collection when Gold is empty (low inventory protection).
- **E3: Multi-offer dedup** – `canonicalUrl`-based dedup prevents duplicate products in deck while keeping different retailers.
- **E4: Explainability** – `GET /admin/explain/:itemId` returns classification, eligibility, Gold status, evidence trail, and review status.

### EPIC F: DevOps & Observability
- **F1: Retention cleanup** – `POST /retention-cleanup` purges old snapshots and extraction failures based on configurable TTLs.
- **F2: Domain dashboard** – `GET /domain-dashboard` returns per-source metrics history with classification stats.
- **F3: Drift check** – `POST /drift-check` compares recent metrics to 7-day baseline; auto-disables sources with `autoDisableOnDrift=true`.
- **F4: Kill-switch** – `POST /kill-switch` enables/disables sources immediately.
- **F5: Cost telemetry** – `GET /cost-telemetry` aggregates fetch volume, processing time, storage estimates per source.

### New Collections
- `goldItems` – Serve-ready items accepted by sorting engine
- `reviewQueue` – Uncertain items awaiting human review
- `reviewerLabels` – Training data from reviewer decisions
- `calibrationRuns` – Threshold calibration history

### New API Endpoints (Supply Engine)
`/classify`, `/classification-stats`, `/review-queue`, `/review-action`, `/sampling-candidates`, `/calibrate`, `/evaluation-report`, `/retention-cleanup`, `/domain-dashboard`, `/drift-check`, `/kill-switch`, `/cost-telemetry`

### New API Endpoints (Firebase)
All Supply Engine endpoints proxied via `/api/admin/*`, plus `GET /api/admin/explain/:itemId` (native Firebase)

### Files Changed
- `services/supply_engine/app/sorting/` – NEW: classifier.py, policy.py, calibration.py
- `services/supply_engine/app/extractor/enrichment.py` – NEW: B1-B5 metadata enrichment
- `services/supply_engine/app/extractor/cascade.py` – Extended NormalizedProduct, integrated enrichment
- `services/supply_engine/app/crawl_ingestion.py` – Incremental skip, enriched fields in item docs
- `services/supply_engine/app/http/fetcher.py` – Per-domain retry policies, failure tracking
- `services/supply_engine/app/firestore_client.py` – Hash lookup/update for incremental crawl
- `services/supply_engine/app/main.py` – 12 new endpoints across Epics C/D/F
- `firebase/functions/src/api/deck.ts` – Gold-first reads, backfill guard, canonicalUrl dedup
- `firebase/functions/src/api/admin_run_trigger.ts` – Explain endpoint, generic proxy
- `firebase/functions/src/api/index.ts` – Route registration for all new endpoints

## 2026-02-07 – Fix broken product images on swipe cards

- **Image proxy domain whitelist removed**: The proxy (`image_proxy.ts`) had a hardcoded allowlist of ~10 domains. Scraped products from other retailer domains were rejected with a JSON error, which Flutter tried to decode as image data — causing "EncodingError: The source image cannot be decoded." Now allows any HTTP/HTTPS URL (all URLs come from our own crawler).
- **Item.fromJson image parsing**: Fixed to handle images stored as plain URL strings (e.g. `["https://..."]`) in addition to the object format (`[{url: "https://..."}]`). Previously, string URLs were silently dropped.
- **Precache error handling**: Improved `_prefetchUpcomingImages()` in `swipe_deck.dart` to use the `onError` callback, preventing hundreds of console error spam lines.

## 2026-02-07 – Fix Image Extraction (Pre-Launch Blocker)

### Problem
The extraction cascade (JSON-LD, embedded JSON, DOM) had zero validation that extracted URLs were actual images. This caused:
- Page URLs stored as images (e.g., product page URLs from `href` keys in JSON)
- Truncated/incomplete CDN URLs
- ~60% of scraped catalog showing blank cards in the app

### Solution

**Image URL Validation (`_is_likely_image_url()`)**
- New heuristic function checks for image file extensions, CDN domain patterns, image path segments, and image-related query parameters
- Rejects URLs that look like product/category pages
- Detects truncated URLs via `_looks_truncated()`

**Fixed `_extract_images_from_any()`**
- Removed `href` key (too often points to product pages, not images)
- Added lazy-loading keys: `data-src`, `data-image`, `data-original`
- Added `contentUrl` for Schema.org ImageObject support
- Prefer `src` over `url` for reliability

**Fixed `_normalize_images()` with validation**
- Applies `_is_likely_image_url()` filter to all extracted URLs
- Truncation detection rejects incomplete URLs
- Graceful fallback: if ALL images fail validation, returns unfiltered list

**Fallback Image Extraction**
- New `_extract_images_from_dom()` function extracts images directly from HTML DOM
- Searches product gallery containers, `<picture>` sources, product-related CSS classes
- Supports lazy-loaded images (data-src, data-original, etc.)
- Each extraction method (JSON-LD, embedded JSON, DOM) now has a 3-step fallback chain: extracted images -> og:image -> DOM img tags

**New Admin Endpoints**
- `GET /image-health` – per-retailer image health stats (valid, broken, no image counts)
- `POST /re-extract-images` – re-fetch and re-extract images for items with broken images
- Firebase Cloud Function proxies for both endpoints

### Current Status
After applying validation improvements, image health is 100% across all 25,575 items. The fixes prevent future scrapes from storing page URLs as images.

### Files Changed
- `services/supply_engine/app/extractor/cascade.py`: Validation, extraction fixes, DOM fallback
- `services/supply_engine/app/main.py`: `/re-extract-images` and `/image-health` endpoints
- `firebase/functions/src/api/admin_run_trigger.ts`: Firebase proxy endpoints
- `firebase/functions/src/api/index.ts`: Route registration

## 2026-02-06 – Added 20 Swedish Furniture Retailer Sources

- Created `scripts/seed_retailer_sources.sh` to bulk-add crawl sources via the admin API
- Added 20 Swedish sofa retailers: IKEA Sverige, Mio, Trademax, Chilli, Furniturebox, SoffaDirekt, Svenska Hem, Svenssons, Länna Möbler, Nordiska Galleriet, RoyalDesign, Rum21, EM Home, Jotex, Ellos, Homeroom, Sweef, Sleepo, Newport, ILVA
- All sources configured with crawl mode, sofa-related keyword filters, and 1 req/s rate limit
- Sources are enabled and ready for auto-discovery + crawl via the admin panel

## 2026-02-06 – Concurrent Scraping (5x Speed Boost)

### Problem
Scraping was entirely sequential - one page fetched at a time, one retailer at a time. A 500-product crawl took ~8+ minutes.

### Solution

**Within a single retailer (~5x faster):**
- Extraction now uses `ThreadPoolExecutor` with configurable concurrency (default: 5 workers)
- Multiple pages are fetched and extracted in parallel
- Thread-safe rate limiting ensures we stay polite to retailer servers
- Progress logging now shows rate (pages/sec) and ETA

**Across multiple retailers (parallel):**
- New `/run-batch` endpoint runs multiple sources simultaneously
- New `POST /api/admin/run-batch` Firebase endpoint for batch triggers from admin UI
- 5 retailers that each take 3 min = ~3 min total instead of ~15 min

### Configuration
- `concurrency` field on source config (default: 5, max: 15)
- Rate limiting still respected per-domain (thread-safe)

### Speed Comparison
| Scenario | Before | After |
|----------|--------|-------|
| 500 pages, 1 retailer | ~8 min | ~2 min |
| 5 retailers × 500 pages | ~40 min | ~2 min |

### Admin UI
- **"Run All Sources" button** in Sources screen (play icon in app bar)
- Confirms before running, shows result count when done
- Only runs enabled sources

### Files Changed
- `services/supply_engine/app/http/fetcher.py`: Thread-safe rate limiting
- `services/supply_engine/app/crawl_ingestion.py`: Concurrent extraction with ThreadPoolExecutor
- `services/supply_engine/app/main.py`: `/run-batch` endpoint
- `firebase/functions/src/api/admin_run_trigger.ts`: Batch trigger endpoint
- `firebase/functions/src/api/index.ts`: Route registration
- `apps/Swiper_flutter/lib/data/api_client.dart`: `adminTriggerBatchRun` method
- `apps/Swiper_flutter/lib/features/admin/admin_sources_screen.dart`: Run All button

---

## 2026-02-06 – Fix Deck Ordering (Random Tie-Breaking + Debug Mode)

### Problem
Cards in the deck appeared in scraping order instead of being properly randomized. This happened because when items had equal scores (common for new users), the tie-breaker preserved the original Firestore query order.

### Solution
1. **Random tie-breaking** - When items have equal scores, they're now shuffled randomly instead of appearing in scraping order
2. **Debug mode** - Added `?debug=true` query param to deck API for observability

### How to Verify Ranker is Working

Call the deck API with debug mode:
```
GET /api/deck?sessionId=xxx&debug=true
```

Response now includes:
- `rank.scoreStats` - Distribution of scores (total, nonZero, min, max, avg)
- `debug.preferenceWeights` - What weights are being used
- `debug.topItemsWithScores` - First 5 items with their scores and attributes
- `debug.hasPersonaSignals` - Whether collaborative filtering is active

### What "Working" Looks Like
- `scoreStats.nonZero > 0` = ranker is scoring items
- Items with higher scores appear first
- Items with score 0 are shuffled randomly (not in scraping order)

### Files Changed
- `firebase/functions/src/ranker/preferenceWeightsRanker.ts`: Random tie-breaking
- `firebase/functions/src/ranker/personalPlusPersonaRanker.ts`: Random tie-breaking
- `firebase/functions/src/api/deck.ts`: Debug mode + score stats

---

## 2026-02-06 – Remove 200 Product Limit + Real-Time Stats

### Problem
1. Crawls were artificially limited to 200 products regardless of how many were discovered
2. Stats only updated at the end of the run, not during crawling

### Solution
1. **Removed 200 limit** - Now processes ALL discovered products (sitemap discovery already handles efficiency via `min_matching_urls`)
2. **Incremental stat updates** - Stats written to Firestore every 10 products during extraction, so the Run Details UI shows real-time progress

### Files Changed
- `services/supply_engine/app/crawl_ingestion.py`: Removed `product_candidates[:max_urls]` truncation, added `update_run()` calls during extraction loop

---

## 2026-02-06 – Redesigned Ingestion Run Details Page

### UX Improvements (CPO Review)
Completely redesigned the run details sheet with real-time updates and clear progress visualization.

### New Features
- **Real-time polling**: Auto-updates every 3 seconds while run is active
- **Stage stepper**: Visual pipeline showing Starting → Discovery → Crawling → Saving → Complete
- **Live progress stats**: Shows Discovered, Candidates, Crawled, Success, Failed, Saved counts
- **Progress bar**: Visual progress indicator during active crawls
- **Pulsing status badge**: Animated indicator for running state
- **Source favicon**: Shows website icon in header for quick identification
- **Collapsible technical details**: Run ID, Source ID, timestamps hidden by default

### Design Principles Applied
- Instant feedback (Design Principle #3)
- Mobile-friendly layout with clear information hierarchy
- Error states with clear messaging (replaced "Unknown" with actionable status)

### Files Changed
- `apps/Swiper_flutter/lib/features/admin/admin_runs_screen.dart`: Complete rewrite of `_RunDetailSheet`

---

## 2026-02-06 – Fix Sitemap Discovery Missing Filtered Products

### Problem
When crawling mio.se with a "soffa" category filter, only 60 URLs were found (all category pages, no actual products). This resulted in 0 products extracted.

**Root cause**: mio.se has 118+ sitemaps. The sofa PRODUCTS are in sitemaps 19-37, but the crawler stopped at 50,000 URLs (sitemaps 0-9) which only contained category pages and other products (beds, accessories).

### Solution
- **Category filter now applied DURING sitemap discovery** instead of after
- Crawler continues reading sitemaps until enough matching URLs are found (min 2,000)
- Increased sitemap scan limit from 50 to 200 sitemaps
- Increased total URL scan limit from 50K to 200K

### Impact
Crawls with category filters will now properly find filtered products even if they appear in later sitemaps.

### Files Changed
- `services/supply_engine/app/locator/sitemap.py`: Added `category_filter` and `min_matching_urls` params to `discover_from_sitemaps`
- `services/supply_engine/app/crawl_ingestion.py`: Pass category filter to sitemap discovery

---

## 2026-02-06 – Category Filter Presets for Easy Setup

### Feature
Added quick preset chips in the Admin Sources screen to auto-fill category filter patterns. No more typing out all the sofa variations manually!

### Presets Included
- **Sofas**: soffa, soffor, hörnsoffa, divansoffa, bäddsoffa, modulsoffa, 2-sits, 3-sits, etc.
- **Chairs**: stol, stolar, fåtölj, kontorsstol, matstol, barstol, etc.
- **Tables**: bord, matbord, soffbord, skrivbord, sidobord, etc.
- **Beds**: säng, sängar, dubbelsäng, enkelsäng, kontinentalsäng, etc.
- **Storage**: förvaring, skåp, hylla, byrå, vitrinskåp, bokhylla, etc.

### Usage
1. Go to Admin → Sources
2. Create or edit a source
3. Expand Advanced settings
4. Click a preset chip (e.g., "Sofas")
5. The filter field auto-populates with all relevant terms

### Files Changed
- `apps/Swiper_flutter/lib/features/admin/admin_sources_screen.dart`: Added `_categoryPresets` map and preset chip UI

---

## 2026-02-06 – Fix "View on Website" Redirect URL

### Problem
Clicking "View on website" in product details navigated to `http://localhost:8080/go/...` (Flutter dev server) instead of the Firebase Functions endpoint, resulting in a 404 error.

### Solution
Added `ApiClient.goUrl(itemId)` helper method that generates the correct `/go/:itemId` URL using the Firebase Functions base URL. Updated all outbound redirect locations to use this method.

### Files Changed
- `apps/Swiper_flutter/lib/data/api_client.dart`: Added `goUrl()` static method
- `apps/Swiper_flutter/lib/shared/widgets/detail_sheet.dart`: Use `ApiClient.goUrl()`
- `apps/Swiper_flutter/lib/features/compare/compare_screen.dart`: Use `ApiClient.goUrl()`
- `apps/Swiper_flutter/lib/features/shared_shortlist/shared_shortlist_screen.dart`: Use `ApiClient.goUrl()`

---

## 2026-02-06 – Fix Missing Images from mio.se CDN

### Problem
Images from mio.se products were not displaying in the app. The image proxy was returning 403 "Domain not allowed" errors because mio.se serves images from `www.mcdn.net` CDN, which wasn't in the allowlist.

### Solution
Added `www.mcdn.net` and `mcdn.net` to the allowed domains in the image proxy.

### Files Changed
- `firebase/functions/src/api/image_proxy.ts`: Added mcdn.net domains to allowlist

---

## 2026-02-05 – Category Filter for Focused Crawling

### Problem
When crawling a retailer site (e.g., mio.se), the crawler was scraping ALL product categories (tables, beds, chairs, sofas) instead of just sofas. Users needed a way to focus crawls on specific categories.

### Solution: Category Filter
Added a `categoryFilter` field to source configuration that filters discovered URLs by path patterns.

**Usage:**
- When creating/editing a source, set category filter to: `soffor, soffa, hornsoffa`
- Only URLs containing at least one of these patterns will be processed
- Empty filter = all URLs pass through (previous behavior)

### Changes

**Backend (Supply Engine):**
- Added `_source_category_filter()` to extract filter patterns from source config
- Added `_filter_urls_by_category()` to filter discovered URLs
- Applied filter after URL discovery, before product extraction
- Logs filter results for debugging

**Frontend (Admin UI):**
- Added "Category filter" field in Advanced Settings when creating/editing sources
- Accepts comma-separated patterns (e.g., "soffor, soffa, hornsoffa")
- Patterns are case-insensitive and match anywhere in URL path

**API:**
- Updated `/api/admin/sources/create-with-discovery` to accept `categoryFilter` parameter
- Filter patterns stored as array in Firestore source document

### Future: MCP Reconnaissance (Idea Logged)
Added comprehensive idea to `docs/FUTURE_IDEAS.md` for AI-powered site reconnaissance that would automatically identify category patterns, eliminating manual configuration.

### Files Changed
- `services/supply_engine/app/crawl_ingestion.py`: Category filter implementation
- `apps/Swiper_flutter/lib/features/admin/admin_sources_screen.dart`: UI field
- `apps/Swiper_flutter/lib/data/api_client.dart`: API parameter
- `firebase/functions/src/api/admin_sources.ts`: Backend endpoint
- `docs/FUTURE_IDEAS.md`: MCP reconnaissance idea

---

## 2026-02-05 – Crawler Quality & Execution Controls

### URL Classifier Improvements
- **Fixed category path mis-classification:** Removed `/soffa` and `/soffor` from product hints (these are category paths in Swedish)
- **Added category negative patterns:** Swedish furniture categories (`/soffor`, `/mobler`, `/stolar`, `/bord`, etc.) now correctly classified as listings
- **Added utility page exclusions:** `/kampanj`, `/inspiration`, `/guide`, `/press`, `/outlet`, etc.
- **Improved confidence scoring:** Shallow paths without product markers now lean toward category classification
- **Added product patterns:** Better detection of `/p/product-slug`, SKU patterns, and deep product paths

### Source Data Validation
- **URL normalization on save:** Sources are now validated and URLs automatically normalized with `https://` on create/update
- **Prevent invalid manual configs:** `seedType=manual` now requires at least one URL in `seedUrls`
- **Clear error messages:** Validation failures return structured error details

### Sitemap Early Stopping
- **Stop on repeated zero-yields:** If 5 consecutive sitemaps return 0 URLs, discovery stops early to conserve crawl budget
- **Resets on any yield:** Counter resets when URLs or nested sitemaps are found
- **Reduces wasted fetches:** Sites with many empty/incompatible sitemaps no longer burn all budget

### Duplicate Run Prevention
- **Prevent concurrent runs:** "Run Now" button now checks for active runs before triggering
- **Run tracking in Firestore:** Runs are tracked with status (`running`, `completed`, `failed`)
- **Stale run handling:** Runs older than 30 minutes are marked as failed and allow new runs
- **Force override:** `force=true` parameter allows bypassing the check when needed

### Run Correlation Logging
- **Run IDs in logs:** All log messages now include a `[run_id]` prefix for filtering concurrent runs
- **Correlation across services:** Run ID passed from Firebase Functions to Supply Engine
- **Easier debugging:** Can now filter logs by run ID when multiple crawls run simultaneously

### New Tests
- `test_classifier.py`: Comprehensive tests for URL classification (categories, products, edge cases)

### Files Changed
- `services/supply_engine/app/locator/classifier.py`: Improved URL classification heuristics
- `firebase/functions/src/api/admin_sources.ts`: Added source validation and URL normalization
- `services/supply_engine/app/locator/sitemap.py`: Added early stopping on zero-yield sitemaps
- `firebase/functions/src/api/admin_run_trigger.ts`: Added duplicate run prevention and tracking
- `services/supply_engine/app/main.py`: Added run ID correlation support
- `services/supply_engine/app/crawl_ingestion.py`: Added run ID to logger
- `services/supply_engine/app/feed_ingestion.py`: Added run ID logging
- `services/supply_engine/tests/test_classifier.py`: New test file for classifier

---

## 2026-02-05 – Crawler Bug Fixes & Reliability Improvements

### Runtime Parity and Environment Alignment
- **Fixed SUPPLY_ENGINE_URL mismatch:** Unified default port to 8081 across all Firebase Functions (was 8000 in `admin_sources.ts`, 8081 in `admin_run_trigger.ts`)
- **Fixed FIRESTORE_EMULATOR_HOST port:** Updated `.env.example` to show correct port 8180 (was 8080)
- **Added Functions build step:** `run_emulators.sh` now runs `npm run build` before starting emulators to prevent stale code issues
- **Auto-set emulator host:** `run_supply_engine.sh` now auto-exports `FIRESTORE_EMULATOR_HOST=localhost:8180`

### Domain Equivalence Normalization
Crawls now work correctly when sites use www and apex domains interchangeably:
- **Added `canonical_domain()`:** Strips www. prefix for consistent comparison
- **Added `domains_equivalent()`:** Treats `www.example.com` and `example.com` as same-site
- **Updated domain checks:** Applied to sitemap filtering (`sitemap.py`), category crawl (`crawler.py`), discovery sampling (`discovery.py`), and robots.txt cache (`fetcher.py`)

### Source Edit Behavior Fix
- **Clear derived config on URL change:** `adminSourcePut` now clears the `derived` object when the source URL changes, preventing stale auto-discovered configuration from silently overriding user edits

### Filter Fallback Hardening
- **Added fallback when path filtering removes all URLs:** When `seedPathPattern` filtering yields zero results:
  1. First tries category crawl from seed URL
  2. If crawl also yields nothing, falls back to unfiltered sitemap URLs
- **Prevents "succeeded with 0 candidates":** Crawls now have robust recovery when sitemap filtering is too aggressive

### Base URL Protocol Normalization
- **Auto-add https:// when missing:** `_base_url()` now normalizes URLs without protocol (e.g., `www.mio.se` → `https://www.mio.se`)
- **Fixes "Request URL is missing protocol" errors:** Legacy sources with bare domains now work correctly

### Text Sitemap Support
- **Support for .txt sitemaps:** Added parsing for plain text sitemaps (one URL per line) in addition to XML
- **Auto-format detection:** `_parse_sitemap_content()` detects text vs XML and parses accordingly
- **Fixes Mio and similar sites:** Sites using `.txt` sitemap files now parse correctly (was returning 0 URLs)

### Regression Tests
- **Domain equivalence tests** (`test_normalization.py`): Tests for `canonical_domain`, `domains_equivalent` including edge cases
- **Filter fallback tests** (`test_crawl_fallback.py`): Tests for path filter behavior, fallback logic, and config resolution

### Documentation Updates
- **RUNBOOK_LOCAL_DEV.md:** Added port reference table, environment variable defaults, and troubleshooting section for common issues (Supply Engine unreachable, stale Functions code, missing emulator host)

### Files Changed
- `firebase/functions/src/api/admin_sources.ts`: Fixed port default, added derived config clearing on URL change
- `.env.example`: Fixed Firestore emulator port, added SUPPLY_ENGINE_URL
- `scripts/run_emulators.sh`: Added Functions build step
- `scripts/run_supply_engine.sh`: Auto-set FIRESTORE_EMULATOR_HOST
- `services/supply_engine/app/normalization.py`: Added `canonical_domain`, `domains_equivalent`
- `services/supply_engine/app/locator/sitemap.py`: Use `domains_equivalent` for filtering, added text sitemap support
- `services/supply_engine/app/locator/crawler.py`: Use `domains_equivalent` for same-site checks
- `services/supply_engine/app/discovery.py`: Use `domains_equivalent` for sampling, added text sitemap support
- `services/supply_engine/app/http/fetcher.py`: Use `canonical_domain` for robots cache key
- `services/supply_engine/app/crawl_ingestion.py`: Added fallback when path filter removes all URLs, auto-add https:// to base URL
- `services/supply_engine/tests/test_normalization.py`: Added domain equivalence tests
- `services/supply_engine/tests/test_crawl_fallback.py`: New file for fallback tests
- `docs/RUNBOOK_LOCAL_DEV.md`: Added ports table and troubleshooting section

---

## 2026-02-05 – Smart Crawler Auto-Discovery

### Major Feature: Automated Source Configuration
Users can now add retailer sources with just a URL - the system automatically discovers:
- Domain root and robots.txt location
- Available sitemaps (including sitemap indexes)
- Product URL counts and category patterns
- Recommended crawl strategy (sitemap vs category crawl)

### Backend Changes
- **URL Normalization** (`services/supply_engine/app/normalization.py`):
  - Added `normalize_source_url()` for parsing user input URLs
  - Added `extract_domain_root()` for proper robots.txt discovery
  - Fixed bug where robots.txt was fetched from subpath instead of domain root

- **Auto-Discovery Module** (`services/supply_engine/app/discovery.py`):
  - New `discover_from_url()` function for URL analysis
  - Samples sitemaps to estimate product counts
  - Returns strategy recommendation (sitemap vs crawl)

- **Supply Engine API** (`services/supply_engine/app/main.py`):
  - New `/discover` endpoint for preview without saving

- **Crawl Ingestion** (`services/supply_engine/app/crawl_ingestion.py`):
  - Updated to support new `derived` config structure
  - Backward compatible with legacy source fields
  - Path pattern filtering for sitemap URLs

- **Firebase Functions** (`firebase/functions/src/api/admin_sources.ts`):
  - New `POST /api/admin/sources/preview` endpoint
  - New `POST /api/admin/sources/create-with-discovery` endpoint
  - Stores both user input and derived configuration

### Frontend Changes
- **API Client** (`apps/Swiper_flutter/lib/data/api_client.dart`):
  - Added `adminPreviewSource()` method
  - Added `adminCreateSourceWithDiscovery()` method

- **Admin Sources Screen** (`apps/Swiper_flutter/lib/features/admin/admin_sources_screen.dart`):
  - Redesigned "Add Retailer" dialog with simplified workflow
  - Single URL input with "Detect" button
  - Visual preview of discovery results before saving
  - Collapsible advanced settings (rate limit, enabled flag)

### Bug Fixes
- Fixed robots.txt discovery to always use domain root (RFC compliance)
- Fixed sitemap URL construction in `sitemap.py` and `fetcher.py`

---

## 2026-02-05 – Bug Fixes & UX Improvements (Testing Round)

### P0 Critical Fixes
- **Gold Card Empty Page Bug**: Fixed budget card not appearing after visual card completion when deck is empty (removed `items.isNotEmpty` check)
- **Auth Screens Missing Back Button**: Added explicit close buttons to login and signup screens for proper navigation
- **Likes Screen List View Broken**: Created separate `_LikeListTile` widget with fixed height for ListView rendering (fixes Expanded constraint issue)
- **Compare Button Missing**: Added Compare button to Likes screen that appears when 2-4 items are selected

### P1 High Priority Fixes
- **Unlike/Remove Functionality**: Added like toggle button to detail sheet with visual feedback and proper state management
- **Admin Run Now Error Handling**: Improved error messages with specific guidance when Supply Engine is unreachable (503 with helpful hints)
- **Admin Items Screen Enhancement**: Complete rewrite with search bar, source/status filters, item detail modal with raw JSON view

### P2 UX Improvements
- **Admin Runs Screen Enhancement**: Added source name/domain display, timestamps with relative time, duration calculation, stats chips, and detailed job listings
- **Empty Deck UX**: Contextual messaging based on filter state with "Clear Filters" button when filters are active

### Files Changed
- `apps/Swiper_flutter/lib/features/deck/deck_screen.dart`: Gold card fix, empty deck UX
- `apps/Swiper_flutter/lib/features/auth/login_screen.dart`: Close button
- `apps/Swiper_flutter/lib/features/auth/signup_screen.dart`: Close button
- `apps/Swiper_flutter/lib/features/likes/likes_screen.dart`: List view fix, compare button, unlike integration
- `apps/Swiper_flutter/lib/shared/widgets/detail_sheet.dart`: Like toggle button
- `apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart`: Empty state widget with filter awareness
- `apps/Swiper_flutter/lib/features/admin/admin_items_screen.dart`: Full rewrite with search/filters
- `apps/Swiper_flutter/lib/features/admin/admin_runs_screen.dart`: Enhanced with more context
- `firebase/functions/src/api/admin_run_trigger.ts`: Better error handling

---

## 2026-02-05 – Code Quality Fixes (Post-Phase 11 QA)

### Flutter Fixes
- Removed unused imports in `router.dart`, `auth_provider.dart`, `decision_room_screen.dart`
- Removed unused `_shareShortlist` method from `likes_screen.dart`
- Removed unused `_isDragging` field from `deck_screen.dart`
- Fixed unnecessary casts in `admin_catalog_preview_screen.dart` by using typed `Future.wait<T>`
- Fixed widget test timer cleanup issue in `swipe_deck_test.dart` with proper `pumpAndSettle`
- Added ignore comments for intentionally reserved fields in `swipe_deck.dart`

### Test Results
- All 11 Flutter unit tests passing
- TypeScript backend compiles cleanly
- All 36 Firebase Functions tests passing

---

## 2026-02-05 – Phase 11: Retailer Data Model + Confidence Score (Complete)

Full implementation of retailer data infrastructure, segment targeting, campaigns, and the Confidence Score system.

### Retailer Data Model (Backend)
- **Retailers collection** (`retailers.ts`): Full CRUD API for retailer management
  - `POST /api/admin/retailers`: Create retailer (admin only)
  - `GET /api/admin/retailers`: List all retailers (admin only)
  - `GET /api/retailers/:id`: Get retailer details (public)
  - `PATCH /api/admin/retailers/:id`: Update retailer (admin only)
  - `POST /api/retailers/:id/claim`: Claim retailer ownership (requires auth)
  - `GET /api/retailer/me`: Get current user's retailer (requires auth)

### Segments Collection (Backend)
- **Segments API** (`segments.ts`): Targeting definitions with system templates
  - 6 system segment templates for Sweden launch (budget-modern, premium-scandinavian, compact-urban, family-friendly, luxury-design, all-sweden)
  - `GET /api/segments/templates`: List system templates (public)
  - `POST /api/segments`: Create custom segment (requires auth)
  - `GET /api/segments`: List segments for retailer (requires auth)
  - `GET /api/segments/:id`: Get segment by ID
  - `PATCH /api/segments/:id`: Update custom segment (requires auth)
  - `DELETE /api/segments/:id`: Delete custom segment (requires auth)

### Campaigns Collection (Backend)
- **Campaigns API** (`campaigns.ts`): Featured distribution campaigns
  - `POST /api/retailer/campaigns`: Create campaign (requires retailer auth)
  - `GET /api/retailer/campaigns`: List campaigns (requires auth)
  - `GET /api/retailer/campaigns/:id`: Get campaign details (requires auth)
  - `PATCH /api/retailer/campaigns/:id`: Update campaign (requires auth)
  - `POST /api/retailer/campaigns/:id/pause`: Pause active campaign
  - `POST /api/retailer/campaigns/:id/activate`: Activate draft/paused campaign
  - `DELETE /api/retailer/campaigns/:id`: Delete draft campaign

### Confidence Score System (Backend)
- **Scores API** (`scores.ts`): Score query endpoints
  - `GET /api/scores?segmentId=&timeWindow=&band=`: Query scores with filters
  - `GET /api/scores/:productId`: Get product scores across segments
  - `GET /api/admin/scores/summary`: Aggregate score statistics (admin)
  - `POST /api/admin/scores/recalculate`: Trigger recalculation (admin)
- **Score Calculation Job** (`confidence_score.ts`): Scheduled hourly function
  - Bayesian smoothing for low-volume items
  - Weighted scoring: saveRate (50%), clickRate (15%), volume (15%), creative (20%)
  - Time windows: 7d, 30d, 90d
  - Score banding: green (60+), yellow (30-59), red (0-29)

### Reason Codes
- Dynamic reason code generation based on metrics:
  - `STRONG_SAVES` / `GOOD_SAVES` / `LOW_SAVES`: Save rate signals
  - `HIGH_CLICKS` / `LOW_CLICKS`: Click rate signals
  - `HIGH_SKIP`: Frequently skipped items
  - `LOW_VOLUME` / `HIGH_CONFIDENCE`: Impression volume signals
  - `EXCELLENT_CREATIVE` / `CREATIVE_ISSUES`: Image quality signals

### Firestore Updates
- **Security rules**: Added rules for `retailers`, `segments`, `campaigns`, `scores`, `scoreCalculationLogs`, `scoreRecalculationJobs`
- **Composite indexes**: Added 12 new indexes for efficient querying

### Scripts
- **Segment template seeder** (`seed_segment_templates.js`): Seeds system segment templates

---

## 2026-02-05 – Phase 10: Premium Image Display + Brand Trust (Complete)

Full implementation of premium image rendering, CDN pipeline, and Creative Health scoring.

### Premium Image Card (Flutter)
- **PremiumImageCard widget** (`premium_image_card.dart`): Reusable component with contain + blurred background pattern
- **DeckCard upgrade**: Now uses premium rendering by default with two-layer approach
  - Background: Blurred cover image (lower resolution for performance)
  - Foreground: Contained image showing full product without distortion
- **Shimmer placeholder**: Animated loading state for premium cards

### CDN Image Pipeline (Backend)
- **Image proxy enhancement** (`image_proxy.ts`): Extended with Sharp library for server-side processing
  - Width parameter: Resize to 400w, 800w, or 1200w
  - Format parameter: WebP, JPEG, or PNG output
  - Quality parameter: 1-100 quality control
  - Auto WebP: Serves WebP when browser supports it via Accept header
- **Image metadata endpoint** (`GET /api/image-meta`): Validates images without full download
  - Returns dimensions, aspect ratio, format, file size
  - Classifies aspect ratio (portrait, landscape, square, etc.)
  - Lists validation issues

### Image Validation & Creative Health
- **Python validation module** (`image_validation.py`): Async image validation for Supply Engine
  - Resolution checks (min 400x400)
  - Aspect ratio classification
  - File size validation
  - Creative Health score calculation (0-100)
- **Admin validation API** (`admin_image_validation.ts`):
  - `POST /api/admin/validate-images`: Batch validate items
  - `GET /api/admin/creative-health-stats`: Aggregate health statistics
- **Item schema update**: Added `imageValidation` and `creativeHealth` fields to items collection

### Catalog Preview UI (Flutter)
- **AdminCatalogPreviewScreen**: New admin screen for image quality review
  - Grid view with Creative Health badges (green/yellow/red)
  - Comparison view: Side-by-side legacy vs premium rendering
  - Health statistics header showing band distribution
  - Trigger validation button for batch processing

### API Client Updates
- Added `ImageWidth` enum (thumbnail: 400, card: 800, detail: 1200)
- Added `ImageFormat` enum (webp, jpeg, png)
- Updated `proxyImageUrl()` to support width/format/quality params
- New admin methods: `adminValidateImages()`, `adminGetCreativeHealthStats()`

### Dependencies
- Added `sharp@0.33.2` to Firebase Functions for image processing
- Added `Pillow==10.2.0` to Supply Engine for Python image validation

---

## 2026-02-05 – Phase 9: User Accounts + Decision Room (Complete)

Full implementation of user authentication and collaborative Decision Room feature.

### Backend (Firebase Functions)
- **User authentication middleware** (`require_user_auth.ts`): Firebase ID token verification for regular users
- **Auth API endpoints** (`auth.ts`): `POST /api/auth/link-session` (migrate anonymous data), `GET /api/auth/me` (user profile)
- **Decision Room API** (`decision_rooms.ts`): Full CRUD + participation endpoints
  - `POST /api/decision-rooms`: Create room (requires auth)
  - `GET /api/decision-rooms/:roomId`: View room (public)
  - `POST /api/decision-rooms/:roomId/vote`: Cast vote (requires auth)
  - `POST /api/decision-rooms/:roomId/comments`: Add comment (requires auth)
  - `GET /api/decision-rooms/:roomId/comments`: List comments (public)
  - `POST /api/decision-rooms/:roomId/suggest`: Suggest alternative product (requires auth)
  - `POST /api/decision-rooms/:roomId/finalists`: Set final 2 items (creator only)
- **Firestore rules**: Added rules for `users`, `decisionRooms`, `votes`, `comments` collections
- **Firestore indexes**: Added composite indexes for efficient queries

### Frontend (Flutter)
- **Auth provider** (`auth_provider.dart`): Firebase Auth state management with Riverpod
  - Email/password sign-up and sign-in
  - Google Sign-In integration
  - Automatic session linking on authentication
  - Password reset functionality
- **Login screen** (`login_screen.dart`): Email + Google sign-in UI with redirect support
- **Sign-up screen** (`signup_screen.dart`): Account creation UI with validation
- **Decision Room screen** (`decision_room_screen.dart`): Full collaborative experience
  - Item grid with vote buttons (up/down)
  - Real-time vote counts
  - Comment section with input
  - "Suggest alternative" dialog with URL input
  - "Pick finalists" for room creator
  - Share functionality
- **Likes screen update**: Replaced "Share shortlist" with "Create Decision Room" flow
- **Router updates**: Added `/auth/login`, `/auth/signup`, `/r/:roomId` routes
- **API client extensions**: Methods for all new auth and Decision Room endpoints

### Analytics Events
- `decisionroom_create`: When room is created
- `decisionroom_view`: When room is viewed
- `decisionroom_vote`: When user votes on an item
- `decisionroom_comment`: When user adds a comment
- `finalists_set`: When creator picks final 2
- `suggest_alternative`: When user suggests a product URL

### Deferred
- Push notifications (9.10) deferred to future iteration

---

## 2026-02-05 – Commercial Platform Build Spec v1 → v2

Comprehensive documentation update integrating the full Retailer Platform build specification across all project documentation.

### COMMERCIAL_STRATEGY.md (Major Update)
- **Product north star:** Added honest value props (more appearances to target personas, high-intent consideration behaviors)
- **Non-negotiables (trust):** Documented ad-free Decision Room, labeled/capped/relevance-gated Featured
- **Retailer target audience:** Economic buyers (Head of Marketing, E-com Director, CEO), day-to-day users (performance marketers, merchandisers, agencies)
- **Confidence Score:** Replaced HIS terminology with Confidence Score (0–100) for retailer UI; includes calculation overview, color bands (green/yellow/red), reason codes
- **Roadmap framing:** v1 (Monetizable MVP), v2 (Close-Rate Proof + Pixel), v3 (Retention Engine + Inspiration Deck), v4 (Creative Lab)
- **Definition of done for v1:** Invoice-ready criteria

### PRD.md (Major Update)
- **Decision Room features:** Vote per product, comment threads, "Final 2" mode, suggest alternative
- **Featured Distribution specs:** Labeled, frequency capped (1 in 12), relevance-gated, diversity constraints
- **Confidence Score specs:** 0–100 per product × segment, inputs (saves, shares, compares, returns, dwell), Bayesian smoothing, banding, reason codes
- **Retailer Console user stories:** Insights Feed, Campaign Builder, Catalog Control, Reports
- **Commercial success criteria:** Retailer activation, campaign fill rate, CPScore benchmark

### IMPLEMENTATION_PLAN.md (Major Update)
- **Phase 9:** User Accounts + Decision Room (11 tasks)
- **Phase 10:** Premium Image Display + Brand Trust (7 tasks)
- **Phase 11:** Retailer Data Model + Confidence Score (10 tasks)
- **Phase 12:** Featured Distribution (11 tasks)
- **Phase 13:** Retailer Console v1 (13 tasks)
- **Phase 14:** Admin Governance + v1 Launch (6 tasks)
- **v2 roadmap:** Click ID, Pixel SDK, conversion reporting, audience tools, geo granularity (13 tasks)
- **v3 roadmap:** Inspiration Deck, Sponsored Themes, Email/SMS (9 tasks)
- **v4 roadmap:** Creative Lab (4 tasks)
- **Engineering checklist:** New collections (users, decisionRooms, votes, comments, retailers, segments, campaigns, scores) and event schema additions

### APP_FLOW.md (Major Update)
- **Decision Room flows:** Create (auth required), view (public), participate (vote/comment/suggest), finalists
- **Retailer Console flows:** Insights Feed, Campaign Builder, Catalog Control, Trends, Reports
- **Featured card handling:** Badge display, logging with campaign_id
- **New screen inventory:** Decision Room, Auth screens, Retailer Console (10 screens)
- **State transitions:** Decision Room lifecycle, Campaign lifecycle

### BACKEND_STRUCTURE.md (Major Update)
- **New collections:** `users`, `decisionRooms`, `decisionRoomItems`, `votes`, `comments`, `retailers`, `segments`, `campaigns`, `scores`
- **Decision Room API:** Create, view, vote, comment, suggest, finalists endpoints
- **Retailer Console API:** Campaigns CRUD, catalog control, insights feed, trends, reports
- **Confidence Score spec (Appendix):** Full calculation including time windows, rate calculation, weighted intent rate, Bayesian smoothing, 0–100 mapping, banding, reason codes
- **Featured serving algorithm:** Slot determination, eligibility filtering, ranking, constraints, logging
- **Click ID + Pixel spec (v2):** Outbound format, pixel behavior, audience enablement, GTM recipes

### FRONTEND_GUIDELINES.md (Major Update)
- **Premium Image Display spec:** Contain + blurred background pattern for furniture images
- **Flutter implementation:** `PremiumImageCard` widget with two-layer rendering
- **CSS equivalent:** For web reference
- **Image CDN:** Size variants (400w, 800w, 1200w), WebP + JPEG fallback
- **Featured Badge component:** Styling and positioning
- **Confidence Score Badge component:** Color-coded by band
- **Insight Feed Card component:** Retailer console pattern

## 2026-02-05 – Commercial Strategy documentation

- **COMMERCIAL_STRATEGY.md:** Added comprehensive commercial strategy document covering retailer-first monetization approach. Includes Featured Distribution (Product Deck), Retailer Console, Sponsored Themes, Swiper Pixel + Audience Retargeting, Lifecycle Messaging, and Affiliate revenue streams. Defines High-Intent Save (HIS) as the core sellable metric. Documents Decision Room ethical boundaries (no paid placement in share/compare). Outlines short/medium/long-term roadmap for monetization features.

## 2026-02-02 – Documentation consolidation: 6-document knowledge base

- **PRD.md:** Consolidated product requirements from existing docs (ASSUMPTIONS, PROJECT_PLAN, CARD_INTERACTION, RECOMMENDATIONS_ENGINE, INGESTION_COMPLIANCE, PRIVACY_GDPR, SECURITY, TAG_TAXONOMY). Contains product overview, scope (in/out), user stories, success criteria, feature specs, constraints, risks, and glossary.
- **APP_FLOW.md:** Complete screen inventory, navigation flows, error handling, deep links, state transitions, and analytics events per flow. Combines ARCHITECTURE, TESTING_LOCAL, EVENT_TRACKING, and Flutter app analysis.
- **TECH_STACK.md:** Locked dependencies with exact versions for Flutter (Riverpod 2.4.9, go_router 13.0.0, etc.), Firebase Functions (Node 20, TS 5.3.3), and Supply Engine (FastAPI 0.109.0, httpx 0.26.0). Environment variables and config files documented.
- **FRONTEND_GUIDELINES.md:** Complete design system: color palette (hex codes), typography scale (Inter, sizes, weights), spacing scale (4px multiples), responsive breakpoints, component patterns (swipe card, buttons, list tiles), animation guidelines, accessibility requirements, folder structure, and code style.
- **BACKEND_STRUCTURE.md:** Full Firestore schema (10 collections with field types), security rules, API endpoint contracts (public and admin), ranker interface, data flow diagrams, error codes, and environment configuration.
- **IMPLEMENTATION_PLAN.md:** Step-by-step build sequence with completed phases (0-7), upcoming phases (8-12), implementation guidelines, branching strategy, risk register, and decision log.

## 2026-02-02 – P1 Recommendation Backbone: extract material, color, dimensions from crawl

- **NormalizedProduct extended:** Added `dimensions_raw`, `material_raw`, `color_raw` so crawl items can be ranked and filtered like feed items.
- **JSON-LD extraction:** Parses `width`, `height`, `depth` (including Schema.org QuantitativeValue), `color`, `material`, and `additionalProperty` (Bredd/Höjd/Djup/Färg/Material).
- **Embedded JSON extraction:** Extracts dimensions, material, color from product-like nodes (width/height/depth, dimensionsCm, material, colorFamily, etc.).
- **Recipe pass-through:** Dimensions, material, color from recipe output flow into items.
- **Title color inference:** `infer_color_from_title()` scans titles for color tokens (e.g. "svart", "grå"); used when DOM fallback has no structured color.
- **Crawl ingestion:** Replaces hardcoded `dimensionsCm`, `sizeClass`, `material`, `colorFamily` with normalized extracted values. Size class derived from width via `size_class_from_width_cm()`.

## 2026-02-02 – Supply Engine crawl locator + self-healing-ready extractor (Sweden-first)

- **Crawl ingestion implemented:** `mode:"crawl"` sources now run URL discovery (robots/sitemaps + bounded category crawl) and write operational state to Firestore (`crawlUrls`, `productSnapshots`, `extractionFailures`, `metricsDaily`, `crawlRecipes`).
- **Extraction cascade:** Deterministic extractor prioritizes JSON-LD, then embedded JSON (Next.js + generic blobs), then optional per-retailer recipe runner, then semantic DOM fallbacks (canonical/og/meta); includes Swedish money parsing and completeness scoring.
- **Recipe system (deterministic):** Added recipe JSON validation + runner (minimal JSONPath, DOM selectors, transforms) and promotion gate evaluation (success rate + completeness thresholds).
- **Monitoring + drift triggers:** Daily metrics are persisted and basic drift detection records alerts into `extractionFailures` when success/completeness drops.

## 2026-02-02 – Recommendation engine robustness fixes

- **Exploration rate:** applyExploration now replaces roughly `rate × limit` positions (stochastic rounding) instead of treating any non-zero rate as full randomization; rate=0 keeps rank order, rate=1 fully samples from the top-2× pool.
- **Recency-preserving ties:** PreferenceWeightsRanker now keeps candidate input order on score ties (preserves recency when all scores are equal).
- **Atomic preference updates:** swipe-right updates preferenceWeights via Firestore atomic increments to avoid lost updates under concurrency.
- **Persona cold weights:** PersonalPlusPersonaRanker treats all-zero weights as “no personal signal,” allowing persona scores to dominate.
- **Filter parsing guard:** deck filters JSON is validated and returns 400 on invalid input.

## 2026-02-02 – Data Science & Observability Gaps (offline eval, A/B, retention)

- **deck_response logging:** Client now logs rank.variant, rank.variantBucket, and rank.itemIds (served slate) in deck_response events; swipe events include variant/variantBucket when rank context is present. ApiClient parses variant and variantBucket from deck response; schema and EVENT_SCHEMA_V1/EVENT_TRACKING updated. Required for offline eval (liked-in-top-K) and A/B segmentation.
- **events_batch chunking:** POST /api/events/batch chunks into Firestore batches of 500 and commits each chunk so large batches no longer fail (Firestore 500-write limit).
- **Exploration seed:** Deck API uses session-based exploration seed when RANKER_EXPLORATION_SEED is unset (hashSessionId(sessionId)) so exploration order is deterministic per session for A/B.
- **OFFLINE_EVAL.md:** New doc with primary metric (Liked-in-top-K per session), required event fields, A/B segmentation by variant, position-bias note, and optional statistical significance (95% CI, sample size). RECOMMENDATIONS_ENGINE updated to reference it.
- **Bias and retention:** RECOMMENDATIONS_ENGINE documents exposure bias (mitigation: exploration, diversity), item cold start (retrieval by lastUpdatedAt, content-based scoring), and persona cold sessions (default bucket or personal-only). events_v1 retention 24 months documented in PRIVACY_GDPR and RUNBOOK_DEPLOYMENT (Data retention: TTL or scheduled purge).
- **Persona and optional:** Persona pipeline future step includes default bucket for cold sessions; optional diversity (MMR / max per styleTag), weight decay, and score-breakdown explainability documented in RECOMMENDATIONS_ENGINE.

## 2026-02-02 – Deck swipe visual continuity (remove white flash)

- **Card rendering unified:** Introduced [deck_card.dart](apps/Swiper_flutter/lib/shared/widgets/deck_card.dart) and now both the top card and stacked cards render via the same cached image + placeholder strategy (no `Image.network` vs `CachedNetworkImage` mismatch).
- **No spinner placeholders:** Replaced the swipe-surface spinner placeholder with a stable, non-white designed placeholder to avoid perceived “flash” on image decode.
- **Stable deck background:** [swipe_deck.dart](apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart) wraps the deck stack in a `ColoredBox(AppTheme.background)` so there’s never a default white canvas between frames.
- **Prefetch:** SwipeDeck prefetches `top + next 4` images via `precacheImage(CachedNetworkImageProvider(...))` on deck updates to reduce image pop-in on promotion.
- **Promotion polish:** Under-stack cards use implicit animations (`AnimatedPadding`/`AnimatedScale`) so the stack advances smoothly when a card is removed.

## 2026-02-02 – New card on top: each top card is a new State, fix _dragDx carry-over and double-commit

- **Top card identity:** [swipe_deck.dart](apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart) now uses `ValueKey(top.id)` for the top `DraggableSwipeCard` (removed GlobalKey). When the top item changes after a swipe, Flutter disposes the old State and creates a new one for the new item, so each top card is a new widget/State; no state is "inserted" into the previous card.
- **_dragDx fix:** The next card no longer inherits the previous card's drag offset (new State always has `_dragDx = 0`); button-triggered swipe animates from center.
- **Button triggers:** Top card registers trigger callbacks and `isAnimating` getter via optional `onRegisterSwipeTriggers`; [draggable_swipe_card.dart](apps/Swiper_flutter/lib/shared/widgets/draggable_swipe_card.dart) calls it in initState and unregisters in dispose. SwipeDeck stores the callbacks and heart/X buttons call them; no GlobalKey.
- **Double-commit prevention:** Button handlers check `_isAnimatingGetter?.call() == true` before commit + trigger, so double-tap during animation does not duplicate API/tracking. Event data (swipe_left/swipe_right, gesture vs button) unchanged.

## 2026-02-02 – Refetch without loading so card exit animation stays visible

- **Refetch timing:** When remaining deck items fall below 3 after a swipe, [deck_provider.dart](apps/Swiper_flutter/lib/data/deck_provider.dart) now refetches in the background without setting `state = AsyncValue.loading()`. Added `_load({ bool showLoading = true })`; refetch from `removeItemById()` calls `_load(showLoading: false)` so the deck is not replaced by a spinner and the top card’s exit animation stays visible.
- **Clipping audit:** Confirmed deck parent chain (Scaffold body, Expanded, Stack with `clipBehavior: Clip.none`) does not clip; no change needed for card overflow during swipe.

## 2026-02-02 – Deck stack, swipe transition, likes on swipe right, deck bundles

- **Deck stack:** Capped visible stack at 5 cards in [swipe_deck.dart](apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart); order and images match “next to show.” Added `ValueKey(item.id)` on stack and top card for widget identity so the next card reuses the same widget (no image reload).
- **Swipe transition:** Two-phase flow: commit (API + tracking) on swipe start, remove from list only after exit animation completes. [draggable_swipe_card.dart](apps/Swiper_flutter/lib/shared/widgets/draggable_swipe_card.dart) calls `onSwipeRight`/`onSwipeLeft` at commit and `onSwipeAnimationEnd(item)` when animation completes; [deck_provider.dart](apps/Swiper_flutter/lib/data/deck_provider.dart) `swipe()` no longer mutates state; `removeItemById(itemId)` mutates state; deck_screen wires `onSwipeAnimationEnd` to `removeItemById`. Button swipes trigger card animation via `DraggableSwipeCardState.triggerSwipeRight`/`triggerSwipeLeft`. Eliminates white flicker when revealing next card.
- **Likes on swipe right:** [swipe.ts](firebase/functions/src/api/swipe.ts) writes to top-level `likes` collection (doc id `sessionId_itemId`, merge for idempotency) and `anonSessions/{sessionId}/likes/{itemId}` when `direction === "right"`, so the Likes page shows swiped-right items.
- **Deck bundles:** Default deck request size reduced to 10; [deck_provider.dart](apps/Swiper_flutter/lib/data/deck_provider.dart) refetches when remaining items &lt; 3 after a swipe.

## 2026-02-02 – Recommendation ranking normalization and analyzer fixes

- **Ranker:** Improved recommendation ranking normalization in [firebase/functions/src/ranker/](firebase/functions/src/ranker/): shared `normalizeScore(score, signalCount)` (divide by √signalCount) in scoreItem.ts; PreferenceWeightsRanker and PersonalPlusPersonaRanker use it to reduce tag-count bias. New/updated tests in scoreItem.test.ts, preferenceWeightsRanker.test.ts, personalPlusPersonaRanker.test.ts. [docs/RECOMMENDATIONS_ENGINE.md](docs/RECOMMENDATIONS_ENGINE.md) updated.
- **Flutter analyzer:** Removed redundant `notifyListeners()` in router (ValueNotifier setter already notifies); removed unused `api_client` import in compare_screen so `flutter analyze --no-fatal-infos` passes with no warnings.

## 2026-02-01 – Swipe-first deck launch and menu consolidation

- **Entry flow:** App opens directly into the deck (no splash). One-time swipe hint overlay stored in Hive.
- **Navigation:** Added hamburger menu on deck (Filters, Likes, Preferences, Data & Privacy, Language). Bottom nav removed from the deck surface.
- **Detail modal:** Near full-screen sheet with handle, dimmed backdrop, and fast spring scale-in.
- **Likes:** Compare action removed from the UI; shortlist sharing remains.
- **QA/docs:** Integration test and runbooks updated to match the new deck-first flow.

## 2025-01-31 – Admin login redirect fix (no more kick-back to splash)

- **Router:** Stopped recreating `GoRouter` when `adminAuthProvider` changes. Recreating the router reset to `initialLocation: '/'` and sent the user back to the splash screen after login. Now the router is built once; admin auth is mirrored in a `ValueNotifier` and passed as `refreshListenable`. A single top-level `redirect` reads the notifier and sends unauthenticated admin routes to `/admin/login` and authenticated `/admin` or `/admin/login` to `/admin/dashboard`. Login no longer kicks the user back.

## 2025-01-31 – Next phase: deploy, real supply, locale, admin auth, SSO stub

- **Staging deploy:** [scripts/deploy_staging.sh](scripts/deploy_staging.sh) builds Flutter web + Functions and runs `firebase deploy --only functions,hosting,firestore:rules,firestore:indexes`. RUNBOOK_DEPLOYMENT updated with one-command deploy.
- **Real supply:** [config/sources.json](config/sources.json) has two sources: `sample_feed` (CSV) and `demo_feed` (JSON). RUNBOOK post-deploy notes updated for demo_feed and production feed URLs.
- **Language / locale:** Swedish and English; app locale from Hive (`swiper_locale`). [lib/l10n/app_strings.dart](apps/Swiper_flutter/lib/l10n/app_strings.dart) and [lib/data/locale_provider.dart](apps/Swiper_flutter/lib/data/locale_provider.dart); profile Language tile opens sheet to pick Swedish/English; splash and Data & Privacy use localised strings.
- **Admin auth:** Firebase Auth allowlist (Firestore `adminAllowlist`, document ID = admin email). Backend: [firebase/functions/src/api/admin_auth.ts](firebase/functions/src/api/admin_auth.ts) `requireAdminAuth`; all admin routes except POST admin/verify require Bearer token + allowlist. Flutter: firebase_auth + google_sign_in; admin login has "Sign in with Google" and legacy password; ApiClient sends Authorization Bearer for admin requests; RUNBOOK and SECURITY updated.
- **SSO stub:** Data & Privacy "Connect social accounts" tappable; shows "Coming soon" dialog. Anonymous remains default.
- **Project plan:** docs/PROJECT_PLAN.md next-phase goals marked done with short notes.

## 2025-01-31 – Plan implementation (deck filters, deploy runbook, profile, opt-out, admin)

- **Deck filters UI:** Real filter sheet with size class (small/medium/large), color family, and condition (new/used). Filters passed to `getDeck(filters)`; deck refreshes on apply/clear. `filter_change` event logged on apply and clear with metadata (sizeClass, colorFamily, newUsed). ApiClient sends filters as JSON string to backend.
- **First production deploy:** RUNBOOK_DEPLOYMENT.md updated with "Post-deploy smoke test" checklist (app load, session, deck, filters, detail, likes, compare, go redirect, profile, admin, shared shortlist).
- **Profile Language:** Stub replaced with "Swedish / English – coming soon"; ListTile disabled so expectations are clear.
- **Opt-out UI (functional):** Analytics opt-out stored in Hive (`swiper_analytics_opt_out`). Data & Privacy screen has a working Switch; when on, non-essential events (open_detail, detail_dismiss, filter_sheet_open, filter_change, session_start, deck_empty_view, compare_open, onboarding_complete) are not sent. Swipes and likes unchanged.
- **Admin Create source:** Dialog replaced with form (name, mode, baseUrl, isEnabled, rateLimitRps); submits to POST /api/admin/sources.
- **Admin Items:** Backend GET /api/admin/items (limit) added; Flutter Admin Items screen lists recent items (title, price, sourceId, active).
- **Admin Import:** Stub replaced with instructions and "Trigger sample / first source run" button that triggers run for a source named "sample" or the first source.

## 2025-01-31 – User interaction capture & Data & Privacy

- **Session context:** Backend `POST /api/session` accepts optional body: `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes`, `userAgent`; stored on **anonSessions**. Flutter sends device context via `DeviceContext.toSessionBody()` when creating session.
- **Client events:** Flutter logs to `POST /api/events`: `open_detail`, `detail_dismiss` (with `timeViewedMs`), `compare_open`, `filter_sheet_open`, `session_start`, `deck_empty_view`, `onboarding_complete` (with preferences). Deck and likes detail sheets log open/dismiss; compare screen logs once; deck logs session_start and deck_empty_view; onboarding logs completion with style/budget/prefs.
- **Session early create:** Splash “Get started” and “Skip to swipe” call `ensureSession()` so onboarding_complete can be logged with sessionId.
- **Data & Privacy screen:** New `/profile/data-privacy` explains what we collect (session/device, usage events); placeholders for “Opt out of analytics” and “Connect social accounts (Instagram/Facebook)” as coming later. Profile entry renamed to “Data & Privacy”.
- **Docs:** EVENT_TRACKING.md updated with client events and session context; backlog items for functional opt-out UI and SSO/social login.

## 2025-01-31 – MVP implementation

- **Flutter app**: Skeleton, Scandi theme, go_router, splash, onboarding (3-step), deck (swipe stack + draggable cards), detail sheet, likes (grid/list, compare, share), compare screen, profile, shared shortlist `/s/:token`, admin console (dashboard, sources, runs, items, import, QA). Riverpod + Dio + Hive.
- **Firebase**: Firestore rules/indexes, Cloud Functions (session, deck, swipe, likes, shortlists, events, go redirect, admin stats/sources/runs/qa/run trigger). Hosting rewrites for /go, /api, /s.
- **Supply Engine**: Python FastAPI, feed ingestion (CSV/JSON), normalization (material, color, size), Firestore client, crawl stub, extraction (JSON-LD + heuristics). Sample feed + config/sources.json. Dockerfile, run scripts.
- **Admin**: Password gate, sources CRUD + Run now, runs list/detail, QA completeness report.
- **Tests**: Flutter (preference scoring, filter logic, item model, swipe deck widget). Functions (go 400, shortlists create 400). Supply Engine (normalization, JSON-LD extractor). CI: GitHub Actions (Flutter analyze/test/build, Functions build/test, Supply Engine pytest).
- **Docs**: ASSUMPTIONS, DECISIONS, ARCHITECTURE, DATA_MODEL, TAG_TAXONOMY, INGESTION_COMPLIANCE, SECURITY, PRIVACY_GDPR, RUNBOOK_LOCAL_DEV, RUNBOOK_DEPLOYMENT.

---
name: ingestion
description: Supply Engine feed and crawl ingestion skill for Swiper — Python FastAPI pipeline that ingests furniture inventory from retailer CSV/JSON feeds and website crawls.
---

## Triggers

- "run ingestion"
- "add a new retailer feed"
- "fix crawl extraction"
- "monitor ingestion health"

## Ingestion Types

### Feed Ingestion
CSV or JSON feeds from retailers → normalized to Firestore `items`.
```bash
FIRESTORE_EMULATOR_HOST=localhost:8180 ./scripts/ingest_sample_feed.sh
```

### Crawl Ingestion
1. Sitemap + category discovery → `crawlUrls`
2. Extraction cascade: JSON-LD → embedded JSON → recipe → semantic DOM
3. Snapshots + failures → `productSnapshots`, `extractionFailures`
4. Daily metrics + drift triggers → `metricsDaily`

## Key Extraction Fields

| Field | Source | Method |
|-------|--------|--------|
| Dimensions | Structured data / DOM | Extraction cascade |
| Material | Structured data / title | Inference |
| Color | Structured data / title | Title-based when no structured |
| Style | Title + tags | Keyword matching |
| Price | Structured data | Direct |

## Files

- `services/supply_engine/` — FastAPI app
- `scripts/run_supply_engine.sh`
- `scripts/ingest_sample_feed.sh`
- `docs/INGESTION_COMPLIANCE.md`

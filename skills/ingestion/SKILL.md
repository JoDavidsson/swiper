# Supply Engine — Feed & Crawl Ingestion

Reusable skill for the Python FastAPI supply engine that ingests furniture inventory.

## Triggers

- "run ingestion"
- "add a new retailer feed"
- "fix crawl extraction"
- "monitor ingestion health"

## Ingestion Types

### Feed Ingestion
CSV or JSON feeds from retailers — normalized to Firestore `items` collection.
- Run: `FIRESTORE_EMULATOR_HOST=localhost:8180 ./scripts/ingest_sample_feed.sh`
- Or: `POST /admin/run` via Firebase Functions

### Crawl Ingestion
URL discovery + extraction cascade:
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
| Images | Structured data / DOM | URL extraction |

## Monitoring

- Daily metrics: success/completeness rates, strategy usage
- Drift detection: `metricsDaily` triggers alerts
- Failures: `extractionFailures` collection

## Files

- `services/supply_engine/` — FastAPI app
- `scripts/run_supply_engine.sh`
- `scripts/ingest_sample_feed.sh`
- `docs/ARCHITECTURE.md` (crawl state)
- `docs/INGESTION_COMPLIANCE.md`

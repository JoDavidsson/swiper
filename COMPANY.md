# Swiper — Company Manifest

> **Agent Companies** compliant package for the Swiper product org.
> Swiper is a mobile-first furniture discovery app (Tinder for sofas, Sweden-first).

## Metadata

| Field | Value |
|-------|-------|
| **name** | Swiper |
| **version** | 1.0.0 |
| **license** | Proprietary |
| **website** | https://github.com/JoDavidsson/swiper |
| **status** | Active |

## Goals

- Build and ship the Swiper mobile-first furniture discovery PWA (Flutter + Firebase)
- Ingest, normalize, and surface furniture inventory from retailer feeds and crawls
- Run autonomous recommendation research campaigns to improve the ranker
- Maintain feature distribution and retailer console operations
- Ensure data privacy (GDPR) and security compliance

## Structure

```
Swiper org
├── CEO          — Product vision, prioritization, stakeholder alignment
├── Flutter Dev  — Mobile app (iOS/Android/Web PWA), Firebase integration
├── Backend Dev  — Firebase Cloud Functions, Firestore, REST API
├── Supply Engineer — Python FastAPI, feed/crawl ingestion, data pipeline
├── Recommendation Dev — Ranker, preference learning, offline evaluation
└── QA Engineer  — Test automation, stress testing, observability
```

## Stack

| Layer | Technology |
|-------|-----------|
| App | Flutter (PWA — iOS, Android, Web) |
| Backend | Firebase Hosting + Cloud Functions + Firestore |
| Supply Engine | Python / FastAPI |
| Ingestion | Feed CSV/JSON + Crawl (sitemap + category) |
| Ranker | Collaborative filtering + preference weights |

## Operates In

- Repo: `JoDavidsson/swiper` (GitHub)
- Branching: feature branches → PR → main
- CI: Playwright tests, eval scripts, stress tests
- Runbooks: `docs/RUNBOOK_LOCAL_DEV.md`, `docs/RUNBOOK_DEPLOYMENT.md`

## Telemetry & Privacy

- Analytics: opt-out supported, V1 event schema, batched
- GDPR: data export/delete stubs in place
- No AR preview, no marketplace payments, no user-submitted links

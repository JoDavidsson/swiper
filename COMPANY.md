---
name: Swiper
description: Mobile-first furniture discovery app — Tinder for sofas, Sweden-first. Users swipe right on sofas they like to build a personalized shortlist. Retailers pay for featured distribution to targeted personas, tracked via Confidence Score.
slug: swiper
schema: agentcompanies/v1
version: 1.0.0
license: Proprietary
website: https://github.com/JoDavidsson/swiper
status: Active
goals:
  - Build and ship the Swiper mobile-first furniture discovery PWA (Flutter + Firebase)
  - Ingest, normalize, and surface furniture inventory from retailer feeds and crawls
  - Run autonomous recommendation research campaigns to improve the ranker
  - Maintain Featured Distribution and retailer console operations
  - Ensure data privacy (GDPR) and security compliance
---

## Company Overview

**Swiper** is a mobile-first furniture discovery app that lets users find their perfect sofa through a Tinder-like swipe experience. Users swipe right on sofas they like, left to dismiss, and build a personalized shortlist to share or compare.

**Commercial Layer:** Retailers pay for Featured Distribution to targeted user personas, tracked via Confidence Score — a unified metric representing high-intent consideration behavior.

## Product Stack

| Layer | Technology |
|-------|-----------|
| App | Flutter (iOS, Android, Web PWA) |
| Backend | Firebase Hosting + Cloud Functions + Firestore |
| Supply Engine | Python / FastAPI |
| Ingestion | Feed CSV/JSON + Crawl (sitemap + category) |
| Ranker | Collaborative filtering + preference weights |

## Org Structure

```
Swiper org
├── CEO          — Product vision, prioritization, stakeholder alignment
├── Flutter Dev  — Mobile app (iOS/Android/Web PWA), Firebase integration
├── Backend Dev  — Firebase Cloud Functions, Firestore, REST API
├── Supply Engineer — Python FastAPI, feed/crawl ingestion, data pipeline
├── Recommendation Dev — Ranker, preference learning, offline evaluation
└── QA Engineer  — Test automation, stress testing, observability
```

## Key Milestones

- [x] MVP Shipped — swipe deck, likes, compare, outbound redirect
- [x] Golden Card v2 — implemented, controlled rollout gates active
- [x] Phase 12 — Featured Distribution (controlled rollout)
- [ ] Decision Room v1 — vote, comment, shareable shortlists
- [ ] User Accounts — required for Decision Room, optional otherwise
- [ ] Retailer Console v1 — Insights Feed, Campaigns, Catalog, Trends, Reporting
- [ ] Confidence Score — per-product/segment intent metric (0–100)

## Compliance

- GDPR: data export/delete stubs in place
- Privacy: analytics opt-out, no AR, no marketplace payments
- Security: see `docs/SECURITY.md`, `docs/PRIVACY_GDPR.md`

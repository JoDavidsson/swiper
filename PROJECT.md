# Swiper — Project Definitions

## Project: Swiper App (MVP + Commercial v1)

### Overview

Swiper is a mobile-first furniture discovery PWA — Tinder for sofas, Sweden-first.

### Sub-projects

| Project | Owner | Description |
|---------|-------|-------------|
| Flutter App | Flutter Dev | iOS/Android/Web PWA, swipe deck, likes, compare, Decision Room |
| Firebase Backend | Backend Dev | Cloud Functions, Firestore, REST API, event tracking |
| Supply Engine | Supply Engineer | Python FastAPI, feed/crawl ingestion, item normalization |
| Ranker | Recommendation Dev | Preference weights, collaborative filtering, Featured Distribution |
| QA | QA Engineer | Test automation, stress testing, observability |

### Key Milestones

- [x] MVP Shipped — swipe deck, likes, compare, outbound redirect
- [x] Golden Card v2 — implemented, controlled rollout gates active
- [x] Phase 12 — Featured Distribution (controlled rollout)
- [ ] Decision Room v1 — vote, comment, shareable shortlists
- [ ] User Accounts — required for Decision Room, optional otherwise
- [ ] Retailer Console v1 — Insights Feed, Campaigns, Catalog, Trends, Reporting
- [ ] Confidence Score — per-product/segment intent metric (0–100)

### Stack

| Layer | Technology |
|-------|-----------|
| App | Flutter (iOS, Android, Web PWA) |
| Backend | Firebase Hosting + Cloud Functions + Firestore |
| Supply Engine | Python / FastAPI |
| Ingestion | Feed CSV/JSON + Crawl (sitemap + category) |
| Ranker | Collaborative filtering + preference weights |

### Compliance

- GDPR: data export/delete stubs in place
- Privacy: analytics opt-out, no AR, no marketplace payments
- Security: see `docs/SECURITY.md`, `docs/PRIVACY_GDPR.md`

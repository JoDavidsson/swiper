# Swiper – Implementation Plan

> **Last updated:** 2026-02-08  
> Step-by-step build sequence with dependencies and milestones.

---

## Current Status

**Phase:** Phase 13 (Retailer Console v1) In Progress + Phase 12/12a Implemented  
**Next Phase:** Complete Retailer Console core workflows (campaign, catalog, insights, reporting) and iterate from pilot feedback  
**Last Milestone:** Data quality sweep: 10 fixes shipped (image proxy domains, currency validation, zero-price gate, HTML stripping, description matching, image extraction heuristics, card layout, deck exhaustion fallback, rich spec extraction & display, recommendation engine signals)

---

## Completed Milestones

### Phase 0: Foundation ✅

| Step | Task | Status |
|------|------|--------|
| 0.1 | Project scaffolding (Flutter, Firebase, Python) | ✅ Done |
| 0.2 | Firebase project setup (Firestore, Functions, Hosting) | ✅ Done |
| 0.3 | Local development environment (emulators, scripts) | ✅ Done |
| 0.4 | CI/CD pipeline (GitHub Actions) | ✅ Done |
| 0.5 | Documentation structure | ✅ Done |

### Phase 1: Core Data Pipeline ✅

| Step | Task | Status |
|------|------|--------|
| 1.1 | Firestore schema design (`items`, `sessions`, `swipes`) | ✅ Done |
| 1.2 | Supply Engine scaffolding (FastAPI) | ✅ Done |
| 1.3 | Feed ingestion (CSV/JSON) | ✅ Done |
| 1.4 | Basic extraction cascade (JSON-LD, embedded JSON, DOM) | ✅ Done |
| 1.4b | Image extraction hardening (validation, fallbacks, DOM extraction) | ✅ Done |
| 1.5 | Normalization pipeline (price, images, URLs) | ✅ Done |
| 1.6 | Crawl ingestion endpoint | ✅ Done |
| 1.7 | Admin trigger endpoint | ✅ Done |

### Phase 2: Flutter App MVP ✅

| Step | Task | Status |
|------|------|--------|
| 2.1 | App architecture (Riverpod, go_router) | ✅ Done |
| 2.2 | Session management (anonymous, local persistence) | ✅ Done |
| 2.3 | Swipe deck UI (card stack, gestures) | ✅ Done |
| 2.4 | Deck loading from API | ✅ Done |
| 2.5 | Swipe recording (like/dislike) | ✅ Done |
| 2.6 | Likes list screen | ✅ Done |
| 2.7 | Outbound redirect (open retailer URL) | ✅ Done |
| 2.8 | Basic styling and theme | ✅ Done |

### Phase 3: Sharing & Social ✅

| Step | Task | Status |
|------|------|--------|
| 3.1 | Shortlist creation (select from likes) | ✅ Done |
| 3.2 | Shortlist API endpoints | ✅ Done |
| 3.3 | Share sheet integration | ✅ Done |
| 3.4 | Public shortlist view (deep link) | ✅ Done |
| 3.5 | Shortlist viewer screen | ✅ Done |

### Phase 4: Admin Panel ✅

| Step | Task | Status |
|------|------|--------|
| 4.1 | Admin authentication (Google Sign-In + allowlist) | ✅ Done |
| 4.2 | Admin routes and guards | ✅ Done |
| 4.3 | Items management screen | ✅ Done |
| 4.4 | Sources management screen | ✅ Done |
| 4.5 | Ingestion runs viewer | ✅ Done |
| 4.6 | Manual trigger UI | ✅ Done |
| 4.7 | QA diagnostics page | ✅ Done |
| 4.8 | Stats dashboard | ✅ Done |

### Phase 5: Analytics & Events ✅

| Step | Task | Status |
|------|------|--------|
| 5.1 | Event schema design (v1) | ✅ Done |
| 5.2 | Event tracking API endpoints | ✅ Done |
| 5.3 | Client-side event batching | ✅ Done |
| 5.4 | Analytics opt-out (GDPR) | ✅ Done |
| 5.5 | Daily metrics aggregation | ✅ Done |

### Phase 6: Recommendation Engine ✅

| Step | Task | Status |
|------|------|--------|
| 6.1 | Ranker interface design | ✅ Done |
| 6.2 | Preference weights ranker | ✅ Done |
| 6.3 | Style tag matching | ✅ Done |
| 6.4 | Exploration sampling | ✅ Done |
| 6.5 | Deck API integration | ✅ Done |
| 6.6 | Multi-queue candidate retrieval (promoted/catalog/preference/persona/long-tail/serendipity) | ✅ Done |
| 6.7 | Wider rank window + request-level rank metadata (`requestId`, `candidateCount`, `rankWindow`, `retrievalQueues`) | ✅ Done |
| 6.8 | Larger client deck batching (30 cards) + proactive refill threshold (12 cards) | ✅ Done |

### Phase 7: P1 Enhancements ✅

| Step | Task | Status |
|------|------|--------|
| 7.1 | Extended `NormalizedProduct` schema (dimensions, material, color) | ✅ Done |
| 7.2 | JSON-LD dimension/material/color extraction | ✅ Done |
| 7.3 | Schema.org `additionalProperty` parsing | ✅ Done |
| 7.4 | Embedded JSON extended extraction | ✅ Done |
| 7.5 | Color inference from title fallback | ✅ Done |
| 7.6 | Normalization functions (material, color family, size class) | ✅ Done |
| 7.7 | Crawl ingestion integration | ✅ Done |
| 7.8 | Unit tests for new extraction | ✅ Done |

---

### Phase 8: Improved Discovery ✅

| Step | Task | Status |
|------|------|--------|
| 8.1 | Progressive onboarding (gold card visual – pick 3 sofas) | ✅ Done |
| 8.2 | Progressive onboarding (gold card budget – slider) | ✅ Done |
| 8.3 | Gold card state management (Hive persistence) | ✅ Done |
| 8.4 | Gold card deck injection (after first right swipe) | ✅ Done |
| 8.5 | Gold card styling (distinct gold theme) | ✅ Done |
| 8.6 | Curated sofas API endpoint (GET /api/onboarding/curated-sofas) | ✅ Done |
| 8.7 | Curated sofas collection + seeder script | ✅ Done |
| 8.8 | Admin screen for curated sofas management | ✅ Done |
| 8.9 | Onboarding picks API (POST /api/onboarding/picks) | ✅ Done |
| 8.10 | Cold-start ranking (boost picked sofa attributes) | ✅ Done |
| 8.11 | Gold card analytics events (shown/complete/skip) | ✅ Done |
| 8.12 | Edit Preferences button in Profile | ✅ Done |
| 8.13 | Persona aggregation pipeline (scheduled function) | ✅ Done |
| 8.14 | PersonalPlusPersonaRanker (collaborative filtering) | ✅ Done |

---

## Commercial Product Roadmap

### v1 — Monetizable MVP (Sofas, Sweden)

**Definition of Done:** We can invoice retailers when we deliver all items below.

### Phase 9: User Accounts + Decision Room ✅

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 9.1 | User authentication (email/password + Google) | High | — | ✅ Done |
| 9.2 | Session migration (anonymous → authenticated) | High | 9.1 | ✅ Done |
| 9.3 | Decision Room data model (`decisionRooms`, `votes`, `comments`) | High | — | ✅ Done |
| 9.4 | Decision Room creation API (requires auth) | High | 9.1, 9.3 | ✅ Done |
| 9.5 | Decision Room view API (public) | High | 9.3 | ✅ Done |
| 9.6 | Decision Room participation API (vote/comment; requires auth) | High | 9.1, 9.3 | ✅ Done |
| 9.7 | Decision Room "suggest alternative" API | Medium | 9.3 | ✅ Done |
| 9.8 | Decision Room UI (Flutter) | High | 9.4–9.7 | ✅ Done |
| 9.9 | "Final 2" finalists mode | Medium | 9.8 | ✅ Done |
| 9.10 | Push notifications setup (basic) | Medium | 9.1 | ⏳ Deferred |
| 9.11 | Decision Room analytics events | Medium | 9.8 | ✅ Done |

### Phase 10: Premium Image Display + Brand Trust ✅

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 10.1 | Card image rendering (contain + blurred bg) | High | — | ✅ Done |
| 10.2 | CDN image pipeline setup | High | — | ✅ Done |
| 10.3 | Multi-size image variants (400w, 800w, 1200w) | High | 10.2 | ✅ Done |
| 10.4 | WebP + JPEG fallback generation | Medium | 10.2 | ✅ Done |
| 10.5 | Image validation (min resolution, aspect ratio, broken detection) | High | 10.2 | ✅ Done |
| 10.6 | Creative Health score calculation (basic) | Medium | 10.5 | ✅ Done |
| 10.7 | Retailer catalog preview UI | Medium | 10.1 | ✅ Done |

### Phase 11: Retailer Data Model + Confidence Score ✅

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 11.1 | `retailers` collection (claim + ownership) | High | — | ✅ Done |
| 11.2 | `segments` collection (targeting definitions) | High | — | ✅ Done |
| 11.3 | `campaigns` collection (featured campaigns) | High | 11.2 | ✅ Done |
| 11.4 | `scores` collection (Confidence Score per product × segment) | High | — | ✅ Done |
| 11.5 | Confidence Score calculation job (rolling 7-day) | High | 11.4 | ✅ Done |
| 11.6 | Score smoothing (Bayesian prior) | High | 11.5 | ✅ Done |
| 11.7 | Score banding (red/yellow/green) | High | 11.5 | ✅ Done |
| 11.8 | Reason code generation | Medium | 11.5 | ✅ Done |
| 11.9 | Score API endpoints | High | 11.4–11.8 | ✅ Done |
| 11.10 | "Low data" badge logic | Medium | 11.5 | ✅ Done |

### Phase 11b: Smart Crawler Auto-Discovery ✅

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 11b.1 | URL normalization functions | High | — | ✅ Done |
| 11b.2 | Fix robots.txt/sitemap domain root discovery | High | 11b.1 | ✅ Done |
| 11b.3 | Auto-discovery module (`discovery.py`) | High | 11b.1-2 | ✅ Done |
| 11b.4 | `/discover` preview endpoint | High | 11b.3 | ✅ Done |
| 11b.5 | Crawl ingestion derived config support | High | 11b.3 | ✅ Done |
| 11b.6 | Firebase preview/create-with-discovery endpoints | High | 11b.4 | ✅ Done |
| 11b.7 | Simplified admin source form with URL detection | High | 11b.6 | ✅ Done |

**Summary:** Single URL input → automatic discovery of domain, sitemaps, product counts, and strategy recommendation. Dramatically simplifies adding new retailer sources.

### Phase 11c: Crawler Bug Fixes ✅

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 11c.1 | Fix SUPPLY_ENGINE_URL port mismatch (8000→8081) | High | — | ✅ Done |
| 11c.2 | Fix FIRESTORE_EMULATOR_HOST port in .env.example | Medium | — | ✅ Done |
| 11c.3 | Add Functions build step to emulators script | High | — | ✅ Done |
| 11c.4 | Auto-set FIRESTORE_EMULATOR_HOST in supply engine script | Medium | — | ✅ Done |
| 11c.5 | Add `canonical_domain` and `domains_equivalent` functions | High | — | ✅ Done |
| 11c.6 | Update sitemap/crawler/discovery domain comparisons | High | 11c.5 | ✅ Done |
| 11c.7 | Clear derived config when source URL changes | High | — | ✅ Done |
| 11c.8 | Add fallback when path filter removes all URLs | High | — | ✅ Done |
| 11c.9 | Regression tests for domain equivalence and fallback | Medium | 11c.5-8 | ✅ Done |
| 11c.10 | Update RUNBOOK_LOCAL_DEV.md with troubleshooting | Medium | 11c.1-4 | ✅ Done |

**Summary:** Fixed runtime parity issues, domain equivalence (www vs apex), stale derived config, and filter fallback. Crawls now work reliably across various site configurations.

### Phase 11d: "Crawl Wide, Show Narrow" Pipeline ✅

| Step | Task | Status |
|------|------|--------|
| 11d.1 | A3: Incremental recrawl (html_hash skip logic) | ✅ Done |
| 11d.2 | A5: Per-domain retry/backoff policy | ✅ Done |
| 11d.3 | B1-B5: Metadata enrichment (breadcrumbs, facets, variants, identity, offers) | ✅ Done |
| 11d.4 | C1: Generic category schema (15 furniture categories, SE+EN lexicons) | ✅ Done |
| 11d.5 | C2: Feature builder with evidence provenance | ✅ Done |
| 11d.6 | C3: Rule scorer with taxonomy lexicons | ✅ Done |
| 11d.7 | C4: Decision policy (ACCEPT/REJECT/UNCERTAIN per surface) | ✅ Done |
| 11d.8 | C5: Gold promotion service (goldItems collection) | ✅ Done |
| 11d.9 | D1-D3: Review queue + active sampling | ✅ Done |
| 11d.10 | D4: Calibration job (threshold optimisation from labels) | ✅ Done |
| 11d.11 | D5: Evaluation report (precision/recall/F1 per category) | ✅ Done |
| 11d.12 | E1: Deck reads Gold collection first | ✅ Done |
| 11d.13 | E2: Backfill guard (fallback when Gold empty) | ✅ Done |
| 11d.14 | E3: Multi-offer dedup (canonicalUrl) | ✅ Done |
| 11d.15 | E4: Explainability endpoint (/admin/explain/:id) | ✅ Done |
| 11d.16 | F1-F5: DevOps (retention cleanup, dashboards, drift check, kill-switch, cost telemetry) | ✅ Done |

### Phase 11e: Embedded JS State Extraction ✅

| Step | Task | Status |
|------|------|--------|
| 11e.1 | Window state detection in signals.py (INITIAL_DATA, __INITIAL_STATE__, __NUXT__, __PRELOADED_STATE__) | ✅ Done |
| 11e.2 | Retailer-specific handlers: Chilli (INITIAL_DATA) and RoyalDesign (__INITIAL_STATE__) | ✅ Done |
| 11e.3 | Generic fallback handler for unknown state structures | ✅ Done |
| 11e.4 | Batch extraction function (multi-product from single page) | ✅ Done |
| 11e.5 | Phase 1.5 in crawl pipeline (category page batch extraction + dedup) | ✅ Done |
| 11e.6 | Live testing: Chilli (24 products) and RoyalDesign (31 products) at 100% completeness | ✅ Done |

### Phase 11f: Supply Engine Data Quality (Cursor Phase 15) ✅

| Step | Task | Status |
|------|------|--------|
| 11f.1 | DOM fallback expansion (description, dimensions, material, brand) | ✅ Done |
| 11f.2 | Completeness scoring update (field richness weighting) | ✅ Done |
| 11f.3 | Playwright browser fallback for JS-rendered pages | ✅ Done |
| 11f.4 | JS-render detector + fetch method telemetry (`http` vs `browser`) | ✅ Done |
| 11f.5 | Per-source `useBrowserFallback` config wiring | ✅ Done |
| 11f.6 | Item-level `extractionMeta` with missing field tracking | ✅ Done |
| 11f.7 | Low-quality stale-item refetch queue helper + optional pass | ✅ Done |
| 11f.8 | Daily quality telemetry (`descriptionRate`, `dimensionsRate`, `materialRate`, `browserFetchCount`) | ✅ Done |
| 11f.9 | Playwright page scrolling for lazy-loaded / infinite-scroll SPA category pages | ✅ Done |
| 11f.10 | Fix 6 failing sources: switch strategy from sitemap to crawl + enable browser fallback (Sleepo, Nordiska Galleriet, Homeroom, SoffaDirekt, Svenssons, Newport) | ✅ Done |

### Phase 12: Featured Distribution

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 12.1 | Campaign creation API | High | 11.3 | ✅ Done |
| 12.2 | Segment targeting (style + budget + size + geo) | High | 11.2 | ✅ Done |
| 12.3 | Product set selection (manual + recommended) | High | 12.1 | ✅ Done |
| 12.4 | Budget + schedule management | High | 12.1 | ✅ Done |
| 12.5 | Featured serving algorithm | High | 12.1–12.4 | ✅ Done |
| 12.6 | Relevance gate (match score threshold) | High | 12.5 | ✅ Done |
| 12.7 | Frequency cap enforcement (1 in 12) | High | 12.5 | ✅ Done |
| 12.8 | Diversity constraint (retailer repetition) | Medium | 12.5 | ✅ Done |
| 12.9 | "Featured" label in deck UI | High | 12.5 | ✅ Done |
| 12.10 | Campaign pacing (even daily spend) | Medium | 12.4 | ✅ Done |
| 12.11 | Featured impression logging | High | 12.5 | ✅ Done |

### Phase 12a: Golden Card v2 - Style Direction Rehaul

| Step | Task | Priority | Dependencies | Status |
|------|------|----------|--------------|--------|
| 12a.1 | UX concept signoff: hybrid 4-step flow (scene -> sofa vibe -> constraints -> reaffirmation) | High | — | ✅ Done |
| 12a.2 | Curate diverse scene/vibe asset sets with dedupe rules | High | 12a.1 | ✅ Done |
| 12a.3 | New onboarding API contract (`/api/onboarding/v2`) | High | 12a.1 | ✅ Done |
| 12a.4 | `onboardingProfiles` schema + index plan | High | 12a.3 | ✅ Done |
| 12a.5 | Deck cold-start contract update (`rank.onboardingProfile`) | High | 12a.3 | ✅ Done |
| 12a.6 | Diversity constraints for first slates (family dedupe + style distance) | High | 12a.5 | ✅ Done |
| 12a.7 | Flutter multi-step Golden flow route + state machine | High | 12a.1 | ✅ Done |
| 12a.8 | EN/SV copy migration to `app_strings` for all new labels/buttons | Medium | 12a.7 | ✅ Done |
| 12a.9 | Reaffirmation summary UI with adjust/start-over controls | High | 12a.5, 12a.7 | ✅ Done |
| 12a.10 | End-to-end event instrumentation (`gold_v2_*`) | High | 12a.3, 12a.7 | ✅ Done |
| 12a.11 | QA sweep (accessibility, perf, integration, rollout guardrails) | High | 12a.2-12a.10 | ✅ Done |
| 12a.12 | Progressive rollout (10% -> 50% -> 100%) with kill switch | High | 12a.11 | ⏳ In Progress (controls + kill switch shipped; live cohort expansion gated by telemetry validation) |

### Phase 13: Retailer Console v1

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 13.1 | Retailer authentication + onboarding | High | — |
| 13.2 | Console shell + navigation | High | 13.1 |
| 13.3 | Insights Feed UI (Instagram-style cards) | High | 13.2 |
| 13.4 | Insight card types (winners, needs help, trends, anomalies) | High | 11.5, 13.3 |
| 13.5 | Campaign Builder UI | High | 12.1, 13.2 |
| 13.6 | Segment template picker | Medium | 13.5 |
| 13.7 | Catalog Control UI (include/exclude/preview) | High | 10.7, 13.2 |
| 13.8 | Creative health warnings display | Medium | 10.6, 13.7 |
| 13.9 | Trends module (Sweden-wide; v2 adds granularity) | Medium | 13.2 |
| 13.10 | Reporting: spend, impressions, Confidence outcomes | High | 12.11, 13.2 |
| 13.11 | CPScore calculation + display | High | 13.10 |
| 13.12 | CSV export | Medium | 13.10 |
| 13.13 | Sharable report links (agency-friendly) | Medium | 13.10 |

### Phase 13 Status (2026-02-08 snapshot)

| Step | Status |
|------|--------|
| 13.1 | ✅ Done (auth-gated `/retailer` console + retailer claim onboarding UI) |
| 13.2 | ✅ Done (retailer console shell + 5-tab navigation in Flutter) |
| 13.3 | ✅ Done (insights feed UI cards) |
| 13.4 | ✅ Done (winners / needs help / trends / anomaly card types) |
| 13.5 | ✅ Done (campaign builder UI with create + activate/pause/recommend actions) |
| 13.6 | ✅ Done (segment template picker integrated in campaign composer) |
| 13.7 | ✅ Done (catalog control include/exclude UI + API) |
| 13.8 | ✅ Done (creative health warnings visible in catalog rows) |
| 13.9 | ⏳ In Progress (currently trend card in Insights; dedicated trends module pending) |
| 13.10 | ✅ Done (retailer reports API + console report view) |
| 13.11 | ✅ Done (CPScore computed and displayed in reports + dashboard cards) |
| 13.12 | ✅ Done (CSV export endpoint + in-app export action) |
| 13.13 | ✅ Done (shareable report link generation + retrieval endpoint + in-app share action) |

### Phase 14: Admin Governance + v1 Launch

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 14.1 | Admin governance panel (caps, thresholds, segment defs) | High | — |
| 14.2 | Featured frequency cap admin controls | High | 14.1 |
| 14.3 | Relevance threshold admin controls | High | 14.1 |
| 14.4 | Pacing parameter admin controls | Medium | 14.1 |
| 14.5 | Brand safety overrides | Medium | 14.1 |
| 14.6 | v1 launch checklist + smoke tests | High | All above |

---

### v2 — Close-Rate Proof + Bigger Budgets

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 15.1 | Click ID generation on outbound (`swp_click_id`) | High | — |
| 15.2 | Segment slug appending (`swp_seg`, `swp_score_band`) | High | — |
| 15.3 | Swiper Pixel SDK (JS snippet) | High | — |
| 15.4 | Pixel landing beacon (reads click_id, stores cookie) | High | 15.3 |
| 15.5 | Pixel event API (product_view, add_to_cart, purchase) | High | 15.3 |
| 15.6 | Pixel status checker in Console | Medium | 15.3 |
| 15.7 | Conversion reporting in Console | High | 15.5 |
| 15.8 | Audience cookie (`swp_seg`) for retailer GTM | Medium | 15.3 |
| 15.9 | Meta/Google custom event recipes | Medium | 15.3 |
| 15.10 | Geo granularity tiers (region/city/postcode) | Medium | 11.2 |
| 15.11 | Better pacing (bid-to-objective) | Medium | 12.10 |
| 15.12 | Per-user frequency + fatigue controls | Medium | 12.7 |
| 15.13 | Experiment framework (holdouts) | Low | — |

---

### v3 — Retention Engine + New Monetization

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 16.1 | Inspiration Deck data model | Medium | — |
| 16.2 | Theme/mood cards (Pinterest-like) | Medium | 16.1 |
| 16.3 | "Shop this vibe" bridge to Product Deck | Medium | 16.2 |
| 16.4 | Boards feature (save themes) | Low | 16.2 |
| 16.5 | Sponsored Themes (campaign type) | Low | 16.2 |
| 16.6 | Email pack integration (SendGrid/etc.) | Low | 9.1 |
| 16.7 | SMS pack integration | Low | 9.1 |
| 16.8 | Lifecycle messaging triggers | Low | 11.5 |
| 16.9 | Creative Health Score as formal module | Low | 10.6 |

---

### v4 — Creative Lab (Optional)

| Step | Task | Priority | Dependencies |
|------|------|----------|--------------|
| 17.1 | Image A/B testing framework | Low | 10.2 |
| 17.2 | Inspiration asset A/B testing | Low | 16.2 |
| 17.3 | AI creative scoring | Low | — |
| 17.4 | AI creative recommendations | Low | 17.3 |

---

## Engineering Checklist (v1 Data Model)

### Collections Required

| Collection | Purpose | Phase |
|------------|---------|-------|
| `users` | Authenticated user accounts | 9 |
| `decisionRooms` | Shared lists for voting/comparison | 9 |
| `decisionRoomItems` | Items within a decision room | 9 |
| `votes` | Per-item votes in decision rooms | 9 |
| `comments` | Room-level or item-level comments | 9 |
| `retailers` | Retailer accounts and ownership | 11 |
| `segments` | Targeting definitions | 11 |
| `campaigns` | Featured campaign objects | 11 |
| `scores` | Confidence Score per product × segment | 11 |

### Event Schema Additions

**Consumer events:**
- `impression` (product_id, deck_type, is_featured, campaign_id, rank_position)
- `decisionroom_create` / `decisionroom_view` / `decisionroom_join`
- `decisionroom_vote` / `decisionroom_comment`
- `finalists_set` / `suggest_alternative`
- `outbound_click` (with click_id, retailer_domain, segment_id, is_featured)

**Retailer events:**
- `campaign_create` / `campaign_update` / `campaign_pause`
- `product_include_exclude`
- `preview_view`
- `report_export`

**Pixel events (v2):**
- `pixel_landing` (swp_click_id, url, referrer)
- `pixel_product_view` / `pixel_add_to_cart` / `pixel_purchase`

---

## Implementation Guidelines

### Starting a New Phase

1. **Review dependencies** – Ensure prerequisite phases are complete
2. **Read relevant docs** – PRD.md for requirements, BACKEND_STRUCTURE.md for schema
3. **Create branch** – `feature/phase-{N}-{description}`
4. **Update CHANGELOG.md** – Add entries as work progresses
5. **Update this plan** – Mark tasks as in-progress/complete

### Task Completion Checklist

- [ ] Code implemented and working
- [ ] Unit tests added (if applicable)
- [ ] Integration tested locally
- [ ] Linter errors resolved
- [ ] Documentation updated
- [ ] CHANGELOG.md updated with timestamp

### Branching Strategy

```
main
  └── feature/phase-9-decision-room
        └── (develop, test, merge back to main)
```

### Commit Message Format

```
{type}: {brief description}

{detailed description if needed}

Refs: #{issue-number}
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

---

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| JS-rendered pages block extraction | High | Phase adds Playwright |
| Retailer blocks crawling | Medium | Polite fetcher, rotate user agents |
| Firestore costs spike | Medium | Optimize queries, add caching |
| App performance degrades | Medium | Optimize, profile |
| GDPR compliance gaps | Medium | Review PRIVACY_GDPR.md |
| Low retailer adoption | High | Strong value props, easy onboarding |
| Featured fatigue | Medium | Strict caps, relevance gates |
| Confidence Score gaming | Medium | Smoothing, anomaly detection |

---

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-01-15 | Use anonymous sessions first | Lower friction, faster MVP |
| 2026-01-20 | Firestore over PostgreSQL | Simpler ops, Firebase integration |
| 2026-01-25 | Static HTML extraction first | Simpler, covers 70% of retailers |
| 2026-02-01 | P1 focus on material/color/dimensions | Highest impact for recommendations |
| 2026-02-02 | Consolidated documentation structure | Better AI context, maintainability |
| 2026-02-05 | Progressive onboarding (gold cards) vs mandatory | Lower friction, collects preferences naturally |
| 2026-02-05 | Visual pick + budget hybrid approach | Combines visual preference learning with price filtering |
| 2026-02-05 | First-like trigger for gold cards | Balance engagement vs interruption |
| 2026-02-05 | Collaborative filtering via pick hash | Simple, effective grouping for similar users |
| 2026-02-05 | Confidence Score replaces HIS in UI | More intuitive for retailers, actionable |
| 2026-02-05 | Decision Room always ad-free | Protects user trust, key differentiator |
| 2026-02-05 | Featured frequency cap 1 in 12 | Balance monetization with UX |
| 2026-02-05 | Retailer Console as Insights Feed, not analytics | Actionable > informational |
| 2026-02-05 | Smart crawler auto-discovery from single URL | Reduce cognitive overhead, prevent config errors (domain root, protocol) |
| 2026-02-07 | Image extraction hardening as Week 0 blocker | Without working images, app is unusable; pulled forward from enrichment epic |
| 2026-02-07 | Crawl Wide, Show Narrow pipeline | Full classification + sorting engine to serve only quality items to deck while ingesting broadly |
| 2026-02-07 | Embedded JS state extraction | Extract products from window.INITIAL_DATA / __INITIAL_STATE__ without headless browsers, unlocking Chilli and RoyalDesign |
| 2026-02-08 | Golden Card v2 uses hybrid 4-step style-first onboarding | Increases cold-start signal quality while preserving low-friction swipe UX |
| 2026-02-08 | Golden Card v2 rollout is hash-bucketed + kill-switch controlled | Enables safe 10/50/100 progressive rollout with immediate fallback via env flags |

---

## References

- [PRD.md](PRD.md) – Product requirements
- [APP_FLOW.md](APP_FLOW.md) – User flows and screens
- [TECH_STACK.md](TECH_STACK.md) – Locked dependencies
- [FRONTEND_GUIDELINES.md](FRONTEND_GUIDELINES.md) – UI patterns
- [BACKEND_STRUCTURE.md](BACKEND_STRUCTURE.md) – API and schema
- [COMMERCIAL_STRATEGY.md](COMMERCIAL_STRATEGY.md) – Commercial model
- [GOLDEN_CARD_V2_UI_UX_SPEC.md](GOLDEN_CARD_V2_UI_UX_SPEC.md) – Complete page/button/copy spec
- [GOLDEN_CARD_V2_EXECUTION_ROADMAP.md](GOLDEN_CARD_V2_EXECUTION_ROADMAP.md) – Detailed cross-functional delivery plan
- [GOLDEN_CARD_V2_MANUAL_TEST_SCRIPT.md](GOLDEN_CARD_V2_MANUAL_TEST_SCRIPT.md) – Manual exploratory QA script (30 sessions)
- [RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md](RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md) – Alerts, thresholds, and rollout triage
- [DOCUMENTATION_CONSISTENCY_CHECK_2026-02-08.md](DOCUMENTATION_CONSISTENCY_CHECK_2026-02-08.md) – Cross-doc consistency audit and fixes
- [CHANGELOG.md](../CHANGELOG.md) – Version history

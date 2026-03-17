# Swiper – Project plan

## Current state

MVP shipped: Flutter app (deck-first entry, onboarding, deck, detail, likes, compare screen, profile, shared shortlist, admin), Firebase (Functions, Firestore, Hosting), Supply Engine (feed ingestion, sample feed), device context + event logging, Data & Privacy + opt-out, deck filters, admin items/sources/import. Ranker robustness fixes completed (exploration rate control, recency-preserving ties, atomic preference updates, persona zero-weight handling). Golden Card v2 implementation is shipped behind rollout controls; see `docs/IMPLEMENTATION_PLAN.md` for phase-level source of truth.

2026-02-02: Supply Engine crawl ingestion added (Sweden-first, sofas-first): sitemap/category URL discovery, extraction cascade (JSON-LD + embedded JSON + recipe runner + semantic DOM), snapshots/failures, daily metrics + drift triggers. P1 Recommendation Backbone: extract material, color, dimensions from crawl; normalize into items for ranker parity.

See [CHANGELOG.md](../CHANGELOG.md) and [ARCHITECTURE.md](ARCHITECTURE.md) for details.

---

## Historical next-phase goals (completed)

Outcome-focused goals (order is suggested; reorder as needed):

1. **Staging / first real deploy** – Deploy app + API to live Firebase once; run post-deploy smoke from [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md). *Done: [scripts/deploy_staging.sh](../scripts/deploy_staging.sh), runbook updated.*
2. **Real supply** – At least one non-sample source (CSV/JSON/URL) in admin, ingested into Firestore; deck shows real items. *Done: [config/sources.json](../config/sources.json) has sample_feed + demo_feed (JSON); runbook updated.*
3. **Language / locale** – Unblock "Swedish / English – coming soon" in profile (e.g. app locale switch or i18n skeleton) so we can use locale in recommendations. *Done: [lib/l10n/app_strings.dart](../apps/Swiper_flutter/lib/l10n/app_strings.dart), locale_provider, profile Language sheet, app-localised strings.*
4. **Admin auth** – Replace password gate with Firebase Auth allowlist (see [ASSUMPTIONS.md](ASSUMPTIONS.md), [DECISIONS.md](DECISIONS.md)). *Done: Firebase Auth + adminAllowlist; Sign in with Google on admin login; legacy password fallback is emulator-only by default and must be explicitly re-enabled for hosted environments; [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md) and [SECURITY.md](SECURITY.md) updated.*
5. **SSO / social login (optional)** – Optional connection to Instagram/Facebook for personalised feed; keep anonymous flow default. *Done: Data & Privacy "Connect social accounts" tappable with "Coming soon" dialog.*
6. **Swipe-first UX refresh** – Launch into deck, one-time swipe hint, hamburger menu, no bottom nav. *Done.*

---

## Backlog

Prioritised list (merge of EVENT_TRACKING, ASSUMPTIONS, DECISIONS; no duplicates):

- **SSO / social login** – Optional connection to Instagram, Facebook, etc. for personalised feed; anonymous remains default.
- **Optional user auth** – Signup / login for users later; anonymous-first stays.
- **Supply Engine: sources from Firestore** – Load sources from Firestore instead of config JSON. *Done: `services/supply_engine/app/sources.py` prefers Firestore `sources` and falls back to config.*
- **Supply Engine: compliant crawl ingestion (Sweden-first)** – Locator + resilient extractor + recipe runner + drift monitoring. *Done: `services/supply_engine/app/crawl_ingestion.py` and new `app/http`, `app/locator`, `app/extractor`, `app/recipes`, `app/monitor` modules.*
- **LLM extractor** – Optional; behind `ENABLE_LLM_EXTRACTOR` and `LLM_API_KEY`; MVP runs without it.
- **Geography / category** – Beyond Sweden-first and sofas-only.
- **Optional events** – `deck_refresh`, `card_view` or dwell in metadata for ML.
- **Events hygiene** – Keep every event with sessionId, createdAt, and suggested metadata so ML pipelines can join and featurize cleanly.
- **My Home tab** – Future personalization tab with home-context questions for recommendations.
- **Recommendations engine** – Personal and persona-based ranking, exploration, and ML best practices (offline eval, A/B, metrics); tested in isolation. *Done: [firebase/functions/src/ranker/](../firebase/functions/src/ranker/), [docs/RECOMMENDATIONS_ENGINE.md](RECOMMENDATIONS_ENGINE.md).* Persona aggregation pipeline and offline eval pipeline are follow-ups.

---

## Out of scope / later

AR preview, payments, messaging/escrow marketplace, multi-category beyond sofas (per ASSUMPTIONS non-goals).

---

## Maintenance

Update this doc when we close next-phase goals or add/complete backlog items.

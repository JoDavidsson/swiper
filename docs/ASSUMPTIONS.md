# Swiper – Assumptions

- **Geography**: Sweden-first MVP; sofas only.
- **Users**: Anonymous-first; no signup required to swipe. Optional auth later.
- **Content**: We ingest enough inventory to feel real; start with seed + 1 feed connector + 1 compliant crawl connector stub. **Who adds links:** End users do not add or submit links to be scraped; only the Swiper organization (via admin console, config, or Supply Engine) defines and allowlists sources for feed/crawl ingestion.
- **Monetization**: Affiliate commissions (tracked clickouts with UTM); premium subscription and ads are stubs only in MVP.
- **Non-goals (MVP)**: AR preview, payments, messaging/escrow marketplace, multi-category beyond sofas.
- **Crawling**: Only for explicitly allowlisted sources; we respect robots.txt and terms. No bypassing anti-bot, CAPTCHA solving, login, or paywall evasion.
- **Flutter web**: Primary web client; admin console is Flutter web routes.
- **Admin auth**: MVP uses password gate (env `ADMIN_PASSWORD`); replace with Firebase Auth allowlist later.
- **Supply Engine**: Sources loaded from config JSON in MVP; Firestore later. LLM extractor optional (env `ENABLE_LLM_EXTRACTOR` + `LLM_API_KEY`); MVP runs without LLM.

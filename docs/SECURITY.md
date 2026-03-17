# Swiper – Security

- **Admin**: Firebase Auth allowlist (Firestore `adminAllowlist` collection, document ID = admin email) is the primary admin path. Sign in with Google on `/admin`; legacy `ADMIN_PASSWORD` fallback is enabled automatically in emulator and can only be re-enabled outside emulator with `ALLOW_LEGACY_ADMIN_PASSWORD=true`.
- **Open redirect**: /go/:itemId validates outboundUrl: scheme https; optionally validate host against source baseUrl or allowlist.
- **Firestore rules**: Client read/write anon sessions, swipes, likes, shortlists, events. Items/sources/ingestion via Admin SDK only.
- **Analytics retention**: `events_v1` is cleaned up by the scheduled Functions job `cleanupAnalyticsEvents` (default retention: 730 days via `EVENTS_V1_RETENTION_DAYS`).
- **Secrets**: No keys in repo; use env vars and Secret Manager in production.

# Swiper – Security

- **Admin**: MVP password gate (ADMIN_PASSWORD env). Replace with Firebase Auth allowlist for production.
- **Open redirect**: /go/:itemId validates outboundUrl: scheme https; optionally validate host against source baseUrl or allowlist.
- **Firestore rules**: Client read/write anon sessions, swipes, likes, shortlists, events. Items/sources/ingestion via Admin SDK only.
- **Secrets**: No keys in repo; use env vars and Secret Manager in production.

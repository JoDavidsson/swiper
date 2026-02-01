# Swiper – Security

- **Admin**: Firebase Auth allowlist (Firestore `adminAllowlist` collection, document ID = admin email). Sign in with Google; legacy ADMIN_PASSWORD still works for POST admin/verify only; other admin routes require Bearer token.
- **Open redirect**: /go/:itemId validates outboundUrl: scheme https; optionally validate host against source baseUrl or allowlist.
- **Firestore rules**: Client read/write anon sessions, swipes, likes, shortlists, events. Items/sources/ingestion via Admin SDK only.
- **Secrets**: No keys in repo; use env vars and Secret Manager in production.

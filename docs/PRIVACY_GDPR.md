# Swiper – Privacy / GDPR

- **Data minimization**: Anonymous session ID, swipes, likes, shortlists, events. No PII. No precise location; only locationHint (city/region) when from source.
- **Events**: No PII in analytics; sessionId opaque.
- **Export**: Stub UI; API shape GET /api/me/export (auth) returning session, swipes, likes, shortlists.
- **Deletion**: Stub UI; API shape POST /api/me/delete (auth) deleting session and linked data; events may be anonymized.
- **Retention**: Analytics events (`events_v1`): **24 months**. Enforced by scheduled Functions job `cleanupAnalyticsEvents` using `createdAtServer` (default `EVENTS_V1_RETENTION_DAYS=730`). Firestore TTL can be added as an optional managed alternative. See [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md) “Data retention”.

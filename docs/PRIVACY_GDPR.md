# Swiper – Privacy / GDPR

- **Data minimization**: Anonymous session ID, swipes, likes, shortlists, events. No PII. No precise location; only locationHint (city/region) when from source.
- **Events**: No PII in analytics; sessionId opaque.
- **Export**: Stub UI; API shape GET /api/me/export (auth) returning session, swipes, likes, shortlists.
- **Deletion**: Stub UI; API shape POST /api/me/delete (auth) deleting session and linked data; events may be anonymized.
- **Retention**: Analytics events (events_v1): **24 months**. Documented in runbook; enforced by Firestore TTL (when configured) or by scheduled purge job. See [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md) “Data retention”.

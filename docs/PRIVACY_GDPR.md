# Swiper – Privacy / GDPR

- **Data minimization**: Anonymous session ID, swipes, likes, shortlists, events. No PII. No precise location; only locationHint (city/region) when from source.
- **Events**: No PII in analytics; sessionId opaque.
- **Export**: Stub UI; API shape GET /api/me/export (auth) returning session, swipes, likes, shortlists.
- **Deletion**: Stub UI; API shape POST /api/me/delete (auth) deleting session and linked data; events may be anonymized.
- **Retention**: Document in runbook (e.g. 24 months for analytics).

# Swiper – Decisions

- **State management**: Riverpod (single source of truth, testable).
- **Local cache**: Hive for session and preferences.
- **Left swipe**: Ignore for preference weights. Right swipe adds weight to item tags/attributes.
- **Preference weights**: Firestore `anonSessions/{sessionId}/preferenceWeights`.
- **Admin auth**: Password gate (env ADMIN_PASSWORD); replace with Firebase Auth allowlist later.
- **Open redirect**: HTTPS only; optionally validate domain against source baseUrl allowlist.
- **Supply Engine sources**: Config JSON in MVP; Firestore later.
- **Item inactivity**: Mark isActive=false if not seen for N=3 runs.
- **Hosting**: /go/* to Function go; /api/* to Function api; /s/* to Flutter web.

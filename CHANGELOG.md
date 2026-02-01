# Changelog

## 2025-01-31 – Plan implementation (deck filters, deploy runbook, profile, opt-out, admin)

- **Deck filters UI:** Real filter sheet with size class (small/medium/large), color family, and condition (new/used). Filters passed to `getDeck(filters)`; deck refreshes on apply/clear. `filter_change` event logged on apply and clear with metadata (sizeClass, colorFamily, newUsed). ApiClient sends filters as JSON string to backend.
- **First production deploy:** RUNBOOK_DEPLOYMENT.md updated with "Post-deploy smoke test" checklist (app load, session, deck, filters, detail, likes, compare, go redirect, profile, admin, shared shortlist).
- **Profile Language:** Stub replaced with "Swedish / English – coming soon"; ListTile disabled so expectations are clear.
- **Opt-out UI (functional):** Analytics opt-out stored in Hive (`swiper_analytics_opt_out`). Data & Privacy screen has a working Switch; when on, non-essential events (open_detail, detail_dismiss, filter_sheet_open, filter_change, session_start, deck_empty_view, compare_open, onboarding_complete) are not sent. Swipes and likes unchanged.
- **Admin Create source:** Dialog replaced with form (name, mode, baseUrl, isEnabled, rateLimitRps); submits to POST /api/admin/sources.
- **Admin Items:** Backend GET /api/admin/items (limit) added; Flutter Admin Items screen lists recent items (title, price, sourceId, active).
- **Admin Import:** Stub replaced with instructions and "Trigger sample / first source run" button that triggers run for a source named "sample" or the first source.

## 2025-01-31 – User interaction capture & Data & Privacy

- **Session context:** Backend `POST /api/session` accepts optional body: `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes`, `userAgent`; stored on **anonSessions**. Flutter sends device context via `DeviceContext.toSessionBody()` when creating session.
- **Client events:** Flutter logs to `POST /api/events`: `open_detail`, `detail_dismiss` (with `timeViewedMs`), `compare_open`, `filter_sheet_open`, `session_start`, `deck_empty_view`, `onboarding_complete` (with preferences). Deck and likes detail sheets log open/dismiss; compare screen logs once; deck logs session_start and deck_empty_view; onboarding logs completion with style/budget/prefs.
- **Session early create:** Splash “Get started” and “Skip to swipe” call `ensureSession()` so onboarding_complete can be logged with sessionId.
- **Data & Privacy screen:** New `/profile/data-privacy` explains what we collect (session/device, usage events); placeholders for “Opt out of analytics” and “Connect social accounts (Instagram/Facebook)” as coming later. Profile entry renamed to “Data & Privacy”.
- **Docs:** EVENT_TRACKING.md updated with client events and session context; backlog items for functional opt-out UI and SSO/social login.

## 2025-01-31 – MVP implementation

- **Flutter app**: Skeleton, Scandi theme, go_router, splash, onboarding (3-step), deck (swipe stack + draggable cards), detail sheet, likes (grid/list, compare, share), compare screen, profile, shared shortlist `/s/:token`, admin console (dashboard, sources, runs, items, import, QA). Riverpod + Dio + Hive.
- **Firebase**: Firestore rules/indexes, Cloud Functions (session, deck, swipe, likes, shortlists, events, go redirect, admin stats/sources/runs/qa/run trigger). Hosting rewrites for /go, /api, /s.
- **Supply Engine**: Python FastAPI, feed ingestion (CSV/JSON), normalization (material, color, size), Firestore client, crawl stub, extraction (JSON-LD + heuristics). Sample feed + config/sources.json. Dockerfile, run scripts.
- **Admin**: Password gate, sources CRUD + Run now, runs list/detail, QA completeness report.
- **Tests**: Flutter (preference scoring, filter logic, item model, swipe deck widget). Functions (go 400, shortlists create 400). Supply Engine (normalization, JSON-LD extractor). CI: GitHub Actions (Flutter analyze/test/build, Functions build/test, Supply Engine pytest).
- **Docs**: ASSUMPTIONS, DECISIONS, ARCHITECTURE, DATA_MODEL, TAG_TAXONOMY, INGESTION_COMPLIANCE, SECURITY, PRIVACY_GDPR, RUNBOOK_LOCAL_DEV, RUNBOOK_DEPLOYMENT.

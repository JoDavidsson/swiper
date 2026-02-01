# Swiper – QA & diagnostics report

Generated from a full diagnostics sweep and QA checklist verification.

---

## 1. Diagnostics sweep (automated)

### Flutter (apps/Swiper_flutter)

| Check | Result |
|-------|--------|
| **flutter analyze** | Pass (warnings addressed: unused import router, unnecessary_cast admin_items, unused variable admin_runs, unused import integration_test) |
| **flutter test** | **11/11 passed** (preference_scoring, item_model, filter_logic, swipe_deck) |
| **flutter build web** | **Success** (build/web) |

### Firebase Functions (firebase/functions)

| Check | Result |
|-------|--------|
| **npm run build** | Success |
| **npm test** | **2/2 passed** (go.test.ts, shortlists.test.ts) |

### Supply Engine (services/supply_engine)

| Check | Result |
|-------|--------|
| **pytest** | Not run (pytest not in default PATH; use `.venv` or `pip install -r requirements.txt` then `pytest tests/`) |

### API smoke test (with emulators)

| Check | Result |
|-------|--------|
| **./scripts/smoke_test_api.sh** | **Pass** – POST /api/session 200 + sessionId, GET /api/items/deck 200 |

---

## 2. Admin mode QA checklist

Use this when testing admin with emulators + Flutter app running. Path-based URLs: go to `http://localhost:PORT/admin`.

| # | Flow | What to verify |
|---|------|----------------|
| 1 | **/admin** | Redirects to admin login (or dashboard if already logged in). No splash; login screen with "Sign in with Google" (if GOOGLE_SIGN_IN_WEB_CLIENT_ID set) and "Login with password". |
| 2 | **Login (password)** | Enter ADMIN_PASSWORD from .env → "Login with password" → redirect to dashboard. Snackbar about legacy login / Sign in with Google for full access. |
| 3 | **Login (Google)** | Requires GOOGLE_SIGN_IN_WEB_CLIENT_ID + email in Firestore adminAllowlist. "Sign in with Google" → popup → redirect to dashboard. Subsequent admin API calls use Bearer token. |
| 4 | **Dashboard** | Stats (sessions, swipes, etc.), links: Sources, Runs, Items, Import, QA. Logout → back to login. |
| 5 | **Sources** | List of sources (from Firestore). "Run now" on a source → triggers run (Supply Engine must be up for full run). FAB "+" → Create source form (name, mode, baseUrl, rateLimitRps, enabled) → Create → source in list. |
| 6 | **Runs** | List of ingestion runs. Tap a run → run detail (jobs, status, stats). |
| 7 | **Items** | List of recent items (title, price, sourceId, active). After ingest, sample items appear. |
| 8 | **Import** | Instructions + "Trigger sample / first source run" → triggers run for sample/first source; snackbar "Run triggered" or "No sources". |
| 9 | **QA** | QA completeness report (items with missing fields). |
| 10 | **Auth** | Without token: legacy password login works for verify only; other admin routes (stats, sources, etc.) require Bearer token. With Google sign-in + allowlist, all admin routes work. |

**Reference:** [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md) (admin allowlist, Web client ID), [TESTING_LOCAL.md](TESTING_LOCAL.md).

---

## 3. End-user flow QA checklist

Use this when testing the main app with emulators + Flutter app running.

| # | Flow | What to verify |
|---|------|----------------|
| 1 | **Splash** | "Swiper", tagline, "Get started", "Skip to swipe". Path-based URL: `/admin` shows admin login, not splash. |
| 2 | **Get started** | Tap "Get started" → onboarding (3 steps: style, budget, preferences) → "Building your deck…" → deck. |
| 3 | **Skip to swipe** | Tap "Skip to swipe" → deck (no onboarding). Session created; deck loads. |
| 4 | **Deck** | Cards from ingested items. Swipe left (X) / right (heart). Deck updates. Filter icon → filter sheet (size, color, condition) → Apply / Clear → deck refreshes. |
| 5 | **Detail** | Tap card → detail sheet (images, title, price, "View on site"). Close sheet. No dispose errors in console. |
| 6 | **Likes** | Swipe right on items → heart icon → Likes list. Tap item → detail. |
| 7 | **Compare** | In Likes, select 2–4 items → Compare → compare screen. "View on site" per item. |
| 8 | **Share shortlist** | In Likes, select items → Share → get link. Open `/s/:token` in new tab → shared shortlist page. |
| 9 | **Profile** | Profile → Language (sheet: Swedish/English), Data & Privacy, Edit preferences (onboarding). |
| 10 | **Data & Privacy** | Opt-out switch (stops non-essential events). "Connect social accounts" → "Coming soon" dialog. |
| 11 | **Go redirect** | Detail → "View on site" → 302 from `/go/:itemId` → outbound URL with UTM. |
| 12 | **Locale** | Profile → Language → pick Swedish or English → app strings (splash, profile, Data & Privacy) update. |
| 13 | **Empty deck** | Swipe all or strict filters with no match → "No more items" / adjust filters. |

**Reference:** [TESTING_LOCAL.md](TESTING_LOCAL.md), [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md) post-deploy smoke test.

---

## 4. Fixes applied during sweep

- **router.dart:** Removed unused `flutter/material.dart` import (go_router provides builder types).
- **admin_items_screen.dart:** Removed unnecessary cast `(price as num)` after `price is num` (use promoted type).
- **admin_runs_screen.dart:** Renamed unused `startedAt` to `_` to satisfy unused_local_variable.
- **integration_test/app_test.dart:** Removed unused `flutter/material.dart` import.

---

## 5. Maintenance

Re-run diagnostics after major changes:

```bash
cd apps/Swiper_flutter && flutter analyze && flutter test
cd firebase/functions && npm run build && npm test
./scripts/smoke_test_api.sh   # with emulators running
```

For full Supply Engine tests: `cd services/supply_engine && .venv/bin/pytest tests/ -v` (or activate venv first).

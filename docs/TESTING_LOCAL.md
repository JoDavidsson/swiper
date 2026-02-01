# Swiper – Local testing guide

How to run the app locally and what to try for **end-user** and **admin** interfaces.

---

## 1. Start the stack (3 terminals)

**Terminal 1 – Firebase emulators** (leave running)

```bash
cd "/Users/johannesdavidsson/Cursor Projects/Swiper"
./scripts/run_emulators.sh
```

Wait until you see “All emulators ready”. Note: Firestore `localhost:8180`, Functions `localhost:5002`, Hosting `localhost:5010`, Emulator UI `localhost:4100`.

**Terminal 2 – Ingest sample data** (run once per emulator session)

```bash
cd "/Users/johannesdavidsson/Cursor Projects/Swiper"
export FIRESTORE_EMULATOR_HOST=localhost:8180
./scripts/ingest_sample_feed.sh
```

If the script fails, ensure Python deps are installed: `cd services/supply_engine && pip3 install -r requirements.txt` (or use the repo’s `.venv` if you have one).

**Terminal 3 – Flutter app** (leave running)

```bash
cd "/Users/johannesdavidsson/Cursor Projects/Swiper/apps/Swiper_flutter"
flutter pub get
flutter run -d chrome
```

Chrome opens the app. It talks to the emulator by default (`http://localhost:5002/...`).

---

## 2. Test the **end-user** interface

**URL:** The URL Flutter opens (e.g. `http://localhost:xxxxx`). Use the same browser tab.

### Checklist – End user

| # | What to try | What to check |
|---|-------------|----------------|
| 1 | **Splash** | Splash screen with “Get started” and “Skip to swipe”. |
| 2 | **Get started** | Tap “Get started” → onboarding (3 steps). |
| 3 | **Onboarding** | Step 1: pick styles. Step 2: budget slider. Step 3: eco/new/size toggles. Tap “Building your deck…” → deck. |
| 4 | **Skip to swipe** | From splash, tap “Skip to swipe” → deck (no onboarding). |
| 5 | **Deck** | Cards appear (sample sofas). Swipe left (X) and right (heart). Deck updates. |
| 6 | **Filters** | Tap filter (tune) icon → sheet. Choose Size (e.g. Small), Color (e.g. Gray), Condition (e.g. New). Tap “Apply” → deck refreshes. Tap filter again → “Clear all” → deck refreshes. |
| 7 | **Detail** | Tap a card → detail sheet (images, title, price, “View on site”). Close sheet (drag or tap outside). |
| 8 | **Likes** | Swipe right on 1–2 items. Tap heart icon in app bar → Likes list. Tap an item → detail sheet. |
| 9 | **Compare** | In Likes, long-press to select 2–4 items. Tap “Compare” → compare screen with table. |
| 10 | **Share shortlist** | In Likes, select items, tap “Share” (or similar) → get link. Open link in new tab → `/s/:token` shows shared shortlist. |
| 11 | **Profile** | Tap person icon → Profile. “Language” (coming soon, disabled). “Data & Privacy” → Data & Privacy screen. “Edit preferences” → onboarding. |
| 12 | **Data & Privacy** | “Opt out of analytics” switch: turn ON → then use deck/detail/filters; events for those are not sent. Turn OFF to send again. |
| 13 | **View on site** | From detail, tap “View on site” → redirect to `/go/:itemId` then outbound URL (or placeholder). |
| 14 | **Empty deck** | Swipe through all cards (or apply strict filters with no match) → “No more items” with hint to adjust filters. |

---

## 3. Test the **admin** interface

**URL:** Same origin as the app, then go to **`/admin`** (e.g. `http://localhost:xxxxx/admin`). You are redirected to **`/admin/login`** if not logged in.

**Login:** Use **password** (from `.env` `ADMIN_PASSWORD`) or **Sign in with Google** (requires Web client ID and email in Firestore `adminAllowlist` – see [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md)).

### Checklist – Admin

| # | What to try | What to check |
|---|-------------|----------------|
| 1 | **Login** | Open `/admin` (path-based URL; app must be built with path strategy). Enter `ADMIN_PASSWORD` from `.env` → "Login with password" → redirect to dashboard. Or "Sign in with Google" if GOOGLE_SIGN_IN_WEB_CLIENT_ID is set and your email is in adminAllowlist. |
| 2 | **Dashboard** | Stats and links to Sources, Runs, Items, Import, QA. |
| 3 | **Sources** | List of sources (after ingest you may see a source or none). “Run now” on a source triggers a run (Supply Engine must be reachable for it to complete; locally you may only see “Run triggered”). |
| 4 | **Create source** | Tap “+” (FAB). Form: Name, Mode (feed/api/crawl/manual), Base URL, Rate limit, Enabled. Fill name (e.g. “Test feed”), mode “feed”, baseUrl “https://example.com”, rate 1, Enabled ON. Tap “Create” → source appears in list. |
| 5 | **Items** | Open “Items”. List of recent items (from Firestore). After ingest, sample sofas appear (title, price, sourceId). Pull to refresh. |
| 6 | **Import** | Open “Import”. Instructions shown. Tap “Trigger sample / first source run” → if at least one source exists, run is triggered and snackbar “Run triggered”. If no sources, snackbar “No sources. Add one in Sources first.” |
| 7 | **Runs** | List of ingestion runs (source, status, etc.). Open a run to see details. |
| 8 | **QA** | QA report (completeness of items, etc.). |
| 9 | **Logout / re-login** | Navigate away or refresh; go to `/admin` again → login required. Enter password again to re-enter admin. |

---

## 4. Quick reference

| Thing | Value |
|-------|--------|
| App (end user) | Same URL as Flutter run (e.g. `http://localhost:xxxxx`) |
| Admin login | `http://localhost:xxxxx/admin` → `/admin/login` |
| Admin password | `.env` → `ADMIN_PASSWORD` |
| Emulator UI | `http://localhost:4100` (Firestore, Functions, etc.) |
| Firestore port | `8180` (for `FIRESTORE_EMULATOR_HOST=localhost:8180`) |
| Ingest (one-time) | `FIRESTORE_EMULATOR_HOST=localhost:8180 ./scripts/ingest_sample_feed.sh` |

---

## 5. Troubleshooting

- **“Backend not available” / 404 on deck:** Emulators not running or wrong port. Start Terminal 1 and wait for “All emulators ready”; Flutter uses port 5002 by default.
- **No cards in deck:** Run the ingest script (Terminal 2) with `FIRESTORE_EMULATOR_HOST=localhost:8180`.
- **Admin login fails:** Check `.env` has `ADMIN_PASSWORD` set; Functions read it when verifying.
- **“Run triggered” but no new items:** Supply Engine is not running locally. For local ingest, use `./scripts/ingest_sample_feed.sh`; “Run now” in admin calls Supply Engine (e.g. Cloud Run in prod).

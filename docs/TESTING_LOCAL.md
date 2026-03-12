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
| 1 | **Deck launch** | App opens directly to the deck. One-time swipe hint overlay appears and dismisses on first swipe/tap. |
| 2 | **Deck** | Cards appear (sample sofas). Swipe left (X) and right (heart). Deck updates. |
| 3 | **Filters** | Tap hamburger menu → Filters. Choose Size (e.g. Small), Color (e.g. Gray), Condition (e.g. New). Tap “Apply” → deck refreshes. Tap filter again → “Clear all” → deck refreshes. |
| 4 | **Detail** | Tap a card → detail modal sheet (images, title, price, “View on site”). Close sheet (drag or tap outside). |
| 5 | **Likes** | Swipe right on 1–2 items. Open menu → Likes list. Tap an item → detail sheet. |
| 6 | **Share shortlist** | In Likes, select items, tap “Share shortlist” → get link. Open link in new tab → `/s/:token` shows shared shortlist. |
| 7 | **Preferences** | Open menu → Preferences. Step 1: pick styles. Step 2: budget slider. Step 3: eco/new/size toggles. Tap “Building your deck…” → deck. |
| 8 | **Data & Privacy** | Open menu → Data & Privacy. “Opt out of analytics” switch: turn ON → then use deck/detail/filters; events for those are not sent. Turn OFF to send again. |
| 9 | **Language** | Open menu → Language. Pick Swedish or English; labels update. |
| 10 | **View on site** | From detail, tap “View on site” → redirect to `/go/:itemId` then outbound URL (or placeholder). |
| 11 | **Empty deck** | Swipe through all cards (or apply strict filters with no match) → “No more items” with hint to adjust filters. |

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
| Synthetic dataset (fake DB) | See [Synthetic dataset for persona and offline eval](#5-synthetic-dataset-for-persona-and-offline-eval) below. |

---

## 5. Synthetic dataset for persona and offline eval

The **fake database** generator creates a synthetic Firestore dataset (e.g. 1000 users, 1000 interactions per user) to support **evaluation of the recommendation algorithm**: persona-based ranking, offline metrics (e.g. liked items in top-K), and A/B. Data is for testing and tuning only; target is the Firestore emulator.

**Run order**

1. Start emulators: `./scripts/run_emulators.sh` (leave running).
2. **(Option A)** Ingest items first: `FIRESTORE_EMULATOR_HOST=localhost:8180 ./scripts/ingest_sample_feed.sh` so the generator can reference existing item IDs. **(Option B)** Skip ingest and use `--generate-items N` so the generator creates N synthetic items.
3. From **firebase/functions**, run the generator (set env so the script talks to the emulator):

   ```bash
   cd firebase/functions
   export FIRESTORE_EMULATOR_HOST=localhost:8180
   export GOOGLE_APPLICATION_CREDENTIALS="../../config/emulator-credentials.json"
   node scripts/generate_fake_db.js [--users 1000] [--interactions-per-user 1000] [--seed 42] [--generate-items N]
   ```

   Or with npm: `FIRESTORE_EMULATOR_HOST=localhost:8180 GOOGLE_APPLICATION_CREDENTIALS="../../config/emulator-credentials.json" npm run generateFakeDb -- --users 100 --interactions-per-user 100` (smaller run for a quick test).

4. Use the app or deck API against the emulator; deck will read preferenceWeights and swipes from the synthetic sessions (e.g. sessionId `synth_1`, `synth_2`, …).

**Options:** `--users` (default 1000), `--interactions-per-user` (default 1000), `--seed` (default 42), `--generate-items N` (optional; if omitted, items must already exist in Firestore). **Safety:** The script requires `FIRESTORE_EMULATOR_HOST` to be set so it never writes to production.

---

## 6. Stress test

A **stress test** runs a larger synthetic dataset (5,000 products, 100 users, 30 swipes per user), unit tests, and many deck API calls, then writes a **human-readable report** so you can see what ran and what passed.

**Run (from repo root):**

```bash
./scripts/run_stress_test.sh
```

**Prereqs:** Start emulators first (`./scripts/run_emulators.sh`). Set `FIRESTORE_EMULATOR_HOST=localhost:8180` if not already set.

**Report:** The script prints a plain-language summary to the console and writes it to [docs/STRESS_TEST_REPORT.md](STRESS_TEST_REPORT.md). The report explains: how many products and users were generated, how long each phase took, whether all deck requests and Jest tests passed, and what that means.

**Large-candidate ranking:** By default the deck API only fetches and ranks a conservative number of candidates per request. To stress the ranker with many more candidates (e.g. 1,000–2,000 per request), set `DECK_ITEMS_FETCH_LIMIT` and `DECK_CANDIDATE_CAP` (e.g. `2000`) in the environment **when you start the emulators**, so the Functions process sees them. If you also want to score deeper before final slicing, set `DECK_RANK_WINDOW_MULTIPLIER` (default `48`). For repeated high-cap tests, `DECK_RETRIEVAL_DOCS_CACHE_TTL_MS` controls retrieval-doc cache TTL (default `15000`). Then run `./scripts/run_stress_test.sh` again.

---

## 7. Troubleshooting

- **“Backend not available” / 404 on deck:** Emulators not running or wrong port. Start Terminal 1 and wait for “All emulators ready”; Flutter uses port 5002 by default.
- **No cards in deck:** Run the ingest script (Terminal 2) with `FIRESTORE_EMULATOR_HOST=localhost:8180`.
- **Admin login fails:** Check `.env` has `ADMIN_PASSWORD` set; Functions read it when verifying.
- **“Run triggered” but no new items:** Supply Engine is not running locally. For local ingest, use `./scripts/ingest_sample_feed.sh`; “Run now” in admin calls Supply Engine (e.g. Cloud Run in prod).

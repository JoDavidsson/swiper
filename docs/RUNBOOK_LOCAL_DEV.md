# Swiper – Local development runbook

## Prerequisites

- Flutter SDK (stable)
- Node.js 18+
- Python 3.11+
- Firebase CLI (`npm i -g firebase-tools`)
- (Optional) Java for Firestore emulator

---

## Quick start: test the app in the browser

1. **Terminal 1 – start Firebase emulators** (backend + Firestore):
   ```bash
   cd "/Users/johannesdavidsson/Cursor Projects/Swiper"
   ./scripts/run_emulators.sh
   ```
   Wait until you see “All emulators ready”. Leave this running.

2. **Terminal 2 – ingest sample data** (so there are items to swipe).  
   One-time: install Supply Engine deps: `cd services/supply_engine && pip3 install -r requirements.txt` (or `python3 -m pip install -r requirements.txt` if `pip3` is not in PATH).  
   Then:
   ```bash
   cd "/Users/johannesdavidsson/Cursor Projects/Swiper"
   export FIRESTORE_EMULATOR_HOST=localhost:8180
   ./scripts/ingest_sample_feed.sh
   ```

3. **Terminal 3 – run the Flutter app** (web):
   ```bash
   cd "/Users/johannesdavidsson/Cursor Projects/Swiper"
   ./scripts/run_flutter_web.sh
   ```
   The app runs on **http://localhost:8080** (same port every time – you can bookmark it). **Leave this terminal running:** code changes hot-reload automatically; you don’t need to re-run the command. Admin: **http://localhost:8080/admin**. API base: `http://localhost:5002/swiper-95482/europe-west1`.

You can swipe through the sample sofas and open Likes and Filters from the hamburger menu. Admin is at `/admin/login` (password from `.env` `ADMIN_PASSWORD`).

### Verify API without Chrome (CI / agent autonomy)

With emulators running, you can smoke-test the API from the shell (no browser):

```bash
./scripts/smoke_test_api.sh
# Optional: custom base URL
./scripts/smoke_test_api.sh http://127.0.0.1:5002/swiper-95482/europe-west1
```

This checks `POST /api/session` (200 + `sessionId`) and `GET /api/items/deck` (200). Use this to verify backend fixes without opening Chrome or inspecting the console.

### Integration tests (web, headless-capable)

Automated tests run the app in Chrome and capture console errors. One test navigates away while the deck is loading and asserts no “dispose” errors (e.g. “Tried to use DeckNotifier after dispose”).

**Requirements:** Chrome and [ChromeDriver](https://googlechromelabs.github.io/chrome-for-testing/) on your PATH. ChromeDriver version must match your Chrome version. Example install:

```bash
npx @puppeteer/browsers install chromedriver@stable
# Add the printed path to PATH, or symlink the chromedriver binary into a dir on PATH.
```

**Run from the Flutter app directory (automated, no manual chromedriver needed):**

```bash
cd apps/Swiper_flutter
./scripts/run_integration_test_web.sh
```

The script starts ChromeDriver on 4444 if needed and runs tests in **release mode** (avoids debug connection issues in automation). Headless: `./scripts/run_integration_test_web.sh --headless`.

Manual run (with chromedriver already on port 4444):

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d chrome --release
```

---

## 1. Clone and env

```bash
git clone <repo>
cd Swiper
cp .env.example .env
# Edit .env: API_BASE_URL for Functions emulator, ADMIN_PASSWORD, etc.
```

## 2. Firebase emulators

```bash
./scripts/run_emulators.sh
# Or: firebase emulators:start --only firestore,functions,hosting,auth,ui
# Firestore: http://localhost:8180
# Functions: http://localhost:5002
# UI: http://localhost:4100
```

## 3. Flutter app

```bash
cd apps/Swiper_flutter
flutter pub get
# Use emulator: set FLUTTER_FIREBASE_EMULATOR=1 and point API_BASE_URL to http://localhost:5002/<project>/europe-west1
flutter run -d chrome
# Or: flutter run -d ios
```

## 4. Supply Engine

```bash
./scripts/run_supply_engine.sh
# Or: cd services/supply_engine && PYTHONPATH=. uvicorn app.main:app --reload --port 8081
# Health: http://localhost:8081/health
# Trigger run: POST http://localhost:8081/run/sample_feed
```

## 5. Ingest sample feed

```bash
export FIRESTORE_EMULATOR_HOST=localhost:8180
# If using real project: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
./scripts/ingest_sample_feed.sh
```

## 6. Test swipe flow (mock data)

Yes. Mock data lives in **`sample_data/sample_feed.csv`** (5 sofas: titles, prices, images, material, color). The ingest script loads it into Firestore so the deck API returns them.

**Minimal steps to test swipe:**

1. **Start emulators** (Terminal 1):  
   `./scripts/run_emulators.sh`  
   Wait until “All emulators ready”.

2. **Ingest sample feed** (Terminal 2, one-time per emulator run):  
   ```bash
   export FIRESTORE_EMULATOR_HOST=localhost:8180
   ./scripts/ingest_sample_feed.sh
   ```  
   You should see “Result: … succeeded” and items written to the `items` collection.

3. **Run the app** (Terminal 3):  
   ```bash
   cd apps/Swiper_flutter
   flutter run -d chrome
   ```  
   The app uses the Functions emulator by default.

4. **In the app:** The deck opens immediately with the 5 sample sofas. Swipe **left** (pass) or **right** (like). Open the hamburger menu → **Likes** to see liked items. Swiped items disappear from the deck; you can keep swiping until the deck is empty.

**Sample feed contents:** `sample_data/sample_feed.csv` has 5 rows (Scandi 2-seat, Velvet 3-seat, Compact sofa, Leather corner, Boucle armchair) with `title`, `price`, `currency`, `url`, `image_url`, `brand`, `description`, dimensions, `material`, `color`, `new_used`. The Supply Engine normalizes and writes them to Firestore with `isActive: true` so the deck API returns them.

## 7. Synthetic dataset for recommendation evaluation

To test **persona-based ranking** and **offline evaluation** (e.g. liked items in top-K) without production traffic, use the fake database generator. It creates multi-session interaction data (e.g. 1000 users, 1000 interactions per user) in the Firestore emulator.

**Run order:** Start emulators → (optional) ingest items or use `--generate-items N` → run generator from `firebase/functions`. See [TESTING_LOCAL.md](TESTING_LOCAL.md) “Synthetic dataset for persona and offline eval” for the exact commands and options (`--users`, `--interactions-per-user`, `--seed`, `--generate-items`). The script requires `FIRESTORE_EMULATOR_HOST` so it never writes to production.

## Environment variables

| Var | Where | Default | Description |
|-----|--------|---------|-------------|
| API_BASE_URL | Flutter | `http://localhost:5002/<project>/europe-west1` | Base URL for API calls |
| ADMIN_PASSWORD | Functions | (none) | Admin login password |
| SUPPLY_ENGINE_URL | Functions | `http://localhost:8081` | Supply Engine URL for admin triggers |
| FIRESTORE_EMULATOR_HOST | Supply Engine | (none) | e.g. `localhost:8180` (required for local dev) |
| GOOGLE_APPLICATION_CREDENTIALS | Supply Engine | (none) | Path to service account JSON (prod only) |
| SOURCES_JSON | Supply Engine | `config/sources.json` | Path to sources configuration file |

---

## Port Reference

| Service | Port | Notes |
|---------|------|-------|
| **Firestore Emulator** | 8180 | Configured in `firebase.json` |
| **Functions Emulator** | 5002 | Configured in `firebase.json` |
| **Supply Engine** | 8081 | Started by `run_supply_engine.sh` |
| **Flutter Web** | 8080 | Default Flutter web port |
| **Emulator UI** | 4100 | Firebase emulator dashboard |

> **Important:** Scripts auto-set `FIRESTORE_EMULATOR_HOST=localhost:8180` where needed.
> The Functions emulator uses `SUPPLY_ENGINE_URL=http://localhost:8081` by default.

---

## Troubleshooting

### "Supply Engine is not reachable" when triggering runs

**Symptoms:** Admin triggers fail with "Supply Engine is not reachable" error.

**Cause:** Functions emulator can't connect to Supply Engine.

**Fix:**
1. Ensure Supply Engine is running: `./scripts/run_supply_engine.sh`
2. Check it's on port 8081: `curl http://localhost:8081/health`
3. If using a different port, set `SUPPLY_ENGINE_URL` before starting emulators:
   ```bash
   export SUPPLY_ENGINE_URL=http://localhost:YOUR_PORT
   ./scripts/run_emulators.sh
   ```

### "Functions not found" or stale code

**Symptoms:** API returns 404 or behaves unexpectedly after code changes.

**Cause:** TypeScript not rebuilt before starting emulators.

**Fix:** The `run_emulators.sh` script now automatically runs `npm run build` in `firebase/functions/` before starting. If you're running emulators manually, build first:
```bash
cd firebase/functions && npm run build
firebase emulators:start --only firestore,functions
```

### "FIRESTORE_EMULATOR_HOST not set" warnings

**Symptoms:** Supply Engine writes to production or fails silently.

**Cause:** Missing emulator host environment variable.

**Fix:** The `run_supply_engine.sh` script now auto-sets `FIRESTORE_EMULATOR_HOST=localhost:8180`. If running manually:
```bash
export FIRESTORE_EMULATOR_HOST=localhost:8180
cd services/supply_engine
uvicorn app.main:app --reload --port 8081
```

### Crawls fail with 0 products

**Symptoms:** Source shows "Successful" but 0 products extracted.

**Possible causes:**
1. **URL normalization issues:** Ensure source URL includes `https://` protocol
2. **robots.txt blocking:** Check if the site blocks the crawler
3. **Path filter too restrictive:** Auto-discovered path patterns may filter out all URLs

**Debug steps:**
1. Watch the Supply Engine terminal for verbose crawl logs
2. Check the run details in Admin > Runs for error messages
3. Try re-detecting the source to refresh derived configuration

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

You can swipe through the sample sofas, open likes, compare, and use the bottom nav. Admin is at `/admin/login` (password from `.env` `ADMIN_PASSWORD`).

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

4. **In the app:** Tap **“Skip to swipe”** → the deck loads the 5 sample sofas. Swipe **left** (pass) or **right** (like). Open **Likes** from the bottom nav to see liked items. Swiped items disappear from the deck; you can keep swiping until the deck is empty.

**Sample feed contents:** `sample_data/sample_feed.csv` has 5 rows (Scandi 2-seat, Velvet 3-seat, Compact sofa, Leather corner, Boucle armchair) with `title`, `price`, `currency`, `url`, `image_url`, `brand`, `description`, dimensions, `material`, `color`, `new_used`. The Supply Engine normalizes and writes them to Firestore with `isActive: true` so the deck API returns them.

## Environment variables

| Var | Where | Description |
|-----|--------|-------------|
| API_BASE_URL | Flutter | Base URL for API (e.g. http://localhost:5001/...) |
| ADMIN_PASSWORD | Functions | Admin login password |
| SUPPLY_ENGINE_URL | Functions | Supply Engine URL (e.g. http://localhost:8081) |
| FIRESTORE_EMULATOR_HOST | Supply Engine | e.g. localhost:8180 |
| GOOGLE_APPLICATION_CREDENTIALS | Supply Engine | Path to service account JSON (prod) |
| SOURCES_JSON | Supply Engine | Path to config/sources.json |

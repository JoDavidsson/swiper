# Swiper – Local development runbook

## Prerequisites

- Flutter SDK (stable)
- Node.js 18+
- Python 3.11+
- Firebase CLI (`npm i -g firebase-tools`)
- (Optional) Java for Firestore emulator

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
# Firestore: http://localhost:8080
# Functions: http://localhost:5001
# UI: http://localhost:4000
```

## 3. Flutter app

```bash
cd apps/Swiper_flutter
flutter pub get
# Use emulator: set FLUTTER_FIREBASE_EMULATOR=1 and point API_BASE_URL to http://localhost:5001/<project>/europe-west1/api
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
export FIRESTORE_EMULATOR_HOST=localhost:8080
# If using real project: export GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json
./scripts/ingest_sample_feed.sh
```

## Environment variables

| Var | Where | Description |
|-----|--------|-------------|
| API_BASE_URL | Flutter | Base URL for API (e.g. http://localhost:5001/...) |
| ADMIN_PASSWORD | Functions | Admin login password |
| SUPPLY_ENGINE_URL | Functions | Supply Engine URL (e.g. http://localhost:8081) |
| FIRESTORE_EMULATOR_HOST | Supply Engine | e.g. localhost:8080 |
| GOOGLE_APPLICATION_CREDENTIALS | Supply Engine | Path to service account JSON (prod) |
| SOURCES_JSON | Supply Engine | Path to config/sources.json |

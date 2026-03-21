# AGENTS.md

## Cursor Cloud specific instructions

### Architecture overview

Swiper is a furniture discovery app ("Tinder for sofas"). Three main services:

| Service | Tech | Location | Dev port |
|---|---|---|---|
| Firebase Emulators (Firestore + Functions + Auth) | Node.js 20 / TypeScript | `firebase/functions/` | Firestore: 8180, Functions: 5002, Auth: 9099, UI: 4100 |
| Flutter Web App | Flutter/Dart | `apps/Swiper_flutter/` | 8080 |
| Supply Engine | Python 3.11+ / FastAPI | `services/supply_engine/` | 8081 |

### Running services

Standard commands are documented in `README.md` (Quick start) and `docs/RUNBOOK_LOCAL_DEV.md`.

**Start order:** Emulators first, then ingest sample data, then Flutter web.

```
# Terminal 1: Firebase emulators (must be first)
./scripts/run_emulators.sh

# Terminal 2: Ingest sample data (one-time per emulator session)
FIRESTORE_EMULATOR_HOST=localhost:8180 ./scripts/ingest_sample_feed.sh

# Terminal 3: Flutter web (headless-friendly)
flutter run -d web-server --web-port=8080 \
  --dart-define=USE_FIREBASE_AUTH_EMULATOR=true \
  --dart-define=FIREBASE_AUTH_EMULATOR_HOST=localhost \
  --dart-define=FIREBASE_AUTH_EMULATOR_PORT=9099
```

### Gotchas & caveats

- **Flutter web-server device:** In headless/CI environments (no display), use `-d web-server` instead of `-d chrome`. This serves the app at `http://localhost:8080` without requiring a display.
- **Node version mismatch:** The Functions `package.json` declares `"node": "20"` but Node 22 works fine; the emulator warns but runs.
- **Flutter analyze exit code:** `flutter analyze` exits with code 1 due to ~76 pre-existing info/warning-level issues (no errors). This is expected; do not treat it as a failure.
- **Emulator data persistence:** `run_emulators.sh` auto-exports Firestore data to `emulator-data/` on exit and re-imports on next start. If you need a clean state, delete `emulator-data/` before starting.
- **Supply Engine virtualenv:** Python deps are installed in `services/supply_engine/.venv`. The `ingest_sample_feed.sh` script auto-detects this venv.
- **Admin password:** Set `ADMIN_PASSWORD` in `.env` for admin console access at `/admin`.
- **CHROME_EXECUTABLE:** Set `CHROME_EXECUTABLE=/usr/local/bin/google-chrome` if Flutter can't find Chrome.

### Testing

- **Jest (Functions):** `cd firebase/functions && npx jest` — 86 tests, all should pass.
- **TypeScript check:** `cd firebase/functions && npx tsc --noEmit` — should be clean.
- **Flutter analyze:** `cd apps/Swiper_flutter && flutter analyze` — info/warnings only, no errors.
- **API smoke test:** `./scripts/smoke_test_api.sh` — requires emulators running + data ingested.
- **Integration tests:** See `docs/RUNBOOK_LOCAL_DEV.md` "Integration tests" section.

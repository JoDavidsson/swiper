# Swiper

Furniture discovery app (Tinder-like swipe deck). Sweden-first, sofas only.

## Repo structure

- **apps/Swiper_flutter** – Flutter app (iOS, Android, Web PWA)
- **firebase/** – Functions, Firestore rules/indexes, Hosting, Storage
- **services/supply_engine** – Python ingestion (feed/crawl)
- **sample_data/** – Sample feed CSV/JSON and HTML fixtures
- **docs/** – Architecture, assumptions, decisions, runbooks

## Firebase setup (first time)

See **[docs/SETUP_FIREBASE_AND_SERVICES.md](docs/SETUP_FIREBASE_AND_SERVICES.md)** for what to get from Firebase (project ID, service account key, admin password) and where to add it (`.env`, FlutterFire).

## Quick start (local)

1. **Emulators**: `./scripts/run_emulators.sh`
2. **Supply Engine**: `./scripts/run_supply_engine.sh`
3. **Ingest sample feed**: `FIRESTORE_EMULATOR_HOST=localhost:8180 ./scripts/ingest_sample_feed.sh`
4. **Flutter**: `./scripts/run_flutter_web.sh` (runs on **http://localhost:8080**; leave it running – edits hot-reload)

See [docs/RUNBOOK_LOCAL_DEV.md](docs/RUNBOOK_LOCAL_DEV.md) for full setup and env vars.

## Docs

### Product & Strategy
- [PRD](docs/PRD.md) – Product requirements
- [COMMERCIAL_STRATEGY](docs/COMMERCIAL_STRATEGY.md) – Monetization and retailer offerings
- [APP_FLOW](docs/APP_FLOW.md) – Screens and navigation
- [PROJECT_PLAN](docs/PROJECT_PLAN.md)
- [IMPLEMENTATION_PLAN](docs/IMPLEMENTATION_PLAN.md)

### Technical
- [ARCHITECTURE](docs/ARCHITECTURE.md)
- [BACKEND_STRUCTURE](docs/BACKEND_STRUCTURE.md)
- [DATA_MODEL](docs/DATA_MODEL.md)
- [TECH_STACK](docs/TECH_STACK.md)
- [FRONTEND_GUIDELINES](docs/FRONTEND_GUIDELINES.md)

### Operations
- [RUNBOOK_LOCAL_DEV](docs/RUNBOOK_LOCAL_DEV.md)
- [RUNBOOK_DEPLOYMENT](docs/RUNBOOK_DEPLOYMENT.md)
- [TESTING_LOCAL](docs/TESTING_LOCAL.md)
- [QA_DIAGNOSTICS_REPORT](docs/QA_DIAGNOSTICS_REPORT.md)

### Governance
- [ASSUMPTIONS](docs/ASSUMPTIONS.md)
- [DECISIONS](docs/DECISIONS.md)
- [INGESTION_COMPLIANCE](docs/INGESTION_COMPLIANCE.md)
- [SECURITY](docs/SECURITY.md)
- [PRIVACY_GDPR](docs/PRIVACY_GDPR.md)

## License

Proprietary.

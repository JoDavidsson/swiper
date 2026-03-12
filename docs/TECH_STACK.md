# Swiper – Tech Stack

> **Last updated:** 2026-02-02  
> Locked dependencies and versions. All AI code generation must use these exact versions.

---

## 1. Flutter Mobile/Web App

**Location:** `apps/Swiper_flutter/`

### SDK

| Dependency | Version | Purpose |
|------------|---------|---------|
| Flutter SDK | `>=3.2.0 <4.0.0` | Cross-platform UI framework |
| Dart SDK | `>=3.2.0 <4.0.0` | Language runtime |

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_riverpod` | `2.4.9` | State management |
| `riverpod_annotation` | `2.3.3` | Riverpod code generation |
| `go_router` | `13.0.0` | Declarative routing |
| `dio` | `5.4.0` | HTTP client |
| `hive` | `2.2.3` | Local NoSQL storage |
| `hive_flutter` | `1.1.0` | Hive Flutter integration |

### Firebase

| Package | Version | Purpose |
|---------|---------|---------|
| `firebase_core` | `3.6.0` | Firebase initialization |
| `firebase_auth` | `5.3.0` | Authentication (admin) |

### Authentication

| Package | Version | Purpose |
|---------|---------|---------|
| `google_sign_in` | `6.2.1` | Google OAuth (admin) |

### UI/UX

| Package | Version | Purpose |
|---------|---------|---------|
| `cached_network_image` | `3.3.1` | Image caching |
| `share_plus` | `7.2.1` | Native share sheet |
| `url_launcher` | `6.2.2` | Open external URLs |

### Utilities

| Package | Version | Purpose |
|---------|---------|---------|
| `uuid` | `4.2.2` | UUID v4 generation |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter_test` | SDK | Unit/widget testing |
| `integration_test` | SDK | Integration testing |
| `flutter_lints` | `3.0.1` | Lint rules |
| `build_runner` | `2.4.8` | Code generation |
| `riverpod_generator` | `2.3.9` | Riverpod code generation |

---

## 2. Firebase Cloud Functions (Backend)

**Location:** `firebase/functions/`

### Runtime

| Dependency | Version | Purpose |
|------------|---------|---------|
| Node.js | `20` | Runtime |
| TypeScript | `5.3.3` | Language |

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `firebase-admin` | `12.0.0` | Firestore, Auth SDK |
| `firebase-functions` | `4.5.0` | Cloud Functions framework |
| `nanoid` | `5.0.4` | Short unique IDs |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `@types/express` | `5.0.6` | Express types |
| `@types/jest` | `29.5.11` | Jest types |
| `jest` | `29.7.0` | Testing framework |
| `ts-jest` | `29.1.1` | TypeScript Jest transformer |

### Configuration

```json
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "target": "ES2022",
    "strict": true,
    "esModuleInterop": true
  },
  "engines": { "node": "20" }
}
```

---

## 3. Supply Engine (Python Service)

**Location:** `services/supply_engine/`

### Runtime

| Dependency | Version | Purpose |
|------------|---------|---------|
| Python | `3.11+` | Runtime |

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `fastapi` | `0.109.0` | Web framework |
| `uvicorn[standard]` | `0.27.0` | ASGI server |
| `httpx` | `0.26.0` | Async HTTP client |
| `firebase-admin` | `6.4.0` | Firestore client |
| `python-dotenv` | `1.0.0` | Environment variables |
| `pandas` | `2.2.0` | Data manipulation |
| `beautifulsoup4` | `4.12.3` | HTML parsing |
| `lxml` | `5.1.0` | XML/HTML parser backend |

### Dev Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `pytest` | `8.0.0` | Testing framework |

---

## 4. Firebase Services

| Service | Configuration |
|---------|---------------|
| **Firestore** | Default database, `europe-west1` |
| **Cloud Functions** | Gen2, `europe-west1` |
| **Hosting** | PWA deployment |
| **Storage** | Item images (optional) |
| **Auth** | Admin allowlist only |

### Emulator Ports (Local Dev)

| Service | Port |
|---------|------|
| Firestore | `8180` |
| Functions | `5002` |
| Hosting | `5010` |
| Emulator UI | `4100` |

---

## 5. External APIs & Services

| Service | Purpose | Notes |
|---------|---------|-------|
| Google Sign-In | Admin authentication | Web Client ID required |
| Retailer websites | Product data crawling | Static HTML only |

---

## 6. Infrastructure

### Deployment Targets

| Component | Platform | Notes |
|-----------|----------|-------|
| Flutter Web | Firebase Hosting | PWA |
| Flutter iOS | App Store | Future |
| Flutter Android | Play Store | Future |
| Cloud Functions | Firebase | Scales automatically |
| Supply Engine | Cloud Run | Manual deploy |

### CI/CD

| Tool | Configuration |
|------|---------------|
| GitHub Actions | `.github/workflows/ci.yml` |

```yaml
# ci.yml triggers
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

# Jobs: lint, test, build
```

---

## 7. Environment Variables

### Flutter App

| Variable | Description |
|----------|-------------|
| `API_BASE_URL` | Backend API URL |
| `FIREBASE_*` | Firebase config (from `firebase_options.dart`) |

### Cloud Functions

| Variable | Description | Default |
|----------|-------------|---------|
| `ADMIN_PASSWORD` | Legacy password auth | — |
| `SUPPLY_ENGINE_URL` | Supply Engine URL | `http://localhost:8081` |
| `DECK_RESPONSE_LIMIT` | Max items per deck response | `20` |
| `DECK_ITEMS_FETCH_LIMIT` | Max items fetched for ranking | `700` |
| `DECK_CANDIDATE_CAP` | Max candidates for ranker | `400` |
| `DECK_RANK_WINDOW_MULTIPLIER` | Score window multiplier (`limit * multiplier`) | `48` |
| `RANKER_EXPLORATION_RATE` | Exploration sampling rate | `0` |
| `RANKER_ENABLE_MMR_RERANK` | Enable MMR reranking | `false` |
| `DECK_RETRIEVAL_DOCS_CACHE_TTL_MS` | Retrieval-doc cache TTL (ms) | `15000` |
| `RANKER_EXPLORATION_SEED` | Random seed for exploration | — |

### Supply Engine

| Variable | Description | Default |
|----------|-------------|---------|
| `FIRESTORE_EMULATOR_HOST` | Emulator host | — |
| `GOOGLE_APPLICATION_CREDENTIALS` | Service account JSON path | — |
| `PORT` | Server port | `8081` |

---

## 8. Locked Configuration Files

### `pubspec.yaml` (Flutter)

```yaml
environment:
  sdk: '>=3.2.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.4.9
  go_router: ^13.0.0
  dio: ^5.4.0
  hive: ^2.2.3
  hive_flutter: ^1.1.0
  firebase_core: ^3.6.0
  firebase_auth: ^5.3.0
  google_sign_in: ^6.2.1
  cached_network_image: ^3.3.1
  share_plus: ^7.2.1
  url_launcher: ^6.2.2
  uuid: ^4.2.2
```

### `package.json` (Functions)

```json
{
  "engines": { "node": "20" },
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^4.5.0",
    "nanoid": "^5.0.4"
  },
  "devDependencies": {
    "typescript": "^5.3.3",
    "jest": "^29.7.0",
    "ts-jest": "^29.1.1"
  }
}
```

### `requirements.txt` (Supply Engine)

```
fastapi==0.109.0
uvicorn[standard]==0.27.0
httpx==0.26.0
firebase-admin==6.4.0
python-dotenv==1.0.0
pandas==2.2.0
beautifulsoup4==4.12.3
lxml==5.1.0
```

---

## 9. Version Upgrade Policy

1. **No upgrades without explicit approval** – AI must use locked versions
2. **Security patches** – May upgrade patch versions (e.g., `5.3.3` → `5.3.4`)
3. **Minor/major upgrades** – Require manual review and testing
4. **Breaking changes** – Document in CHANGELOG before merging

---

## References

- [RUNBOOK_LOCAL_DEV.md](RUNBOOK_LOCAL_DEV.md) – Local setup
- [RUNBOOK_DEPLOYMENT.md](RUNBOOK_DEPLOYMENT.md) – Deployment
- [ARCHITECTURE.md](ARCHITECTURE.md) – System architecture

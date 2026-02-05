# Swiper – Architecture

## High-level

```
+----------+     +------------------+     +----------------+
| Flutter  |     | Firebase         |     | Supply Engine  |
| App      |---->| Hosting +        |<----| (FastAPI)      |
| (PWA)    |     | Functions +      |     | Feed/Crawl     |
|          |     | Firestore        |     | Ingestion      |
+----------+     +------------------+     +----------------+
       |                  |                        |
       v                  v                        v
   /deck, /likes,     /api/*, /go/*           items, runs,
   /s/:token         Firestore writes        jobs
```

- **Flutter**: Single codebase (iOS, Android, Web PWA). `go_router` for app + `/admin/*` and `/s/:token`. Web build deployed to Firebase Hosting.
- **Firebase**: Firestore = primary DB; Cloud Functions = REST API (`/api/*`) + redirect (`/go/:itemId`); Hosting serves Flutter web and rewrites to Functions.
- **Supply Engine**: Python FastAPI; reads sources from config (or Firestore); runs feed/crawl jobs; writes `items`, `ingestionRuns`, `ingestionJobs`. Triggered via `POST /admin/run` (Functions call Supply Engine).
  - Crawl ingestion now includes **URL discovery (robots/sitemaps + bounded category crawl)**, **extraction cascade (JSON-LD → embedded JSON → recipe → semantic DOM)**, **snapshots/failures**, and **daily metrics + drift triggers**. P1 extracts **dimensions, material, color** for ranker parity with feed items (size class from width, title-based color inference when no structured data).

## Data flow

1. User opens app → `POST /api/session` → store `sessionId` locally.
2. Deck → `GET /api/items/deck?sessionId=...` → ranked items (exclude seen, apply preference weights).
3. Swipe → `POST /api/swipe` → record swipe, update preference weights, log event.
4. Like → `POST /api/likes/toggle` → add/remove like, log event.
5. Share → `POST /api/shortlists/create` → return `shareToken` → link `/s/:token`.
6. Outbound → open `https://<host>/go/:itemId` → Function logs `outbound_click`, 302 to `outboundUrl` with UTM.

## Mermaid

```mermaid
flowchart LR
  subgraph client [Client]
    FlutterApp[Flutter App]
    AdminWeb[Admin Web]
  end
  subgraph firebase [Firebase]
    Hosting[Hosting]
    Functions[Cloud Functions]
    Firestore[(Firestore)]
    Storage[Storage]
  end
  subgraph supply [Supply Engine]
    FastAPI[FastAPI]
    Feed[Feed Ingestion]
    Crawl[Locator+Crawl Ingestion]
    Extract[Extractor Cascade]
    Recipes[Recipes+Runner]
    Monitor[Metrics+Drift]
  end
  FlutterApp --> Hosting
  AdminWeb --> Hosting
  Hosting --> Functions
  FlutterApp --> Functions
  Functions --> Firestore
  Functions --> Storage
  FastAPI --> Firestore
  Feed --> FastAPI
  Crawl --> FastAPI
  Extract --> FastAPI
  Recipes --> FastAPI
  Monitor --> FastAPI
```

## Supply Engine crawl state (Firestore)

In addition to writing user-facing inventory to `items`, crawl ingestion writes operational state:

- `crawlUrls`: discovered URL candidates (confidence, urlType, status, first/last seen)
- `productSnapshots`: extraction history per canonical URL (snapshot JSON + hash)
- `crawlRecipes`: versioned extraction recipes (draft/active/deprecated)
- `extractionFailures`: fetch/parse/validate failures + small signals packet
- `metricsDaily`: daily success/completeness and strategy usage rates

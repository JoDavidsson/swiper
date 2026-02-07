# Swiper – Backend Structure

> **Last updated:** 2026-02-07  
> Complete database schema, API contracts, and service architecture.

---

## 1. Architecture Overview

```
┌─────────────────┐     ┌─────────────────────────────────────┐
│  Flutter App    │────▶│  Firebase Cloud Functions (API)     │
└─────────────────┘     │  • /api/session, /api/items/deck    │
                        │  • /api/swipe, /api/likes, /api/*   │
                        │  • /admin/*, /retailer/*            │
                        └───────────────┬─────────────────────┘
                                        │
                                        ▼
                        ┌─────────────────────────────────────┐
                        │          Firestore Database          │
                        │  • items, swipes, likes, shortlists │
                        │  • anonSessions, users, events_v1   │
                        │  • decisionRooms, votes, comments   │
                        │  • retailers, campaigns, segments   │
                        │  • scores, ingestionRuns            │
                        └───────────────┬─────────────────────┘
                                        │
        ┌───────────────────────────────┴──────────────────────┐
        ▼                                                      ▼
┌───────────────────┐                              ┌───────────────────┐
│  Supply Engine    │                              │  Score Calculator │
│  (Python/FastAPI) │                              │  (Scheduled Job)  │
│  • Crawl websites │                              │  • Confidence     │
│  • Extract data   │                              │    Score compute  │
│  • Write items    │                              │  • Reason codes   │
└───────────────────┘                              └───────────────────┘
```

---

## 2. Firestore Collections

### 2.1 `items` – Product Catalog

Primary collection for all furniture products.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID, nanoid |
| `sourceId` | `string` | ✓ | External product ID |
| `sourceUrl` | `string` | ✓ | Product page URL |
| `title` | `string` | ✓ | Product name |
| `priceAmount` | `number` | ✓ | Price amount |
| `priceCurrency` | `string` | ✓ | Currency (typically SEK) |
| `images` | `string[]` | ✓ | Image URLs (first is primary) |
| `retailer` | `string` | ✓ | Retailer slug |
| `isActive` | `boolean` | ✓ | Visible in deck |
| `styleTags` | `string[]` | — | Style descriptors |
| `material` | `string` | — | Normalized material |
| `colorFamily` | `string` | — | Normalized color |
| `sizeClass` | `string` | — | `small` / `medium` / `large` |
| `dimensionsCm` | `object` | — | `{w, h, d}` in cm |
| `extractionMeta` | `object` | — | Extraction quality metadata `{method, extractorMethod, completeness, missingFields[], fetchMethod, extractedAt}` |
| `firstSeenAt` | `timestamp` | ✓ | First ingestion time |
| `lastUpdatedAt` | `timestamp` | ✓ | Last update time |
| `lastSeenAt` | `timestamp` | ✓ | Last crawl/seen time |

**Indexes:**

```json
{
  "collectionGroup": "items",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "isActive", "order": "ASCENDING" },
    { "fieldPath": "lastUpdatedAt", "order": "DESCENDING" }
  ]
}
```

### 2.2 `anonSessions` – Anonymous User Sessions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID, nanoid |
| `deviceFingerprint` | `string` | — | Optional device ID |
| `createdAt` | `timestamp` | ✓ | Session start |
| `lastSeenAt` | `timestamp` | ✓ | Last activity |
| `swipeCount` | `number` | — | Total swipes |
| `likeCount` | `number` | — | Total likes |
| `analyticsOptOut` | `boolean` | — | GDPR opt-out flag |
| `userId` | `string` | — | Linked user account (if migrated) |

### 2.3 `users` – Authenticated User Accounts

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID = Firebase Auth UID |
| `email` | `string` | ✓ | User email |
| `displayName` | `string` | — | Display name |
| `photoUrl` | `string` | — | Profile photo URL |
| `linkedSessionIds` | `string[]` | — | Migrated anonymous sessions |
| `createdAt` | `timestamp` | ✓ | Account creation time |
| `lastActiveAt` | `timestamp` | ✓ | Last activity |

### 2.4 `swipes` – Swipe Events

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `sessionId` | `string` | ✓ | Reference to `anonSessions` |
| `itemId` | `string` | ✓ | Reference to `items` |
| `direction` | `string` | ✓ | `left` / `right` |
| `positionInDeck` | `number` | — | Position when swiped |
| `createdAt` | `timestamp` | ✓ | Swipe timestamp |

**Indexes:**

```json
{
  "collectionGroup": "swipes",
  "fields": [
    { "fieldPath": "sessionId", "order": "ASCENDING" },
    { "fieldPath": "createdAt", "order": "DESCENDING" }
  ]
}
```

### 2.5 `likes` – Liked Items (Denormalized)

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `sessionId` | `string` | ✓ | Reference to `anonSessions` |
| `itemId` | `string` | ✓ | Reference to `items` |
| `createdAt` | `timestamp` | ✓ | Like timestamp |

### 2.6 `shortlists` – Shareable Lists

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID (short code) |
| `sessionId` | `string` | ✓ | Creator session |
| `itemIds` | `string[]` | ✓ | Ordered item IDs |
| `createdAt` | `timestamp` | ✓ | Creation time |
| `expiresAt` | `timestamp` | — | Optional expiry |
| `viewCount` | `number` | — | Times viewed |
| `decisionRoomId` | `string` | — | Linked Decision Room (if created) |

### 2.7 `decisionRooms` – Collaborative Decision Rooms

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID (short code) |
| `creatorUserId` | `string` | ✓ | User who created the room |
| `title` | `string` | — | Optional room title |
| `itemIds` | `string[]` | ✓ | Items in the room |
| `finalistIds` | `string[]` | — | Final 2 items (when selected) |
| `status` | `string` | ✓ | `open` / `finalists` / `decided` |
| `createdAt` | `timestamp` | ✓ | Creation time |
| `updatedAt` | `timestamp` | ✓ | Last update |
| `participantCount` | `number` | — | Number of participants |

### 2.8 `decisionRoomItems` – Items Within a Decision Room

Subcollection under `decisionRooms/{roomId}/items`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID = item ID |
| `itemId` | `string` | ✓ | Reference to `items` |
| `addedBy` | `string` | ✓ | User ID who added (creator or suggester) |
| `isSuggested` | `boolean` | ✓ | True if added via "suggest alternative" |
| `suggestedUrl` | `string` | — | Original URL if suggested from external |
| `voteCountUp` | `number` | ✓ | Upvote count |
| `voteCountDown` | `number` | ✓ | Downvote count |
| `addedAt` | `timestamp` | ✓ | When added to room |

### 2.9 `votes` – Decision Room Votes

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `roomId` | `string` | ✓ | Reference to `decisionRooms` |
| `itemId` | `string` | ✓ | Reference to item in room |
| `userId` | `string` | ✓ | Voter user ID |
| `vote` | `string` | ✓ | `up` / `down` |
| `createdAt` | `timestamp` | ✓ | Vote timestamp |

**Indexes:**

```json
{
  "collectionGroup": "votes",
  "fields": [
    { "fieldPath": "roomId", "order": "ASCENDING" },
    { "fieldPath": "userId", "order": "ASCENDING" }
  ]
}
```

### 2.10 `comments` – Decision Room Comments

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `roomId` | `string` | ✓ | Reference to `decisionRooms` |
| `itemId` | `string` | — | Optional item reference (for per-item comments) |
| `userId` | `string` | ✓ | Author user ID |
| `text` | `string` | ✓ | Comment text |
| `createdAt` | `timestamp` | ✓ | Comment timestamp |

### 2.11 `retailers` – Retailer Accounts

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID (slug) |
| `name` | `string` | ✓ | Display name |
| `domain` | `string` | ✓ | Website domain |
| `logoUrl` | `string` | — | Logo image URL |
| `ownerUserIds` | `string[]` | ✓ | Users with admin access |
| `status` | `string` | ✓ | `claimed` / `pending` / `active` |
| `createdAt` | `timestamp` | ✓ | Creation time |
| `updatedAt` | `timestamp` | ✓ | Last update |

### 2.12 `segments` – Targeting Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `name` | `string` | ✓ | Segment name |
| `isTemplate` | `boolean` | ✓ | True if system-provided template |
| `styleTags` | `string[]` | — | Target style tags |
| `budgetMin` | `number` | — | Min price SEK |
| `budgetMax` | `number` | — | Max price SEK |
| `sizeClasses` | `string[]` | — | Target size classes |
| `geoRegion` | `string` | — | Geographic region |
| `geoCity` | `string` | — | City (v2) |
| `geoPostcodes` | `string[]` | — | Postcode clusters (v2) |
| `retailerId` | `string` | — | Owning retailer (null for templates) |
| `createdAt` | `timestamp` | ✓ | Creation time |

### 2.13 `campaigns` – Featured Distribution Campaigns

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `retailerId` | `string` | ✓ | Owning retailer |
| `name` | `string` | ✓ | Campaign name |
| `segmentId` | `string` | ✓ | Target segment |
| `productIds` | `string[]` | — | Specific products (null = auto-select) |
| `productMode` | `string` | ✓ | `manual` / `recommended` |
| `budgetTotal` | `number` | ✓ | Total budget SEK |
| `budgetDaily` | `number` | ✓ | Daily budget SEK |
| `budgetSpent` | `number` | ✓ | Spent so far |
| `startDate` | `timestamp` | ✓ | Campaign start |
| `endDate` | `timestamp` | ✓ | Campaign end |
| `status` | `string` | ✓ | `draft` / `active` / `paused` / `completed` |
| `frequencyCap` | `number` | ✓ | Max featured per N cards (default 12) |
| `maxImpressionShare` | `number` | — | Max % of segment impressions |
| `excludedProductIds` | `string[]` | — | Excluded products |
| `createdAt` | `timestamp` | ✓ | Creation time |
| `updatedAt` | `timestamp` | ✓ | Last update |

### 2.14 `scores` – Confidence Scores

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID = `{productId}_{segmentId}` |
| `productId` | `string` | ✓ | Product reference |
| `segmentId` | `string` | ✓ | Segment reference (or `_global`) |
| `window` | `string` | ✓ | `7d` / `1d` / `28d` |
| `impressions` | `number` | ✓ | Total impressions in window |
| `saves` | `number` | ✓ | Save count |
| `shares` | `number` | ✓ | Share count |
| `compares` | `number` | ✓ | Compare/finalists count |
| `returns` | `number` | ✓ | Return session count |
| `dwellHits` | `number` | ✓ | Dwell above threshold |
| `outboundClicks` | `number` | — | Optional click count |
| `rawScore` | `number` | ✓ | Raw weighted score |
| `smoothedScore` | `number` | ✓ | After Bayesian smoothing |
| `score` | `number` | ✓ | Final 0–100 score |
| `band` | `string` | ✓ | `green` / `yellow` / `red` |
| `reasonCodes` | `string[]` | ✓ | Top 2–3 reason codes |
| `lowData` | `boolean` | ✓ | True if below threshold |
| `calculatedAt` | `timestamp` | ✓ | Calculation time |

### 2.15 `events_v1` – Analytics Events

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `sessionId` | `string` | ✓ | Session reference |
| `eventType` | `string` | ✓ | Event name (see EVENT_SCHEMA_V1) |
| `eventData` | `object` | — | Event-specific payload |
| `clientTimestamp` | `timestamp` | ✓ | Client-side time |
| `serverTimestamp` | `timestamp` | ✓ | Server-side time |
| `appVersion` | `string` | — | App version string |
| `platform` | `string` | — | `ios` / `android` / `web` |

### 2.16 `ingestionRuns` – Crawl Run Logs

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `sourceId` | `string` | ✓ | Source slug |
| `status` | `string` | ✓ | `pending`/`running`/`completed`/`failed` |
| `itemsCreated` | `number` | — | New items |
| `itemsUpdated` | `number` | — | Updated items |
| `itemsSkipped` | `number` | — | Skipped items |
| `errors` | `string[]` | — | Error messages |
| `startedAt` | `timestamp` | ✓ | Run start |
| `completedAt` | `timestamp` | — | Run end |
| `triggeredBy` | `string` | — | `scheduled` / `manual` / `admin` |

### 2.17 `crawlRecipes` – Custom Extraction Rules

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID |
| `domain` | `string` | ✓ | Target domain |
| `urlPattern` | `string` | — | URL regex pattern |
| `selectors` | `object` | ✓ | CSS/XPath selectors |
| `transforms` | `object[]` | — | Post-extraction transforms |
| `priority` | `number` | — | Match priority (higher wins) |
| `active` | `boolean` | ✓ | Recipe enabled |
| `createdAt` | `timestamp` | ✓ | Creation time |
| `updatedAt` | `timestamp` | ✓ | Last update |

### 2.18 `curatedOnboardingSofas` – Gold Card Curated Items

Admin-managed collection of sofas for the visual gold card.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID = item ID |
| `order` | `number` | ✓ | Display order (0-5) |
| `addedAt` | `timestamp` | ✓ | When added to curated list |

### 2.19 `onboardingPicks` – User's Gold Card Selections

Stores user's visual picks and budget from progressive onboarding.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID = session ID |
| `pickedItemIds` | `string[]` | ✓ | Selected sofa IDs (3) |
| `budgetMin` | `number` | — | Budget minimum SEK |
| `budgetMax` | `number` | — | Budget maximum SEK |
| `pickHash` | `string` | ✓ | Sorted item IDs joined |
| `extractedAttributes` | `object` | ✓ | Aggregated attributes from picks |
| `createdAt` | `timestamp` | ✓ | First submission time |
| `updatedAt` | `timestamp` | ✓ | Last update time |

### 2.20 `personaSignals` – Collaborative Filtering Signals

Precomputed signals from users with similar onboarding picks.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | `string` | ✓ | Document ID = pick hash |
| `pickHash` | `string` | ✓ | Sorted item IDs joined |
| `userCount` | `number` | ✓ | Users with this pick pattern |
| `itemScores` | `object` | ✓ | Item ID → like frequency |
| `topItems` | `string[]` | ✓ | Top 20 liked items |
| `updatedAt` | `timestamp` | ✓ | Last aggregation time |

### 2.21 `goldItems` – Serve-Ready Items (Phase 11d)

Items that have been classified and accepted by the sorting engine. The deck reads from this collection first.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | `string` | ✓ | Matches items collection doc ID |
| `eligibleSurfaces` | `string[]` | ✓ | Surface IDs where item is accepted |
| `predictedCategory` | `string` | ✓ | Category from classifier |
| `categoryConfidence` | `number` | ✓ | Classification confidence 0.0-1.0 |
| `classificationVersion` | `number` | ✓ | Version of classification model |
| `policyVersion` | `number` | ✓ | Version of eligibility policy |
| `decisions` | `object` | ✓ | Per-surface ACCEPT/REJECT/UNCERTAIN with reason codes |
| `humanVerified` | `boolean` | | True if reviewer manually accepted |
| `promotedAt` | `string` | ✓ | ISO timestamp of promotion |
| `isActive` | `boolean` | ✓ | Whether shown in deck |
| (plus essential item fields for fast reads: title, brand, price, images, etc.) | | | |

### 2.22 `reviewQueue` – Uncertain Items (Phase 11d)

Items that the classifier is uncertain about, awaiting human review.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | `string` | ✓ | Matches items collection doc ID |
| `classification` | `object` | ✓ | Full classification result |
| `decisions` | `object` | ✓ | Per-surface decisions |
| `status` | `string` | ✓ | "pending" or "reviewed" |
| `reviewedBy` | `string` | | Reviewer ID |
| `reviewAction` | `string` | | "accept", "reject", or "reclassify" |
| `createdAt` | `string` | ✓ | ISO timestamp |

### 2.23 `reviewerLabels` – Training Data (Phase 11d)

Stores reviewer decisions as training data for future model calibration.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `itemId` | `string` | ✓ | Item that was reviewed |
| `action` | `string` | ✓ | "accept", "reject", "reclassify" |
| `correctCategory` | `string` | | If reclassified, the correct category |
| `reason` | `string` | | Reviewer's reason |
| `reviewerId` | `string` | ✓ | Who reviewed |
| `originalClassification` | `object` | ✓ | Classification at review time |
| `createdAt` | `string` | ✓ | ISO timestamp |

### 2.24 `calibrationRuns` – Threshold Calibration History (Phase 11d)

Records of calibration runs that adjust classification thresholds.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `totalLabels` | `number` | ✓ | Labels used for calibration |
| `accuracyBefore` | `number` | ✓ | Accuracy before adjustment |
| `accuracyAfter` | `number` | ✓ | Accuracy after adjustment |
| `thresholdAdjustments` | `object` | ✓ | Old vs new thresholds |
| `calibratedAt` | `string` | ✓ | ISO timestamp |

### 2.25 `sources` – Crawl Config (Quality Fields)

Additional crawl-source fields used by Supply Engine quality controls.

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `useBrowserFallback` | `boolean` | — | Enable Playwright fallback for JS-rendered pages (default `false`) |
| `enableQualityRefetch` | `boolean` | — | Optional second-pass refetch for stale low-completeness items |
| `qualityRefetchLimit` | `number` | — | Max low-quality items to refetch per run (default `100`) |

---

## 3. Firestore Security Rules

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Items: read-only for all, write via admin/functions
    match /items/{itemId} {
      allow read: if true;
      allow write: if false;
    }
    
    // Sessions: create own, read/update own
    match /anonSessions/{sessionId} {
      allow create: if true;
      allow read, update: if request.auth == null || 
                            resource.data.id == request.resource.data.id;
      allow delete: if false;
    }
    
    // Users: authenticated users can read/update own
    match /users/{userId} {
      allow read, update: if request.auth != null && request.auth.uid == userId;
      allow create: if request.auth != null && request.auth.uid == userId;
      allow delete: if false;
    }
    
    // Swipes: create for own session
    match /swipes/{swipeId} {
      allow create: if request.resource.data.sessionId != null;
      allow read: if resource.data.sessionId == request.resource.data.sessionId;
      allow update, delete: if false;
    }
    
    // Likes: manage for own session
    match /likes/{likeId} {
      allow create, read: if request.resource.data.sessionId != null;
      allow delete: if resource.data.sessionId == request.resource.data.sessionId;
      allow update: if false;
    }
    
    // Shortlists: public read, create for own session
    match /shortlists/{listId} {
      allow read: if true;
      allow create: if request.resource.data.sessionId != null;
      allow update, delete: if false;
    }
    
    // Decision Rooms: public read, create requires auth
    match /decisionRooms/{roomId} {
      allow read: if true;
      allow create: if request.auth != null;
      allow update: if request.auth != null && 
                      resource.data.creatorUserId == request.auth.uid;
      allow delete: if false;
    }
    
    // Votes: authenticated users only
    match /votes/{voteId} {
      allow read: if true;
      allow create, update: if request.auth != null && 
                              request.resource.data.userId == request.auth.uid;
      allow delete: if false;
    }
    
    // Comments: authenticated users only
    match /comments/{commentId} {
      allow read: if true;
      allow create: if request.auth != null && 
                      request.resource.data.userId == request.auth.uid;
      allow update, delete: if false;
    }
    
    // Events: write-only
    match /events_v1/{eventId} {
      allow create: if true;
      allow read, update, delete: if false;
    }
    
    // Admin/retailer collections: functions only
    match /retailers/{retailerId} {
      allow read, write: if false;
    }
    match /campaigns/{campaignId} {
      allow read, write: if false;
    }
    match /segments/{segmentId} {
      allow read, write: if false;
    }
    match /scores/{scoreId} {
      allow read, write: if false;
    }
    match /ingestionRuns/{runId} {
      allow read, write: if false;
    }
    match /crawlRecipes/{recipeId} {
      allow read, write: if false;
    }
    // Sorting engine collections (Phase 11d)
    match /goldItems/{itemId} {
      allow read, write: if false;
    }
    match /reviewQueue/{itemId} {
      allow read, write: if false;
    }
    match /reviewerLabels/{labelId} {
      allow read, write: if false;
    }
    match /calibrationRuns/{runId} {
      allow read, write: if false;
    }
  }
}
```

---

## 4. API Endpoints (Cloud Functions)

Base URL:

- Emulator: `http://127.0.0.1:5002/{projectId}/{region}`
- API path prefix: `/api/*`

### 4.1 Public Endpoints

#### `POST /api/session`

Create anonymous session.

**Request:**
```json
{
  "locale": "sv-SE",
  "platform": "web",
  "screenBucket": "mobile",
  "timezoneOffsetMinutes": 60
}
```

**Response:**
```json
{
  "sessionId": "abc123"
}
```

#### `GET /api/items/deck`

Get ranked items for swiping.

**Query Params:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `sessionId` | `string` | — | Required |
| `limit` | `number` | `30` | Max items |
| `filters` | `json-string` | — | Optional serialized filters |
| `requestId` | `string` | auto | Optional caller-provided request id |
| `debug` | `boolean` | `false` | Include debug block |

**Response:**
```json
{
  "requestId": "deck_...",
  "items": [
    {
      "id": "item123",
      "title": "STOCKHOLM Sofa",
      "priceAmount": 14995,
      "priceCurrency": "SEK",
      "images": ["https://..."],
      "retailer": "ikea",
      "sourceUrl": "https://ikea.com/...",
      "styleTags": ["scandinavian", "modern"],
      "material": "leather",
      "colorFamily": "brown",
      "sizeClass": "large"
    }
  ],
  "rank": {
    "rankerRunId": "run_...",
    "algorithmVersion": "preference_weights_v1",
    "candidateCount": 300,
    "rankWindow": 300,
    "retrievalQueues": ["preference_match", "fresh_catalog"],
    "itemIds": ["item123", "item456"]
  },
  "itemScores": {
    "item123": 1.42
  }
}
```

#### `POST /api/swipe`

Record a swipe action.

**Request:**
```json
{
  "sessionId": "abc123",
  "itemId": "item456",
  "direction": "right",
  "positionInDeck": 0
}
```

**Response:**
```json
{
  "ok": true
}
```

#### `GET /api/likes`

Get user's liked items.

**Query Params:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `sessionId` | `string` | — | Required |

**Response:**
```json
{
  "items": [...]
}
```

#### `POST /api/likes/toggle`

Toggle like for an item.

**Request:**
```json
{
  "sessionId": "abc123",
  "itemId": "item456"
}
```

**Response:**
```json
{
  "liked": true
}
```

#### `POST /api/shortlists/create`

Create shareable shortlist.

**Request:**
```json
{
  "sessionId": "abc123",
  "itemIds": ["item1", "item2", "item3"]
}
```

**Response:**
```json
{
  "shortlistId": "xyz789",
  "shareToken": "abcXYZ..."
}
```

#### `GET /api/shortlists/byToken/{shareToken}`

Get shortlist by ID (public).

**Response:**
```json
{
  "shortlistId": "xyz789",
  "shareToken": "abcXYZ...",
  "items": [...],
  "createdAt": "2026-02-02T12:00:00Z"
}
```

### 4.2 Decision Room Endpoints

#### `POST /decision-rooms` (Auth Required)

Create a new Decision Room.

**Request:**
```json
{
  "itemIds": ["item1", "item2", "item3"],
  "title": "Our sofa hunt"
}
```

**Response:**
```json
{
  "id": "room123",
  "shareUrl": "https://swiper.app/r/room123"
}
```

#### `GET /decision-rooms/{id}` (Public)

Get Decision Room details.

**Response:**
```json
{
  "id": "room123",
  "title": "Our sofa hunt",
  "status": "open",
  "items": [
    {
      "id": "item1",
      "title": "...",
      "images": [...],
      "voteCountUp": 3,
      "voteCountDown": 1,
      "isSuggested": false
    }
  ],
  "finalistIds": [],
  "participantCount": 2,
  "createdAt": "2026-02-05T12:00:00Z"
}
```

#### `POST /decision-rooms/{id}/vote` (Auth Required)

Vote on an item.

**Request:**
```json
{
  "itemId": "item1",
  "vote": "up"
}
```

**Response:**
```json
{
  "success": true,
  "voteCountUp": 4,
  "voteCountDown": 1
}
```

#### `POST /decision-rooms/{id}/comment` (Auth Required)

Add a comment.

**Request:**
```json
{
  "text": "I love this one!",
  "itemId": null
}
```

**Response:**
```json
{
  "id": "comment123",
  "createdAt": "2026-02-05T12:30:00Z"
}
```

#### `GET /decision-rooms/{id}/comments` (Public)

Get comments for a room.

**Response:**
```json
{
  "comments": [
    {
      "id": "comment123",
      "text": "I love this one!",
      "userId": "user456",
      "displayName": "Anna",
      "itemId": null,
      "createdAt": "2026-02-05T12:30:00Z"
    }
  ]
}
```

#### `POST /decision-rooms/{id}/suggest` (Auth Required)

Suggest an alternative.

**Request:**
```json
{
  "url": "https://retailer.com/product/123"
}
```

**Response:**
```json
{
  "success": true,
  "itemId": "suggested123"
}
```

#### `POST /decision-rooms/{id}/finalists` (Auth Required, Creator Only)

Set finalists.

**Request:**
```json
{
  "finalistIds": ["item1", "item3"]
}
```

**Response:**
```json
{
  "success": true,
  "status": "finalists"
}
```

### 4.3 Outbound Redirect

#### `GET /go/{itemId}`

Redirect to retailer site with tracking.

**Query Params:**
| Param | Type | Description |
|-------|------|-------------|
| `sessionId` | `string` | Required |
| `ref` | `string` | Source (detail, shortlist, etc.) |

**Behavior:**
1. Generate `swp_click_id` (UUID)
2. Log outbound_click event
3. 302 redirect to retailer URL with:
   - `utm_source=swiper`
   - `utm_medium=discovery`
   - `utm_campaign={retailer_slug}`
   - `swp_click_id={uuid}`
   - `swp_seg={segment_slug}` (if applicable)
   - `swp_score_band={green|yellow|red}` (if applicable)

### 4.4 Events Endpoints

#### `POST /events`

Record single analytics event.

**Request:**
```json
{
  "sessionId": "abc123",
  "eventType": "card_view",
  "eventData": { "itemId": "item456", "isFeatured": false },
  "clientTimestamp": "2026-02-02T12:00:00Z"
}
```

#### `POST /events/batch`

Record multiple events.

**Request:**
```json
{
  "sessionId": "abc123",
  "events": [
    { "eventType": "card_view", "eventData": {...}, "clientTimestamp": "..." },
    { "eventType": "swipe", "eventData": {...}, "clientTimestamp": "..." }
  ]
}
```

### 4.5 Onboarding Endpoints

#### `GET /onboarding/curated-sofas`

Get curated sofas for visual gold card.

**Response:**
```json
{
  "sofas": [
    {
      "id": "sofa123",
      "imageUrl": "https://...",
      "styleTags": ["scandinavian", "modern"],
      "material": "leather",
      "colorFamily": "brown"
    }
  ]
}
```

#### `POST /onboarding/picks`

Store user's gold card selections.

**Request:**
```json
{
  "sessionId": "abc123",
  "pickedItemIds": ["item1", "item2", "item3"],
  "budgetMin": 5000,
  "budgetMax": 15000
}
```

**Response:**
```json
{
  "ok": true,
  "pickHash": "item1-item2-item3"
}
```

#### `GET /onboarding/picks`

Get user's gold card selections.

**Query Params:**
| Param | Type | Description |
|-------|------|-------------|
| `sessionId` | `string` | Required |

**Response:**
```json
{
  "picks": {
    "pickedItemIds": ["item1", "item2", "item3"],
    "budgetMin": 5000,
    "budgetMax": 15000,
    "pickHash": "item1-item2-item3",
    "extractedAttributes": {
      "styleTags": ["scandinavian"],
      "materials": ["leather"],
      "colorFamilies": ["brown"]
    }
  }
}
```

### 4.6 Admin Endpoints

All admin endpoints require authentication header:

```
Authorization: Bearer {google-id-token}
```

Or legacy password:

```
X-Admin-Password: {password}
```

*See existing admin endpoints in original docs.*

### 4.7 Retailer Console Endpoints

All retailer endpoints require authentication.

#### `GET /retailer/me`

Get current retailer profile.

**Response:**
```json
{
  "id": "ikea",
  "name": "IKEA Sweden",
  "domain": "ikea.com",
  "logoUrl": "...",
  "status": "active"
}
```

#### `GET /retailer/campaigns`

List retailer's campaigns.

**Response:**
```json
{
  "campaigns": [
    {
      "id": "camp123",
      "name": "Spring Collection",
      "segmentId": "seg456",
      "status": "active",
      "budgetTotal": 50000,
      "budgetSpent": 12500,
      "startDate": "2026-02-01",
      "endDate": "2026-02-28"
    }
  ]
}
```

#### `POST /retailer/campaigns`

Create a new campaign.

**Request:**
```json
{
  "name": "Spring Collection",
  "segmentId": "seg456",
  "productIds": ["prod1", "prod2"],
  "productMode": "manual",
  "budgetTotal": 50000,
  "budgetDaily": 2500,
  "startDate": "2026-02-01",
  "endDate": "2026-02-28",
  "frequencyCap": 12
}
```

#### `PATCH /retailer/campaigns/{id}`

Update a campaign.

#### `POST /retailer/campaigns/{id}/pause`

Pause a campaign.

#### `GET /retailer/catalog`

List retailer's products with scores.

**Response:**
```json
{
  "products": [
    {
      "id": "prod123",
      "title": "STOCKHOLM Sofa",
      "images": [...],
      "priceAmount": 14995,
      "included": true,
      "score": {
        "value": 87.3,
        "band": "green",
        "reasonCodes": ["Strong saves", "High share rate"],
        "impressions": 3240,
        "lowData": false
      }
    }
  ]
}
```

#### `PATCH /retailer/catalog/{productId}`

Update product inclusion.

**Request:**
```json
{
  "included": false
}
```

#### `GET /retailer/insights`

Get Insights Feed cards.

**Response:**
```json
{
  "insights": [
    {
      "type": "winner",
      "title": "These SKUs are performing well",
      "description": "5 products have Confidence Score > 80 in Stockholm segment",
      "productIds": ["prod1", "prod2", "prod3"],
      "action": {
        "label": "Boost budget",
        "type": "boost_campaign",
        "campaignId": "camp123"
      }
    },
    {
      "type": "needs_help",
      "title": "High impressions, low saves",
      "description": "3 products have high visibility but aren't converting",
      "productIds": ["prod4", "prod5", "prod6"],
      "action": {
        "label": "Pause or replace",
        "type": "edit_campaign"
      }
    }
  ]
}
```

#### `GET /retailer/trends`

Get trend data.

**Response:**
```json
{
  "trends": {
    "rising": [
      { "type": "style", "value": "bouclé", "change": "+23%" },
      { "type": "material", "value": "velvet", "change": "+15%" }
    ],
    "falling": [
      { "type": "color", "value": "black", "change": "-8%" }
    ],
    "priceMovement": {
      "direction": "up",
      "hotBand": "8000-12000"
    }
  },
  "region": "sweden"
}
```

#### `GET /retailer/reports`

Get reporting data.

**Response:**
```json
{
  "period": "2026-02-01/2026-02-05",
  "spend": 12500,
  "impressions": 45000,
  "featuredImpressions": 3750,
  "confidenceOutcomes": 892,
  "cpScore": 14.01,
  "bySegment": [
    {
      "segmentId": "seg456",
      "impressions": 25000,
      "outcomes": 534,
      "cpScore": 11.61
    }
  ],
  "byProduct": [...]
}
```

#### `GET /retailer/reports/export`

Export report as CSV.

#### `POST /retailer/reports/share`

Generate shareable report link.

**Response:**
```json
{
  "shareUrl": "https://swiper.app/reports/abc123"
}
```

---

## 5. Confidence Score Specification

### 5.1 Time Windows

Compute scores on rolling windows:
- Default: **7-day rolling**
- Also store 1-day and 28-day for trend visualization

### 5.2 Inputs (Per product_id × segment_id × window)

| Field | Description |
|-------|-------------|
| `impressions` | Number of times card was shown |
| `saves` | Saved to shortlist/board |
| `shares` | Share initiated from product |
| `compares` | Compare/finalists events involving the product |
| `returns` | Sessions where user returns within X days and engages |
| `dwellHits` | Dwell time above threshold on product card/details |
| `outboundClicks` | Optional: outbound clicks |

### 5.3 Rate Calculation

```
save_rate    = saves / impressions
share_rate   = shares / impressions
compare_rate = compares / impressions
return_rate  = returns / impressions
dwell_rate   = dwellHits / impressions
click_rate   = outboundClicks / impressions
```

### 5.4 Weighted Intent Rate (Raw)

```
raw = 0.50 * save_rate
    + 0.20 * share_rate
    + 0.15 * compare_rate
    + 0.10 * return_rate
    + 0.05 * dwell_rate
```

(Optional: include click_rate as 0.05 with renormalization)

### 5.5 Smoothing (Prevents Small-Sample Noise)

Use an empirical Bayes prior on `raw`:

```
prior_mean = median(raw) across all products in that segment (or global)
prior_weight = 2000 impressions (tunable)

smoothed = (prior_mean * prior_weight + raw * impressions) / (prior_weight + impressions)
```

### 5.6 Map to 0–100

Use a saturating mapping to avoid extreme values:

```
target = 90th percentile of smoothed values for segment over last 28 days
score = 100 * clamp(smoothed / target, 0, 1)
```

### 5.7 Banding

| Band | Score Range | Meaning |
|------|-------------|---------|
| Green | ≥ 75 | Strong performance; boost/spend |
| Yellow | 45–74 | Has promise; test/iterate |
| Red | < 45 | Reevaluate creative, price, or fit |

Also show "Low data" if `impressions < 1000` (or dynamic per segment volume).

### 5.8 Reason Codes

Compare each component vs segment baseline:

| Condition | Reason Code |
|-----------|-------------|
| save_rate above baseline by X% | "Strong saves" |
| impressions high but save_rate low | "Low saves despite impressions" |
| share_rate high | "High share rate" |
| return_rate high | "High return sessions" |
| Product often shown but low match score | "Segment mismatch" |
| Image health issues | "Creative health issues" |
| Price outside typical segment range | "Price band mismatch" |

---

## 6. Featured Serving Algorithm

### 6.1 Slot Determination

At each card opportunity:

1. Check if this slot is **organic** or **featured** (based on frequency cap + pacing)
2. Default: featured slot every 12 cards (configurable per session)

### 6.2 If Featured Slot

```
1. Filter eligible campaigns:
   - Status = 'active'
   - Budget remaining > 0
   - Schedule includes current date
   - Segment matches user attributes

2. Filter eligible products:
   - Campaign products (manual or recommended)
   - Creative Health >= threshold
   - Not in retailer exclude list
   - Relevance score > threshold for user

3. Rank candidates by:
   - Expected incremental intent (estimated Confidence Score uplift)
   - Predicted save probability
   - Price to show (if bid-based in v2)

4. Apply constraints:
   - Diversity: don't show same retailer twice in last N featured
   - User fatigue: respect per-user frequency limits

5. Serve winner
```

### 6.3 Logging

Every featured impression logs:

| Field | Description |
|-------|-------------|
| `campaignId` | Which campaign |
| `productId` | Which product |
| `segmentId` | Target segment |
| `rankPosition` | Position in candidate ranking |
| `relevanceScore` | Match score for user |
| `isFeatured` | true |
| `slotNumber` | N-th card in session |

---

## 7. Click ID + Pixel Specification (v2)

### 7.1 Outbound Click Format

When sending users to retailer site, append:

| Parameter | Description |
|-----------|-------------|
| `swp_click_id` | UUID generated per click |
| `swp_seg` | Segment slug (e.g., `japandi_small_8k_stockholm`) |
| `swp_score_band` | `green` / `yellow` / `red` (optional) |

### 7.2 Pixel Behavior

On retailer site:

1. If `swp_click_id` exists in URL → store as first-party cookie `swpclid`
2. Send beacon to Swiper: `{event: "landing", swp_click_id, url, referrer, ts}`
3. Retailer can optionally call JS API to emit:
   - `product_view`
   - `add_to_cart`
   - `purchase` (with value/currency/order_id)

### 7.3 Audience Enablement

Two modes (no full "sync" needed in v2):

1. **DIY mode (fast adoption):** Pixel sets `swp_seg` cookie; retailer uses GTM to map to Meta/Google audiences
2. **Enriched remarketing:** Swiper Pixel emits custom events into retailer ad tags:
   - Meta: `fbq('trackCustom', 'SwiperIntent', {segment, score_band})`
   - Google: Custom remarketing parameters

### 7.4 Console Features (v2)

- Pixel status checker ("installed / receiving events")
- Event diagnostics
- Audience size estimates per segment
- Conversion funnel: click → product view → cart → purchase

---

## 8. Recommendation Engine

### Ranker Interface

```typescript
// firebase/functions/src/ranker/types.ts
interface SessionContext {
  sessionId: string;
  swipeHistory: SwipeRecord[];
  likedItems: Item[];
  seenItemIds: Set<string>;
}

interface SwipeRecord {
  itemId: string;
  direction: 'like' | 'dislike';
  timestamp: Date;
}

interface RankedItem {
  item: Item;
  score: number;
  reason?: string;
  isFeatured: boolean;
  campaignId?: string;
}

interface Ranker {
  rank(items: Item[], context: SessionContext): RankedItem[];
}
```

### Preference Weights Ranker

```typescript
// firebase/functions/src/ranker/preferenceWeightsRanker.ts

const ATTRIBUTE_WEIGHTS = {
  styleTags: 0.35,
  material: 0.25,
  colorFamily: 0.20,
  sizeClass: 0.15,
  priceRange: 0.05,
};

function buildPreferenceProfile(likes: Item[]): PreferenceProfile {
  // Count attribute frequencies in liked items
  // Normalize to 0-1 scores
}

function scoreItem(item: Item, profile: PreferenceProfile): number {
  // Weighted sum of attribute match scores
}
```

---

## 9. Error Handling

### HTTP Status Codes

| Code | Meaning | When Used |
|------|---------|-----------|
| `200` | Success | Normal response |
| `201` | Created | New resource created |
| `400` | Bad Request | Invalid input |
| `401` | Unauthorized | Missing/invalid auth |
| `403` | Forbidden | Not in admin allowlist |
| `404` | Not Found | Resource doesn't exist |
| `429` | Too Many Requests | Rate limited |
| `500` | Internal Error | Server error |

### Error Response Format

```json
{
  "error": {
    "code": "INVALID_SESSION",
    "message": "Session ID is required",
    "details": {}
  }
}
```

### Error Codes

| Code | Description |
|------|-------------|
| `INVALID_SESSION` | Session ID missing or invalid |
| `SESSION_NOT_FOUND` | Session doesn't exist |
| `ITEM_NOT_FOUND` | Item doesn't exist |
| `INVALID_DIRECTION` | Swipe direction not `like`/`dislike` |
| `RATE_LIMITED` | Too many requests |
| `ADMIN_REQUIRED` | Admin authentication required |
| `ADMIN_FORBIDDEN` | Email not in allowlist |
| `AUTH_REQUIRED` | User authentication required |
| `ROOM_NOT_FOUND` | Decision Room doesn't exist |
| `NOT_ROOM_CREATOR` | Only room creator can perform action |
| `CAMPAIGN_NOT_FOUND` | Campaign doesn't exist |
| `SEGMENT_NOT_FOUND` | Segment doesn't exist |
| `RETAILER_NOT_FOUND` | Retailer doesn't exist |

---

## 10. Environment Configuration

### Cloud Functions

```bash
# firebase/functions/.env
ADMIN_PASSWORD=xxx
SUPPLY_ENGINE_URL=https://supply-engine-xxx.run.app
DECK_RESPONSE_LIMIT=20
DECK_ITEMS_FETCH_LIMIT=500
DECK_CANDIDATE_CAP=2000
RANKER_EXPLORATION_RATE=0
FEATURED_FREQUENCY_CAP=12
FEATURED_RELEVANCE_THRESHOLD=0.5
CONFIDENCE_SCORE_PRIOR_WEIGHT=2000
CONFIDENCE_SCORE_LOW_DATA_THRESHOLD=1000
```

### Supply Engine

```bash
# services/supply_engine/.env
GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
PORT=8081
```

---

## References

- [PRD.md](PRD.md) – Product requirements
- [COMMERCIAL_STRATEGY.md](COMMERCIAL_STRATEGY.md) – Commercial model
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) – Build sequence
- [APP_FLOW.md](APP_FLOW.md) – User flows and screens
- [FRONTEND_GUIDELINES.md](FRONTEND_GUIDELINES.md) – UI patterns
- [TECH_STACK.md](TECH_STACK.md) – Package versions

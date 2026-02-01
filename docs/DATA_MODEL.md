# Swiper – Firestore data model

## Collections

### 1. sources/{sourceId}

Content source for ingestion (feed, API, crawl, manual).

| Field | Type | Description |
|-------|------|-------------|
| name | string | Display name |
| mode | string | "feed" \| "api" \| "crawl" \| "manual" |
| isEnabled | boolean | |
| baseUrl | string | Base URL for the source |
| scheduleCron | string? | Optional cron for scheduled runs |
| rateLimitRps | number | Rate limit (requests per second) |
| allowlistPolicy | map | domains: string[], pathPrefixes: string[] |
| robotsRespect | boolean | Respect robots.txt |
| mediaRights | map | canHotlinkImages, canStoreImages, canStoreDescriptions (bool) |
| notes | string? | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

### 2. items/{itemId}

Normalized furniture item (sofa). Primary collection for deck.

| Field | Type | Description |
|-------|------|-------------|
| sourceId | string | |
| sourceType | string | |
| sourceItemId | string? | |
| sourceUrl | string | |
| canonicalUrl | string | Normalized URL (dedupe) |
| title | string | |
| brand | string? | |
| descriptionShort | string? | Capped length |
| priceAmount | number | |
| priceCurrency | string | "SEK" |
| dimensionsCm | map | w, h, d (number) |
| sizeClass | string | "small" \| "medium" \| "large" |
| material | string | fabric, leather, velvet, boucle, wood, metal, mixed |
| colorFamily | string | white, beige, brown, gray, black, green, blue, red, yellow, orange, pink, multi |
| styleTags | array | string[] |
| newUsed | string | "new" \| "used" |
| conditionNote | string? | |
| locationHint | string? | City/region only |
| deliveryComplexity | string | "low" \| "medium" \| "high" |
| smallSpaceFriendly | boolean | |
| modular | boolean | |
| ecoTags | array | string[] |
| availabilityStatus | string | "in_stock" \| "out_of_stock" \| "unknown" |
| outboundUrl | string | URL for /go redirect |
| images | array | [{ url, width?, height?, alt?, type? }] |
| lastUpdatedAt | timestamp | |
| firstSeenAt | timestamp | |
| lastSeenAt | timestamp | |
| isActive | boolean | |

---

### 3. anonSessions/{sessionId}

Anonymous session (no login). Created by POST /api/session.

| Field | Type | Description |
|-------|------|-------------|
| createdAt | timestamp | |
| lastSeenAt | timestamp | |
| locale | string? | |
| preferences | map? | Snapshot from onboarding |
| seenItemIdsRolling | array? | Small rolling list; do not grow unbounded |

Subcollections:

- **anonSessions/{sessionId}/likes/{itemId}** – quick lookup of liked itemIds (document ID = itemId).
- **anonSessions/{sessionId}/preferenceWeights** – optional map of tag/attribute weights for ranking.

---

### 4. swipes/{swipeId}

Single swipe event.

| Field | Type | Description |
|-------|------|-------------|
| sessionId | string | |
| itemId | string | |
| direction | string | "left" \| "right" |
| positionInDeck | number | |
| createdAt | timestamp | |

---

### 5. likes/{likeId}

Like (saved item).

| Field | Type | Description |
|-------|------|-------------|
| sessionId | string | |
| itemId | string | |
| createdAt | timestamp | |

Also mirrored in anonSessions/{sessionId}/likes/{itemId} for fast reads.

---

### 6. shortlists/{shortlistId}

Shared shortlist.

| Field | Type | Description |
|-------|------|-------------|
| ownerSessionId | string | |
| shareToken | string | Unique token for /s/{token} |
| createdAt | timestamp | |

**shortlists/{shortlistId}/items/{itemId}**

| Field | Type | Description |
|-------|------|-------------|
| addedAt | timestamp | |

---

### 7. events/{eventId}

Analytics events (no PII).

| Field | Type | Description |
|-------|------|-------------|
| sessionId | string | Opaque ID |
| eventType | string | swipe_left, swipe_right, open_detail, add_like, remove_like, outbound_click, share_shortlist, filter_change, compare_open |
| itemId | string? | |
| metadata | map? | No PII |
| createdAt | timestamp | |

---

### 8. ingestionRuns/{runId}

Supply Engine run per source.

| Field | Type | Description |
|-------|------|-------------|
| sourceId | string | |
| startedAt | timestamp | |
| finishedAt | timestamp? | |
| status | string | "running" \| "succeeded" \| "failed" |
| stats | map | fetched, parsed, normalized, upserted, failed, durationMs |
| errorSummary | string? | |

---

### 9. ingestionJobs/{jobId}

Individual job within a run.

| Field | Type | Description |
|-------|------|-------------|
| sourceId | string | |
| runId | string | |
| jobType | string | fetch_feed, fetch_page, parse, normalize, upsert |
| payload | map | |
| status | string | queued, running, succeeded, failed |
| attempts | number | |
| error | string? | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

## Indexes

Defined in `firebase/firestore.indexes.json`:

- **items**: isActive == true, orderBy lastUpdatedAt desc; composites for sizeClass, colorFamily, newUsed, ecoTags.
- **likes**: sessionId.
- **swipes**: sessionId, orderBy createdAt desc.
- **ingestionJobs**: status, orderBy createdAt asc.

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

Legacy analytics events (no PII). Still written by backend (swipe.ts, likes.ts, go.ts, shortlists.ts).

| Field | Type | Description |
|-------|------|-------------|
| sessionId | string | Opaque ID |
| eventType | string | swipe_left, swipe_right, add_like, remove_like, outbound_click, share_shortlist, … |
| itemId | string? | |
| metadata | map? | No PII |
| createdAt | timestamp | |

---

### 7b. events_v1/{eventId}

Canonical v1 events (client → POST /api/events/batch). Document ID = eventId (UUID v4) for dedupe.

| Field | Type | Description |
|-------|------|-------------|
| schemaVersion | string | "1.0" |
| eventId | string | UUID v4 (also doc ID) |
| eventName | string | session_start, deck_response, swipe_left, swipe_right, card_impression_start, card_impression_end, detail_open, detail_close, like_add, like_remove, filters_apply, compare_open, shortlist_create, outbound_click, onboarding_complete, onboarding_skip, empty_deck, … |
| sessionId | string | Opaque ID (min 8 chars) |
| clientSeq | number | Monotonic per session |
| createdAtClient | string | ISO 8601 |
| createdAtServer | timestamp | Set by server |
| app | map | platform, appVersion, locale, timezoneOffsetMinutes, screenBucket |
| surface | map? | name, route, referrerSurface |
| item | map? | itemId, source, positionInDeck, snapshot, … |
| rank | map? | rankerRunId, algorithmVersion, scoreAtRender, … |
| impression | map? | impressionId, visibleDurationMs, endReason, … |
| interaction | map? | gesture, direction, velocity, … |
| filters | map? | active, change |
| onboarding | map? | styleTagsSelected, budgetMinSEK, budgetMaxSEK, ecoOnly, newOnly, smallSpaceOnly, … |
| compare | map? | compareCount, attribute, direction |
| share | map? | shortlistId, method, channel, … |
| outbound | map? | destinationDomain, redirectId, timeToRedirectMs, … |
| perf | map? | endpoint, latencyMs, statusCode, … |
| error | map? | errorType, errorCode, surface, stackHash |
| ext | map? | Escape hatch (e.g. durationMs, sizeClass) |

Index: sessionId (ASC), createdAtServer (DESC).

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

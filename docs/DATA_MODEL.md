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
| useBrowserFallback | boolean | Enable browser fallback for JS-rendered pages (default false) |
| enableQualityRefetch | boolean | Optional post-crawl low-quality refetch pass |
| qualityRefetchLimit | number | Max candidates to refetch per run (default 100) |
| mediaRights | map | canHotlinkImages, canStoreImages, canStoreDescriptions (bool) |
| notes | string? | |
| createdAt | timestamp | |
| updatedAt | timestamp | |

---

### 2. items/{itemId}

Normalized furniture item. Primary collection for deck (MVP surface currently sofas).

| Field | Type | Description |
|-------|------|-------------|
| sourceId | string | |
| sourceType | string | |
| sourceItemId | string? | |
| sourceUrl | string | |
| canonicalUrl | string | Normalized URL (dedupe) |
| title | string | |
| brand | string? | |
| descriptionShort | string? | Full product description (no truncation) |
| priceAmount | number | |
| priceCurrency | string | "SEK" |
| dimensionsCm | map | w, h, d (number) |
| primaryCategory | string | Primary taxonomy category (e.g. sofa, armchair) |
| sofaTypeShape | string? | Sofa shape axis: straight, corner, u_shaped, chaise, modular |
| sofaFunction | string? | Sofa function axis: standard, sleeper |
| seatCountBucket | string? | Optional seat bucket: 2, 3, 4_plus |
| environment | string | indoor, outdoor, both, unknown (internal fallback) |
| subCategory | string? | Legacy sofa descriptor (backward compatibility) |
| roomTypes | array | string[] placement tags (multi-valued) |
| extractionMeta | map | `{ method, extractorMethod, completeness, missingFields[], fetchMethod, extractedAt }` |
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
| filters | map? | active, change (includes taxonomy keys such as primaryCategory, sofaTypeShape, sofaFunction, seatCountBucket, environment) |
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

### 10. goldItems/{itemId}

Serve-ready subset used by deck retrieval after classification/policy gates.

| Field | Type | Description |
|-------|------|-------------|
| itemId | string | Mirrors items doc id |
| eligibleSurfaces | array | Surface allow-list for serving |
| primaryCategory | string | Canonical category for routing/filtering |
| predictedCategory | string | Legacy alias from classifier output |
| sofaTypeShape | string? | Sofa shape axis |
| sofaFunction | string? | Sofa function axis |
| seatCountBucket | string? | Optional seat-count bucket |
| environment | string? | indoor, outdoor, both, unknown |
| subCategory | string? | Legacy sofa descriptor |
| roomTypes | array? | Placement tags |
| categoryConfidence | number | Confidence for predicted category |
| decisions | map | Per-surface policy decision details |
| promotedAt | string | ISO timestamp of promotion |
| isActive | boolean | Active in deck candidate pool |

---

### 11. reviewQueue/{itemId}

Operational review queue for uncertain classification outcomes.

| Field | Type | Description |
|-------|------|-------------|
| itemId | string | Mirrors items doc id |
| classification | map | Full classifier output snapshot |
| decisions | map | Policy decisions at enqueue time |
| status | string | pending or reviewed |
| reviewAction | string? | accept, reject, reclassify |
| reviewedBy | string? | Reviewer identifier |
| createdAt | string | ISO timestamp |

---

### 12. reviewerLabels/{labelId}

Human labels used for training/evaluation loops.

| Field | Type | Description |
|-------|------|-------------|
| itemId | string | Reviewed item |
| action | string | accept, reject, reclassify |
| trainingOnly | boolean? | True for Training Lab labels (no queue/gold mutation) |
| labelCategory | string? | Explicit target category for binary task |
| labelDecision | string? | in_category or not_category |
| isInCategory | boolean? | Normalized binary target |
| source | string? | training_lab or operations_review |
| correctCategory | string? | Populated when reclassified |
| reviewerId | string | Reviewer identifier |
| originalClassification | map | Snapshot at label time |
| createdAt | string | ISO timestamp |

---

### 13. categorizationTrainingConfig/latest

Derived runtime controls generated from reviewer labels.

| Field | Type | Description |
|-------|------|-------------|
| version | number | Config schema version |
| updatedAt | string | ISO timestamp |
| lastTargetCategory | string? | Last category trained |
| byCategory | map | Per-category runtime config |

Per-category (`byCategory.{category}`) includes:
- `runtimeStatus`: `validated` or `shadow_only`
- `sourceCategoryRejectTokens`: source/category token reject lists
- `sourceCategoryMinConfidence`: source/category confidence floors
- `sourceRequireImages`: source image requirements
- `evaluation`: holdout metrics and gate details
- `trainingSplit`: train/holdout counts

---

## Indexes

Defined in `firebase/firestore.indexes.json`:

- **items**: isActive == true, orderBy lastUpdatedAt desc; composites for sizeClass, colorFamily, newUsed, ecoTags.
- **likes**: sessionId.
- **swipes**: sessionId, orderBy createdAt desc.
- **ingestionJobs**: status, orderBy createdAt asc.

# Swiper – Event tracking (current vs recommended for ML)

This doc lists what we track today and what we should track for a future ML recommendation engine. Events live in the **events** collection (legacy) and **events_v1** (canonical v1 schema); all use **sessionId** and **createdAt** / **createdAtServer** for session-based and temporal modeling.

**Canonical schema (v1):** Client sends batched v1 events to POST /api/events/batch. Schema and Event Requirements Matrix: [docs/EVENT_SCHEMA_V1.md](EVENT_SCHEMA_V1.md). JSON Schema: [docs/schemas/swiper_event_v1.schema.json](schemas/swiper_event_v1.schema.json). Flutter tracker: `lib/data/event_tracker.dart` — use `ref.read(eventTrackerProvider).track(eventName, partial)`; buffer flushes when size ≥ 20, oldest ≥ 5s, or on session_end / app background.

---

## 1. What we track today

| Event | Source | Where stored | When | Key fields |
|-------|--------|--------------|------|------------|
| **swipe_left** | Backend (swipe.ts) | events + swipes | User swipes card left (pass) | sessionId, itemId, metadata.positionInDeck |
| **swipe_right** | Backend (swipe.ts) | events + swipes | User swipes card right (like) | sessionId, itemId, metadata.positionInDeck |
| **add_like** | Backend (likes.ts) | events | User taps like on item (from Likes or detail) | sessionId, itemId |
| **remove_like** | Backend (likes.ts) | events | User unlikes item | sessionId, itemId |
| **share_shortlist** | Backend (shortlists.ts) | events | User creates shared shortlist | sessionId, metadata.shortlistId |
| **outbound_click** | Backend (go.ts) | events | User taps “View product” / external link | sessionId, itemId, metadata.destinationDomain, metadata.ref |

**Swipes collection** (denormalized for deck logic): each swipe row has `sessionId`, `itemId`, `direction` (left|right), `positionInDeck`, `createdAt`. Used to exclude seen items and for sequence data.

**Client-side events (Flutter → POST /api/events/batch, v1 schema):**

| Event | When | Key fields |
|-------|------|------------|
| **app_open** | First event with session in app run | — |
| **session_start** | First deck load for session (or after create) | — |
| **session_resume** | App resumed after ≥30s background | — |
| **session_end** | App backgrounded / hidden | — |
| **deck_request** | Deck fetch started | filters.active (if any), ext.requestId, ext.requestedLimit |
| **deck_response** | Deck fetch completed | rank.requestId, rank.rankerRunId, rank.algorithmVersion, rank.itemIds (served slate), rank.candidateSetId, rank.candidateCount, rank.rankWindow, rank.retrievalQueues, rank.explorationPolicy, rank.variant, rank.variantBucket, rank.sameFamilyTop8Rate, rank.styleDistanceTop4Min, rank.nearDuplicateShaping, rank.fallbackStage, perf.latencyMs |
| **deck_refresh** | User refreshes deck (Retry, Apply/Clear filters) | — |
| **card_render** | Top card built (with impression start) | item, rank |
| **card_impression_start** | Top card becomes visible | item, impression.impressionId, rank |
| **card_impression_end** | Top card leaves | item, impression.visibleDurationMs, endReason, bucket |
| **swipe_left / swipe_right** | User swipes card (or button) | item (itemId, positionInDeck, priceSEKAtTime, snapshot), interaction.gesture, direction, rank |
| **swipe_cancel** | User releases card without threshold | item, interaction.gesture |
| **swipe_undo** | User taps undo (when implemented) | item, interaction.direction |
| **detail_open / detail_close** | User opens/closes detail (deck, likes, shortlist) | item, source; close: ext.durationMs |
| **detail_scroll** | User scrolls detail sheet (throttled) | item.itemId |
| **detail_gallery_interaction** | User swipes image in detail | item.itemId, ext.imageIndex |
| **outbound_click** | User taps “View on site” | item, outbound.destinationDomain |
| **outbound_redirect_start / success / fail** | Around launchUrl | item, outbound.destinationDomain |
| **filters_open** | User opens filter sheet | — |
| **filters_apply** | User applies filters | filters.active (full snapshot; taxonomy-first keys + legacy compatibility keys) |
| **filters_clear** | User taps Clear all | — |
| **filter_change** | User changes a filter control (optional) | filters.change.key, from, to |
| **compare_open / compare_close** | User opens/leaves compare | items, compare.compareCount |
| **compare_outbound_click** | Outbound from compare screen | item, outbound.destinationDomain |
| **likes_open** | User navigates to Likes | — |
| **like_add / like_remove** | When UI calls toggleLike (use toggleLikeWithTracking) | item.itemId |
| **shortlist_create** | User creates shared shortlist | items, share.shortlistId |
| **shortlist_share** | Share sheet shown after create | share |
| **share_link_landing_view** | User lands on /s/:token | share.linkType, linkId |
| **deep_link_open** | User lands on /s/:token or /compare?ids= | surface, ext |
| **onboarding_start** | User enters onboarding | — |
| **onboarding_step_view** | Each step shown | onboarding.stepName |
| **onboarding_step_change** | User changes style/budget/toggle | onboarding.stepName, field |
| **onboarding_complete** | User finishes onboarding | onboarding (preferences) |
| **onboarding_skip** | User skips to deck | — |
| **consent_updated** | User toggles analytics opt-out | ext.analyticsOptOut |
| **client_error** | Caught error (e.g. deck load) | error.errorType, surface |
| **empty_deck** | Deck loads with no items | — |
| **surface** | Set per screen via currentSurfaceProvider | surface.name (deck_card, likes, compare, etc.) |

**Session context (POST /api/session body):** Flutter sends `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes`; backend stores on **anonSessions** and may set `userAgent` from request header.

---

## 2. What we should track for ML

Recommendation models need **explicit signals** (swipe, like, click), **implicit engagement** (views, dwell time, detail opens), and **context** (position, filters, session). Below: event type, why it matters, and suggested metadata.

### 2.1 Already tracked (keep as-is)

| Event | Use for ML |
|-------|------------|
| swipe_left | Strong negative signal (not interested). |
| swipe_right | Strong positive signal; also used for preferenceWeights. |
| add_like | Strong positive (save). |
| remove_like | Negative signal. |
| outbound_click | Strong intent (likely purchase path). |
| share_shortlist | Social / intent signal. |

Keep storing these in **events** (and swipes for left/right). Ensure **itemId**, **sessionId**, **createdAt**, and **positionInDeck** (for swipes) are always present.

### 2.2 Add: engagement (implicit signals)

| Event | When | Why for ML | Suggested metadata |
|-------|------|------------|--------------------|
| **open_detail** | User opens item detail sheet from deck or likes | Interest without like; good for CTR / engagement models | itemId, source (deck | likes), positionInDeck (if from deck) |
| **detail_dismiss** | User closes detail sheet without like/click | Soft negative if dwell time short | itemId, timeViewedMs |
| **compare_open** | User opens compare screen with N items | Strong consideration signal | itemIds (list), count |
| **deck_refresh** | User pulls to refresh deck | Re-engagement; can add metadata later | — |
| **deck_empty_view** | User sees “no more items” | Session boundary; useful for session length | — |

### 2.3 Add: context (for features)

| Event | When | Why for ML | Suggested metadata |
|-------|------|------------|--------------------|
| **session_start** | First deck load for session (or first after onboarding) | Session start; cold start / onboarding | hasOnboardingPreferences (bool), locale |
| **filter_change** | User applies/clears filters on deck | Explains why deck composition changes; filter-aware models | filters (e.g. primaryCategory, sofaTypeShape, sofaFunction, seatCountBucket, environment, roomType, sizeClass, colorFamily, newUsed) |
| **onboarding_complete** | User finishes onboarding | Explicit preferences for cold start | preferences (map: budget, style tags, etc.) |

### 2.4 Optional: dwell time

| Concept | How | Why for ML |
|---------|-----|------------|
| **Time on card** | From card enter view until swipe or leave (e.g. next card) | Dwell time = implicit interest; long dwell + swipe_right = stronger than short. |
| **Time in detail** | From open_detail to detail_dismiss (or outbound_click) | Distinguish “glanced” vs “read”; good for engagement scoring. |

Store as **metadata** on existing events (e.g. `timeViewedMs` on open_detail/detail_dismiss) or as a dedicated **card_view** event with duration.

---

## 3. Canonical event schema v1 (implemented)

V1 events are sent by the Flutter tracker to POST /api/events/batch and stored in **events_v1** (document ID = eventId for dedupe). Each document has:

- **Required:** schemaVersion "1.0", eventId (UUID v4), eventName, sessionId, clientSeq (monotonic per session), createdAtClient, app (platform, appVersion, locale, timezoneOffsetMinutes, screenBucket).
- **Server-added:** createdAtServer.
- **Optional:** surface, item, rank, impression, interaction, filters, onboarding, compare, share, outbound, perf, error, ext.

**Event names (v1):** app_open, session_start, session_resume, session_end, deck_request, deck_response, deck_refresh, card_render, card_impression_start, card_impression_end, swipe_left, swipe_right, swipe_cancel, swipe_undo, detail_open, detail_close, detail_scroll, detail_gallery_interaction, outbound_click, outbound_redirect_start, outbound_redirect_success, outbound_redirect_fail, filters_open, filters_apply, filters_clear, filter_change, compare_open, compare_close, compare_outbound_click, likes_open, like_add, like_remove, shortlist_create, shortlist_share, share_link_landing_view, deep_link_open, onboarding_start, onboarding_step_view, onboarding_step_change, onboarding_complete, onboarding_skip, consent_updated, client_error, empty_deck, etc. Full enum: [schemas/swiper_event_v1.schema.json](schemas/swiper_event_v1.schema.json).

**Golden Card v2 events (implemented):**
- `gold_v2_intro_shown`
- `gold_v2_step_viewed`
- `gold_v2_option_selected`
- `gold_v2_option_deselected`
- `gold_v2_step_completed`
- `gold_v2_skipped`
- `gold_v2_summary_confirmed`
- `gold_v2_summary_adjusted`

**Event Requirements Matrix (training-critical):** See [EVENT_SCHEMA_V1.md](EVENT_SCHEMA_V1.md). Key: deck_response must include rank.rankerRunId, rank.algorithmVersion, and for **offline eval and A/B** rank.variant, rank.variantBucket, rank.itemIds (served slate); card_impression_end must match impressionId and include visibleDurationMs, endReason; swipe_left/right must include item.itemId, item.positionInDeck, interaction.gesture, interaction.direction, and ideally rank; filters_apply must include full filters.active (including taxonomy keys such as primaryCategory, sofaTypeShape, sofaFunction, seatCountBucket, environment, roomType; `subCategory` is legacy-compatible); outbound_click must include outbound.destinationDomain.

---

## 4. Data needed to train a recommender

Typical inputs for training:

| Data | Source | Status |
|------|--------|--------|
| Positive actions | swipe_right, add_like, outbound_click | ✅ Stored |
| Negative actions | swipe_left, remove_like | ✅ Stored |
| Item features | items collection (title, material, color, price, etc.) | ✅ Stored |
| Session sequence | events + swipes by sessionId, ordered by createdAt | ✅ Available |
| Context per event | positionInDeck, filters, source, rank | ✅ In events_v1 (item, rank, filters) |
| Implicit engagement | detail_open/close, card_impression_start/end, dwell | ✅ In events_v1 |
| Cold start | onboarding_complete, session_start | ✅ In events_v1 |

**Done (canonical v1):**

1. Client sends batched v1 events to POST /api/events/batch; stored in **events_v1** with eventId as doc ID.  
2. Tracker in `lib/data/event_tracker.dart`: `track(eventName, partial)`; auto-fills schemaVersion, eventId, clientSeq, app; buffer flushes at 20 events, 5s, or session_end.  
3. Deck API returns rank (rankerRunId, algorithmVersion, itemScores); card impressions and swipes include rank context.
4. Lifecycle observer flushes buffer and emits session_end / session_resume (resume after >30s background).
5. Analytics opt-out: when enabled, only essential events (session_start, deck_response, swipe_left/right, like_add/remove, outbound_click, card_impression_*, empty_deck) are sent.

**QA invariants (ship-proofing):**

- clientSeq strictly increases within a session.
- Every swipe has itemId and positionInDeck.
- Every card_impression_end has a matching impressionId from a start.
- Deck-origin events include rankerRunId when applicable.
- deck_request and deck_response share the same requestId (rank.requestId and/or ext.requestId).
- deck_response includes rank.itemIds, rank.variant, rank.variantBucket for offline eval and A/B segmentation.
- filters_apply always includes full filters.active snapshot.
- outbound_click never missing destinationDomain.

---

## 5. Device and user context (browser, locale, etc.)

**Current state: we are not tracking device or browser data.**

- **Flutter app:** On session create, the app sends optional body: `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes` (from `DeviceContext`). No raw User-Agent from client.
- **Backend:** Session creation (`POST /api/session`) stores `sessionId`, `createdAt`, `lastSeenAt` and, when provided: `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes`, `userAgent` (normalized from request header). Events store `sessionId`, `eventType`, `itemId`, `metadata`, `createdAt`.

So today: **device/platform, locale, screen bucket, timezone, and normalized User-Agent are stored on anonSessions at session create.**

### 5.1 What to add (for ML and analytics)

Keep everything **anonymous and non-PII**. Prefer **session-level** context on **anonSessions** (set at session create or first event) so we don’t repeat the same data on every event.

| Data | Where to get it | Where to store | Use for ML |
|------|------------------|-----------------|------------|
| **User-Agent** | Request header (backend) or client (Flutter) | anonSessions.deviceInfo.userAgent, or events.metadata.userAgent (first event only) | Browser/device family, bot detection |
| **Platform** | Flutter: `Theme.of(context).platform` / `dart:io` Platform / kIsWeb | anonSessions.deviceInfo.platform (e.g. web, ios, android) | Platform-specific models, A/B |
| **Locale** | Flutter: `Localizations.localeOf(context)` or system | anonSessions.locale (e.g. en, sv) | Geo/language features, cold start |
| **Screen size bucket** | Flutter: MediaQuery (e.g. width bucket: mobile / tablet / desktop) | anonSessions.deviceInfo.screenBucket or first event metadata | Layout/UX and device-type features |
| **Timezone offset** | Client: `DateTime.now().timeZoneOffset` (minutes) | anonSessions.timezoneOffsetMinutes or first event | Time-of-day features |

**Recommendation:**

1. **Session creation:** When the app calls `POST /api/session`, send optional body (or headers) with: `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes`. Backend writes these once to **anonSessions** (e.g. `locale`, `deviceInfo: { platform, screenBucket, userAgent? }`, `timezoneOffsetMinutes`).  
2. **User-Agent:** Backend can read `req.headers["user-agent"]` on session create (or first request) and store a **normalized** string or hash (e.g. "Chrome/120", "Safari/iOS") in anonSessions; avoid storing raw UA in events.  
3. **Events:** Do **not** attach full device/browser to every event; reference the session. Optionally add a one-off **session_start** event whose metadata includes platform/locale/screenBucket for easier analytics queries.

### 5.2 Privacy

- Do not store IP, fingerprint, or any identifier that can be linked to a person.  
- Prefer coarse values: platform (web|ios|android), locale (language only, e.g. en/sv), screen bucket (mobile|tablet|desktop), and a truncated or hashed User-Agent if needed for bot/device family.  
- Document in the privacy policy that we collect anonymous device/platform/locale for recommendations and analytics.

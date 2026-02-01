# Swiper – Event tracking (current vs recommended for ML)

This doc lists what we track today and what we should track for a future ML recommendation engine. Events live in the **events** collection (and some in **swipes**); all use **sessionId** and **createdAt** for session-based and temporal modeling.

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

**Client-side events (Flutter → POST /api/events):**

| Event | When | Key fields |
|-------|------|------------|
| **open_detail** | User opens item detail sheet (deck or likes) | itemId, metadata.source (deck \| likes) |
| **detail_dismiss** | User closes detail sheet | itemId, metadata.timeViewedMs, metadata.source |
| **compare_open** | User opens compare screen with items | metadata.itemIds, metadata.count |
| **filter_sheet_open** | User opens filter bottom sheet | — |
| **session_start** | First deck load for session (or after create) | — |
| **deck_empty_view** | Deck loads with no items | — |
| **onboarding_complete** | User finishes onboarding | metadata.styles, budgetMin, budgetMax, ecoOnly, newOnly, sizeConstraint |

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
| **filter_change** | User applies/clears filters on deck | Explains why deck composition changes; filter-aware models | filters (e.g. sizeClass, colorFamily, newUsed) |
| **onboarding_complete** | User finishes onboarding | Explicit preferences for cold start | preferences (map: budget, style tags, etc.) |

### 2.4 Optional: dwell time

| Concept | How | Why for ML |
|---------|-----|------------|
| **Time on card** | From card enter view until swipe or leave (e.g. next card) | Dwell time = implicit interest; long dwell + swipe_right = stronger than short. |
| **Time in detail** | From open_detail to detail_dismiss (or outbound_click) | Distinguish “glanced” vs “read”; good for engagement scoring. |

Store as **metadata** on existing events (e.g. `timeViewedMs` on open_detail/detail_dismiss) or as a dedicated **card_view** event with duration.

---

## 3. Recommended event schema (for new/updated events)

Use a single **events** collection. Each document:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| sessionId | string | Yes | Anonymous session. |
| eventType | string | Yes | One of the event types below. |
| itemId | string | No | Item concerned (if any). |
| metadata | map | No | Event-specific payload (no PII). |
| createdAt | timestamp | Yes | Server or client time (prefer server). |

**Event types (canonical list):**

- swipe_left, swipe_right  
- add_like, remove_like  
- outbound_click, share_shortlist  
- open_detail, detail_dismiss  
- compare_open, deck_refresh, deck_empty_view  
- session_start, filter_change, onboarding_complete  
- (Optional) card_view with duration in metadata.

**Metadata conventions (examples):**

- **positionInDeck**: int (0-based) for deck position.  
- **timeViewedMs**: int for dwell/time in view.  
- **filters**: map (e.g. sizeClass, colorFamily, newUsed).  
- **source**: string (e.g. "deck" | "likes").  
- **ref**: string (e.g. "detail" | "list") for outbound_click.  
- **itemIds**: list of strings for compare_open.  
- **preferences**: map for onboarding_complete.

---

## 4. Data needed to train a recommender

Typical inputs for training:

| Data | Source | Status |
|------|--------|--------|
| Positive actions | swipe_right, add_like, outbound_click | ✅ Stored |
| Negative actions | swipe_left, remove_like | ✅ Stored |
| Item features | items collection (title, material, color, price, etc.) | ✅ Stored |
| Session sequence | events + swipes by sessionId, ordered by createdAt | ✅ Available |
| Context per event | positionInDeck, filters, source | ⚠️ Partial (positionInDeck on swipes; filters not yet logged) |
| Implicit engagement | open_detail, dwell time | ❌ Not yet |
| Cold start | onboarding_complete, session_start | ❌ Not yet |

**Done (as of 2025-01):**

1. Client-side calls to `POST /api/events` for: **open_detail**, **detail_dismiss** (with timeViewedMs), **compare_open**, **filter_sheet_open**, **session_start**, **deck_empty_view**, **onboarding_complete**.  
2. Session creation sends device context (locale, platform, screenBucket, timezoneOffsetMinutes); backend stores on anonSessions.  
3. Data & Privacy screen in app explains what we collect; placeholders for **opt-out** and **social login (e.g. Instagram/Facebook)** as “Coming later”.

**Backlog:**

- **Opt-out UI:** Functional control to reduce or disable non-essential event collection (stored per session or device).  
- **SSO / social login:** Optional connection to Instagram, Facebook, etc. for personalised feed; no SSO in MVP.  
- Optionally add **deck_refresh** and **card_view** (or dwell in metadata) later.  
- Keep using **swipes** + **events**; ensure every event has sessionId, createdAt, and suggested metadata so ML pipelines can join and featurize cleanly.

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

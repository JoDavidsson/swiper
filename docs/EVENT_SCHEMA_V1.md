# Swiper Event Schema v1

Canonical event schema for client-originated analytics. Stored events are validated against [schemas/swiper_event_v1.schema.json](schemas/swiper_event_v1.schema.json).

## Base requirements (every event)

- **schemaVersion**: `"1.0"`
- **eventId**: UUID v4 (client-generated)
- **eventName**: One of the enum values in the schema
- **sessionId**: Opaque session ID (min 8 chars)
- **clientSeq**: Monotonic integer per session (starts at 1)
- **createdAtClient**: ISO 8601 date-time
- **app**: Object with `platform`, `appVersion`, `locale`, `timezoneOffsetMinutes`, `screenBucket`

Server adds **createdAtServer** on ingestion.

## Event Requirements Matrix (training-critical)

| Event | Required payload |
|-------|------------------|
| **deck_response** | rank.rankerRunId, rank.algorithmVersion, rank.itemIds (served slate); recommended rank.requestId, rank.candidateSetId, rank.candidateCount, rank.rankWindow, rank.retrievalQueues, rank.explorationPolicy, rank.variant, rank.variantBucket; perf.latencyMs |
| **card_impression_start** | item.itemId, item.positionInDeck, impression.impressionId |
| **card_impression_end** | impression.visibleDurationMs, impression.endReason; same impressionId as start; optional impression.bucket (0_1s, 1_3s, 3_8s, 8s_plus) |
| **deck_refresh** | — (no required payload) |
| **consent_updated** | optional ext.analyticsOptOut |
| **swipe_left / swipe_right** | item.itemId, item.positionInDeck, interaction.gesture, interaction.direction; ideally item.priceSEKAtTime, item.snapshot (brand/newUsed/size/material/color/style), rank.rankerRunId, rank.scoreAtRender |
| **detail_open / detail_close** | item.itemId; on close include duration (ext.durationMs or impression.visibleDurationMs) |
| **outbound_click** | item.itemId, outbound.destinationDomain; optional outbound.redirectId |
| **filters_apply** | filters.active (full snapshot) |

## Tracker API (Flutter)

Use the event tracker in `lib/data/event_tracker.dart`:

- **track(eventName, partial)** — Enqueues a v1 event. Auto-fills schemaVersion, eventId, createdAtClient, sessionId, clientSeq, app.*, and optionally surface from router. `partial` can contain item, rank, impression, interaction, filters, onboarding, compare, share, outbound, perf, error, ext.
- **Deck request correlation** — Include `ext.requestId` on `deck_request` and echo it on `deck_response` (and rank.requestId when available) so request/serve/impression chains can be joined reliably.

Events are buffered and flushed when: buffer size ≥ 20, oldest event ≥ 5s, or session_background / before unload.

## QA invariants

- clientSeq strictly increases within a session
- Every swipe has itemId and positionInDeck
- Every card_impression_end has a matching impressionId from a start
- Deck-origin events include rankerRunId when applicable
- filters_apply always includes full filters.active snapshot
- outbound_click never missing destinationDomain

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
| **deck_response** | rank.rankerRunId, rank.algorithmVersion; optional perf.latencyMs, ext.deckItemScores |
| **card_impression_start** | item.itemId, item.positionInDeck, impression.impressionId |
| **card_impression_end** | impression.visibleDurationMs, impression.endReason; same impressionId as start |
| **swipe_left / swipe_right** | item.itemId, item.positionInDeck, interaction.gesture, interaction.direction; ideally rank.rankerRunId, rank.scoreAtRender |
| **detail_open / detail_close** | item.itemId; on close include duration (ext.durationMs or impression.visibleDurationMs) |
| **outbound_click** | item.itemId, outbound.destinationDomain; optional outbound.redirectId |
| **filters_apply** | filters.active (full snapshot) |

## Tracker API (Flutter)

Use the event tracker in `lib/data/event_tracker.dart`:

- **track(eventName, partial)** — Enqueues a v1 event. Auto-fills schemaVersion, eventId, createdAtClient, sessionId, clientSeq, app.*, and optionally surface from router. `partial` can contain item, rank, impression, interaction, filters, onboarding, compare, share, outbound, perf, error, ext.

Events are buffered and flushed when: buffer size ≥ 20, oldest event ≥ 5s, or session_background / before unload.

## QA invariants

- clientSeq strictly increases within a session
- Every swipe has itemId and positionInDeck
- Every card_impression_end has a matching impressionId from a start
- Deck-origin events include rankerRunId when applicable
- filters_apply always includes full filters.active snapshot
- outbound_click never missing destinationDomain

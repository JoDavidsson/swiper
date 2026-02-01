# Stress test report

Generated: 2026-02-01 21:14:23 UTC

## What was run

- **Products:** 5000
- **Users:** 1000
- **Swipes per user:** 30 (30000 total swipes)
- **Deck API calls:** 40 (30 sequential, 10 parallel)

## Timing

- Data generation: 2 s
- Unit tests (Jest): 2 s
- Deck API phase: 6 s

## Results

- All Jest tests **passed**.
- All 40 deck requests returned **200**. Average response time: **239.051 ms**.

## What this means

The recommendation engine and deck API handled 5000 products and the requested deck load without errors. Unit tests passed. You can increase scale (e.g. 10k products, more users) or set `DECK_ITEMS_FETCH_LIMIT` and `DECK_CANDIDATE_CAP` when starting the emulators to stress the ranker with more candidates per request.


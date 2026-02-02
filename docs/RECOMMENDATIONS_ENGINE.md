# Swiper – Recommendations engine

The recommendations engine ranks items for the deck using **personal** signals (this session’s preference weights) and optionally **persona-based** signals (“people like you”). It is implemented as a Firestore-free module so it can be unit-tested in isolation.

---

## Personal vs persona-based ranking

| Mode | Description | Data source |
|------|-------------|-------------|
| **Personal** | Rank by this session’s preference weights (onboarding + swipe-right), likes, and (later) dwell/impression. | anonSessions doc, preferenceWeights subcollection, likes, events_v1 (session-scoped). |
| **Persona-based** | Rank by behaviour of “similar” sessions (e.g. similar preference weights or similar liked items). | Precomputed aggregates: “item scores among similar sessions”, “popular among similar”. |

Persona aggregation is a **separate process** (scheduled function or pipeline) that precomputes `PersonaSignals` per “persona bucket” and writes to e.g. `personaSignals/{bucketId}`. The deck API looks up the bucket for the current session and passes the stored `PersonaSignals` into the ranker.

---

## Engine interface

**Location**: `firebase/functions/src/ranker/`.

**Public types**:

- **ItemCandidate** – `{ id: string } & Record<string, unknown>`; attributes used for scoring: `styleTags`, `material`, `colorFamily`, `sizeClass`.
- **SessionContext** – `{ preferenceWeights: Record<string, number> }`.
- **PersonaSignals** – optional `itemScoresFromSimilarSessions` (itemId → score), `popularAmongSimilar` (ordered itemIds).
- **RankOptions** – `{ limit: number; algorithmVersion?: string }`.
- **RankResult** – `{ runId, algorithmVersion, itemIds, itemScores }`.
- **Ranker** – interface with `rank(session, candidates, options, personaSignals?)`.

**Implementations**:

- **PreferenceWeightsRanker** – Personal-only: scores by `SessionContext.preferenceWeights` (styleTags, material, colorFamily, sizeClass), then normalizes by the number of matched signals (square-root normalization) to reduce tag-count bias. algorithmVersion: `preference_weights_v1`.
- **PersonalPlusPersonaRanker** – Blends personal score and persona score (configurable alpha). Personal scores use the same normalization; persona scores are normalized to the max persona score in the candidate set for scale alignment. When the session has no personal weights, alpha falls back to 0 (persona-only); when an item has no personal signals, alpha is capped to favor persona. algorithmVersion: `personal_plus_persona_v1`. Falls back to personal-only when `personaSignals` is missing or empty.
- **applyExploration(rankedIds, candidates, options)** – Applies exploration to avoid over-optimization. When `explorationRate === 0`, returns ranker order unchanged. When rate &gt; 0, uses “sample-from-top-2K” strategy; optional `seed` for reproducibility.

---

## Exploration

To prevent the ranker from over-exploiting the same top items (filter bubble), **exploration** is applied after ranking.

- **Strategy**: Sample-from-top-2K (take top 2×limit by score, randomly sample limit). Configurable rate (e.g. 0–10%). Optional `seed` for reproducible tests.
- **Config**: `RANKER_EXPLORATION_RATE` (env, default 0), `RANKER_EXPLORATION_SEED` (optional).
- **Tests**: With rate 0, output equals ranker order; with fixed seed and rate &gt; 0, output is reproducible.

---

## Offline evaluation

Use historical data to evaluate a ranker without affecting live traffic.

- **Data**: events_v1, likes, swipes (session-scoped feedback: deck_response, swipe_right, like_add, etc.).
- **Metric**: At least one offline metric, e.g. “For sessions with at least one like, what fraction of liked itemIds appeared in the ranker’s top-K for that deck request?” Requires joining deck_request/deck_response with likes (or replaying with the ranker).
- **Required logging**: rankerRunId, algorithmVersion, itemIds or itemScores in deck_response / events. Document the chosen metric and required fields here when defined.

---

## A/B readiness

When comparing algorithms (e.g. personal-only vs personal+persona, or different exploration rates), the **variant** is assigned deterministically (e.g. hash(sessionId) % 100) and included in the deck response (`rank.variant`, `rank.variantBucket`). The client should log variant (and algorithmVersion) in events_v1 so we can segment by variant when analysing likes, swipes, and retention.

---

## Target metrics

Pick 1–2 for MVP; ensure we log the required fields in events_v1.

- **Likes per session** (or per deck request): more likes may indicate better relevance.
- **Liked items in top-K**: of items the user liked, how many were in the ranker’s top-K when they were shown (supports offline evaluation; requires joining deck_response with likes).
- **Diversity**: e.g. variety of styleTags/material in top-K (optional).

**Required fields in events_v1**: sessionId, algorithmVersion, variant (or equivalent), itemIds or scores in deck_response; like/swipe events.

---

## How to run unit tests

From `firebase/functions`:

```bash
npm test
```

Tests live in `src/ranker/__tests__/`: scoreItem.test.ts, preferenceWeightsRanker.test.ts, personalPlusPersonaRanker.test.ts, exploration.test.ts. All use in-memory data only (no Firebase).

---

## Optional runner

From `firebase/functions`:

```bash
npm run runRanker
```

Loads fixtures from `scripts/fixtures/` (items.json, sessionContext.json, optional personaSignals.json), runs PreferenceWeightsRanker, applies exploration, and prints ranked ids and scores. If personaSignals.json exists, also runs PersonalPlusPersonaRanker. Useful for manual/exploratory testing.

---

## Debug loop and test output

From `firebase/functions`:

```bash
npm run debugRanker
```

Runs the recommendation engine with fixtures and **validates** each step:

1. **scoreItem** – Asserts score is a number and non-negative for the first item.
2. **PreferenceWeightsRanker** – Asserts runId, algorithmVersion, itemIds length ≤ limit, itemScores keys match itemIds.
3. **applyExploration(rate=0)** – Asserts order is unchanged (deterministic).
4. **applyExploration(rate>0, seed)** – Asserts two runs with the same seed produce the same order (reproducible).
5. **PersonalPlusPersonaRanker** – Asserts runId, algorithmVersion, itemIds and itemScores consistency.

Writes **NDJSON** to `<workspace>/.cursor/debug.log` (entry/exit for each step, plus a summary). Prints **PASS/FAIL** per step and exits with code 0 only if all checks pass. Use this to confirm the engine works after changes or in CI.

---

## Stress test

From the repo root, run `./scripts/run_stress_test.sh` to generate a larger synthetic DB (5,000 products, 100 users, 30 swipes each), run Jest, and hit the deck API many times. A **human-readable report** is printed and written to [docs/STRESS_TEST_REPORT.md](STRESS_TEST_REPORT.md). See [TESTING_LOCAL.md](TESTING_LOCAL.md) “Stress test” for prerequisites (emulators must be running). To stress the ranker with many more candidates per request (e.g. 1,000–2,000), set `DECK_ITEMS_FETCH_LIMIT` and `DECK_CANDIDATE_CAP` (e.g. `2000`) in the environment when starting the emulators.

---

## Deck API integration

The deck API (`GET /api/deck`) fetches preferenceWeights from the subcollection `anonSessions/{sessionId}/preferenceWeights/weights` (swipe-learned weights). It builds candidate items (exclude seen, apply filters), calls `PreferenceWeightsRanker.rank(sessionContext, candidates, { limit })`, applies `applyExploration` with configurable rate and seed, assigns A/B variant, and returns items, rank (rankerRunId, algorithmVersion, variant, variantBucket), and itemScores. Optional env vars `DECK_ITEMS_FETCH_LIMIT` and `DECK_CANDIDATE_CAP` (when set) raise the Firestore fetch and candidate caps for stress testing. When persona-based ranking is enabled, the API will fetch precomputed PersonaSignals and call PersonalPlusPersonaRanker instead (or in addition, via variant).

---

## Future

- **Persona aggregation pipeline**: Group sessions into persona buckets; aggregate item scores or “popular among similar” from likes/swipes (or events_v1); write to `personaSignals/{bucketId}`.
- **Offline eval pipeline**: Replay sessions, compute “liked in top-K” (or other metric).
- **MLRanker**: Consume events_v1 and/or persona aggregates; same `Ranker` interface.

Events_v1 and persona aggregation feed future/ML rankers.

**Synthetic dataset for testing:** A fake database generator (see [TESTING_LOCAL.md](TESTING_LOCAL.md) “Synthetic dataset for persona and offline eval”) creates multi-session interaction data (e.g. 1000 users, 1000 interactions per user) in the Firestore emulator. Use it to test persona aggregation and offline evaluation without production traffic.

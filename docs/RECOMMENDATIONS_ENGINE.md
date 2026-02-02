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

- **PreferenceWeightsRanker** – Personal-only: scores by `SessionContext.preferenceWeights` (styleTags, material, colorFamily, sizeClass), then normalizes by the number of matched signals (square-root normalization) to reduce tag-count bias. Ties preserve input order (recency order from deck candidates). algorithmVersion: `preference_weights_v1`.
- **PersonalPlusPersonaRanker** – Blends personal score and persona score (configurable alpha). Personal scores use the same normalization; persona scores are normalized to the max persona score in the candidate set for scale alignment. When the session has no personal weights, alpha falls back to 0 (persona-only); when an item has no personal signals, alpha is capped to favor persona. algorithmVersion: `personal_plus_persona_v1`. Falls back to personal-only when `personaSignals` is missing or empty.
- **applyExploration(rankedIds, candidates, options)** – Applies exploration to avoid over-optimization. When `explorationRate === 0`, returns ranker order unchanged. When rate &gt; 0, replaces roughly `rate × limit` positions by sampling from the top 2×limit pool (stochastic rounding), with optional `seed` for reproducibility.

---

## Exploration

To prevent the ranker from over-exploiting the same top items (filter bubble), **exploration** is applied after ranking.

- **Strategy**: Sample-from-top-2K (take top 2×limit by score). Replace roughly `rate × limit` positions in the top list with items sampled from the pool. Configurable rate (e.g. 0–10%). Optional `seed` for reproducible tests.
- **Config**: `RANKER_EXPLORATION_RATE` (env, default 0), `RANKER_EXPLORATION_SEED` (optional; when unset, deck uses session-based seed for deterministic exploration per session).
- **Tests**: With rate 0, output equals ranker order; with fixed seed and rate &gt; 0, output is reproducible.

**Exposure bias:** Items that rank higher get more exposure, hence more right-swipes, hence higher weights. We mitigate with exploration (sample-from-top-2K) and optional diversity; long-term consider exposure-aware or causal approaches.

---

## Offline evaluation

Use historical data to evaluate a ranker without affecting live traffic.

- **Data**: events_v1, likes, swipes (session-scoped feedback: deck_response, swipe_right, like_add, etc.).
- **Primary metric and required fields**: See [docs/OFFLINE_EVAL.md](OFFLINE_EVAL.md). Primary metric: **Liked-in-top-K** (per session): fraction of a session’s liked item IDs that appeared in the union of served slates; average over sessions with at least one like. Required: deck_response with rank.itemIds, rank.variant, rank.variantBucket; likes (Firestore or like_add).

---

## A/B readiness

When comparing algorithms (e.g. personal-only vs personal+persona, or different exploration rates), the **variant** is assigned deterministically (e.g. hash(sessionId) % 100) and included in the deck response (`rank.variant`, `rank.variantBucket`). The client logs variant, variantBucket, and itemIds in deck_response (and variant/variantBucket in swipe events when rank context is present) so we can segment by variant when analysing likes, swipes, and retention. See [OFFLINE_EVAL.md](OFFLINE_EVAL.md) for A/B segmentation.

---

## Target metrics

- **Likes per session** (or per deck request): more likes may indicate better relevance.
- **Liked-in-top-K** (primary offline metric): see [OFFLINE_EVAL.md](OFFLINE_EVAL.md).
- **Diversity**: e.g. variety of styleTags/material in top-K (optional). **Optional implementation:** Add a diversity constraint or MMR-style re-ranking so top-K is not dominated by one styleTag/material (e.g. max N items per styleTag in top-K, or maximal marginal relevance re-rank after PreferenceWeightsRanker).

**Optional – weight decay / normalization:** preferenceWeights grow unbounded on swipe_right; long sessions can over-dominate a few tags. Optional: periodic weight decay (e.g. multiply by 0.99 per day) or normalization of preferenceWeights to avoid runaway dominance.

**Optional – explainability:** Log or return score breakdown (e.g. top 3 attribute contributions) for the top item in deck response (e.g. ext.scoreBreakdown) for debugging and support.

**Required fields in events_v1 for offline eval**: sessionId, deck_response with rank.rankerRunId, rank.algorithmVersion, rank.variant, rank.variantBucket, rank.itemIds; like/swipe events.

**Item cold start:** Retrieval is by `lastUpdatedAt` desc; new/updated items surface first. New items have no swipe history, so persona does not help them. They rely on content-based scoring (preferenceWeights) and optional recency boost. Consider a “default” or global persona bucket for new items when persona is enabled.

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

**Persona cold sessions:** When a session has no preferenceWeights (and no preferences from onboarding), the session cannot be assigned a persona bucket from preference/profile. Use either: (A) a **default** or **global** persona bucket (e.g. `bucketId = "default"` with PersonaSignals aggregated across all sessions), or (B) skip persona for that session and use PreferenceWeightsRanker only. The persona aggregation pipeline should write `personaSignals/default` (or similar) so the deck can fall back when the session’s bucket would otherwise be empty.

---

## Future

- **Persona aggregation pipeline**: Group sessions into persona buckets; aggregate item scores or “popular among similar” from likes/swipes (or events_v1); write to `personaSignals/{bucketId}`. Include a **default** bucket (e.g. `personaSignals/default`) for cold sessions (no preferenceWeights/preferences).
- **Offline eval pipeline**: Replay sessions, compute “liked in top-K” (or other metric).
- **MLRanker**: Consume events_v1 and/or persona aggregates; same `Ranker` interface.

Events_v1 and persona aggregation feed future/ML rankers.

**Synthetic dataset for testing:** A fake database generator (see [TESTING_LOCAL.md](TESTING_LOCAL.md) “Synthetic dataset for persona and offline eval”) creates multi-session interaction data (e.g. 1000 users, 1000 interactions per user) in the Firestore emulator. Use it to test persona aggregation and offline evaluation without production traffic.

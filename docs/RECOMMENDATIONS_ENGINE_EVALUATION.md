# Recommendations Engine – Implementation Evaluation (2026-02-02)

## Scope

This evaluation covers the current “ranker” implementation in `firebase/functions/src/ranker/` and its integration in the Deck API (`firebase/functions/src/api/deck.ts`), including how preference weights are updated (`firebase/functions/src/api/swipe.ts`) and how rank context is emitted for offline evaluation.

## What’s implemented (current behavior)

### 1) Candidate retrieval (Deck API)

- **Retrieval**: Firestore `items` filtered by `isActive == true`, ordered by `lastUpdatedAt desc`, limited by `DECK_ITEMS_FETCH_LIMIT` (default `limit * 5`), then filtered client-side:
  - exclude “seen” from the last 500 swipes,
  - apply simple filters (`sizeClass`, `colorFamily`, `newUsed`),
  - cap candidates to `DECK_CANDIDATE_CAP` (default `limit * 2`).
- **Implication**: By default, the ranker only sees a *very small* candidate set (for `limit=10`, default candidateCap=20), which limits the ceiling of ranking quality regardless of how good scoring is.

### 2) Personal scoring (content-based)

- **Signals used**: `styleTags`, `material`, `colorFamily`, `sizeClass`.
- **Weights**: `SessionContext.preferenceWeights: Record<string, number>`, keyed as:
  - `modern` (for style tags),
  - `material:fabric`, `color:gray`, `size:medium`, etc.
- **Score**: sum of matched weights.
- **Normalization**: `score / sqrt(signalCount)` to reduce “many tags wins” bias.
- **Determinism**: ties are broken by `id` to keep stable ordering.

### 3) Persona blending (implemented, but optional)

- **Ranker exists**: `PersonalPlusPersonaRanker` blends normalized personal score with a normalized persona score.
- **Persona score sources**:
  - `itemScoresFromSimilarSessions[itemId]` (preferred),
  - fallback: `popularAmongSimilar` list converted to a descending score by position.
- **Note**: The persona aggregation pipeline that produces these signals is documented as a follow-up; it is not evaluated here because it is not present in this repo.

### 4) Exploration (post-ranking)

- **Goal**: avoid over-exploiting the same top items.
- **Current implementation**: probabilistic “explore-inject” from a top-N pool:
  - for each output position, with probability = `explorationRate`, pick a random unseen item from the exploration pool,
  - otherwise take the next unseen item from strict rank order,
  - pool is top **min(2000, rankedIds.length)** but at least **2×limit** when available,
  - optional `seed` makes exploration deterministic.

### 5) Offline eval / A/B readiness (instrumentation)

- **Deck response includes**:
  - `rank.rankerRunId`
  - `rank.algorithmVersion`
  - `rank.variant`, `rank.variantBucket`
  - `rank.itemIds` (served slate)
- **Client logging**: Flutter logs a `deck_response` event with `rank.*` and latency. This enables the documented “Liked-in-top-K” offline metric (see `docs/OFFLINE_EVAL.md`).

## Strengths

- **Pure, unit-tested ranker**: `scoreItem`, `PreferenceWeightsRanker`, persona blending, and exploration are all covered by Jest tests and do not depend on Firestore.
- **Deterministic core ranking**: aside from `runId`, ordering is stable; exploration can be made deterministic per session via seeding.
- **Simple, interpretable model**: content-based scoring is easy to reason about and debug; normalization helps prevent tag-count bias.
- **Offline-eval-aware shape**: rank context fields exist and are logged client-side to enable analysis without live experimentation.

## Gaps / risks (implementation-level)

### 1) Candidate set is too small by default (biggest quality limiter)

With `limit=10`, the default `DECK_CANDIDATE_CAP = limit * 2 = 20`. That means ranking is effectively “pick the best 10 out of 20”, which often makes improvements in scoring/exploration/persona invisible in real usage.

**Recommendation**: raise default `DECK_CANDIDATE_CAP` and `DECK_ITEMS_FETCH_LIMIT` in production (or make them adaptive), e.g.:
- candidateCap: 200–1000 (depending on Firestore read budget),
- itemsFetchLimit: 3×–5× candidateCap (to survive filtering).

### 2) Preference weights only learn from positive feedback

- `swipe_right` increments weights, but `swipe_left` does not decrement weights.
- There is no time decay or normalization step for long sessions.

**Result**: weights can become “sticky” and dominated by early right-swipes; negative feedback doesn’t actively suppress features.

**Recommendation**:
- decrement on left-swipe (weaker magnitude than right), and/or
- apply a cap or normalization (e.g. L2 normalization or softmax), and/or
- introduce time decay to prevent runaway dominance.

### 3) Exploration effectiveness depends on having enough rankedIds

Exploration only has meaningful room to operate if the ranker produces more than `limit` ranked IDs (a larger top-N pool). The API now supports this *when exploration is enabled*, but it still depends on candidate caps (see gap #1).

### 4) Persona blending depends on future pipeline + careful normalization

The blend normalizes persona scores by the max persona score within the candidate set. This is simple, but it can be unstable if:
- persona score distributions change across buckets,
- max persona score is an outlier (compresses the rest).

**Recommendation**: when persona is implemented, consider using robust scaling (e.g. percentile normalization) and include monitoring for “persona dominates” vs “personal dominates”.

### 5) Event storage is split (`events` vs `events_v1`)

The recommendation engine’s offline eval story is based on `events_v1`, but several API endpoints still write legacy events to `events`. This isn’t “wrong”, but it increases analysis complexity.

**Recommendation**: treat `events_v1` as canonical and either:
- migrate server-side event writes to `events_v1`, or
- clearly document that only client-originated analytics live in `events_v1`.

## Suggested next steps (prioritized)

1. **Increase candidate pool defaults** (or make adaptive) so ranking changes actually matter.
2. **Add negative learning + decay/normalization** for preference weights.
3. **Implement persona aggregation** (default bucket + “similar sessions” definition) and add offline checks.
4. **Implement offline eval script** to compute “Liked-in-top-K” + confidence intervals, segmented by `rank.variant`.
5. **Optional diversity re-rank** (MMR / per-tag caps) to reduce filter bubbles.

## Files reviewed (key)

- Ranker: `firebase/functions/src/ranker/*`
- Deck integration: `firebase/functions/src/api/deck.ts`
- Preference updates: `firebase/functions/src/api/swipe.ts`
- Docs: `docs/RECOMMENDATIONS_ENGINE.md`, `docs/OFFLINE_EVAL.md`, `docs/EVENT_SCHEMA_V1.md`


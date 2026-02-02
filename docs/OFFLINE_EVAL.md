# Swiper – Offline evaluation and A/B

This doc defines the primary offline metric, required event fields, A/B segmentation, and position-bias notes for evaluating the recommendation engine without affecting live traffic.

---

## 1. Primary offline metric

**Metric name:** **Liked-in-top-K** (per session).

**Definition:** For each session that has at least one like, compute the fraction of that session’s liked item IDs that appeared in the **union of served item IDs** across all deck_response events for that session. Aggregate: **average over sessions** (so each session counts once).

- **K:** We do not fix K; we use the full served slate. The union of rank.itemIds across deck_response events for the session is the “served set.” Alternatively, you can restrict to “liked items that appeared in the top 20 of any deck_response” by using the first 20 entries of rank.itemIds per event; document which you use.
- **Aggregation:** Per session (not per deck_request). One number: average across sessions with at least one like.
- **Required data:** events_v1 deck_response events with rank.itemIds, sessionId; likes (Firestore or like_add events) per sessionId.

**Required fields in events_v1:**

- **deck_response:** sessionId, rank.rankerRunId, rank.algorithmVersion, **rank.itemIds** (list of served item IDs), rank.variant, rank.variantBucket.
- **Likes:** Either Firestore `likes` collection (sessionId, itemId) or events_v1 like_add (sessionId, item.itemId).

**How to compute:**

1. Query events_v1 where eventName == "deck_response", optionally time-bounded (e.g. last 7 days).
2. For each sessionId, collect the union of rank.itemIds from all deck_response events for that session.
3. For each sessionId, get the set of liked itemIds (from Firestore likes or like_add events).
4. For each session with at least one like: fraction = |liked ∩ served| / |liked|.
5. Average this fraction across all such sessions.

**Reference:** [RECOMMENDATIONS_ENGINE.md](RECOMMENDATIONS_ENGINE.md) (Offline evaluation, Target metrics).

---

## 2. A/B segmentation by variant

**Use:** With rank.variant and rank.variantBucket in deck_response (and optionally in swipe/like/outbound_click events), segment events by rank.variant (e.g. `personal_only` vs `personal_only_exploration_5`).

**How to report:**

1. Segment deck_response events by rank.variant.
2. For each variant, compute the primary metric (Liked-in-top-K per session) using only sessions that received at least one deck_response with that variant (or assign each session to the variant of its first deck_response).
3. Report primary metric per variant; compare variants.
4. **Optional:** Report 95% confidence interval per variant and document minimum sample size (e.g. per variant) for meaningful comparison (see Section 4).

**Downstream events:** For consistency, swipe_left, swipe_right, like_add, like_remove, outbound_click that carry rank context should include rank.variant and rank.variantBucket when available (same deck load). The client includes these when rank context is present.

---

## 3. Position bias

**Current state:** We log positionInDeck on swipes and card_impression_start/end. Items at position 0 are more likely to be swiped (position bias).

**Offline metrics:** The primary metric (Liked-in-top-K) does **not** correct for position bias: we only check whether a liked item appeared in the served slate, not whether it was at position 0 or 20. So the metric is **uncorrected** for position.

**Optional later:** Add position-weighted metric or inverse propensity weighting (IPW) in the offline eval script if we need to compare rankers in a position-neutral way. Document in this file when implemented.

---

## 4. Statistical significance (optional)

When comparing variants:

- Report the primary metric per variant with **95% confidence interval** (e.g. bootstrap or normal approximation).
- Document **minimum sample size** per variant for meaningful comparison (e.g. “at least N sessions per variant for 5% absolute difference to be significant at 80% power”). Update this section when concrete numbers are chosen (e.g. N ≥ 500 sessions per variant).

---

## 5. How to run offline eval

- **Data source:** events_v1 (deck_response with rank.itemIds, rank.variant, rank.variantBucket), Firestore likes (or like_add in events_v1).
- **Script:** `firebase/functions/scripts/offlineEval.js`
- **Usage:** 
  ```bash
  cd firebase/functions
  node scripts/offlineEval.js [--days N] [--variant VARIANT] [--min-likes N] [--emulator]
  ```
  Or with npm:
  ```bash
  npm run offlineEval -- --days 7
  ```
- **Options:**
  - `--days N`: Only consider events from the last N days (default: 7)
  - `--variant VARIANT`: Filter by specific variant (default: all variants)
  - `--min-likes N`: Only include sessions with at least N likes (default: 1)
  - `--emulator`: Use Firestore emulator (reads FIRESTORE_EMULATOR_HOST)
- **Output:** 
  - Console: Summary stats (sessions, avg Liked-in-top-K, by-variant breakdown)
  - JSON: Detailed results in `.cursor/offline_eval_results.json`
- **Schedule:** Weekly or on-demand after collecting sufficient event data.

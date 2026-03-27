---
name: recommendations
description: Recommendation systems skill for Swiper — ranker, preference learning, collaborative filtering, offline evaluation, and autonomous research campaigns.
---

## Triggers

- "improve the ranker"
- "run an evaluation"
- "understand recommendation quality"
- "tune preference weights"

## Ranker Overview

`PreferenceWeightsRanker` ranks items based on:
- User's swipe history (right-swipes → increased weight for material, color, size, style tags)
- Collaborative filtering (persona signals from similar users)
- Featured Distribution boost (retailer-paid, relevance-gated, frequency-capped)
- Exploration component (show some non-matched items)

## Primary Metric

**Liked-in-top-K** — offline eval metric defined in `docs/OFFLINE_EVAL.md`

## Running Evaluations

```bash
./scripts/run_eval.sh        # baseline eval
./scripts/run_stress_test.sh # stress test (pre-autoresearch guardrail)
```

## Confidence Score

Per-product/segment intent metric (0–100) tracking high-intent consideration behaviors.

## Files

- `firebase/functions/src/ranker/` — ranker implementation
- `docs/OFFLINE_EVAL.md` — eval methodology
- `docs/RECOMMENDATIONS_ENGINE.md`
- `docs/AUTORESEARCH_AGENT_PROMPT.md`

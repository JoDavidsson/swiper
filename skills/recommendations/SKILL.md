# Recommendation Systems

Reusable skill for the Swiper ranker, preference learning, and offline evaluation.

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
# Baseline eval
./scripts/run_eval.sh

# Stress test (pre-autoresearch guardrail)
./scripts/run_stress_test.sh

# Autoresearch campaign
# Use docs/AUTORESEARCH_AGENT_PROMPT.md with
# $recommender-offline-evaluation-specialist + $swiper-recommendation-eval-analyst
```

## Confidence Score

Per-product/segment intent metric (0–100):
- Tracks high-intent consideration behavior (saves, shortlists, shares, comparisons)
- Used for Featured Distribution targeting and billing

## Files

- `firebase/functions/src/ranker/` — ranker implementation
- `docs/OFFLINE_EVAL.md` — eval methodology
- `docs/RECOMMENDATIONS_ENGINE.md`
- `docs/AUTORESEARCH_AGENT_PROMPT.md`

# Deep Ranker Research (2026-03-11)

## Objective
Test unorthodox-but-logical ranker improvements beyond local constant tweaks:

1. Diversity-aware MMR rerank on top ranked candidates.
2. Adaptive exploration rate based on session preference confidence.

## Hypotheses
1. MMR can improve diversity without harming oracle coverage.
2. Adaptive exploration improves coverage in low-confidence sessions.
3. A high lambda (near relevance-first) can preserve relevance while still increasing diversity.

## Method
- Dataset: 1767 active emulator items + 250 `synth_` sessions.
- Evaluator: `firebase/functions/scripts/deep_research_eval.js` (deterministic after tie-break fix).
- Metrics per variant:
  - `oracle_coverage_top_k` (primary)
  - `avg_relevance_top_k`
  - `avg_diversity_top_k`
- Compared variants each run: `baseline`, `mmr`, `mmr_adaptive`.

## Outcomes
- Early exploratory runs showed noise due ranker tie-breaking randomness.
- After deterministic evaluator fix, results were reproducible and stable:
  - `mmr` with high lambda achieved parity on coverage with meaningful diversity lift.
  - `mmr_adaptive` gave no coverage gain and slightly reduced relevance.

## Decision
- Keep MMR infrastructure behind feature flag (`RANKER_ENABLE_MMR_RERANK`).
- Recommended candidate config when enabling MMR in controlled tests:
  - `RANKER_MMR_LAMBDA=0.95`
  - `RANKER_MMR_TOP_N_MULTIPLIER=3`
- Keep adaptive exploration disabled by default for now (`RANKER_ADAPTIVE_EXPLORATION_ENABLED=false`).

## Next experiments
1. Evaluate MMR using full deck API offline evaluator (with retrieval + featured + diversity pipeline) once script parity is restored in this branch.
2. Segment deep eval by cold vs warm sessions to verify where adaptive exploration helps/hurts.
3. Add confidence intervals to the deep evaluator to avoid overfitting to tiny metric differences.

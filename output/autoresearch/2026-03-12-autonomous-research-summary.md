# Autonomous Research Summary (2026-03-12)

## Scope
Evaluate non-trivial recommendation-engine changes on emulator data with strict offline metrics and controlled emulator lifecycle.

## Data + metric contract
- Data: existing scraped active items in Firestore emulator + regenerated deterministic `synth_` sessions (`generate_fake_db.js --seed 42`).
- Offline metric script: `firebase/functions/scripts/offline_eval_liked_topk.js`.
- Metrics:
  - `oracle_preference` liked-in-top-K (proxy primary for ranking quality).
  - `likes` liked-in-top-K (historical-like overlap).

## Validity fixes applied
1. Replaced stale long-running emulator process with `firebase emulators:exec` per config.
2. Added per-config probe validation (`rank.variant`, exploration rate, MMR flags, rank window fields).
3. Corrected result parsing bug where `false` was mistakenly treated as missing (`jq //` fallback issue).

## New hypotheses tested
1. Retrieval breadth (`DECK_ITEMS_FETCH_LIMIT`, `DECK_CANDIDATE_CAP`) is the dominant quality driver.
2. In high-breadth regime, exploration helps less or hurts oracle coverage.
3. In high-breadth regime, MMR rerank still regresses oracle coverage.
4. There is an optimal rank window depth (`DECK_RANK_WINDOW_MULTIPLIER`) before returns decline.
5. Practical rollout should optimize quality-latency frontier, not quality alone.

## Experiment sets run
- Set A (clean config matrix): `output/autoresearch/2026-03-11-deep-ranker-research-03/results_corrected.tsv` (8 configs).
- Set B (rank-window matrix v2): `output/autoresearch/2026-03-12-deep-ranker-research-05/results.tsv` (7 configs + 1 MMR confirmation).
- Set C (cap/latency frontier): `output/autoresearch/2026-03-12-deep-ranker-research-06/results.tsv` (4 configs).

Total clean experiments this phase: **20**.

## Key results
### 1) Breadth lift is real
- Baseline regime (candidate ~120): oracle around `0.0208`.
- Wide regime (`DECK_CANDIDATE_CAP=1200`, `DECK_ITEMS_FETCH_LIMIT=2000`): oracle around `0.1856-0.1932`.
- Absolute lift: about `+0.165` to `+0.172`.

### 2) Best oracle in tested space
- `cap1200 + fetch2000 + rankWindowMultiplier=48 + exploration=0 + mmr=false`:
  - oracle: `0.193200`
  - likes: `0.001692`

### 3) MMR still regresses at best window
- Same config with `MMR lambda=0.95 topN x3`:
  - oracle: `0.180800` (worse than `0.193200`)
  - likes: `0.001692` (flat)

### 4) Exploration in wide regime did not help
- `exp=0.08` under wide/window settings reduced oracle vs `exp=0` in tested configs.
- Likes stayed flat in this synthetic setup.

### 5) Latency tradeoff is steep
Compared to baseline (~`289ms` avg, `402ms` p95):
- `cap240`: `328ms` avg, `415ms` p95, oracle `0.0408`.
- `cap400`: `452ms` avg, `630ms` p95, oracle `0.0736`.
- `cap800`: `708ms` avg, `887ms` p95, oracle `0.1384`.
- `cap1200`: `965ms` avg, `1245ms` p95, oracle `0.1856`.

## Decisions from this phase
1. Keep `RANKER_ENABLE_MMR_RERANK=false` by default.
2. Keep adaptive exploration disabled for now in this offline objective.
3. Keep `DECK_RANK_WINDOW_MULTIPLIER` knob (default `48`) for controlled tuning.
4. Treat retrieval breadth as primary lever; rollout should be staged by latency budget.

## Recommended rollout candidates
- Conservative candidate:
  - `DECK_CANDIDATE_CAP=400`
  - `DECK_ITEMS_FETCH_LIMIT=700`
  - `DECK_RANK_WINDOW_MULTIPLIER=48`
  - `RANKER_EXPLORATION_RATE=0`
  - `RANKER_ENABLE_MMR_RERANK=false`
- Aggressive candidate (max quality in this offline study):
  - `DECK_CANDIDATE_CAP=1200`
  - `DECK_ITEMS_FETCH_LIMIT=2000`
  - `DECK_RANK_WINDOW_MULTIPLIER=48`
  - `RANKER_EXPLORATION_RATE=0`
  - `RANKER_ENABLE_MMR_RERANK=false`

## Code changes made during this phase
- Added MMR + adaptive exploration integration and flags in deck pipeline (already in branch changes).
- Reverted deterministic tie-break patch in rankers (regressed metrics in strict eval).
- Added `DECK_RANK_WINDOW_MULTIPLIER` env knob in `firebase/functions/src/api/deck.ts`.
- Updated docs:
  - `docs/RECOMMENDATIONS_ENGINE.md`
  - `docs/TESTING_LOCAL.md`

## Repro artifacts
- Scripts:
  - `output/autoresearch/2026-03-11-deep-ranker-research-03/run_matrix.sh`
  - `output/autoresearch/2026-03-12-deep-ranker-research-05/run_wide_window_matrix_v2.sh`
  - `output/autoresearch/2026-03-12-deep-ranker-research-06/run_cap_latency_matrix.sh`
- Tables:
  - `output/autoresearch/2026-03-11-deep-ranker-research-03/results_corrected.tsv`
  - `output/autoresearch/2026-03-12-deep-ranker-research-05/results.tsv`
  - `output/autoresearch/2026-03-12-deep-ranker-research-06/results.tsv`

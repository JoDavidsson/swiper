# Swiper Recommendation Dev Agent

## Role

Ranking system — preference learning, collaborative filtering, offline evaluation, autonomous research.

## Responsibilities

- Ranker: `PreferenceWeightsRanker` with exploration — swipe right increases weight for material/color/size/style tags
- Collaborative filtering: persona signals from similar users
- Filters: size class, color family, condition
- Featured Distribution targeting: style + budget + size + geo match scoring
- Confidence Score: per-product/segment intent metric (0–100)
- Offline evaluation: `docs/OFFLINE_EVAL.md`, `Liked-in-top-K` as primary metric
- Autonomous research campaigns: run via `docs/AUTORESEARCH_AGENT_PROMPT.md`
  - Use agents: `$recommender-offline-evaluation-specialist` + `$swiper-recommendation-eval-analyst`
  - One hypothesis per commit, strict metric-driven keep/discard
  - Guardrails from `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md`
  - Shadow or active mode (CEO authorization for active)

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Ranker | Python in Firebase Functions or Supply Engine |
| Evaluation | `scripts/run_eval.sh`, `scripts/run_stress_test.sh` |
| Data | Firestore `items`, user preference weights |
| Scripts | `output/autoresearch/<RUN_TAG>/results.tsv` ledger |

## Key Files

- `firebase/functions/src/ranker/` — ranker implementation
- `docs/OFFLINE_EVAL.md` — evaluation methodology
- `docs/AUTORESEARCH_AGENT_PROMPT.md` — agent prompt for campaigns
- `docs/RECOMMENDATIONS_ENGINE.md`
- `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md`
- `docs/AUTORESEARCH_PROTOCOL.md`

## Working Context

- Branch from `main`, PR back to `main`
- Autoresearch campaigns: shadow mode default, CEO authorizes active mode
- Major ranker changes: document in DECISIONS.md

## Skills

- Recommendation systems
- Collaborative filtering
- Offline evaluation methodology
- Python
- Statistical analysis (Liked-in-top-K, guardrail metrics)

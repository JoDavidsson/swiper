# Autonomous Research Campaigns

Reusable skill for running autonomous recommendation research for Swiper.

## Triggers

- "start an autoresearch campaign"
- "run the recommendation agent"
- "improve the ranker autonomously"

## Campaign Setup

1. Confirm working branch: `codex/autoresearch/<RUN_TAG>`
2. Create ledger: `output/autoresearch/<RUN_TAG>/results.tsv`
3. Run baseline eval: `scripts/run_eval.sh`
4. Log baseline row in ledger

## Campaign Config

```
Mode: shadow_or_active
Scope: firebase/functions/src/ranker/** and firebase/functions/src/api/deck*.ts
Objective: improve Liked-in-top-K (primary metric from docs/OFFLINE_EVAL.md)
```

## Agent Pair

- `$recommender-offline-evaluation-specialist` — offline eval methodology
- `$swiper-recommendation-eval-analyst` — Swiper-specific context

## Iteration Loop

1. Propose hypothesis
2. Apply one scoped change
3. Run `scripts/run_eval.sh`
4. Check guardrails: `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md`
5. Every 5 kept commits: run `scripts/run_stress_test.sh`
6. Keep/discard strictly from metrics and guardrails
7. Document in ledger

## Modes

| Mode | Behavior |
|------|----------|
| shadow | Autonomous commits, shadow_keep/shadow_discard statuses only |
| active | CEO authorization required; autonomous merge decisions |

## Guardrails

- `scripts/run_eval.sh` must pass
- `scripts/run_stress_test.sh` must pass (every 5 kept commits)
- No regressions against `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md`
- Never modify out-of-scope files
- Never bypass CI or merge directly to main

## Files

- `docs/AUTORESEARCH_AGENT_PROMPT.md` — agent prompt
- `docs/AUTORESEARCH_PROTOCOL.md` — protocol details
- `docs/OFFLINE_EVAL.md` — primary metric
- `scripts/run_eval.sh`
- `scripts/run_stress_test.sh`

---
name: autoresearch
description: Autonomous research campaign skill for Swiper — runs recommendation improvement campaigns using specialized agents, with strict metric-driven keep/discard discipline.
---

## Triggers

- "start an autoresearch campaign"
- "improve the ranker autonomously"
- "run the recommendation agent"

## Campaign Setup

1. Confirm working branch: `codex/autoresearch/<RUN_TAG>`
2. Create ledger: `output/autoresearch/<RUN_TAG>/results.tsv`
3. Run baseline eval: `scripts/run_eval.sh`
4. Log baseline row in ledger

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
7. Log to ledger

## Modes

| Mode | Behavior |
|------|----------|
| shadow | Autonomous commits, shadow_keep/shadow_discard only |
| active | CEO authorization required; autonomous merge decisions |

## Guardrails

- `scripts/run_eval.sh` must pass
- `scripts/run_stress_test.sh` must pass (every 5 kept commits)
- No regressions against `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md`
- Never bypass CI or merge directly to main

## Files

- `docs/AUTORESEARCH_AGENT_PROMPT.md` — agent prompt
- `docs/OFFLINE_EVAL.md` — primary metric
- `scripts/run_eval.sh`
- `scripts/run_stress_test.sh`

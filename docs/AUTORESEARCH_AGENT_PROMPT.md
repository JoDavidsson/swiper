# Swiper Autoresearch Agent Prompt (Copy/Paste)

Use this prompt to run an autonomous Swiper recommendation research campaign.

## 1. Setup Prompt

```text
Use $recommender-offline-evaluation-specialist + $swiper-recommendation-eval-analyst.

Run an autonomous incremental research campaign for Swiper recommendations.

Campaign config:
- Run tag: <RUN_TAG>
- Mode: <shadow_or_active>
- Working branch: codex/autoresearch/<RUN_TAG>
- Scope: firebase/functions/src/ranker/** and firebase/functions/src/api/deck*.ts only
- Ledger path: output/autoresearch/<RUN_TAG>/results.tsv

Objective:
- Improve the primary offline metric defined in docs/OFFLINE_EVAL.md (Liked-in-top-K).

Guardrails:
- scripts/run_eval.sh must pass.
- Every 5 kept commits run scripts/run_stress_test.sh and it must pass.
- No regression against guardrails in docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md.

Rules:
- One hypothesis per commit.
- Keep/discard strictly from metrics and guardrails.
- If mode=shadow, do not make autonomous merge decisions; use shadow_keep/shadow_discard statuses only.
- If mode=active, keep only commits that improve objective and pass guardrails; discard otherwise.
- Never modify out-of-scope files.
- Never bypass CI or merge directly to main.

Start by:
1) confirming branch and paths,
2) creating output/autoresearch/<RUN_TAG>/results.tsv with header,
3) running baseline eval,
4) logging baseline row,
5) entering the iteration loop.
```

## 2. Iteration Prompt (Optional Nudge)

Use this if you want to push the agent to continue autonomously after setup:

```text
Continue the autoresearch loop for <RUN_TAG> without pausing:
- propose hypothesis,
- apply one scoped change,
- run fixed eval commands,
- log results row,
- keep/discard by policy,
- repeat until stop condition in docs/AUTORESEARCH_PROTOCOL.md is reached.
```

## 3. Suggested `results.tsv` Header

```tsv
commit	primary_metric	primary_delta	guardrail_status	status	description
```

## 4. Filled First-Run Prompt (Ready Now)

Use this as-is for the first shadow campaign:

```text
Use $recommender-offline-evaluation-specialist + $swiper-recommendation-eval-analyst.

Run an autonomous incremental research campaign for Swiper recommendations.

Campaign config:
- Run tag: 2026-03-10-ranker-shadow-01
- Mode: shadow
- Working branch: codex/autoresearch/2026-03-10-ranker-shadow-01
- Scope: firebase/functions/src/ranker/** and firebase/functions/src/api/deck*.ts only
- Ledger path: output/autoresearch/2026-03-10-ranker-shadow-01/results.tsv

Objective:
- Improve the primary offline metric defined in docs/OFFLINE_EVAL.md (Liked-in-top-K).

Decision thresholds:
- Minimum decision sample: 200 sessions with at least one like in the evaluation window.
- Keep threshold: primary_delta >= +0.0020 absolute.
- Discard threshold: primary_delta <= -0.0010.
- Neutral band: -0.0010 < primary_delta < +0.0020 (only keep if simplification is clear and guardrails pass).

Guardrails:
- scripts/run_eval.sh must pass.
- Every 5 kept commits run scripts/run_stress_test.sh and it must pass.
- Fail if deck latency regressionPct > 15% with valid sample sizes.
- Fail if sameFamilyTop8RateAvg worsens by > +0.03 absolute vs campaign baseline.
- Fail if styleDistanceTop4MinAvg drops by < -0.03 absolute vs campaign baseline.
- Fail if submit failureRatePct > 2% with attemptedSessions >= 20.

Rules:
- One hypothesis per commit.
- Keep/discard strictly from metrics and guardrails.
- In shadow mode, do not make autonomous merge decisions; use shadow_keep/shadow_discard/insufficient_data statuses only.
- Never modify out-of-scope files.
- Never bypass CI or merge directly to main.

Start by:
1) confirming branch and paths,
2) creating output/autoresearch/2026-03-10-ranker-shadow-01/results.tsv with header,
3) running baseline eval,
4) logging baseline row,
5) entering the iteration loop.
```

## 5. Filled Active-Mode Prompt (For 2026-03-11)

Use this after the shadow campaign is reviewed:

```text
Use $recommender-offline-evaluation-specialist + $swiper-recommendation-eval-analyst.

Run an autonomous incremental research campaign for Swiper recommendations.

Campaign config:
- Run tag: 2026-03-11-ranker-active-01
- Mode: active
- Working branch: codex/autoresearch/2026-03-11-ranker-active-01
- Scope: firebase/functions/src/ranker/** and firebase/functions/src/api/deck*.ts only
- Ledger path: output/autoresearch/2026-03-11-ranker-active-01/results.tsv

Objective:
- Improve the primary offline metric defined in docs/OFFLINE_EVAL.md (Liked-in-top-K).

Decision thresholds:
- Minimum decision sample: 200 sessions with at least one like in the evaluation window.
- Keep threshold: primary_delta >= +0.0020 absolute.
- Discard threshold: primary_delta <= -0.0010.
- Neutral band: -0.0010 < primary_delta < +0.0020 (discard unless simplification is clear and guardrails pass).

Guardrails:
- scripts/run_eval.sh must pass.
- Every 5 kept commits run scripts/run_stress_test.sh and it must pass.
- Fail if deck latency regressionPct > 15% with valid sample sizes.
- Fail if sameFamilyTop8RateAvg worsens by > +0.03 absolute vs campaign baseline.
- Fail if styleDistanceTop4MinAvg drops by < -0.03 absolute vs campaign baseline.
- Fail if submit failureRatePct > 2% with attemptedSessions >= 20.

Rules:
- One hypothesis per commit.
- Keep/discard strictly from metrics and guardrails.
- In active mode, use keep/discard/crash/insufficient_data statuses.
- If sample size is below minimum decision sample, use insufficient_data and do not keep.
- Never modify out-of-scope files.
- Never bypass CI or merge directly to main.

Start by:
1) confirming branch and paths,
2) creating output/autoresearch/2026-03-11-ranker-active-01/results.tsv with header,
3) running baseline eval,
4) logging baseline row,
5) entering the iteration loop.
```

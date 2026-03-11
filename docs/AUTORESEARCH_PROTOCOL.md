# Swiper Autoresearch Protocol (Ranker Lane)

Last updated: 2026-03-10
Owner: Recommendations Engineering
Status: Ready for pilot

## 1. Purpose

Run incremental autonomous research on Swiper recommendations using a keep/discard loop:

1. Propose one hypothesis.
2. Make one scoped change.
3. Run fixed evaluation commands.
4. Keep commit only if objective improves and guardrails pass.
5. Repeat.

This protocol adapts the `karpathy/autoresearch` method to the Swiper codebase.

## 2. Scope (Phase 1)

In scope:

- `firebase/functions/src/ranker/**`
- `firebase/functions/src/api/deck*.ts`
- `firebase/functions/scripts/**` (evaluation helpers only)
- Documentation and run artifacts

Out of scope in phase 1:

- Flutter UI changes
- Supply ingestion extraction logic
- Production deploy automation changes

## 3. Metric Contract

Primary objective:

- Maximize Liked-in-top-K as defined in [OFFLINE_EVAL.md](./OFFLINE_EVAL.md).

Guardrails:

- No CI regression in [ci.yml](../.github/workflows/ci.yml).
- No stress test failures in [`./scripts/run_stress_test.sh`](../scripts/run_stress_test.sh).
- No deck latency or quality alert regression using [RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md](./RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md).

## 4. Prerequisites Before Active Mode

Required before autonomous keep/discard runs:

1. Single analytics source of truth for evaluation-sensitive paths:
- Use `events_v1` contracts from [EVENT_SCHEMA_V1.md](./EVENT_SCHEMA_V1.md) and [OFFLINE_EVAL.md](./OFFLINE_EVAL.md).
- Remove or isolate legacy `events` dependencies from ranking evaluation paths.
2. Reproducible offline metric output per run:
- Produce a per-run scalar for primary objective (Liked-in-top-K).
3. Baseline run recorded for the selected run tag.

Current note (2026-03-10): repository scripts include `run_eval.sh` and `run_stress_test.sh`, but a dedicated offline-eval runner that emits Liked-in-top-K per variant is not yet present in `firebase/functions/scripts`.

## 5. Run Modes

Use one of two modes:

- `shadow`: loop runs, artifacts and hypotheses are generated, but no autonomous merge decisions.
- `active`: loop performs keep/discard decisions automatically from metric gates.

Default for first campaign: `shadow` for 1-2 nights, then `active`.

## 6. Installation Steps

1. Pick run tag:
- Example: `2026-03-10-ranker-pilot`.
2. Create campaign branch:
- `git checkout -b codex/autoresearch/<run-tag>`
3. Create run directory:
- `output/autoresearch/<run-tag>/`
4. Initialize ledger file:
- `output/autoresearch/<run-tag>/results.tsv`
5. Freeze evaluation commands for the campaign:
- Always run `./scripts/run_eval.sh`
- Every 5 kept commits run `./scripts/run_stress_test.sh`
6. Paste the agent prompt from [AUTORESEARCH_AGENT_PROMPT.md](./AUTORESEARCH_AGENT_PROMPT.md) with the run tag and mode.

## 7. Iteration Loop

Each iteration must follow this order:

1. Read current branch + head commit.
2. Propose one hypothesis with expected directional effect.
3. Apply one scoped change.
4. Commit with a short hypothesis label.
5. Run fixed eval commands.
6. Parse metrics and guardrails.
7. Write one row to `results.tsv`.
8. Keep or discard commit:
- Keep if primary improves and all guardrails pass.
- Discard if primary does not improve, is neutral without simplification benefit, or any guardrail fails.

## 8. Keep/Discard Policy

Numeric thresholds (phase 1 default):

- Minimum decision sample: at least `200` sessions with at least one like in the evaluation window.
- Keep threshold: `primary_delta >= +0.0020` (absolute Liked-in-top-K lift).
- Discard threshold: `primary_delta <= -0.0010`.
- Neutral band: `-0.0010 < primary_delta < +0.0020`.
- Neutral-band keep exception: only keep if the change clearly simplifies logic and still passes all guardrails.

Hard discard conditions:

- Any test failure from `./scripts/run_eval.sh`.
- Any failed request or test in `./scripts/run_stress_test.sh`.
- Any alert-condition breach in latency or quality guardrails.
- Crash, timeout, or non-reproducible output.
- Evaluation sample below minimum decision sample in active mode.

Keep conditions:

- Primary objective improves by meaningful margin, and guardrails pass.
- Or primary is flat but code is materially simpler and all guardrails pass.

Neutral changes that add complexity are discarded.

Guardrail thresholds (phase 1 default):

- Deck latency: fail if `regressionPct > 15%` with valid sample sizes (as in runbook alert condition).
- First-slate duplicate-family rate: fail if `sameFamilyTop8RateAvg` worsens by more than `+0.03` absolute vs campaign baseline.
- First-slate style variety: fail if `styleDistanceTop4MinAvg` drops by more than `-0.03` absolute vs campaign baseline.
- Onboarding submit reliability (if observed in run window): fail if `failureRatePct > 2%` and `attemptedSessions >= 20`.

## 9. Failure and Safety Controls

1. Timeout per iteration:
- Stop iteration if evaluation exceeds 15 minutes total.
2. Crash handling:
- Fix obvious issue once.
- If repeated crash on same hypothesis, log `crash` and move on.
3. Consecutive failure stop:
- Stop campaign after 5 consecutive crashes/discards and require human review.
4. Blast radius limit:
- Do not touch non-scope paths in phase 1.

## 10. Ledger Format

`results.tsv` is tab-separated with this header:

```tsv
commit	primary_metric	primary_delta	guardrail_status	status	description
```

Suggested `status` values:

- `keep`
- `discard`
- `crash`
- `shadow_keep`
- `shadow_discard`
- `insufficient_data`

Example rows:

```tsv
commit	primary_metric	primary_delta	guardrail_status	status	description
1a2b3c4	0.2140	+0.0031	pass	keep	increase persona blend alpha for cold-start cohort
2b3c4d5	0.2139	-0.0001	pass	discard	added retrieval lane weighting complexity with no gain
3c4d5e6	0.0000	0.0000	fail	crash	OOM after candidate cap increase
```

## 11. Human Review Cadence

Daily or per campaign window:

1. Review top kept commits.
2. Spot-check tradeoff quality (improvement vs complexity).
3. Open PR with kept commits only.
4. Run normal CI and staging checks before merge.

No direct merge from autonomous campaign branch to `main`.

## 12. Recommended Pilot Plan

Night 1:

- Mode: `shadow`
- Duration: 2-3 hours
- Goal: validate artifact quality and decision logic

Night 2:

- Mode: `shadow`
- Duration: 4-6 hours
- Goal: verify stability under longer loop

Night 3+:

- Mode: `active` (if prerequisites are met)
- Duration: 6-8 hours
- Goal: harvest keep-worthy ranking improvements

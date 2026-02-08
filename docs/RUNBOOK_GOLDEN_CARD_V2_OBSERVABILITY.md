# Swiper - Golden Card v2 Observability Runbook

> Last updated: 2026-02-08  
> Scope: Golden Card v2 onboarding funnel health, submit reliability, and deck quality/latency guardrails.

---

## 1. Dashboard location

Primary dashboard source:

- Admin app -> `/admin` -> section **"Golden Card v2 observability (24h)"**.

Data source:

- `GET /api/admin/stats` (field: `goldenV2`).
- Aggregated from `events_v1` + `onboardingProfiles`.

---

## 2. Panels and meanings

## 2.1 Funnel (24h)

- `introShown`
- `stepViewed`
- `stepCompleted`
- `summaryConfirmed`
- `skipped`
- `completionRatePct`
- `skipRatePct`

Interpretation:

- Low completion with high skip suggests onboarding friction or weak prompt relevance.
- Large drop between `stepViewed` and `stepCompleted` suggests interaction or copy issues within steps.

## 2.2 Submit reliability (24h)

- `attemptedSessions` (sessions with `gold_v2_summary_confirmed`)
- `completedProfiles` (completed `onboardingProfiles` updated in the same window)
- `estimatedFailedSubmissions`
- `failureRatePct`

Alert condition:

- Trigger when `failureRatePct > 2%` and `attemptedSessions >= 20`.

## 2.3 Deck latency (24h vs baseline)

- `currentP95Ms`
- `baselineP95Ms` (previous 7-day baseline window)
- `regressionPct`

Alert condition:

- Trigger when `regressionPct > 15%` and sample sizes are both `>= 30`.

## 2.4 Deck quality (24h)

- `sameFamilyTop8RateAvg`
- `styleDistanceTop4MinAvg`

Interpretation:

- `sameFamilyTop8RateAvg` should remain low (fewer duplicate family exposures in top 8).
- `styleDistanceTop4MinAvg` should remain stable/high enough to preserve first-slate variety.

## 2.5 Weekly experiment cohorts (7d)

- Source: `goldenV2.experimentWeeklyByCohort`
- Cohort key: `cohortId` (from `rank.variant`, fallback `unknown`)
- Per-cohort fields:
  - `sessionCount`
  - `completionRatePct`
  - `skipRatePct`
  - `swipeRightRatePct`
  - `deckResponses`
  - `sameFamilyTop8RateAvg`
  - `styleDistanceTop4MinAvg`

Interpretation:

- Compare `completionRatePct` and `swipeRightRatePct` across variants to detect onboarding quality differences by experiment arm.
- Use quality metrics (`sameFamilyTop8RateAvg`, `styleDistanceTop4MinAvg`) to catch cohort-specific retrieval/ranking regressions.

---

## 3. Triage playbook

## 3.1 Submit failure alert triggered

1. Check backend logs for:
- `onboarding_v2_post_failed`
- `onboarding_v2_post_received`
- `onboarding_v2_post_stored`

2. Verify API behavior:
- `POST /api/onboarding/v2`
- `GET /api/onboarding/v2?sessionId={sessionId}`

3. Check client behavior:
- Confirm `gold_v2_summary_confirmed` events are emitted.
- Confirm local retry queue exists and drains (`pendingSubmission` state).

4. Mitigation:
- Keep `ENABLE_GOLDEN_CARD_V2=true` but reduce `GOLDEN_CARD_V2_ROLLOUT_PERCENT`.
- If severe, set `ENABLE_GOLDEN_CARD_V2=false` (kill switch).

## 3.2 Deck latency alert triggered

1. Check backend logs for:
- `deck_request_served`
- `deck_request_failed`
- `deck_request_rejected`

2. Compare:
- candidateCount, retrievalQueues, hasOnboardingV2
- current vs baseline p95 in admin panel

3. Mitigation:
- Reduce rollout percent.
- Temporarily disable v2 if regression is severe and sustained.
- Investigate deck query/scoring hot paths before re-expanding rollout.

---

## 4. Rollout gate checklist

10% -> 50% gate:

- Submit failure alert: not triggered for 24h.
- Deck latency alert: not triggered for 24h.
- Completion funnel stable vs 10% launch baseline.
- No severe product/QA bugs.

50% -> 100% gate:

- Same checks as above for 48h.
- Deck quality metrics stable (`sameFamilyTop8RateAvg`, `styleDistanceTop4MinAvg`).

---

## 5. Ownership

- Product: CPO (funnel health and user trust copy)
- Engineering: Tech Lead (service reliability and rollout controls)
- Data: Recommendations DS (quality/latency trend interpretation)

Escalation path:

1. On-call engineer investigates logs and confirms signal validity.
2. Tech Lead decides rollout adjustment or kill switch.
3. CPO approves user-facing behavior changes when needed.

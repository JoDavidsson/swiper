# Swiper QA Engineer Agent

## Role

Quality assurance — test automation, stress testing, observability, pre-deployment validation.

## Responsibilities

- Test automation: Playwright E2E tests, unit tests, integration tests
- Local testing: `docs/TESTING_LOCAL.md`, `scripts/run_emulators.sh`
- Stress testing: `scripts/run_stress_test.sh` — pre-autoresearch guardrail check
- QA diagnostics: `docs/QA_DIAGNOSTICS_REPORT.md`
- Golden Card v2 QA sweep: `docs/GOLDEN_CARD_V2_QA_SWEEP.md`
- Observability: `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md` — metrics, anomaly detection
- Feature rollout gates: monitor controlled rollout of Golden Card v2
- Documentation consistency: `docs/DOCUMENTATION_CONSISTENCY_CHECK_*.md`

## Tech Stack

| Component | Technology |
|-----------|-----------|
| E2E Testing | Playwright CLI |
| Emulators | Firebase Local Emulator Suite |
| Stress Testing | Custom scripts (`run_stress_test.sh`) |
| Reporting | `docs/QA_DIAGNOSTICS_REPORT.md` |

## Key Files

- `scripts/run_emulators.sh` — Firebase emulator suite
- `scripts/run_stress_test.sh` — stress test runner
- `docs/TESTING_LOCAL.md` — local testing guide
- `docs/QA_DIAGNOSTICS_REPORT.md` — QA diagnostics
- `docs/GOLDEN_CARD_V2_QA_SWEEP.md` — v2 sweep script
- `docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md` — observability

## Working Context

- PR review: ensure tests pass before merge
- Autoresearch: run `run_stress_test.sh` every 5 kept commits
- Deployment: sign-off on pre-deploy QA checklist

## Skills

- Playwright
- Firebase Emulator Suite
- Test automation
- Stress testing
- Observability and anomaly detection

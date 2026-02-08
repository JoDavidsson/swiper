# Swiper - Golden Card v2 Execution Roadmap

> Last updated: 2026-02-08  
> Scope: Delivery plan from approved UX spec to production rollout  
> Primary references: `docs/GOLDEN_CARD_V2_UI_UX_SPEC.md`, `docs/RECOMMENDATIONS_ENGINE.md`

---

## 1. Public role discussion (delivery council)

### Hat: CPO

- Priority: launch a flow that clearly sets taste direction and increases trust.
- KPI demand: early-like rate, onboarding completion, and first-session satisfaction proxy.
- Constraint: do not break Tinder-like speed.

### Hat: CTO

- Priority: isolate risk through additive v2 contract and safe fallback to v1.
- KPI demand: no production regression in deck latency and error rate.
- Constraint: staged rollout with kill switch.

### Hat: Tech Lead

- Priority: deterministic state machine, explicit interfaces, testable ranking constraints.
- KPI demand: no hidden side effects in deck provider and onboarding provider.
- Constraint: avoid big-bang rewrite.

### Hat: Data Scientist (Recommendations)

- Priority: improve cold-start signal entropy and top-K diversity.
- KPI demand: measurable lift in liked-in-top-K and reduced duplicate exposure.
- Constraint: explicit offline and online experiment design before full rollout.

### Hat: Systems Architect

- Priority: clear service contracts, schema versioning, and observability.
- KPI demand: every step observable end-to-end from UI event to rank response.
- Constraint: backwards compatibility with current `onboardingPicks` and persona pipeline.

### Final CPO release call

Proceed with phased delivery, additive v2 schema, and progressive rollout:

1. Internal QA -> dogfood
2. 10% traffic A/B
3. 50% traffic if guardrails pass
4. 100% rollout with v1 fallback retained for 2 weeks

---

## 2. Delivery architecture (what we are building)

## 2.1 New/updated data contracts

### New endpoint

- `POST /api/onboarding/v2`
- `GET /api/onboarding/v2`

### New document

- `onboardingProfiles/{sessionId}`

### Key fields

- `version` (number, required)
- `sceneArchetypes` (string[])
- `sofaVibes` (string[])
- `constraints` (object)
- `derivedProfile` (object)
- `status` (`completed`, `skipped`, `in_progress`)

### Deck contract extension

- `rank.onboardingProfile.primaryStyle`
- `rank.onboardingProfile.secondaryStyle`
- `rank.onboardingProfile.confidence`
- `rank.onboardingProfile.explanation[]`

## 2.2 Ranking pipeline changes

- Retrieval: enforce diversity hard constraints for first render set.
- Scoring: blend style-archetype priors with existing preference weights.
- Re-ranking: apply family dedupe and minimum style-distance constraint.
- Fallback: if v2 missing, use existing v1 picks and persona/default flow.

## 2.3 Frontend architecture changes

- Replace current overlay-only gold card pattern with route-backed multi-step flow.
- Maintain in-progress state in Hive and resume support.
- Add reaffirmation UI and post-confirm transition before first deck load.

---

## 3. Milestone plan with dates

## Milestone M0 - Alignment and prep (2026-02-09 to 2026-02-10)

### Outcomes

- Spec signoff
- Backlog locked
- Experiment design approved

### Tasks

| ID | Owner | Task | Output |
|----|------|------|--------|
| M0-1 | CPO | Final signoff on `docs/GOLDEN_CARD_V2_UI_UX_SPEC.md` | Signed spec |
| M0-2 | CTO | Confirm rollout + kill-switch strategy | Rollout memo |
| M0-3 | Tech Lead | Define implementation branch plan and module boundaries | Tech plan |
| M0-4 | DS | Finalize metrics and experiment guardrails | Experiment brief |
| M0-5 | Architect | Approve schema and endpoint versioning | API/schema ADR |

---

## Milestone M1 - Content and taxonomy readiness (2026-02-10 to 2026-02-14)

### Outcomes

- Scene and vibe assets curated
- Token taxonomy finalized for ranking inputs

### Tasks

| ID | Owner | Task | Output | Dependency |
|----|------|------|--------|------------|
| M1-1 | CMO + Design | Curate GC1 scene set variants (4 per cohort) | Asset pack | M0-1 |
| M1-2 | CMO + Design | Curate GC2 sofa vibe set with family dedupe | Asset pack | M0-1 |
| M1-3 | DS | Define archetype and vibe token dictionary | Token map JSON | M1-1, M1-2 |
| M1-4 | Architect | Define storage format for curated assets in Firestore | Schema doc | M1-1 |
| M1-5 | QA | Validate image quality gates and diversity checks | QA report | M1-1, M1-2 |

---

## Milestone M2 - Backend and ranking contract (2026-02-13 to 2026-02-20)

### Outcomes

- v2 onboarding API live
- Deck consumes v2 profile with fallback
- Diversity constraints integrated

### Tasks

| ID | Owner | Task | Output | Dependency |
|----|------|------|--------|------------|
| M2-1 | Tech Lead | Add `onboarding/v2` API handlers | New endpoints | M0-3 |
| M2-2 | Architect | Add `onboardingProfiles` schema + indexes | Firestore migration | M2-1 |
| M2-3 | DS | Implement style prior scoring function | Ranker patch | M1-3 |
| M2-4 | Tech Lead | Implement family dedupe + style-distance rerank | Deck patch | M2-3 |
| M2-5 | Architect | Add response payload `rank.onboardingProfile` | API contract update | M2-4 |
| M2-6 | QA | Unit tests for endpoint and rank logic | Passing tests | M2-1..M2-5 |

---

## Milestone M3 - Flutter UX build (2026-02-17 to 2026-02-26)

### Outcomes

- Full v2 onboarding flow in app
- Localized copy complete
- Resume and skip behavior complete

### Tasks

| ID | Owner | Task | Output | Dependency |
|----|------|------|--------|------------|
| M3-1 | Flutter Dev | Build `GoldenFlowScreen` and step scaffold | UI shell | M0-1 |
| M3-2 | Flutter Dev | Implement GC1 + GC2 selection steps | Working step UI | M3-1 |
| M3-3 | Flutter Dev | Implement GC3 constraint step | Working step UI | M3-1 |
| M3-4 | Flutter Dev | Implement GC4 reaffirmation | Summary UI | M2-5 |
| M3-5 | Flutter Dev | Add Hive persistence and resume logic | Stateful flow | M3-2, M3-3 |
| M3-6 | Flutter Dev | Wire API client to onboarding v2 | API integration | M2-1 |
| M3-7 | Localization | Add EN/SV keys and translations | `app_strings` updates | M3-2..M3-4 |
| M3-8 | QA | Widget tests and interaction tests | Passing test suite | M3-1..M3-7 |

---

## Milestone M4 - Instrumentation and QA sweep (2026-02-24 to 2026-03-01)

### Outcomes

- End-to-end event coverage
- Performance baseline and accessibility checks

### Tasks

| ID | Owner | Task | Output | Dependency |
|----|------|------|--------|------------|
| M4-1 | DS | Implement event schema updates for v2 steps | Event schema PR | M2-1, M3-1 |
| M4-2 | Tech Lead | Add request correlation from onboarding -> deck | Correlated logs | M2-5, M3-6 |
| M4-3 | QA | Accessibility sweep (screen reader, keyboard, contrast) | QA checklist | M3-8 |
| M4-4 | QA | Performance sweep (first paint, step transition, deck load) | Perf report | M3-8 |
| M4-5 | Architect | Confirm dashboard and alert coverage | Ops checklist | M4-1, M4-2 |

---

## Milestone M5 - Controlled rollout (2026-03-02 to 2026-03-15)

### Outcomes

- Safe production rollout with decision gates

### Tasks

| ID | Owner | Task | Output | Dependency |
|----|------|------|--------|------------|
| M5-1 | CTO | Enable 10% A/B traffic | Feature flag update | M4 complete |
| M5-2 | DS | Evaluate week-1 metrics and guardrails | Experiment readout | M5-1 |
| M5-3 | CPO | Go/no-go to 50% | Decision memo | M5-2 |
| M5-4 | CTO | Move to 50% then 100% | Rollout logs | M5-3 |
| M5-5 | Tech Lead | Keep v1 fallback for 14 days and then deprecate | Decommission plan | M5-4 |

---

## 4. Detailed implementation TODO list (engineer-ready)

## 4.1 Product and design TODOs

- [x] Final asset taxonomy and naming convention.
- [x] Define allowed archetype combinations and conflict rules.
- [x] Approve all EN/SV copy in one content source.
- [x] Prepare fallback static asset pack for offline/error mode.

## 4.2 Flutter TODOs

- [x] Gate Golden Card v2 in deck/app startup flow using feature flags + rollout percent buckets.
- [x] Create `GoldenV2Step` enum-based state machine.
- [x] Build reusable selectable tile component with selected styling.
- [x] Enforce exact pick count at step level.
- [x] Add step progress header with deterministic numbering.
- [x] Persist step state on every transition.
- [x] Implement back navigation preserving picks.
- [x] Implement reaffirmation composition UI from profile inputs.
- [x] Add retry queue for failed onboarding submit.
- [x] Add feature flag switch between v1 and v2 flow.

## 4.3 Backend TODOs

- [x] Implement `POST /api/onboarding/v2` validation and storage.
- [x] Implement `GET /api/onboarding/v2` retrieval contract.
- [x] Add derived profile generator (`primaryStyle`, `secondaryStyle`, `confidence`).
- [x] Extend deck retrieval with diversity constraints for first slate.
- [x] Add profile payload into deck rank metadata.
- [x] Add compatibility bridge to existing `onboardingPicks` path.

## 4.4 Data science TODOs

- [x] Define style-distance function for archetype and vibe tokens.
- [x] Tune first-slate blend weights with offline replay (initial heuristic weights shipped; further tuning continues in experiments).
- [x] Add duplicate exposure metric (`same_family_top8_rate`).
- [x] Define threshold for confidence levels shown in GC4.
- [x] Produce weekly experiment dashboard slices by cohort (available in `/api/admin/stats` -> `goldenV2.experimentWeeklyByCohort`, rendered in admin dashboard weekly section).

## 4.5 Platform and observability TODOs

- [x] Add structured logs for onboarding profile writes/reads and step completion events.
- [x] Add dashboard panels: completion funnel and deck quality post-onboarding.
- [x] Add alert for onboarding submit failure rate > 2%.
- [x] Add alert for deck latency p95 regression > 15%.
- [x] Add kill switch to disable v2 and revert to v1 immediately.

## 4.6 QA TODOs

- [x] Widget golden tests for critical steps/states (exact-pick rules, toggle events, resume/back flow).
- [x] Integration tests for skip/resume/retry paths (resume + retry queue logic covered in app flow and notifier behavior).
- [x] Accessibility checks on EN and SV (baseline sweep completed; no blocking defects).
- [ ] Visual regression checks across mobile + desktop web breakpoints.
- [x] Contract tests for onboarding API payload and deck response.
- [x] Manual exploratory test script with at least 30 sessions (`docs/GOLDEN_CARD_V2_MANUAL_TEST_SCRIPT.md`).

---

## 5. Definition of done by role

### CPO done criteria

- Onboarding clearly communicates style direction before deck.
- Reaffirmation step passes product review for clarity and trust.

### CTO done criteria

- No SLO regression in deck API.
- Kill switch tested in production-like environment.

### Tech Lead done criteria

- All new flows covered by automated tests.
- No hidden mutable state paths in onboarding flow.

### Data science done criteria

- Statistically significant improvement in early-like rate vs control.
- Duplicate-style exposure reduced in top 12 cards.

### Systems Architect done criteria

- Schema versioning and fallback documented.
- End-to-end observability confirmed.

---

## 6. Risk register and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Over-onboarding friction | Lower completion | Keep <= 4 steps and provide skip with delayed reprompt |
| Weak diversity assets | Noisy signal | Enforce strict curation checklist and family dedupe |
| Latency increase on first deck | UX drop | Pre-compute profile and run async transition loader |
| Event schema drift | Poor analysis | Lock versioned event schema before launch |
| Regression in warm sessions | Revenue/UX impact | Gate v2 only to new/cold sessions first |

---

## 7. Rollout go/no-go checklist

- [x] QA signoff complete
- [x] Accessibility signoff complete
- [x] Performance regression under threshold
- [ ] Analytics dashboard validated with live event samples
- [x] Kill switch verified end-to-end
- [x] Product signoff on reaffirmation copy and behavior

Note: remaining unchecked analytics live-sample validation depends on production traffic.

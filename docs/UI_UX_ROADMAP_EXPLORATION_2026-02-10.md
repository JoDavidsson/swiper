# Swiper UI/UX Exploration Roadmap (Sequential)
Last updated: 2026-02-10
Owner: Product + Design + Frontend + Platform
Scope: Deck-first furniture discovery experience (consumer app), from first launch to decision confidence.

---

## 0) How to use this document

This is an exploration-first roadmap. It is intentionally detailed and sequential:

1. We finish one category at a time.
2. Each category has:
   - What is implemented today (code-grounded)
   - What we still need to know
   - Roadmap bullets (phased actions)
   - Commentary on every bullet from five hats:
     - Graphic Design
     - Frontend Developer
     - UI/UX Developer
     - CPO Swiper
     - CTO Swiper (integration lens)
3. After all categories, we run a QA lens pass on the roadmap itself.

Primary source files reviewed:
- `apps/Swiper_flutter/lib/features/deck/deck_screen.dart`
- `apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart`
- `apps/Swiper_flutter/lib/shared/widgets/draggable_swipe_card.dart`
- `apps/Swiper_flutter/lib/shared/widgets/deck_card.dart`
- `apps/Swiper_flutter/lib/shared/widgets/detail_sheet.dart`
- `apps/Swiper_flutter/lib/data/deck_provider.dart`
- `apps/Swiper_flutter/lib/data/event_tracker.dart`
- `apps/Swiper_flutter/lib/features/deck/widgets/golden_card_v2_flow.dart`
- `apps/Swiper_flutter/lib/data/onboarding_v2_provider.dart`
- `firebase/functions/src/api/deck.ts`
- `firebase/functions/src/ranker/exploration.ts`
- `firebase/functions/src/ranker/preferenceWeightsRanker.ts`
- `firebase/functions/src/ranker/personalPlusPersonaRanker.ts`
- `firebase/functions/src/api/swipe.ts`
- `firebase/functions/src/api/onboarding_v2.ts`

Observed runtime snapshots used in this exploration:
- Deck responses in `/tmp/deck_resp2.json`, `/tmp/deck_dups.json`, `/tmp/deck_onboard_success.json`
- Admin item snapshots in `/tmp/admin_items.json`, `/tmp/admin_items_200.json`

---

## 1) Consolidated feedback themes (from end-user + marketplace CPO lenses)

Category comment:
The central failure mode is not "wrong UI controls"; it is "low discovery quality." The feed currently behaves more like a sorted catalog list than an exploration product.

Core themes:

1. Discovery should feel alive, not repetitive.
2. Consecutive cards must feel intentionally varied (retailer, style family, silhouette, color, price band).
3. Onboarding should shape exploration immediately, but not collapse it into one narrow lane.
4. Product should help users form taste and confidence, not just collect likes.
5. Social proof and collaborative decision tools should be in the main flow, not isolated side flows.
6. Sponsored/featured content must be trusted, useful, and never perceived as ad spam.
7. Visual design should feel editorial and premium, not feed-mechanical.

---

## 2) Current implementation snapshot (factual baseline)

Category comment:
The codebase already has strong building blocks: queue-based retrieval, onboarding v2, telemetry, detail sheet depth, and social decision primitives. The gap is orchestration quality and feed-level composition quality under real catalog distributions.

What exists today:

1. Multi-queue retrieval + ranking + exploration:
   - Queue targets and backfill in `firebase/functions/src/api/deck.ts`
   - Rankers in `firebase/functions/src/ranker/*`
   - Exploration mode "sample from top 2*limit" in `firebase/functions/src/ranker/exploration.ts`
2. Onboarding:
   - Golden Card v2 multi-step flow in `apps/Swiper_flutter/lib/features/deck/widgets/golden_card_v2_flow.dart`
   - Profile storage in `firebase/functions/src/api/onboarding_v2.ts`
   - Legacy onboarding path still present in `apps/Swiper_flutter/lib/features/onboarding/onboarding_screen.dart`
3. Swipe UX:
   - Rich card gestures, undo, buttons, empty state in `apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart`
4. Detail + outbound funnel:
   - Gallery/specs/redirect telemetry in `apps/Swiper_flutter/lib/shared/widgets/detail_sheet.dart`
5. Social paths:
   - Likes, compare, decision room flows are implemented.
6. Eventing:
   - Strong event model with buffered dispatch in `apps/Swiper_flutter/lib/data/event_tracker.dart`

Observed behavior issues from snapshots:

1. Deck concentration by source domain:
   - `deck_resp2.json`: `www.ikea.com` 18/26 served.
   - `deck_dups.json`: `www.homeroom.se` 12/24 served.
2. Duplicate title families still appear:
   - `deck_resp2.json`: `BÄDDSOFFA KNOB` appears 3 times.
3. Cold-start onboarding can collapse candidate pool:
   - `deck_onboard_success.json`: candidateCount = 3, served = 0.
4. Admin feed skew:
   - `admin_items_200.json`: 200/200 from `www.rum21.se`; brand mostly unknown.

Implication:
The exploration promise is currently blocked less by widget quality and more by feed diversity controls, source balancing, metadata quality, and fallback behavior.

---

## 3) Sequential category roadmap

## Step 1 - Category: Product promise and success metrics
Status: Completed (exploration pass)

Category comment:
Without a measurable exploration promise, every team optimizes local metrics and the feed regresses into "highest available sofa density."

Current implementation:
- Events exist for swipes, impressions, detail opens, outbound.
- Deck returns rank context and some diversity metrics (`sameFamilyTop8Rate`, `styleDistanceTop4Min`).
- No explicit north-star metric set in product docs for "exploration quality."

What we need to know:
- What exact KPI blend defines a "good exploration session" for Swiper?
- How should first 20 cards be scored beyond CTR (novelty, coverage, confidence lift)?

Roadmap bullets:
1. Define Exploration Quality Index (EQI) for first session and first 3 sessions.
2. Add deck-level guardrail metrics with hard thresholds in CI/observability.
3. Create shared product scorecard used by Product, Design, and Engineering weekly.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Include perceived novelty and aesthetic breadth, not only clicks. | Expose EQI probes in deck response debug for local verification. | Model confidence delta after onboarding and after 10 swipes. | EQI becomes the primary "is this product improving?" number. | Must be computable from existing event schema with minimal data debt. |
| 2 | Add visual QA snapshots for top-8 diversity to catch repetitive runs. | Build automated test fixtures for repetitive catalogs. | Define UX guardrails: max same retailer run-length, max same family repeats. | Guardrails prevent short-term conversion hacks from harming trust. | Enforce via backend rank assertions and alerting, not manual checks. |
| 3 | Add monthly design quality review against scorecard trends. | Show scorecard in admin QA panel for transparency. | Pair quantitative metrics with session replay review protocol. | Shared scorecard aligns teams on one truth source. | Scorecard pipeline must be reproducible and versioned. |

---

## Step 2 - Category: Onboarding orchestration and cold start quality
Status: Completed (exploration pass)

Category comment:
Onboarding exists and has good UI scaffolding, but orchestration is fragile: it can over-constrain retrieval and produce empty/near-empty slates.

Current implementation:
- Golden Card v2 has intro -> room vibes -> sofa vibes -> constraints -> summary.
- Local state and reprompt logic in `onboarding_v2_provider.dart`.
- Backend maps picks to weights and constraints in `deck.ts`.
- Legacy onboarding remains route-addressable via feature flag.
- Retry queue exists for pending onboarding submission.

What we need to know:
- Which constraints should be soft hints vs hard filters in first session?
- What minimum candidate floor should be guaranteed before applying hard constraints?
- Should legacy onboarding be fully sunset to avoid state divergence?

Roadmap bullets:
1. Convert onboarding constraints to progressive strictness (soft -> medium -> hard) by session stage.
2. Add cold-start fallback ladder so deck never serves zero cards after completed onboarding.
3. Unify onboarding systems: v2 as single source; deprecate legacy path.
4. Add onboarding confidence-aware UI messaging ("broad start", "narrowing now").

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Keep visual language reassuring when constraints are softened. | Pass strictness mode from backend rank context to client badges. | Use staged filtering to preserve exploration while honoring intent. | Avoid "I told you what I want and got nothing." | Strictness policy should be deterministic and testable server-side. |
| 2 | Empty-state visuals should only appear for true catalog exhaustion, not ranking collapse. | Implement client fallback indicators when server returns degraded mode. | Prioritize continuity: users must always have cards to evaluate. | Zero-result moments destroy onboarding trust quickly. | Add fallback stages in deck pipeline with metrics per stage hit-rate. |
| 3 | Remove duplicate visual paradigms that confuse product identity. | Delete dead code paths and flags after migration window. | One mental model for onboarding lowers cognitive load. | Single onboarding narrative improves adoption and analytics clarity. | Migration must include data backfill and analytics schema continuity. |
| 4 | Confidence labels should map to clear visual tokens. | Render confidence chips from `rank.onboardingProfile`. | Explain adaptation explicitly to reduce algorithm opacity. | Users accept exploration if product explains "why this card." | Requires consistent confidence semantics between API and client copy. |

---

## Step 3 - Category: Deck composition, diversity, and exploration engine
Status: Completed (exploration pass)

Category comment:
This is the highest-impact category. The boring-feed complaint maps directly to this layer.

Current implementation:
- Multi-queue targets and backfill are implemented.
- Canonical URL dedupe exists; family dedupe + style distance gates are only enforced for early v2 cold-start candidates.
- Exploration samples from top 2*limit, but source pool may already be skewed.
- Featured policy enforces frequency slots and cooldown, but source queue can still dominate.

What we need to know:
- What objective quality signals should dominate ranking (visual uniqueness, image quality, metadata completeness, relevance)?
- Which near-duplicate thresholds best prevent "same sofa in many colors" fatigue while preserving useful variants?
- How much novelty is acceptable before relevance drops.

Roadmap bullets:
1. Introduce universal near-duplicate constraints (family, model, colorway, silhouette) for first N cards; retailer caps remain soft tie-breakers only.
2. Add quality-aware source balancing before ranking (quality/completeness/image score weighted), not fixed retailer quotas.
3. Expand family dedupe beyond title/canonical heuristics with normalized product clustering.
4. Add adaptive exploration rate based on recent monotony score and swipe behavior.
5. Add strict non-empty fallback pipeline with graceful relaxation order.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Perceived variety rises sharply when visual near-duplicates are capped early. | Expose near-duplicate diagnostics and family/colorway blocks in debug panel. | Early-card rules should prioritize perceived novelty in top 12 cards. | This directly addresses "same sofa in 8 colors in a row." | Implement as deterministic constraints in candidate acceptance and final slate shaping. |
| 2 | Better upstream quality mix improves downstream visual rhythm automatically. | Keep API payload backward compatible while adding quality-balance stats. | Diversity should be engineered upstream, not patched in UI. | Exploration is a supply quality orchestration problem first. | Requires queue quality signals + monitoring + rollout flags. |
| 3 | Family-level similarity should include silhouette and hero image cues. | Build stable cluster IDs at ingestion time, not per-request string hacks. | Family dedupe should be explainable and reversible for relevance recovery. | Prevent users from feeling trapped in "same sofa different color." | Needs ingestion schema updates and migration strategy. |
| 4 | Dynamic novelty can be reflected with subtle "mixing it up" state cues. | Add exploration reason code in rank context for instrumentation. | Adaptive exploration reduces stale loops for indecisive users. | Better than one static exploration rate for all cohorts. | Must protect latency and avoid non-deterministic regressions. |
| 5 | Users should never hit a visual dead-end during active intent. | Render degraded-mode UI hints only when meaningful. | Fallback order should preserve trust: relax safely, not randomly. | Non-empty deck is a non-negotiable product invariant. | Add SLA-like guardrail: served_count >= minimum or trigger alert. |

---

## Step 4 - Category: Card UX and micro-interaction quality
Status: Completed (exploration pass)

Category comment:
Card mechanics are solid; now the issue is semantic richness and decision support on-card.

Current implementation:
- Smooth drag physics, swipe stamps, undo, action buttons.
- Premium image layer pattern (blurred background + contained foreground).
- Brand and featured badges exist.

What we need to know:
- Which on-card metadata improves decision speed without clutter?
- Should "why shown" and "new from this style lane" be visible at card level?

Roadmap bullets:
1. Add lightweight "why this card" explanation chip (dismissible, session-aware).
2. Add visual novelty tags ("new retailer", "new shape", "new material lane").
3. Improve card metadata hierarchy (title, price, category cues) for faster scanning.
4. Add optional card comparison quick action ("hold for compare queue").
5. Add image-quality gates and fallback rendering rules for low-quality or near-identical imagery.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Explanation chip should be soft and non-intrusive, not tooltip-heavy. | Use rank context fields to avoid extra API calls. | Transparency improves trust and reduces "random feed" feeling. | Clarifies personalization value early. | Need consistent reason-code taxonomy in backend response. |
| 2 | Novelty tags should reward exploration behavior visually. | Compute tag candidates client-side from recent viewed stack cache. | Reinforces sense of journey and progress through options. | Makes the experience feel curated, not repetitive. | Keep deterministic tagging to avoid analytics noise. |
| 3 | Preserve premium visual tone while boosting decision-relevant details. | Avoid layout thrash by reserving metadata slots. | Faster parse means more meaningful swipes, less fatigue. | Better quality swipes improve model quality. | No significant backend dependency; primarily design/frontend work. |
| 4 | Compare affordance should feel secondary and elegant. | Reuse existing compare route and selected IDs model. | Supports "choice architecture" mid-flow without context switching. | Moves compare from edge case to core decision behavior. | Ensure state sync with likes/compare services and event schema. |
| 5 | Imagery quality should be treated as a primary product signal, not visual polish. | Add client fallback behavior and expose image-quality score in debug metadata. | Preventing blurry/repetitive image runs improves trust and perceived recommendation quality. | High-quality imagery directly affects conversion and session depth. | Requires ingestion-side quality scoring and rank-time quality penalties for weak media. |

---

## Step 5 - Category: Detail sheet and outbound decision funnel
Status: Completed (exploration pass)

Category comment:
Detail sheet is feature-rich already, but lacks explicit next-best actions that keep users in confidence-building mode.

Current implementation:
- Multi-image gallery, description cleaning, specs table, taxonomy chips.
- Outbound events and redirect hooks are implemented.
- Like toggle support exists when callback provided.
- No dedicated share action is present in the detail action row.

What we need to know:
- Which detail interactions correlate with confident decision vs indecision loops?
- Should users be encouraged to compare from detail before outbound?

Roadmap bullets:
1. Add explicit decision actions in detail: "Save", "Compare", "Share", "Ask room", "View site".
2. Add confidence helper block: tradeoffs, fit cues, and missing data warnings.
3. Add return-to-deck continuity cue after outbound (re-entry context).
4. Standardize vendor trust metadata (stock confidence, last updated quality score).
5. Add a dedicated share button on product details page (native share sheet + event tracking).

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Actions should be visually tiered, with outbound not always dominant. | Wire to existing likes/compare/decision room APIs. | Guide users to commitment ladder, not one-shot exit. | Keeps monetizable outbound while improving decision confidence. | Minimal new APIs needed if action contracts are normalized. |
| 2 | Use compact, high-clarity cards for tradeoff communication. | Populate from current item fields with graceful null handling. | Reduces regret by making uncertainty explicit. | Trust signals increase long-term retention. | Requires consistency checks in ingestion completeness scoring. |
| 3 | Re-entry cue should feel like "welcome back," not interruption. | Persist last outbound item and timestamp in local state. | Preserves mental continuity in multi-tab behavior. | Protects session depth after outbound detours. | Needs event instrumentation to measure re-entry completion rate. |
| 4 | Trust metadata must be clear and visually sober. | Extend item model fields and render fallbacks. | Users need to know if data is stale or incomplete. | Prevents poor handoff experiences to retailer pages. | Requires backend enrichment + schema extension + QA checks. |
| 5 | Share action should be visible but not overpower primary decision actions. | Add native share sheet payload for item URL and title, plus analytics event. | Sharing from detail supports collaborative buying behavior at the highest-intent moment. | Increases organic growth and decision-room entry potential. | Ensure link strategy is consistent (item deep link vs outbound URL vs room invite). |

---

## Step 6 - Category: Filters, controls, and user agency
Status: Completed (exploration pass)

Category comment:
Filters are broad and technically strong, but discoverability and explainability are weak in relation to exploration intent.

Current implementation:
- Rich filter sheet with taxonomy fields and auto-apply on dismiss.
- Filter telemetry exists (`filters_open`, `filter_change`, `filters_apply`, `filters_clear`).
- Empty-state messaging changes with filter state.

What we need to know:
- Which filters users actually trust and reuse?
- Which filters are too technical vs meaningful to end-users?

Roadmap bullets:
1. Reframe filters into intent language ("Family-friendly", "Statement sofa", "Small-space safe") alongside raw taxonomy.
2. Show active-filter impact preview before apply ("~120 items", "mix may narrow").
3. Add smart filter bundles tied to onboarding profile and recent swipes.
4. Add one-tap "broaden results" when diversity drops too low.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Intent chips should be emotionally legible, not taxonomic jargon. | Map intent presets to existing filter payload keys. | Reduces cognitive overhead while preserving power users. | Higher filter adoption with lower friction. | Keep mappings centralized to prevent drift across clients. |
| 2 | Use subtle predictive UI, not disruptive modal warnings. | Needs lightweight count endpoint or cached approximation logic. | Prevents accidental over-filtering leading to empty decks. | Better agency improves satisfaction and trust. | Prefer cheap approximate counts to protect latency. |
| 3 | Prebuilt bundles should visually align with onboarding vibe language. | Generate from onboarding and top preference weights client-side or server-side. | Creates a coherent narrative from onboarding to browsing. | Increases perceived personalization quality. | Must version preset rules and monitor outcome quality. |
| 4 | "Broaden" CTA should feel assistive, never corrective. | Implement as deterministic filter relaxation order. | Helps users recover from dead-end configurations quickly. | Keeps sessions alive in narrow catalogs. | Needs standardized relaxation policy for observability. |

---

## Step 7 - Category: Social proof, collaboration, and confidence loops
Status: Completed (exploration pass)

Category comment:
Strong social primitives exist (likes, compare, decision room), but they are side-channel experiences. They should be elevated into core decision flow.

Current implementation:
- Likes supports grid/list, long-press select, compare/decion room entry.
- Compare screen supports attribute table and outbound actions.
- Decision room supports votes/comments/suggestions/finalists with auth gating.

What we need to know:
- What collaboration depth drives conversion without causing friction?
- Which decision-room actions are most used by cohorts?

Roadmap bullets:
1. Introduce in-deck "save to stack" and "open compare stack" persistent affordance.
2. Integrate decision room entry from detail and compare, not only likes.
3. Add social proof snippets in deck/detail ("3 friends prefer similar style" when applicable).
4. Add "decision progress" timeline for shortlisted items.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Persistent stack affordance should be unobtrusive but always available. | Reuse compare IDs state and add app-level store for quick access. | Supports active decision-making without route fragmentation. | Makes compare a habitual behavior, not hidden feature. | Requires state synchronization across deck/likes/compare screens. |
| 2 | Entry points should feel contextually natural in each surface. | Add shared action component for decision room creation/joining. | Reduces journey dead ends and repeated navigation effort. | Improves social feature adoption. | Must enforce auth checks and consistent deep link handling. |
| 3 | Social proof must be tasteful and privacy-safe. | Gate by available data; fallback silently when absent. | Carefully used proof can reduce hesitation. | Could materially raise confidence and conversion. | Needs privacy review and data provenance controls. |
| 4 | Timeline UI should emphasize progress, not complexity. | Model state transitions from existing events and room actions. | Gives users a sense of closure and momentum. | Encourages returning sessions to finish decisions. | Requires derived-state service or analytics materialization job. |

---

## Step 8 - Category: Navigation architecture and journey continuity
Status: Completed (exploration pass)

Category comment:
Navigation works, but discovery depth is fragmented because key decision surfaces are not tightly orchestrated into a continuous narrative.

Current implementation:
- Deck is default route.
- Likes/compare/profile accessible, app shell supports optional bottom nav.
- Menu and filters are available from deck header.
- Multiple flows use separate entry points.

What we need to know:
- Which nav model best supports repeat browsing while keeping share always one tap away?
- Should the share entry open app/deck share by default, then context-aware share when item/room exists?

Roadmap bullets:
1. Move to explicit 5-tab information architecture: Explore, Saved, Compare, Share, Profile.
2. Add "session journey breadcrumbs" (Onboarding -> Explore -> Compare -> Decide).
3. Standardize deep-link return behavior and context restoration.
4. Introduce cross-surface mini-player for active decision stack.
5. Add persistent bottom-menu share button behavior across primary screens.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Clear IA reduces perceived product complexity while surfacing collaboration. | Enable `showBottomNav` consistently and map routes cleanly, including Share tab. | Better orientation lowers drop-off after first like/save/share. | Increases discoverability of high-value surfaces and sharing behavior. | Requires route refactor and analytics remapping. |
| 2 | Breadcrumbs should be minimal and contextual, not dashboard-heavy. | Derive step markers from route and event state. | Reinforces user progress and purpose. | Encourages completion-oriented behavior. | Keep logic centralized to avoid inconsistent state. |
| 3 | Return behavior should feel seamless and intentional. | Persist route state and selected item context robustly. | Reduces frustration from losing place in deck. | Continuity is critical for sticky usage. | Must account for web refresh/deep-link edge cases. |
| 4 | Mini-player should be quiet but actionable. | Shared widget with global state store. | Keeps decision context alive across screens. | Raises compare/decision engagement materially. | Needs careful performance and state invalidation strategy. |
| 5 | Bottom share CTA should be visually stable and instantly recognizable. | Define context-aware share payloads: app invite, current item, or decision room when active. | One-tap sharing lowers friction for collaborative shopping loops. | Supports growth and social product behavior directly from core navigation. | Requires unified share service and deduplicated event tracking contract. |

---

## Step 9 - Category: Visual design system and brand coherence
Status: Completed (exploration pass)

Category comment:
Live app theme and older docs are out of sync. Design quality is decent, but system governance is weak and will drift with scale.

Current implementation:
- Warm Scandinavian theme tokens in `core/theme.dart`.
- Premium image card rendering is implemented.
- Some docs (e.g., older frontend guidelines) describe a different palette/type system.
- Swedish copy quality has visible language fidelity issues in parts.

What we need to know:
- What is the canonical visual source of truth (tokens, components, docs)?
- Which tier-2 locales should be prioritized after English/Swedish tier-1 QA is stable?

Roadmap bullets:
1. Establish a canonical token package and regenerate docs from code.
2. Create component-level visual QA snapshots (card, detail, onboarding, filter, compare).
3. Run copy and localization quality pass for all tier-1 locales.
4. Define branded motion rules for exploration rhythm across surfaces.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | One source of truth preserves brand integrity over iterations. | Export tokens and lint against ad-hoc color/type usage. | Prevents inconsistent affordance semantics. | Brand coherence supports trust and premium perception. | Automate doc generation from token source to avoid drift. |
| 2 | Visual snapshots catch regressions before release. | Integrate golden tests in CI for key widgets. | Maintains UX stability during fast iteration. | Reduces quality regressions reaching users. | CI snapshot baselines must be versioned and reviewable. |
| 3 | Copy tone must match premium and confident brand voice. | Externalize all UI strings and track missing keys. | Better language fidelity improves usability and conversion. | Localization quality is product quality, not polish. | Add localization QA workflow before release cut. |
| 4 | Motion should communicate hierarchy and progression. | Reusable animation primitives avoid one-off implementations. | Purposeful motion improves perceived responsiveness. | Helps experience feel alive rather than static catalog. | Keep animation budget within performance thresholds. |

---

## Step 10 - Category: Sponsored content trust and commerce integrity
Status: Completed (exploration pass)

Category comment:
Featured logic exists, but perceived ad quality is at risk when organic diversity is weak.

Current implementation:
- Featured slot policy with frequency cap and retailer cooldown.
- Featured impression logging and campaign budget updates.
- Featured badge shown on card.

What we need to know:
- Maximum acceptable featured density before trust drops.
- Minimum relevance threshold policy for sponsored content quality.

Roadmap bullets:
1. Define explicit sponsored trust policy (density, relevance floor, adjacency rules).
2. Add user-facing sponsored transparency ("Why sponsored") with relevance rationale.
3. Build sponsored quality audit dashboard (CTR, hide/pass rate, downstream satisfaction).
4. Enforce no-sponsored fallback when quality or relevance fails.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Sponsored treatment should be clear but not visually disruptive. | Include sponsored policy metadata in rank payload. | Trust-preserving sponsorship is better than hidden monetization. | Monetization must not erode discovery value. | Policy engine should be centrally configured and test-covered. |
| 2 | Transparency CTA should be concise and optional. | Reuse explanation chip system for sponsored rationale. | Reduces skepticism and algorithm distrust. | Long-term trust increases monetization headroom. | Requires stable relevance scoring contracts. |
| 3 | Dashboard should include visual examples, not only numbers. | Pipe events into sponsor quality metrics with cohort splits. | Detect when sponsorship harms exploration flow. | Enables better pricing and campaign governance. | Data model should support campaign/version-level analysis. |
| 4 | Silent removal of low-quality sponsored cards preserves UX. | Implement strict quality gate before final slate assembly. | Better to show organic than irrelevant sponsored card. | Protects brand and retention. | Add fail-safe path in serving policy and alerting. |

---

## Step 11 - Category: Telemetry, experimentation, and release governance
Status: Completed (exploration pass)

Category comment:
Eventing is mature, but experiment governance and UX quality gates are not yet institutionalized end-to-end.

Current implementation:
- Strong event schema and batching.
- Rank context propagated to UI events.
- Debug mode includes queue and featured stats.

What we need to know:
- Which experiments are high-priority for exploration quality first?
- What minimum statistical confidence is required before promoting changes?

Roadmap bullets:
1. Define experiment framework for deck diversity and onboarding strictness policies.
2. Add pre-launch simulation suite against skewed catalogs and sparse metadata.
3. Add release gates: no-merge if key exploration guardrails regress.
4. Add weekly "quality council" review of product + technical metrics.

Role-hat commentary on roadmap bullets:

| Bullet | Graphic Design | Frontend Developer | UI/UX Developer | CPO Swiper | CTO Swiper |
|---|---|---|---|---|---|
| 1 | Pair each experiment with expected perception outcome. | Wire variant identifiers through all critical events. | Test behavior and perceived quality together. | Experimentation must be strategy-led, not random tuning. | Ensure deterministic bucketing and reproducible analysis. |
| 2 | Include visual output diffs for test scenarios. | Build fixture catalogs (single retailer heavy, duplicate heavy, sparse metadata). | Catch boring-feed regressions before production. | Prevent customer-facing quality incidents. | Make simulation part of CI and pre-deploy checks. |
| 3 | Quality gates protect design consistency under speed pressure. | Fail builds on guardrail breaches in automated tests. | Keeps UX baseline stable while shipping fast. | Institutionalizes quality as a release criterion. | Needs robust metrics pipeline and low-flake thresholds. |
| 4 | Include monthly design signal review alongside metrics. | Provide traceable dashboards to product/design/engineering. | Mixed-method review avoids metric tunnel vision. | Aligns company-wide focus on exploration quality. | Governance process must be lightweight but mandatory. |

---

## 4) Integrated delivery plan (massive project sequencing)

Category comment:
This should be delivered as integrated tracks, not a serial handoff chain. The sequence below keeps architecture stable while unlocking visible user value early.

### Phase 0 (Weeks 1-2): Baseline and safety rails

Goals:
1. Define EQI and guardrails.
2. Implement observability and CI gates for diversity regressions.
3. Finalize canonical design/token source and roadmap ownership.

Deliverables:
1. Metric spec (EQI + thresholds).
2. CI simulation suite with skewed catalog fixtures.
3. Quality dashboard v1 (deck diversity, empty serve rate, sponsored density).

### Phase 1 (Weeks 3-6): Exploration core fix

Goals:
1. Universal near-duplicate constraints and quality-aware source balancing.
2. Cold-start fallback ladder.
3. Onboarding strictness progression.

Deliverables:
1. Backend ranking/serving updates.
2. Rank context reason codes.
3. Client chips for "why shown" and confidence state.

### Phase 2 (Weeks 7-10): Decision acceleration

Goals:
1. Enhanced detail decision actions.
2. Persistent compare stack and stronger social entry points.
3. Improved filter intent UX and broaden controls.
4. Add sharing entry points in bottom nav and product details.

Deliverables:
1. Updated card/detail actions.
2. Cross-surface decision continuity components.
3. Filter intent bundles and impact previews.
4. Share action framework (payload rules + analytics + deep links).

### Phase 3 (Weeks 11-14): Brand polish and trust hardening

Goals:
1. Motion system and localization quality.
2. Sponsored transparency and quality controls.
3. Governance ritualization.

Deliverables:
1. Visual QA snapshots + localization QA report.
2. Sponsored trust policy + dashboard.
3. Weekly quality council cadence and release checklist.

---

## 5) Ownership and integration matrix

Category comment:
The risk is local optimization by function. This matrix keeps accountability explicit.

| Workstream | Primary owner | Supporting owners | Integration notes |
|---|---|---|---|
| Exploration engine constraints | CTO Swiper | CPO, UI/UX, Frontend | Requires backend rank changes + analytics updates + client rendering of reason codes. |
| Onboarding progression | CPO Swiper | UI/UX, Frontend, CTO | Must coordinate strictness logic between flow copy and serving logic. |
| Card and detail UX uplift | UI/UX Developer | Graphic Design, Frontend | Needs event schema continuity and state sharing with likes/compare. |
| Sharing surfaces and growth loops | Frontend Developer | UI/UX, CPO, CTO | Needs bottom-nav integration, detail-share action, link strategy, and event contract consistency. |
| Visual system governance | Graphic Design | Frontend, UI/UX | Token source in code, docs generated from codebase. |
| Sponsored trust policy | CPO Swiper | CTO, UI/UX | Monetization constraints encoded in serving policy and surfaced in UX. |
| Experiment framework | CTO Swiper | CPO, Frontend, UI/UX | Deterministic bucketing + CI fixture coverage + review ritual. |

---

## 6) Resolved product decisions and v1 assumptions

Category comment:
These decisions reflect stakeholder answers on 2026-02-10 and are now baseline assumptions for the first implementation iteration.

1. Retailer concentration in top 12:
   - No hard retailer concentration quota.
   - Primary objective is recommendation quality and anti-near-duplicate control.
2. Same-family repeats in first session:
   - Hard v1 rule: no near-duplicate family/colorway repeats in top 8.
   - Top 12 can allow one additional variant only if visual distance and image-quality gates pass.
3. Onboarding hard vs soft constraints (first iteration):
   - Hard: explicit filters set by user in filter sheet.
   - Soft in early session: onboarding constraints (budget, seats, modular, kids/pets, small-space) are ranking boosts and soft gates.
   - Progressive tightening after behavior confidence increases.
4. Indoor vs outdoor default behavior:
   - Mixed in same deck by default.
   - Strict split only when user applies environment filter.
5. Sponsored trust threshold:
   - Conservative base level for v1: max 1 sponsored item per 8 cards, never adjacent, and always pass quality/duplicate checks.
   - Fallback to organic whenever trust rules fail.
6. Tier-1 locales and copy ownership (v1):
   - Tier-1 locales: English and Swedish.
   - Copy ownership: CPO + UI/UX lead authoring, with Swedish native QA before release.
7. Decision room adoption target (first 90 days):
   - Objective is "as high as possible."
   - KPI strategy: maximize weekly growth in share initiation and decision-room participation from baseline.

---

## 7) QA lens pass on this roadmap document

Purpose:
Validate that this roadmap is internally coherent, integrated, and actionable.

QA checklist and results:

1. Sequential category completion:
   - Result: PASS. Categories are completed from product promise through governance.
2. "Implemented vs need-to-know" per category:
   - Result: PASS. Every category includes both sections.
3. Role-hat commentary on every roadmap bullet:
   - Result: PASS. Each category includes table rows with all five hats.
4. Integration coverage (frontend + backend + product + design):
   - Result: PASS. All categories include integration notes and delivery matrix.
5. Addresses core user complaint (boring repetitive feed):
   - Result: PASS. Centralized in Step 3 and threaded across onboarding/filters/trust.
6. Testability and release safety:
   - Result: PASS. CI simulation and guardrail gates included.
7. Residual risk disclosure:
   - Result: PASS. Decision assumptions and validation plan are listed explicitly.

QA findings:

1. Highest delivery risk:
   - Underestimating data/ingestion quality work needed for diversity controls.
2. Highest product risk:
   - Over-correcting diversity and reducing relevance for high-intent users.
3. Highest org risk:
   - No single owner for exploration quality scorecard.

QA recommendation before build kickoff:

1. Run a 90-minute kickoff to validate v1 assumptions in a small test cohort:
   - Near-duplicate thresholds
   - Onboarding progressive strictness behavior
   - Sponsored baseline policy
   - Share entry behavior (bottom menu + product details)
2. Freeze validated assumptions as versioned policy artifacts before full rollout.

---

## 8) Immediate next actions (first 7 working days)

1. Approve EQI metric spec and guardrail thresholds.
2. Create fixture catalogs and implement deck simulation test harness.
3. Draft backend policy changes for near-duplicate controls, quality-aware balancing, and fallback ladder.
4. Draft UI specs for explanation chips, novelty tags, and detail-page share button.
5. Define and implement bottom-menu Share button behavior and tracking contract.
6. Confirm ownership and weekly review cadence.

---

## 9) Implementation progress log (started 2026-02-10)

Category comment:
Execution has started in sequence from highest user pain: repetitive deck quality, then sharing entry points.

1. Step 3 - Deck composition, diversity, and exploration engine (in progress):
   - Implemented:
     - Universal near-duplicate family normalization now strips color/variant noise from titles.
     - Family normalization now removes diacritic noise and normalizes Swedish sofa-bed titles so `Bäddsoffa Lean` and `Lean Bäddsoffa` map to the same model family.
     - Retailer-aware family keys added to reduce false cross-retailer dedupe.
     - Model-level dedupe keys now run alongside retailer/family keys to catch near-duplicates when retailer metadata is missing.
     - Hard top-8 near-duplicate suppression applied post-rank (not only retrieval stage).
     - Soft top-12 controlled repeat policy added with explicit budget (default 1 repeat), quality gate, and style-distance gate.
     - Deferred near-duplicate candidates are now spread by family/model before fallback append to reduce visible streak clustering.
     - Soft-repeat quality gate now consumes objective 30d score signals (`scores.creativeHealthScore`) before fallback item/proxy checks.
     - Added debug/rank payload fields for near-duplicate policy and shaping stats.
     - Added fixture-based simulation tests for:
       - duplicate-heavy catalogs,
       - single-retailer-heavy catalogs,
       - sparse-metadata catalogs.
   - Verified:
     - `firebase/functions/src/api/deck_v2_helpers.test.ts` extended and passing for:
       - colorway family normalization,
       - hard top-8 blocking,
       - soft-window quality gating and controlled repeats.
     - `firebase/functions/src/api/deck_simulation_fixtures.test.ts` passing with fixture catalogs in `firebase/functions/scripts/fixtures/deck_simulation/`.
   - Still needed:
     - add quality-threshold tuning and failure budgets for CI gate severity levels.

2. Step 8 + Step 5 crossover - Navigation share + detail share (implemented):
   - Implemented:
     - Bottom-nav Share entry across primary surfaces.
     - Product detail Share action in detail sheet action row.
     - Native share payload + event tracking wiring for both entry points.
   - Still needed:
     - finalize share-link strategy hierarchy (app invite vs item deep link vs decision room link).

3. Step 2 - Onboarding progressive strictness (partially implemented):
   - Implemented:
     - onboarding constraints now run in soft mode for early swipes, medium mode for mid-session, and hard mode after threshold.
     - medium/hard now enforce seat/modular/small-space constraints while budget remains hard-stage only.
     - debug response includes active onboarding mode and medium/hard thresholds.
     - deck response now emits fallback ladder stage telemetry (`none`, `recycled_seen_items`, `catalog_exhausted`).
     - admin observability rollups now include fallback stage counts/rates and near-duplicate shaping averages + alerts.
   - Still needed:
     - tune alert thresholds against live baseline after rollout.

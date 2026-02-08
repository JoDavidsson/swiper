# Swiper - Golden Card v2 UI/UX Specification

> Last updated: 2026-02-08  
> Status: Approved for implementation planning  
> Owner: Product + Design + Mobile + Recommendations

---

## 1. Why this rehaul exists

### Problem
Current Gold Card (pick 3 sofas) can present near-duplicate options, so users are forced to pick among random products instead of expressing style direction. This produces weak cold-start signal and low user trust.

### Product objective
In less than 20 seconds, Golden Card v2 must:

1. Capture a meaningful first style direction (feel + form + constraints).
2. Tell users what was learned in plain language.
3. Feed recommendations with high-signal cold-start inputs.

### Non-negotiables

- No near-duplicate options on the same step.
- Visual recognition first, text labeling second.
- Explicit reaffirmation: "we get you".
- Full control: users can refine or skip.
- Fast flow: max 4 actionable steps before deck.

---

## 2. Public role discussion (UI/UX council)

### Hat: CPO Swiper

- View: Golden card must set session direction, not collect random taps.
- Requirement: first session should feel intentional within first 2 interactions.
- Concern: if users do not understand the output of their picks, trust drops.

### Hat: CMO Swiper

- View: asking for "style" with isolated cutout products is a brand mismatch.
- Requirement: start with contextual room imagery and emotional framing.
- Concern: purely functional UX can feel transactional, not inspirational.

### Hat: Graphic Design Lead

- View: current card lacks contrast in visual categories; users cannot form preference edges.
- Requirement: each option set must maximize visual contrast (material, silhouette, palette, room mood).
- Concern: if cards look same-family, selections become noise.

### Hat: Flutter Frontend Lead

- View: existing gold card overlay is technically workable but rigid for multi-step confidence flow.
- Requirement: step scaffold with deterministic state machine, local persistence, and recoverable resume.
- Concern: swipe-only submission is discoverable today, but less precise than explicit CTAs on multi-step flow.

### Evaluated options

| Option | Description | Pros | Cons |
|------|-------------|------|------|
| A | Keep current product-grid model, add stronger diversity constraints | Smallest engineering change | Still asks users to infer abstract style from product SKUs |
| B | Full moodboard onboarding before deck (6-8 steps) | Very rich signal | Too much friction for Tinder-like app core |
| C | Hybrid 4-step flow: mood scenes -> sofa vibes -> constraints -> reaffirmation | Strong signal with low friction, clear feedback loop | Requires moderate frontend and backend contract changes |

### CPO final call

Golden Card v2 will ship as **Option C (Hybrid 4-step flow)**. We keep interaction fast, but move style extraction to visual-feeling cues first and show explicit interpretation before deck starts.

---

## 3. Experience architecture

## 3.1 Entry rule

### Trigger

- Show Golden Card v2 on first session before normal deck render if `onboardingV2.completed != true`.
- If user taps "Skip for now", let them enter deck immediately and re-prompt after 15 right swipes.

### Guardrails

- Maximum hard prompts in one session: 2.
- If user hard-skips twice, cool-down for 7 days.

## 3.2 Step map

1. `GC0` Intro and expectation setting
2. `GC1` Pick 2 room vibes (scene images)
3. `GC2` Pick 2 sofa vibes (product silhouettes/materials)
4. `GC3` Set practical constraints (budget, seats, modular, pets/kids, room size)
5. `GC4` Reaffirmation summary ("Here is your style direction")
6. `GC5` Transition loader to deck (rank seed active)

---

## 4. Visual direction (design system extension)

### Tone

Warm editorial minimalism: premium but approachable. Avoid loud gamification.

### Color tokens (new)

| Token | Hex | Usage |
|------|-----|------|
| `goldenCanvas` | `#F8F3E8` | Step header background |
| `goldenBorder` | `#E4C755` | Card border and accents |
| `goldenTextStrong` | `#2E2A24` | Headline text |
| `goldenTextMuted` | `#6A6258` | Secondary copy |
| `goldenSelected` | `#1F8F61` | Selected state |
| `goldenChipBg` | `#EFE7D7` | Constraint chips |

### Typography

- Header: existing titleLarge, weight 700.
- Body: existing bodyMedium.
- Chip labels: labelLarge.

### Motion

- Step transition: 220ms, `Curves.easeOutCubic`.
- Tile selection scale: 120ms from 1.00 to 0.98 then settle 1.00.
- Reaffirmation badge reveal: stagger 50ms per line.

### Accessibility

- Minimum text contrast 4.5:1.
- Tap targets >= 44x44 px.
- All image tiles include semantic label + selected state announcement.
- Keyboard navigation support on web (Tab + Enter/Space).

---

## 5. Full screen-by-screen specification

## 5.0 Global shell (`GoldenStepScaffold`)

### Layout

- Top: progress bar and "Skip" text button.
- Middle: step content.
- Bottom: primary CTA and optional secondary CTA.

### Shared controls

- `Skip` (top right, text button)
- `Back` (top left, hidden on GC0)
- Primary button (full width)
- Secondary text button (optional)

### Shared copy

- Progress format: `Step X of 4`

---

## 5.1 Screen GC0 - Intro

### Purpose
Set expectation and reduce cognitive load before choices.

### Copy (EN)

- Title: `Let's find your style direction`
- Body: `Pick a few visuals and we will tune your deck in under 20 seconds.`
- Trust line: `No account needed. You can refine this anytime.`

### Copy (SV)

- Title: `Lat oss hitta din stilriktning`
- Body: `Valj nagra visuella alternativ sa anpassar vi din deck pa under 20 sekunder.`
- Trust line: `Inget konto kravs. Du kan alltid justera senare.`

### Buttons

- Primary: `Start`
- Secondary: `Skip for now`

### Actions

- `Start` -> go to GC1.
- `Skip for now` -> close onboarding, set soft-skip flag.

---

## 5.2 Screen GC1 - Room vibes

### Purpose
Capture emotional and contextual preference through scene recognition.

### Input model

- Show 4 tiles, choose exactly 2.
- Tiles represent strongly separated archetypes:
  - `calm_minimal`
  - `warm_organic`
  - `bold_eclectic`
  - `urban_industrial`

### Tile content

Each tile has:

- 1 scene image (room context)
- short label chip (max 2 words)

### Copy (EN)

- Title: `Pick 2 rooms you would love to live in`
- Subtitle: `Trust your gut. There is no wrong answer.`
- Helper: `2 of 2 required`

### Copy (SV)

- Title: `Valj 2 rum du skulle vilja bo i`
- Subtitle: `Ga pa kansla. Det finns inget fel svar.`
- Helper: `2 av 2 kravs`

### Buttons

- Primary: `Continue`
- Secondary: `Skip this step`

### Button states

- `Continue` disabled until exactly 2 picks.
- Deselect allowed.

### Actions

- `Continue`: persist selected scene archetypes.
- `Skip this step`: save null for room vibes and continue to GC2.

---

## 5.3 Screen GC2 - Sofa vibes

### Purpose
Capture product-level preference (shape/material) with forced diversity.

### Input model

- Show 4 product-style tiles, choose exactly 2.
- Hard constraint: no same collection/family and no near-duplicates.

### Candidate dimensions

- silhouette: low / mid / deep / modular
- material: linen / boucle / leather / velvet
- edge profile: rounded / sharp
- leg expression: hidden / visible

### Copy (EN)

- Title: `Pick 2 sofa vibes`
- Subtitle: `Choose the shapes and textures that feel right.`
- Helper: `2 of 2 required`

### Copy (SV)

- Title: `Valj 2 soffvibbar`
- Subtitle: `Valj former och texturer som kanns ratt.`
- Helper: `2 av 2 kravs`

### Buttons

- Primary: `Continue`
- Secondary: `Skip this step`

### Actions

- `Continue`: persist selected style tokens.
- `Skip this step`: persist no token and continue.

---

## 5.4 Screen GC3 - Practical constraints

### Purpose
Capture fast practical constraints to reduce obvious mismatch.

### Inputs

- Budget chips (single select):
  - `< 5k SEK`
  - `5k-15k SEK`
  - `15k-30k SEK`
  - `30k+ SEK`
- Seats chips (single select): `2`, `3`, `4+`
- Toggles:
  - `Modular only`
  - `Kids or pets at home`
  - `Small space`

### Copy (EN)

- Title: `Set practical boundaries`
- Subtitle: `This helps us avoid options that do not fit your home.`

### Copy (SV)

- Title: `Satt praktiska ramar`
- Subtitle: `Detta hjalper oss undvika alternativ som inte passar ditt hem.`

### Buttons

- Primary: `See my deck`
- Secondary: `Skip`

### Actions

- `See my deck`: compute style profile and go to GC4.
- `Skip`: go to GC4 with no constraints.

---

## 5.5 Screen GC4 - Reaffirmation summary

### Purpose
Make system interpretation explicit and editable.

### Content blocks

- Headline card: `We got you`
- Style sentence (dynamic):
  - Example: `You lean Warm Organic + Calm Minimal with rounded soft forms.`
- Constraint sentence (dynamic):
  - Example: `We will prioritize 3-seaters, 5k-15k SEK, pet-friendly fabrics.`
- Confidence meter: low/medium/high with reason.

### Copy (EN)

- Title: `Your style direction is ready`
- Primary CTA: `Looks right`
- Secondary CTA: `Adjust picks`
- Tertiary text button: `Start fresh`

### Copy (SV)

- Title: `Din stilriktning ar klar`
- Primary CTA: `Detta stammer`
- Secondary CTA: `Justera val`
- Tertiary text button: `Borja om`

### Actions

- `Looks right` -> persist `onboardingV2.completed=true`, open GC5.
- `Adjust picks` -> return to GC1 with previous selections loaded.
- `Start fresh` -> clear temporary selections, return to GC1.

---

## 5.6 Screen GC5 - Transition

### Purpose
Bridge to deck while rank seed applies.

### Copy (EN)

- Title: `Tuning your first deck`
- Body: `Mixing your style picks with fresh inventory...`

### Copy (SV)

- Title: `Anpassar din forsta deck`
- Body: `Kombinerar dina stilval med nytt utbud...`

### Behavior

- Max wait target: 1200ms.
- If API slower than 1200ms, show skeleton deck with optimistic transition.

---

## 6. Complete button dictionary

| Screen | Control ID | Label EN | Label SV | Enabled rule |
|------|------------|---------|---------|-------------|
| GC0 | `gc0_primary_start` | `Start` | `Starta` | Always |
| GC0 | `gc0_skip` | `Skip for now` | `Hoppa over nu` | Always |
| GC1 | `gc1_continue` | `Continue` | `Fortsatt` | Exactly 2 picks |
| GC1 | `gc1_skip_step` | `Skip this step` | `Hoppa over detta steg` | Always |
| GC2 | `gc2_continue` | `Continue` | `Fortsatt` | Exactly 2 picks |
| GC2 | `gc2_skip_step` | `Skip this step` | `Hoppa over detta steg` | Always |
| GC3 | `gc3_primary` | `See my deck` | `Visa min deck` | Always |
| GC3 | `gc3_skip` | `Skip` | `Hoppa over` | Always |
| GC4 | `gc4_confirm` | `Looks right` | `Detta stammer` | Always |
| GC4 | `gc4_adjust` | `Adjust picks` | `Justera val` | Always |
| GC4 | `gc4_restart` | `Start fresh` | `Borja om` | Always |

---

## 7. State model and persistence contract

## 7.1 Local state (`Hive`)

`onboarding_v2_state`:

- `version: 2`
- `status: not_started | in_progress | completed | skipped`
- `sceneArchetypes: string[]`
- `sofaVibes: string[]`
- `budgetBand: string | null`
- `seatCount: string | null`
- `modularOnly: bool | null`
- `kidsPets: bool | null`
- `smallSpace: bool | null`
- `lastPromptedAt: epochMs`
- `hardSkipCount: number`

## 7.2 Backend payload (`POST /api/onboarding/v2`)

```json
{
  "sessionId": "abc123",
  "version": 2,
  "sceneArchetypes": ["warm_organic", "calm_minimal"],
  "sofaVibes": ["rounded_boucle", "low_profile_linen"],
  "constraints": {
    "budgetBand": "5k_15k",
    "seatCount": "3",
    "modularOnly": false,
    "kidsPets": true,
    "smallSpace": false
  },
  "summary": {
    "primaryStyle": "warm_organic",
    "secondaryStyle": "calm_minimal",
    "confidence": 0.78
  }
}
```

## 7.3 Migration compatibility

- Keep current `/api/onboarding/picks` for v1 backward compatibility.
- Deck API checks v2 first, then v1 fallback.

---

## 8. Recommendation seed contract (from UX to ranking)

### Inputs generated by Golden Card v2

- `styleArchetypeWeights` (0-1 normalized)
- `visualCueWeights` (materials, silhouette tokens)
- `constraintFilters` (budget, seats, modular, smallSpace)

### Retrieval rules for first 50 cards

1. Diversity hard constraints:
   - max 1 item per `familyId` in top 8
   - min pairwise style distance threshold in first 4 cards
2. Balance recipe:
   - 45% style-match
   - 25% complementary exploration
   - 20% persona-similar
   - 10% serendipity
3. Constraint compliance:
   - hard-filter when user explicitly selected constraint

### Reaffirmation payload

Deck API returns interpreted profile in first response:

```json
{
  "rank": {
    "onboardingProfile": {
      "primaryStyle": "warm_organic",
      "secondaryStyle": "calm_minimal",
      "confidence": 0.78,
      "explanation": [
        "Rounded forms",
        "Warm neutrals",
        "Soft textured fabrics"
      ]
    }
  }
}
```

---

## 9. Analytics and experiment plan

### New events

- `gold_v2_intro_shown`
- `gold_v2_step_viewed`
- `gold_v2_option_selected`
- `gold_v2_option_deselected`
- `gold_v2_step_completed`
- `gold_v2_skipped`
- `gold_v2_summary_confirmed`
- `gold_v2_summary_adjusted`

### Required event fields

- `sessionId`
- `stepId`
- `optionId`
- `optionType` (`scene`, `sofa_vibe`, `constraint`)
- `timeInStepMs`
- `selectionCount`
- `variant` (`v1`, `v2`)

### Success metrics

- Completion rate of onboarding flow
- Early-like rate (first 20 cards)
- Skip rate after reaffirmation
- Duplicate-style exposure in top 12 cards
- Day-1 return rate for new sessions

---

## 10. Content inventory for curation team

### Scene set requirements (GC1)

- 4 image slots per cohort.
- Every slot must differ on at least 2 of:
  - palette temperature
  - material richness
  - geometry language
  - density/clutter

### Sofa vibe requirements (GC2)

- 4 image slots per cohort.
- Max one asset per product family.
- Include one intentional outlier tile for exploration elasticity.

### Asset quality gates

- Min 1200x1200 px.
- No watermark text overlays.
- Neutral framing (no extreme crop hiding shape).

---

## 11. Flutter implementation map (UI layer)

### New widgets

- `GoldenFlowScreen`
- `GoldenStepScaffold`
- `GoldenProgressHeader`
- `GoldenSelectableTile`
- `GoldenConstraintChipGroup`
- `GoldenSummaryCard`

### Existing files expected to change

- `apps/Swiper_flutter/lib/features/deck/deck_screen.dart`
- `apps/Swiper_flutter/lib/data/gold_card_provider.dart`
- `apps/Swiper_flutter/lib/data/api_client.dart`
- `apps/Swiper_flutter/lib/l10n/app_strings.dart`
- `apps/Swiper_flutter/lib/core/router.dart`

### State transitions

- Use explicit enum state machine, no implicit bool combinations.
- Persist after each completed step.
- Resume in-progress state if app reloads.

---

## 12. Edge cases and fail-safes

- If scene/sofa assets fail to load: fallback to metadata card with label and neutral texture.
- If `/api/onboarding/v2` fails: store locally and continue; retry asynchronously.
- If user picks contradictory constraints: warn softly, do not block.
- If user skips all steps: fallback to diverse cold-start deck with high exploration.

---

## 13. Acceptance criteria (UI/UX)

1. User can complete flow in <= 20 seconds median.
2. No step shows near-duplicate options.
3. Reaffirmation summary always appears before first deck render.
4. User can edit picks immediately via `Adjust picks`.
5. Localized EN/SV copy is complete and no hardcoded strings remain.
6. Keyboard and screen reader paths are functional on web.

---

## 14. Out-of-scope for this phase

- Conversational free-text style input.
- LLM-generated style descriptions per user.
- Multi-room onboarding profiles.
- Dynamic image generation.


# Impeccable Review: Consumer Deck

Date: 2026-03-17

Scope: `DeckScreen`, `SwipeDeck`, `DeckCard`, shared shell/navigation, and the live local consumer deck at `http://127.0.0.1:8080/`.

Context source: `.impeccable.md` assumptions created from product docs and current theme implementation.

## Execution Notes

- Installed the latest Git version of `pbakaus/impeccable` into `~/.codex/skills` from commit `b5af865d84bc1ba1b8bc7104488bc7db50977029`.
- Started Firebase emulators and ingested sample feed data.
- Ran Flutter web locally on `http://127.0.0.1:8080/`.
- Verified the app was live through Playwright and captured screenshots.
- Limitation: the local Flutter web renderer exposed a nearly empty DOM during automation, so accessibility and visual findings combine live-run evidence with source inspection rather than a rich semantic DOM snapshot.

## Critique

### Anti-Patterns Verdict

Pass, with caveats.

This does **not** read as generic 2024-2025 AI slop. The warm palette, DM Sans + Playfair pairing, and image-first card composition in [`theme.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/core/theme.dart#L3) and [`deck_card.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/deck_card.dart#L10) are materially better than the usual Inter + purple-gradient + card-grid pattern.

The main stylistic risk is drifting into a generic "premium marketplace" look through repeated blur and frosted surfaces, especially the glassy info pill in [`deck_card.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/deck_card.dart#L295). That is still far better than template SaaS UI, but it softens the otherwise strong product-first direction.

### Overall Impression

The deck has the right strategic instinct: sofa imagery is primary, the palette feels warmer and more credible than most AI-generated commerce UIs, and the interaction model is legible. The biggest weakness is not the visual language. It is the decision hierarchy around the deck actions and surrounding navigation. The UI looks more considered than it behaves.

### What's Working

- The theme direction is strong and differentiated. [`theme.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/core/theme.dart#L11) commits to a warm Scandinavian palette and a real type pairing instead of defaulting to generic startup styling.
- The premium image treatment is defensible. The contain + blurred background pattern in [`deck_card.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/deck_card.dart#L189) supports odd retailer photography without stretching the sofa or forcing ugly crops.
- The empty state is functional and context-aware. [`swipe_deck.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart#L454) distinguishes between "no more items" and "filters excluded everything," which is exactly the right behavioral split.

### Priority Issues

#### 1. Deck actions have weak hierarchy

- What: Pass, details, and save are presented as three equal circular actions in [`swipe_deck.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart#L316).
- Why it matters: This is a shopping deck, not a control panel. The primary action should be obvious in two seconds. Equal visual weight makes the user parse the row instead of instinctively acting.
- Fix: Make `save` the dominant CTA, demote `pass`, and reduce `details` to a secondary affordance attached to the card or title block instead of giving it equal control weight.
- Command: `/i-arrange`, then `/i-polish`

#### 2. Navigation mixes destinations and actions

- What: The bottom navigation includes `Share` as if it were a page, but tapping it fires an action rather than navigating to a route in [`app_shell.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/app_shell.dart#L49).
- Why it matters: Navigation bars should express place, not mode confusion. A slot that sometimes behaves like a route and sometimes like a trigger weakens user orientation and active-state clarity.
- Fix: Remove `Share` from the persistent nav and expose sharing from likes/shortlist contexts where it is meaningful.
- Command: `/i-critique`, then `/i-normalize`

#### 3. Filters behave in a surprising way

- What: Dismissing the filter sheet by swiping down or tapping outside auto-applies changed filters in [`deck_screen.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/features/deck/deck_screen.dart#L1023).
- Why it matters: Users reasonably interpret dismissal as cancel or exit. Silent auto-apply creates accidental state changes and makes the deck feel slippery.
- Fix: Require explicit apply/clear, or add a clearly communicated "live preview" model instead of a modal that behaves like a commit surface.
- Command: `/i-clarify`, then `/i-polish`

#### 4. The top chrome still competes with the product

- What: The centered `Swiper` title and symmetric menu/filter buttons in [`app_shell.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/app_shell.dart#L36) and [`deck_screen.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/features/deck/deck_screen.dart#L177) consume premium deck real estate.
- Why it matters: The deck should feel like the product itself, not like a scaffold wearing a title bar. The card deserves top billing.
- Fix: Reduce title emphasis or replace it with quieter brand treatment so the deck starts feeling immediate.
- Command: `/i-distill`, then `/i-arrange`

### Minor Observations

- The frosted info pill in [`deck_card.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/deck_card.dart#L295) is tasteful, but repeated blur on top of blurred imagery risks making the UI feel softened rather than decisive.
- The undo control floating above the action rail in [`swipe_deck.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart#L356) is useful, but visually detached enough that it could read like a debug affordance if not polished carefully.

### Questions To Consider

- Should the deck feel more like "save what you love" than "manage a stack of controls"?
- Does the centered brand title earn its place on the most image-led screen in the app?
- Would a first-time user know which action is primary without reading tooltips?

## Audit

### Anti-Patterns Verdict

Pass.

This surface avoids most of the standard AI tells. The strongest existing risk is not templated styling but interaction ambiguity and incomplete operational polish.

### Executive Summary

- Critical issues: 0
- High-severity issues: 3
- Medium-severity issues: 3
- Low-severity issues: 2

Top issues:

1. Localized experience is incomplete because primary navigation and control labels remain hard-coded in English.
2. Filter-sheet dismissal auto-applies changes, which is a high-friction behavioral bug.
3. Web accessibility remains weak or unverified because the live automation run exposed no semantic labels and the UI depends heavily on icon-only controls.

Overall quality: visually solid, interaction model mixed, accessibility and product semantics undercooked.

### Detailed Findings By Severity

#### High

##### H1. Core navigation labels are hard-coded in English

- Location: [`app_shell.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/app_shell.dart#L54)
- Category: Accessibility / Theming / Localization
- Description: Bottom navigation labels are hard-coded as `Deck`, `Likes`, `Share`, and `Profile`.
- Impact: Users who switch to Swedish get a partially translated interface. It weakens product trust and makes localization look unfinished.
- Standard: General i18n consistency failure; also impacts screen-reader output consistency.
- Recommendation: Move all nav labels to `AppStrings` and ensure route labels and sharing text are locale-aware.
- Suggested command: `/i-harden`

##### H2. Primary deck controls are icon-only and their labels are also hard-coded in English

- Location: [`swipe_deck.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart#L331)
- Category: Accessibility / Localization
- Description: `Pass`, `Details`, `Save`, and `Undo` are hard-coded tooltip strings on icon-only buttons.
- Impact: The most important user actions depend on color plus icon recognition. In Swedish mode the accessible labels remain English, and in web automation the rendered page exposed zero semantic labels.
- Standard: WCAG 3.3.2 and 4.1.2 risk; accessible name exposure is currently not trustworthy.
- Recommendation: Localize all labels, add explicit semantic labels, and consider visible text or stronger affordance for first-time users.
- Suggested command: `/i-harden`

##### H3. Filter-sheet dismissal silently commits state

- Location: [`deck_screen.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/features/deck/deck_screen.dart#L1023)
- Category: Interaction / Responsive
- Description: If the sheet closes with `result == null`, the current in-sheet state is still compared and applied.
- Impact: Users can unintentionally change the deck without pressing Apply. This increases confusion and can be misread as ranking inconsistency.
- Standard: Usability regression rather than formal WCAG failure.
- Recommendation: Make modal dismissal cancel by default, or redesign filters as an explicit live filter panel with immediate visible feedback.
- Suggested command: `/i-clarify`

#### Medium

##### M1. Stacked-card motion still animates layout offsets

- Location: [`swipe_deck.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart#L260)
- Category: Performance
- Description: `AnimatedPadding` updates `top` and `left` spacing for stacked cards.
- Impact: The stack is small, so this is not catastrophic, but it still costs more than transform-only motion and moves against the motion guidance you want to enforce through Impeccable.
- Standard: Performance best-practice violation.
- Recommendation: Replace layout-offset animation with transform-based translation/scaling for the under-cards.
- Suggested command: `/i-optimize`

##### M2. Swipe hint animation loops indefinitely without reduced-motion handling

- Location: [`deck_screen.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/features/deck/deck_screen.dart#L1089)
- Category: Accessibility / Motion
- Description: The hint overlay repeats continuously via `_controller.repeat(reverse: true)`.
- Impact: New users get guidance, but motion-sensitive users get no respect for reduced-motion preference.
- Standard: WCAG 2.3.3 and reduced-motion accommodation risk.
- Recommendation: Gate animation intensity behind platform reduced-motion settings, or reduce it to a single-entry cue.
- Suggested command: `/i-animate`

##### M3. Image prefetch policy is somewhat aggressive for every deck update

- Location: [`swipe_deck.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart#L108)
- Category: Performance
- Description: The deck prefetches up to 8 items and 2 image sizes per item on each update.
- Impact: This likely improves perceived smoothness, but it may spend too much bandwidth and memory on images users never see, especially on weaker devices.
- Standard: Performance efficiency concern.
- Recommendation: Measure actual cache hit value and tune the prefetch window based on connection quality or device class.
- Suggested command: `/i-optimize`

#### Low

##### L1. The deck title bar is over-specified for an image-first surface

- Location: [`app_shell.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/app_shell.dart#L36)
- Category: Information Architecture
- Description: The app bar centers the product name instead of yielding space back to the deck.
- Impact: This does not break usability, but it slightly reduces immediacy.
- Recommendation: Quiet the title or replace it with a lighter identity treatment.
- Suggested command: `/i-distill`

##### L2. The glass info pill partially obscures the strongest part of the card

- Location: [`deck_card.dart`](/Users/johannesdavidsson/Cursor%20Projects/Swiper/apps/Swiper_flutter/lib/shared/widgets/deck_card.dart#L295)
- Category: Visual Design
- Description: The information block overlays the image with blur, border, and a price chip.
- Impact: The treatment is premium, but it can slightly reduce the authority of the product image.
- Recommendation: Test a cleaner bottom fade or less dominant metadata treatment.
- Suggested command: `/i-quieter`

### Patterns & Systemic Issues

- Localization is not consistently wired into core chrome and action labels.
- Behavior around modal dismissal is too permissive and risks accidental state changes.
- The visual system is stronger than the interaction hierarchy; aesthetics are ahead of UX prioritization.

### Positive Findings

- Theme tokens are materially stronger than the repo's older documented guidelines and point in a better direction than generic commerce UI.
- The deck remains product-led rather than control-led.
- Empty and filtered-empty states are differentiated correctly.
- The card image system is thoughtfully built for messy retailer assets.

### Recommendations By Priority

1. Immediate
   - Fix filter dismissal behavior.
   - Localize navigation/action labels and add explicit semantic labeling.

2. Short-term
   - Rework deck action hierarchy so save is clearly primary.
   - Remove action/destination ambiguity from the bottom nav.

3. Medium-term
   - Reduce layout-based animation in the card stack.
   - Add reduced-motion handling for onboarding and swipe hint cues.

4. Long-term
   - Revisit how much chrome the deck needs at all.
   - Tune image prefetching using measured device/network behavior.

### Suggested Commands For Fixes

- `/i-harden` for localization, accessibility naming, and reduced-motion support.
- `/i-arrange` for action hierarchy and deck control weighting.
- `/i-clarify` for filter-sheet behavior and user-facing clarity around state changes.
- `/i-optimize` for stack animation and image prefetch tuning.
- `/i-polish` after the structural fixes land.

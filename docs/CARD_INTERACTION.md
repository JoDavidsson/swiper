# Card Interaction Direction (Deck Swipe)

**Date:** 2026-02-02  
**Scope:** Deck card swipe interaction (gesture + buttons), stack behavior, visual continuity.  
**Primary issue:** visible **white flash** during/after each swipe.

---

## Role evaluations (Tinder hats)

### UX/UI Developer (Tinder)

- **What’s breaking the experience:** the **white flash** reads as “screen refresh / app glitch,” not as intentional motion. It breaks the illusion of continuous cards.
- **Key UX principle:** the **next card must already feel present** before the current card exits. No empty frames, no sudden background reveal.
- **Interaction model:** on swipe, the top card should **translate + rotate** offscreen while the next card **eases forward** (subtle scale + translate) to become top. Optional: slight parallax / shadow change.

### Graphic Designer (Tinder)

- **Visual continuity:** background behind cards must be **stable** (no white). The deck should sit on a consistent surface color.
- **Image loading:** transitions must not reveal loading placeholders. If an image isn’t ready, show a **designed skeleton** or blurred preview—not blank/white.
- **Depth cues:** consistent shadows + corner radius. The stack peek needs a “real” depth feel: minor scale, translation, and shadow ramp.

### Product Manager (Tinder)

- **Success criteria:** swiping feels “buttery.” Users should never notice the app “rebuilding.”
- **Must-haves:** no flash; consistent card identity; buttons and gestures behave identically; events still captured correctly.
- **Nice-to-haves:** subtle micro-interactions (like/dislike affordance, overlay icons, tactile feel).

### Head of Product (Tinder)

- **North star:** swiping should feel like a single continuous surface with predictable momentum.
- **Failure modes to eliminate:** flash, image pop-in, card identity confusion, inconsistent timing between gesture and button.
- **Rollout plan:** implement baseline continuity first (no flash), then tune motion curves and add polish.

### CPO (Tinder)

- **User trust:** any flash looks like instability. It will reduce engagement and confidence.
- **Measurable impact:** improved retention and swipe velocity correlates with perceived smoothness.
- **Guardrails:** prioritize stable rendering + prefetch; do not ship “half-polish” where images pop in mid-swipe.

---

## Current state (observed / likely from implementation)

### What users see today

- Swipe works, but **every swipe shows a white flash** (briefly revealing a white background or placeholder).
- The transition reads as: **card exits → white frame → next card appears**, rather than continuous layering.

### Why this likely happens (typical causes in Flutter web)

These are the most common technical causes consistent with the current architecture:

1. **Background mismatch:** a parent surface (Scaffold/Container) is effectively white for a frame while cards rebuild.
2. **Image loading gap:** the “next” card’s image is not yet rasterized/cached; placeholder or blank shows momentarily.
3. **Widget identity churn:** changing keys/state can trigger image widgets to re-resolve, briefly showing placeholder.
4. **Cross-widget inconsistency:** top card and rest cards use different image widgets/placeholder strategies (e.g. one uses `CachedNetworkImage` with spinner, another uses `Image.network`), causing inconsistent paint timing.

---

## We want to avoid (explicit anti-goals)

- **Any solid-color flash** (white/black) between cards.
- **Spinner as a placeholder** on a swipe surface (spinners read as loading, not as designed content).
- **Card pop-in** (card appears after swipe completes rather than already being present behind).
- **Image swap on the same card** (state reuse that makes the “same card” suddenly become a different item).
- **Gesture vs button mismatch** (different animation timing, different commit semantics).

---

## Target interaction spec (what we want)

### 1) Visual continuity (non-negotiable)

- The deck area has a **stable background color** (e.g. `AppTheme.background`) that is never white.
- The next card is **always visible behind** the current card during the swipe (even if partially).
- Card images are **prefetched** or have a **designed fallback** (skeleton/blur), never blank.

### 2) Stack behavior (5-card peek)

- **Visible depth:** show up to **5** cards including top.
- **Offset:** each underlying card is offset by a small translation (e.g. 6–10px) and scaled (e.g. 0.95 → 0.80).
- **Shadow ramp:** top card has the strongest shadow; cards behind have progressively lighter shadows.

### 3) Swipe gesture behavior

- **Drag:** card follows finger/cursor horizontally with slight rotation.
- **Threshold:** commit when beyond threshold or velocity threshold.
- **Cancel:** if not committed, card springs back to center smoothly (no snap).

### 4) Commit animation (exit + promotion)

When a swipe is committed:

- **Top card exit (200–260ms):**
  - Translate offscreen in the swipe direction
  - Rotate slightly more during exit
  - Optional: reduce opacity slightly near the end (do not fade to reveal white; fade into stable background)
- **Next card promotion (same time window):**
  - Underlying card moves to top with a subtle scale-up and translation to center
  - Shadow increases to match top card

**Important:** the deck must never render a frame where *no card* is painted.

### 5) Button-triggered swipe parity

- Tapping X/heart triggers **the exact same commit + animation** as gesture.
- Buttons must be **disabled** while a card is animating to prevent double commits.

---

## Visual language guidelines

### Loading & placeholders

- Prefer **skeleton shimmer** or **blurred image** placeholder inside the card frame.
- Never show a full-screen spinner in the deck region during swiping.
- Ensure underlying cards use **the same image widget strategy** as the top card (consistent decode/caching behavior).

### Motion feel

- Use **easeOut** / spring-like curves that feel responsive.
- Keep motion subtle: swipes should feel direct; promotions should feel supportive, not distracting.

---

## Implementation checklist (to translate direction → code)

### Continuity

- Ensure the deck container background is explicitly set to the app background (never default white).
- Prefetch upcoming card images (top + next N) on deck load and after refetch.
- Use one consistent image approach for top/rest cards (same caching + placeholder strategy).

### Interaction

- Confirm each new top card uses a **new widget State** (keyed by item id).
- Confirm button commits are guarded while animating.

### QA scenarios

- Swipe rapidly 10 times (gesture + buttons). Verify **no flash** and no “loading spinner flash”.
- Slow network / cache cold-start: verify skeleton/blur, not blank/white.
- Resize window (web): verify no layout-induced flash.

---

## Open questions (product decisions)

- Do we want a **like/dislike overlay** (heart/X) that scales in as you drag?
- Do we want a **slight vertical parallax** or only horizontal motion?
- Should we support **undo** visually (bring card back) or keep it disabled for now?


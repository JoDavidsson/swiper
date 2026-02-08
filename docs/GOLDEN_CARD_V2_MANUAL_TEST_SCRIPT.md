# Golden Card v2 Manual Exploratory Test Script (30 Sessions)

> Date: 2026-02-08  
> Goal: Validate Golden Card v2 user experience and cold-start serving quality across realistic interaction patterns.

## 1. Setup

- Enable Golden Card v2: `ENABLE_GOLDEN_CARD_V2=true`
- Disable legacy gold card: `ENABLE_LEGACY_GOLD_CARD=false`
- Set rollout to full for QA: `GOLDEN_CARD_V2_ROLLOUT_PERCENT=100`
- Start app with clean local session for each run.

## 2. Session Matrix

Run 30 sessions total:

- 10 sessions: complete all steps and confirm summary.
- 5 sessions: skip from intro.
- 5 sessions: skip after step 2.
- 5 sessions: complete, then use Adjust and re-confirm.
- 5 sessions: complete while simulating network submit failure (verify retry queue behavior).

## 3. Per-session checklist

For each session, record:

- Session ID
- Path variant (complete/skip/adjust/retry)
- Step completion times (intro, room, sofa, constraints, summary)
- Selected room archetypes and sofa vibes
- Constraints selections
- Whether summary copy matched selections
- First deck quality notes (top 8 diversity and relevance)
- Any UI defects (layout, clipping, untranslated text, interaction issues)

## 4. Pass/Fail Criteria

- No blocking UI defects or dead-ends.
- Completion path always reaches deck.
- Skip path always returns to deck and reprompt logic still works.
- Failed onboarding submit queues locally and retries successfully later.
- `gold_v2_*` events emitted across all expected transitions.
- Deck response includes `rank.onboardingProfile` for completed sessions.
- Deck rank quality fields present: `sameFamilyTop8Rate`, `styleDistanceTop4Min`.

## 5. Debug queries

- Verify onboarding profile write:
  - `GET /api/onboarding/v2?sessionId={sessionId}`
- Verify deck metadata:
  - `GET /api/items/deck?sessionId={sessionId}&limit=10`
- Verify event stream contains v2 events for session.

## 6. Sign-off template

- QA owner:
- Date:
- Sessions executed:
- Pass rate:
- Blocking defects:
- Non-blocking defects:
- Recommendation: go / no-go

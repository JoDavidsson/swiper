# Playwright E2E Testing

Reusable skill for Playwright test automation on the Swiper app.

## Triggers

- "run the E2E tests"
- "write a Playwright test"
- "debug a failing test"
- "validate the app end-to-end"

## Setup

```bash
cd apps/Swiper_flutter
flutter pub get
npx playwright install
```

## Running Tests

```bash
# Run all tests
npx playwright test

# Run with Firebase emulators
./scripts/run_emulators.sh &
npx playwright test

# Run specific test file
npx playwright test tests/my_test.spec.ts
```

## Test Areas

| Area | Tests |
|------|-------|
| Swipe deck | Card rendering, swipe left/right, animation |
| Likes list | Items appear, removal works |
| Compare screen | 2–4 items side-by-side |
| Detail sheet | Tap card, expand content |
| Decision Room | Vote, comment, share link |
| Onboarding | Style/budget collection |
| Featured Distribution | Label visibility, frequency cap |

## CI

Tests run on PR via Playwright CI integration. See `docs/TESTING_LOCAL.md`.

## Files

- `apps/Swiper_flutter/tests/` — Playwright tests
- `scripts/run_emulators.sh`
- `docs/TESTING_LOCAL.md`
- `docs/QA_DIAGNOSTICS_REPORT.md`

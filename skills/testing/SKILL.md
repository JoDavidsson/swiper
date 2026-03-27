---
name: testing
description: Playwright E2E testing skill for Swiper — test automation, Firebase emulator setup, stress testing, and observability validation.
---

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
npx playwright test                          # all tests
./scripts/run_emulators.sh &                 # start emulators first
npx playwright test tests/my_test.spec.ts    # specific file
```

## Test Areas

| Area | Tests |
|------|-------|
| Swipe deck | Card rendering, swipe left/right, animation |
| Likes list | Items appear, removal works |
| Compare screen | 2–4 items side-by-side |
| Featured Distribution | Label visibility, frequency cap |

## Files

- `apps/Swiper_flutter/tests/` — Playwright tests
- `scripts/run_emulators.sh`
- `docs/TESTING_LOCAL.md`

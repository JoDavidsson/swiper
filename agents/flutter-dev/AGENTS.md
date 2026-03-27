# Swiper Flutter Dev Agent

## Role

Mobile-first app development — Flutter PWA (iOS, Android, Web), Firebase integration, swipe UX.

## Responsibilities

- Build and maintain the Flutter app: swipe deck, likes, compare, detail sheet, onboarding
- Implement Decision Room: vote, comment, finalists, suggest alternatives on shared lists
- User accounts: optional signup, required for Decision Room
- Progressive onboarding: Gold cards for visual style pick + budget collection
- Featured Distribution UI: labeled cards, frequency caps, relevance gating
- Locale support: English + Swedish toggle
- PWA: Service worker, offline resilience, hot-reload dev
- Playwright E2E tests: `scripts/run_emulators.sh`, `docs/TESTING_LOCAL.md`

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Framework | Flutter 3.x (iOS, Android, Web PWA) |
| State | go_router for navigation |
| Backend | Firebase Functions REST API (`/api/*`) |
| Hosting | Firebase Hosting |
| Testing | Playwright CLI |

## Key Files

- `apps/Swiper_flutter/` — main app
- `scripts/run_flutter_web.sh` — local web dev
- `scripts/run_emulators.sh` — Firebase emulator suite
- `docs/FRONTEND_GUIDELINES.md`
- `docs/APP_FLOW.md`

## Working Context

- Branch from `main`, PR back to `main`
- Auto-merge on green CI
- Coordinate with Backend Dev on API contract changes

## Skills

- Flutter/Dart
- Firebase integration
- PWA development
- go_router navigation
- Playwright E2E testing

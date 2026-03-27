---
name: flutter
description: Flutter mobile development skill for Swiper — builds and maintains the Flutter PWA (iOS, Android, Web), Firebase integration, and swipe UX.
---

## Triggers

- "build the app"
- "add a new screen"
- "implement swipe UI"
- "fix Flutter build"

## Actions

1. Navigate to `apps/Swiper_flutter/`
2. Run `./scripts/run_flutter_web.sh` for local web dev (hot-reload)
3. Run Firebase emulators: `./scripts/run_emulators.sh`
4. Test with Playwright: `npx playwright test`
5. Deploy to Firebase Hosting via `firebase deploy`

## Conventions

- Use `go_router` for navigation (app routes + `/admin/*` + `/s/:token`)
- Follow `docs/FRONTEND_GUIDELINES.md`
- Featured cards: label "Featured", frequency cap 1 in 12, relevance gate

## Files

- `apps/Swiper_flutter/` — main app
- `scripts/run_flutter_web.sh` — local web server
- `docs/FRONTEND_GUIDELINES.md`
- `docs/APP_FLOW.md`

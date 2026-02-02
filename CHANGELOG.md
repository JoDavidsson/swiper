# Changelog

## 2026-02-02 – Recommendation engine robustness fixes

- **Exploration rate:** applyExploration now replaces roughly `rate × limit` positions (stochastic rounding) instead of treating any non-zero rate as full randomization; rate=0 keeps rank order, rate=1 fully samples from the top-2× pool.
- **Recency-preserving ties:** PreferenceWeightsRanker now keeps candidate input order on score ties (preserves recency when all scores are equal).
- **Atomic preference updates:** swipe-right updates preferenceWeights via Firestore atomic increments to avoid lost updates under concurrency.
- **Persona cold weights:** PersonalPlusPersonaRanker treats all-zero weights as “no personal signal,” allowing persona scores to dominate.
- **Filter parsing guard:** deck filters JSON is validated and returns 400 on invalid input.

## 2026-02-02 – Data Science & Observability Gaps (offline eval, A/B, retention)

- **deck_response logging:** Client now logs rank.variant, rank.variantBucket, and rank.itemIds (served slate) in deck_response events; swipe events include variant/variantBucket when rank context is present. ApiClient parses variant and variantBucket from deck response; schema and EVENT_SCHEMA_V1/EVENT_TRACKING updated. Required for offline eval (liked-in-top-K) and A/B segmentation.
- **events_batch chunking:** POST /api/events/batch chunks into Firestore batches of 500 and commits each chunk so large batches no longer fail (Firestore 500-write limit).
- **Exploration seed:** Deck API uses session-based exploration seed when RANKER_EXPLORATION_SEED is unset (hashSessionId(sessionId)) so exploration order is deterministic per session for A/B.
- **OFFLINE_EVAL.md:** New doc with primary metric (Liked-in-top-K per session), required event fields, A/B segmentation by variant, position-bias note, and optional statistical significance (95% CI, sample size). RECOMMENDATIONS_ENGINE updated to reference it.
- **Bias and retention:** RECOMMENDATIONS_ENGINE documents exposure bias (mitigation: exploration, diversity), item cold start (retrieval by lastUpdatedAt, content-based scoring), and persona cold sessions (default bucket or personal-only). events_v1 retention 24 months documented in PRIVACY_GDPR and RUNBOOK_DEPLOYMENT (Data retention: TTL or scheduled purge).
- **Persona and optional:** Persona pipeline future step includes default bucket for cold sessions; optional diversity (MMR / max per styleTag), weight decay, and score-breakdown explainability documented in RECOMMENDATIONS_ENGINE.

## 2026-02-02 – Deck swipe visual continuity (remove white flash)

- **Card rendering unified:** Introduced [deck_card.dart](apps/Swiper_flutter/lib/shared/widgets/deck_card.dart) and now both the top card and stacked cards render via the same cached image + placeholder strategy (no `Image.network` vs `CachedNetworkImage` mismatch).
- **No spinner placeholders:** Replaced the swipe-surface spinner placeholder with a stable, non-white designed placeholder to avoid perceived “flash” on image decode.
- **Stable deck background:** [swipe_deck.dart](apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart) wraps the deck stack in a `ColoredBox(AppTheme.background)` so there’s never a default white canvas between frames.
- **Prefetch:** SwipeDeck prefetches `top + next 4` images via `precacheImage(CachedNetworkImageProvider(...))` on deck updates to reduce image pop-in on promotion.
- **Promotion polish:** Under-stack cards use implicit animations (`AnimatedPadding`/`AnimatedScale`) so the stack advances smoothly when a card is removed.

## 2026-02-02 – New card on top: each top card is a new State, fix _dragDx carry-over and double-commit

- **Top card identity:** [swipe_deck.dart](apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart) now uses `ValueKey(top.id)` for the top `DraggableSwipeCard` (removed GlobalKey). When the top item changes after a swipe, Flutter disposes the old State and creates a new one for the new item, so each top card is a new widget/State; no state is "inserted" into the previous card.
- **_dragDx fix:** The next card no longer inherits the previous card's drag offset (new State always has `_dragDx = 0`); button-triggered swipe animates from center.
- **Button triggers:** Top card registers trigger callbacks and `isAnimating` getter via optional `onRegisterSwipeTriggers`; [draggable_swipe_card.dart](apps/Swiper_flutter/lib/shared/widgets/draggable_swipe_card.dart) calls it in initState and unregisters in dispose. SwipeDeck stores the callbacks and heart/X buttons call them; no GlobalKey.
- **Double-commit prevention:** Button handlers check `_isAnimatingGetter?.call() == true` before commit + trigger, so double-tap during animation does not duplicate API/tracking. Event data (swipe_left/swipe_right, gesture vs button) unchanged.

## 2026-02-02 – Refetch without loading so card exit animation stays visible

- **Refetch timing:** When remaining deck items fall below 3 after a swipe, [deck_provider.dart](apps/Swiper_flutter/lib/data/deck_provider.dart) now refetches in the background without setting `state = AsyncValue.loading()`. Added `_load({ bool showLoading = true })`; refetch from `removeItemById()` calls `_load(showLoading: false)` so the deck is not replaced by a spinner and the top card’s exit animation stays visible.
- **Clipping audit:** Confirmed deck parent chain (Scaffold body, Expanded, Stack with `clipBehavior: Clip.none`) does not clip; no change needed for card overflow during swipe.

## 2026-02-02 – Deck stack, swipe transition, likes on swipe right, deck bundles

- **Deck stack:** Capped visible stack at 5 cards in [swipe_deck.dart](apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart); order and images match “next to show.” Added `ValueKey(item.id)` on stack and top card for widget identity so the next card reuses the same widget (no image reload).
- **Swipe transition:** Two-phase flow: commit (API + tracking) on swipe start, remove from list only after exit animation completes. [draggable_swipe_card.dart](apps/Swiper_flutter/lib/shared/widgets/draggable_swipe_card.dart) calls `onSwipeRight`/`onSwipeLeft` at commit and `onSwipeAnimationEnd(item)` when animation completes; [deck_provider.dart](apps/Swiper_flutter/lib/data/deck_provider.dart) `swipe()` no longer mutates state; `removeItemById(itemId)` mutates state; deck_screen wires `onSwipeAnimationEnd` to `removeItemById`. Button swipes trigger card animation via `DraggableSwipeCardState.triggerSwipeRight`/`triggerSwipeLeft`. Eliminates white flicker when revealing next card.
- **Likes on swipe right:** [swipe.ts](firebase/functions/src/api/swipe.ts) writes to top-level `likes` collection (doc id `sessionId_itemId`, merge for idempotency) and `anonSessions/{sessionId}/likes/{itemId}` when `direction === "right"`, so the Likes page shows swiped-right items.
- **Deck bundles:** Default deck request size reduced to 10; [deck_provider.dart](apps/Swiper_flutter/lib/data/deck_provider.dart) refetches when remaining items &lt; 3 after a swipe.

## 2026-02-02 – Recommendation ranking normalization and analyzer fixes

- **Ranker:** Improved recommendation ranking normalization in [firebase/functions/src/ranker/](firebase/functions/src/ranker/): shared `normalizeScore(score, signalCount)` (divide by √signalCount) in scoreItem.ts; PreferenceWeightsRanker and PersonalPlusPersonaRanker use it to reduce tag-count bias. New/updated tests in scoreItem.test.ts, preferenceWeightsRanker.test.ts, personalPlusPersonaRanker.test.ts. [docs/RECOMMENDATIONS_ENGINE.md](docs/RECOMMENDATIONS_ENGINE.md) updated.
- **Flutter analyzer:** Removed redundant `notifyListeners()` in router (ValueNotifier setter already notifies); removed unused `api_client` import in compare_screen so `flutter analyze --no-fatal-infos` passes with no warnings.

## 2026-02-01 – Swipe-first deck launch and menu consolidation

- **Entry flow:** App opens directly into the deck (no splash). One-time swipe hint overlay stored in Hive.
- **Navigation:** Added hamburger menu on deck (Filters, Likes, Preferences, Data & Privacy, Language). Bottom nav removed from the deck surface.
- **Detail modal:** Near full-screen sheet with handle, dimmed backdrop, and fast spring scale-in.
- **Likes:** Compare action removed from the UI; shortlist sharing remains.
- **QA/docs:** Integration test and runbooks updated to match the new deck-first flow.

## 2025-01-31 – Admin login redirect fix (no more kick-back to splash)

- **Router:** Stopped recreating `GoRouter` when `adminAuthProvider` changes. Recreating the router reset to `initialLocation: '/'` and sent the user back to the splash screen after login. Now the router is built once; admin auth is mirrored in a `ValueNotifier` and passed as `refreshListenable`. A single top-level `redirect` reads the notifier and sends unauthenticated admin routes to `/admin/login` and authenticated `/admin` or `/admin/login` to `/admin/dashboard`. Login no longer kicks the user back.

## 2025-01-31 – Next phase: deploy, real supply, locale, admin auth, SSO stub

- **Staging deploy:** [scripts/deploy_staging.sh](scripts/deploy_staging.sh) builds Flutter web + Functions and runs `firebase deploy --only functions,hosting,firestore:rules,firestore:indexes`. RUNBOOK_DEPLOYMENT updated with one-command deploy.
- **Real supply:** [config/sources.json](config/sources.json) has two sources: `sample_feed` (CSV) and `demo_feed` (JSON). RUNBOOK post-deploy notes updated for demo_feed and production feed URLs.
- **Language / locale:** Swedish and English; app locale from Hive (`swiper_locale`). [lib/l10n/app_strings.dart](apps/Swiper_flutter/lib/l10n/app_strings.dart) and [lib/data/locale_provider.dart](apps/Swiper_flutter/lib/data/locale_provider.dart); profile Language tile opens sheet to pick Swedish/English; splash and Data & Privacy use localised strings.
- **Admin auth:** Firebase Auth allowlist (Firestore `adminAllowlist`, document ID = admin email). Backend: [firebase/functions/src/api/admin_auth.ts](firebase/functions/src/api/admin_auth.ts) `requireAdminAuth`; all admin routes except POST admin/verify require Bearer token + allowlist. Flutter: firebase_auth + google_sign_in; admin login has "Sign in with Google" and legacy password; ApiClient sends Authorization Bearer for admin requests; RUNBOOK and SECURITY updated.
- **SSO stub:** Data & Privacy "Connect social accounts" tappable; shows "Coming soon" dialog. Anonymous remains default.
- **Project plan:** docs/PROJECT_PLAN.md next-phase goals marked done with short notes.

## 2025-01-31 – Plan implementation (deck filters, deploy runbook, profile, opt-out, admin)

- **Deck filters UI:** Real filter sheet with size class (small/medium/large), color family, and condition (new/used). Filters passed to `getDeck(filters)`; deck refreshes on apply/clear. `filter_change` event logged on apply and clear with metadata (sizeClass, colorFamily, newUsed). ApiClient sends filters as JSON string to backend.
- **First production deploy:** RUNBOOK_DEPLOYMENT.md updated with "Post-deploy smoke test" checklist (app load, session, deck, filters, detail, likes, compare, go redirect, profile, admin, shared shortlist).
- **Profile Language:** Stub replaced with "Swedish / English – coming soon"; ListTile disabled so expectations are clear.
- **Opt-out UI (functional):** Analytics opt-out stored in Hive (`swiper_analytics_opt_out`). Data & Privacy screen has a working Switch; when on, non-essential events (open_detail, detail_dismiss, filter_sheet_open, filter_change, session_start, deck_empty_view, compare_open, onboarding_complete) are not sent. Swipes and likes unchanged.
- **Admin Create source:** Dialog replaced with form (name, mode, baseUrl, isEnabled, rateLimitRps); submits to POST /api/admin/sources.
- **Admin Items:** Backend GET /api/admin/items (limit) added; Flutter Admin Items screen lists recent items (title, price, sourceId, active).
- **Admin Import:** Stub replaced with instructions and "Trigger sample / first source run" button that triggers run for a source named "sample" or the first source.

## 2025-01-31 – User interaction capture & Data & Privacy

- **Session context:** Backend `POST /api/session` accepts optional body: `locale`, `platform`, `screenBucket`, `timezoneOffsetMinutes`, `userAgent`; stored on **anonSessions**. Flutter sends device context via `DeviceContext.toSessionBody()` when creating session.
- **Client events:** Flutter logs to `POST /api/events`: `open_detail`, `detail_dismiss` (with `timeViewedMs`), `compare_open`, `filter_sheet_open`, `session_start`, `deck_empty_view`, `onboarding_complete` (with preferences). Deck and likes detail sheets log open/dismiss; compare screen logs once; deck logs session_start and deck_empty_view; onboarding logs completion with style/budget/prefs.
- **Session early create:** Splash “Get started” and “Skip to swipe” call `ensureSession()` so onboarding_complete can be logged with sessionId.
- **Data & Privacy screen:** New `/profile/data-privacy` explains what we collect (session/device, usage events); placeholders for “Opt out of analytics” and “Connect social accounts (Instagram/Facebook)” as coming later. Profile entry renamed to “Data & Privacy”.
- **Docs:** EVENT_TRACKING.md updated with client events and session context; backlog items for functional opt-out UI and SSO/social login.

## 2025-01-31 – MVP implementation

- **Flutter app**: Skeleton, Scandi theme, go_router, splash, onboarding (3-step), deck (swipe stack + draggable cards), detail sheet, likes (grid/list, compare, share), compare screen, profile, shared shortlist `/s/:token`, admin console (dashboard, sources, runs, items, import, QA). Riverpod + Dio + Hive.
- **Firebase**: Firestore rules/indexes, Cloud Functions (session, deck, swipe, likes, shortlists, events, go redirect, admin stats/sources/runs/qa/run trigger). Hosting rewrites for /go, /api, /s.
- **Supply Engine**: Python FastAPI, feed ingestion (CSV/JSON), normalization (material, color, size), Firestore client, crawl stub, extraction (JSON-LD + heuristics). Sample feed + config/sources.json. Dockerfile, run scripts.
- **Admin**: Password gate, sources CRUD + Run now, runs list/detail, QA completeness report.
- **Tests**: Flutter (preference scoring, filter logic, item model, swipe deck widget). Functions (go 400, shortlists create 400). Supply Engine (normalization, JSON-LD extractor). CI: GitHub Actions (Flutter analyze/test/build, Functions build/test, Supply Engine pytest).
- **Docs**: ASSUMPTIONS, DECISIONS, ARCHITECTURE, DATA_MODEL, TAG_TAXONOMY, INGESTION_COMPLIANCE, SECURITY, PRIVACY_GDPR, RUNBOOK_LOCAL_DEV, RUNBOOK_DEPLOYMENT.

# Changelog

## 2026-02-05 – Smart Crawler Auto-Discovery

### Major Feature: Automated Source Configuration
Users can now add retailer sources with just a URL - the system automatically discovers:
- Domain root and robots.txt location
- Available sitemaps (including sitemap indexes)
- Product URL counts and category patterns
- Recommended crawl strategy (sitemap vs category crawl)

### Backend Changes
- **URL Normalization** (`services/supply_engine/app/normalization.py`):
  - Added `normalize_source_url()` for parsing user input URLs
  - Added `extract_domain_root()` for proper robots.txt discovery
  - Fixed bug where robots.txt was fetched from subpath instead of domain root

- **Auto-Discovery Module** (`services/supply_engine/app/discovery.py`):
  - New `discover_from_url()` function for URL analysis
  - Samples sitemaps to estimate product counts
  - Returns strategy recommendation (sitemap vs crawl)

- **Supply Engine API** (`services/supply_engine/app/main.py`):
  - New `/discover` endpoint for preview without saving

- **Crawl Ingestion** (`services/supply_engine/app/crawl_ingestion.py`):
  - Updated to support new `derived` config structure
  - Backward compatible with legacy source fields
  - Path pattern filtering for sitemap URLs

- **Firebase Functions** (`firebase/functions/src/api/admin_sources.ts`):
  - New `POST /api/admin/sources/preview` endpoint
  - New `POST /api/admin/sources/create-with-discovery` endpoint
  - Stores both user input and derived configuration

### Frontend Changes
- **API Client** (`apps/Swiper_flutter/lib/data/api_client.dart`):
  - Added `adminPreviewSource()` method
  - Added `adminCreateSourceWithDiscovery()` method

- **Admin Sources Screen** (`apps/Swiper_flutter/lib/features/admin/admin_sources_screen.dart`):
  - Redesigned "Add Retailer" dialog with simplified workflow
  - Single URL input with "Detect" button
  - Visual preview of discovery results before saving
  - Collapsible advanced settings (rate limit, enabled flag)

### Bug Fixes
- Fixed robots.txt discovery to always use domain root (RFC compliance)
- Fixed sitemap URL construction in `sitemap.py` and `fetcher.py`

---

## 2026-02-05 – Bug Fixes & UX Improvements (Testing Round)

### P0 Critical Fixes
- **Gold Card Empty Page Bug**: Fixed budget card not appearing after visual card completion when deck is empty (removed `items.isNotEmpty` check)
- **Auth Screens Missing Back Button**: Added explicit close buttons to login and signup screens for proper navigation
- **Likes Screen List View Broken**: Created separate `_LikeListTile` widget with fixed height for ListView rendering (fixes Expanded constraint issue)
- **Compare Button Missing**: Added Compare button to Likes screen that appears when 2-4 items are selected

### P1 High Priority Fixes
- **Unlike/Remove Functionality**: Added like toggle button to detail sheet with visual feedback and proper state management
- **Admin Run Now Error Handling**: Improved error messages with specific guidance when Supply Engine is unreachable (503 with helpful hints)
- **Admin Items Screen Enhancement**: Complete rewrite with search bar, source/status filters, item detail modal with raw JSON view

### P2 UX Improvements
- **Admin Runs Screen Enhancement**: Added source name/domain display, timestamps with relative time, duration calculation, stats chips, and detailed job listings
- **Empty Deck UX**: Contextual messaging based on filter state with "Clear Filters" button when filters are active

### Files Changed
- `apps/Swiper_flutter/lib/features/deck/deck_screen.dart`: Gold card fix, empty deck UX
- `apps/Swiper_flutter/lib/features/auth/login_screen.dart`: Close button
- `apps/Swiper_flutter/lib/features/auth/signup_screen.dart`: Close button
- `apps/Swiper_flutter/lib/features/likes/likes_screen.dart`: List view fix, compare button, unlike integration
- `apps/Swiper_flutter/lib/shared/widgets/detail_sheet.dart`: Like toggle button
- `apps/Swiper_flutter/lib/shared/widgets/swipe_deck.dart`: Empty state widget with filter awareness
- `apps/Swiper_flutter/lib/features/admin/admin_items_screen.dart`: Full rewrite with search/filters
- `apps/Swiper_flutter/lib/features/admin/admin_runs_screen.dart`: Enhanced with more context
- `firebase/functions/src/api/admin_run_trigger.ts`: Better error handling

---

## 2026-02-05 – Code Quality Fixes (Post-Phase 11 QA)

### Flutter Fixes
- Removed unused imports in `router.dart`, `auth_provider.dart`, `decision_room_screen.dart`
- Removed unused `_shareShortlist` method from `likes_screen.dart`
- Removed unused `_isDragging` field from `deck_screen.dart`
- Fixed unnecessary casts in `admin_catalog_preview_screen.dart` by using typed `Future.wait<T>`
- Fixed widget test timer cleanup issue in `swipe_deck_test.dart` with proper `pumpAndSettle`
- Added ignore comments for intentionally reserved fields in `swipe_deck.dart`

### Test Results
- All 11 Flutter unit tests passing
- TypeScript backend compiles cleanly
- All 36 Firebase Functions tests passing

---

## 2026-02-05 – Phase 11: Retailer Data Model + Confidence Score (Complete)

Full implementation of retailer data infrastructure, segment targeting, campaigns, and the Confidence Score system.

### Retailer Data Model (Backend)
- **Retailers collection** (`retailers.ts`): Full CRUD API for retailer management
  - `POST /api/admin/retailers`: Create retailer (admin only)
  - `GET /api/admin/retailers`: List all retailers (admin only)
  - `GET /api/retailers/:id`: Get retailer details (public)
  - `PATCH /api/admin/retailers/:id`: Update retailer (admin only)
  - `POST /api/retailers/:id/claim`: Claim retailer ownership (requires auth)
  - `GET /api/retailer/me`: Get current user's retailer (requires auth)

### Segments Collection (Backend)
- **Segments API** (`segments.ts`): Targeting definitions with system templates
  - 6 system segment templates for Sweden launch (budget-modern, premium-scandinavian, compact-urban, family-friendly, luxury-design, all-sweden)
  - `GET /api/segments/templates`: List system templates (public)
  - `POST /api/segments`: Create custom segment (requires auth)
  - `GET /api/segments`: List segments for retailer (requires auth)
  - `GET /api/segments/:id`: Get segment by ID
  - `PATCH /api/segments/:id`: Update custom segment (requires auth)
  - `DELETE /api/segments/:id`: Delete custom segment (requires auth)

### Campaigns Collection (Backend)
- **Campaigns API** (`campaigns.ts`): Featured distribution campaigns
  - `POST /api/retailer/campaigns`: Create campaign (requires retailer auth)
  - `GET /api/retailer/campaigns`: List campaigns (requires auth)
  - `GET /api/retailer/campaigns/:id`: Get campaign details (requires auth)
  - `PATCH /api/retailer/campaigns/:id`: Update campaign (requires auth)
  - `POST /api/retailer/campaigns/:id/pause`: Pause active campaign
  - `POST /api/retailer/campaigns/:id/activate`: Activate draft/paused campaign
  - `DELETE /api/retailer/campaigns/:id`: Delete draft campaign

### Confidence Score System (Backend)
- **Scores API** (`scores.ts`): Score query endpoints
  - `GET /api/scores?segmentId=&timeWindow=&band=`: Query scores with filters
  - `GET /api/scores/:productId`: Get product scores across segments
  - `GET /api/admin/scores/summary`: Aggregate score statistics (admin)
  - `POST /api/admin/scores/recalculate`: Trigger recalculation (admin)
- **Score Calculation Job** (`confidence_score.ts`): Scheduled hourly function
  - Bayesian smoothing for low-volume items
  - Weighted scoring: saveRate (50%), clickRate (15%), volume (15%), creative (20%)
  - Time windows: 7d, 30d, 90d
  - Score banding: green (60+), yellow (30-59), red (0-29)

### Reason Codes
- Dynamic reason code generation based on metrics:
  - `STRONG_SAVES` / `GOOD_SAVES` / `LOW_SAVES`: Save rate signals
  - `HIGH_CLICKS` / `LOW_CLICKS`: Click rate signals
  - `HIGH_SKIP`: Frequently skipped items
  - `LOW_VOLUME` / `HIGH_CONFIDENCE`: Impression volume signals
  - `EXCELLENT_CREATIVE` / `CREATIVE_ISSUES`: Image quality signals

### Firestore Updates
- **Security rules**: Added rules for `retailers`, `segments`, `campaigns`, `scores`, `scoreCalculationLogs`, `scoreRecalculationJobs`
- **Composite indexes**: Added 12 new indexes for efficient querying

### Scripts
- **Segment template seeder** (`seed_segment_templates.js`): Seeds system segment templates

---

## 2026-02-05 – Phase 10: Premium Image Display + Brand Trust (Complete)

Full implementation of premium image rendering, CDN pipeline, and Creative Health scoring.

### Premium Image Card (Flutter)
- **PremiumImageCard widget** (`premium_image_card.dart`): Reusable component with contain + blurred background pattern
- **DeckCard upgrade**: Now uses premium rendering by default with two-layer approach
  - Background: Blurred cover image (lower resolution for performance)
  - Foreground: Contained image showing full product without distortion
- **Shimmer placeholder**: Animated loading state for premium cards

### CDN Image Pipeline (Backend)
- **Image proxy enhancement** (`image_proxy.ts`): Extended with Sharp library for server-side processing
  - Width parameter: Resize to 400w, 800w, or 1200w
  - Format parameter: WebP, JPEG, or PNG output
  - Quality parameter: 1-100 quality control
  - Auto WebP: Serves WebP when browser supports it via Accept header
- **Image metadata endpoint** (`GET /api/image-meta`): Validates images without full download
  - Returns dimensions, aspect ratio, format, file size
  - Classifies aspect ratio (portrait, landscape, square, etc.)
  - Lists validation issues

### Image Validation & Creative Health
- **Python validation module** (`image_validation.py`): Async image validation for Supply Engine
  - Resolution checks (min 400x400)
  - Aspect ratio classification
  - File size validation
  - Creative Health score calculation (0-100)
- **Admin validation API** (`admin_image_validation.ts`):
  - `POST /api/admin/validate-images`: Batch validate items
  - `GET /api/admin/creative-health-stats`: Aggregate health statistics
- **Item schema update**: Added `imageValidation` and `creativeHealth` fields to items collection

### Catalog Preview UI (Flutter)
- **AdminCatalogPreviewScreen**: New admin screen for image quality review
  - Grid view with Creative Health badges (green/yellow/red)
  - Comparison view: Side-by-side legacy vs premium rendering
  - Health statistics header showing band distribution
  - Trigger validation button for batch processing

### API Client Updates
- Added `ImageWidth` enum (thumbnail: 400, card: 800, detail: 1200)
- Added `ImageFormat` enum (webp, jpeg, png)
- Updated `proxyImageUrl()` to support width/format/quality params
- New admin methods: `adminValidateImages()`, `adminGetCreativeHealthStats()`

### Dependencies
- Added `sharp@0.33.2` to Firebase Functions for image processing
- Added `Pillow==10.2.0` to Supply Engine for Python image validation

---

## 2026-02-05 – Phase 9: User Accounts + Decision Room (Complete)

Full implementation of user authentication and collaborative Decision Room feature.

### Backend (Firebase Functions)
- **User authentication middleware** (`require_user_auth.ts`): Firebase ID token verification for regular users
- **Auth API endpoints** (`auth.ts`): `POST /api/auth/link-session` (migrate anonymous data), `GET /api/auth/me` (user profile)
- **Decision Room API** (`decision_rooms.ts`): Full CRUD + participation endpoints
  - `POST /api/decision-rooms`: Create room (requires auth)
  - `GET /api/decision-rooms/:roomId`: View room (public)
  - `POST /api/decision-rooms/:roomId/vote`: Cast vote (requires auth)
  - `POST /api/decision-rooms/:roomId/comments`: Add comment (requires auth)
  - `GET /api/decision-rooms/:roomId/comments`: List comments (public)
  - `POST /api/decision-rooms/:roomId/suggest`: Suggest alternative product (requires auth)
  - `POST /api/decision-rooms/:roomId/finalists`: Set final 2 items (creator only)
- **Firestore rules**: Added rules for `users`, `decisionRooms`, `votes`, `comments` collections
- **Firestore indexes**: Added composite indexes for efficient queries

### Frontend (Flutter)
- **Auth provider** (`auth_provider.dart`): Firebase Auth state management with Riverpod
  - Email/password sign-up and sign-in
  - Google Sign-In integration
  - Automatic session linking on authentication
  - Password reset functionality
- **Login screen** (`login_screen.dart`): Email + Google sign-in UI with redirect support
- **Sign-up screen** (`signup_screen.dart`): Account creation UI with validation
- **Decision Room screen** (`decision_room_screen.dart`): Full collaborative experience
  - Item grid with vote buttons (up/down)
  - Real-time vote counts
  - Comment section with input
  - "Suggest alternative" dialog with URL input
  - "Pick finalists" for room creator
  - Share functionality
- **Likes screen update**: Replaced "Share shortlist" with "Create Decision Room" flow
- **Router updates**: Added `/auth/login`, `/auth/signup`, `/r/:roomId` routes
- **API client extensions**: Methods for all new auth and Decision Room endpoints

### Analytics Events
- `decisionroom_create`: When room is created
- `decisionroom_view`: When room is viewed
- `decisionroom_vote`: When user votes on an item
- `decisionroom_comment`: When user adds a comment
- `finalists_set`: When creator picks final 2
- `suggest_alternative`: When user suggests a product URL

### Deferred
- Push notifications (9.10) deferred to future iteration

---

## 2026-02-05 – Commercial Platform Build Spec v1 → v2

Comprehensive documentation update integrating the full Retailer Platform build specification across all project documentation.

### COMMERCIAL_STRATEGY.md (Major Update)
- **Product north star:** Added honest value props (more appearances to target personas, high-intent consideration behaviors)
- **Non-negotiables (trust):** Documented ad-free Decision Room, labeled/capped/relevance-gated Featured
- **Retailer target audience:** Economic buyers (Head of Marketing, E-com Director, CEO), day-to-day users (performance marketers, merchandisers, agencies)
- **Confidence Score:** Replaced HIS terminology with Confidence Score (0–100) for retailer UI; includes calculation overview, color bands (green/yellow/red), reason codes
- **Roadmap framing:** v1 (Monetizable MVP), v2 (Close-Rate Proof + Pixel), v3 (Retention Engine + Inspiration Deck), v4 (Creative Lab)
- **Definition of done for v1:** Invoice-ready criteria

### PRD.md (Major Update)
- **Decision Room features:** Vote per product, comment threads, "Final 2" mode, suggest alternative
- **Featured Distribution specs:** Labeled, frequency capped (1 in 12), relevance-gated, diversity constraints
- **Confidence Score specs:** 0–100 per product × segment, inputs (saves, shares, compares, returns, dwell), Bayesian smoothing, banding, reason codes
- **Retailer Console user stories:** Insights Feed, Campaign Builder, Catalog Control, Reports
- **Commercial success criteria:** Retailer activation, campaign fill rate, CPScore benchmark

### IMPLEMENTATION_PLAN.md (Major Update)
- **Phase 9:** User Accounts + Decision Room (11 tasks)
- **Phase 10:** Premium Image Display + Brand Trust (7 tasks)
- **Phase 11:** Retailer Data Model + Confidence Score (10 tasks)
- **Phase 12:** Featured Distribution (11 tasks)
- **Phase 13:** Retailer Console v1 (13 tasks)
- **Phase 14:** Admin Governance + v1 Launch (6 tasks)
- **v2 roadmap:** Click ID, Pixel SDK, conversion reporting, audience tools, geo granularity (13 tasks)
- **v3 roadmap:** Inspiration Deck, Sponsored Themes, Email/SMS (9 tasks)
- **v4 roadmap:** Creative Lab (4 tasks)
- **Engineering checklist:** New collections (users, decisionRooms, votes, comments, retailers, segments, campaigns, scores) and event schema additions

### APP_FLOW.md (Major Update)
- **Decision Room flows:** Create (auth required), view (public), participate (vote/comment/suggest), finalists
- **Retailer Console flows:** Insights Feed, Campaign Builder, Catalog Control, Trends, Reports
- **Featured card handling:** Badge display, logging with campaign_id
- **New screen inventory:** Decision Room, Auth screens, Retailer Console (10 screens)
- **State transitions:** Decision Room lifecycle, Campaign lifecycle

### BACKEND_STRUCTURE.md (Major Update)
- **New collections:** `users`, `decisionRooms`, `decisionRoomItems`, `votes`, `comments`, `retailers`, `segments`, `campaigns`, `scores`
- **Decision Room API:** Create, view, vote, comment, suggest, finalists endpoints
- **Retailer Console API:** Campaigns CRUD, catalog control, insights feed, trends, reports
- **Confidence Score spec (Appendix):** Full calculation including time windows, rate calculation, weighted intent rate, Bayesian smoothing, 0–100 mapping, banding, reason codes
- **Featured serving algorithm:** Slot determination, eligibility filtering, ranking, constraints, logging
- **Click ID + Pixel spec (v2):** Outbound format, pixel behavior, audience enablement, GTM recipes

### FRONTEND_GUIDELINES.md (Major Update)
- **Premium Image Display spec:** Contain + blurred background pattern for furniture images
- **Flutter implementation:** `PremiumImageCard` widget with two-layer rendering
- **CSS equivalent:** For web reference
- **Image CDN:** Size variants (400w, 800w, 1200w), WebP + JPEG fallback
- **Featured Badge component:** Styling and positioning
- **Confidence Score Badge component:** Color-coded by band
- **Insight Feed Card component:** Retailer console pattern

## 2026-02-05 – Commercial Strategy documentation

- **COMMERCIAL_STRATEGY.md:** Added comprehensive commercial strategy document covering retailer-first monetization approach. Includes Featured Distribution (Product Deck), Retailer Console, Sponsored Themes, Swiper Pixel + Audience Retargeting, Lifecycle Messaging, and Affiliate revenue streams. Defines High-Intent Save (HIS) as the core sellable metric. Documents Decision Room ethical boundaries (no paid placement in share/compare). Outlines short/medium/long-term roadmap for monetization features.

## 2026-02-02 – Documentation consolidation: 6-document knowledge base

- **PRD.md:** Consolidated product requirements from existing docs (ASSUMPTIONS, PROJECT_PLAN, CARD_INTERACTION, RECOMMENDATIONS_ENGINE, INGESTION_COMPLIANCE, PRIVACY_GDPR, SECURITY, TAG_TAXONOMY). Contains product overview, scope (in/out), user stories, success criteria, feature specs, constraints, risks, and glossary.
- **APP_FLOW.md:** Complete screen inventory, navigation flows, error handling, deep links, state transitions, and analytics events per flow. Combines ARCHITECTURE, TESTING_LOCAL, EVENT_TRACKING, and Flutter app analysis.
- **TECH_STACK.md:** Locked dependencies with exact versions for Flutter (Riverpod 2.4.9, go_router 13.0.0, etc.), Firebase Functions (Node 20, TS 5.3.3), and Supply Engine (FastAPI 0.109.0, httpx 0.26.0). Environment variables and config files documented.
- **FRONTEND_GUIDELINES.md:** Complete design system: color palette (hex codes), typography scale (Inter, sizes, weights), spacing scale (4px multiples), responsive breakpoints, component patterns (swipe card, buttons, list tiles), animation guidelines, accessibility requirements, folder structure, and code style.
- **BACKEND_STRUCTURE.md:** Full Firestore schema (10 collections with field types), security rules, API endpoint contracts (public and admin), ranker interface, data flow diagrams, error codes, and environment configuration.
- **IMPLEMENTATION_PLAN.md:** Step-by-step build sequence with completed phases (0-7), upcoming phases (8-12), implementation guidelines, branching strategy, risk register, and decision log.

## 2026-02-02 – P1 Recommendation Backbone: extract material, color, dimensions from crawl

- **NormalizedProduct extended:** Added `dimensions_raw`, `material_raw`, `color_raw` so crawl items can be ranked and filtered like feed items.
- **JSON-LD extraction:** Parses `width`, `height`, `depth` (including Schema.org QuantitativeValue), `color`, `material`, and `additionalProperty` (Bredd/Höjd/Djup/Färg/Material).
- **Embedded JSON extraction:** Extracts dimensions, material, color from product-like nodes (width/height/depth, dimensionsCm, material, colorFamily, etc.).
- **Recipe pass-through:** Dimensions, material, color from recipe output flow into items.
- **Title color inference:** `infer_color_from_title()` scans titles for color tokens (e.g. "svart", "grå"); used when DOM fallback has no structured color.
- **Crawl ingestion:** Replaces hardcoded `dimensionsCm`, `sizeClass`, `material`, `colorFamily` with normalized extracted values. Size class derived from width via `size_class_from_width_cm()`.

## 2026-02-02 – Supply Engine crawl locator + self-healing-ready extractor (Sweden-first)

- **Crawl ingestion implemented:** `mode:"crawl"` sources now run URL discovery (robots/sitemaps + bounded category crawl) and write operational state to Firestore (`crawlUrls`, `productSnapshots`, `extractionFailures`, `metricsDaily`, `crawlRecipes`).
- **Extraction cascade:** Deterministic extractor prioritizes JSON-LD, then embedded JSON (Next.js + generic blobs), then optional per-retailer recipe runner, then semantic DOM fallbacks (canonical/og/meta); includes Swedish money parsing and completeness scoring.
- **Recipe system (deterministic):** Added recipe JSON validation + runner (minimal JSONPath, DOM selectors, transforms) and promotion gate evaluation (success rate + completeness thresholds).
- **Monitoring + drift triggers:** Daily metrics are persisted and basic drift detection records alerts into `extractionFailures` when success/completeness drops.

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

# Swiper – App Flow

> **Last updated:** 2026-02-05  
> Navigation paths, screen inventory, and user journey documentation.

---

## 1. Screen Inventory

### Public Consumer Screens

| Route | Screen | Component | Description |
|-------|--------|-----------|-------------|
| `/` | Deck | `DeckScreen` | Main swipe deck (default entry) |
| `/deck` | Deck | `DeckScreen` | Alias for `/` |
| `/onboarding` | Onboarding | `OnboardingScreen` | Style/budget preference setup |
| `/likes` | Likes | `LikesScreen` | Saved items list |
| `/compare` | Compare | `CompareScreen` | Side-by-side comparison (2–4 items) |
| `/profile` | Profile | `ProfileScreen` | User settings |
| `/profile/data-privacy` | Data Privacy | `DataPrivacyScreen` | Privacy controls |
| `/s/:token` | Shared Shortlist | `SharedShortlistScreen` | View shared shortlist by token |
| `/r/:roomId` | Decision Room | `DecisionRoomScreen` | Collaborative decision room |
| `/auth/login` | Login | `LoginScreen` | User authentication |
| `/auth/signup` | Sign Up | `SignUpScreen` | Account creation |

### Admin Screens

| Route | Screen | Component | Description |
|-------|--------|-----------|-------------|
| `/admin` | Admin Login | `AdminLoginScreen` | Redirects to `/admin/login` |
| `/admin/login` | Admin Login | `AdminLoginScreen` | Google Sign-In + password fallback |
| `/admin/dashboard` | Dashboard | `AdminScreen` | Stats overview |
| `/admin/sources` | Sources | `AdminSourcesScreen` | Manage data sources |
| `/admin/runs` | Runs | `AdminRunsScreen` | Ingestion run history |
| `/admin/items` | Items | `AdminItemsScreen` | Browse items |
| `/admin/import` | Import | `AdminImportScreen` | Manual data import |
| `/admin/qa` | QA | `AdminQAScreen` | Diagnostics report |
| `/admin/curated` | Curated Sofas | `AdminCuratedScreen` | Manage gold card items |
| `/admin/governance` | Governance | `AdminGovernanceScreen` | Caps, thresholds, segments |

### Retailer Console Screens (v1)

| Route | Screen | Component | Description |
|-------|--------|-----------|-------------|
| `/console` | Console Home | `ConsoleHomeScreen` | Insights Feed |
| `/console/login` | Console Login | `ConsoleLoginScreen` | Retailer authentication |
| `/console/campaigns` | Campaigns | `ConsoleCampaignsScreen` | Campaign list |
| `/console/campaigns/new` | Campaign Builder | `CampaignBuilderScreen` | Create campaign |
| `/console/campaigns/:id` | Campaign Detail | `CampaignDetailScreen` | View/edit campaign |
| `/console/catalog` | Catalog | `ConsoleCatalogScreen` | Product control |
| `/console/catalog/:id` | Product Preview | `ProductPreviewScreen` | Preview as card |
| `/console/trends` | Trends | `ConsoleTrendsScreen` | Market trends |
| `/console/reports` | Reports | `ConsoleReportsScreen` | Performance reporting |
| `/console/settings` | Settings | `ConsoleSettingsScreen` | Account settings |

---

## 2. Navigation Flows

### 2.1 First Launch Flow

```
App Launch
    │
    ▼
┌─────────────────────┐
│  Check session ID   │
│  (Hive local store) │
└─────────────────────┘
    │
    ├── No session ──▶ POST /api/session ──▶ Store sessionId
    │
    ▼
┌─────────────────────┐
│  Check swipeHintSeen│
└─────────────────────┘
    │
    ├── Not seen ──▶ Show swipe hint overlay (one-time)
    │
    ▼
┌─────────────────────┐
│     Deck Screen     │
│  GET /api/items/deck│
└─────────────────────┘
```

### 2.1b Golden Card v2 Flow (Shipped, Feature-Flagged)

```
App Launch
    │
    ▼
┌─────────────────────┐
│  Check session ID   │
│  (Hive local store) │
└─────────────────────┘
    │
    ▼
┌────────────────────────────────────┐
│ Check onboardingV2 completion flag │
└────────────────────────────────────┘
    │
    ├── Should prompt + in rollout cohort ──▶ Golden Card v2 flow
    │                     1) Intro
    │                     2) Room vibes (pick 2)
    │                     3) Sofa vibes (pick 2)
    │                     4) Constraints
    │                     5) Reaffirmation summary
    │
    └── Completed / skipped / out of cohort ──▶ Deck Screen
                       GET /api/items/deck
```

Golden Card v2 reference docs:
- `docs/GOLDEN_CARD_V2_UI_UX_SPEC.md`
- `docs/GOLDEN_CARD_V2_EXECUTION_ROADMAP.md`

### 2.2 Core Swipe Flow

```
Deck Screen
    │
    ├── Swipe RIGHT ──────────────────────────┐
    │   ├── POST /api/swipe {direction: right}│
    │   ├── Track: swipe_right event          │
    │   ├── Update preference weights         │
    │   ├── Card exits right (200–260ms)      │
    │   └── Remove from deck state            │
    │
    ├── Swipe LEFT ───────────────────────────┐
    │   ├── POST /api/swipe {direction: left} │
    │   ├── Track: swipe_left event           │
    │   ├── Card exits left (200–260ms)       │
    │   └── Remove from deck state            │
    │
    ├── TAP card ─────────────────────────────┐
    │   └── Open DetailSheet (bottom sheet)   │
    │       ├── Images gallery                │
    │       ├── Price, dimensions, description│
    │       ├── "Add to likes" button         │
    │       └── "View on site" → /go/:itemId  │
    │
    ├── TAP Heart button ─────────────────────┐
    │   └── Same as swipe right               │
    │
    ├── TAP X button ─────────────────────────┐
    │   └── Same as swipe left                │
    │
    ├── TAP Filter icon ──────────────────────┐
    │   └── Open FilterSheet                  │
    │       ├── Size: small / medium / large  │
    │       ├── Color: white, beige, gray...  │
    │       ├── Condition: new / used         │
    │       └── Apply → refresh deck          │
    │
    ├── FEATURED card appears ────────────────┐
    │   └── "Featured" badge visible          │
    │       ├── Same swipe interactions       │
    │       └── Logs campaign_id + is_featured│
    │
    └── Remaining items ≤ 3 ──────────────────┐
        └── Background fetch next batch       │
            (no loading spinner shown)        │
```

### 2.3 Likes & Compare Flow

```
Deck Screen
    │
    ▼
Hamburger Menu → Likes
    │
    ▼
┌─────────────────────┐
│    Likes Screen     │
│ GET /api/likes      │
└─────────────────────┘
    │
    ├── TAP item ──▶ Open DetailSheet
    │
    ├── LONG PRESS item ──▶ Toggle select for compare
    │
    ├── Select 2–4 items ──▶ "Compare" button appears
    │   │
    │   └── TAP Compare ──▶ Compare Screen
    │       │
    │       ▼
    │   ┌─────────────────────┐
    │   │   Compare Screen    │
    │   │ Side-by-side cards  │
    │   │ Attribute rows      │
    │   └─────────────────────┘
    │
    └── TAP "Share" ──▶ Create Decision Room Flow
```

### 2.4 Share & Decision Room Flow

```
Likes Screen (with items selected)
    │
    ▼
TAP "Share" button
    │
    ▼
┌─────────────────────────────┐
│ Check: Is user logged in?   │
└─────────────────────────────┘
    │
    ├── Not logged in ──▶ Login/Signup flow
    │   │
    │   └── After auth ──▶ Continue to room creation
    │
    ▼
┌─────────────────────────────┐
│ POST /api/decision-rooms    │
│ { itemIds, title? }         │
└─────────────────────────────┘
    │
    ▼
Response: { id, shareUrl }
    │
    ▼
┌─────────────────────┐
│ Share Sheet (native)│
│ Copy / Message / etc│
└─────────────────────┘
```

### 2.5 View Decision Room Flow

```
External link: /r/:roomId
    │
    ▼
┌─────────────────────────────────┐
│ GET /api/decision-rooms/:roomId │
└─────────────────────────────────┘
    │
    ├── Success ──▶ DecisionRoomScreen
    │              │
    │              ├── View items in grid
    │              │   ├── Item cards with vote counts
    │              │   ├── "Featured" never shown here
    │              │   └── TAP item → DetailSheet
    │              │
    │              ├── View comments section
    │              │
    │              ├── Want to participate? ──▶ Check auth
    │              │   │
    │              │   ├── Not logged in ──▶ Login prompt
    │              │   │
    │              │   └── Logged in ──▶ Enable interactions:
    │              │       ├── VOTE (👍/👎 per item)
    │              │       ├── COMMENT (add to thread)
    │              │       ├── SUGGEST (paste link)
    │              │       └── FINALISTS (creator only)
    │              │
    │              └── If status = "finalists" ──▶
    │                  Show Final 2 comparison view
    │
    └── Error ──▶ "Room not found" message
```

### 2.6 Decision Room Participation Flow

```
Decision Room Screen (logged in)
    │
    ├── VOTE on item ─────────────────────────┐
    │   ├── TAP 👍 or 👎                      │
    │   ├── POST /api/decision-rooms/:id/vote │
    │   ├── Update vote counts in real-time   │
    │   └── Track: decisionroom_vote event    │
    │
    ├── ADD COMMENT ──────────────────────────┐
    │   ├── TAP comment input                 │
    │   ├── Type message                      │
    │   ├── POST /api/decision-rooms/:id/comment
    │   └── Comment appears in thread         │
    │
    ├── SUGGEST ALTERNATIVE ──────────────────┐
    │   ├── TAP "Suggest" button              │
    │   ├── Paste retailer URL                │
    │   ├── POST /api/decision-rooms/:id/suggest
    │   │   └── System extracts product info  │
    │   └── New item appears in room          │
    │
    └── SET FINALISTS (creator only) ─────────┐
        ├── TAP "Pick finalists"              │
        ├── Select 2 items                    │
        ├── POST /api/decision-rooms/:id/finalists
        └── Room enters "Final 2" mode        │
            └── Side-by-side comparison view  │
```

### 2.7 Outbound Redirect Flow

```
DetailSheet → "View on site" button
    │
    ▼
Open: /go/:itemId?sessionId=...&ref=detail
    │
    ▼
┌─────────────────────────────┐
│ Cloud Function: go.ts       │
│ 1. Generate swp_click_id    │
│ 2. Lookup item.outboundUrl  │
│ 3. Log outbound_click event │
│ 4. 302 redirect with:       │
│    - UTM params             │
│    - swp_click_id           │
│    - swp_seg (if available) │
│    - swp_score_band         │
└─────────────────────────────┘
    │
    ▼
Retailer website opens in browser
```

### 2.8 Progressive Onboarding (Gold Cards) Flow

```
User swipes RIGHT on first item
    │
    ▼
┌───────────────────────────────────────┐
│ Check goldCardState.shouldShowVisualCard │
└───────────────────────────────────────┘
    │
    ├── Yes + curatedSofas available ──▶
    │   │
    │   ▼
    │   ┌─────────────────────────────────┐
    │   │   Gold Card Visual (overlay)    │
    │   │   ┌─────────────────────────────┐
    │   │   │ "Pick 3 sofas you love"     │
    │   │   │                             │
    │   │   │ ┌──────┐ ┌──────┐ ┌──────┐ │
    │   │   │ │ Sofa │ │ Sofa │ │ Sofa │ │
    │   │   │ │  1   │ │  2   │ │  3   │ │
    │   │   │ └──────┘ └──────┘ └──────┘ │
    │   │   │ ┌──────┐ ┌──────┐ ┌──────┐ │
    │   │   │ │ Sofa │ │ Sofa │ │ Sofa │ │
    │   │   │ │  4   │ │  5   │ │  6   │ │
    │   │   │ └──────┘ └──────┘ └──────┘ │
    │   │   │                             │
    │   │   │ Selection: 0/3              │
    │   │   │                             │
    │   │   │ Swipe → to submit           │
    │   │   │ Swipe ← to skip             │
    │   │   └─────────────────────────────┘
    │   └─────────────────────────────────┘
    │       │
    │       ├── TAP sofa ──▶ Toggle selection (max 3)
    │       │
    │       ├── SWIPE RIGHT (3 selected) ──▶
    │       │   ├── Track: gold_card_visual_complete
    │       │   ├── POST /api/onboarding/picks
    │       │   ├── Mark visualCompleted = true
    │       │   └── Show budget card (immediately after)
    │       │
    │       └── SWIPE LEFT ──▶
    │           ├── Track: gold_card_visual_skip
    │           ├── Increment visualSkipCount
    │           ├── Record lastSkipSwipe index
    │           └── Return to regular deck
    │
    └── No ──▶ Continue to regular deck

Gold Card Budget (after visual complete)
    │
    ▼
┌─────────────────────────────────┐
│   Gold Card Budget (overlay)    │
│   ┌─────────────────────────────┐
│   │ "What's your budget?"       │
│   │                             │
│   │     Min         Max         │
│   │   0 SEK     50,000 SEK      │
│   │   ●━━━━━━━━━━━●             │
│   │                             │
│   │ Quick picks:                │
│   │ [Under 5k] [5-10k] [10-20k] │
│   │                             │
│   │ Swipe → to submit           │
│   │ Swipe ← to skip             │
│   └─────────────────────────────┘
└─────────────────────────────────┘
    │
    ├── SWIPE RIGHT ──▶
    │   ├── Track: gold_card_budget_complete
    │   ├── Update onboardingPicks with budget
    │   ├── Mark budgetCompleted = true
    │   └── Return to regular deck (with filters applied)
    │
    └── SWIPE LEFT ──▶
        ├── Track: gold_card_budget_skip
        ├── Increment budgetSkipCount
        └── Return to regular deck

Skip Behavior:
    │
    ├── Visual card: Max 2 skips, reappears after 20 swipes
    └── Budget card: Max 2 skips, reappears after 20 swipes
```

### 2.9 Admin Flow

```
/admin
    │
    ▼
┌─────────────────────┐
│ Admin Login Screen  │
└─────────────────────┘
    │
    ├── Google Sign-In ──▶ Check adminAllowlist
    │   │
    │   ├── In list ──▶ /admin/dashboard
    │   └── Not in list ──▶ "Access denied"
    │
    └── Password fallback (legacy) ──▶ /admin/dashboard

Admin Dashboard
    │
    ├── Stats: sessions, swipes, likes, outbound clicks
    │
    ├── Sources ──▶ CRUD sources
    │   │
    │   └── Run Now ──▶ POST /api/admin/run
    │       └── Triggers Supply Engine
    │
    ├── Runs ──▶ View ingestion history
    │
    ├── Items ──▶ Browse items
    │
    ├── QA ──▶ Diagnostics (missing fields, etc.)
    │
    └── Governance ──▶ Manage caps, thresholds
        ├── Featured frequency caps
        ├── Relevance thresholds
        ├── Pacing parameters
        └── Segment definitions
```

### 2.10 Retailer Console Flow

```
/console
    │
    ▼
┌─────────────────────┐
│ Check: Authenticated│
│ as retailer?        │
└─────────────────────┘
    │
    ├── No ──▶ /console/login
    │   │
    │   └── After auth ──▶ /console (Home)
    │
    ▼
┌─────────────────────────────────────┐
│       Console Home (Insights Feed)  │
│                                     │
│  ┌────────────────────────────────┐│
│  │ [Today's Insights]             ││
│  │                                ││
│  │ ┌────────────────────────────┐ ││
│  │ │ 🎯 WINNERS                 │ ││
│  │ │ These 5 SKUs are green...  │ ││
│  │ │ [Boost Budget →]           │ ││
│  │ └────────────────────────────┘ ││
│  │                                ││
│  │ ┌────────────────────────────┐ ││
│  │ │ ⚠️ NEEDS HELP              │ ││
│  │ │ High impressions, low save │ ││
│  │ │ [Pause or Replace →]       │ ││
│  │ └────────────────────────────┘ ││
│  │                                ││
│  │ ┌────────────────────────────┐ ││
│  │ │ 📈 TREND                   │ ││
│  │ │ Bouclé rising in Stockholm │ ││
│  │ │ [Create Campaign →]        │ ││
│  │ └────────────────────────────┘ ││
│  └────────────────────────────────┘│
└─────────────────────────────────────┘
    │
    ├── TAP Insight Card Action ──▶ Relevant screen
    │
    ├── NAV: Campaigns ───────────────────────────┐
    │   │                                         │
    │   ▼                                         │
    │   ┌─────────────────────────────────────┐   │
    │   │ Campaigns List                      │   │
    │   │ ├── Active campaigns (with metrics) │   │
    │   │ ├── Draft campaigns                 │   │
    │   │ └── [+ New Campaign]                │   │
    │   └─────────────────────────────────────┘   │
    │       │                                     │
    │       ├── TAP campaign ──▶ Campaign Detail  │
    │       │   ├── Edit settings                 │
    │       │   ├── View performance              │
    │       │   └── Pause/Resume                  │
    │       │                                     │
    │       └── TAP New Campaign ──▶ Campaign Builder
    │           │
    │           ▼
    │       ┌─────────────────────────────────────┐
    │       │ Campaign Builder                    │
    │       │ 1. Choose segment (template picker) │
    │       │ 2. Select products (manual/auto)    │
    │       │ 3. Set budget + schedule            │
    │       │ 4. Define caps (frequency, share)   │
    │       │ 5. Review preview                   │
    │       │ 6. Launch                           │
    │       └─────────────────────────────────────┘
    │
    ├── NAV: Catalog ─────────────────────────────┐
    │   │                                         │
    │   ▼                                         │
    │   ┌─────────────────────────────────────┐   │
    │   │ Catalog Control                     │   │
    │   │ ├── Product list with scores        │   │
    │   │ │   ├── Score badge (green/yellow/red)│ │
    │   │ │   ├── Reason codes                │   │
    │   │ │   └── Include/Exclude toggle      │   │
    │   │ ├── Creative health warnings        │   │
    │   │ └── Preview as card                 │   │
    │   └─────────────────────────────────────┘   │
    │       │                                     │
    │       └── TAP product ──▶ Product Preview   │
    │           ├── Mobile frame preview          │
    │           ├── Featured insertion preview    │
    │           └── Health checklist              │
    │
    ├── NAV: Trends ──────────────────────────────┐
    │   │                                         │
    │   ▼                                         │
    │   ┌─────────────────────────────────────┐   │
    │   │ Trends Module                       │   │
    │   │ ├── Rising styles/materials/colors  │   │
    │   │ ├── Falling trends                  │   │
    │   │ ├── Price band movements            │   │
    │   │ └── Region selector (v2)            │   │
    │   └─────────────────────────────────────┘   │
    │
    └── NAV: Reports ─────────────────────────────┐
        │                                         │
        ▼                                         │
        ┌─────────────────────────────────────┐   │
        │ Reporting                           │   │
        │ ├── Spend + impressions             │   │
        │ ├── Confidence outcomes             │   │
        │ ├── CPScore (cost per outcome)      │   │
        │ ├── Segment breakdown               │   │
        │ ├── Product breakdown               │   │
        │ ├── [Export CSV]                    │   │
        │ └── [Generate Shareable Link]       │   │
        └─────────────────────────────────────┘
```

---

## 3. Error Handling

| Scenario | User Sees | Recovery |
|----------|-----------|----------|
| Network error loading deck | "Couldn't load sofas" + retry button | TAP retry |
| Session creation fails | Silent retry (3 attempts) | Falls back to local-only mode |
| Swipe API fails | Toast "Couldn't save" | Swipe still animates; retry queued |
| Empty deck | "No more sofas matching your filters" | Clear filters button |
| Shortlist not found | "This shortlist doesn't exist" | Back to deck |
| Room not found | "This room doesn't exist" | Back to deck |
| Auth required | "Log in to participate" | Login button |
| Admin auth fails | "Access denied" message | Sign in with different account |
| Retailer auth fails | "Not authorized for this retailer" | Contact support |

---

## 4. Deep Links

| URL Pattern | Destination | Parameters |
|-------------|-------------|------------|
| `/` | Deck screen | — |
| `/deck` | Deck screen | — |
| `/likes` | Likes screen | — |
| `/compare` | Compare screen | itemIds (state) |
| `/profile` | Profile screen | — |
| `/s/:token` | Shared shortlist | token (path) |
| `/r/:roomId` | Decision Room | roomId (path) |
| `/go/:itemId` | Outbound redirect | sessionId, ref (query) |
| `/admin/*` | Admin screens | — |
| `/console/*` | Retailer Console | — |
| `/auth/login` | Login screen | redirect (query) |
| `/reports/:shareId` | Shared report (public) | shareId (path) |

---

## 5. State Transitions

### Session State

```
┌──────────┐    POST /api/session    ┌───────────┐
│  No ID   │ ───────────────────────▶│  Has ID   │
└──────────┘                          └───────────┘
                                           │
                                           │ (persisted in Hive)
                                           ▼
                                    ┌────────────┐
                                    │ Rehydrated │
                                    │ on launch  │
                                    └────────────┘
                                           │
                                           │ user logs in
                                           ▼
                                    ┌────────────┐
                                    │  Linked to │
                                    │   User     │
                                    └────────────┘
```

### Deck Item Lifecycle

```
┌──────────┐   fetch   ┌──────────┐   swipe   ┌─────────┐
│ Loading  │ ────────▶ │ In Deck  │ ────────▶ │ Removed │
└──────────┘           └──────────┘           └─────────┘
                            │
                            │ tap
                            ▼
                      ┌───────────┐
                      │ Expanded  │
                      │ (Detail)  │
                      └───────────┘
```

### Decision Room State

```
┌──────────┐   create   ┌──────────┐   finalists   ┌───────────┐
│   N/A    │ ─────────▶ │   Open   │ ────────────▶ │ Finalists │
└──────────┘            └──────────┘               └───────────┘
                             │                           │
                             │ (votes, comments)         │ decide
                             ▼                           ▼
                        ┌──────────┐              ┌───────────┐
                        │ Active   │              │  Decided  │
                        │ (ongoing)│              │  (final)  │
                        └──────────┘              └───────────┘
```

### Campaign State

```
┌──────────┐   save    ┌──────────┐   launch   ┌──────────┐
│  (none)  │ ────────▶ │  Draft   │ ─────────▶ │  Active  │
└──────────┘           └──────────┘            └──────────┘
                                                    │
                            ┌───────────────────────┤
                            │                       │
                            ▼                       ▼
                     ┌──────────┐           ┌───────────┐
                     │  Paused  │           │ Completed │
                     └──────────┘           │(end date) │
                            │               └───────────┘
                            │ resume
                            ▼
                     ┌──────────┐
                     │  Active  │
                     └──────────┘
```

---

## 6. Analytics Events by Flow

| Flow | Events Tracked |
|------|----------------|
| First launch | `session_start`, `deck_response` |
| Swipe | `card_impression_start`, `card_impression_end`, `swipe_left` or `swipe_right` |
| Featured swipe | Above + `is_featured`, `campaign_id` |
| Detail view | `detail_open`, `detail_close` |
| Like | `like_add`, `like_remove` |
| Compare | `compare_open` |
| Share | `shortlist_create`, `decisionroom_create` |
| Decision Room | `decisionroom_view`, `decisionroom_join`, `decisionroom_vote`, `decisionroom_comment` |
| Finalists | `finalists_set`, `suggest_alternative` |
| Outbound | `outbound_click` (with `swp_click_id`, `is_featured`) |
| Onboarding | `onboarding_complete` or `onboarding_skip` |
| Gold card visual | `gold_card_visual_shown`, `gold_card_visual_complete`, `gold_card_visual_skip` |
| Gold card budget | `gold_card_budget_shown`, `gold_card_budget_complete`, `gold_card_budget_skip` |
| Filters | `filters_apply` |
| Error | `error` (with errorType, surface) |
| Console | `campaign_create`, `campaign_update`, `campaign_pause`, `report_export` |

---

## References

- [PRD.md](PRD.md) – Product requirements
- [BACKEND_STRUCTURE.md](BACKEND_STRUCTURE.md) – API and data model
- [FRONTEND_GUIDELINES.md](FRONTEND_GUIDELINES.md) – UI patterns
- [COMMERCIAL_STRATEGY.md](COMMERCIAL_STRATEGY.md) – Commercial model

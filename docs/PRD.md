# Swiper – Product Requirements Document

> **Last updated:** 2026-02-05  
> **Status:** MVP Shipped + Phase 8 Complete + Commercial Platform v1 Defined

---

## 1. Product Overview

**Swiper** is a mobile-first furniture discovery app that lets users find their perfect sofa through a Tinder-like swipe experience. Users swipe right on sofas they like, left to dismiss, and build a personalized shortlist to share or compare.

**Commercial Layer:** Retailers pay for featured distribution to targeted user personas, tracked via Confidence Score—a unified metric representing high-intent consideration behavior.

### Target Users

| Persona | Description |
|---------|-------------|
| **Primary** | Millennials/Gen-Z renting or buying first apartments in Sweden |
| **Secondary** | Couples furnishing a shared space |
| **Tertiary** | Interior design enthusiasts browsing for inspiration |

### Retailer Target Audience

| Role | Description |
|------|-------------|
| **Economic Buyer** | Head of Marketing / E-commerce Director / CEO (mid-sized) |
| **Day-to-Day Users** | Performance marketers, merchandisers, agency operators |

### Core Value Proposition (Consumer)

- **Effortless discovery** – No complex filters or endless scrolling; just swipe
- **Personalized** – Learns preferences from swipes to surface better matches
- **Comparison** – Side-by-side compare before deciding
- **Shareable** – Send a shortlist link to get partner approval (Decision Room)

### Core Value Proposition (Retailer)

- **Targeted reach** – Pay to appear to users matching style/budget/size/geo personas
- **Intent metrics** – Confidence Score shows what's working, not vanity metrics
- **Actionable insights** – Console tells you what to do, not just what happened
- **Brand control** – Preview, include/exclude SKUs, creative health warnings

---

## 2. Scope

### 2.1 In Scope (MVP + Commercial v1)

| Feature | Description | Status |
|---------|-------------|--------|
| Anonymous sessions | No signup required; session persists locally | Done |
| Swipe deck | Tinder-like card stack; swipe left/right or tap buttons | Done |
| Preference learning | Right-swipes increase weight for material, color, size, style tags | Done |
| Detail sheet | Tap card to expand; see images, price, dimensions, description | Done |
| Likes list | View all right-swiped/liked items | Done |
| Compare screen | Side-by-side compare 2–4 items | Done |
| Shared shortlist | Create shareable link `/s/:token` | Done |
| Outbound redirect | `/go/:itemId` logs click + redirects to retailer with UTM | Done |
| Onboarding | Optional style/budget preferences to seed weights | Done |
| Progressive onboarding | Gold cards in deck for visual pick + budget collection | Done |
| Collaborative filtering | Persona signals from similar users | Done |
| Filters | Size class, color family, condition | Done |
| Admin panel | Manage sources, trigger ingestion, view stats, QA diagnostics | Done |
| Feed ingestion | CSV/JSON feeds normalized to Firestore items | Done |
| Crawl ingestion | Sitemap/category discovery, extraction cascade, drift monitoring | Done |
| Recommendation engine | PreferenceWeightsRanker with exploration | Done |
| Event tracking | V1 schema, batched, opt-out support | Done |
| Privacy controls | Analytics opt-out, data export/delete stubs | Done |
| Locale | English + Swedish toggle | Done |
| **Decision Room** | Vote, comment, finalists, suggest alternatives on shared lists | v1 |
| **User accounts** | Required to create Decision Room; optional otherwise | v1 |
| **Featured Distribution** | Paid product placement with targeting, caps, labels | v1 |
| **Retailer Console** | Insights Feed, Campaigns, Catalog, Trends, Reporting | v1 |
| **Confidence Score** | Per-product/segment intent metric (0–100) | v1 |
| **Premium image rendering** | Contain + blurred background; CDN variants | v1 |

### 2.2 Out of Scope (Explicit Non-Goals)

| Feature | Reason |
|---------|--------|
| AR preview | Complex; deferred post-MVP |
| Payments/checkout | Affiliate model only |
| Messaging/escrow | Not a marketplace |
| Multi-category | Sofas only for focus |
| User-submitted links | Compliance risk; organization-defined sources only |
| Heavy retailer integrations | No inventory, delivery ETA, postcode availability in v1 |
| Paid placement in Decision Room | Preserves user trust |

---

## 3. User Stories

### 3.1 Discovery (Consumer)

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-1 | As a user, I want to launch into the deck immediately so I can start browsing | App opens to deck screen; onboarding is optional |
| US-2 | As a user, I want to swipe right on sofas I like | Right swipe adds to likes, updates preference weights, card exits right |
| US-3 | As a user, I want to swipe left to dismiss | Left swipe dismisses, card exits left, no weight update |
| US-4 | As a user, I want to tap a card to see details | Tap opens detail sheet with images, price, dimensions, description |
| US-5 | As a user, I want to filter by size, color, condition | Filter sheet; deck refreshes with matching items |
| US-6 | As a user, I can see when a product is "Featured" | Featured label clearly visible, distinct from organic |

### 3.2 Shortlist & Compare (Consumer)

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-7 | As a user, I want to view my liked items | Likes screen shows all right-swiped items |
| US-8 | As a user, I want to compare 2–4 items side by side | Compare screen with attribute rows; navigate from likes |
| US-9 | As a user, I want to share my shortlist with a link | Create shortlist generates Decision Room link |

### 3.3 Decision Room (Consumer)

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-10 | As a user, I need an account to create a Decision Room | Account creation/login flow before room creation |
| US-11 | As a user, I can view a Decision Room without login | Public link shows items; participation requires login |
| US-12 | As a user, I want to vote on items in a Decision Room | Vote per product (👍/👎); votes visible to all participants |
| US-13 | As a user, I want to comment on a Decision Room | List-level comment thread; all participants see comments |
| US-14 | As a user, I want to pick finalists ("Final 2" mode) | Narrow to 2 finalists; gamified comparison |
| US-15 | As a user, I want to suggest an alternative | Paste link → added to room as a candidate |

### 3.4 Outbound

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-16 | As a user, I want to go to the retailer site | "Buy now" opens `/go/:itemId`; redirects to retailer with UTM + click_id |

### 3.5 Preferences & Privacy

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-17 | As a user, I want to set style preferences upfront | Onboarding: select styles, budget; seeds preference weights |
| US-18 | As a user, I want to opt out of analytics | Data & Privacy toggle; only essential events logged |
| US-19 | As a user, I want to switch language | Profile → Language → English/Swedish |

### 3.6 Admin

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-20 | As an admin, I want to add/edit sources | Admin → Sources → Create/Edit source |
| US-21 | As an admin, I want to trigger ingestion | Admin → Runs → Run Now for a source |
| US-22 | As an admin, I want to see QA diagnostics | Admin → QA → Missing fields report |
| US-23 | As an admin, I want to manage featured frequency caps | Admin → Governance → Cap settings |

### 3.7 Retailer Console

| ID | Story | Acceptance Criteria |
|----|-------|---------------------|
| US-30 | As a retailer, I want to see actionable insights | Insights Feed shows "what to do today" cards |
| US-31 | As a retailer, I want to create a featured campaign | Campaign builder: segment + products + budget + schedule |
| US-32 | As a retailer, I want to control my catalog | Include/exclude SKUs, preview as card, see health warnings |
| US-33 | As a retailer, I want to see Confidence Scores | Per-product scores with color bands + reason codes |
| US-34 | As a retailer, I want to export reports | CSV export + sharable report links (agency-friendly) |
| US-35 | As a retailer, I want to see regional trends | Trends module with Sweden → city → postcode tiers |

---

## 4. Success Criteria

### Consumer Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Likes per session** | ≥3 | Average likes per unique session |
| **Outbound CTR** | ≥5% | Outbound clicks / deck impressions |
| **Shortlist share rate** | ≥10% | Sessions with ≥1 share / total sessions |
| **Deck completion rate** | ≥50% | Sessions that swipe ≥10 items / total |
| **Decision Room participation** | ≥30% | Rooms with ≥2 participants / rooms created |

### Supply Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Extraction success rate** | ≥80% | Successful extractions / crawl attempts |
| **Avg completeness score** | ≥0.7 | Average NormalizedProduct.completeness_score |

### Commercial Metrics (v1)

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Retailer activation** | ≥5 | Retailers running ≥1 campaign |
| **Campaign fill rate** | ≥80% | Featured slots filled / available |
| **CPScore benchmark** | Track | Cost per Confidence Score outcome (no target yet) |

---

## 5. Feature Specifications

### 5.1 Swipe Deck

- **Stack size:** 5 visible cards (top + 4 peeking)
- **Swipe threshold:** 100px horizontal drag or velocity ≥800px/s
- **Exit animation:** 200–260ms to edge
- **Commit timing:** API call + event log on swipe start; card removed after animation
- **Refetch:** When ≤3 items remain, background fetch next batch
- **Empty state:** "No more sofas" with refresh button
- **Featured insertion:** Max 1 in 12 cards, labeled, relevance-gated

### 5.2 Recommendation Engine

- **Algorithm:** PreferenceWeightsRanker (content-based) + PersonalPlusPersonaRanker (collaborative)
- **Signals:** styleTags, material, colorFamily, sizeClass
- **Exploration:** Configurable rate (0–10%) samples from top-2×limit pool
- **Personalization:** Weights updated atomically on right-swipe
- **Variant assignment:** Deterministic hash(sessionId) % 100
- **Cold-start:** Onboarding picks boost matching attributes in deck
- **Featured ranking:** Eligible campaigns ranked by expected incremental intent

### 5.3 Progressive Onboarding (Gold Cards)

- **Visual card:** 2×3 grid of curated sofa images; user picks 3 favorites
- **Budget card:** Range slider (0–50,000 SEK) with quick-select chips
- **Trigger:** After first right-swipe (configurable)
- **Skip behavior:** Card reappears after 20 swipes (max 2 skips)
- **Styling:** Gold gradient border, distinct background, swipeable
- **Data storage:** Picks stored in `onboardingPicks` collection with extracted attributes

### 5.4 Decision Room

- **Creation:** Account required; generates unique room URL
- **Viewing:** Public (no login required)
- **Participation:** Login required to vote/comment/suggest
- **Features:**
  - Vote per product (👍/👎)
  - Comment thread (list-level)
  - "Final 2" mode (compare finalists)
  - "Suggest alternative" (paste link → added as candidate)
- **Monetization:** Always ad-free (trust boundary)

### 5.5 Featured Distribution

- **Label:** "Featured" badge always visible
- **Frequency cap:** Max 1 in 12 cards per session (configurable)
- **Relevance gate:** Only when segment match score > threshold
- **Diversity:** Avoid same retailer repeatedly
- **Campaign object:** Target segment + product set + budget + schedule + guardrails

### 5.6 Confidence Score

- **Range:** 0–100 per product × segment × time window
- **Inputs:** Saves, shares, compares, returns, dwell, optional clicks
- **Smoothing:** Bayesian prior to prevent small-sample noise
- **Bands:** Green (≥75), Yellow (45–74), Red (<45)
- **Reason codes:** Top 2–3 "why" tags per score

### 5.7 Crawl Ingestion

- **Discovery:** Sitemaps (robots.txt → sitemap XML) or category BFS crawl
- **Extraction cascade:** JSON-LD → embedded JSON → recipe → DOM
- **Extracted fields:** title, canonicalUrl, price, images, brand, description, dimensions, material, color
- **Normalization:** Map to TAG_TAXONOMY (sizeClass from width, colorFamily, material)
- **Monitoring:** Daily metrics, drift detection (success rate, completeness)
- **Compliance:** Allowlist only, robots.txt respected, rate limited

---

## 6. Constraints & Assumptions

| Constraint | Detail |
|------------|--------|
| **Geography** | Sweden-first; SEK pricing |
| **Category** | Sofas only (MVP) |
| **Sources** | Organization-defined only; no user submissions |
| **Auth** | Anonymous sessions default; account required for Decision Room creation |
| **Crawl** | Static HTML only; no JS rendering |
| **LLM** | Optional; extraction works without LLM |
| **Paid placement** | Never in Decision Room |

---

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Site blocks bot | No data | Respect robots.txt, use polite User-Agent, allowlist only |
| SPA with no SSR | Extraction fails | Prioritize JSON-LD; add per-site recipes; consider Puppeteer later |
| Cold start (no swipes) | Poor recommendations | Seed from onboarding; global popularity fallback |
| Exposure bias | Filter bubble | Exploration sampling; diversity re-ranking (future) |
| Featured fatigue | User trust erosion | Strict caps, relevance gates, clear labeling |
| Low retailer adoption | No revenue | Focus on value props, easy onboarding, proof of intent |

---

## 8. Glossary

| Term | Definition |
|------|------------|
| **Deck** | The swipeable card stack |
| **Item** | A normalized product (sofa) in Firestore |
| **Source** | A data source (feed URL or crawl config) |
| **Recipe** | Per-retailer extraction mapping (JSONPath/DOM selectors) |
| **Completeness score** | 0–1 score based on extracted field coverage |
| **Preference weights** | Per-session attribute weights from swipes |
| **Decision Room** | Shared page for voting/commenting on a shortlist |
| **Confidence Score** | 0–100 metric of high-intent consideration per product/segment |
| **Featured** | Paid product placement (labeled, capped, relevance-gated) |
| **Segment** | Targeting definition (style + budget + size + geo) |

---

## 9. References

- [ARCHITECTURE.md](ARCHITECTURE.md) – System architecture
- [BACKEND_STRUCTURE.md](BACKEND_STRUCTURE.md) – Firestore schema, API, Confidence Score spec
- [COMMERCIAL_STRATEGY.md](COMMERCIAL_STRATEGY.md) – Commercial model and roadmap
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) – Build sequence
- [APP_FLOW.md](APP_FLOW.md) – User flows and screens
- [FRONTEND_GUIDELINES.md](FRONTEND_GUIDELINES.md) – UI patterns

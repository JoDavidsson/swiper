# Swiper Commercial Strategy

> **Last updated:** 2026-02-05  
> **Status:** Strategic Framework — Build Spec v1 → v2  
> **Authors:** Executive roundtable (CRO/CPO perspectives)

---

## One-Line Positioning

**Swiper is a targeted discovery + intent platform for furniture retailers:** users swipe to discover sofas and inspiration; retailers pay to appear more often to the right personas, generate high-intent saves, and convert that intent into downstream purchases via measurement and re-engagement—without corrupting the user's decision flow.

---

## 0. Product North Star

### What Swiper Sells (Honest Value Props for Furniture Retailers)

Retailers pay for:

- **More appearances** to users who match a target persona (**style + budget + size constraints + geo**)
- More **high-intent consideration behaviors** (saves, shortlists, shares, comparisons)
- Optional (later): **creative testing** / creative diagnostics to improve those behaviors
- Optional (v2): **Pixel + audience retargeting** to connect Swiper intent to retailer site outcomes

### Non-Negotiables (Trust)

- **No paid placement** inside the **Decision Room** (share/compare/finalize)
- "Featured" in decks is **clearly labeled**, **frequency capped**, and **relevance gated**
- No heavy retailer integrations (inventory, delivery ETA, postcode availability, etc.) in v1

---

## 1. Retailer Target Audience

### Economic Buyer (Who Signs)

| Role | Description |
|------|-------------|
| **Head of Marketing / Growth** | Primary budget holder for acquisition channels |
| **E-commerce Director / C-Ecom Officer** | Owns digital conversion + customer acquisition |
| **CEO/Founder** | Common in mid-sized retailers |

### Day-to-Day Users

| Role | Responsibilities |
|------|-----------------|
| **Performance marketer** | Runs budgets and campaigns |
| **Merchandiser / Category manager** | Chooses products, priorities, assortment gaps |
| **Agency operators** | Need sharable reporting and repeatable workflows |

### "Jobs to Be Done" (Retailer Language)

- "I want qualified discovery for my sofas without paying for junk clicks."
- "I want to push collections/hero SKUs to the right shoppers."
- "I need to see what's working and what to do next—fast."
- "I need brand control: image quality, which SKUs appear, how we look."

---

## 2. What We Sell (Core Commercial Offerings)

### A. Featured Distribution in the Product Deck (Core Revenue)

**What it is:**  
Retailers pay to have their products weighted higher (shown more frequently) to users who match a target persona.

**Targeting ("persona") includes:**

- Style signals (e.g., Japandi / Scandinavian minimal / classic)
- Budget band
- Size constraints (2-seater / 3-seater / depth/width preference inferred)
- Geo (Sweden-wide → region → city → postcode clusters over time)

**How it stays honest & user-safe:**

- Clearly labeled "Featured"
- Frequency capped (e.g., max 1 in 12 cards)
- Relevance-gated (only eligible when match score > threshold)
- Diversity constraint (avoid showing same retailer repeatedly)
- No paid placement inside the Decision Room (share/compare/finalize stays clean)

**What retailers get (outcomes):**

- More appearances in the exact segments they care about
- More Confidence Score actions (saves, shares, compares)
- Campaign control + reporting (via the Retailer Console)

---

### B. Sponsored Themes in the Inspiration Deck (Medium-term Revenue — v3)

**What it is:**  
Retailers sponsor inspiration experiences, not decision outcomes.

**Examples:**

- "Own 'Bouclé & Scandinavian Minimal' for a weekend"
- "New collection launch takeover"
- "Inspiration for YOU" themed decks, curated to user taste

**Why it works:**  
Inspiration behaves like Pinterest: it's high-retention, high-sharing, and brand-friendly. Sponsorship feels native and doesn't pressure purchase decisions.

---

### C. Retailer Console (Subscription Floor)

**What it is:**  
A retailer dashboard that is not "analytics," but an **actionable Insights Feed + campaign tools**.

**Principle:** If it looks like analytics, it dies. It must feel like:
- "Here's what to do today."
- "Here's what's winning this week."

The Console is the recurring value layer that makes Featured Distribution sticky, measurable, and repeatable.

---

### D. Swiper Pixel + Audience Retargeting (v2 Add-on + Close-Rate Engine)

**What it is:**  
A lightweight tracking + audience layer that connects Swiper intent to retailer website outcomes.

**How it works:**

1. When Swiper sends a user to retailer site, append `swp_click_id=...` and `swp_seg=...` to URL
2. Retailer adds Swiper Pixel (small script) to their site:
   - Reads the click id param
   - Stores first-party cookie on retailer domain
   - Sends event back to Swiper to connect sessions/conversions
3. Swiper builds intent audiences and enables:
   - DIY mode: Pixel sets `swp_seg` cookie; retailer uses GTM to map to Meta/Google audiences
   - Enriched remarketing: Swiper Pixel emits custom events into retailer ad tags

**Important commercial reason:**  
This is the cleanest answer to: *"How does Swiper intent help me increase close rate?"*  
Because we turn upstream preference into downstream conversion pressure and measurement.

---

### E. Lifecycle Messaging (Push included; Email/SMS are paid add-ons — v2/v3)

**Principle:** Push is our retention service to bring users back into Swiper.

Retailers can pay to "insert" themselves into intent only in contexts that help the user (not in the Decision Room).

**Examples of "decision nudges" that increase conversion momentum:**

- "You have 3 finalists—want to vote with your partner?"
- "Based on your style, here are new matches"
- "Your shortlist is ready—compare top 3"

**Commercial packaging:**

| Channel | Model |
|---------|-------|
| Push | Included (supports product retention + repeat sessions) |
| Email | Paid add-on (volume based) — v2/v3 |
| SMS | Paid add-on (volume based) — v2/v3 |

This is monetizable because it's tied to measurable outcomes (Confidence Score → return session → clickout → conversion).

---

### F. Affiliate Revenue (Background / Incremental)

Affiliate remains a bonus stream:

- It validates intent quality
- It adds incremental revenue
- But it is **not the core engine** due to attribution and long purchase cycles

---

## 3. The Core Metric: Confidence Score (0–100)

We replace "HIS" terminology in UI with **Confidence Score** because it's more intuitive and operational for retailers.

### What the Score Represents

**Confidence Score (0–100)** = "How strongly users are showing *high-intent consideration* for this product (in a given segment), based on observed behaviors."

### Why This is Better Than Exposing HIS Directly

- Retailers don't want an event definition—they want a **decision tool**
- A single score supports:
  - Campaign optimization
  - Merchandising choices
  - "Boost vs test vs pause" guidance

### UI Presentation

- Show per product: **Score: 94.3 / 100**
- Color bands:
  - **Green (≥75):** Spend/boost
  - **Yellow (45–74):** Has promise; test/iterate
  - **Red (<45):** Reevaluate (creative, price, mismatch, or low fit)

**Tooltip (simple):**
> "Confidence Score is based on saves plus additional high-intent signals like return visits, sharing, comparing, and time spent."

**Important:** Show **Data Volume** (e.g., "Based on 3,240 impressions") and "Low data" badge when below threshold.

### Reason Codes (to Make Score Actionable)

Every score should have top 2–3 "why" tags:

- "Strong saves"
- "High share rate"
- "High return sessions"
- "Low saves despite impressions"
- "Segment mismatch"
- "Creative health issues"
- "Price band mismatch" (if inferred)

These reason codes power Insights Feed actions.

### Commercial KPI

```
Cost per Confidence Score outcome (CPScore) = Campaign spend / High-confidence outcomes generated
```

This becomes your "new CPC," but closer to purchase.

---

## 4. Core Surfaces and Flows

### 4.1 Consumer Surfaces (Generate Intent)

We operate two deck types (Product now; Inspiration later):

#### A) Product Deck (v1)

- Swipeable sofa cards
- Save to shortlist/board
- Share → creates a Decision Room

#### B) Inspiration Deck (v3)

- Swipe/save themes, rooms, moods (Pinterest-like retention loop)
- "Shop this vibe" bridges to Product Deck
- Monetization later via **Sponsored Themes** (not required for v1)

#### C) Decision Room (Share Page) — Always Ad-Free

**Rules:**
- Must have an account to **create** a room
- Anyone can **view** a room without login
- To **participate** (vote/comment/suggest/save), login required

**MVP Features:**
- Vote per product (👍/👎 or ❤️/😬)
- Comment thread (list-level; optional per-item later)
- "Final 2" mode (compare finalists; simple gamification)
- "Suggest alternative" (paste link → added to room as a candidate)

> Decision Room is also a key measurement surface (high concentration of intent + social validation).

### 4.2 Retailer Surfaces (Where We Earn)

#### Retailer Console Information Architecture

1. **Home: Insights Feed** (Instagram-like feed of actionable insights)
2. **Campaigns** (builder + pacing + results)
3. **Catalog** (product control + preview + creative health)
4. **Trends** (Sweden → region/city/postcode as tiers)
5. **Reporting** (stats, exports, sharable links)

---

## 5. What We Explicitly Do NOT Rely On (By Design)

| Exclusion | Reason |
|-----------|--------|
| "Request offer" as primary monetization | Not natural for mainstream sofa retail |
| Heavy retailer integrations | Inventory, back-in-stock, delivery ETA, postcode availability add complexity |
| Selling influence in decision/compare/finalize surface | Preserves user trust |

---

## 6. Commercial Packaging (Retailer Webpage)

> This is not a pricing page; it's a "what you get + book a meeting" page.

### Offer Structure: Subscription + Campaign Budgets + Add-ons

#### 1. Featured Distribution (Product Deck)

- Persona targeting (style/budget/size/geo)
- Frequency caps + sponsored label
- Campaign control + reporting
- **Primary KPI:** CPScore (Cost per Confidence Score outcome)

#### 2. Retailer Console

- Insights Feed ("what to do today")
- Trends (Sweden → city → postcode tiers)
- Product performance + recommendations
- Daily findings

#### 3. Sponsored Themes (Inspiration Deck) — *v3*

- Theme ownership
- Promoted inspiration (native)
- Launch campaigns for new collections

#### 4. Swiper Pixel + Audiences — *v2 Add-on*

- Onsite event tracking (lightweight)
- Audience creation from Swiper intent
- Sync to ad platforms or managed retargeting packages

#### 5. Lifecycle Messaging — *v2/v3 Add-on*

- Push included (retention)
- Email/SMS packs (activation tied to intent outcomes)

#### 6. Affiliate — *Incremental*

- Background revenue + validation signal

---

## 7. Roadmap Framing

### v1 — Monetizable MVP (Sofas, Sweden)

**Consumer:**
- Product Deck (swipe, save)
- Account required to create Decision Room
- Decision Room: view, login-to-interact (vote/comment/final2/suggest link)
- Push nudges (basic)

**Retailer:**
- Claim retailer + catalog surfaced from crawl
- Catalog control (include/exclude; preview)
- Featured campaigns (segment templates + product sets + budget)
- Insights Feed v1 + Reporting centered on Confidence Score

**Trust/Quality:**
- Premium image rendering (contain + blurred bg)
- CDN image caching + multi-size variants

### v2 — Close-Rate Proof + Bigger Budgets

- Swiper Pixel + click-id attribution
- Conversion reporting in console
- Audience tools (DIY cookie segmentation + custom events)
- Better pacing + frequency/fatigue controls
- Geo granularity tiers (region/city/postcode clusters)

### v3 — Retention Engine + New Monetization

- Inspiration Deck + boards
- Sponsored Themes (in Inspiration Deck)
- Email/SMS packs
- Creative Health Score surfacing as a formal module

### v4 — Creative Lab (Optional)

- Image/inspiration A/B testing
- AI creative scoring + recommendations

---

## 8. Retailer-Facing Pitch (Copy You Can Use)

> **"Swiper helps furniture retailers reach the right shoppers earlier."**
>
> Users swipe to discover sofas and save what they seriously consider. Retailers pay to appear more often to the personas they want, measure cost per high-intent outcome (Confidence Score), and optionally retarget those intent audiences to convert on their own site. Decision-making remains unbiased: we don't sell placements in the share/compare room.

---

## 9. Definition of "Done" for v1

We can invoice retailers when we can deliver:

- Featured campaigns that reliably increase appearances to targeted segments
- A retailer console that tells them what to do (Insights Feed) and lets them do it (Campaign Builder)
- Confidence Score per product/segment with reason tags and data volume
- Brand trust: clean image rendering + catalog preview + instant exclude controls
- Decision Room built as the growth/identity/intent concentration surface (ad-free)

---

## References

- [PRD.md](PRD.md) – Product requirements
- [APP_FLOW.md](APP_FLOW.md) – Screens and navigation
- [BACKEND_STRUCTURE.md](BACKEND_STRUCTURE.md) – Database, API, and Confidence Score spec
- [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) – Build sequence
- [FRONTEND_GUIDELINES.md](FRONTEND_GUIDELINES.md) – UI patterns including image display

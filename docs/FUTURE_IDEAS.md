# Future Ideas

A collection of feature ideas for future development phases.

---

## 1. "Find Similar but Cheaper"

**Status:** Idea  
**Added:** 2026-02-05

### Concept
When a user likes a product but finds it too expensive, allow them to request similar alternatives at a lower price point.

### User Flow
1. User sees a product they like
2. User taps a "Like but too expensive" action (or long-press / secondary action)
3. System finds visually and stylistically similar items below the liked item's price
4. Results are injected into the deck or shown as a mini-collection

### Technical Considerations
- Requires similarity scoring based on:
  - `styleTags` overlap
  - `colorFamily` match
  - `material` match
  - Visual embedding similarity (future: ML-based)
- Price filter: `priceAmount < likedItem.priceAmount`
- Could weight results by price discount percentage
- Consider caching similarity scores for common items

### UX Options
- **Option A:** Third swipe direction (swipe down = "like but cheaper")
- **Option B:** Button overlay on card ("Find cheaper")
- **Option C:** Long-press context menu
- **Option D:** Post-like prompt ("Too pricey? Find similar for less")

### Success Metrics
- Conversion rate on "cheaper similar" suggestions
- User retention after using feature
- Price sensitivity insights for recommendation tuning

---

## 2. MCP/AI Reconnaissance for Smart Crawling

**Status:** Idea  
**Added:** 2026-02-05

### Problem
When setting up a crawl source, users currently need to know the retailer's URL structure to specify which categories to scrape. Entering just `mio.se` without a category path results in scraping everything (tables, beds, sofas, etc.) instead of just sofas.

### Concept
A two-phase crawl system where an AI/MCP first analyzes the site structure, identifies relevant category paths, and then the crawler uses those paths for focused ingestion.

### Proposed Flow
1. **Phase 1: Site Mapping (Reconnaissance)**
   - Fetch homepage and navigation structure
   - Extract menu items, category links, breadcrumbs
   - Send structure to LLM: "Identify all URL patterns for sofas"
   - LLM returns patterns: `["soffor", "soffa-", "hornsoffa", "divansoffa"]`
   - Store in source config as `derived.categoryPatterns`

2. **Phase 2: Filtered Crawl**
   - Fetch sitemap or crawl site
   - Apply AI-derived patterns to filter URLs
   - Only process pages matching sofa patterns

### Example LLM Prompt
```
Given this furniture retailer's navigation structure:
- /soffor (Sofas) 
- /bord (Tables)
- /stolar (Chairs)
- /sangar (Beds)
- /soffor/hornsoffor (Corner Sofas)
- /soffor/divansoffor (Divan Sofas)

Identify all URL path patterns that correspond to "sofas" (including subcategories).
Return as JSON array: ["soffor", "hornsoffor", "divansoffor"]
```

### Technical Considerations
- Could use Claude, GPT-4, or local model
- Navigation extraction via BeautifulSoup (already available)
- Cache reconnaissance results per domain
- Consider cost/latency tradeoff vs manual configuration
- MCP server integration for tool-based approach

### Benefits
- Zero configuration for users - just paste domain
- Handles any site structure automatically
- Adapts to different languages (Swedish: soffor, English: sofas)
- Can detect category reorganizations on re-crawl

### Success Metrics
- Reduction in "wrong category" ingestion errors
- Time-to-first-run for new sources
- User satisfaction with automated setup

---

## 3. Recommendation Quality Approval Gate (Non-Code)

**Status:** Idea  
**Added:** 2026-02-10

### Problem
Ranking changes can feel better in isolated sessions but still regress user trust over time. We need a repeatable, product-level approval process that does not depend on hardcoded one-off logic.

### Concept
Introduce a formal quality gate for recommendation changes, approved by product and engineering leadership using live observability metrics over a fixed window.

### Proposed Flow
1. Enable a ranking or policy change behind config/env toggles.
2. Run a 2-3 day observation window on real traffic.
3. Review quality gate metrics in a shared dashboard.
4. Approve rollout only if all guardrails pass.
5. If guardrails fail, roll back config and document failure reason.

### Approval Guardrails (v1)
- Median `sourceDiversityTop8 >= 3`
- `p90 sourceConcentrationTop8 <= 0.625`
- Repeated model in top 12 appears in <10% of decks
- No regression in `swipe_right` rate and outbound click-through

### Operating Model
- Decision owners: CPO + CTO
- Cadence: Weekly recommendation quality review
- Change control: Config-first rollout, code changes only when repeatedly justified by data
- Output artifact: One short approval note per rollout decision

### Benefits
- Keeps polish mode disciplined without panic changes
- Separates experimentation from permanent product behavior
- Creates shared product + engineering accountability for recommendation quality

### Success Metrics
- Fewer recommendation regressions after rollout
- Faster approval cycle for safe ranking improvements
- Higher consistency in exploration quality across sessions

---

*Add new ideas below using the same format*

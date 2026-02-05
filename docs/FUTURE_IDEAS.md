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

*Add new ideas below using the same format*

# Documentation Consistency Check (Phase 12.3-12.11)

Date: 2026-02-08  
Scope: Featured distribution completion docs sync

## Reviewed Files

- `docs/IMPLEMENTATION_PLAN.md`
- `docs/BACKEND_STRUCTURE.md`
- `docs/RECOMMENDATIONS_ENGINE.md`
- `CHANGELOG.md`

## Consistency Findings and Fixes

1. Phase status mismatch:
- Found: Phase 12.3-12.11 still marked pending.
- Fixed: Marked 12.3-12.11 as `✅ Done` in `docs/IMPLEMENTATION_PLAN.md`.

2. Campaign schema drift:
- Found: Missing documented fields used by implementation (`recommendedProductIds`, daily spend/impression maps, `recommendedAt`, `featuredImpressions`, `createdBy`, `lastImpressionAt`).
- Fixed: Updated campaign schema table in `docs/BACKEND_STRUCTURE.md`.

3. Featured impression logging schema missing:
- Found: No explicit collection contract for `featuredImpressions`.
- Fixed: Added `2.13a featuredImpressions` schema section in `docs/BACKEND_STRUCTURE.md`.

4. Retailer campaign API drift:
- Found: Missing documentation for campaign recommendation endpoint and activation route semantics.
- Fixed: Added `POST /retailer/campaigns/{id}/recommend` and activation/update notes in `docs/BACKEND_STRUCTURE.md`.

5. Deck response metadata drift:
- Found: `rank.featuredServing` and featured card payload fields not documented.
- Fixed: Updated deck response example in `docs/BACKEND_STRUCTURE.md`.

6. Recommendation engine behavior drift:
- Found: Doc only reflected segment gate; implementation also includes product-mode, budget/schedule, pacing, slotting, and impression logging.
- Fixed: Updated featured distribution behavior in `docs/RECOMMENDATIONS_ENGINE.md`.

7. Score schema naming drift:
- Found: Docs used `window`, implementation/API uses `timeWindow`.
- Fixed: Updated field name to `timeWindow` in `docs/BACKEND_STRUCTURE.md`.

## Validation Commands

Executed against `firebase/functions`:

```bash
npm run build
npm test -- --runInBand
```

Result: both passed.

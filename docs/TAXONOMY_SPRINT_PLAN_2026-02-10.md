# Taxonomy Sprint Plan (2026-02-10)

## Goal

Operationalize the new hierarchical + orthogonal taxonomy end-to-end:

- `primaryCategory` (single)
- `sofaTypeShape` (single)
- `sofaFunction` (single)
- `seatCountBucket` (single, optional)
- `environment` (single, internal `unknown`)
- `roomTypes` / `styleTags` (multi)

## Scope

### Stream A: Runtime Loop Closure (P0)

1. Consume `categorizationTrainingConfig/latest` during live classify/eligibility.
2. Support `CATEGORIZATION_TRAINING_RULES_MODE`:
   - `off`: ignore rules
   - `shadow`: evaluate + log diagnostics, no decision change
   - `active`: enforce rules in eligibility outcomes
3. Add response/diagnostic counters to classify pipelines.

### Stream B: Review Lab/Product Flow (P0/P1)

1. Separate modes in admin UI:
   - Operations review (queue decisions affect Gold/ReviewQueue)
   - Training labeling (labels only, no queue/gold mutation)
2. Improve sampling:
   - Larger paginated scan (remove fixed `limit(1000)` bias)
   - Better multiclass uncertainty ranking
   - Surface per-item sampling reason (primary/near_miss/backfill)
3. Tighten label quality:
   - Require explicit `labelCategory` unless legacy fallback flag enabled
   - Add holdout evaluation metrics and go/no-go status in train output

### Stream C: Consumer Taxonomy Adoption

1. Move deck filters from `subCategory` dependency to taxonomy axes.
2. Keep backward compatibility for existing `subCategory` filter calls.
3. Show taxonomy chips in detail UI (and hide `environment=unknown`).

### Stream D: Retailer Taxonomy Adoption

1. Include taxonomy fields in retailer catalog API rows.
2. Render taxonomy context in retailer catalog UI to support campaign decisions.

### Stream E: Documentation Alignment

Update core docs to match shipped behavior and contracts:

- `docs/TAG_TAXONOMY.md`
- `docs/BACKEND_STRUCTURE.md`
- `docs/DATA_MODEL.md`
- `docs/RECOMMENDATIONS_ENGINE.md`
- `docs/EVENT_SCHEMA_V1.md`
- `docs/EVENT_TRACKING.md`
- `docs/IMPLEMENTATION_PLAN.md`

## Non-goals (this sprint)

1. Full model retraining platform.
2. New learned classifier architecture.
3. Complete legacy field removal (`predictedCategory`, `subCategory`) before migration completion.

## Rollout Strategy

1. Ship runtime rule consumption in `shadow`.
2. Validate diagnostics + holdout metrics.
3. Enable `active` in controlled environments.
4. Keep compatibility reads from `classification.predictedCategory` and `subCategory` during migration.

## Acceptance Criteria

1. Training config materially influences runtime when mode is `active`.
2. Review Lab training labels no longer mutate queue/gold decisions.
3. Sampling API returns unbiased larger candidate scan and reason metadata.
4. Consumer deck supports new taxonomy filters and uses them in candidate filtering.
5. Retailer catalog surfaces taxonomy fields.
6. Docs reflect current behavior and flags without contradictory legacy statements.

## Risks and Mitigations

1. Over-rejection from aggressive rules:
   - Mitigation: default `shadow`, require holdout gate signals before `active`.
2. Filter fragmentation during migration:
   - Mitigation: dual support for old and new filter keys.
3. Label drift from legacy records:
   - Mitigation: explicit-category requirement by default.


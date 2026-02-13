# Skill Invocation Style (Hybrid: Specialist + Swiper Adapter)

## Goal
Use general specialists for reasoning quality and Swiper adapters for repo-specific execution.

## Preferred invocation pattern
Use this exact structure:

`Use $<specialist-skill> + $<swiper-adapter-skill> to <outcome>.`

Examples:
- `Use $recommender-offline-evaluation-specialist + $swiper-recommendation-eval-analyst to compute liked-in-top-K by variant for the last 7 days and flag regressions.`
- `Use $release-qa-specialist + $swiper-release-qa-runner to run full pre-release checks and give go/no-go.`

## Routing rule
1. Swiper repo task: invoke the pair (specialist + adapter).
2. Non-Swiper or cross-repo task: invoke only the specialist.
3. Fast ops with clear repo contracts: adapter can run alone, but pair is preferred.

## Trigger wording standard
Use this style when editing skill descriptions in the future:

- Specialist skills:
  - Start with: `Cross-project specialist for ...`
  - Include: `Use when tasks involve ...`
  - Avoid Swiper-only terms.

- Swiper adapter skills:
  - Start with: `Swiper-specific operator for ...`
  - Include exact surfaces: scripts, endpoints, collections, and docs.
  - Include: `Use in this repository when ...`

## Default prompt standard
Each skill `agents/openai.yaml` should use one sentence and include `$skill-name`.

- Specialist template:
  - `Use $<specialist> to <perform domain task> in a reusable, cross-project way.`

- Swiper adapter template:
  - `Use $<adapter> with $<specialist> to <achieve Swiper outcome> using repo runbooks and scripts.`

## Pair map (authoritative)
1. `$local-dev-stack-specialist` + `$swiper-local-stack-operator`
2. `$ingestion-operations-specialist` + `$swiper-supply-ingestion-operator`
3. `$crawl-extraction-evaluation-specialist` + `$swiper-crawl-quality-evaluator`
4. `$taxonomy-training-loop-specialist` + `$swiper-taxonomy-review-lab`
5. `$recommender-offline-evaluation-specialist` + `$swiper-recommendation-eval-analyst`
6. `$product-funnel-observability-specialist` + `$swiper-golden-card-v2-observability`
7. `$retail-campaign-ops-specialist` + `$swiper-retailer-console-ops`
8. `$analytics-event-quality-specialist` + `$swiper-event-quality-guard`
9. `$release-qa-specialist` + `$swiper-release-qa-runner`
10. `$data-hygiene-backfill-specialist` + `$swiper-data-hygiene-maintainer`
11. `$docs-consistency-specialist` + `$swiper-doc-consistency-checker`
12. `$incident-triage-specialist` + `$swiper-incident-triage-commander`

## Copy-paste prompts (recommended)
1. `Use $local-dev-stack-specialist + $swiper-local-stack-operator to boot the full local stack and verify all health checks.`
2. `Use $ingestion-operations-specialist + $swiper-supply-ingestion-operator to run a batch ingestion and summarize failures by source.`
3. `Use $crawl-extraction-evaluation-specialist + $swiper-crawl-quality-evaluator to evaluate crawl quality and produce a prioritized fix queue.`
4. `Use $taxonomy-training-loop-specialist + $swiper-taxonomy-review-lab to run classify/review/train/calibrate and recommend shadow vs active.`
5. `Use $recommender-offline-evaluation-specialist + $swiper-recommendation-eval-analyst to compute offline ranking metrics and compare variants.`
6. `Use $product-funnel-observability-specialist + $swiper-golden-card-v2-observability to assess funnel health and rollout guardrails.`
7. `Use $retail-campaign-ops-specialist + $swiper-retailer-console-ops to validate segment/campaign/catalog/report workflows end-to-end.`
8. `Use $analytics-event-quality-specialist + $swiper-event-quality-guard to audit events_v1 schema and tracking invariants.`
9. `Use $release-qa-specialist + $swiper-release-qa-runner to run release checks and return a go/no-go decision with blockers.`
10. `Use $data-hygiene-backfill-specialist + $swiper-data-hygiene-maintainer to run a dry-run hygiene backfill and report apply-safe changes.`
11. `Use $docs-consistency-specialist + $swiper-doc-consistency-checker to find docs drift and patch contracts/runbooks.`
12. `Use $incident-triage-specialist + $swiper-incident-triage-commander to triage this incident and propose immediate containment.`

## Notes
- Keep prompts outcome-first: what you want delivered, not implementation details.
- Add scope/time explicitly when relevant: `last 7 days`, `only sourceId=...`, `staging only`.
- For reviews, require severity ordering and concrete file references.

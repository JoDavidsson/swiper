# Swiper — Task Definitions

## Recurring Tasks

### Daily

- Monitor ingestion health (supply engine metrics, extraction failures)
- Check drift triggers on crawled products
- Review Featured Distribution relevance gates

### Per-PR

- Run Playwright E2E tests (`npx playwright test`)
- Run Firebase emulators: `./scripts/run_emulators.sh`
- Run eval and stress test before merge (autoresearch changes)
- Update `docs/DECISIONS.md` for any architectural changes

### Release Gates

- CEO sign-off on major releases
- QA sweep on Golden Card v2 feature rollout
- Documentation consistency check

## Active Workstreams

### Phase 12a: Golden Card v2 (Controlled Rollout)
- Owner: QA Engineer + Flutter Dev
- Gate: rollout monitors active

### Decision Room v1
- Owner: Flutter Dev + Backend Dev
- Status: planned, not started
- Scope: vote, comment, finalists, suggest alternatives

### Retailer Console v1
- Owner: Backend Dev
- Scope: Insights Feed, Campaigns, Catalog, Trends, Reporting

### Confidence Score v1
- Owner: Recommendation Dev + Backend Dev
- Scope: per-product/segment intent metric (0–100)

## Autoresearch Campaigns

Run via `docs/AUTORESEARCH_AGENT_PROMPT.md`:
- Mode: shadow (default), active requires CEO authorization
- Primary metric: Liked-in-top-K (docs/OFFLINE_EVAL.md)
- Guardrails: docs/RUNBOOK_GOLDEN_CARD_V2_OBSERVABILITY.md

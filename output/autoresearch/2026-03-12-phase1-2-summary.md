# Phase 1 + Phase 2 Execution Summary (2026-03-12)

## What was requested
1. Apply one rollout profile directly in config/code.
2. Then run autonomous latency-mitigation research for high-cap (`>=800`) ranking.

## Phase 1: Applied rollout profile
Conservative profile is now applied by default in the deck pipeline and local env config.

### Effective defaults now
- `DECK_ITEMS_FETCH_LIMIT=700`
- `DECK_CANDIDATE_CAP=400`
- `DECK_RANK_WINDOW_MULTIPLIER=48`
- `RANKER_EXPLORATION_RATE=0`
- `RANKER_ENABLE_MMR_RERANK=false`
- `DECK_RETRIEVAL_DOCS_CACHE_TTL_MS=15000`

### Runtime validation probe
Validated with emulator run:
- `candidateCount=400`
- `rankWindow=400`
- `rankWindowMultiplier=48`
- `adaptiveExploration.effectiveRate=0`
- `mmrPolicy.enabled=false`
- `retrievalCache.enabled=true`

## Phase 2: High-cap latency mitigation
Implemented in-memory retrieval-doc cache in deck API (TTL controlled by `DECK_RETRIEVAL_DOCS_CACHE_TTL_MS`).

### Important bug fixed
`DECK_RETRIEVAL_DOCS_CACHE_TTL_MS=0` was initially impossible because of `||` fallback semantics; fixed parsing so `0` correctly disables cache.

### Cache matrix results
Source: `output/autoresearch/2026-03-12-deep-ranker-research-07/results_corrected.tsv`

| Config | Oracle | Likes | Avg latency (ms) | P95 latency (ms) |
|---|---:|---:|---:|---:|
| cap800 cache OFF | 0.136400 | 0.000000 | 739.65 | 890 |
| cap800 cache ON | 0.146000 | 0.000000 | 159.49 | 167 |
| cap1200 cache OFF | 0.188800 | 0.001692 | 948.95 | 1068 |
| cap1200 cache ON | 0.188800 | 0.001692 | 203.56 | 213 |

### Interpretation
- Cache ON preserved recommendation quality metrics (oracle/likes unchanged or slightly better in tested runs).
- Cache ON reduced latency by ~4-5x in high-cap settings.
- This re-opens viability of aggressive high-cap profile if cache-hit rate remains high in production traffic.

## Key artifacts
- Cache matrix script: `output/autoresearch/2026-03-12-deep-ranker-research-07/run_cache_latency_matrix.sh`
- Cache matrix results (corrected): `output/autoresearch/2026-03-12-deep-ranker-research-07/results_corrected.tsv`
- Earlier broad research summary: `output/autoresearch/2026-03-12-autonomous-research-summary.md`

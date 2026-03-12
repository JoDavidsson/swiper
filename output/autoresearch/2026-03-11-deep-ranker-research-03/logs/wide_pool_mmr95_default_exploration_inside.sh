#!/usr/bin/env bash
set -euo pipefail
cd "/Users/johannesdavidsson/Cursor Projects/Swiper/firebase/functions"
export FIRESTORE_EMULATOR_HOST=localhost:8180

node scripts/generate_fake_db.js   --users 250   --interactions-per-user 20   --item-pool-limit 5000   --seed 42   > "/Users/johannesdavidsson/Cursor Projects/Swiper/output/autoresearch/2026-03-11-deep-ranker-research-03/logs/wide_pool_mmr95_default_exploration_generator.log" 2>&1

node scripts/offline_eval_liked_topk.js   --sessions-prefix synth_   --max-sessions 250   --limit 10   --requests-per-session 2   --ground-truth-mode oracle_preference   --oracle-top-k 10   --concurrency 8   > "/Users/johannesdavidsson/Cursor Projects/Swiper/output/autoresearch/2026-03-11-deep-ranker-research-03/logs/wide_pool_mmr95_default_exploration_oracle.log" 2>&1

node scripts/offline_eval_liked_topk.js   --sessions-prefix synth_   --max-sessions 250   --limit 10   --requests-per-session 2   --ground-truth-mode likes   --oracle-top-k 10   --concurrency 8   > "/Users/johannesdavidsson/Cursor Projects/Swiper/output/autoresearch/2026-03-11-deep-ranker-research-03/logs/wide_pool_mmr95_default_exploration_likes.log" 2>&1

curl -s "http://127.0.0.1:5002/swiper-95482/europe-west1/api/items/deck?sessionId=synth_1&limit=10" > "/Users/johannesdavidsson/Cursor Projects/Swiper/output/autoresearch/2026-03-11-deep-ranker-research-03/logs/wide_pool_mmr95_default_exploration_probe.json"

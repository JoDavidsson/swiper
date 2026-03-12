#!/usr/bin/env bash
# Run complete eval and QA: fake DB generator (small), debug ranker, Jest tests.
# Optional: deck API call for synth_1 (requires emulators + functions running).
# Logs: .cursor/debug.log (NDJSON).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

EVAL_USERS="${EVAL_USERS:-250}"
EVAL_INTERACTIONS_PER_USER="${EVAL_INTERACTIONS_PER_USER:-20}"
# Default to using existing scraped/ingested items in Firestore.
# Set EVAL_GENERATE_ITEMS to a positive integer only when you explicitly want synthetic items.
EVAL_GENERATE_ITEMS="${EVAL_GENERATE_ITEMS:-}"
EVAL_ITEM_POOL_LIMIT="${EVAL_ITEM_POOL_LIMIT:-5000}"
EVAL_OFFLINE_MAX_SESSIONS="${EVAL_OFFLINE_MAX_SESSIONS:-250}"
EVAL_OFFLINE_LIMIT="${EVAL_OFFLINE_LIMIT:-10}"
EVAL_OFFLINE_REQUESTS_PER_SESSION="${EVAL_OFFLINE_REQUESTS_PER_SESSION:-1}"
EVAL_OFFLINE_CONCURRENCY="${EVAL_OFFLINE_CONCURRENCY:-8}"
EVAL_GROUND_TRUTH_MODE="${EVAL_GROUND_TRUTH_MODE:-oracle_preference}"
EVAL_ORACLE_TOP_K="${EVAL_ORACLE_TOP_K:-10}"

echo "=== Eval 1: Fake DB generator (small run) ==="
cd firebase/functions
export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8180}"
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ ! -f "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  # Emulator mode does not require service account credentials.
  unset GOOGLE_APPLICATION_CREDENTIALS
fi
if [ -z "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "$REPO_ROOT/config/emulator-credentials.json" ]; then
  export GOOGLE_APPLICATION_CREDENTIALS="$REPO_ROOT/config/emulator-credentials.json"
fi
GENERATOR_ARGS=(
  --users "$EVAL_USERS"
  --interactions-per-user "$EVAL_INTERACTIONS_PER_USER"
  --item-pool-limit "$EVAL_ITEM_POOL_LIMIT"
  --seed 42
)

if [ -n "$EVAL_GENERATE_ITEMS" ] && [ "$EVAL_GENERATE_ITEMS" -gt 0 ] 2>/dev/null; then
  GENERATOR_ARGS+=(--generate-items "$EVAL_GENERATE_ITEMS")
fi

node scripts/generate_fake_db.js "${GENERATOR_ARGS[@]}"
echo ""

echo "=== Eval 2: Debug ranker (in-memory) ==="
npm run debugRanker
echo ""

echo "=== Eval 3: Jest (ranker + api tests) ==="
npm test
echo ""

echo "=== Eval 4 (optional): Deck API for synth_1 ==="
if curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:5002/swiper-95482/europe-west1/api/items/deck?sessionId=synth_1&limit=5" 2>/dev/null | grep -q 200; then
  echo "Deck API returned 200 for synth_1"
  curl -s "http://127.0.0.1:5002/swiper-95482/europe-west1/api/items/deck?sessionId=synth_1&limit=5" | head -c 200
  echo "..."
else
  echo "Deck API not reached (start emulators + functions to test deck for synth_1)"
fi
echo ""

echo "=== Eval 5: Offline metric (Liked-in-top-K) ==="
OFFLINE_EVAL_OUTPUT="$(node scripts/offline_eval_liked_topk.js \
  --sessions-prefix synth_ \
  --max-sessions "$EVAL_OFFLINE_MAX_SESSIONS" \
  --limit "$EVAL_OFFLINE_LIMIT" \
  --requests-per-session "$EVAL_OFFLINE_REQUESTS_PER_SESSION" \
  --ground-truth-mode "$EVAL_GROUND_TRUTH_MODE" \
  --oracle-top-k "$EVAL_ORACLE_TOP_K" \
  --concurrency "$EVAL_OFFLINE_CONCURRENCY")"
echo "$OFFLINE_EVAL_OUTPUT"
PRIMARY_METRIC="$(printf '%s\n' "$OFFLINE_EVAL_OUTPUT" | awk '/^primary_metric_liked_in_top_k:/ {print $2}' | tail -n 1)"
PRIMARY_STATUS="$(printf '%s\n' "$OFFLINE_EVAL_OUTPUT" | awk '/^offline_eval_status:/ {print $2}' | tail -n 1)"
if [ -z "$PRIMARY_METRIC" ]; then
  echo "primary_metric_liked_in_top_k missing from offline eval output"
  exit 1
fi
echo ""
echo "primary_metric_liked_in_top_k: $PRIMARY_METRIC"
echo "primary_metric_status: ${PRIMARY_STATUS:-unknown}"
echo ""

echo "=== Eval complete ==="
echo "Logs: $REPO_ROOT/.cursor/debug.log"

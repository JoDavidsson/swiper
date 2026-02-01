#!/usr/bin/env bash
# Run complete eval and QA: fake DB generator (small), debug ranker, Jest tests.
# Optional: deck API call for synth_1 (requires emulators + functions running).
# Logs: .cursor/debug.log (NDJSON).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "=== Eval 1: Fake DB generator (small run) ==="
cd firebase/functions
export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8180}"
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-$REPO_ROOT/config/emulator-credentials.json}"
node scripts/generate_fake_db.js --users 2 --interactions-per-user 15 --generate-items 20 --seed 42
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

echo "=== Eval complete ==="
echo "Logs: $REPO_ROOT/.cursor/debug.log"

#!/usr/bin/env bash
# Stress test: larger synthetic DB (5k products, 100 users), Jest, deck API, then human-readable report.
# Requires: FIRESTORE_EMULATOR_HOST set, emulators (and Functions) running.
# For large-candidate ranking, set DECK_ITEMS_FETCH_LIMIT and DECK_CANDIDATE_CAP when starting the emulators.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPORT_PATH="$REPO_ROOT/docs/STRESS_TEST_REPORT.md"
BASE_URL="http://127.0.0.1:5002/swiper-95482/europe-west1/api/items/deck"

cd "$REPO_ROOT"

PRODUCTS=5000
USERS=${STRESS_TEST_USERS:-100}
INTERACTIONS_PER_USER=30
TOTAL_SWIPES=$((USERS * INTERACTIONS_PER_USER))
SEQ_REQUESTS=30
PARALLEL_REQUESTS=10

echo "=== Stress test: $PRODUCTS products, $USERS users, $INTERACTIONS_PER_USER swipes each ($TOTAL_SWIPES total) ==="
echo ""

# --- Phase 1: Generate data ---
echo "=== Phase 1: Generate data ==="
cd "$REPO_ROOT/firebase/functions"
export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8180}"
export GOOGLE_APPLICATION_CREDENTIALS="${GOOGLE_APPLICATION_CREDENTIALS:-$REPO_ROOT/config/emulator-credentials.json}"

T0=$(date +%s)
node scripts/generate_fake_db.js --users "$USERS" --interactions-per-user "$INTERACTIONS_PER_USER" --generate-items "$PRODUCTS" --seed 42
T1=$(date +%s)
GEN_DURATION=$((T1 - T0))
echo "Phase 1 completed in ${GEN_DURATION} s"
echo ""

# --- Phase 2: Unit tests ---
echo "=== Phase 2: Unit tests ==="
T2=$(date +%s)
JEST_EXIT=0
npm test || JEST_EXIT=$?
T3=$(date +%s)
JEST_DURATION=$((T3 - T2))
echo "Phase 2 completed in ${JEST_DURATION} s (exit $JEST_EXIT)"
echo ""

# --- Phase 3: Deck API stress ---
echo "=== Phase 3: Deck API stress (${SEQ_REQUESTS} sequential + ${PARALLEL_REQUESTS} parallel) ==="
T4=$(date +%s)
CURL_OUT=$(mktemp)
trap "rm -f $CURL_OUT" EXIT

# Sequential: synth_1..synth_30, limit=20
SEQ_OK=0
SEQ_FAIL=0
SEQ_TIMES=""
: > "$CURL_OUT"
for i in $(seq 1 "$SEQ_REQUESTS"); do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "${BASE_URL}?sessionId=synth_${i}&limit=20" >> "$CURL_OUT" 2>/dev/null || true
done
while read -r code time; do
  [ -z "$code" ] && continue
  if [ "$code" = "200" ]; then
    SEQ_OK=$((SEQ_OK + 1))
  else
    SEQ_FAIL=$((SEQ_FAIL + 1))
  fi
  SEQ_TIMES="$SEQ_TIMES $time"
done < "$CURL_OUT"

# Parallel: synth_1..synth_10, limit=50
PAR_OK=0
PAR_FAIL=0
PAR_TIMES=""
: > "$CURL_OUT"
for i in $(seq 1 "$PARALLEL_REQUESTS"); do
  curl -s -o /dev/null -w "%{http_code} %{time_total}\n" "${BASE_URL}?sessionId=synth_${i}&limit=50" >> "$CURL_OUT" 2>/dev/null &
done
wait
while read -r code time; do
  [ -z "$code" ] && continue
  if [ "$code" = "200" ]; then
    PAR_OK=$((PAR_OK + 1))
  else
    PAR_FAIL=$((PAR_FAIL + 1))
  fi
  PAR_TIMES="$PAR_TIMES $time"
done < "$CURL_OUT"

T5=$(date +%s)
API_DURATION=$((T5 - T4))
TOTAL_REQUESTS=$((SEQ_REQUESTS + PARALLEL_REQUESTS))
TOTAL_OK=$((SEQ_OK + PAR_OK))
TOTAL_FAIL=$((SEQ_FAIL + PAR_FAIL))

# Average latency (from first batch only for simplicity; could parse both)
AVG_MS=""
if command -v awk >/dev/null 2>&1; then
  ALL_TIMES="$SEQ_TIMES $PAR_TIMES"
  AVG_MS=$(echo "$ALL_TIMES" | awk '{ s=0; n=0; for(i=1;i<=NF;i++){ if($i+0==$i){ s+=$i; n++ } } print (n>0) ? (s/n)*1000 : 0 }')
fi
[ -z "$AVG_MS" ] && AVG_MS="(n/a)"

echo "Phase 3 completed in ${API_DURATION} s: $TOTAL_OK succeeded, $TOTAL_FAIL failed. Average response time: ${AVG_MS} ms"
echo ""

# --- Human-readable report ---
{
  echo "# Stress test report"
  echo ""
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo ""
  echo "## What was run"
  echo ""
  echo "- **Products:** $PRODUCTS"
  echo "- **Users:** $USERS"
  echo "- **Swipes per user:** $INTERACTIONS_PER_USER ($TOTAL_SWIPES total swipes)"
  echo "- **Deck API calls:** $TOTAL_REQUESTS (${SEQ_REQUESTS} sequential, ${PARALLEL_REQUESTS} parallel)"
  echo ""
  echo "## Timing"
  echo ""
  echo "- Data generation: ${GEN_DURATION} s"
  echo "- Unit tests (Jest): ${JEST_DURATION} s"
  echo "- Deck API phase: ${API_DURATION} s"
  echo ""
  echo "## Results"
  echo ""
  if [ "$JEST_EXIT" -eq 0 ]; then
    echo "- All Jest tests **passed**."
  else
    echo "- Jest: **$JEST_EXIT test(s) failed**."
  fi
  if [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "- All $TOTAL_REQUESTS deck requests returned **200**. Average response time: **${AVG_MS} ms**."
  else
    echo "- Deck API: **$TOTAL_FAIL** of $TOTAL_REQUESTS requests **failed**; $TOTAL_OK succeeded."
  fi
  echo ""
  echo "## What this means"
  echo ""
  if [ "$JEST_EXIT" -eq 0 ] && [ "$TOTAL_FAIL" -eq 0 ]; then
    echo "The recommendation engine and deck API handled $PRODUCTS products and the requested deck load without errors. Unit tests passed. You can increase scale (e.g. 10k products, more users) or set \`DECK_ITEMS_FETCH_LIMIT\` and \`DECK_CANDIDATE_CAP\` when starting the emulators to stress the ranker with more candidates per request."
  else
    echo "One or more steps failed. Check Jest output and deck API responses above. Fix failures before increasing scale."
  fi
  echo ""
} > "$REPORT_PATH"

echo "=== Report written to $REPORT_PATH ==="
echo ""
cat "$REPORT_PATH"
echo ""

if [ "$JEST_EXIT" -ne 0 ] || [ "$TOTAL_FAIL" -gt 0 ]; then
  exit 1
fi

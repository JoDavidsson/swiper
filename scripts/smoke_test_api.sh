#!/usr/bin/env bash
# Smoke-test the API (session + deck). Run with Firebase emulators up.
# Usage: ./scripts/smoke_test_api.sh [base_url]
# Default base_url: http://127.0.0.1:5002/swiper-95482/europe-west1

set -e
BASE="${1:-http://127.0.0.1:5002/swiper-95482/europe-west1}"
SESSION_URL="${BASE}/api/session"
DECK_URL="${BASE}/api/items/deck"

echo "Smoke-test API at ${BASE}"

# POST /api/session -> 200 + { sessionId }
RES=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" "${SESSION_URL}")
BODY=$(echo "$RES" | sed '$d')
CODE=$(echo "$RES" | tail -n 1)
if [ "$CODE" != "200" ]; then
  echo "FAIL: POST /api/session returned ${CODE}"
  echo "$BODY"
  exit 1
fi
SESSION_ID=$(echo "$BODY" | grep -o '"sessionId":"[^"]*"' | cut -d'"' -f4)
if [ -z "$SESSION_ID" ]; then
  echo "FAIL: POST /api/session did not return sessionId"
  echo "$BODY"
  exit 1
fi
echo "OK: POST /api/session -> 200, sessionId=${SESSION_ID}"

# GET /api/items/deck?sessionId=... -> 200 + { items }
DECK_RES=$(curl -s -w "\n%{http_code}" "${DECK_URL}?sessionId=${SESSION_ID}&limit=5")
DECK_BODY=$(echo "$DECK_RES" | sed '$d')
DECK_CODE=$(echo "$DECK_RES" | tail -n 1)
if [ "$DECK_CODE" != "200" ]; then
  echo "FAIL: GET /api/items/deck returned ${DECK_CODE}"
  echo "$DECK_BODY"
  exit 1
fi
echo "OK: GET /api/items/deck -> 200"
echo "Smoke test passed."

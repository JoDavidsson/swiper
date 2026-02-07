#!/usr/bin/env bash
# Seed retailer sources into Firestore via the admin API.
# Usage: ./scripts/seed_retailer_sources.sh
#
# Prerequisites:
#   1. Firebase emulators running (./scripts/run_emulators.sh)
#   2. Supply Engine running (./scripts/run_supply_engine.sh)
#
# Each source is added via POST /api/admin/sources with crawl mode.
# Auto-discovery (sitemap detection etc.) happens when a run is triggered.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load .env for ADMIN_PASSWORD
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  source "$REPO_ROOT/.env"
  set +a
fi

API_BASE="${API_BASE_URL:-http://localhost:5002/swiper-95482/europe-west1/api}"
PASSWORD="${ADMIN_PASSWORD:?ADMIN_PASSWORD must be set in .env}"

echo "============================================"
echo "  Seeding retailer sources"
echo "  API: $API_BASE"
echo "============================================"
echo ""

# Sofa-related keywords used for filtering product URLs during crawl
SOFA_KEYWORDS='["soffa","soffor","sofa","sofas","hörnsoffa","bäddsoffa","divansoffa","hornsoffa","soffbord"]'

SUCCESS=0
FAIL=0
SKIP=0

add_source() {
  local name="$1"
  local domain="$2"
  local url="$3"

  # Check if source already exists (by name)
  existing=$(curl -s -H "X-Admin-Password: $PASSWORD" "$API_BASE/admin/sources" 2>/dev/null)
  if echo "$existing" | grep -q "\"name\":\"$name\""; then
    echo "  SKIP  $name (already exists)"
    SKIP=$((SKIP + 1))
    return
  fi

  response=$(curl -s -w "\n%{http_code}" -X POST "$API_BASE/admin/sources" \
    -H "Content-Type: application/json" \
    -H "X-Admin-Password: $PASSWORD" \
    -d "{
      \"name\": \"$name\",
      \"url\": \"$url\",
      \"baseUrl\": \"https://$domain\",
      \"mode\": \"crawl\",
      \"isEnabled\": true,
      \"rateLimitRps\": 1.0,
      \"includeKeywords\": $SOFA_KEYWORDS,
      \"categoryFilter\": [\"soffa\", \"soffor\", \"sofa\", \"sofas\", \"hornsoffa\", \"divansoffa\"]
    }")

  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | sed '$d')

  if [ "$http_code" = "200" ]; then
    id=$(echo "$body" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    echo "  OK    $name → $id"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  FAIL  $name (HTTP $http_code): $body"
    FAIL=$((FAIL + 1))
  fi
}

echo "Adding sources..."
echo ""

add_source "IKEA Sverige"        "ikea.com"              "https://www.ikea.com/se/sv/cat/soffor-fatoljer-700640/"
add_source "Mio"                 "mio.se"                "https://www.mio.se/kampanj/soffor"
add_source "Trademax"            "trademax.se"           "https://www.trademax.se/"
add_source "Chilli"              "chilli.se"             "https://www.chilli.se/"
add_source "Furniturebox"        "furniturebox.se"       "https://www.furniturebox.se/"
add_source "SoffaDirekt"         "soffadirekt.se"        "https://www.soffadirekt.se/"
add_source "Svenska Hem"         "svenskahem.se"         "https://www.svenskahem.se/produkter/soffor"
add_source "Svenssons"           "svenssons.se"          "https://www.svenssons.se/mobler/soffor/"
add_source "Länna Möbler"        "lannamobler.se"        "https://www.lannamobler.se/soffor"
add_source "Nordiska Galleriet"  "nordiskagalleriet.se"  "https://www.nordiskagalleriet.se/no-ga/soffor"
add_source "RoyalDesign"         "royaldesign.se"        "https://royaldesign.se/mobler/soffor"
add_source "Rum21"               "rum21.se"              "https://www.rum21.se/"
add_source "EM Home"             "emhome.se"             "https://www.emhome.se/soffor"
add_source "Jotex"               "jotex.se"              "https://www.jotex.se/mobler/soffor"
add_source "Ellos"               "ellos.se"              "https://www.ellos.se/hem-inredning/mobler/soffor-fatoljer/soffor"
add_source "Homeroom"            "homeroom.se"           "https://www.homeroom.se/mobler/soffor-fatoljer/soffor"
add_source "Sweef"               "sweef.se"              "https://sweef.se/soffor"
add_source "Sleepo"              "sleepo.se"             "https://www.sleepo.se/mobler/soffor-fatoljer/"
add_source "Newport"             "newport.se"            "https://www.newport.se/shop/mobler/soffor"
add_source "ILVA"                "ilva.se"               "https://ilva.se/vardagsrum/soffor/"

echo ""
echo "============================================"
echo "  Done: $SUCCESS added, $SKIP skipped, $FAIL failed"
echo "============================================"

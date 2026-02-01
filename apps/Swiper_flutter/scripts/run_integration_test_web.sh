#!/usr/bin/env bash
# Run Flutter web integration tests in Chrome (headless optional).
# Requires: chromedriver on PATH or installed via npx @puppeteer/browsers install chromedriver@stable
# Usage: from apps/Swiper_flutter, ./scripts/run_integration_test_web.sh [--headless]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$APP_ROOT"

# Prefer chromedriver from project (npx @puppeteer/browsers install chromedriver@<version>)
CHROMEDRIVER_BIN=""
if command -v chromedriver &>/dev/null; then
  CHROMEDRIVER_BIN=chromedriver
elif [ -d "$APP_ROOT/chromedriver" ]; then
  CHROMEDRIVER_BIN=$(find "$APP_ROOT/chromedriver" -name chromedriver -type f 2>/dev/null | head -1)
fi
if [ -z "$CHROMEDRIVER_BIN" ]; then
  echo "chromedriver not found. Install with: npx @puppeteer/browsers install chromedriver@stable"
  echo "Or match your Chrome version: npx @puppeteer/browsers install chromedriver@\$(curl -s https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json | grep -o '\"version\":\"[^\"]*\"' | head -1 | cut -d'\"' -f4)"
  exit 1
fi

# Start chromedriver in background if not already listening
if ! (curl -s "http://127.0.0.1:4444/status" >/dev/null 2>&1); then
  echo "Starting chromedriver on port 4444..."
  "$CHROMEDRIVER_BIN" --port=4444 &
  CHROMEDRIVER_PID=$!
  trap "kill $CHROMEDRIVER_PID 2>/dev/null" EXIT
  sleep 2
fi

# Use --release so flutter drive avoids debug connection (avoids AppConnectionException).
# For headless, -d web-server still needs chromedriver on 4444.
EXTRA=""
[[ "${1:-}" == "--headless" ]] && EXTRA="-d web-server --web-run-headless"

echo "Running integration tests (Chrome, release mode for reliable automation)..."
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d chrome \
  --release \
  $EXTRA

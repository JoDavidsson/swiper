#!/usr/bin/env bash
# Run Flutter web on a fixed port so you can bookmark http://localhost:8080.
# Leave this running: code changes hot-reload automatically; no need to re-run.
#
# Prereq: API must be available. Start emulators first: ./scripts/run_emulators.sh
# (Otherwise login and deck will fail with ERR_CONNECTION_REFUSED on port 5002.)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/apps/Swiper_flutter"
echo "Flutter web: http://localhost:8080 (leave running for hot reload)"
echo "If login/deck fail, start emulators in another terminal: ./scripts/run_emulators.sh"
exec flutter run -d chrome --web-port=8080

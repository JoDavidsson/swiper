#!/usr/bin/env bash
# Run Flutter web on a fixed port so you can bookmark http://localhost:8080.
# Leave this running: code changes hot-reload automatically; no need to re-run.
#
# Prereq: API must be available. Start emulators first: ./scripts/run_emulators.sh
# (Otherwise login and deck will fail with ERR_CONNECTION_REFUSED on port 5002.)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/apps/Swiper_flutter"
WEB_PORT="${WEB_PORT:-8080}"
FORCE_RESTART="${FORCE_RESTART:-0}"

EXISTING_PID="$(lsof -nP -iTCP:${WEB_PORT} -sTCP:LISTEN -t 2>/dev/null || true)"
if [ -n "$EXISTING_PID" ]; then
  EXISTING_CMD="$(ps -p "$EXISTING_PID" -o command= 2>/dev/null || true)"
  if echo "$EXISTING_CMD" | grep -Eiq 'flutter|flutter_tools|dart.*flutter_tools'; then
    if [ "$FORCE_RESTART" = "1" ]; then
      echo "Stopping existing Flutter web process on ${WEB_PORT} (PID ${EXISTING_PID})..."
      kill "${EXISTING_PID}" || true
      sleep 1
    else
    echo "Flutter web already running on http://localhost:${WEB_PORT} (PID ${EXISTING_PID})."
    echo "Reuse that session for hot reload. If needed: kill ${EXISTING_PID} and rerun."
    exit 0
    fi
  fi
  if [ "$FORCE_RESTART" != "1" ]; then
    echo "Port ${WEB_PORT} is already in use by PID ${EXISTING_PID}."
    echo "Stop that process or run on another port, e.g. WEB_PORT=8081 ./scripts/run_flutter_web.sh"
    echo "If this is a stale Flutter process: FORCE_RESTART=1 ./scripts/run_flutter_web.sh"
    exit 1
  fi
fi

echo "Flutter web: http://localhost:${WEB_PORT} (leave running for hot reload)"
echo "If login/deck fail, start emulators in another terminal: ./scripts/run_emulators.sh"
exec flutter run -d chrome --web-port="${WEB_PORT}"

#!/usr/bin/env bash
# Run Supply Engine locally (FastAPI).
# Usage: from repo root, ./scripts/run_supply_engine.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

export PYTHONPATH="$REPO_ROOT/services/supply_engine"
export SOURCES_JSON="$REPO_ROOT/config/sources.json"

echo "Starting Supply Engine on http://localhost:8081"
echo "Trigger run: POST http://localhost:8081/run/sample_feed"
echo ""

cd services/supply_engine
uvicorn app.main:app --reload --host 0.0.0.0 --port 8081

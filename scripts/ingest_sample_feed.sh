#!/usr/bin/env bash
# Ingest sample_feed.csv into Firestore (emulator or project).
# With no env set, defaults to emulator (localhost:8180). Prereq: start emulators first: ./scripts/run_emulators.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

export PYTHONPATH="$REPO_ROOT/services/supply_engine"
export SOURCES_JSON="$REPO_ROOT/config/sources.json"

# Use absolute path for feedUrl so Supply Engine finds the file
export SAMPLE_FEED_PATH="$REPO_ROOT/sample_data/sample_feed.csv"

# Default to emulator when no credentials set (common case: local dev). Emulator does not validate certs.
if [ -z "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  export FIRESTORE_EMULATOR_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8180}"
  export GOOGLE_APPLICATION_CREDENTIALS="$REPO_ROOT/config/emulator-credentials.json"
fi

echo "Ingesting sample feed from $SAMPLE_FEED_PATH"
echo "Firestore: ${FIRESTORE_EMULATOR_HOST:-default project}"
[ -n "$FIRESTORE_EMULATOR_HOST" ] && echo "(Start emulators first: ./scripts/run_emulators.sh)"
echo ""

cd services/supply_engine
PYTHON="python3"
[ -x "$REPO_ROOT/services/supply_engine/.venv/bin/python3" ] && PYTHON="$REPO_ROOT/services/supply_engine/.venv/bin/python3"
"$PYTHON" -c "
from app.sources import get_sources_from_config
from app.feed_ingestion import run_feed_ingestion
import os
sources = get_sources_from_config()
# Override feedUrl to absolute path
for s in sources:
    if s.get('id') == 'sample_feed':
        s['feedUrl'] = os.environ.get('SAMPLE_FEED_PATH', 'sample_data/sample_feed.csv')
        break
source = next((s for s in sources if s.get('id') == 'sample_feed'), None)
if not source:
    raise SystemExit('sample_feed source not found')
result = run_feed_ingestion('sample_feed', source)
print('Result:', result)
stats = result.get('stats', {})
n = stats.get('upserted', 0) + stats.get('failed', 0)
print('Items in feed:', stats.get('fetched', 0), '-> ingested:', n, '(upserted:', stats.get('upserted', 0), ')')
"

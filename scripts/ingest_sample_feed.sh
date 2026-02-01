#!/usr/bin/env bash
# Ingest sample_feed.csv into Firestore (emulator or project).
# Usage: set GOOGLE_APPLICATION_CREDENTIALS or FIRESTORE_EMULATOR_HOST, then ./scripts/ingest_sample_feed.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

export PYTHONPATH="$REPO_ROOT/services/supply_engine"
export SOURCES_JSON="$REPO_ROOT/config/sources.json"

# Use absolute path for feedUrl so Supply Engine finds the file
export SAMPLE_FEED_PATH="$REPO_ROOT/sample_data/sample_feed.csv"

echo "Ingesting sample feed from $SAMPLE_FEED_PATH"
echo "Firestore: ${FIRESTORE_EMULATOR_HOST:-default project}"
echo ""

cd services/supply_engine
python -c "
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
"

#!/usr/bin/env bash
# Start Firebase emulators for local development.
# Usage: from repo root, ./scripts/run_emulators.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Starting Firebase emulators (Firestore, Functions, Hosting, Auth, UI)..."
echo "Firestore: http://localhost:8180"
echo "Functions: http://localhost:5002"
echo "Hosting:   http://localhost:5010"
echo "UI:        http://localhost:4100"
echo ""
echo "For ingest script use: export FIRESTORE_EMULATOR_HOST=localhost:8180"
echo ""

firebase emulators:start --only firestore,functions,hosting,auth,ui

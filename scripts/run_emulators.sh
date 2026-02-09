#!/usr/bin/env bash
# Start Firebase emulators for local development.
# Usage: from repo root, ./scripts/run_emulators.sh
# Loads .env from repo root so ADMIN_PASSWORD (and other vars) are available to Functions.
# Automatically imports existing data from emulator-data/ and exports on exit.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ -f .env ]; then
  set -a
  source .env
  set +a
  echo "Loaded .env (ADMIN_PASSWORD and other vars available to Functions)."
fi

# Build Functions TypeScript before starting emulators
# This ensures we're running the latest code, not stale lib/index.js
echo "Building Firebase Functions..."
cd "$REPO_ROOT/firebase/functions"
npm run build
cd "$REPO_ROOT"
echo "Functions build complete."
echo ""

# Start only Firestore + Functions so the deck API works. Avoids UI/Auth/Hosting port conflicts.
# For full emulators (UI, Auth, Hosting) run: firebase emulators:start --only firestore,functions,hosting,auth,ui
echo "Starting Firebase emulators (Firestore, Functions)..."
echo "Firestore: http://localhost:8180"
echo "Functions: http://localhost:5002"
echo ""
echo "For Supply Engine: export FIRESTORE_EMULATOR_HOST=localhost:8180"
echo "Supply Engine default port: http://localhost:8081"
echo ""

# Import existing data if available, always export on exit to preserve state
IMPORT_FLAG=""
if [ -d "$REPO_ROOT/emulator-data" ]; then
  echo "Importing existing Firestore data from emulator-data/..."
  IMPORT_FLAG="--import=$REPO_ROOT/emulator-data"
fi

firebase emulators:start --only firestore,functions $IMPORT_FLAG --export-on-exit="$REPO_ROOT/emulator-data"

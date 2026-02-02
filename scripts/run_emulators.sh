#!/usr/bin/env bash
# Start Firebase emulators for local development.
# Usage: from repo root, ./scripts/run_emulators.sh
# Loads .env from repo root so ADMIN_PASSWORD (and other vars) are available to Functions.

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

# Start only Firestore + Functions so the deck API works. Avoids UI/Auth/Hosting port conflicts.
# For full emulators (UI, Auth, Hosting) run: firebase emulators:start --only firestore,functions,hosting,auth,ui
echo "Starting Firebase emulators (Firestore, Functions)..."
echo "Firestore: http://localhost:8180"
echo "Functions: http://localhost:5002"
echo ""
echo "For ingest script use: export FIRESTORE_EMULATOR_HOST=localhost:8180"
echo ""

firebase emulators:start --only firestore,functions

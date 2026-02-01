#!/usr/bin/env bash
# Start Firebase emulators for local development.
# Usage: from repo root, ./scripts/run_emulators.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Starting Firebase emulators (Firestore, Functions, Hosting, Auth, UI)..."
echo "Firestore: http://localhost:8080"
echo "Functions: http://localhost:5001"
echo "Hosting:   http://localhost:5000"
echo "UI:        http://localhost:4000"
echo ""
echo "Set FLUTTER_FIREBASE_EMULATOR=1 and use Firebase emulator host for Flutter."
echo ""

firebase emulators:start --only firestore,functions,hosting,auth,ui

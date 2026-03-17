#!/usr/bin/env bash
# Staging / family-test deploy: build Flutter web + Functions, then deploy to Firebase.
# Prereqs: firebase login, firebase use <project-id>, .env or Firebase config set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT_ID="$(firebase use --json | node -e 'let s=""; process.stdin.on("data", d => s += d).on("end", () => { const parsed = JSON.parse(s); process.stdout.write(parsed.result || ""); });')"
if [ -z "$PROJECT_ID" ]; then
  echo "Unable to determine the active Firebase project. Run: firebase use <project-id>"
  exit 1
fi

API_BASE_URL="${API_BASE_URL:-https://${PROJECT_ID}.web.app}"
BUILD_ARGS=("--dart-define=API_BASE_URL=${API_BASE_URL}")

if [ -n "${GOOGLE_SIGN_IN_WEB_CLIENT_ID:-}" ]; then
  BUILD_ARGS+=("--dart-define=GOOGLE_SIGN_IN_WEB_CLIENT_ID=${GOOGLE_SIGN_IN_WEB_CLIENT_ID}")
else
  echo "Warning: GOOGLE_SIGN_IN_WEB_CLIENT_ID is not set."
  echo "Hosted admin login will require either Google Sign-In to be configured in a later build"
  echo "or legacy password fallback to be explicitly enabled in Functions with ALLOW_LEGACY_ADMIN_PASSWORD=true."
fi

if [ -n "${APP_VERSION:-}" ]; then
  BUILD_ARGS+=("--dart-define=APP_VERSION=${APP_VERSION}")
fi

echo "Building Flutter web for project: ${PROJECT_ID}"
echo "Using API base URL: ${API_BASE_URL}"
cd apps/Swiper_flutter
flutter pub get
flutter build web "${BUILD_ARGS[@]}"
cd "$ROOT"

echo "Building Cloud Functions..."
cd firebase/functions
npm ci
npm run build
cd "$ROOT"

echo "Deploying Firebase (functions, hosting, firestore rules/indexes)..."
firebase deploy --only functions,hosting,firestore:rules,firestore:indexes

echo "Deploy complete."
echo "Family-test URLs:"
echo "  https://${PROJECT_ID}.web.app"
echo "  https://${PROJECT_ID}.firebaseapp.com"
echo "Run the post-deploy smoke from docs/RUNBOOK_DEPLOYMENT.md before sending the link out."

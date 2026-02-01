#!/usr/bin/env bash
# Staging / first real deploy: build Flutter web + Functions, then deploy to Firebase.
# Prereqs: firebase login, firebase use <project-id>, .env or Firebase config set.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Building Flutter web..."
cd apps/Swiper_flutter
flutter pub get
flutter build web
cd "$ROOT"

echo "Building Cloud Functions..."
cd firebase/functions
npm ci
npm run build
cd "$ROOT"

echo "Deploying Firebase (functions, hosting, firestore rules/indexes)..."
firebase deploy --only functions,hosting,firestore:rules,firestore:indexes

echo "Done. Run post-deploy smoke from docs/RUNBOOK_DEPLOYMENT.md (App loads, Session, Deck, Detail, Likes, Go redirect, Profile, Admin, Shared shortlist)."

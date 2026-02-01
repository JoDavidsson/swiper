#!/usr/bin/env bash
# One-time setup: FlutterFire config for Swiper. Run from repo root after firebase login.
# Requires: Flutter in PATH, firebase CLI logged in (firebase login).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

echo "Using Firebase project: $(firebase use 2>/dev/null || cat .firebaserc | grep default)"
echo ""

# Ensure FlutterFire CLI is available
if ! command -v flutterfire >/dev/null 2>&1; then
  echo "Installing FlutterFire CLI..."
  dart pub global activate flutterfire_cli 2>/dev/null || flutter pub global activate flutterfire_cli
  export PATH="$PATH:$HOME/.pub-cache/bin"
fi
export PATH="$PATH:$HOME/.pub-cache/bin"

cd apps/Swiper_flutter
echo "Running flutter pub get..."
flutter pub get
echo "Running flutterfire configure..."
flutterfire configure

echo ""
echo "Done. You can run: flutter run -d chrome"

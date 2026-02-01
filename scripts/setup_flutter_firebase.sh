#!/usr/bin/env bash
# One-time setup: FlutterFire config for Swiper. Run from repo root after firebase login.
# Requires: Flutter in PATH, firebase CLI logged in (firebase login).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Prefer flutter from PATH; fallback to common install locations
if ! command -v flutter >/dev/null 2>&1; then
  for dir in "$HOME/flutter/bin" "$HOME/development/flutter/bin"; do
    if [ -x "$dir/flutter" ]; then
      export PATH="$dir:$PATH"
      break
    fi
  done
  [ -d /opt/homebrew/opt/flutter/bin ] && export PATH="/opt/homebrew/opt/flutter/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on your PATH."
  echo ""
  echo "1. Install Flutter: https://docs.flutter.dev/get-started/install"
  echo "   (e.g. macOS: brew install flutter, or download the SDK and unzip to ~/flutter)"
  echo "2. Add Flutter to PATH, e.g. in ~/.zshrc:"
  echo "   export PATH=\"\$PATH:\$HOME/flutter/bin\""
  echo "3. Restart this terminal (or run: source ~/.zshrc), then run this script again:"
  echo "   ./scripts/setup_flutter_firebase.sh"
  exit 1
fi

echo "Using Firebase project: $(firebase use 2>/dev/null || grep default .firebaserc)"
echo ""

# Ensure FlutterFire CLI is available
export PATH="$PATH:$HOME/.pub-cache/bin"
if ! command -v flutterfire >/dev/null 2>&1; then
  echo "Installing FlutterFire CLI..."
  dart pub global activate flutterfire_cli 2>/dev/null || flutter pub global activate flutterfire_cli
fi

cd apps/Swiper_flutter
echo "Running flutter pub get..."
flutter pub get
# Use project from repo root .firebaserc so configure finds it when run from app dir
FIREBASE_PROJECT="${FIREBASE_PROJECT:-$(grep -o '"default"[[:space:]]*:[[:space:]]*"[^"]*"' "$REPO_ROOT/.firebaserc" 2>/dev/null | cut -d'"' -f4)}"
echo "Running flutterfire configure (project: ${FIREBASE_PROJECT:-default})..."
flutterfire configure ${FIREBASE_PROJECT:+--project "$FIREBASE_PROJECT"}

echo ""
echo "Done. You can run: flutter run -d chrome"

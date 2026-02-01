#!/usr/bin/env bash
# Add Git remote and push main. Run from repo root with your private repo URL.
# Usage: ./scripts/push_to_remote.sh <REPO_URL>
# Example: ./scripts/push_to_remote.sh git@github.com:youruser/Swiper.git

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

REPO_URL="${1:?Usage: $0 <REPO_URL>}"

if git remote get-url origin 2>/dev/null; then
  echo "Remote 'origin' already exists. To replace it:"
  echo "  git remote remove origin"
  echo "  $0 $REPO_URL"
  exit 1
fi

git remote add origin "$REPO_URL"
git push -u origin main
echo "Done. Pushed to origin (main)."

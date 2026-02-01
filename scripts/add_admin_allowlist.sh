#!/usr/bin/env bash
# Add an admin email to Firestore adminAllowlist.
# Prereqs: GOOGLE_APPLICATION_CREDENTIALS set (service account JSON path).
# For emulator: FIRESTORE_EMULATOR_HOST=localhost:8180
#
# Usage: ./scripts/add_admin_allowlist.sh <email>
# Example: ./scripts/add_admin_allowlist.sh you@example.com
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/firebase/functions"
if [ -z "$1" ]; then
  echo "Usage: $0 <email>"
  echo "Example: $0 you@example.com"
  exit 1
fi
node scripts/add_admin_allowlist.js "$1"

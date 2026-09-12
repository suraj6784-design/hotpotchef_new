#!/usr/bin/env bash
# Play/internal release APK. Does not switch Razorpay to live keys.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Missing .env — release builds must use --dart-define-from-file=.env" >&2
  exit 1
fi
if [[ ! -f android/key.properties ]]; then
  echo "Missing android/key.properties — debug signing is not allowed for release APKs" >&2
  exit 1
fi

flutter build apk --release --dart-define-from-file=.env --no-tree-shake-icons
echo "APK: build/app/outputs/flutter-apk/app-release.apk"

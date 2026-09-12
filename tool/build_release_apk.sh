#!/usr/bin/env bash
# Play/internal release APKs. Does not switch Razorpay to live keys.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  echo "Missing .env - release builds must use --dart-define-from-file=.env" >&2
  exit 1
fi
if [[ ! -f android/key.properties ]]; then
  echo "Missing android/key.properties - debug signing is not allowed for release APKs" >&2
  exit 1
fi

COMMON=(--release --dart-define-from-file=.env --no-tree-shake-icons --split-per-abi --target-platform android-arm64)

flutter build apk "${COMMON[@]}" --flavor diner --dart-define=APP_FLAVOR=diner
flutter build apk "${COMMON[@]}" --flavor partner --dart-define=APP_FLAVOR=partner

OUT=build/app/outputs/flutter-apk
cp "$OUT/app-arm64-v8a-diner-release.apk" "$OUT/HotPotChef.apk"
cp "$OUT/app-arm64-v8a-partner-release.apk" "$OUT/HotPotChef-Partner.apk"
find "$OUT" -maxdepth 1 -name '*.apk' ! -name 'HotPotChef.apk' ! -name 'HotPotChef-Partner.apk' -delete

size_mb() { du -m "$1" | awk '{print $1}'; }
echo "HotPotChef:         $(size_mb "$OUT/HotPotChef.apk") MB  $OUT/HotPotChef.apk"
echo "HotPotChef Partner: $(size_mb "$OUT/HotPotChef-Partner.apk") MB  $OUT/HotPotChef-Partner.apk"

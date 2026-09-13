#!/usr/bin/env bash
# Cloud Agent install script for the hotpotchef_new Flutter app.
# Idempotent: safe to run repeatedly and against cached/snapshotted state.
set -euo pipefail

FLUTTER_VERSION="3.44.8"
FLUTTER_DIR="/opt/flutter"
ARCHIVE_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# 1. Install the pinned Flutter SDK (matches this project's .metadata revision).
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  echo "Installing Flutter ${FLUTTER_VERSION} to ${FLUTTER_DIR}..."
  tmp="$(mktemp -d)"
  curl -fsSL -o "${tmp}/flutter.tar.xz" "${ARCHIVE_URL}"
  sudo mkdir -p /opt
  sudo tar -xf "${tmp}/flutter.tar.xz" -C /opt
  sudo chown -R "$(id -u):$(id -g)" "${FLUTTER_DIR}"
  rm -rf "${tmp}"
else
  echo "Flutter already present at ${FLUTTER_DIR}."
fi

# 2. Expose flutter/dart on PATH for every shell (idempotent symlinks).
sudo ln -sf "${FLUTTER_DIR}/bin/flutter" /usr/local/bin/flutter
sudo ln -sf "${FLUTTER_DIR}/bin/dart" /usr/local/bin/dart
export PATH="${FLUTTER_DIR}/bin:${PATH}"

# 3. Trust the SDK and project git directories (avoids "dubious ownership").
git config --global --add safe.directory "${FLUTTER_DIR}" || true
git config --global --add safe.directory "$(pwd)" || true

# 4. Disable analytics and precache the web engine artifacts.
flutter config --no-analytics >/dev/null 2>&1 || true
flutter precache --web >/dev/null 2>&1 || true

# 5. Write .env on every Cloud Agent boot. The app declares `.env` as a
#    required Flutter asset and reads credentials from it at startup.
#    SUPABASE_URL defaults to this project's hosted instance. Cursor Secrets
#    for SUPABASE_ANON_KEY / RAZORPAY_KEY_ID / GOOGLE_MAPS_API_KEY (and an
#    optional URL override) are sanitized before write — pasted values often
#    arrive wrapped in quotes or with a trailing newline and then fail as
#    "Invalid API key". Placeholders keep analyze/test/build working when
#    secrets are absent. Do not commit real keys (.env is gitignored).
_clean_secret() {
  local v
  # Drop CR/LF first so a trailing quote is not hidden behind a newline.
  v="$(printf '%s' "$1" | tr -d '\r\n')"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v#[\"\']}"
  v="${v%[\"\']}"
  printf '%s' "$v"
}

DEFAULT_SUPABASE_URL="https://tpcykyaumvqtwhuiiomg.supabase.co"
echo "Writing .env (credentials sourced from environment / Cursor Secrets when present)."
cat > .env <<EOF
SUPABASE_URL=$(_clean_secret "${SUPABASE_URL:-$DEFAULT_SUPABASE_URL}")
SUPABASE_ANON_KEY=$(_clean_secret "${SUPABASE_ANON_KEY:-placeholder-anon-key}")
GOOGLE_MAPS_API_KEY=$(_clean_secret "${GOOGLE_MAPS_API_KEY:-}")
RAZORPAY_KEY_ID=$(_clean_secret "${RAZORPAY_KEY_ID:-}")
EOF

# 6. Fetch Dart/Flutter package dependencies from the pinned lockfile.
flutter pub get

echo "Install complete. Flutter: $(flutter --version | head -1)"

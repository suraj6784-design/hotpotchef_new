# Play/internal release APK. Does not switch Razorpay to live keys.
# Requires repo-root .env (SUPABASE_*, GOOGLE_MAPS_API_KEY) and android/key.properties.

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path ".env")) {
  throw "Missing .env — release builds must use --dart-define-from-file=.env"
}
if (-not (Test-Path "android/key.properties")) {
  throw "Missing android/key.properties — debug signing is not allowed for release APKs"
}

flutter build apk --release --dart-define-from-file=.env --no-tree-shake-icons
Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk"

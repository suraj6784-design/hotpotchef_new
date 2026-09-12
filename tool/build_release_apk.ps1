# Play/internal release APKs. Does not switch Razorpay to live keys.
# Requires repo-root .env and android/key.properties.

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Test-Path ".env")) {
  throw "Missing .env - release builds must use --dart-define-from-file=.env"
}
if (-not (Test-Path "android/key.properties")) {
  throw "Missing android/key.properties - debug signing is not allowed for release APKs"
}

# Phone APKs only (arm64). Copies land as HotPotChef.apk and HotPotChef-Partner.apk.
$common = @(
    "--release",
    "--dart-define-from-file=.env",
    "--no-tree-shake-icons",
    "--split-per-abi",
    "--target-platform", "android-arm64"
)

flutter build apk @common --flavor diner --dart-define=APP_FLAVOR=diner
flutter build apk @common --flavor partner --dart-define=APP_FLAVOR=partner

$outDir = "build/app/outputs/flutter-apk"
Copy-Item "$outDir/app-arm64-v8a-diner-release.apk" "$outDir/HotPotChef.apk" -Force
Copy-Item "$outDir/app-arm64-v8a-partner-release.apk" "$outDir/HotPotChef-Partner.apk" -Force
Get-ChildItem $outDir -Filter "*.apk" |
    Where-Object { $_.Name -notin @("HotPotChef.apk", "HotPotChef-Partner.apk") } |
    Remove-Item -Force

function Show-Apk([string]$label, [string]$path) {
    $mb = [math]::Round((Get-Item $path).Length / 1MB, 1)
    Write-Host ("{0,-18} {1,6} MB  {2}" -f $label, $mb, $path)
}

Show-Apk "HotPotChef" "$outDir/HotPotChef.apk"
Show-Apk "HotPotChef Partner" "$outDir/HotPotChef-Partner.apk"

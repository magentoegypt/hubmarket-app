# run-android.ps1 — build, install (MIUI-safe), launch, and attach for hot reload.
#
# The Xiaomi/MIUI test phone rejects `flutter run`'s streamed install
# (INSTALL_FAILED_USER_RESTRICTED). This script installs via `adb push` + `pm install`
# instead, then `flutter attach` gives you the normal hot-reload session (press r / R / q).
#
# Usage:
#   .\tool\run-android.ps1                # dev flavor, auto-detects the only wireless device
#   .\tool\run-android.ps1 -Flavor staging
#   .\tool\run-android.ps1 -DeviceId adb-xxxx._adb-tls-connect._tcp

param(
  [string]$Flavor = "dev",
  [string]$DeviceId = ""
)

$ErrorActionPreference = "Stop"

# --- toolchain env (standalone install; see memory: android-toolchain-windows) ---
$env:JAVA_HOME = "C:\Program Files\Microsoft\jdk-17.0.19.10-hotspot"
$env:ANDROID_HOME = "C:\Android\Sdk"
$env:ANDROID_SDK_ROOT = "C:\Android\Sdk"
$env:Path = "$env:JAVA_HOME\bin;" + [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$config = "config\$Flavor.json"
if (-not (Test-Path $config)) { throw "Config not found: $config" }

# app id: com.hubmarket.app + .<flavor> suffix (prod has no suffix)
$appId = if ($Flavor -eq "prod") { "com.hubmarket.app" } else { "com.hubmarket.app.$Flavor" }
$apk   = "build\app\outputs\flutter-apk\app-$Flavor-debug.apk"

# resolve device if not given
if (-not $DeviceId) {
  $line = (adb devices | Select-String "_adb-tls-connect._tcp|device$" | Where-Object { $_ -notmatch "List of" } | Select-Object -First 1)
  if (-not $line) { throw "No adb device found. Connect the phone over WiFi first (adb connect ...)." }
  $DeviceId = ($line -split "\s+")[0]
}
Write-Host "Device : $DeviceId"  -ForegroundColor Cyan
Write-Host "Flavor : $Flavor ($appId)" -ForegroundColor Cyan

Write-Host "`n[1/5] Building debug APK..." -ForegroundColor Yellow
flutter build apk --debug --flavor $Flavor --dart-define-from-file=$config

Write-Host "`n[2/5] Pushing APK to device..." -ForegroundColor Yellow
adb -s $DeviceId push $apk /data/local/tmp/hubmarket-$Flavor.apk

Write-Host "`n[3/5] Installing via pm install (MIUI-safe)..." -ForegroundColor Yellow
adb -s $DeviceId shell pm install -r -t -g /data/local/tmp/hubmarket-$Flavor.apk
adb -s $DeviceId shell rm /data/local/tmp/hubmarket-$Flavor.apk

Write-Host "`n[4/5] Launching app..." -ForegroundColor Yellow
adb -s $DeviceId shell monkey -p $appId -c android.intent.category.LAUNCHER 1 | Out-Null

Write-Host "`n[5/5] Attaching for hot reload (press r = reload, R = restart, q = quit)..." -ForegroundColor Yellow
flutter attach -d $DeviceId

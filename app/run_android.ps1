# Reliable Flutter run — bypasses Cursor Run button when the IDE extension is stuck.
Set-Location $PSScriptRoot

$devices = flutter devices --machine 2>$null | ConvertFrom-Json
$android = $devices | Where-Object { $_.targetPlatform -like 'android*' } | Select-Object -First 1

if (-not $android) {
  Write-Host "No Android device found. Launching Pixel_9 emulator..."
  flutter emulators --launch Pixel_9
  Start-Sleep -Seconds 12
  $devices = flutter devices --machine 2>$null | ConvertFrom-Json
  $android = $devices | Where-Object { $_.targetPlatform -like 'android*' } | Select-Object -First 1
}

if (-not $android) {
  Write-Error "Still no Android device. Open Android Studio AVD Manager and start an emulator, then re-run this script."
  exit 1
}

Write-Host "Running on $($android.name) ($($android.id))..."
flutter run -d $android.id --dart-define-from-file=config/local.json

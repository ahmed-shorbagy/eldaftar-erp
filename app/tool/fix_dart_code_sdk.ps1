# Re-apply after `flutter upgrade` if Cursor says "Could not find Dart in your Flutter SDK".
$snapDir = "C:\flutter\bin\cache\dart-sdk\bin\snapshots"
$aot = Join-Path $snapDir "analysis_server_aot.dart.snapshot"
$legacy = Join-Path $snapDir "analysis_server.dart.snapshot"
if (-not (Test-Path $aot)) { Write-Error "AOT snapshot missing. Run: flutter doctor"; exit 1 }
if (-not (Test-Path $legacy)) {
  New-Item -ItemType HardLink -Path $legacy -Target $aot -Force | Out-Null
  Write-Host "Restored analysis_server.dart.snapshot hardlink for Dart-Code."
} else {
  Write-Host "Legacy snapshot already present."
}

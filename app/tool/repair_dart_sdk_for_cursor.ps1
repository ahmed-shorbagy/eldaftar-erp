# Repair Cursor/VS Code Dart detection after Flutter upgrades.
# Dart-Code still looks for analysis_server.dart.snapshot; newer Flutter
# only ships analysis_server_aot.dart.snapshot.
$snapDir = "C:\flutter\bin\cache\dart-sdk\bin\snapshots"
$aot = Join-Path $snapDir "analysis_server_aot.dart.snapshot"
$legacy = Join-Path $snapDir "analysis_server.dart.snapshot"
if (-not (Test-Path $aot)) {
  Write-Error "Missing $aot — run: flutter doctor"
  exit 1
}
if (-not (Test-Path $legacy)) {
  try { New-Item -ItemType HardLink -Path $legacy -Target $aot -Force | Out-Null }
  catch { Copy-Item $aot $legacy -Force }
  Write-Host "Created $legacy"
} else {
  Write-Host "Already present: $legacy"
}
Write-Host "Reload Cursor window (Ctrl+Shift+P -> Developer: Reload Window)"

# Apply pricing then M3 on a unique disposable local DB and run rollback SQL suites.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$hostName = '127.0.0.1'
$port = '55432'
$user = 'postgres'
$pgBin = $env:ELDAFTTAR_PG_BIN
if ([string]::IsNullOrWhiteSpace($pgBin)) {
  $pgBin = Join-Path $env:TEMP 'eldafttar-postgres17\pgsql\bin'
}
$psql = Join-Path $pgBin 'psql.exe'
$createdb = Join-Path $pgBin 'createdb.exe'
$dropdb = Join-Path $pgBin 'dropdb.exe'
foreach ($bin in @($psql, $createdb, $dropdb)) {
  if (-not (Test-Path -LiteralPath $bin)) { throw "postgres binary missing: $bin" }
}

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$m3 = Join-Path $repo 'supabase\migrations\20261004081229_milestone_3_inventory_contract.sql'
if (-not (Test-Path -LiteralPath $m3)) { throw "safe repository root required: missing $m3" }

$unique = -join ((1..8) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
$db = "eldafttar_m3r_$unique"
if ($db -cnotmatch '^eldafttar_m3r_[0-9a-f]{8}$') { throw "db name failed guard: $db" }
$forbidden = @('eldafttar_test', 'eldafttar_backend_test', 'eldafttar_notes_test', 'postgres', 'template0', 'template1')
if ($forbidden -contains $db) { throw "forbidden database $db" }

$tempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
$taskdir = Join-Path $tempRoot "eldafttar-m3t-$unique"
New-Item -ItemType Directory -Force -Path $taskdir | Out-Null
$taskdirResolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $taskdir).Path).TrimEnd('\')
if (-not $taskdirResolved.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "taskdir outside TEMP"
}

function Invoke-Psql {
  param([string]$Database, [string]$File, [string]$Command)
  $argList = @('-h', $hostName, '-p', $port, '-U', $user, '-d', $Database, '-X', '-v', 'ON_ERROR_STOP=1')
  if ($File) { $argList += @('-f', $File) }
  if ($Command) { $argList += @('-c', $Command) }
  & $psql @argList
  if ($LASTEXITCODE -ne 0) { throw "psql failed (exit $LASTEXITCODE)" }
}

$createdDb = $false
try {
  $exists = & $psql @('-h', $hostName, '-p', $port, '-U', $user, '-d', 'postgres', '-X', '-t', '-A', '-c', "select coalesce((select 1 from pg_database where datname = '$db'), 0)")
  if (([string]$exists).Trim() -ne '0') { throw "database $db already exists; refusing to drop it" }
  Write-Host "Creating disposable $db"
  & $createdb @('-h', $hostName, '-p', $port, '-U', $user, $db)
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  $createdDb = $true

  $bootstrap = Get-Content -LiteralPath (Join-Path $repo 'supabase\tests\local_auth_bootstrap.sql') -Raw
  $bootstrap = $bootstrap.Replace("current_database() <> 'eldafttar_test'", "current_database() <> '$db'")
  $bootFile = Join-Path $taskdir 'bootstrap.sql'
  Set-Content -LiteralPath $bootFile -Value $bootstrap -Encoding utf8
  Invoke-Psql $db $bootFile $null

  $m3Name = '20261004081229_milestone_3_inventory_contract.sql'
  $files = @(Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*.sql' | Where-Object { $_.Length -gt 0 } | Sort-Object Name)
  foreach ($file in $files) {
    Write-Host "Applying $($file.Name)"
    Invoke-Psql $db $file.FullName $null
  }

  $tests = @(
    'identity_rls.sql', 'identity_commands.sql', 'egypt_owner_registration.sql',
    'opening_balances.sql', 'opening_rls.sql', 'daily_ledger_trades.sql',
    'invoice_price_components.sql', 'milestone_3_inventory.sql', 'milestone_3_inventory_rls.sql'
  )
  foreach ($name in $tests) {
    Write-Host "===== $name ====="
    Invoke-Psql $db (Join-Path $repo "supabase\tests\$name") $null
    Write-Host "PASSED $name"
  }
  Write-Host "hosted_order_sql_suites_passed db=$db"
}
finally {
  if ($createdDb) {
    if ($db -cnotmatch '^eldafttar_m3r_[0-9a-f]{8}$') { throw "refusing drop of $db" }
    & $dropdb @('-h', $hostName, '-p', $port, '-U', $user, '--if-exists', $db)
    Write-Host "Dropped owned disposable $db"
  }
  if ($taskdirResolved.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -and
      (Split-Path -Leaf $taskdirResolved).StartsWith('eldafttar-m3t-')) {
    Remove-Item -LiteralPath $taskdirResolved -Recurse -Force -ErrorAction SilentlyContinue
  }
}


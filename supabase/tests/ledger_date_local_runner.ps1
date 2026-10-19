# Disposable local Postgres for historical ledger-date reads.
# Never drops a pre-existing database and never uses an ordinary port.
param(
  [string]$Database = $(if ($env:ELDAFTAR_LEDGER_DATE_DB) { $env:ELDAFTAR_LEDGER_DATE_DB } else { 'eldaftar_ledger_date' }),
  [int]$Port = $(if ($env:ELDAFTAR_LEDGER_DATE_PORT) { [int]$env:ELDAFTAR_LEDGER_DATE_PORT } else { 55468 })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ordinary = @(
  'postgres', 'template0', 'template1',
  'eldafttar_test', 'eldafttar_backend_test', 'eldafttar_notes_test', 'eldafttar_complete_test'
)
if ($ordinary -contains $Database -or $Database -notmatch '^eldaftar_ledger_date[a-z0-9_]*$') {
  throw "refusing ordinary or non-dedicated database name $Database"
}
if ($Port -ne 55468) {
  throw "refusing ordinary or non-dedicated port $Port"
}

$serverBin = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\bin'
$clientBin = Join-Path $env:TEMP 'eldaftar-pg-client'
$psql = Join-Path $clientBin 'psql.exe'
$initdb = Join-Path $serverBin 'initdb.exe'
$pgctl = Join-Path $serverBin 'pg_ctl.exe'
$createdb = Join-Path $clientBin 'createdb.exe'
$readyExe = Join-Path $clientBin 'pg_isready.exe'
foreach ($bin in @($psql, $initdb, $pgctl, $createdb, $readyExe)) {
  if (-not (Test-Path -LiteralPath $bin)) { throw "postgres binary missing: $bin" }
}
$riyadh = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\share\timezone\Asia\Riyadh'
$cairo = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\share\timezone\Africa\Cairo'
$kiritimati = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\share\timezone\Pacific\Kiritimati'
$pago = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\share\timezone\Pacific\Pago_Pago'
foreach ($zoneFile in @($riyadh, $cairo, $kiritimati, $pago)) {
  if (-not (Test-Path -LiteralPath $zoneFile)) { throw "restored timezone file missing: $zoneFile" }
}

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$migrationName = '20261019184500_ledger_date_read.sql'
$migration = Join-Path $repo "supabase\migrations\$migrationName"
if (-not (Test-Path -LiteralPath $migration)) { throw "migration missing: $migration" }
$migrationHash = (Get-FileHash -LiteralPath $migration -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "MIGRATION_SHA256 $migrationHash"

$env:PGCLIENTENCODING = 'UTF8'
$data = Join-Path $env:TEMP "eldaftar-ledger-date-pg\p$Port\data"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $data) | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
  & $initdb -D $data -U postgres -A trust -E UTF8 --locale=C --lc-messages=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
}

$startedHere = $false
$listen = & $readyExe -h 127.0.0.1 -p $Port
if ($LASTEXITCODE -eq 0) {
  $pidFile = Join-Path $data 'postmaster.pid'
  if (-not (Test-Path -LiteralPath $pidFile)) { throw "port $Port is in use by a foreign server" }
  $pidLines = Get-Content -LiteralPath $pidFile
  if ($pidLines.Count -lt 4 -or $pidLines[3] -ne "$Port") {
    throw "dedicated data directory is not the listener on port $Port"
  }
} else {
  & $pgctl -D $data -l (Join-Path (Split-Path -Parent $data) 'postgres.log') -o "-p $Port -h 127.0.0.1" start
  if ($LASTEXITCODE -ne 0) { throw 'pg_ctl start failed' }
  $startedHere = $true
  $listen = & $readyExe -h 127.0.0.1 -p $Port
  if ($LASTEXITCODE -ne 0) { throw 'postgres did not become ready' }
}

try {
  function Invoke-PsqlFile([string]$DatabaseName, [string]$File) {
    & $psql -h 127.0.0.1 -p $Port -U postgres -d $DatabaseName -X -v ON_ERROR_STOP=1 -f $File
    if ($LASTEXITCODE -ne 0) { throw "psql failed for $File on $DatabaseName" }
  }

  function Invoke-PsqlScalar([string]$DatabaseName, [string]$Command) {
    $out = & $psql -h 127.0.0.1 -p $Port -U postgres -d $DatabaseName -X -t -A -v ON_ERROR_STOP=1 -c $Command
    if ($LASTEXITCODE -ne 0) { throw "psql scalar failed: $Command" }
    return ([string]$out).Trim()
  }

  $zoneProbe = Invoke-PsqlScalar 'postgres' "select to_char(timestamptz '2026-01-17 22:30:00+00' at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI') || '|' || to_char(timestamptz '2026-01-17 22:30:00+00' at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI') || '|' || ((timestamptz '2026-06-15 12:00:00+00' at time zone 'Pacific/Kiritimati')::date - (timestamptz '2026-06-15 12:00:00+00' at time zone 'Pacific/Pago_Pago')::date)::text"
  Write-Host "ZONE_PROBE $zoneProbe"
  if ($zoneProbe -ne '2026-01-18 01:30|2026-01-18 00:30|1') { throw "timezone probe mismatch: $zoneProbe" }

  $exists = Invoke-PsqlScalar 'postgres' "select coalesce((select 1 from pg_database where datname = '$Database'), 0)"
  if ($exists -eq '0') {
    & $createdb -h 127.0.0.1 -p $Port -U postgres $Database
    if ($LASTEXITCODE -ne 0) { throw "createdb failed for $Database" }
  }

  $task = Join-Path $env:TEMP "eldaftar-ledger-date-boot\$Database"
  New-Item -ItemType Directory -Force -Path $task | Out-Null
  $auth = (Get-Content -LiteralPath (Join-Path $repo 'supabase\tests\local_auth_bootstrap.sql') -Raw).Replace("current_database() <> 'eldafttar_test'", "current_database() <> '$Database'")
  $storage = (Get-Content -LiteralPath (Join-Path $repo 'supabase\tests\local_storage_bootstrap.sql') -Raw).Replace("current_database() is distinct from 'eldafttar_notes_test'", "current_database() is distinct from '$Database'")
  $authPath = Join-Path $task 'auth.sql'
  $storagePath = Join-Path $task 'storage.sql'
  Set-Content -LiteralPath $authPath -Value $auth -Encoding utf8NoBOM
  Set-Content -LiteralPath $storagePath -Value $storage -Encoding utf8NoBOM

  $applied = Invoke-PsqlScalar $Database "select to_regclass('public.shops') is not null"
  if ($applied -eq 'f' -or $applied -eq 'false') {
    Invoke-PsqlFile $Database $authPath
    Invoke-PsqlFile $Database $storagePath
    Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*.sql' |
      Sort-Object Name |
      Where-Object { $_.Name -lt $migrationName } |
      ForEach-Object { Write-Host $_.Name; Invoke-PsqlFile $Database $_.FullName }
  }

  $hasRead = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_ledger_date_v1(date,text,integer)') is not null and to_regclass('public.business_days_shop_business_date_idx') is not null"
  if ($hasRead -eq 'f' -or $hasRead -eq 'false') {
    $partial = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_ledger_date_v1(date,text,integer)') is not null or to_regclass('public.business_days_shop_business_date_idx') is not null"
    if ($partial -eq 't' -or $partial -eq 'true') { throw 'partial ledger date objects; inspect dedicated database' }
    $rollback = (Get-Content -LiteralPath $migration -Raw) -replace '(?s)\r?\ncommit;\s*$', "`r`nrollback;`r`n"
    $rollbackPath = Join-Path $task 'ledger-date-rollback.sql'
    Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
    Invoke-PsqlFile $Database $rollbackPath
    $rolledBack = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_ledger_date_v1(date,text,integer)') is null and to_regclass('public.business_days_shop_business_date_idx') is null"
    if ($rolledBack -ne 't' -and $rolledBack -ne 'true') { throw 'rollback left ledger date objects' }
    Write-Host 'MIGRATION_ROLLBACK_PASSED'
    Invoke-PsqlFile $Database $migration
    Write-Host 'MIGRATION_APPLY_PASSED'
  }

  Write-Host 'LEDGER_DATE_SQL'
  Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\ledger_date_read.sql')
  Write-Host 'DAILY_LEDGER_TRADES_SQL'
  Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\daily_ledger_trades.sql')
  Write-Host 'IDENTITY_RLS_SQL'
  Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\identity_rls.sql')
  Write-Host 'SHOP_SYNC_SQL'
  Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\shop_sync_signals.sql')
  Write-Host 'SKIP_DAILY_NOTES_PAGINATION database allowlist is eldafttar_notes_test or eldafttar_complete_test'
  if ((Get-FileHash -LiteralPath $migration -Algorithm SHA256).Hash.ToLowerInvariant() -ne $migrationHash) {
    throw 'migration changed during validation'
  }
  Write-Host 'ALL_LOCAL_SQL_PASSED'
} finally {
  if ($startedHere) {
    & $pgctl -D $data -m fast -w stop
    if ($LASTEXITCODE -ne 0) { throw 'task-created local cluster stop failed' }
    Write-Host 'LOCAL_CLUSTER_STOPPED_DATA_RETAINED'
  }
}

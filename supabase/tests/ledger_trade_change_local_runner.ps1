# Disposable local Postgres for sale/purchase edit and delete. Never drops a
# pre-existing database and never connects to an ordinary or hosted database.
param(
  [string]$Database = $(if ($env:ELDAFTAR_TRADE_CHANGE_DB) { $env:ELDAFTAR_TRADE_CHANGE_DB } else { 'eldaftar_trade_change' }),
  [int]$Port = $(if ($env:ELDAFTAR_TRADE_CHANGE_PORT) { [int]$env:ELDAFTAR_TRADE_CHANGE_PORT } else { 55469 })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$env:PGCLIENTENCODING = 'UTF8'

$ordinary = @('postgres', 'template0', 'template1', 'eldafttar_test', 'eldafttar_backend_test', 'eldafttar_notes_test')
if ($ordinary -contains $Database -or $Database -notmatch '^eldaftar_trade_change[a-z0-9_]*$') {
  throw "refusing ordinary or non-dedicated database name $Database"
}
if ($Port -ne 55469) {
  throw "refusing port $Port; this runner is pinned to 55469"
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
if (-not (Test-Path -LiteralPath $riyadh) -or -not (Test-Path -LiteralPath $cairo)) {
  throw 'restored timezone files missing beside extracted bin'
}

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$migration = Join-Path $repo 'supabase\migrations\20261019230000_ledger_trade_edit_delete.sql'
$dateMigration = Join-Path $repo 'supabase\migrations\20261019184500_ledger_date_read.sql'
if (-not (Test-Path -LiteralPath $migration)) { throw "migration missing: $migration" }
if (-not (Test-Path -LiteralPath $dateMigration)) { throw "date migration missing: $dateMigration" }
$dateText = Get-Content -LiteralPath $dateMigration -Raw
if ($dateText -notmatch '(?s)\r?\ncommit;\s*$') {
  throw 'date-read migration is not finished with commit; this runner will not edit it'
}

$migrationHash = (Get-FileHash -LiteralPath $migration -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "MIGRATION_SHA256 $migrationHash"

$data = Join-Path $env:TEMP 'eldaftar-trade-change-pg\data'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $data) | Out-Null
if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
  & $initdb -D $data -U postgres -A trust -E UTF8 --locale=C --lc-messages=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
}

$startedHere = $false
$listen = & $readyExe -h 127.0.0.1 -p $Port
if ($LASTEXITCODE -ne 0) {
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

$zoneProbe = Invoke-PsqlScalar 'postgres' "select to_char(timestamptz '2026-01-17 22:30:00+00' at time zone 'Asia/Riyadh', 'YYYY-MM-DD HH24:MI') || '|' || to_char(timestamptz '2026-01-17 22:30:00+00' at time zone 'Africa/Cairo', 'YYYY-MM-DD HH24:MI')"
Write-Host "ZONE_PROBE $zoneProbe"
if ($zoneProbe -ne '2026-01-18 01:30|2026-01-18 00:30') { throw "timezone probe mismatch: $zoneProbe" }

$exists = Invoke-PsqlScalar 'postgres' "select coalesce((select 1 from pg_database where datname = '$Database'), 0)"
if ($exists -eq '0') {
  & $createdb -h 127.0.0.1 -p $Port -U postgres $Database
  if ($LASTEXITCODE -ne 0) { throw "createdb failed for $Database" }
}

$task = Join-Path $env:TEMP "eldaftar-trade-change-boot\$Database"
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
    Where-Object { $_.Name -lt '20261019230000_ledger_trade_edit_delete.sql' } |
    ForEach-Object {
      if ($_.Name -eq '20261019184500_ledger_date_read.sql') {
        $dateRollback = (Get-Content -LiteralPath $_.FullName -Raw) -replace '(?s)\r?\ncommit;\s*$', "`r`nrollback;`r`n"
        $dateRollbackPath = Join-Path $task 'date-rollback.sql'
        Set-Content -LiteralPath $dateRollbackPath -Value $dateRollback -Encoding utf8NoBOM
        Invoke-PsqlFile $Database $dateRollbackPath
        $dateClean = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_ledger_date_v1(date,text,integer)') is null and to_regclass('public.business_days_shop_business_date_idx') is null"
        if ($dateClean -ne 't' -and $dateClean -ne 'true') { throw 'date rollback left objects' }
        Write-Host 'DATE_MIGRATION_ROUNDTRIP_PASSED'
      }
      Write-Host $_.Name
      Invoke-PsqlFile $Database $_.FullName
    }
}

$dateReady = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_ledger_date_v1(date,text,integer)') is not null"
if ($dateReady -ne 't' -and $dateReady -ne 'true') {
  throw 'get_ledger_date_v1 is absent. Use a fresh eldaftar_trade_change database suffix instead of editing the date-read migration.'
}

$hasTrade = Invoke-PsqlScalar $Database "select to_regclass('public.ledger_trade_changes') is not null"
if ($hasTrade -eq 'f' -or $hasTrade -eq 'false') {
  $rollback = (Get-Content -LiteralPath $migration -Raw) -replace '(?s)\r?\ncommit;\s*$', "`r`nrollback;`r`n"
  $rollbackPath = Join-Path $task 'trade-change-rollback.sql'
  Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
  Invoke-PsqlFile $Database $rollbackPath
  $rolledBack = Invoke-PsqlScalar $Database "select to_regclass('public.ledger_trade_changes') is null and to_regprocedure('public.review_ledger_trade_change_v1(uuid,text,jsonb)') is null and has_function_privilege('authenticated', 'public.post_linked_return_v1(uuid,jsonb)', 'execute')"
  if ($rolledBack -ne 't' -and $rolledBack -ne 'true') { throw 'rollback left trade-change objects or revoked return writes' }
  Write-Host 'MIGRATION_ROLLBACK_PASSED'
  Invoke-PsqlFile $Database $migration
  Write-Host 'MIGRATION_APPLY_PASSED'
}


$cacheMigration = Join-Path $repo 'supabase\migrations\20261019233000_ledger_trade_cache_revision.sql'
$cacheHash = (Get-FileHash -LiteralPath $cacheMigration -Algorithm SHA256).Hash
$cacheReady = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_daily_ledger_v2_before_trade_cache()') is not null"
if ($cacheReady -ne 't' -and $cacheReady -ne 'true') {
  $cacheRollback = (Get-Content -LiteralPath $cacheMigration -Raw) -replace '(?s)\r?\ncommit;\s*$', "`r`nrollback;`r`n"
  $cacheRollbackPath = Join-Path $task 'cache-rollback.sql'
  Set-Content -LiteralPath $cacheRollbackPath -Value $cacheRollback -Encoding utf8NoBOM
  Invoke-PsqlFile $Database $cacheRollbackPath
  $cacheClean = Invoke-PsqlScalar $Database "select to_regprocedure('public.get_daily_ledger_v2_before_trade_cache()') is null"
  if ($cacheClean -ne 't' -and $cacheClean -ne 'true') { throw 'cache rollback left objects' }
  Invoke-PsqlFile $Database $cacheMigration
  Write-Host 'CACHE_MIGRATION_ROUNDTRIP_PASSED'
}
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\ledger_trade_cache_revision.sql')
$revoked = Invoke-PsqlScalar $Database "select not has_function_privilege('authenticated', 'public.post_linked_return_v1(uuid,jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.post_exchange_v1(uuid,jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.post_daily_ledger_return(uuid,uuid,text)', 'execute') and has_function_privilege('authenticated', 'public.review_ledger_trade_change_v1(uuid,text,jsonb)', 'execute') and has_function_privilege('authenticated', 'public.post_ledger_trade_change_v1(uuid,uuid,text,jsonb,uuid,bigint,text,text)', 'execute')"
if ($revoked -ne 't' -and $revoked -ne 'true') { throw 'authenticated return privileges were not replaced by trade-change execute' }
Write-Host 'PRIVILEGE_SHAPE_PASSED'

Write-Host 'LEDGER_TRADE_CHANGE_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\ledger_trade_change.sql')
Write-Host 'LEDGER_TRADE_CHANGE_CONCURRENCY'
$env:SUPABASE_TEST_DATABASE_URL = "postgresql://postgres@127.0.0.1:${Port}/${Database}"
$env:PSQL = $psql
node (Join-Path $repo 'supabase\tests\ledger_trade_change_concurrency.mjs')
if ($LASTEXITCODE -ne 0) { throw 'trade change concurrency failed' }

Write-Host 'LEDGER_COMPENSATION_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\ledger_compensation.sql')
Write-Host 'LEDGER_COMPENSATION_EDGES_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\ledger_compensation_edges.sql')
Write-Host 'DAILY_LEDGER_TRADES_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\daily_ledger_trades.sql')
Write-Host 'CUSTOMER_STATISTICS_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\customer_statistics.sql')
Write-Host 'DEBTS_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\debts.sql')
Write-Host 'LEDGER_DATE_SQL_FINAL_SCHEMA'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\ledger_date_read.sql')

if ((Get-FileHash -LiteralPath $migration -Algorithm SHA256).Hash.ToLowerInvariant() -ne $migrationHash) {
  throw 'migration changed during validation'
}
if ((Get-FileHash -LiteralPath $cacheMigration -Algorithm SHA256).Hash -ne $cacheHash) { throw 'cache migration changed during validation' }
Write-Host 'ALL_LOCAL_SQL_PASSED'
} finally {
  if ($startedHere) {
    & $pgctl -D $data -m fast -w stop
    if ($LASTEXITCODE -ne 0) { throw 'task-created local cluster stop failed' }
    Write-Host 'LOCAL_CLUSTER_STOPPED_DATA_RETAINED'
  }
}

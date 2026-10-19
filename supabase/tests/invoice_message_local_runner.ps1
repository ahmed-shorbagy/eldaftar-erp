# Disposable local Postgres for invoice message SQL. Never drops a pre-existing database.
param(
  [string]$Database = $(if ($env:ELDAFTAR_INVOICE_MESSAGE_DB) { $env:ELDAFTAR_INVOICE_MESSAGE_DB } else { 'eldaftar_invoice_message' }),
  [int]$Port = $(if ($env:ELDAFTAR_INVOICE_MESSAGE_PORT) { [int]$env:ELDAFTAR_INVOICE_MESSAGE_PORT } else { 55462 })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ordinary = @('postgres', 'template0', 'template1', 'eldafttar_test', 'eldafttar_backend_test', 'eldafttar_notes_test')
if ($ordinary -contains $Database -or $Database -notmatch '^eldaftar_invoice_message[a-z0-9_]*$') {
  throw "refusing ordinary or non-dedicated database name $Database"
}
if ($Port -lt 1024 -or $Port -gt 65535 -or $Port -eq 5432 -or $Port -eq 54322) {
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
if (-not (Test-Path -LiteralPath $riyadh) -or -not (Test-Path -LiteralPath $cairo)) {
  throw 'restored timezone files missing beside extracted bin'
}

$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$migration = Join-Path $repo 'supabase\migrations\20261018075947_invoice_message_templates.sql'
if (-not (Test-Path -LiteralPath $migration)) { throw "migration missing: $migration" }

$reviewedMessageHash = (Get-FileHash -LiteralPath $migration -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "MIGRATION_SHA256 $reviewedMessageHash"
$actorIndexes = Join-Path $repo 'supabase\migrations\20261019063514_invoice_message_actor_indexes.sql'
$actorIndexesHash = (Get-FileHash -LiteralPath $actorIndexes -Algorithm SHA256).Hash.ToLowerInvariant()
Write-Host "ACTOR_INDEXES_SHA256 $actorIndexesHash"

if ($Port -eq 55462) {
  $data = Join-Path $env:TEMP 'eldaftar-invoice-message-pg\data'
} else {
  $data = Join-Path $env:TEMP "eldaftar-invoice-message-pg\p$Port\data"
}
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

$task = Join-Path $env:TEMP "eldaftar-invoice-message-boot\$Database"
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
    Where-Object { $_.Name -lt '20261018075947_invoice_message_templates.sql' } |
    ForEach-Object { Write-Host $_.Name; Invoke-PsqlFile $Database $_.FullName }
}

$hasMessage = Invoke-PsqlScalar $Database "select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'shop_sync_signals' and column_name = 'message_revision')"
if ($hasMessage -eq 'f' -or $hasMessage -eq 'false') {
  $rollback = (Get-Content -LiteralPath $migration -Raw) -replace '(?s)\r?\ncommit;\s*$', "`r`nrollback;`r`n"
  $rollbackPath = Join-Path $task 'message-rollback.sql'
  Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
  Invoke-PsqlFile $Database $rollbackPath
  $still = Invoke-PsqlScalar $Database "select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'shop_sync_signals' and column_name = 'message_revision')"
  if ($still -eq 't' -or $still -eq 'true') { throw 'rollback left message_revision' }
  $rolledBack = Invoke-PsqlScalar $Database "select to_regclass('public.invoice_message_revisions') is null and to_regprocedure('public.get_invoice_message_v1()') is null"
  if ($rolledBack -ne 't' -and $rolledBack -ne 'true') { throw 'rollback left message objects' }
  Write-Host 'MIGRATION_ROLLBACK_PASSED'
  Invoke-PsqlFile $Database $migration
  Write-Host 'MIGRATION_APPLY_PASSED'
}

$hasActorIndexes = Invoke-PsqlScalar $Database "select to_regclass('public.invoice_message_revisions_actor_idx') is not null and to_regclass('public.invoice_message_audits_actor_idx') is not null"
if ($hasActorIndexes -eq 'f' -or $hasActorIndexes -eq 'false') {
  $partialActorIndexes = Invoke-PsqlScalar $Database "select to_regclass('public.invoice_message_revisions_actor_idx') is not null or to_regclass('public.invoice_message_audits_actor_idx') is not null"
  if ($partialActorIndexes -eq 't' -or $partialActorIndexes -eq 'true') { throw 'partial actor indexes; inspect dedicated database' }
  $actorRollback = (Get-Content -LiteralPath $actorIndexes -Raw) -replace '(?s)\r?\ncommit;\s*$', "`r`nrollback;`r`n"
  $actorRollbackPath = Join-Path $task 'message-actor-indexes-rollback.sql'
  Set-Content -LiteralPath $actorRollbackPath -Value $actorRollback -Encoding utf8NoBOM
  Invoke-PsqlFile $Database $actorRollbackPath
  $actorRolledBack = Invoke-PsqlScalar $Database "select to_regclass('public.invoice_message_revisions_actor_idx') is null and to_regclass('public.invoice_message_audits_actor_idx') is null"
  if ($actorRolledBack -ne 't' -and $actorRolledBack -ne 'true') { throw 'rollback left actor indexes' }
  Write-Host 'ACTOR_INDEXES_ROLLBACK_PASSED'
  Invoke-PsqlFile $Database $actorIndexes
  Write-Host 'ACTOR_INDEXES_APPLY_PASSED'
}
$actorCoverage = Invoke-PsqlScalar $Database "select count(*) = 2 from pg_constraint c where c.conname in ('invoice_message_revisions_actor_fkey', 'invoice_message_audits_actor_fkey') and c.connamespace = 'public'::regnamespace and exists (select 1 from pg_index i where i.indrelid = c.conrelid and i.indisvalid and i.indisready and i.indpred is null and i.indexprs is null and i.indkey[0] = c.conkey[1] and i.indkey[1] = c.conkey[2])"
if ($actorCoverage -ne 't' -and $actorCoverage -ne 'true') { throw 'actor foreign keys lack covering indexes' }
Write-Host 'ACTOR_INDEXES_COVERAGE_PASSED'

Write-Host 'INVOICE_MESSAGE_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\invoice_message.sql')
Write-Host 'INVOICE_MESSAGE_CONCURRENCY'
$env:SUPABASE_TEST_DATABASE_URL = "postgresql://postgres@127.0.0.1:${Port}/${Database}"
$env:PSQL = $psql
node (Join-Path $repo 'supabase\tests\invoice_message_concurrency.mjs')
if ($LASTEXITCODE -ne 0) { throw 'concurrency failed' }
Write-Host 'INVOICE_APPEARANCE_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\invoice_appearance.sql')
Write-Host 'SHOP_SYNC_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\shop_sync_signals.sql')
Write-Host 'DAILY_LEDGER_TRADES_SQL'
Invoke-PsqlFile $Database (Join-Path $repo 'supabase\tests\daily_ledger_trades.sql')
if ((Get-FileHash -LiteralPath $migration -Algorithm SHA256).Hash.ToLowerInvariant() -ne $reviewedMessageHash) { throw 'migration changed during validation' }
if ((Get-FileHash -LiteralPath $actorIndexes -Algorithm SHA256).Hash.ToLowerInvariant() -ne $actorIndexesHash) { throw 'actor indexes changed during validation' }
Write-Host 'ALL_LOCAL_SQL_PASSED'
} finally {
  if ($startedHere) {
    & $pgctl -D $data -m fast -w stop
    if ($LASTEXITCODE -ne 0) { throw 'task-created local cluster stop failed' }
    Write-Host 'LOCAL_CLUSTER_STOPPED_DATA_RETAINED'
  }
}

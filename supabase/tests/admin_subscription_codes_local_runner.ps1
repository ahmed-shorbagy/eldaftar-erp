# Requires a fresh database suffix. An existing database is left in place.
param(
  [Parameter(Mandatory = $true)]
  [string]$Database
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Database -notmatch '^eldaftar_admin_subscription_codes_[a-z0-9_]+$') { throw 'dedicated database required' }
$port = 55475
$env:PGCLIENTENCODING = 'UTF8'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$server = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\bin'
$client = Join-Path $env:TEMP 'eldaftar-pg-client'
$psql = Join-Path $client 'psql.exe'
$pgctl = Join-Path $server 'pg_ctl.exe'
$ready = Join-Path $client 'pg_isready.exe'
$task = Join-Path $env:TEMP 'eldaftar-admin-subscription-codes-pg'
$data = Join-Path $task 'data'
New-Item -ItemType Directory -Force -Path $task | Out-Null
& $ready -h 127.0.0.1 -p $port
if ($LASTEXITCODE -eq 0) { throw 'port already occupied; refusing to use an unknown cluster' }
if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
  & (Join-Path $server 'initdb.exe') -D $data -U postgres -A trust -E UTF8 --locale=C --lc-messages=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
}
$startStdout = Join-Path $task 'pg-start.stdout'
$startStderr = Join-Path $task 'pg-start.stderr'
$startArguments = @('-D',"`"$data`"",'-l',"`"$(Join-Path $task 'postgres.log')`"",'-o',"`"-p $port -h 127.0.0.1`"",'-w','start')
$startProcess = Start-Process -FilePath $pgctl -ArgumentList $startArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $startStdout -RedirectStandardError $startStderr
if (-not $startProcess.WaitForExit(30000)) { throw 'local cluster startup timed out' }
if ($startProcess.ExitCode -ne 0) { throw "local cluster failed to start: $(Get-Content -LiteralPath $startStderr -Raw)" }
Get-Content -LiteralPath $startStdout | Write-Host
$startProcess.Dispose()
try {
  function Scalar([string]$db, [string]$sql) {
    $value = & $psql -h 127.0.0.1 -p $port -U postgres -d $db -X -t -A -v ON_ERROR_STOP=1 -c $sql
    if ($LASTEXITCODE -ne 0) { throw 'SQL query failed' }
    return ([string]$value).Trim()
  }
  function FileSql([string]$path) {
    & $psql -h 127.0.0.1 -p $port -U postgres -d $Database -X -q -v ON_ERROR_STOP=1 -f $path
    if ($LASTEXITCODE -ne 0) { throw "SQL file failed: $path" }
  }
  $migrations = @(Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*_admin_subscription_code_issuance.sql')
  if ($migrations.Count -ne 1) { throw 'expected exactly one admin subscription-code issuance migration' }
  $target = $migrations[0].Name
  if ((Scalar 'postgres' "select count(*) from pg_database where datname='$Database'") -ne '0') {
    throw "database $Database already exists; pass a fresh suffix and leave the existing database in place"
  }
  & (Join-Path $client 'createdb.exe') -h 127.0.0.1 -p $port -U postgres $Database
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  $auth = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_auth_bootstrap.sql') -Raw).Replace("current_database() <> 'eldafttar_test'", "current_database() <> '$Database'")
  $storage = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_storage_bootstrap.sql') -Raw).Replace("current_database() is distinct from 'eldafttar_notes_test'", "current_database() is distinct from '$Database'")
  $authPath = Join-Path $task 'auth.sql'
  $storagePath = Join-Path $task 'storage.sql'
  Set-Content -LiteralPath $authPath -Value $auth -Encoding utf8NoBOM
  Set-Content -LiteralPath $storagePath -Value $storage -Encoding utf8NoBOM
  FileSql $authPath
  Scalar $Database 'alter table auth.users add column banned_until timestamptz' | Out-Null
  FileSql $storagePath
  Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*.sql' | Sort-Object Name | ForEach-Object {
    if ($_.Name -eq $target) {
      $beforeIssue = Scalar $Database "select md5(pg_get_functiondef('public.issue_subscription_code(uuid,integer,integer,uuid)'::regprocedure))"
      $beforeRedeem = Scalar $Database "select md5(pg_get_functiondef('public.redeem_subscription_code(uuid,text)'::regprocedure))"
      $beforeAdminGuard = Scalar $Database "select md5(pg_get_functiondef('private.subscription_platform_admin_session()'::regprocedure))"
      $beforeCallerGuard = Scalar $Database "select md5(pg_get_functiondef('private.caller_session_accepted()'::regprocedure))"
      $rollback = (Get-Content -LiteralPath $_.FullName -Raw) -replace '(?s)\r?\ncommit;\s*$', "`nrollback;`n"
      $rollbackPath = Join-Path $task 'admin-subscription-codes-rollback.sql'
      Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
      FileSql $rollbackPath
      if ((Scalar $Database "select to_regprocedure('public.admin_list_subscription_codes_v1(uuid,text,integer)') is null and to_regclass('private.subscription_codes_shop_issued_id_idx') is null and to_regprocedure('private.subscription_owner_session()') is null and to_regprocedure('private.subscription_session_live()') is null") -ne 't') {
        throw 'subscription-code migration rollback left objects'
      }
      $afterIssue = Scalar $Database "select md5(pg_get_functiondef('public.issue_subscription_code(uuid,integer,integer,uuid)'::regprocedure))"
      $afterRedeem = Scalar $Database "select md5(pg_get_functiondef('public.redeem_subscription_code(uuid,text)'::regprocedure))"
      $afterAdminGuard = Scalar $Database "select md5(pg_get_functiondef('private.subscription_platform_admin_session()'::regprocedure))"
      $afterCallerGuard = Scalar $Database "select md5(pg_get_functiondef('private.caller_session_accepted()'::regprocedure))"
      if ($afterIssue -ne $beforeIssue -or $afterRedeem -ne $beforeRedeem -or $afterAdminGuard -ne $beforeAdminGuard -or $afterCallerGuard -ne $beforeCallerGuard) {
        throw 'subscription-code migration rollback changed issue/redeem/guard definitions'
      }
      Write-Host 'ADMIN_SUBSCRIPTION_CODES_MIGRATION_ROLLBACK_PASSED'
    }
    FileSql $_.FullName
  }
  if ((Scalar $Database "select to_regprocedure('public.admin_list_subscription_codes_v1(uuid,text,integer)') is not null and to_regprocedure('public.issue_subscription_code(uuid,integer,integer,uuid)') is not null and to_regprocedure('private.subscription_session_live()') is not null") -ne 't') {
    throw 'subscription-code functions were not reapplied'
  }
  FileSql (Join-Path $PSScriptRoot 'subscription_redemption.sql')
  Write-Host 'SUBSCRIPTION_REDEMPTION_SQL_PASSED'
  FileSql (Join-Path $PSScriptRoot 'admin_subscription_codes.sql')
  Write-Host 'ADMIN_SUBSCRIPTION_CODES_SQL_PASSED'
  FileSql (Join-Path $PSScriptRoot 'admin_subscription_codes_hosted.sql')
  Write-Host 'ADMIN_SUBSCRIPTION_CODES_HOSTED_SQL_PASSED'
  $subscribersSql = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'admin_subscribers.sql') -Raw).Replace('eldaftar_admin_subscribers_', 'eldaftar_admin_subscription_codes_')
  $subscribersHostedSql = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'admin_subscribers_hosted.sql') -Raw).Replace('eldaftar_admin_subscribers_', 'eldaftar_admin_subscription_codes_')
  $subscribersPath = Join-Path $task 'admin-subscribers-patched.sql'
  $subscribersHostedPath = Join-Path $task 'admin-subscribers-hosted-patched.sql'
  Set-Content -LiteralPath $subscribersPath -Value $subscribersSql -Encoding utf8NoBOM
  Set-Content -LiteralPath $subscribersHostedPath -Value $subscribersHostedSql -Encoding utf8NoBOM
  FileSql $subscribersPath
  Write-Host 'ADMIN_SUBSCRIBERS_SQL_PASSED'
  FileSql $subscribersHostedPath
  Write-Host 'ADMIN_SUBSCRIBERS_HOSTED_SQL_PASSED'
  FileSql (Join-Path $PSScriptRoot 'identity_rls.sql')
  Write-Host 'IDENTITY_RLS_SQL_PASSED'
  FileSql (Join-Path $PSScriptRoot 'identity_commands.sql')
  Write-Host 'IDENTITY_COMMANDS_SQL_PASSED'
  FileSql (Join-Path $PSScriptRoot 'shop_sync_signals.sql')
  Write-Host 'SHOP_SYNC_SIGNALS_SQL_PASSED'
  $env:SUPABASE_TEST_DATABASE_URL = "postgresql://postgres@127.0.0.1:${port}/${Database}"
  $env:PSQL = $psql
  & node (Join-Path $PSScriptRoot 'admin_subscription_codes_concurrency.mjs')
  if ($LASTEXITCODE -ne 0) { throw 'concurrency regression failed' }
  Write-Host 'ADMIN_SUBSCRIPTION_CODES_CONCURRENCY_PASSED'
} finally {
  & $pgctl -D $data -m fast -w stop
  if ($LASTEXITCODE -ne 0) { throw 'local cluster stop failed' }
}

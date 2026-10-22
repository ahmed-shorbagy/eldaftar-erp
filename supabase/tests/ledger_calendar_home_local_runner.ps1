param([string]$Database = 'eldaftar_owner_meeting_calendar', [switch]$ReportsOnly)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Database -notmatch '^eldaftar_owner_meeting_[a-z0-9_]+$') { throw 'dedicated database required' }
$port = 55472
$env:PGCLIENTENCODING = 'UTF8'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$server = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\bin'
$client = Join-Path $env:TEMP 'eldaftar-pg-client'
$psql = Join-Path $client 'psql.exe'
$pgctl = Join-Path $server 'pg_ctl.exe'
$ready = Join-Path $client 'pg_isready.exe'
$task = Join-Path $env:TEMP 'eldaftar-owner-meeting-pg'
$data = Join-Path $task 'data'
New-Item -ItemType Directory -Force -Path $task | Out-Null
& $ready -h 127.0.0.1 -p $port
if ($LASTEXITCODE -eq 0) { throw 'port already occupied; refusing to use an unknown cluster' }
if (-not (Test-Path -LiteralPath (Join-Path $data 'PG_VERSION'))) {
  & (Join-Path $server 'initdb.exe') -D $data -U postgres -A trust -E UTF8 --locale=C --lc-messages=C
  if ($LASTEXITCODE -ne 0) { throw 'initdb failed' }
}
# Keep postgres from inheriting the caller's captured output pipe on Windows.
# Otherwise a redirected/automated invocation can wait here until postgres exits.
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
  if ((Scalar 'postgres' "select count(*) from pg_database where datname='$Database'") -ne '0') {
    throw 'database already exists; supply a fresh dedicated suffix'
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
  $target = '20261020092917_ledger_calendar_home.sql'
  Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*.sql' | Sort-Object Name | ForEach-Object {
    if ($_.Name -eq $target) {
      $rollback = (Get-Content -LiteralPath $_.FullName -Raw) -replace '(?s)\r?\ncommit;\s*$', "`nrollback;`n"
      $rollbackPath = Join-Path $task 'calendar-rollback.sql'
      Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
      FileSql $rollbackPath
      if ((Scalar $Database "select to_regprocedure('public.get_daily_ledger_home_v1()') is null and to_regprocedure('public.list_daily_notes_date_v1(date,text,integer,text)') is null") -ne 't') { throw 'rollback left functions' }
      Write-Host 'CALENDAR_MIGRATION_ROLLBACK_PASSED'
    }
    if ($_.Name -in @('20261020094919_closing_count_observations.sql','20261020100258_temporary_staff_closing_tasks.sql','20261020121826_invoice_document_render_v2.sql')) {
      $rollback = (Get-Content -LiteralPath $_.FullName -Raw) -replace '(?s)\r?\ncommit;\s*$', "`nrollback;`n"
      $rollbackPath = Join-Path $task 'meeting-migration-rollback.sql'
      Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
      FileSql $rollbackPath
      $check = switch ($_.Name) {
        '20261020094919_closing_count_observations.sql' { "select to_regprocedure('public.close_daily_ledger_day_v2(uuid,uuid,bigint,jsonb)') is null" }
        '20261020100258_temporary_staff_closing_tasks.sql' { "select to_regclass('public.closing_staff_accounts') is null and to_regprocedure('public.get_my_closing_task_v1()') is null" }
        default { "select to_regprocedure('public.post_invoice_presentation_v2(uuid,jsonb)') is null and pg_get_constraintdef(oid) not like '%dark%' from pg_constraint where conrelid='public.invoice_appearance_revisions'::regclass and conname='invoice_appearance_revisions_template_check'" }
      }
      if ((Scalar $Database $check) -ne 't') { throw "rollback failed: $($_.Name)" }
      Write-Host "MEETING_MIGRATION_ROLLBACK_PASSED $($_.Name)"
    }
    if ($_.Name -eq '20261020132245_closing_delegation_foreign_key_indexes.sql') {
      $rollback = (Get-Content -LiteralPath $_.FullName -Raw) -replace '(?s)\r?\ncommit;\s*$', "`nrollback;`n"
      $rollbackPath = Join-Path $task 'staff-index-rollback.sql'
      Set-Content -LiteralPath $rollbackPath -Value $rollback -Encoding utf8NoBOM
      FileSql $rollbackPath
      if ((Scalar $Database "select count(*) from pg_indexes where indexname in ('closing_staff_accounts_creator_idx','closing_count_tasks_day_idx','closing_count_tasks_assigner_idx','closing_count_tasks_submitter_idx','closing_count_tasks_close_operation_idx','closing_count_tasks_shop_staff_idx','closing_delegation_audit_shop_idx','closing_delegation_audit_actor_idx','closing_delegation_audit_staff_idx','closing_delegation_audit_task_idx','closing_delegation_audit_operation_idx','closing_staff_creation_owner_idx','closing_staff_creation_staff_idx','closing_delegation_commands_actor_idx')") -ne '0') { throw 'index rollback left indexes' }
      Write-Host 'CLOSING_DELEGATION_INDEX_ROLLBACK_PASSED'
    }
    FileSql $_.FullName
  }
  if ($ReportsOnly) {
    FileSql (Join-Path $PSScriptRoot 'financial_day_report.sql')
    FileSql (Join-Path $PSScriptRoot 'financial_week_report.sql')
    Write-Host 'REPORTS_SQL_PASSED'
    return
  }
  FileSql (Join-Path $PSScriptRoot 'ledger_calendar_home.sql')
  FileSql (Join-Path $PSScriptRoot 'ledger_date_read.sql')
  FileSql (Join-Path $PSScriptRoot 'daily_notes_pagination.sql')
  FileSql (Join-Path $PSScriptRoot 'invoice_price_components.sql')
  FileSql (Join-Path $PSScriptRoot 'daily_ledger_trades.sql')
  FileSql (Join-Path $PSScriptRoot 'ledger_trade_change.sql')
  FileSql (Join-Path $PSScriptRoot 'financial_day_report.sql')
  FileSql (Join-Path $PSScriptRoot 'financial_week_report.sql')
  FileSql (Join-Path $PSScriptRoot 'staff_closing_delegation.sql')
  FileSql (Join-Path $PSScriptRoot 'invoice_appearance.sql')
  FileSql (Join-Path $PSScriptRoot 'closing_delegation_index_coverage.sql')
  FileSql (Join-Path $PSScriptRoot 'meeting_close_race_seed.sql')
  $day = Scalar $Database "select id from public.business_days where shop_id='e2900000-0000-4000-8000-000000000001' and status='open'"
  $version = Scalar $Database "select day_version from public.business_days where id='$day'"
  $raceSql = @"
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','e1900000-0000-4000-8000-000000000001',true);
select public.close_daily_ledger_day_v2('e3900000-0000-4000-8000-000000000002','$day',$version,
  '{"version":2,"cash":{"cash":"10000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb);
commit;
"@
  $racePath = Join-Path $task 'close-race.sql'
  Set-Content -LiteralPath $racePath -Value $raceSql -Encoding utf8NoBOM
  $processes = @()
  foreach ($index in 1..2) {
    $info = [System.Diagnostics.ProcessStartInfo]::new($psql)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in @('-h','127.0.0.1','-p',"$port",'-U','postgres','-d',$Database,'-X','-t','-A','-v','ON_ERROR_STOP=1','-f',$racePath)) { $info.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    if (-not $process.Start()) { throw 'race client did not start' }
    $processes += @{ Process=$process; Output=$process.StandardOutput.ReadToEndAsync(); Error=$process.StandardError.ReadToEndAsync() }
  }
  $raceOutput = ''
  foreach ($entry in $processes) {
    if (-not $entry.Process.WaitForExit(30000)) { throw 'race timed out' }
    $output = $entry.Output.GetAwaiter().GetResult()
    $errors = $entry.Error.GetAwaiter().GetResult()
    if ($entry.Process.ExitCode -ne 0) { throw "race client failed: $errors" }
    $raceOutput += $output
    $entry.Process.Dispose()
  }
  if ($raceOutput -notmatch '"replayed": true' -or $raceOutput -notmatch '"replayed": false' -or
    (Scalar $Database "select count(*) from public.financial_operations where shop_id='e2900000-0000-4000-8000-000000000001' and kind='close_day'") -ne '1' -or
    (Scalar $Database "select count(*) from public.financial_audit_events where shop_id='e2900000-0000-4000-8000-000000000001' and action='business_day_closed'") -ne '1') { throw 'duplicate or missing concurrent close' }
  Write-Host 'MEETING_CONCURRENT_CLOSE_PASSED'

  Write-Host 'CALENDAR_HOME_SQL_PASSED'
} finally {
  & $pgctl -D $data -m fast -w stop
  if ($LASTEXITCODE -ne 0) { throw 'local cluster stop failed' }
}

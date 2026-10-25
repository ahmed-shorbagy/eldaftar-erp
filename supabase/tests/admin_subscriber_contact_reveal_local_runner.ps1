param(
  [Parameter(Mandatory = $true)]
  [string]$Database
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($Database -notmatch '^eldaftar_pii_[a-z0-9_]+$') { throw 'dedicated database required' }
$port = 55477
$env:PGCLIENTENCODING = 'UTF8'
$repo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$server = Join-Path $env:TEMP 'eldaftar-pg-binaries\extracted\bin'
$client = Join-Path $env:TEMP 'eldaftar-pg-client'
$psql = Join-Path $client 'psql.exe'
$pgctl = Join-Path $server 'pg_ctl.exe'
$ready = Join-Path $client 'pg_isready.exe'
$task = Join-Path $env:TEMP 'eldaftar-pii-pg'
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
Get-Content -LiteralPath $startStdout | Write-Host
$startErr = ''
if (Test-Path -LiteralPath $startStderr) { $startErr = Get-Content -LiteralPath $startStderr -Raw }
$startProcess.Dispose()
$readyOk = $false
for ($i = 0; $i -lt 20; $i++) {
  & $ready -h 127.0.0.1 -p $port | Out-Null
  if ($LASTEXITCODE -eq 0) { $readyOk = $true; break }
  Start-Sleep -Milliseconds 250
}
if (-not $readyOk) { throw "local cluster failed to start: $startErr" }
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
  $migrations = @(Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*_admin_subscriber_contact_reveal.sql')
  if ($migrations.Count -ne 1) { throw 'expected exactly one contact reveal migration' }
  $target = $migrations[0].Name
  if ((Scalar 'postgres' "select count(*) from pg_database where datname='$Database'") -ne '0') {
    throw "database $Database already exists; pass a fresh suffix and leave the existing database in place"
  }
  & (Join-Path $client 'createdb.exe') -h 127.0.0.1 -p $port -U postgres $Database
  if ($LASTEXITCODE -ne 0) { throw 'createdb failed' }
  $utf8 = New-Object System.Text.UTF8Encoding $false
  $auth = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_auth_bootstrap.sql') -Raw).Replace("current_database() <> 'eldafttar_test'", "current_database() <> '$Database'")
  $storage = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local_storage_bootstrap.sql') -Raw).Replace("current_database() is distinct from 'eldafttar_notes_test'", "current_database() is distinct from '$Database'")
  $authPath = Join-Path $task 'auth.sql'
  $storagePath = Join-Path $task 'storage.sql'
  [System.IO.File]::WriteAllText($authPath, $auth, $utf8)
  [System.IO.File]::WriteAllText($storagePath, $storage, $utf8)
  FileSql $authPath
  Scalar $Database 'alter table auth.users add column banned_until timestamptz' | Out-Null
  FileSql $storagePath
  Get-ChildItem -LiteralPath (Join-Path $repo 'supabase\migrations') -Filter '*.sql' | Sort-Object Name | ForEach-Object {
    if ($_.Name -eq $target) {
      $beforeList = Scalar $Database "select md5(pg_get_functiondef('public.list_my_shop_accounts()'::regprocedure))"
      $rollback = (Get-Content -LiteralPath $_.FullName -Raw) -replace '(?s)\r?\ncommit;\s*$', "`nrollback;`n"
      $rollbackPath = Join-Path $task 'pii-rollback.sql'
      [System.IO.File]::WriteAllText($rollbackPath, $rollback, $utf8)
      FileSql $rollbackPath
      if ((Scalar $Database "select to_regprocedure('public.admin_get_subscriber_contact_v1(uuid)') is null") -ne 't') {
        throw 'contact reveal migration rollback left objects'
      }
      $afterList = Scalar $Database "select md5(pg_get_functiondef('public.list_my_shop_accounts()'::regprocedure))"
      if ($afterList -ne $beforeList) { throw 'pii rollback changed list_my_shop_accounts' }
      Write-Host 'ADMIN_SUBSCRIBER_CONTACT_REVEAL_MIGRATION_ROLLBACK_PASSED'
    }
    FileSql $_.FullName
  }
  FileSql (Join-Path $PSScriptRoot 'admin_subscriber_contact_reveal.sql')
  Write-Host 'ADMIN_SUBSCRIBER_CONTACT_REVEAL_SQL_PASSED'
} finally {
  & $pgctl -D $data -m fast -w stop
  if ($LASTEXITCODE -ne 0) { throw 'local cluster stop failed' }
}

# Regression for hosted Storage ownership: execute the actual migration block
# against an owner-controlled local probe, then a non-owner role with RLS enabled.
$ErrorActionPreference = 'Stop'
$pgBin = Join-Path $env:TEMP 'eldafttar-postgres17/pgsql/bin'
$migrationPath = Join-Path $PSScriptRoot '../migrations/20261004090000_daily_notes_and_ledger_pagination.sql'
$source = Get-Content -LiteralPath $migrationPath -Raw
$block = [regex]::Match($source, '(?s)do \$storage_rls\$.*?\$storage_rls\$;').Value
if (-not $block) { throw 'Storage RLS migration block missing' }
$probeBlock = $block.Replace('storage.objects', 'pg_temp.notes_storage_probe')
$before = @'
begin;
do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database()<>'eldafttar_notes_test' then
    raise exception 'local disposable notes database required';
  end if;
end;
$guard$;
create temp table notes_storage_probe(id integer);
alter table notes_storage_probe enable row level security;
set local role authenticated;
do $nonowner$
begin
  begin
    alter table pg_temp.notes_storage_probe enable row level security;
    raise exception 'fixture role unexpectedly owns probe';
  exception when insufficient_privilege then null;
  end;
end;
$nonowner$;
'@
$middle = @'
reset role;
alter table notes_storage_probe disable row level security;
'@
$after = @'
do $enabled$
begin
  if not (select relrowsecurity from pg_class where oid='pg_temp.notes_storage_probe'::regclass) then
    raise exception 'owner path did not enable RLS';
  end if;
end;
$enabled$;
select 'owner enable and already-enabled non-owner migration paths passed' as result;
rollback;
'@
$sql = ($before, $probeBlock, $middle, $probeBlock, $after) -join [char]10
$sql | & "$pgBin/psql.exe" -h 127.0.0.1 -p 55432 -U postgres -d eldafttar_notes_test -X -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw "Storage ownership regression failed: $LASTEXITCODE" }

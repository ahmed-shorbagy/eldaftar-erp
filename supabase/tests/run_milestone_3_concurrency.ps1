# Two-connection races on a unique disposable local database.
# Workers run as role authenticated. Never drops a pre-existing database.
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
if (-not (Test-Path -LiteralPath $m3)) {
  throw "safe repository root required (no fallback): missing $m3"
}
$migDir = Join-Path $repo 'supabase\migrations'
$bootSrc = Join-Path $repo 'supabase\tests\local_auth_bootstrap.sql'

$unique = -join ((1..8) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
$db = "eldafttar_m3r_$unique"
if ($db -cnotmatch '^eldafttar_m3r_[0-9a-f]{8}$') { throw "generated db name failed guard: $db" }
$forbidden = @('eldafttar_test', 'eldafttar_backend_test', 'eldafttar_notes_test', 'postgres', 'template0', 'template1')
if ($forbidden -contains $db) { throw "refusing forbidden database name $db" }

$tempRoot = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
$taskdir = Join-Path $tempRoot "eldafttar-m3r-$unique"
New-Item -ItemType Directory -Force -Path $taskdir | Out-Null
$taskdirResolved = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $taskdir).Path).TrimEnd('\')
if ($taskdirResolved -ne [System.IO.Path]::GetFullPath($taskdir).TrimEnd('\')) {
  throw "taskdir mismatch"
}
if ($taskdirResolved -eq $tempRoot -or -not $taskdirResolved.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "refusing to use taskdir outside TEMP: $taskdirResolved"
}

function Invoke-Psql {
  param([string]$Database, [string]$File, [string]$Command)
  $argList = @('-h', $hostName, '-p', $port, '-U', $user, '-d', $Database, '-X', '-v', 'ON_ERROR_STOP=1')
  if ($File) { $argList += @('-f', $File) }
  if ($Command) { $argList += @('-c', $Command) }
  & $psql @argList
  if ($LASTEXITCODE -ne 0) { throw "psql failed for $Database (exit $LASTEXITCODE)" }
}

function Invoke-PsqlScalar([string]$Database, [string]$Command) {
  $out = & $psql @('-h', $hostName, '-p', $port, '-U', $user, '-d', $Database, '-X', '-t', '-A', '-c', $Command)
  if ($LASTEXITCODE -ne 0) { throw "psql scalar failed: $Command" }
  return ([string]$out).Trim()
}

function Assert-OwnDatabase([string]$Name) {
  if ($Name -cnotmatch '^eldafttar_m3r_[0-9a-f]{8}$' -or $forbidden -contains $Name) {
    throw "refusing to drop non-owned database $Name"
  }
}

$createdDb = $false
$script:workers = @()
try {
  $already = Invoke-PsqlScalar 'postgres' "select coalesce((select 1 from pg_database where datname = '$db'), 0)"
  if ($already -ne '0') { throw "database $db already exists; refusing to drop it" }

  Write-Host "Creating disposable $db on ${hostName}:$port"
  & $createdb @('-h', $hostName, '-p', $port, '-U', $user, $db)
  if ($LASTEXITCODE -ne 0) { throw "createdb failed for $db" }
  $createdDb = $true

  $bootstrap = Get-Content -LiteralPath $bootSrc -Raw
  if ($bootstrap -notmatch "current_database\(\) <> 'eldafttar_test'") {
    throw 'committed bootstrap guard missing'
  }
  $bootstrap = $bootstrap.Replace("current_database() <> 'eldafttar_test'", "current_database() <> '$db'")
  $bootFile = Join-Path $taskdir 'bootstrap.sql'
  Set-Content -LiteralPath $bootFile -Value $bootstrap -Encoding utf8
  Invoke-Psql $db $bootFile $null

  $m3Name = '20261004081229_milestone_3_inventory_contract.sql'
  $files = @(Get-ChildItem -LiteralPath $migDir -Filter '*.sql' | Where-Object { $_.Length -gt 0 } | Sort-Object Name)
  foreach ($file in $files) {
    Write-Host "Applying $($file.Name)"
    Invoke-Psql $db $file.FullName $null
  }
  $m3File = $files | Where-Object { $_.Name -eq $m3Name }
  if (-not $m3File) { throw 'milestone 3 migration missing' }

  $setup = @'
begin;
insert into auth.users(id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values ('c1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'race-owner@example.test', false, now(), now());
insert into public.shops(id, name, owner_display_name, time_zone)
values ('c1222222-2222-4222-8222-222222222222', 'متجر السباق', 'مالك السباق', 'Africa/Cairo');
insert into public.shop_memberships(shop_id, user_id, role)
values ('c1222222-2222-4222-8222-222222222222', 'c1111111-1111-4111-8111-111111111111', 'owner');
insert into public.shop_entitlements(shop_id, starts_at, expires_at)
values ('c1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '1 day');
commit;
set role authenticated;
select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claims', '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', false);
select public.confirm_opening_balances(
  'c1333333-3333-4333-8333-333333333333',
  '{"version":1,"cash":{"cash":"10000000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"20000","count":"4"}],"scrap":[{"karat":18,"milligrams":"5000"}]}'::jsonb
);
reset role;
create table public.race_results (
  worker text not null,
  phase text not null,
  outcome text not null,
  operation_id uuid,
  session_role text,
  finished_at timestamptz not null default clock_timestamp(),
  primary key (phase, worker)
);
create table public.race_start (phase text primary key, go boolean not null);
insert into public.race_start(phase, go) values
  ('diff_key', false), ('same_key', false), ('gold', false);
grant select on table public.race_start to authenticated;
grant insert on table public.race_results to authenticated;
revoke update, delete on table public.race_results from authenticated;
revoke update, delete, insert on table public.race_start from authenticated;
'@
  $setupFile = Join-Path $taskdir 'setup.sql'
  Set-Content -LiteralPath $setupFile -Value $setup -Encoding utf8
  Invoke-Psql $db $setupFile $null

  function New-Receipt([string]$Key, [string]$Mg) {
    $sql = @"
set role authenticated;
select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claims', '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', false);
select public.post_inventory_receipt_v1(
  '$Key'::uuid,
  (select jsonb_build_object(
    'version', 1, 'kind', 'inventory_receipt', 'owner_kind', 'shop',
    'counterparty_name', 'مورد', 'product_name', 'طقم', 'category', 'worked_jewelry',
    'karat', 21, 'milligrams', '$Mg', 'count', '1', 'recognition', 'deferred',
    'denomination_id', null, 'coin_type_id', null, 'note', '',
    'expected_day_id', state ->> 'business_day_id',
    'expected_day_version', state ->> 'day_version'
  ) from (select public.get_daily_ledger_day_state() as state) s)
);
reset role;
"@
    $file = Join-Path $taskdir "receipt-$Key.sql"
    Set-Content -LiteralPath $file -Value $sql -Encoding utf8
    Invoke-Psql $db $file $null
  }

  New-Receipt 'c1444444-4444-4444-8444-444444444444' '3000'
  New-Receipt 'c1444445-4445-4445-8445-444444444445' '2000'
  $goldSql = @'
set role authenticated;
select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claims', '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', false);
select public.post_gold_obligation_acquisition_v1(
  'c1444446-4446-4446-8446-444444444446'::uuid,
  (select jsonb_build_object(
    'version', 1, 'kind', 'gold_obligation_acquisition', 'category', 'worked_jewelry',
    'karat', 18, 'milligrams', '1000', 'count', '1', 'item_name', 'غويشة',
    'obligation_karat', 18, 'obligation_milligrams', '1500',
    'counterparty_name', 'تاجر سباق', 'note', '',
    'denomination_id', null, 'coin_type_id', null,
    'expected_day_id', state ->> 'business_day_id',
    'expected_day_version', state ->> 'day_version'
  ) from (select public.get_daily_ledger_day_state() as state) s)
);
reset role;
'@
  $goldFile = Join-Path $taskdir 'gold-acq.sql'
  Set-Content -LiteralPath $goldFile -Value $goldSql -Encoding utf8
  Invoke-Psql $db $goldFile $null

  $receiptDiff = Invoke-PsqlScalar $db "select id::text from public.inventory_receipts where milligrams = 3000"
  $receiptSame = Invoke-PsqlScalar $db "select id::text from public.inventory_receipts where milligrams = 2000"
  $goldOp = Invoke-PsqlScalar $db "select operation_id::text from public.gold_obligations"
  $scrapLot = Invoke-PsqlScalar $db "select id::text from public.inventory_lots where category_code = 'scrap' and karat = 18"

  function Write-Worker([string]$Name, [string]$Phase, [string]$Key, [string]$BodySql) {
    $sql = @"
select pg_sleep(0.05);
do `$wait`$
begin
  loop
    if exists (select 1 from public.race_start where phase = '$Phase' and go) then exit; end if;
    perform pg_sleep(0.05);
  end loop;
end;
`$wait`$;
set role authenticated;
select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', false);
select set_config('request.jwt.claims', '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', false);
do `$race`$
declare v_result jsonb; v_role text;
begin
  v_role := current_user;
  if v_role is distinct from 'authenticated' then
    insert into public.race_results(worker, phase, outcome, session_role)
    values ('$Name', '$Phase', 'role:' || v_role, v_role);
    return;
  end if;
  begin
    $BodySql
    insert into public.race_results(worker, phase, outcome, operation_id, session_role)
    values ('$Name', '$Phase', 'ok', (v_result ->> 'operation_id')::uuid, v_role);
  exception when others then
    insert into public.race_results(worker, phase, outcome, session_role)
    values ('$Name', '$Phase', sqlerrm, v_role);
  end;
end;
`$race`$;
"@
    $path = Join-Path $taskdir "$Phase-$Name.sql"
    Set-Content -LiteralPath $path -Value $sql -Encoding utf8
    return $path
  }

  function Start-Workers([string]$Phase, [string]$FileA, [string]$FileB) {
    $outA = Join-Path $taskdir "$Phase-a.out"
    $errA = Join-Path $taskdir "$Phase-a.err"
    $outB = Join-Path $taskdir "$Phase-b.out"
    $errB = Join-Path $taskdir "$Phase-b.err"
    $quotedFileA = '"' + $FileA + '"'
    $quotedFileB = '"' + $FileB + '"'
    $procA = Start-Process -FilePath $psql -ArgumentList @('-h', $hostName, '-p', $port, '-U', $user, '-d', $db, '-X', '-v', 'ON_ERROR_STOP=1', '-f', $quotedFileA) -WorkingDirectory $taskdir -WindowStyle Hidden -PassThru -RedirectStandardOutput $outA -RedirectStandardError $errA
    $procB = Start-Process -FilePath $psql -ArgumentList @('-h', $hostName, '-p', $port, '-U', $user, '-d', $db, '-X', '-v', 'ON_ERROR_STOP=1', '-f', $quotedFileB) -WorkingDirectory $taskdir -WindowStyle Hidden -PassThru -RedirectStandardOutput $outB -RedirectStandardError $errB
    $script:workers += @($procA, $procB)
    Start-Sleep -Seconds 1
    Invoke-Psql $db $null "update public.race_start set go = true where phase = '$Phase'"
    $okA = $procA.WaitForExit(60000)
    $okB = $procB.WaitForExit(60000)
    if (-not $okA -or -not $okB) {
      foreach ($p in @($procA, $procB)) {
        if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
      }
      throw "worker timeout phase $Phase"
    }
    $rows = Invoke-PsqlScalar $db "select count(*) from public.race_results where phase = '$Phase'"
    if ($rows -ne '2') {
      Get-Content -LiteralPath $outA, $errA, $outB, $errB -ErrorAction SilentlyContinue | Write-Host
      throw "worker failed phase $Phase rows=$rows exitA=$($procA.ExitCode) exitB=$($procB.ExitCode)"
    }
    if (($null -ne $procA.ExitCode -and $procA.ExitCode -ne 0) -or ($null -ne $procB.ExitCode -and $procB.ExitCode -ne 0)) {
      Get-Content -LiteralPath $outA, $errA, $outB, $errB -ErrorAction SilentlyContinue | Write-Host
      throw "worker non-zero exit phase $Phase exitA=$($procA.ExitCode) exitB=$($procB.ExitCode)"
    }
  }

  function DayPayload() {
    $day = Invoke-PsqlScalar $db "select id::text || '|' || day_version::text from public.business_days where shop_id = 'c1222222-2222-4222-8222-222222222222' and status = 'open'"
    $parts = $day.Split('|')
    return @{ Id = $parts[0]; Version = $parts[1] }
  }

  function RecognitionBody([string]$Key, [string]$Receipt, [string]$Mg, [hashtable]$Day) {
    return @"
    v_result := public.post_inventory_recognition_v1(
      '$Key'::uuid,
      jsonb_build_object(
        'version', 1, 'kind', 'inventory_recognition', 'receipt_id', '$Receipt'::uuid,
        'milligrams', '$Mg', 'count', '1', 'reason', 'سباق اعتراف',
        'expected_day_id', '$($Day.Id)', 'expected_day_version', '$($Day.Version)'
      )
    );
"@
  }

  $day = DayPayload
  $a = Write-Worker 'a' 'diff_key' 'c1555555-5555-4555-8555-555555555555' (RecognitionBody 'c1555555-5555-4555-8555-555555555555' $receiptDiff '3000' $day)
  $b = Write-Worker 'b' 'diff_key' 'c1666666-6666-4666-8666-666666666666' (RecognitionBody 'c1666666-6666-4666-8666-666666666666' $receiptDiff '3000' $day)
  Start-Workers 'diff_key' $a $b

  $day = DayPayload
  $sameKey = 'c1777777-7777-4777-8777-777777777777'
  $a = Write-Worker 'a' 'same_key' $sameKey (RecognitionBody $sameKey $receiptSame '2000' $day)
  $b = Write-Worker 'b' 'same_key' $sameKey (RecognitionBody $sameKey $receiptSame '2000' $day)
  Start-Workers 'same_key' $a $b

  $day = DayPayload
  $goldBodyA = @"
    v_result := public.post_gold_obligation_settlement_v1(
      'c1888888-8888-4888-8888-888888888888'::uuid,
      jsonb_build_object(
        'version', 1, 'kind', 'gold_obligation_settlement',
        'obligation_operation_id', '$goldOp'::uuid, 'reason', 'سباق ذهب',
        'expected_day_id', '$($day.Id)', 'expected_day_version', '$($day.Version)',
        'deliveries', jsonb_build_array(jsonb_build_object(
          'lot_id', '$scrapLot', 'milligrams', '1500', 'count', null))
      )
    );
"@
  $goldBodyB = $goldBodyA.Replace('c1888888-8888-4888-8888-888888888888', 'c1999999-9999-4999-8999-999999999999')
  $a = Write-Worker 'a' 'gold' 'c1888888-8888-4888-8888-888888888888' $goldBodyA
  $b = Write-Worker 'b' 'gold' 'c1999999-9999-4999-8999-999999999999' $goldBodyB
  Start-Workers 'gold' $a $b

  $diffWins = Invoke-PsqlScalar $db "select count(*) from public.race_results where phase = 'diff_key' and outcome = 'ok'"
  $diffFail = Invoke-PsqlScalar $db "select string_agg(outcome, ',') from public.race_results where phase = 'diff_key' and outcome <> 'ok'"
  $diffRole = Invoke-PsqlScalar $db "select string_agg(distinct session_role, ',') from public.race_results where phase = 'diff_key'"
  $alloc = Invoke-PsqlScalar $db "select a.milligrams::text from public.inventory_receipts r join public.receipt_quantity_allocations a on a.receipt_id = r.id where r.milligrams = 3000"
  if ($diffWins -ne '1') { throw "diff_key expected one winner, got $diffWins fail=$diffFail" }
  if ($diffFail -notmatch 'stale_day|already_allocated') { throw "diff_key loser $diffFail" }
  if ($diffRole -ne 'authenticated') { throw "diff_key role $diffRole" }
  if ($alloc -ne '3000') { throw "diff_key allocation $alloc" }

  $sameOk = Invoke-PsqlScalar $db "select count(*) from public.race_results where phase = 'same_key' and outcome = 'ok'"
  $sameOps = Invoke-PsqlScalar $db "select count(distinct operation_id) from public.race_results where phase = 'same_key' and outcome = 'ok'"
  $sameRole = Invoke-PsqlScalar $db "select string_agg(distinct session_role, ',') from public.race_results where phase = 'same_key'"
  $sameRecog = Invoke-PsqlScalar $db "select count(*) from public.financial_operations where kind = 'inventory_recognition' and id in (select a.operation_id from public.receipt_quantity_allocations a join public.inventory_receipts r on r.id = a.receipt_id where r.milligrams = 2000)"
  if ($sameOk -ne '2' -or $sameOps -ne '1' -or $sameRecog -ne '1') {
    throw "same_key expected two ok one operation, ok=$sameOk ops=$sameOps recog=$sameRecog"
  }
  if ($sameRole -ne 'authenticated') { throw "same_key role $sameRole" }

  $goldWins = Invoke-PsqlScalar $db "select count(*) from public.race_results where phase = 'gold' and outcome = 'ok'"
  $goldFail = Invoke-PsqlScalar $db "select string_agg(outcome, ',') from public.race_results where phase = 'gold' and outcome <> 'ok'"
  $goldRem = Invoke-PsqlScalar $db "select remaining_milligrams::text from public.gold_obligations"
  $goldAudit = Invoke-PsqlScalar $db "select count(*) from public.financial_audit_events where action = 'gold_obligation_settled'"
  $goldOutbox = Invoke-PsqlScalar $db "select count(*) from public.financial_outbox where event_type = 'gold_obligation_settled'"
  $imbalance = Invoke-PsqlScalar $db "select count(*) from (select journal.id from public.journals journal join public.journal_postings posting on posting.journal_id = journal.id group by journal.id having sum(posting.amount) <> 0) x"
  $negLot = Invoke-PsqlScalar $db "select count(*) from (select lot_id from public.inventory_lot_movements group by lot_id having sum(delta_milligrams) < 0 or sum(delta_count) < 0) x"
  if ($goldWins -ne '1') { throw "gold expected one winner, got $goldWins fail=$goldFail" }
  if ($goldFail -notmatch 'stale_day|settlement_exceeds_obligation|negative_owned_balance') {
    throw "gold loser $goldFail"
  }
  if ($goldRem -ne '0') { throw "gold remaining $goldRem" }
  if ($goldAudit -ne '1' -or $goldOutbox -ne '1') { throw "gold audit/outbox $goldAudit $goldOutbox" }
  if ($imbalance -ne '0' -or $negLot -ne '0') { throw "conservation failed imbalance=$imbalance neg=$negLot" }

  Write-Host "milestone_3_concurrency_passed diff_key loser=$diffFail same_key ops=1 gold remaining=0 role=authenticated db=$db"
}
finally {
  foreach ($p in $workers) {
    try {
      if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
    } catch { }
  }
  if ($createdDb) {
    Assert-OwnDatabase $db
    & $dropdb @('-h', $hostName, '-p', $port, '-U', $user, '--if-exists', $db)
    if ($LASTEXITCODE -ne 0) { Write-Host "warning: dropdb $db failed" }
    else { Write-Host "Dropped owned disposable $db" }
  }
  $cleanup = [System.IO.Path]::GetFullPath($taskdirResolved).TrimEnd('\')
  if ($cleanup.StartsWith($tempRoot + '\', [System.StringComparison]::OrdinalIgnoreCase) -and
      $cleanup -eq $taskdirResolved -and
      (Split-Path -Leaf $cleanup).StartsWith('eldafttar-m3r-')) {
    Remove-Item -LiteralPath $cleanup -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    throw "refusing temp cleanup of $cleanup"
  }
}


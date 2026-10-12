-- Repair custody, fee posting, and RLS. Synthetic rows roll back.
begin;

-- Test-only failure injection after every command write. Never deployed.
create function pg_temp.repair_fail_after_write() returns trigger
language plpgsql as $failure$
begin
  if current_setting('eldafttar.repair_fail_after_write', true) = '1' then
    raise exception 'repair_test_failure';
  end if;
  return new;
end;
$failure$;
create trigger repair_test_failure after insert on public.repair_command_requests
for each row execute function pg_temp.repair_fail_after_write();

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, deleted_at, created_at, updated_at)
values
  ('c1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-owner@example.test', false, null, now(), now()),
  ('c2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-other@example.test', false, null, now(), now()),
  ('c3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-revoked@example.test', false, null, now(), now()),
  ('c4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-anon@example.test', true, null, now(), now()),
  ('c5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-admin@example.test', false, null, now(), now()),
  ('c6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-pending@example.test', false, null, now(), now()),
  ('c7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'repair-expired@example.test', false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('c1222222-2222-4222-8222-222222222222', 'متجر الإصلاح', 'مالك الإصلاح', 'Africa/Cairo'),
  ('c2222222-2222-4222-8222-222222222222', 'متجر الآخر', 'مالك الآخر', 'Africa/Cairo'),
  ('c3222222-2222-4222-8222-222222222222', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('c4222222-2222-4222-8222-222222222222', 'متجر مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('c6222222-2222-4222-8222-222222222222', 'متجر معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('c7222222-2222-4222-8222-222222222222', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('c1222222-2222-4222-8222-222222222222', 'c1111111-1111-4111-8111-111111111111', 'owner', null),
  ('c2222222-2222-4222-8222-222222222222', 'c2111111-1111-4111-8111-111111111111', 'owner', null),
  ('c3222222-2222-4222-8222-222222222222', 'c3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('c4222222-2222-4222-8222-222222222222', 'c4111111-1111-4111-8111-111111111111', 'owner', null),
  ('c6222222-2222-4222-8222-222222222222', 'c6111111-1111-4111-8111-111111111111', 'owner', null),
  ('c7222222-2222-4222-8222-222222222222', 'c7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('c1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c4222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c7222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

insert into public.platform_admins (user_id)
values ('c5111111-1111-4111-8111-111111111111');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('c1818181-8181-4181-8181-818181818181', 'c1111111-1111-4111-8111-111111111111', now(), now(), now() + interval '1 day'),
  ('c1818181-8181-4181-8181-818181818182', 'c1111111-1111-4111-8111-111111111111', now(), now(), now() - interval '1 minute');

create function pg_temp.expect_code(p_sql text, p_code text)
returns void language plpgsql security invoker set search_path = '' as $fn$
begin
  begin
    execute p_sql;
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception using message = 'expected_' || p_code;
      elsif sqlerrm is distinct from p_code then
        raise exception using message = 'expected_' || p_code || '_got_' || sqlerrm;
      end if;
  end;
end;
$fn$;

do $priv$
begin
  if private.ledger_operation_label('repair_fee') is distinct from 'أجرة إصلاح'
    or private.ledger_operation_label('sale') is distinct from 'بيع'
    or private.ledger_operation_label('daily_note') is distinct from 'ملاحظة يومية' then
    raise exception 'repair_label_regressed';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shop_sync_signals'
      and column_name = 'repair_revision'
  ) then
    raise exception 'repair_revision_missing';
  end if;
  if has_function_privilege('anon', 'public.post_repair_intake_v1(uuid,jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.list_repairs_v1(text,text,integer,text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_repair_v1(uuid)', 'EXECUTE')
    or has_table_privilege('anon', 'public.repairs', 'SELECT')
    or has_table_privilege('authenticated', 'public.repairs', 'INSERT')
    or has_table_privilege('authenticated', 'public.repair_events', 'UPDATE')
    or has_table_privilege('authenticated', 'public.repair_custody_events', 'DELETE')
    or has_table_privilege('authenticated', 'public.repair_command_requests', 'INSERT') then
    raise exception 'repair_privileges_were_too_wide';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'repairs', 'repair_events', 'repair_custody_events', 'repair_command_requests'
      )
      and cmd <> 'SELECT'
  ) then
    raise exception 'repair_client_write_policy';
  end if;
end;
$priv$;

set local role anon;
do $anon$
begin
  begin
    perform public.list_repairs_v1('', 'open', 20, null);
    raise exception 'anon_list_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'anon_list_unexpected: %', sqlerrm;
  end;
end;
$anon$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_code(
  'select public.list_repairs_v1('''', ''open'', 20, null)',
  'unauthenticated'
);

select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"c1818181-8181-4181-8181-818181818182","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_repair_context_v1()', 'session_expired');

select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select set_config('request.jwt.claim.sub', 'c3111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.list_repairs_v1('''', ''open'', 20, null)', 'forbidden');
select set_config('request.jwt.claim.sub', 'c4111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_repair_v1(''c1222222-2222-4222-8222-222222222222'')', 'forbidden');
select set_config('request.jwt.claim.sub', 'c5111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.list_repairs_v1('''', ''open'', 20, null)', 'forbidden');
select set_config('request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.list_repairs_v1('''', ''open'', 20, null)', 'shop_unavailable');

select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', true);
select public.confirm_opening_balances(
  'c1333333-3333-4333-8333-333333333301',
  '{"version":1,"cash":{"cash":"500000","wallet":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"1"}],"scrap":[]}'::jsonb
);

do $owner$
declare
  v_shop uuid := 'c1222222-2222-4222-8222-222222222222';
  v_state jsonb;
  v_lots bigint;
  v_moves bigint;
  v_receipts bigint;
  v_gold bigint;
  v_payables bigint;
  v_sync bigint;
  v_ops bigint;
  v_cash bigint;
  v_wallet bigint;
  v_day_version text;
  v_result jsonb;
  v_page jsonb;
  v_partial uuid;
  v_none uuid;
  v_all uuid;
  v_cancel uuid;
  v_ready uuid;
begin
  v_lots := (select count(*) from public.inventory_lots where shop_id = v_shop);
  v_moves := (select count(*) from public.inventory_lot_movements where shop_id = v_shop);
  v_receipts := (select count(*) from public.inventory_receipts where shop_id = v_shop);
  v_gold := (select count(*) from public.gold_obligations where shop_id = v_shop);
  v_payables := (select count(*) from public.purchase_cash_payables where shop_id = v_shop);
  v_sync := (select count(*) from public.inventory_lot_sync where shop_id = v_shop);
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  if v_lots <> 1 or v_gold <> 0 or v_payables <> 0 then
    raise exception 'opening_fixture_unexpected';
  end if;

  v_result := public.post_repair_intake_v1(
    'c1444444-4444-4444-8444-444444444401',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'عميل الإصلاح', 'customer_phone', '01001234567',
      'item_description', 'خاتم مفصص', 'measured_milligrams', '1255',
      'karat', 21, 'issue', 'مفصص', 'intake_notes', 'ملاحظة',
      'estimated_fee_piastres', '15000'
    )
  );
  if v_result ->> 'ok' is distinct from 'true'
    or v_result ->> 'stock_milligrams' is distinct from '0'
    or v_result ->> 'cash_piastres' is distinct from '0'
    or v_result ->> 'custody_milligrams' is distinct from '1255' then
    raise exception 'intake_effect_wrong';
  end if;
  v_partial := (v_result ->> 'repair_id')::uuid;
  if (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select count(*) from public.inventory_lots where shop_id = v_shop) <> v_lots
    or (select count(*) from public.repair_custody_events
        where repair_id = v_partial and direction = 'intake') <> 1
    or (select estimated_fee_piastres from public.repairs where id = v_partial) <> 15000 then
    raise exception 'intake_touched_stock_or_cash';
  end if;
  v_result := public.post_repair_intake_v1(
    'c1444444-4444-4444-8444-444444444401',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'عميل الإصلاح', 'customer_phone', '01001234567',
      'item_description', 'خاتم مفصص', 'measured_milligrams', '1255',
      'karat', 21, 'issue', 'مفصص', 'intake_notes', 'ملاحظة',
      'estimated_fee_piastres', '15000'
    )
  );
  if v_result ->> 'replayed' is distinct from 'true'
    or (select count(*) from public.repairs where shop_id = v_shop) <> 1 then
    raise exception 'intake_replay_duplicated';
  end if;
  begin
    perform public.post_repair_intake_v1(
      'c1444444-4444-4444-8444-444444444401',
      jsonb_build_object(
        'version', 1, 'kind', 'repair_intake',
        'customer_name', 'اسم مختلف', 'customer_phone', '',
        'item_description', 'خاتم', 'measured_milligrams', '1255',
        'karat', 21, 'issue', 'مفصص', 'intake_notes', '',
        'estimated_fee_piastres', null
      )
    );
    raise exception 'changed_payload_accepted';
  exception
    when others then
      if sqlerrm is distinct from 'payload_mismatch' then
        raise exception 'changed_payload_got_%', sqlerrm;
      end if;
  end;

  perform public.post_repair_status_v1(
    'c1444444-4444-4444-8444-444444444402',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_status', 'repair_id', v_partial,
      'expected_version', '1', 'status', 'in_progress'
    )
  );
  begin
    perform public.post_repair_status_v1(
      'c1444444-4444-4444-8444-444444444403',
      jsonb_build_object(
        'version', 1, 'kind', 'repair_status', 'repair_id', v_partial,
        'expected_version', '1', 'status', 'ready'
      )
    );
    raise exception 'stale_status_accepted';
  exception
    when others then
      if sqlerrm is distinct from 'stale_repair' then
        raise exception 'stale_status_got_%', sqlerrm;
      end if;
  end;
  perform public.post_repair_status_v1(
    'c1444444-4444-4444-8444-444444444404',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_status', 'repair_id', v_partial,
      'expected_version', '2', 'status', 'ready'
    )
  );
  if (select estimated_fee_piastres from public.repairs where id = v_partial) <> 15000
    or (select status from public.repairs where id = v_partial) <> 'ready' then
    raise exception 'estimate_or_status_lost';
  end if;

  v_state := public.get_daily_ledger_day_state();
  v_day_version := v_state ->> 'day_version';
  begin
    perform public.post_repair_handover_v1(
      'c1444444-4444-4444-8444-444444444405',
      jsonb_build_object(
        'version', 1, 'kind', 'repair_handover', 'repair_id', v_partial,
        'expected_version', '3', 'final_fee_piastres', '20000',
        'collection', 'part', 'collected_piastres', '8000',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '8000')),
        'expected_day_id', v_state ->> 'business_day_id',
        'expected_day_version', '999'
      )
    );
    raise exception 'stale_day_accepted';
  exception
    when others then
      if sqlerrm is distinct from 'stale_day' then
        raise exception 'stale_day_got_%', sqlerrm;
      end if;
  end;
  if (select status from public.repairs where id = v_partial) <> 'ready'
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops then
    raise exception 'stale_day_wrote_state';
  end if;

  perform set_config('eldafttar.repair_fail_after_write', '1', true);
  begin
    perform public.post_repair_handover_v1(
      'c1444444-4444-4444-8444-444444444406',
      jsonb_build_object(
        'version', 1, 'kind', 'repair_handover', 'repair_id', v_partial,
        'expected_version', '3', 'final_fee_piastres', '20000',
        'collection', 'part', 'collected_piastres', '8000',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '8000')),
        'expected_day_id', v_state ->> 'business_day_id',
        'expected_day_version', v_day_version
      )
    );
    raise exception 'injected_failure_committed';
  exception
    when others then
      if sqlerrm is distinct from 'repair_test_failure' then
        raise exception 'injected_failure_got_%', sqlerrm;
      end if;
  end;
  perform set_config('eldafttar.repair_fail_after_write', '', true);
  if (select status from public.repairs where id = v_partial) <> 'ready'
    or exists (
      select 1 from public.repair_command_requests
      where idempotency_key = 'c1444444-4444-4444-8444-444444444406'
    )
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops then
    raise exception 'injected_failure_left_rows';
  end if;

  begin
    perform public.post_repair_handover_v1(
      'c1444444-4444-4444-8444-444444444407',
      jsonb_build_object(
        'version', 1, 'kind', 'repair_handover', 'repair_id', v_partial,
        'expected_version', '3', 'final_fee_piastres', '20000',
        'collection', 'part', 'collected_piastres', '25000',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '25000')),
        'expected_day_id', v_state ->> 'business_day_id',
        'expected_day_version', v_day_version
      )
    );
    raise exception 'overcollect_accepted';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'overcollect_got_%', sqlerrm;
      end if;
  end;

  v_result := public.post_repair_handover_v1(
    'c1444444-4444-4444-8444-444444444408',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_handover', 'repair_id', v_partial,
      'expected_version', '3', 'final_fee_piastres', '20000',
      'collection', 'part', 'collected_piastres', '8000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '8000')),
      'expected_day_id', v_state ->> 'business_day_id',
      'expected_day_version', v_day_version
    )
  );
  if v_result ->> 'outstanding_piastres' is distinct from '12000'
    or v_result ->> 'collected_piastres' is distinct from '8000'
    or v_result ->> 'stock_milligrams' is distinct from '0'
    or v_result ->> 'custody_released_milligrams' is distinct from '1255'
    or v_result ->> 'day_version' is distinct from (v_day_version::bigint + 1)::text then
    raise exception 'partial_handover_wrong';
  end if;
  select coalesce(sum(posting.amount), 0) into v_cash
  from public.journal_postings as posting
  join public.financial_operations as operation
    on operation.id = posting.operation_id
  where operation.id = (v_result ->> 'operation_id')::uuid;
  if v_cash <> 0
    or (select count(*) from public.journal_postings as posting
        join public.journals as journal on journal.id = posting.journal_id
        where posting.operation_id = (v_result ->> 'operation_id')::uuid
          and journal.unit_kind = 'money') <> 2
    or (select count(*) from public.journals
        where operation_id = (v_result ->> 'operation_id')::uuid
          and unit_kind <> 'money') <> 0 then
    raise exception 'partial_journal_wrong';
  end if;
  if (select count(*) from public.repair_custody_events
      where repair_id = v_partial and direction = 'release') <> 1
    or (select count(*) from public.inventory_lots where shop_id = v_shop) <> v_lots
    or (select count(*) from public.inventory_lot_movements where shop_id = v_shop) <> v_moves
    or (select count(*) from public.inventory_receipts where shop_id = v_shop) <> v_receipts
    or (select count(*) from public.gold_obligations where shop_id = v_shop) <> v_gold
    or (select count(*) from public.purchase_cash_payables where shop_id = v_shop) <> v_payables
    or (select count(*) from public.inventory_lot_sync where shop_id = v_shop) <> v_sync + 1
    or (select estimated_fee_piastres from public.repairs where id = v_partial) <> 15000 then
    raise exception 'partial_touched_custody_stock';
  end if;
  begin
    perform public.post_repair_handover_v1(
      'c1444444-4444-4444-8444-444444444409',
      jsonb_build_object(
        'version', 1, 'kind', 'repair_handover', 'repair_id', v_partial,
        'expected_version', '4', 'final_fee_piastres', '20000',
        'collection', 'none', 'collected_piastres', '0', 'tenders', '[]'::jsonb
      )
    );
    raise exception 'second_handover_accepted';
  exception
    when others then
      if sqlerrm is distinct from 'repair_not_ready' then
        raise exception 'second_handover_got_%', sqlerrm;
      end if;
  end;
  if (select count(*) from public.repair_custody_events
      where repair_id = v_partial and direction = 'release') <> 1 then
    raise exception 'duplicate_release';
  end if;

  v_result := public.post_repair_intake_v1(
    'c1444444-4444-4444-8444-444444444410',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'بدون تحصيل', 'customer_phone', '',
      'item_description', 'سلسلة', 'measured_milligrams', '2000',
      'karat', 18, 'issue', 'قص', 'intake_notes', '',
      'estimated_fee_piastres', null
    )
  );
  v_none := (v_result ->> 'repair_id')::uuid;
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444411',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_none,
      'expected_version', '1', 'status', 'in_progress'));
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444412',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_none,
      'expected_version', '2', 'status', 'ready'));
  v_state := public.get_daily_ledger_day_state();
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  v_result := public.post_repair_handover_v1(
    'c1444444-4444-4444-8444-444444444413',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_handover', 'repair_id', v_none,
      'expected_version', '3', 'final_fee_piastres', '20000',
      'collection', 'none', 'collected_piastres', '0', 'tenders', '[]'::jsonb
    )
  );
  if v_result ->> 'operation_id' is not null
    or v_result ->> 'outstanding_piastres' is distinct from '20000'
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select day_version::text from public.business_days where id = (v_state ->> 'business_day_id')::uuid)
       is distinct from (v_state ->> 'day_version')
    or (select count(*) from public.gold_obligations where shop_id = v_shop) <> 0 then
    raise exception 'unpaid_delivery_posted_cash';
  end if;

  v_result := public.post_repair_intake_v1(
    'c1444444-4444-4444-8444-444444444414',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'تحصيل كامل', 'customer_phone', '',
      'item_description', 'غويشة', 'measured_milligrams', '3000',
      'karat', 22, 'issue', 'تلميع', 'intake_notes', '',
      'estimated_fee_piastres', '0'
    )
  );
  v_all := (v_result ->> 'repair_id')::uuid;
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444415',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_all,
      'expected_version', '1', 'status', 'in_progress'));
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444416',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_all,
      'expected_version', '2', 'status', 'ready'));
  v_state := public.get_daily_ledger_day_state();
  v_result := public.post_repair_handover_v1(
    'c1444444-4444-4444-8444-444444444417',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_handover', 'repair_id', v_all,
      'expected_version', '3', 'final_fee_piastres', '20000',
      'collection', 'all', 'collected_piastres', '20000',
      'tenders', jsonb_build_array(
        jsonb_build_object('method', 'cash', 'piastres', '12000'),
        jsonb_build_object('method', 'wallet', 'piastres', '8000')
      ),
      'expected_day_id', v_state ->> 'business_day_id',
      'expected_day_version', v_state ->> 'day_version'
    )
  );
  if v_result ->> 'outstanding_piastres' is distinct from '0' then
    raise exception 'full_collection_left_outstanding';
  end if;
  select coalesce(sum(posting.amount), 0) into v_cash
  from public.journal_postings as posting
  join public.ledger_accounts as account on account.id = posting.account_id
  where account.shop_id = v_shop and account.method_code = 'cash';
  select coalesce(sum(posting.amount), 0) into v_wallet
  from public.journal_postings as posting
  join public.ledger_accounts as account on account.id = posting.account_id
  where account.shop_id = v_shop and account.method_code = 'wallet';
  if v_cash <> 520000 or v_wallet <> 108000 then
    raise exception 'split_tender_balances_wrong';
  end if;

  v_result := public.post_repair_intake_v1(
    'c1444444-4444-4444-8444-444444444418',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'إلغاء', 'customer_phone', '',
      'item_description', 'أسورة', 'measured_milligrams', '1000',
      'karat', 14, 'issue', 'كسر', 'intake_notes', '',
      'estimated_fee_piastres', null
    )
  );
  v_cancel := (v_result ->> 'repair_id')::uuid;
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444419',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_cancel,
      'expected_version', '1', 'status', 'in_progress'));
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  v_result := public.post_repair_cancel_v1(
    'c1444444-4444-4444-8444-444444444420',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_cancel', 'repair_id', v_cancel,
      'expected_version', '2', 'reason', 'إرجاع للعميل', 'confirm_return', true
    )
  );
  if v_result ->> 'cash_piastres' is distinct from '0'
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select count(*) from public.repair_custody_events
        where repair_id = v_cancel and direction = 'release') <> 1
    or (select custody_held from public.repairs where id = v_cancel) then
    raise exception 'cancel_did_not_release_cleanly';
  end if;

  v_cash := (
    select coalesce(sum(posting.amount), 0)
    from public.journal_postings as posting
    join public.ledger_accounts as account on account.id = posting.account_id
    where account.shop_id = v_shop and account.account_kind = 'cash_method'
  );
  perform public.post_repair_archive_v1(
    'c1444444-4444-4444-8444-444444444421',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_archive', 'repair_id', v_partial,
      'expected_version', '4', 'confirm_archive', true
    )
  );
  if (select outstanding_piastres from public.repairs where id = v_partial) <> 12000
    or (select status from public.repairs where id = v_partial) <> 'archived'
    or (
      select coalesce(sum(posting.amount), 0)
      from public.journal_postings as posting
      join public.ledger_accounts as account on account.id = posting.account_id
      where account.shop_id = v_shop and account.account_kind = 'cash_method'
    ) <> v_cash then
    raise exception 'archive_changed_money';
  end if;
  v_page := public.get_repair_context_v1();
  if jsonb_array_length(v_page -> 'cash_methods') <> 4
    or v_page -> 'day' ->> 'state' <> 'open' then
    raise exception 'repair_context_read_failed';
  end if;
  v_page := public.get_daily_ledger_v2();
  if not exists (
    select 1 from jsonb_array_elements(v_page -> 'feed') as fee(value)
    where value ->> 'kind' = 'repair_fee'
      and value ->> 'total_pounds' = '80.00'
      and value ->> 'party_name' = 'عميل الإصلاح'
  ) then
    raise exception 'repair_fee_ledger_summary_missing';
  end if;
  v_page := public.list_repairs_v1('', 'outstanding', 20, null);
  if not exists (
    select 1 from jsonb_array_elements(v_page -> 'items') as item
    where item ->> 'repair_id' = v_partial::text
  ) then
    raise exception 'archived_outstanding_hidden';
  end if;
  v_page := public.list_repairs_v1('عميل الإصلاح', 'open', 20, null);
  if jsonb_array_length(v_page -> 'items') <> 0 then
    raise exception 'archived_still_open';
  end if;
  v_page := public.list_repairs_v1('', 'all', 1, null);
  if v_page ->> 'next_cursor' is null then
    raise exception 'repair_page_missing_cursor';
  end if;
  if (select repair_revision from public.shop_sync_signals where shop_id = v_shop) <= 0 then
    raise exception 'repair_sync_not_bumped';
  end if;

  v_result := public.post_repair_intake_v1(
    'c1444444-4444-4444-8444-444444444422',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'جاهز', 'customer_phone', '',
      'item_description', 'خاتم', 'measured_milligrams', '1000',
      'karat', 24, 'issue', 'توسيع', 'intake_notes', '',
      'estimated_fee_piastres', null
    )
  );
  v_ready := (v_result ->> 'repair_id')::uuid;
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444423',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_ready,
      'expected_version', '1', 'status', 'in_progress'));
  perform public.post_repair_status_v1('c1444444-4444-4444-8444-444444444424',
    jsonb_build_object('version', 1, 'kind', 'repair_status', 'repair_id', v_ready,
      'expected_version', '2', 'status', 'ready'));
  perform set_config('eldafttar.repair_test_id', v_partial::text, true);
end;
$owner$;

do $all_karats$
declare v_karat integer; v_id uuid; v_payload jsonb; v_original timestamptz;
begin
  foreach v_karat in array array[14,18,21,22,24] loop
    v_payload := public.post_repair_intake_v1(gen_random_uuid(), jsonb_build_object(
      'version',1,'kind','repair_intake','customer_name','اختبار العيار','customer_phone','',
      'item_description','قطعة اختبار','measured_milligrams','1255','karat',v_karat,
      'issue','فحص','intake_notes','','estimated_fee_piastres',null));
    v_id := (v_payload ->> 'repair_id')::uuid;
    if (select measured_milligrams from public.repairs where id=v_id) <> 1255
      or (select karat from public.repairs where id=v_id) <> v_karat then
      raise exception 'repair_karat_precision_lost';
    end if;
  end loop;
  select intake_at into v_original from public.repairs where id=v_id;
  perform set_config('TimeZone','Asia/Tokyo',true);
  v_payload := public.get_repair_v1(v_id);
  if v_payload ->> 'intake_at' not like '%Z'
    or (v_payload ->> 'intake_at')::timestamptz <> v_original then
    raise exception 'repair_wire_utc_lost';
  end if;
  perform set_config('TimeZone','UTC',true);
end;
$all_karats$;

reset role;
update public.shops set time_zone='Asia/Riyadh' where id='c1222222-2222-4222-8222-222222222222';
set local role authenticated;
do $display_zone$
declare v_id uuid; v_payload jsonb; v_at timestamptz;
begin
  select id,intake_at into v_id,v_at from public.repairs order by intake_at limit 1;
  v_payload := public.get_repair_v1(v_id);
  if v_payload ->> 'intake_at_shop' <> to_char(v_at at time zone 'Asia/Riyadh','YYYY-MM-DD"T"HH24:MI:SS')
    or (v_payload ->> 'intake_at')::timestamptz <> v_at then
    raise exception 'repair_display_zone_changed_instant';
  end if;
end;
$display_zone$;


select set_config('request.jwt.claim.sub', 'c2111111-1111-4111-8111-111111111111', true);
do $other$
begin
  if (select count(*) from public.repairs) <> 0 then
    raise exception 'cross_shop_repairs_visible';
  end if;
end;
$other$;
select pg_temp.expect_code(
  'select public.get_repair_v1(' || quote_literal(current_setting('eldafttar.repair_test_id')) || '::uuid)',
  'not_found'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c7111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"c7111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select public.confirm_opening_balances(
  'c1555555-5555-4555-8555-555555555501',
  '{"version":1,"cash":{"cash":"1000"},"stock":[],"scrap":[]}'::jsonb
);
do $expired_write$
declare v_repair uuid;
begin
  v_repair := (public.post_repair_intake_v1(
    'c1555555-5555-4555-8555-555555555502',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'قبل الانتهاء', 'customer_phone', '',
      'item_description', 'خاتم', 'measured_milligrams', '1000',
      'karat', 21, 'issue', 'فحص', 'intake_notes', '',
      'estimated_fee_piastres', null
    )
  ) ->> 'repair_id')::uuid;
  if v_repair is null then
    raise exception 'pre_expiry_intake_failed';
  end if;
end;
$expired_write$;
reset role;
update public.shop_entitlements
  set expires_at = now() - interval '1 hour'
  where shop_id = 'c7222222-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c7111111-1111-4111-8111-111111111111', true);
do $expired_read$
begin
  if jsonb_array_length(public.list_repairs_v1('', 'all', 20, null) -> 'items') <> 1 then
    raise exception 'expired_read_denied';
  end if;
end;
$expired_read$;
select pg_temp.expect_code(
  'select public.post_repair_intake_v1(''c1555555-5555-4555-8555-555555555503'', ''{"version":1,"kind":"repair_intake","customer_name":"بعد","customer_phone":"","item_description":"خاتم","measured_milligrams":"1000","karat":21,"issue":"فحص","intake_notes":"","estimated_fee_piastres":null}''::jsonb)',
  'shop_not_active'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', true);
do $direct$
begin
  begin
    delete from public.repairs;
    raise exception 'direct_delete_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'direct_delete_got_%', sqlerrm;
  end;
end;
$direct$;

reset role;
do $trigger$
declare v_id uuid; v_table text;
begin
  select id into v_id from public.repairs
  where shop_id = 'c1222222-2222-4222-8222-222222222222' limit 1;
  begin
    update public.repairs set customer_name = 'تغيير' where id = v_id;
    raise exception 'immutable_update_allowed';
  exception
    when others then
      if sqlerrm is distinct from 'audit_append_only' then
        raise exception 'immutable_update_got_%', sqlerrm;
      end if;
  end;
  begin
    delete from public.repairs where id = v_id;
    raise exception 'hard_delete_allowed';
  exception
    when others then
      if sqlerrm is distinct from 'audit_append_only' then
        raise exception 'hard_delete_got_%', sqlerrm;
      end if;
  end;
  foreach v_table in array array['repair_events','repair_custody_events','repair_command_requests'] loop
    begin
      execute format('update public.%I set created_at=clock_timestamp()',v_table);
      raise exception 'history_mutation_allowed';
    exception when others then
      if sqlerrm <> 'audit_append_only' then raise exception 'history_guard_failed_%',sqlerrm; end if;
    end;
  end loop;
end;
$trigger$;

rollback;

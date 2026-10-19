-- DEBT-01. Synthetic rows roll back. Linked payables and gold obligations stay
-- authoritative; this gate never copies them into shop_debts.
begin;

-- Trade edit/delete revokes authenticated EXECUTE on return and exchange
-- writers. This fixture restores that privilege only inside this rolled-back
-- transaction so historic return math still runs. It is not a production grant.
grant execute on function public.post_daily_ledger_return(uuid, uuid, text) to authenticated;
grant execute on function public.post_linked_return_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_exchange_v1(uuid, jsonb) to authenticated;

create function pg_temp.debt_fail_after_write() returns trigger
language plpgsql as $failure$
begin
  if current_setting('eldafttar.debt_fail_after_write', true) = '1' then
    raise exception 'debt_test_failure';
  end if;
  return new;
end;
$failure$;
create trigger debt_test_failure after insert on public.debt_command_requests
for each row execute function pg_temp.debt_fail_after_write();

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, deleted_at, created_at, updated_at
) values
  ('d1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-owner@example.test', false, null, now(), now()),
  ('d2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-other@example.test', false, null, now(), now()),
  ('d3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-revoked@example.test', false, null, now(), now()),
  ('d4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-anon@example.test', true, null, now(), now()),
  ('d5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-admin@example.test', false, null, now(), now()),
  ('d6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-pending@example.test', false, null, now(), now()),
  ('d7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'debt-expired@example.test', false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('d1222222-2222-4222-8222-222222222222', 'متجر الديون', 'مالك الديون', 'Africa/Cairo'),
  ('d2222222-2222-4222-8222-222222222222', 'متجر آخر', 'مالك آخر', 'Africa/Cairo'),
  ('d3222222-2222-4222-8222-222222222222', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('d4222222-2222-4222-8222-222222222222', 'متجر مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('d6222222-2222-4222-8222-222222222222', 'متجر معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('d7222222-2222-4222-8222-222222222222', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('d1222222-2222-4222-8222-222222222222', 'd1111111-1111-4111-8111-111111111111', 'owner', null),
  ('d2222222-2222-4222-8222-222222222222', 'd2111111-1111-4111-8111-111111111111', 'owner', null),
  ('d3222222-2222-4222-8222-222222222222', 'd3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('d4222222-2222-4222-8222-222222222222', 'd4111111-1111-4111-8111-111111111111', 'owner', null),
  ('d6222222-2222-4222-8222-222222222222', 'd6111111-1111-4111-8111-111111111111', 'owner', null),
  ('d7222222-2222-4222-8222-222222222222', 'd7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('d1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('d2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('d3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('d4222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('d7222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

insert into public.platform_admins (user_id)
values ('d5111111-1111-4111-8111-111111111111');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('d1818181-8181-4181-8181-818181818181', 'd1111111-1111-4111-8111-111111111111', now(), now(), now() + interval '1 day'),
  ('d1818181-8181-4181-8181-818181818182', 'd1111111-1111-4111-8111-111111111111', now(), now(), now() - interval '1 minute');

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

create function pg_temp.declare_payload(
  p_direction text, p_unit text, p_karat jsonb, p_amount text,
  p_party text, p_reason text, p_external jsonb
) returns jsonb language sql immutable as $fn$
  select pg_catalog.jsonb_build_object(
    'version', 1, 'kind', 'debt_declare', 'direction', p_direction, 'unit', p_unit,
    'karat', p_karat, 'amount', p_amount, 'party_name', p_party,
    'contact_phone', '', 'reason', p_reason, 'external_reference', p_external
  );
$fn$;

create function pg_temp.settle_payload(
  p_kind text, p_id uuid, p_direction text, p_unit text, p_karat jsonb,
  p_amount text, p_remaining text, p_version jsonb, p_effect text, p_reason text,
  p_reference uuid, p_day jsonb, p_day_version jsonb, p_tenders jsonb,
  p_deliveries jsonb, p_receipt jsonb
) returns jsonb language sql immutable as $fn$
  select pg_catalog.jsonb_build_object(
    'version', 1, 'kind', 'debt_settle', 'source_kind', p_kind, 'source_id', p_id,
    'direction', p_direction, 'unit', p_unit, 'karat', p_karat, 'amount', p_amount,
    'expected_remaining', p_remaining, 'expected_version', p_version,
    'ledger_effect', p_effect, 'reason', p_reason, 'settlement_reference', p_reference,
    'expected_day_id', p_day, 'expected_day_version', p_day_version,
    'tenders', p_tenders, 'deliveries', p_deliveries, 'receipt', p_receipt
  );
$fn$;

do $priv$
begin
  if private.ledger_operation_label('debt_settlement') is distinct from 'سداد دين'
    or private.ledger_operation_label('repair_fee') is distinct from 'أجرة إصلاح'
    or private.ledger_operation_label('purchase_settlement') is distinct from 'سداد شراء'
    or private.ledger_operation_label('gold_obligation_acquisition') is distinct from 'استلام ذهب مقابل التزام'
    or private.ledger_operation_label('gold_obligation_settlement') is distinct from 'سداد التزام ذهب' then
    raise exception 'debt_label_regressed';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shop_sync_signals'
      and column_name = 'debt_revision' and is_nullable = 'NO'
  ) then
    raise exception 'debt_revision_missing';
  end if;
  if has_function_privilege('anon', 'public.post_debt_declare_v1(uuid, jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.post_debt_settle_v1(uuid, jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_debt_list_v1(text, text, integer, text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_debt_v1(text, uuid)', 'EXECUTE')
    or has_function_privilege('public', 'public.post_debt_declare_v1(uuid, jsonb)', 'EXECUTE')
    or has_table_privilege('anon', 'public.shop_debts', 'SELECT')
    or has_table_privilege('authenticated', 'public.shop_debts', 'INSERT')
    or has_table_privilege('authenticated', 'public.shop_debts', 'UPDATE')
    or has_table_privilege('authenticated', 'public.shop_debts', 'DELETE')
    or has_table_privilege('authenticated', 'public.debt_events', 'INSERT')
    or has_table_privilege('authenticated', 'public.debt_command_requests', 'INSERT')
    or has_table_privilege('authenticated', 'public.debt_source_archives', 'INSERT')
    or has_table_privilege('authenticated', 'public.debt_settlement_references', 'UPDATE') then
    raise exception 'debt_privileges_were_too_wide';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'shop_debts', 'debt_events', 'debt_command_requests',
        'debt_source_archives', 'debt_settlement_references'
      )
      and cmd <> 'SELECT'
  ) then
    raise exception 'debt_client_write_policy';
  end if;
end;
$priv$;

set local role anon;
do $anon$
begin
  begin
    perform public.get_debt_list_v1('', 'open', 20, null);
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
  'select public.get_debt_list_v1('''', ''open'', 20, null)',
  'unauthenticated'
);

select set_config('request.jwt.claim.sub', 'd1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"d1818181-8181-4181-8181-818181818182","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_debt_context_v1()', 'session_expired');

select set_config('request.jwt.claims',
  '{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select set_config('request.jwt.claim.sub', 'd3111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_debt_list_v1('''', ''open'', 20, null)', 'forbidden');
select set_config('request.jwt.claim.sub', 'd4111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code(
  'select public.get_debt_v1(''standalone'', ''d3000000-0000-4000-8000-000000000001'')',
  'forbidden'
);
select set_config('request.jwt.claim.sub', 'd5111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_debt_list_v1('''', ''all'', 20, null)', 'forbidden');
select set_config('request.jwt.claim.sub', 'd6111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_debt_context_v1()', 'shop_unavailable');

select set_config('request.jwt.claim.sub', 'd1111111-1111-4111-8111-111111111111', true);
select public.confirm_opening_balances(
  'd3000000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"500000","wallet":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"1"}],"scrap":[{"karat":21,"milligrams":"3000"}]}'::jsonb
);

do $owner$
declare
  v_shop uuid := 'd1222222-2222-4222-8222-222222222222';
  v_day jsonb;
  v_result jsonb;
  v_detail jsonb;
  v_page jsonb;
  v_money uuid;
  v_gold_in uuid;
  v_cancel uuid;
  v_archive uuid;
  v_purchase uuid;
  v_history uuid;
  v_obligation uuid;
  v_scrap uuid;
  v_ops bigint;
  v_lots bigint;
  v_receipts bigint;
  v_custody bigint;
  v_sales bigint;
  v_debts bigint;
  v_cash bigint;
  v_debt_rev bigint;
  v_repair_rev bigint;
  v_ledger_rev bigint;
  v_day_version bigint;
  v_payable bigint;
  v_stored timestamptz;
  v_base_mg bigint;
  v_base_count bigint;
  v_trader uuid;
  v_return uuid;
begin
  v_day := public.get_daily_ledger_day_state();
  if v_day ->> 'state' is distinct from 'open' then
    raise exception 'opening_day_missing %', v_day;
  end if;
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  v_lots := (select count(*) from public.inventory_lots where shop_id = v_shop);
  v_receipts := (select count(*) from public.inventory_receipts where shop_id = v_shop);
  v_custody := (select count(*) from public.repair_custody_events where shop_id = v_shop);
  v_sales := (select count(*) from public.financial_operations where shop_id = v_shop and kind = 'sale');
  v_cash := (
    select coalesce(sum(posting.amount), 0)
    from public.journal_postings as posting
    join public.ledger_accounts as account
      on account.shop_id = posting.shop_id and account.id = posting.account_id
    where posting.shop_id = v_shop and account.account_kind = 'cash_method'
      and account.method_code = 'cash'
  );
  if v_lots <> 2 or v_cash <> 500000 or v_receipts <> 0 then
    raise exception 'opening_fixture_unexpected lots % cash % receipts %', v_lots, v_cash, v_receipts;
  end if;

  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000010',
      pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '9223372036854775808', 'طرف', 'تجاوز', 'null'::jsonb)
    ),
    'overflow'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000011',
      pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '-1', 'طرف', 'سالب', 'null'::jsonb)
    ),
    'negative_amount'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000012',
      pg_temp.declare_payload('shop_owes', 'gold', '21'::jsonb, '1000', 'طرف', 'سبب', 'null'::jsonb)
        || '{"created_at":"2026-01-01T00:00:00Z"}'::jsonb
    ),
    'invalid_input'
  );

  v_debt_rev := (select debt_revision from public.shop_sync_signals where shop_id = v_shop);
  v_repair_rev := (select repair_revision from public.shop_sync_signals where shop_id = v_shop);
  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000020',
    pg_temp.declare_payload(
      'shop_owes', 'money', 'null'::jsonb, '10000', 'طرف تاريخي',
      'دين خارجي قبل النظام', '"EXT-1"'::jsonb
    )
  );
  v_money := (v_result ->> 'source_id')::uuid;
  if v_result ->> 'ok' is distinct from 'true'
    or v_result ->> 'replayed' is distinct from 'false'
    or v_result ->> 'ledger_effect' is distinct from 'none'
    or v_result ->> 'operation_id' is not null
    or v_result ->> 'cash_piastres' is distinct from '0'
    or v_result ->> 'gold_milligrams' is distinct from '0'
    or v_result ->> 'custody_milligrams' is distinct from '0'
    or v_result ->> 'saleable_stock_milligrams' is distinct from '0'
    or v_result ->> 'display_status' is distinct from 'open'
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select count(*) from public.inventory_lots where shop_id = v_shop) <> v_lots
    or (select debt_revision - v_debt_rev from public.shop_sync_signals where shop_id = v_shop) <> 2
    or (select repair_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_repair_rev then
    raise exception 'declare_effect_not_zero %', v_result;
  end if;
  select debt.created_at into v_stored from public.shop_debts as debt where debt.id = v_money;
  v_detail := public.get_debt_v1('standalone', v_money);
  if v_detail ->> 'created_at' !~ 'Z$'
    or v_detail ->> 'created_at_shop' is distinct from
      pg_catalog.to_char(v_stored at time zone 'Africa/Cairo', 'YYYY-MM-DD"T"HH24:MI:SS')
    or (v_detail ->> 'created_at')::timestamptz is distinct from v_stored
    or v_detail ->> 'time_zone' is distinct from 'Africa/Cairo'
    or jsonb_array_length(v_detail -> 'history') <> 1
    or v_detail -> 'history' -> 0 ->> 'label_ar' is distinct from 'تسجيل دين'
    or v_detail -> 'history' -> 0 ->> 'actor_user_id'
      is distinct from 'd1111111-1111-4111-8111-111111111111'
    or v_detail -> 'history' -> 0 ->> 'actor_display_name' is distinct from 'مالك الديون'
    or v_detail ->> 'cancelled_amount' is distinct from '0'
    or v_detail ->> 'settled_amount' is distinct from '0'
    or (v_detail ->> 'original_amount')::bigint
      is distinct from (v_detail ->> 'settled_amount')::bigint
        + (v_detail ->> 'cancelled_amount')::bigint
        + (v_detail ->> 'remaining_amount')::bigint then
    raise exception 'declare_clock_or_history %', v_detail;
  end if;
  if (public.post_debt_declare_v1(
      'd3000000-0000-4000-8000-000000000020',
      pg_temp.declare_payload(
        'shop_owes', 'money', 'null'::jsonb, '10000', 'طرف تاريخي',
        'دين خارجي قبل النظام', '"EXT-1"'::jsonb
      )
    ) ->> 'replayed') is distinct from 'true'
    or (select count(*) from public.shop_debts where shop_id = v_shop) <> 1 then
    raise exception 'declare_replay_duplicated';
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000020',
      pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '10000', 'طرف آخر', 'سبب مختلف', 'null'::jsonb)
    ),
    'payload_mismatch'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000021',
      pg_temp.declare_payload('owed_to_shop', 'money', 'null'::jsonb, '500', 'طرف مكرر', 'مرجع مكرر', '"EXT-1"'::jsonb)
    ),
    'duplicate_reference'
  );
  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000120',
    pg_temp.declare_payload(
      'shop_owes', 'money', 'null'::jsonb, '1500', 'طرف مطابق', 'التزام بلا مرجع', 'null'::jsonb
    )
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000121',
      pg_temp.declare_payload(
        'shop_owes', 'money', 'null'::jsonb, '1500', 'طرف مطابق', 'التزام بلا مرجع', 'null'::jsonb
      )
    ),
    'duplicate_debt'
  );
  if (select count(*) from public.shop_debts
      where shop_id = v_shop and party_name = 'طرف مطابق') <> 1 then
    raise exception 'identical_declaration_was_reused';
  end if;
  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000122',
    pg_temp.declare_payload(
      'shop_owes', 'money', 'null'::jsonb, '1500', 'طرف مطابق', 'التزام بلا مرجع', '"مرجع-مختلف"'::jsonb
    )
  );
  if v_result ->> 'source_id' is null
    or (select count(*) from public.shop_debts
        where shop_id = v_shop and party_name = 'طرف مطابق') <> 2 then
    raise exception 'distinct_reference_rejected %', v_result;
  end if;

  v_result := public.post_repair_intake_v1(
    'd3000000-0000-4000-8000-000000000022',
    '{"version":1,"kind":"repair_intake","customer_name":"عميل الصيانة","customer_phone":"","item_description":"خاتم","measured_milligrams":"1255","karat":21,"issue":"فحص","intake_notes":"","estimated_fee_piastres":"15000"}'::jsonb
  );
  if v_result ->> 'repair_id' is null
    or jsonb_array_length(public.get_debt_list_v1('عميل الصيانة', 'all', 20, null) -> 'items') <> 0 then
    raise exception 'repair_imported_as_debt %', v_result;
  end if;

  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_daily_ledger_trade(
    'd3000000-0000-4000-8000-000000000030',
    '{"version":1,"kind":"purchase","total_piastres":"10000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"1","item_name":"سوار أرشيف","line_price_piastres":null}],"description":"","customer_name":"تاجر الأرشيف","customer_phone":"","note":"","purchase_obligation_piastres":"6000"}'::jsonb
  );
  v_history := (v_result ->> 'operation_id')::uuid;
  perform public.settle_purchase_cash_payable(
    'd3000000-0000-4000-8000-000000000031', v_history,
    '[{"method":"cash","piastres":"2000"}]'::jsonb
  );
  v_day := public.get_daily_ledger_day_state();
  perform public.post_linked_return_v1(
    'd3000000-0000-4000-8000-000000000032',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'purchase_return', 'original_operation_id', v_history,
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version',
      'note', 'مرتجع شراء للسجل',
      'items', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'item_index', '0', 'milligrams', '2000', 'count', '1'
      )),
      'consideration_piastres', '4000',
      'tenders', '[]'::jsonb
    )
  );
  v_detail := public.get_debt_v1('purchase_cash_payable', v_history);
  if v_detail ->> 'reason' is distinct from 'رصيد شراء آجل'
    or v_detail ->> 'party_name' is distinct from 'تاجر الأرشيف'
    or v_detail ->> 'contact_phone' is not null
    or v_detail ->> 'original_amount' is distinct from '6000'
    or v_detail ->> 'settled_amount' is distinct from '2000'
    or v_detail ->> 'cancelled_amount' is distinct from '4000'
    or v_detail ->> 'remaining_amount' is distinct from '0'
    or (select count(*) from public.shop_debts where id = v_history) <> 0
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'label_ar' = 'شراء'
    ) <> 1
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'label_ar' = 'سداد شراء'
    ) <> 1
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'label_ar' = 'مرتجع شراء'
    ) <> 1
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'actor_user_id' is null
        or entry.value ->> 'actor_display_name' is distinct from 'مالك الديون'
        or entry.value ->> 'label_ar' ~ '[A-Za-z_]'
    ) then
    raise exception 'source_history_missing %', v_detail;
  end if;

  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_daily_ledger_trade(
    'd3000000-0000-4000-8000-000000000033',
    '{"version":1,"kind":"purchase","total_piastres":"8000","tenders":[],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم آجل","line_price_piastres":null}],"description":"","customer_name":"تاجر السداد","customer_phone":"01000000000","note":"","purchase_obligation_piastres":"8000"}'::jsonb
  );
  v_purchase := (v_result ->> 'operation_id')::uuid;
  if (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase) <> 8000
    or (select count(*) from public.shop_debts where id = v_purchase) <> 0 then
    raise exception 'payable_was_copied';
  end if;
  v_page := public.get_debt_list_v1('تاجر السداد', 'open', 20, null);
  if jsonb_array_length(v_page -> 'items') <> 1
    or v_page -> 'items' -> 0 ->> 'source_kind' is distinct from 'purchase_cash_payable'
    or v_page -> 'items' -> 0 ->> 'remaining_amount' is distinct from '8000'
    or v_page -> 'items' -> 0 ->> 'original_amount' is distinct from '8000'
    or v_page -> 'items' -> 0 ->> 'settled_amount' is distinct from '0'
    or v_page -> 'items' -> 0 ->> 'cancelled_amount' is distinct from '0'
    or v_page -> 'items' -> 0 ->> 'contact_phone' is distinct from '01000000000' then
    raise exception 'payable_not_live %', v_page;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_settle_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000034',
      pg_temp.settle_payload(
        'purchase_cash_payable', v_purchase, 'shop_owes', 'money', 'null'::jsonb,
        '1000', '8000', 'null'::jsonb, 'none', 'بلا قيد مرفوض',
        'd3000000-0000-4000-8000-000000000034', 'null'::jsonb, 'null'::jsonb,
        'null'::jsonb, 'null'::jsonb, 'null'::jsonb
      )
    ),
    'ledger_effect_required'
  );
  v_day := public.get_daily_ledger_day_state();
  v_ledger_rev := (select ledger_revision from public.shop_sync_signals where shop_id = v_shop);
  v_cash := (
    select coalesce(sum(posting.amount), 0)
    from public.journal_postings as posting
    join public.ledger_accounts as account
      on account.shop_id = posting.shop_id and account.id = posting.account_id
    where posting.shop_id = v_shop and account.account_kind = 'cash_method'
      and account.method_code = 'cash'
  );
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000035',
    pg_temp.settle_payload(
      'purchase_cash_payable', v_purchase, 'shop_owes', 'money', 'null'::jsonb,
      '3000', '8000', 'null'::jsonb, 'move', 'سداد جزء من الآجل',
      'd3000000-0000-4000-8000-000000000035',
      to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
      '[{"method":"cash","piastres":"2000"},{"method":"wallet","piastres":"1000"}]'::jsonb,
      'null'::jsonb, 'null'::jsonb
    )
  );
  if v_result ->> 'remaining_amount' is distinct from '5000'
    or v_result ->> 'original_amount' is distinct from '8000'
    or v_result ->> 'settled_amount' is distinct from '3000'
    or v_result ->> 'cancelled_amount' is distinct from '0'
    or v_result ->> 'cash_piastres' is distinct from '-3000'
    or v_result ->> 'gold_milligrams' is distinct from '0'
    or v_result ->> 'operation_id' is null
    or (select kind from public.financial_operations where id = (v_result ->> 'operation_id')::uuid)
      is distinct from 'purchase_settlement'
    or (select detail.payload ->> 'kind' from public.financial_operation_details as detail
        where detail.operation_id = (v_result ->> 'operation_id')::uuid)
      is distinct from 'purchase_settlement'
    or (select detail.payload ->> 'purchase_operation_id'
        from public.financial_operation_details as detail
        where detail.operation_id = (v_result ->> 'operation_id')::uuid)
      is distinct from v_purchase::text
    or (select request.payload_canonical ->> 'kind' from public.debt_command_requests as request
        where request.idempotency_key = 'd3000000-0000-4000-8000-000000000035')
      is distinct from 'debt_settle'
    or (select count(*) from public.financial_operations as operation
        where operation.shop_id = v_shop and operation.kind = 'debt_settlement'
          and operation.id = (v_result ->> 'operation_id')::uuid) <> 0
    or (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase) <> 5000
    or (select count(*) from public.shop_debts where id = v_purchase) <> 0
    or (
      select coalesce(sum(posting.amount), 0)
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where posting.shop_id = v_shop and account.account_kind = 'cash_method'
        and account.method_code = 'cash'
    ) <> v_cash - 2000
    or (select ledger_revision from public.shop_sync_signals where shop_id = v_shop) <= v_ledger_rev then
    raise exception 'source_cash_settlement %', v_result;
  end if;
  if (public.post_debt_settle_v1(
      'd3000000-0000-4000-8000-000000000035',
      pg_temp.settle_payload(
        'purchase_cash_payable', v_purchase, 'shop_owes', 'money', 'null'::jsonb,
        '3000', '8000', 'null'::jsonb, 'move', 'سداد جزء من الآجل',
        'd3000000-0000-4000-8000-000000000035',
        to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
        '[{"method":"cash","piastres":"2000"},{"method":"wallet","piastres":"1000"}]'::jsonb,
        'null'::jsonb, 'null'::jsonb
      )
    ) ->> 'replayed') is distinct from 'true'
    or (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase) <> 5000 then
    raise exception 'source_settlement_replay_moved_again';
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_settle_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000036',
      pg_temp.settle_payload(
        'purchase_cash_payable', v_purchase, 'shop_owes', 'money', 'null'::jsonb,
        '1000', '5000', 'null'::jsonb, 'move', 'مرجع مكرر',
        'd3000000-0000-4000-8000-000000000035',
        to_jsonb((public.get_daily_ledger_day_state()) ->> 'business_day_id'),
        to_jsonb((public.get_daily_ledger_day_state()) ->> 'day_version'),
        '[{"method":"cash","piastres":"1000"}]'::jsonb,
        'null'::jsonb, 'null'::jsonb
      )
    ),
    'duplicate_reference'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_settle_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000037',
      pg_temp.settle_payload(
        'purchase_cash_payable', v_purchase, 'shop_owes', 'money', 'null'::jsonb,
        '6000', '5000', 'null'::jsonb, 'move', 'زيادة',
        'd3000000-0000-4000-8000-000000000037',
        to_jsonb((public.get_daily_ledger_day_state()) ->> 'business_day_id'),
        to_jsonb((public.get_daily_ledger_day_state()) ->> 'day_version'),
        '[{"method":"cash","piastres":"6000"}]'::jsonb,
        'null'::jsonb, 'null'::jsonb
      )
    ),
    'settlement_exceeds_obligation'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_cancel_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000038',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'debt_cancel', 'source_kind', 'purchase_cash_payable',
        'source_id', v_purchase, 'expected_remaining', '5000',
        'expected_version', '1', 'reason', 'إلغاء مصدر'
      )
    ),
    'source_cancel_forbidden'
  );

  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_gold_obligation_acquisition_v1(
    'd3000000-0000-4000-8000-000000000040',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'gold_obligation_acquisition',
      'category', 'worked_jewelry', 'karat', 21, 'milligrams', '1000', 'count', '1',
      'item_name', 'غويشة دين', 'obligation_karat', 21, 'obligation_milligrams', '800',
      'counterparty_name', 'تاجر ذهب', 'note', '',
      'denomination_id', null, 'coin_type_id', null,
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version'
    )
  );
  v_obligation := (v_result ->> 'operation_id')::uuid;
  select lot.id into v_scrap
  from public.inventory_lots as lot
  where lot.shop_id = v_shop and lot.category_code = 'scrap' and lot.karat = 21
    and lot.stock_class = 'owned_available';
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000041',
    pg_temp.settle_payload(
      'gold_obligation', v_obligation, 'shop_owes', 'gold', '21'::jsonb,
      '800', '800', 'null'::jsonb, 'move', 'تسليم كسر بنفس العيار',
      'd3000000-0000-4000-8000-000000000041',
      to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
      'null'::jsonb,
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'lot_id', v_scrap, 'milligrams', '800', 'count', null
      )),
      'null'::jsonb
    )
  );
  if v_result ->> 'remaining_amount' is distinct from '0'
    or v_result ->> 'gold_milligrams' is distinct from '-800'
    or v_result ->> 'gold_count' is distinct from '0'
    or v_result ->> 'saleable_stock_milligrams' is distinct from '0'
    or v_result ->> 'cash_piastres' is distinct from '0'
    or v_result ->> 'custody_milligrams' is distinct from '0'
    or (select remaining_milligrams from public.gold_obligations where operation_id = v_obligation) <> 0
    or (select count(*) from public.shop_debts where id = v_obligation) <> 0
    or v_result ->> 'settled_amount' is distinct from '800'
    or v_result ->> 'cancelled_amount' is distinct from '0'
    or v_result ->> 'original_amount' is distinct from '800'
    or (select kind from public.financial_operations where id = (v_result ->> 'operation_id')::uuid)
      is distinct from 'gold_obligation_settlement'
    or (
      select count(*) from pg_catalog.jsonb_array_elements(
        public.get_debt_v1('gold_obligation', v_obligation) -> 'history'
      ) as entry(value)
      where entry.value ->> 'label_ar' = 'سداد التزام ذهب'
    ) <> 1
    or (
      select count(*) from pg_catalog.jsonb_array_elements(
        public.get_debt_v1('gold_obligation', v_obligation) -> 'history'
      ) as entry(value)
      where entry.value ->> 'label_ar' = 'استلام ذهب مقابل التزام'
    ) <> 1
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(
        public.get_debt_v1('gold_obligation', v_obligation) -> 'history'
      ) as entry(value)
      where entry.value ->> 'label_ar' in (
        'gold_obligation_acquisition', 'gold_obligation_settlement'
      )
    ) then
    raise exception 'gold_out_settlement %', v_result;
  end if;

  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000050',
    pg_temp.declare_payload(
      'owed_to_shop', 'gold', '21'::jsonb, '1500', 'عميل الذهب',
      'ذهب وارد تاريخي', 'null'::jsonb
    )
  );
  v_gold_in := (v_result ->> 'source_id')::uuid;
  v_day := public.get_daily_ledger_day_state();
  v_day_version := (v_day ->> 'day_version')::bigint;
  v_sales := (
    select count(*) from public.financial_operations
    where shop_id = v_shop and kind = 'sale'
  );
  v_custody := (
    select count(*) from public.repair_custody_events where shop_id = v_shop
  );
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000051',
    pg_temp.settle_payload(
      'standalone', v_gold_in, 'owed_to_shop', 'gold', '21'::jsonb,
      '1500', '1500', '"1"'::jsonb, 'move', 'استلام مشغول مملوك',
      'd3000000-0000-4000-8000-000000000051',
      to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
      'null'::jsonb, 'null'::jsonb,
      pg_catalog.jsonb_build_object(
        'category', 'worked_jewelry', 'product_name', 'خاتم وارد',
        'milligrams', '1500', 'count', '1'
      )
    )
  );
  if v_result ->> 'gold_milligrams' is distinct from '1500'
    or v_result ->> 'gold_count' is distinct from '1'
    or v_result ->> 'saleable_stock_milligrams' is distinct from '1500'
    or v_result ->> 'custody_milligrams' is distinct from '0'
    or v_result ->> 'display_status' is distinct from 'settled'
    or (select count(*) from public.financial_operations where shop_id = v_shop and kind = 'sale') <> v_sales
    or (select count(*) from public.repair_custody_events where shop_id = v_shop) <> v_custody
    or not exists (
      select 1 from public.inventory_receipts as receipt
      where receipt.operation_id = (v_result ->> 'operation_id')::uuid
        and receipt.owner_kind = 'shop'
        and receipt.custodian_kind = 'shop'
        and receipt.recognition_policy = 'immediate'
        and receipt.trader_id is null
    ) then
    raise exception 'incoming_gold_not_owned %', v_result;
  end if;
  if (public.get_daily_ledger_day_state() ->> 'business_day_id')
      is distinct from (v_day ->> 'business_day_id')
    or (public.get_daily_ledger_day_state() ->> 'day_version')::bigint <= v_day_version then
    raise exception 'move_ignored_open_day';
  end if;

  v_day_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000052',
    pg_temp.settle_payload(
      'standalone', v_money, 'shop_owes', 'money', 'null'::jsonb,
      '2500', '10000', '"1"'::jsonb, 'none', 'تسوية دفترية بلا حركة',
      'd3000000-0000-4000-8000-000000000052',
      'null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb
    )
  );
  if v_result ->> 'ledger_effect' is distinct from 'none'
    or v_result ->> 'operation_id' is not null
    or v_result ->> 'remaining_amount' is distinct from '7500'
    or v_result ->> 'cash_piastres' is distinct from '0'
    or (public.get_daily_ledger_day_state() ->> 'day_version')::bigint is distinct from v_day_version then
    raise exception 'no_ledger_moved_day %', v_result;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_cancel_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000053',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'debt_cancel', 'source_kind', 'standalone',
        'source_id', v_money, 'expected_remaining', '7500',
        'expected_version', '2', 'reason', 'إلغاء بعد سداد'
      )
    ),
    'partly_settled'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_settle_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000054',
      pg_temp.settle_payload(
        'standalone', v_money, 'shop_owes', 'money', 'null'::jsonb,
        '1000', '10000', '"1"'::jsonb, 'none', 'نسخة قديمة',
        'd3000000-0000-4000-8000-000000000054',
        'null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb
      )
    ),
    'stale_debt'
  );

  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000060',
    pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '4000', 'للإلغاء', 'لم يسدد', 'null'::jsonb)
  );
  v_cancel := (v_result ->> 'source_id')::uuid;
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  v_result := public.post_debt_cancel_v1(
    'd3000000-0000-4000-8000-000000000061',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'debt_cancel', 'source_kind', 'standalone',
      'source_id', v_cancel, 'expected_remaining', '4000',
      'expected_version', '1', 'reason', 'تسجيل خاطئ'
    )
  );
  if v_result ->> 'display_status' is distinct from 'cancelled'
    or v_result ->> 'remaining_amount' is distinct from '0'
    or v_result ->> 'original_amount' is distinct from '4000'
    or v_result ->> 'settled_amount' is distinct from '0'
    or v_result ->> 'cancelled_amount' is distinct from '4000'
    or v_result ->> 'cash_piastres' is distinct from '0'
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select status from public.shop_debts where id = v_cancel) is distinct from 'cancelled' then
    raise exception 'cancel_changed_books %', v_result;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_settle_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000062',
      pg_temp.settle_payload(
        'standalone', v_cancel, 'shop_owes', 'money', 'null'::jsonb,
        '1000', '0', '"2"'::jsonb, 'none', 'بعد الإلغاء',
        'd3000000-0000-4000-8000-000000000062',
        'null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb, 'null'::jsonb
      )
    ),
    'settlement_not_allowed'
  );

  v_result := public.post_debt_archive_v1(
    'd3000000-0000-4000-8000-000000000063',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'debt_archive', 'source_kind', 'standalone',
      'source_id', v_cancel, 'expected_remaining', '0',
      'expected_version', '2', 'reason', 'أرشفة الملغى'
    )
  );
  if v_result ->> 'display_status' is distinct from 'archived'
    or (select archived_from_status from public.shop_debts where id = v_cancel) is distinct from 'cancelled'
    or (select remaining_amount from public.shop_debts where id = v_cancel) <> 0
    or v_result ->> 'settled_amount' is distinct from '0'
    or v_result ->> 'cancelled_amount' is distinct from '4000'
    or public.get_debt_v1('standalone', v_cancel) ->> 'cancelled_amount' is distinct from '4000' then
    raise exception 'archive_cancelled_lost_history %', v_result;
  end if;

  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000070',
    pg_temp.declare_payload('owed_to_shop', 'money', 'null'::jsonb, '9000', 'للأرشفة', 'يبقى الرصيد', 'null'::jsonb)
  );
  v_archive := (v_result ->> 'source_id')::uuid;
  v_result := public.post_debt_archive_v1(
    'd3000000-0000-4000-8000-000000000071',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'debt_archive', 'source_kind', 'standalone',
      'source_id', v_archive, 'expected_remaining', '9000',
      'expected_version', '1', 'reason', 'إخفاء مع بقاء الرصيد'
    )
  );
  if v_result ->> 'remaining_amount' is distinct from '9000'
    or public.get_debt_v1('standalone', v_archive) ->> 'can_settle' is distinct from 'true' then
    raise exception 'archive_cleared_remaining %', v_result;
  end if;
  if jsonb_array_length(public.get_debt_list_v1('', 'remaining', 50, null) -> 'items') < 1
    or not exists (
      select 1 from pg_catalog.jsonb_array_elements(
        public.get_debt_list_v1('', 'remaining', 50, null) -> 'items'
      ) as item(value)
      where item.value ->> 'source_id' = v_archive::text
    ) then
    raise exception 'remaining_filter_dropped_archive';
  end if;
  v_payable := (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase);
  v_result := public.post_debt_archive_v1(
    'd3000000-0000-4000-8000-000000000072',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'debt_archive', 'source_kind', 'purchase_cash_payable',
      'source_id', v_purchase, 'expected_remaining', v_payable::text,
      'expected_version', null, 'reason', 'إخفاء الآجل'
    )
  );
  if (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase) <> v_payable
    or public.get_debt_v1('purchase_cash_payable', v_purchase) ->> 'display_status' is distinct from 'archived' then
    raise exception 'source_archive_mutated_payable %', v_result;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_archive_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000073',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'debt_archive', 'source_kind', 'purchase_cash_payable',
        'source_id', v_purchase, 'expected_remaining', v_payable::text,
        'expected_version', null, 'reason', 'أرشفة ثانية'
      )
    ),
    'duplicate_archive'
  );
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000074',
    pg_temp.settle_payload(
      'purchase_cash_payable', v_purchase, 'shop_owes', 'money', 'null'::jsonb,
      '1000', v_payable::text, 'null'::jsonb, 'move', 'سداد بعد الأرشفة',
      'd3000000-0000-4000-8000-000000000074',
      to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
      '[{"method":"wallet","piastres":"1000"}]'::jsonb,
      'null'::jsonb, 'null'::jsonb
    )
  );
  if (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase)
      is distinct from v_payable - 1000 then
    raise exception 'archived_source_settlement_blocked %', v_result;
  end if;

  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000123',
      pg_temp.declare_payload(
        'shop_owes', 'money', 'null'::jsonb, '10', 'إعادة مصدر', 'مرجع عملية',
        to_jsonb(v_purchase::text)
      )
    ),
    'duplicate_debt'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000124',
      pg_temp.declare_payload(
        'shop_owes', 'money', 'null'::jsonb, '11', 'إعادة مصدر', 'مفتاح مصدر',
        to_jsonb('purchase_cash_payable:' || v_purchase::text)
      )
    ),
    'duplicate_debt'
  );
  v_return := (
    select repair.id from public.repairs as repair
    where repair.shop_id = v_shop
    order by repair.intake_at desc
    limit 1
  );
  v_result := public.post_debt_declare_v1(
    'd3000000-0000-4000-8000-000000000125',
    pg_temp.declare_payload(
      'owed_to_shop', 'money', 'null'::jsonb, '12', 'ليس صيانة', 'مرجع صيانة ليس دينا',
      to_jsonb(v_return::text)
    )
  );
  if v_result ->> 'source_kind' is distinct from 'standalone'
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(
        public.get_debt_list_v1('عميل الصيانة', 'all', 20, null) -> 'items'
      ) as item(value)
      where item.value ->> 'source_id' = v_return::text
    ) then
    raise exception 'repair_reference_imported %', v_result;
  end if;

  select
    coalesce(sum(posting.amount) filter (where account.account_kind = 'saleable_metal'), 0)::bigint,
    coalesce(sum(posting.amount) filter (where account.account_kind = 'saleable_count'), 0)::bigint
  into v_base_mg, v_base_count
  from public.ledger_accounts as account
  left join public.journal_postings as posting
    on posting.shop_id = account.shop_id and posting.account_id = account.id
  where account.shop_id = v_shop
    and account.category_code = 'worked_jewelry'
    and account.karat = 21
    and account.account_kind in ('saleable_metal', 'saleable_count');
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_daily_ledger_trade(
    'd3000000-0000-4000-8000-000000000130',
    '{"version":1,"kind":"purchase","total_piastres":"8000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","item_name":"زوج مرتجع","line_price_piastres":null}],"description":"","customer_name":"تاجر المرتجع","customer_phone":"01022222222","note":"","purchase_obligation_piastres":"7000"}'::jsonb
  );
  v_return := (v_result ->> 'operation_id')::uuid;
  v_day := public.get_daily_ledger_day_state();
  perform public.settle_purchase_cash_payable(
    'd3000000-0000-4000-8000-000000000131', v_return,
    '[{"method":"cash","piastres":"1000"}]'::jsonb
  );
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000132',
    pg_temp.settle_payload(
      'purchase_cash_payable', v_return, 'shop_owes', 'money', 'null'::jsonb,
      '2000', '6000', 'null'::jsonb, 'move', 'سداد دين بعد سداد قديم',
      'd3000000-0000-4000-8000-000000000132',
      to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
      '[{"method":"cash","piastres":"2000"}]'::jsonb,
      'null'::jsonb, 'null'::jsonb
    )
  );
  if v_result ->> 'settled_amount' is distinct from '3000'
    or v_result ->> 'cancelled_amount' is distinct from '0'
    or v_result ->> 'remaining_amount' is distinct from '4000'
    or v_result ->> 'original_amount' is distinct from '7000'
    or (select count(*) from public.financial_operations as operation
        join public.financial_operation_details as detail
          on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
        where operation.shop_id = v_shop and operation.kind = 'purchase_settlement'
          and detail.payload ->> 'purchase_operation_id' = v_return::text) <> 2
    or (select count(*) from public.financial_operations as operation
        where operation.shop_id = v_shop and operation.kind = 'debt_settlement'
          and operation.id = (v_result ->> 'operation_id')::uuid) <> 0 then
    raise exception 'mixed_settlement_not_legacy %', v_result;
  end if;
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_linked_return_v1(
    'd3000000-0000-4000-8000-000000000133',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'purchase_return', 'original_operation_id', v_return,
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version',
      'note', 'مرتجع جزء',
      'items', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'item_index', '0', 'milligrams', '1000', 'count', '1'
      )),
      'consideration_piastres', '2000',
      'tenders', '[]'::jsonb
    )
  );
  if v_result ->> 'cancelled_payable_piastres' is distinct from '2000'
    or v_result ->> 'cash_refund_piastres' is distinct from '0' then
    raise exception 'partial_return_refund %', v_result;
  end if;
  v_detail := public.get_debt_v1('purchase_cash_payable', v_return);
  if v_detail ->> 'settled_amount' is distinct from '3000'
    or v_detail ->> 'cancelled_amount' is distinct from '2000'
    or v_detail ->> 'remaining_amount' is distinct from '2000'
    or v_detail ->> 'original_amount' is distinct from '7000'
    or v_detail ->> 'contact_phone' is distinct from '01022222222' then
    raise exception 'partial_return_split %', v_detail;
  end if;
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_linked_return_v1(
    'd3000000-0000-4000-8000-000000000134',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'purchase_return', 'original_operation_id', v_return,
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version',
      'note', 'مرتجع باقي',
      'items', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'item_index', '0', 'milligrams', '1000', 'count', '1'
      )),
      'consideration_piastres', '6000',
      'tenders', '[{"method":"cash","piastres":"4000"}]'::jsonb
    )
  );
  if v_result ->> 'cancelled_payable_piastres' is distinct from '2000'
    or v_result ->> 'cash_refund_piastres' is distinct from '4000' then
    raise exception 'full_return_refund %', v_result;
  end if;
  v_detail := public.get_debt_v1('purchase_cash_payable', v_return);
  select
    coalesce(sum(posting.amount) filter (where account.account_kind = 'saleable_metal'), 0)::bigint,
    coalesce(sum(posting.amount) filter (where account.account_kind = 'saleable_count'), 0)::bigint
  into v_ops, v_lots
  from public.ledger_accounts as account
  left join public.journal_postings as posting
    on posting.shop_id = account.shop_id and posting.account_id = account.id
  where account.shop_id = v_shop
    and account.category_code = 'worked_jewelry'
    and account.karat = 21
    and account.account_kind in ('saleable_metal', 'saleable_count');
  if v_detail ->> 'settled_amount' is distinct from '3000'
    or v_detail ->> 'cancelled_amount' is distinct from '4000'
    or v_detail ->> 'remaining_amount' is distinct from '0'
    or v_detail ->> 'original_amount' is distinct from '7000'
    or (v_detail ->> 'original_amount')::bigint
      is distinct from (v_detail ->> 'settled_amount')::bigint
        + (v_detail ->> 'cancelled_amount')::bigint
        + (v_detail ->> 'remaining_amount')::bigint
    or v_ops is distinct from v_base_mg
    or v_lots is distinct from v_base_count
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'label_ar' = 'سداد شراء'
    ) <> 2
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'event_type' = 'settled'
    ) <> 0 then
    raise exception 'full_return_stock_or_history %', v_detail;
  end if;

  v_day := public.get_daily_ledger_day_state();
  v_result := public.save_trader_v1(
    'd3000000-0000-4000-8000-000000000140',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'trader',
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version',
      'display_name', 'تاجر النشاط', 'phone', '01033333333',
      'note', '', 'active', true
    )
  );
  v_trader := (v_result ->> 'id')::uuid;
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_gold_obligation_acquisition_v1(
    'd3000000-0000-4000-8000-000000000141',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'gold_obligation_acquisition',
      'category', 'worked_jewelry', 'karat', 21, 'milligrams', '1000', 'count', '1',
      'item_name', 'سوار تاجر', 'obligation_karat', 21, 'obligation_milligrams', '1000',
      'counterparty_name', 'تاجر النشاط', 'note', '',
      'denomination_id', null, 'coin_type_id', null, 'trader_id', v_trader,
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version'
    )
  );
  v_obligation := (v_result ->> 'operation_id')::uuid;
  select lot.id into v_scrap
  from public.inventory_lots as lot
  where lot.shop_id = v_shop and lot.category_code = 'scrap' and lot.karat = 21
    and lot.stock_class = 'owned_available'
  order by lot.created_at, lot.id
  limit 1;
  select coalesce(sum(movement.delta_milligrams), 0) into v_cash
  from public.inventory_lot_movements as movement
  where movement.shop_id = v_shop and movement.lot_id = v_scrap;
  v_day := public.get_daily_ledger_day_state();
  perform public.post_gold_obligation_settlement_v1(
    'd3000000-0000-4000-8000-000000000142',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'gold_obligation_settlement',
      'expected_day_id', v_day ->> 'business_day_id',
      'expected_day_version', v_day ->> 'day_version',
      'obligation_operation_id', v_obligation,
      'deliveries', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'lot_id', v_scrap, 'milligrams', '400', 'count', null
      )),
      'reason', 'سداد ذهب قديم'
    )
  );
  v_day := public.get_daily_ledger_day_state();
  v_result := public.post_debt_settle_v1(
    'd3000000-0000-4000-8000-000000000143',
    pg_temp.settle_payload(
      'gold_obligation', v_obligation, 'shop_owes', 'gold', '21'::jsonb,
      '600', '600', 'null'::jsonb, 'move', 'سداد ذهب جديد',
      'd3000000-0000-4000-8000-000000000143',
      to_jsonb(v_day ->> 'business_day_id'), to_jsonb(v_day ->> 'day_version'),
      'null'::jsonb,
      pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'lot_id', v_scrap, 'milligrams', '600', 'count', null
      )),
      'null'::jsonb
    )
  );
  v_detail := public.get_debt_v1('gold_obligation', v_obligation);
  if v_result ->> 'settled_amount' is distinct from '1000'
    or v_result ->> 'cancelled_amount' is distinct from '0'
    or v_result ->> 'remaining_amount' is distinct from '0'
    or v_detail ->> 'contact_phone' is distinct from '01033333333'
    or (
      select count(*) from pg_catalog.jsonb_array_elements(
        public.list_trader_activity_v1(v_trader, 50, null) -> 'items'
      ) as item(value)
      where item.value ->> 'kind' = 'gold_obligation_settlement'
    ) <> 2
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'label_ar' = 'سداد التزام ذهب'
    ) <> 2
    or (
      select count(*) from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'event_type' = 'settled'
    ) <> 0
    or exists (
      select 1 from pg_catalog.jsonb_array_elements(v_detail -> 'history') as entry(value)
      where entry.value ->> 'label_ar' ~ '[A-Za-z_]'
        or entry.value ->> 'actor_user_id' is null
        or entry.value ->> 'actor_display_name' is distinct from 'مالك الديون'
    )
    or (
      select coalesce(sum(movement.delta_milligrams), 0)
      from public.inventory_lot_movements as movement
      where movement.shop_id = v_shop and movement.lot_id = v_scrap
    ) <> v_cash - 1000 then
    raise exception 'trader_gold_activity %', v_detail;
  end if;

  v_page := public.get_debt_list_v1('', 'all', 1, null);
  if jsonb_array_length(v_page -> 'items') <> 1 or v_page ->> 'next_cursor' is null then
    raise exception 'pagination_missing %', v_page;
  end if;
  if jsonb_array_length(public.get_debt_list_v1('', 'all', 20, v_page ->> 'next_cursor') -> 'items') < 1 then
    raise exception 'cursor_page_empty';
  end if;
  perform pg_temp.expect_code(
    'select public.get_debt_list_v1('''', ''open'', 51, null)',
    'invalid_input'
  );

  v_debts := (select count(*) from public.shop_debts where shop_id = v_shop);
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  v_lots := (select count(*) from public.inventory_lots where shop_id = v_shop);
  perform set_config('eldafttar.debt_fail_after_write', '1', true);
  perform pg_temp.expect_code(
    format(
      'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
      'd3000000-0000-4000-8000-000000000080',
      pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '100', 'فشل متأخر', 'يجب التراجع', 'null'::jsonb)
    ),
    'debt_test_failure'
  );
  perform set_config('eldafttar.debt_fail_after_write', '0', true);
  if (select count(*) from public.shop_debts where shop_id = v_shop) <> v_debts
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select count(*) from public.inventory_lots where shop_id = v_shop) <> v_lots
    or exists (
      select 1 from public.debt_command_requests
      where idempotency_key = 'd3000000-0000-4000-8000-000000000080'
    ) then
    raise exception 'late_failure_did_not_roll_back';
  end if;

  perform set_config('eldafttar.debt_source', v_money::text, true);
end;
$owner$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd2111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"d2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $other$
begin
  if (select count(*) from public.shop_debts) <> 0
    or (select count(*) from public.purchase_cash_payables) <> 0 then
    raise exception 'cross_shop_debts_visible';
  end if;
end;
$other$;
select pg_temp.expect_code(
  'select public.get_debt_v1(''standalone'', ''d3000000-0000-4000-8000-000000000020'')',
  'not_found'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd7111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"d7111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select public.confirm_opening_balances(
  'd3000000-0000-4000-8000-000000000090',
  '{"version":1,"cash":{"cash":"1000"},"stock":[],"scrap":[]}'::jsonb
);
select public.post_debt_declare_v1(
  'd3000000-0000-4000-8000-000000000091',
  pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '700', 'قبل الانتهاء', 'سجل سابق', 'null'::jsonb)
);
reset role;
update public.shop_entitlements
  set expires_at = now() - interval '1 hour'
  where shop_id = 'd7222222-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd7111111-1111-4111-8111-111111111111', true);
do $expired_read$
begin
  if jsonb_array_length(public.get_debt_list_v1('', 'all', 20, null) -> 'items') <> 1 then
    raise exception 'expired_read_denied';
  end if;
  if (public.post_debt_declare_v1(
      'd3000000-0000-4000-8000-000000000091',
      pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '700', 'قبل الانتهاء', 'سجل سابق', 'null'::jsonb)
    ) ->> 'replayed') is distinct from 'true' then
    raise exception 'expired_replay_denied';
  end if;
end;
$expired_read$;
select pg_temp.expect_code(
  format(
    'select public.post_debt_declare_v1(%L::uuid, %L::jsonb)',
    'd3000000-0000-4000-8000-000000000092',
    pg_temp.declare_payload('shop_owes', 'money', 'null'::jsonb, '100', 'بعد الانتهاء', 'مرفوض', 'null'::jsonb)
  ),
  'shop_not_active'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $direct$
begin
  begin
    insert into public.shop_debts (
      shop_id, status, record_version, direction, unit, original_amount,
      settled_amount, remaining_amount, party_name, contact_phone, reason,
      declaration_payload, created_at, actor_user_id, updated_at
    ) values (
      'd1222222-2222-4222-8222-222222222222', 'open', 1, 'shop_owes', 'money', 1,
      0, 1, 'مباشر', '', 'سبب', '{}'::jsonb, now(),
      'd1111111-1111-4111-8111-111111111111', now()
    );
    raise exception 'direct_insert_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'direct_insert_got_%', sqlerrm;
  end;
  begin
    update public.debt_events set event_type = 'declared';
    raise exception 'direct_update_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'direct_update_got_%', sqlerrm;
  end;
  begin
    delete from public.debt_command_requests;
    raise exception 'direct_delete_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'direct_delete_got_%', sqlerrm;
  end;
end;
$direct$;

-- Regression: gold debt payload has JSON null tenders. Ledger must remain readable.
do $ledger_debt$
declare v_result jsonb;
begin
  v_result := public.get_daily_ledger_v2();
  if v_result is null then raise exception 'debt_ledger_missing'; end if;
  v_result := public.get_ledger_operation_page(null, null, '1', 100);
  if not exists (select 1 from jsonb_array_elements(v_result -> 'items') row where row ->> 'kind' = 'debt_settlement') then
    raise exception 'debt_ledger_asc_missing';
  end if;
end;
$ledger_debt$;

reset role;
do $gold_karat$
begin
  begin
    insert into public.shop_debts (
      shop_id, status, record_version, direction, unit, karat, original_amount,
      settled_amount, remaining_amount, party_name, contact_phone, reason,
      declaration_payload, created_at, actor_user_id, updated_at
    ) values (
      'd1222222-2222-4222-8222-222222222222', 'open', 1, 'shop_owes', 'gold', null, 1,
      0, 1, 'عيار فارغ', '', 'ذهب بلا عيار', '{}'::jsonb, pg_catalog.clock_timestamp(),
      'd1111111-1111-4111-8111-111111111111', pg_catalog.clock_timestamp()
    );
    raise exception 'null_gold_karat_allowed';
  exception
    when check_violation then
      if sqlerrm not like '%shop_debts_karat_check%' then
        raise exception 'null_gold_karat_got_%', sqlerrm;
      end if;
    when others then
      if sqlerrm = 'null_gold_karat_allowed' then
        raise;
      end if;
      raise exception 'null_gold_karat_got_%', sqlerrm;
  end;
end;
$gold_karat$;

rollback;

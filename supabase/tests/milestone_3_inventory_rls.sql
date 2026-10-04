-- Milestone 3 RLS and actor isolation. Synthetic fixtures roll back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, deleted_at, created_at, updated_at)
values
  ('b1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-owner@example.test', false, null, now(), now()),
  ('b2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-other@example.test', false, null, now(), now()),
  ('b3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-revoked@example.test', false, null, now(), now()),
  ('b4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-anon@example.test', true, null, now(), now()),
  ('b5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-admin@example.test', false, null, now(), now()),
  ('b6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-pending@example.test', false, null, now(), now()),
  ('b7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'm3-rls-expired@example.test', false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1222222-2222-4222-8222-222222222222', 'متجر الجرد', 'مالك الجرد', 'Africa/Cairo'),
  ('b2222222-2222-4222-8222-222222222222', 'متجر الآخر', 'مالك الآخر', 'Africa/Cairo'),
  ('b3222222-2222-4222-8222-222222222222', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('b4222222-2222-4222-8222-222222222222', 'متجر مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('b6222222-2222-4222-8222-222222222222', 'متجر معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('b7222222-2222-4222-8222-222222222222', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('b1222222-2222-4222-8222-222222222222', 'b1111111-1111-4111-8111-111111111111', 'owner', null),
  ('b2222222-2222-4222-8222-222222222222', 'b2111111-1111-4111-8111-111111111111', 'owner', null),
  ('b3222222-2222-4222-8222-222222222222', 'b3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('b4222222-2222-4222-8222-222222222222', 'b4111111-1111-4111-8111-111111111111', 'owner', null),
  ('b6222222-2222-4222-8222-222222222222', 'b6111111-1111-4111-8111-111111111111', 'owner', null),
  ('b7222222-2222-4222-8222-222222222222', 'b7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b4222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b7222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

insert into public.platform_admins (user_id)
values ('b5111111-1111-4111-8111-111111111111');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('b1818181-8181-4181-8181-818181818181', 'b1111111-1111-4111-8111-111111111111', now(), now(), now() + interval '1 day'),
  ('b1818181-8181-4181-8181-818181818182', 'b1111111-1111-4111-8111-111111111111', now(), now(), now() - interval '1 minute');

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
  if has_function_privilege('anon', 'public.post_inventory_addition_v1(uuid,jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_inventory_totals_v1(text,smallint)', 'EXECUTE')
    or has_function_privilege('anon', 'public.search_traders_v1(text,integer,text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.list_trader_obligations_v1(uuid,text,integer,text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.list_inventory_receipts_v1(text,uuid,text,integer,text)', 'EXECUTE')
    or has_table_privilege('anon', 'public.inventory_lots', 'SELECT')
    or has_table_privilege('authenticated', 'public.inventory_lots', 'INSERT')
    or has_table_privilege('authenticated', 'public.inventory_lot_movements', 'UPDATE')
    or has_table_privilege('authenticated', 'public.inventory_receipts', 'DELETE')
    or has_table_privilege('authenticated', 'public.gold_obligations', 'INSERT')
    or has_table_privilege('authenticated', 'public.traders', 'UPDATE') then
    raise exception 'inventory_privileges_were_too_wide';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'inventory_products', 'bullion_denominations', 'coin_types', 'traders',
        'inventory_lots', 'inventory_lot_movements', 'inventory_receipts',
        'receipt_quantity_allocations', 'gold_obligations', 'inventory_explicit_plans',
        'inventory_command_envelopes', 'inventory_catalog_requests',
        'inventory_catalog_events', 'inventory_lot_sync'
      )
      and cmd <> 'SELECT'
  ) then
    raise exception 'inventory_client_write_policy';
  end if;
end;
$priv$;

set local role anon;
do $anon$
begin
  begin
    perform public.get_inventory_totals_v1();
    raise exception 'anon_totals_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'anon_totals_unexpected: %', sqlerrm;
  end;
end;
$anon$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_code('select public.get_inventory_totals_v1()', 'unauthenticated');

select set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"b1818181-8181-4181-8181-818181818182","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_inventory_totals_v1()', 'session_expired');

select set_config('request.jwt.claims',
  '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select set_config('request.jwt.claim.sub', 'b3111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_inventory_totals_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'b4111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_inventory_totals_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'b5111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_inventory_totals_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'b6111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_inventory_totals_v1()', 'shop_unavailable');

select set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
select public.confirm_opening_balances(
  'b1333333-3333-4333-8333-333333333333',
  '{"version":1,"cash":{"cash":"1000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1"}],"scrap":[]}'::jsonb
);

do $owner$
declare v_state jsonb; v_payload jsonb;
begin
  if (select count(*) from public.inventory_lots) <> 1 then
    raise exception 'owner_lot_visibility';
  end if;
  v_state := public.get_daily_ledger_day_state();
  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'inventory_addition', 'reason', 'تجربة',
    'expected_day_id', v_state ->> 'business_day_id',
    'expected_day_version', v_state ->> 'day_version',
    'lines', jsonb_build_array(jsonb_build_object(
      'item_name', 'خاتم', 'category', 'worked_jewelry', 'karat', 18,
      'milligrams', '100', 'count', '1', 'denomination_id', null, 'coin_type_id', null))
  );
  if (public.post_inventory_addition_v1(
      'b1444444-4444-4444-8444-444444444444', v_payload) ->> 'ok')
      is distinct from 'true' then
    raise exception 'active_owner_write_failed';
  end if;
end;
$owner$;

select set_config('request.jwt.claim.sub', 'b2111111-1111-4111-8111-111111111111', true);
do $other$
begin
  if (select count(*) from public.inventory_lots) <> 0
    or (select count(*) from public.traders) <> 0
    or (select count(*) from public.inventory_receipts) <> 0 then
    raise exception 'cross_shop_table_visible';
  end if;
end;
$other$;

select set_config('request.jwt.claim.sub', 'b7111111-1111-4111-8111-111111111111', true);
select public.confirm_opening_balances(
  'b1555555-5555-4555-8555-555555555555',
  '{"version":1,"cash":{"cash":"500"},"stock":[],"scrap":[]}'::jsonb
);
reset role;
update public.shop_entitlements
  set expires_at = now() - interval '1 hour'
  where shop_id = 'b7222222-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7111111-1111-4111-8111-111111111111', true);
do $expired$
declare v_state jsonb;
begin
  if public.get_inventory_totals_v1() ->> 'ok' is distinct from 'true'
    or public.list_inventory_receipts_v1() ->> 'ok' is distinct from 'true' then
    raise exception 'expired_read_denied';
  end if;
  v_state := public.get_daily_ledger_day_state();
  begin
    perform public.post_inventory_addition_v1(
      'b1666666-6666-4666-8666-666666666666',
      jsonb_build_object(
        'version', 1, 'kind', 'inventory_addition', 'reason', 'منتهٍ',
        'expected_day_id', v_state ->> 'business_day_id',
        'expected_day_version', v_state ->> 'day_version',
        'lines', jsonb_build_array(jsonb_build_object(
          'item_name', 'خاتم', 'category', 'worked_jewelry', 'karat', 18,
          'milligrams', '100', 'count', '1', 'denomination_id', null, 'coin_type_id', null))
      )
    );
    raise exception 'expired_write_accepted';
  exception when others then
    if sqlerrm <> 'shop_not_active' then raise; end if;
  end;
end;
$expired$;

reset role;
select 'milestone_3_inventory_rls_passed' as result;
rollback;

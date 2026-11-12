-- O2 (device pass 2026-11-11): stock named «رصيد سابق مجمّع» by an older
-- backfill is the pooled opening stock. The grid shows it in the one
-- «رصيد افتتاحي مجمّع» row, and a named sale takes it second (after the named
-- item, before another item's lots). One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('f4800000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'legacy-pooled-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('f4800000-0000-4000-8000-0000000000a1', 'متجر الرصيد السابق', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('f4800000-0000-4000-8000-0000000000a1', 'f4800000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('f4800000-0000-4000-8000-0000000000a1', now() - interval '1 day', now() + interval '30 days');

do $canonical$
begin
  if private.canonical_jewelry_name('رصيد سابق مجمّع') is distinct from 'رصيد افتتاحي مجمّع'
    or private.canonical_jewelry_name(' رصيد افتتاحي مجمّع ') is distinct from 'رصيد افتتاحي مجمّع'
    or private.canonical_jewelry_name('خاتم') is distinct from 'خواتم' then
    raise exception 'canonical_name_mapping';
  end if;
  if has_function_privilege('authenticated', 'private.canonical_jewelry_name(text)', 'execute')
    or has_function_privilege('authenticated', 'private.consume_fifo_named(uuid,uuid,text,smallint,bigint,bigint,text,text)', 'execute') then
    raise exception 'private_function_granted';
  end if;
end;
$canonical$;

create function pg_temp.with_day(p_payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $fn$
declare v_state jsonb;
begin
  v_state := public.get_daily_ledger_day_state();
  return p_payload || jsonb_build_object(
    'expected_day_id', v_state ->> 'business_day_id',
    'expected_day_version', v_state ->> 'day_version'
  );
end;
$fn$;

create function pg_temp.grid_cell(p_name text, p_karat int)
returns jsonb language sql security invoker set search_path = '' as $fn$
  select item from pg_catalog.jsonb_array_elements(public.get_inventory_item_grid_v1() -> 'rows') as item
  where item ->> 'item_name' = p_name and (item ->> 'karat')::int = p_karat;
$fn$;

create function pg_temp.add_item(p_key uuid, p_name text, p_mg text, p_count text)
returns void language plpgsql security invoker set search_path = '' as $fn$
begin
  perform public.post_inventory_addition_v1(
    p_key,
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_addition', 'reason', p_name,
      'lines', jsonb_build_array(jsonb_build_object(
        'item_name', p_name, 'category', 'worked_jewelry', 'karat', 21,
        'milligrams', p_mg, 'count', p_count,
        'denomination_id', null, 'coin_type_id', null)))));
end;
$fn$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f4800000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'f4800000-0000-4000-8000-000000000100',
  '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
);

do $pooled$
declare
  v_cell jsonb;
  v_index int;
begin
  -- Several chain lots first, so an unpreferred pooled lot would lose the
  -- created_at / id tie-break most of the time.
  for v_index in 1..4 loop
    perform pg_temp.add_item(
      ('f4800000-0000-4000-8000-00000000010' || v_index)::uuid, 'سلسلة', '1000', '1');
  end loop;
  perform pg_temp.add_item('f4800000-0000-4000-8000-000000000111', 'رصيد سابق مجمّع', '2000', '2');

  if pg_temp.grid_cell('رصيد سابق مجمّع', 21) is not null then
    raise exception 'legacy_row_shown %', pg_temp.grid_cell('رصيد سابق مجمّع', 21);
  end if;
  v_cell := pg_temp.grid_cell('رصيد افتتاحي مجمّع', 21);
  if v_cell ->> 'count' is distinct from '2' or v_cell ->> 'milligrams' is distinct from '2000' then
    raise exception 'pooled_row %', v_cell;
  end if;

  -- A ring sale with no ring stock takes the pooled lot, never the chains.
  perform public.post_daily_ledger_trade(
    'f4800000-0000-4000-8000-000000000201',
    '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb);
  v_cell := pg_temp.grid_cell('سلاسل', 21);
  if v_cell ->> 'count' is distinct from '4' or v_cell ->> 'milligrams' is distinct from '4000' then
    raise exception 'chains_paid_for_ring %', v_cell;
  end if;
  v_cell := pg_temp.grid_cell('رصيد افتتاحي مجمّع', 21);
  if v_cell ->> 'count' is distinct from '1' or v_cell ->> 'milligrams' is distinct from '1000' then
    raise exception 'pooled_not_taken %', v_cell;
  end if;
end;
$pooled$;

rollback;

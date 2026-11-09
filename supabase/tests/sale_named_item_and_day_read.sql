-- A sale takes stock from the same item first; one day reads by day id;
-- home pages older open-day rows (ADR 0042, ADR 0043). Rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('f1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'named-owner@example.test', false, now(), now()),
  ('f1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'named-staff@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('f2200000-0000-4000-8000-000000000001', 'متجر الأصناف', 'مالك الأصناف', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('f2200000-0000-4000-8000-000000000001', 'f1100000-0000-4000-8000-000000000001', 'owner'),
  ('f2200000-0000-4000-8000-000000000001', 'f1100000-0000-4000-8000-000000000002', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('f2200000-0000-4000-8000-000000000001', 'f1100000-0000-4000-8000-000000000002', 'sale', 'f1100000-0000-4000-8000-000000000001');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('f2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

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

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'f3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2"}],"scrap":[]}'::jsonb
);

-- 1. Named item first, pooled opening stock second, other items last.
do $named$
declare
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_cell jsonb;
begin
  perform public.post_inventory_addition_v1(
    'f3300000-0000-4000-8000-000000000011',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"سلاسل","lines":[{"item_name":"سلسلة","category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","denomination_id":null,"coin_type_id":null}]}'::jsonb));
  perform public.post_inventory_addition_v1(
    'f3300000-0000-4000-8000-000000000012',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"خاتم","lines":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb));

  perform public.post_daily_ledger_trade('f3300000-0000-4000-8000-000000000013', v_sale);
  if pg_temp.grid_cell('خاتم', 21) is not null then
    raise exception 'ring_not_taken_from_ring %', pg_temp.grid_cell('خاتم', 21);
  end if;
  v_cell := pg_temp.grid_cell('سلسلة', 21);
  if v_cell ->> 'count' is distinct from '2' or v_cell ->> 'milligrams' is distinct from '2000' then
    raise exception 'chain_changed_by_ring_sale %', v_cell;
  end if;
  v_cell := pg_temp.grid_cell('رصيد افتتاحي مجمّع', 21);
  if v_cell ->> 'count' is distinct from '2' then
    raise exception 'opening_changed_by_ring_sale %', v_cell;
  end if;

  -- No «حلق» lot: pooled opening stock goes before another item's lot.
  perform public.post_daily_ledger_trade(
    'f3300000-0000-4000-8000-000000000014',
    jsonb_set(v_sale, '{items,0,item_name}', '"حلق"'));
  v_cell := pg_temp.grid_cell('رصيد افتتاحي مجمّع', 21);
  if v_cell ->> 'count' is distinct from '1' or v_cell ->> 'milligrams' is distinct from '1000' then
    raise exception 'earring_not_from_opening %', v_cell;
  end if;
  v_cell := pg_temp.grid_cell('سلسلة', 21);
  if v_cell ->> 'count' is distinct from '2' then
    raise exception 'chain_changed_by_earring_sale %', v_cell;
  end if;

  -- Opening used up: the oldest other item pays, and the karat total is exact.
  perform public.post_daily_ledger_trade(
    'f3300000-0000-4000-8000-000000000015',
    jsonb_set(jsonb_set(v_sale, '{items,0,item_name}', '"تعليقة"'), '{items,0,count}', '"2"')
      || '{"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","item_name":"تعليقة","line_price_piastres":null}]}'::jsonb);
  if pg_temp.grid_cell('رصيد افتتاحي مجمّع', 21) is not null then
    raise exception 'opening_not_used_first %', pg_temp.grid_cell('رصيد افتتاحي مجمّع', 21);
  end if;
  v_cell := pg_temp.grid_cell('سلسلة', 21);
  if v_cell ->> 'count' is distinct from '1' or v_cell ->> 'milligrams' is distinct from '1000' then
    raise exception 'fallback_wrong %', v_cell;
  end if;
end;
$named$;

-- 2. Day read and paging.
do $days$
declare
  v_expense jsonb := '{"version":1,"kind":"expense","total_piastres":"100","tenders":[{"method":"cash","piastres":"100"}],"items":[],"description":"مصروف صغير","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_state jsonb;
  v_closed_day uuid;
  v_closed_date date;
  v_open_day uuid;
  v_counts jsonb;
  v_read jsonb;
  v_next text;
  v_home jsonb;
  v_index int;
begin
  v_state := public.get_daily_ledger_day_state();
  v_closed_day := (v_state ->> 'business_day_id')::uuid;
  v_closed_date := (v_state ->> 'business_date')::date;
  v_counts := jsonb_build_object(
    'version', 2,
    'cash', v_state #> '{counts,cash}',
    'scrap', v_state #> '{counts,scrap}',
    'stock', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_name', 'سلسلة',
        'category', item ->> 'category',
        'karat', item -> 'karat',
        'count', item ->> 'count',
        'milligrams', 'null'::jsonb
      ))
      from jsonb_array_elements(v_state #> '{counts,stock}') as item
    ), '[]'::jsonb)
  );
  if (public.close_daily_ledger_day_v2(
    'f3300000-0000-4000-8000-000000000021', v_closed_day,
    (v_state ->> 'day_version')::bigint, v_counts
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'close_failed';
  end if;
  perform public.open_daily_ledger_day('f3300000-0000-4000-8000-000000000022');
  v_state := public.get_daily_ledger_day_state();
  v_open_day := (v_state ->> 'business_day_id')::uuid;
  if (v_state ->> 'business_date')::date is distinct from v_closed_date then
    raise exception 'test_needs_same_date';
  end if;

  for v_index in 1..102 loop
    perform public.post_daily_ledger_trade(
      ('f3300000-0000-4000-8000-' || lpad((1000 + v_index)::text, 12, '0'))::uuid,
      v_expense);
  end loop;

  -- The closed day alone: three sales, no expense of the new day.
  v_read := public.get_ledger_day_v1(v_closed_day, null, 100);
  if v_read #>> '{day_summary,sale_piastres}' is distinct from '3000'
    or v_read #>> '{day_summary,expense_count}' is distinct from '0'
    or v_read -> 'day_ids' is distinct from jsonb_build_array(v_closed_day)
    or exists (
      select 1 from jsonb_array_elements(v_read #> '{feed_page,items}') as item
      join public.financial_operations as operation
        on operation.id = (item ->> 'operation_id')::uuid
      where operation.business_day_id <> v_closed_day
    )
    or not exists (
      select 1 from jsonb_array_elements(v_read #> '{feed_page,items}') as item
      where item ->> 'kind' = 'sale'
    ) then
    raise exception 'closed_day_read_wrong %', jsonb_build_object(
      'summary', v_read -> 'day_summary', 'ids', v_read -> 'day_ids');
  end if;

  -- The open day pages by day: 100, then 2.
  v_read := public.get_ledger_day_v1(v_open_day, null, 100);
  if jsonb_array_length(v_read #> '{feed_page,items}') <> 100
    or v_read #>> '{feed_page,has_more}' is distinct from 'true'
    or v_read #>> '{day_summary,expense_count}' is distinct from '102'
    or v_read #>> '{day_summary,sale_count}' is distinct from '0' then
    raise exception 'open_day_first_page_wrong %', jsonb_build_object(
      'n', jsonb_array_length(v_read #> '{feed_page,items}'),
      'more', v_read #> '{feed_page,has_more}', 'summary', v_read -> 'day_summary');
  end if;
  v_next := v_read #>> '{feed_page,next_before_sequence}';
  v_read := public.get_ledger_day_v1(v_open_day, v_next, 100);
  if v_read #>> '{feed_page,has_more}' is distinct from 'false'
    or (select count(*) from jsonb_array_elements(v_read #> '{feed_page,items}') as item
        where item ->> 'kind' = 'expense') <> 2 then
    raise exception 'open_day_second_page_wrong %', v_read -> 'feed_page';
  end if;

  -- Home sends the cursor of the older open-day rows.
  v_home := public.get_daily_ledger_home_v1();
  if v_home #>> '{feed_page,has_more}' is distinct from 'true'
    or v_home #>> '{feed_page,next_before_sequence}' is null then
    raise exception 'home_cursor_missing %', v_home -> 'feed_page';
  end if;

  begin
    perform public.get_ledger_day_v1(gen_random_uuid(), null, 100);
    raise exception 'unknown_day_read';
  exception when others then
    if sqlerrm is distinct from 'not_found' then
      raise exception 'unknown_day_got_%', sqlerrm;
    end if;
  end;

  -- An employee keeps the employee rules: own rows only, no shop figures.
  perform set_config('request.jwt.claim.sub', 'f1100000-0000-4000-8000-000000000002', true);
  v_read := public.get_ledger_day_v1(v_closed_day, null, 100);
  if v_read ? 'day_summary'
    or jsonb_array_length(v_read #> '{feed_page,items}') <> 0 then
    raise exception 'employee_day_read_leaks %', v_read;
  end if;
end;
$days$;

rollback;

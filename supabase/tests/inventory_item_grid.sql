-- Item-by-karat inventory aggregate (ADR 0043). Rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('e1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'grid-owner@example.test', false, now(), now()),
  ('e1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'grid-staff@example.test', false, now(), now()),
  ('e1100000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'grid-other@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('e2200000-0000-4000-8000-000000000001', 'متجر الجدول', 'مالك الجدول', 'Africa/Cairo'),
  ('e2200000-0000-4000-8000-000000000002', 'متجر جدول آخر', 'مالك آخر', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role) values
  ('e2200000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'owner'),
  ('e2200000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000002', 'employee'),
  ('e2200000-0000-4000-8000-000000000002', 'e1100000-0000-4000-8000-000000000003', 'owner');

insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('e2200000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000002', 'sale', 'e1100000-0000-4000-8000-000000000001');

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('e2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days'),
  ('e2200000-0000-4000-8000-000000000002', now() - interval '1 day', now() + interval '30 days');

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

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'e3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"20000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"bullion","karat":24,"milligrams":"8000","count":"1"},{"category":"coin","karat":21,"milligrams":"8000","count":"1"}],"scrap":[{"karat":21,"milligrams":"100000"},{"karat":18,"milligrams":"2500"}]}'::jsonb
);

do $grid$
declare
  v_shop uuid := 'e2200000-0000-4000-8000-000000000001';
  v_trader uuid;
  v_grid jsonb;
  v_totals jsonb;
  v_row jsonb;
  v_scrap jsonb;
begin
  if (public.post_inventory_addition_v1(
    'e3300000-0000-4000-8000-000000000011',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"خاتم أول","lines":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"milligrams":"3000","count":"3","denomination_id":null,"coin_type_id":null}]}'::jsonb)
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'first_ring_failed';
  end if;
  if (public.post_inventory_addition_v1(
    'e3300000-0000-4000-8000-000000000012',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"خاتم ثان","lines":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","denomination_id":null,"coin_type_id":null}]}'::jsonb)
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'second_ring_failed';
  end if;
  if (public.post_inventory_addition_v1(
    'e3300000-0000-4000-8000-000000000013',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"دفلة","lines":[{"item_name":"دفلة","category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb)
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'sold_out_item_failed';
  end if;
  if (public.post_daily_ledger_trade(
    'e3300000-0000-4000-8000-000000000014',
    '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"دفلة","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  ) ->> 'operation_id') is null then
    raise exception 'sold_out_sale_failed';
  end if;
  v_trader := (public.save_trader_v1(
    'e3300000-0000-4000-8000-000000000015',
    pg_temp.with_day('{"version":1,"kind":"trader","display_name":"تاجر الجدول","phone":"+201000000009","note":"","active":true}'::jsonb)
  ) ->> 'id')::uuid;
  if (public.post_inventory_receipt_v1(
    'e3300000-0000-4000-8000-000000000016',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_receipt', 'owner_kind', 'trader',
      'trader_id', v_trader, 'counterparty_name', 'تاجر الجدول',
      'product_name', 'طقم', 'category', 'worked_jewelry', 'karat', 21,
      'milligrams', '4000', 'count', '1', 'recognition', 'custody',
      'denomination_id', null, 'coin_type_id', null, 'note', ''
    ))
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'custody_lot_failed';
  end if;

  v_grid := public.get_inventory_item_grid_v1();
  select item into v_row
  from jsonb_array_elements(v_grid -> 'rows') as item
  where item ->> 'item_name' = 'خاتم' and (item ->> 'karat')::int = 21;
  if v_row ->> 'count' is distinct from '5'
    or v_row ->> 'count_known' is distinct from 'true'
    or v_row ->> 'milligrams' is distinct from '5000' then
    raise exception 'ring_row_wrong %', v_row;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_grid -> 'rows') as item
    where item ->> 'item_name' in ('دفلة', 'طقم')
      or item ->> 'item_name' ilike '%سبيكة%'
      or item ->> 'item_name' ilike '%جنيه%'
  ) then
    raise exception 'grid_listed_excluded_stock %', v_grid -> 'rows';
  end if;

  v_totals := public.get_inventory_totals_v1();
  for v_scrap in
    select value from jsonb_array_elements(v_grid -> 'scrap')
  loop
    if not exists (
      select 1 from jsonb_array_elements(v_totals -> 'buckets') as bucket
      where bucket ->> 'category' = 'scrap'
        and (bucket ->> 'karat')::int = (v_scrap ->> 'karat')::int
        and bucket ->> 'available_milligrams' = v_scrap ->> 'milligrams'
    ) then
      raise exception 'scrap_disagrees %', jsonb_build_object('scrap', v_scrap, 'totals', v_totals -> 'buckets');
    end if;
  end loop;
  if (select count(*) from jsonb_array_elements(v_grid -> 'scrap')) <> (
    select count(*) from jsonb_array_elements(v_totals -> 'buckets') as bucket
    where bucket ->> 'category' = 'scrap'
      and (bucket ->> 'available_milligrams')::numeric > 0
  ) then
    raise exception 'scrap_count_disagrees %', v_grid -> 'scrap';
  end if;
end;
$grid$;

select set_config('request.jwt.claim.sub', 'e1100000-0000-4000-8000-000000000002', true);
do $staff$
begin
  perform public.get_inventory_item_grid_v1();
  raise exception 'staff_grid_allowed';
exception
  when others then
    if sqlerrm is distinct from 'forbidden' then
      raise exception 'staff_grid_got_%', sqlerrm;
    end if;
end;
$staff$;

select set_config('request.jwt.claim.sub', 'e1100000-0000-4000-8000-000000000003', true);
select public.confirm_opening_balances(
  'e3300000-0000-4000-8000-000000000002',
  '{"version":1,"cash":{"cash":"1000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
);
do $other$
declare
  v_grid jsonb;
begin
  if (public.post_inventory_addition_v1(
    'e3300000-0000-4000-8000-000000000021',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"سلسلة المحل الآخر","lines":[{"item_name":"سلسلة السر","category":"worked_jewelry","karat":18,"milligrams":"1500","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb)
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'other_shop_addition_failed';
  end if;
  perform set_config('request.jwt.claim.sub', 'e1100000-0000-4000-8000-000000000001', true);
  v_grid := public.get_inventory_item_grid_v1();
  if exists (
    select 1 from jsonb_array_elements(v_grid -> 'rows') as item
    where item ->> 'item_name' = 'سلسلة السر'
  ) then
    raise exception 'other_shop_visible %', v_grid -> 'rows';
  end if;
end;
$other$;

rollback;

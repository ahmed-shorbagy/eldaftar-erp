-- Canonical jewelry names and coin row (ADR 0044 C-D2..C-D4).
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('d1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'jewelry-owner@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('d2200000-0000-4000-8000-000000000001', 'متجر الأصناف', 'مالك الأصناف', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('d2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

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

-- private.* is not executable by authenticated; check the map as the owner role.
do $map$
begin
  if private.canonical_jewelry_name('خاتم') is distinct from 'خواتم'
    or private.canonical_jewelry_name('حلق') is distinct from 'حلقان'
    or private.canonical_jewelry_name('سلسلة') is distinct from 'سلاسل'
    or private.canonical_jewelry_name(' دبلة ') is distinct from 'دبل'
    or private.canonical_jewelry_name('مخصص') is distinct from 'مخصص' then
    raise exception 'canonical_map_wrong';
  end if;
  if has_function_privilege('authenticated', 'private.canonical_jewelry_name(text)', 'EXECUTE') then
    raise exception 'canonical_map_exposed';
  end if;
end;
$map$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'd3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"5"},{"category":"coin","karat":21,"milligrams":"8000","count":"1"}],"scrap":[]}'::jsonb
);

do $jewelry$
declare
  v_cell jsonb;
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خواتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
begin
  perform public.post_inventory_addition_v1(
    'd3300000-0000-4000-8000-000000000011',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"خاتم","lines":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb));
  perform public.post_inventory_addition_v1(
    'd3300000-0000-4000-8000-000000000012',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"خواتم","lines":[{"item_name":"خواتم","category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb));
  perform public.post_inventory_addition_v1(
    'd3300000-0000-4000-8000-000000000013',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"سلاسل","lines":[{"item_name":"سلاسل","category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","denomination_id":null,"coin_type_id":null}]}'::jsonb));

  v_cell := pg_temp.grid_cell('خواتم', 21);
  if v_cell is null
    or (v_cell ->> 'count')::bigint <> 2
    or (v_cell ->> 'milligrams')::bigint <> 2000 then
    raise exception 'khatam_not_grouped %', v_cell;
  end if;
  if pg_temp.grid_cell('خاتم', 21) is not null then
    raise exception 'singular_still_present';
  end if;
  if pg_temp.grid_cell('جنيهات', 21) is null then
    raise exception 'coin_row_missing %', public.get_inventory_item_grid_v1();
  end if;

  -- Selling «خواتم» takes the canonical خاتم lot before سلاسل.
  perform public.post_daily_ledger_trade(
    'd3300000-0000-4000-8000-000000000014',
    v_sale
  );
  v_cell := pg_temp.grid_cell('خواتم', 21);
  if v_cell is null
    or (v_cell ->> 'count')::bigint <> 1
    or (v_cell ->> 'milligrams')::bigint <> 1000 then
    raise exception 'sale_did_not_take_khatam %', v_cell;
  end if;
  v_cell := pg_temp.grid_cell('سلاسل', 21);
  if v_cell is null
    or (v_cell ->> 'count')::bigint <> 2 then
    raise exception 'salasil_changed %', v_cell;
  end if;
end;
$jewelry$;

rollback;

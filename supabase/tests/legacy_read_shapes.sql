-- Legacy public reads keep the 361ad2e shapes; v2 keeps the new keys (ADR 0044 C-D1).
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('c1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'legacy-owner@example.test', false, now(), now()),
  ('c1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'legacy-staff@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('c2200000-0000-4000-8000-000000000001', 'متجر التوافق', 'مالك التوافق', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('c2200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000001', 'owner'),
  ('c2200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000002', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('c2200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000002', 'sale', 'c1100000-0000-4000-8000-000000000001');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('c2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'c3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"1000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"2"}],"scrap":[]}'::jsonb
);

do $legacy$
declare
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"10000","tenders":[{"method":"cash","piastres":"10000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_legacy jsonb;
  v_full jsonb;
  v_keys text;
  v_summary_keys text;
  v_closed text;
  v_state jsonb;
begin
  perform public.post_daily_ledger_trade('c3300000-0000-4000-8000-000000000011', v_sale);

  v_legacy := public.get_daily_ledger_home_v1();
  v_full := public.get_daily_ledger_home_v2();

  if v_legacy ? 'day_reset' or v_legacy ? 'last_closed_business_date' then
    raise exception 'legacy_home_has_new_top_keys %', v_legacy;
  end if;
  if not (v_full ? 'day_reset') or not (v_full ? 'last_closed_business_date') then
    raise exception 'v2_home_missing_new_top_keys %', v_full;
  end if;

  select string_agg(key, ',' order by key) into v_summary_keys
  from jsonb_object_keys(v_legacy -> 'day_summary') as key;
  if v_summary_keys ~ 'repair_' then
    raise exception 'legacy_home_summary_has_repair %', v_summary_keys;
  end if;
  select string_agg(key, ',' order by key) into v_summary_keys
  from jsonb_object_keys(v_full -> 'day_summary') as key;
  if v_summary_keys !~ 'repair_piastres' or v_summary_keys !~ 'repair_count' then
    raise exception 'v2_home_summary_missing_repair %', v_summary_keys;
  end if;

  perform set_config('request.jwt.claim.sub', 'c1100000-0000-4000-8000-000000000002', true);
  v_legacy := public.get_daily_ledger_home_v1();
  v_full := public.get_daily_ledger_home_v2();
  if v_legacy ? 'day_reset' or v_legacy ? 'last_closed_business_date' then
    raise exception 'legacy_employee_home_has_new_keys %', v_legacy;
  end if;
  if not (v_full ? 'day_reset') then
    raise exception 'v2_employee_home_missing_day_reset %', v_full;
  end if;

  perform set_config('request.jwt.claim.sub', 'c1100000-0000-4000-8000-000000000001', true);
  v_state := public.get_daily_ledger_day_state();
  v_closed := v_state ->> 'business_date';
  if (public.close_daily_ledger_day_v2(
    'c3300000-0000-4000-8000-000000000021',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    jsonb_build_object(
      'version', 2,
      'cash', v_state #> '{counts,cash}',
      'scrap', v_state #> '{counts,scrap}',
      'stock', coalesce((
        select jsonb_agg(jsonb_build_object(
          'item_name', 'خواتم',
          'category', item ->> 'category',
          'karat', item -> 'karat',
          'count', item ->> 'count',
          'milligrams', 'null'::jsonb
        ))
        from jsonb_array_elements(v_state #> '{counts,stock}') as item
      ), '[]'::jsonb)
    )
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'close_failed';
  end if;

  v_legacy := public.get_daily_ledger_home_v1();
  v_full := public.get_daily_ledger_home_v2();
  if v_legacy ? 'day_reset' then
    raise exception 'legacy_closed_home_has_day_reset';
  end if;
  if v_full ->> 'day_reset' is distinct from 'true' then
    raise exception 'v2_closed_home_not_reset %', v_full -> 'day_reset';
  end if;
  if (v_legacy #>> '{day_summary,sale_piastres}') is distinct from '0'
    or (v_full #>> '{day_summary,sale_piastres}') is distinct from '0' then
    raise exception 'closed_day_flows_not_zeroed';
  end if;
  if (v_legacy -> 'cash' -> 0 ->> 'piastres') is null then
    raise exception 'legacy_closed_home_lost_cash';
  end if;

  select string_agg(key, ',' order by key) into v_keys
  from jsonb_object_keys(
    public.get_ledger_date_v1(null, null, 20) -> 'day_summary'
  ) as key;
  if v_keys ~ 'repair_' then
    raise exception 'legacy_date_summary_has_repair %', v_keys;
  end if;
  select string_agg(key, ',' order by key) into v_keys
  from jsonb_object_keys(
    public.get_ledger_date_v2(null, null, 20) -> 'day_summary'
  ) as key;
  if v_keys !~ 'repair_piastres' then
    raise exception 'v2_date_summary_missing_repair %', v_keys;
  end if;
end;
$legacy$;

rollback;

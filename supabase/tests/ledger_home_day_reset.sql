-- Home zeroes daily flows after close and keeps cash balances (ADR 0042).
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('b1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reset-owner@example.test', false, now(), now()),
  ('b1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'reset-staff@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b2200000-0000-4000-8000-000000000001', 'متجر التقفيل', 'مالك التقفيل', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b2200000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001', 'owner'),
  ('b2200000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000002', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('b2200000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000002', 'sale', 'b1100000-0000-4000-8000-000000000001');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'b3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"1000000","instant_transfer":"0","wallet":"0","card":"200000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"9000","count":"4"}],"scrap":[]}'::jsonb
);

do $reset$
declare
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"500000","tenders":[{"method":"cash","piastres":"500000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_staff jsonb := '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_home jsonb;
  v_cash jsonb;
  v_stock jsonb;
  v_scrap jsonb;
  v_state jsonb;
  v_counts jsonb;
  v_closed text;
  v_date jsonb;
  v_keys text;
begin
  perform public.post_daily_ledger_trade('b3300000-0000-4000-8000-000000000011', v_sale);
  v_home := public.get_daily_ledger_home_v1();
  if v_home #>> '{day_summary,sale_piastres}' is distinct from '500000'
    or (
      select count(*) from jsonb_array_elements(v_home -> 'feed') as item
      where item ->> 'kind' = 'sale'
    ) <> 1
    or v_home ->> 'day_reset' is distinct from 'false' then
    raise exception 'open_day_home_wrong %', jsonb_build_object(
      'sale', v_home #> '{day_summary,sale_piastres}',
      'feed', jsonb_array_length(v_home -> 'feed'),
      'reset', v_home -> 'day_reset',
      'summary_keys', (select jsonb_agg(key) from jsonb_object_keys(v_home -> 'day_summary') as key),
      'journal_keys', (select jsonb_agg(key) from jsonb_object_keys(v_home -> 'journal_context') as key)
    );
  end if;
  select string_agg(key, ',') into v_keys from jsonb_object_keys(v_home -> 'day_summary') as key;
  if v_keys ~ 'cash|stock|scrap' then
    raise exception 'day_summary_holds_a_balance %', v_keys;
  end if;
  select string_agg(key, ',') into v_keys from jsonb_object_keys(v_home -> 'journal_context') as key;
  if v_keys ~ 'cash|stock|scrap' then
    raise exception 'journal_context_holds_a_balance %', v_keys;
  end if;

  perform set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000002', true);
  perform public.post_daily_ledger_trade('b3300000-0000-4000-8000-000000000012', v_staff);
  v_home := public.get_daily_ledger_home_v1();
  if v_home ->> 'employee_ledger' is distinct from 'true'
    or jsonb_array_length(v_home -> 'feed') <> 1
    or v_home ? 'day_summary'
    or v_home ->> 'day_reset' is distinct from 'false' then
    raise exception 'employee_open_home_wrong %', v_home;
  end if;

  perform set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000001', true);
  v_home := public.get_daily_ledger_home_v1();
  v_cash := v_home -> 'cash';
  v_stock := v_home -> 'stock';
  v_scrap := v_home -> 'scrap';
  v_state := public.get_daily_ledger_day_state();
  v_closed := v_state ->> 'business_date';
  v_counts := jsonb_build_object(
    'version', 2,
    'cash', v_state #> '{counts,cash}',
    'scrap', v_state #> '{counts,scrap}',
    'stock', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_name', 'خاتم',
        'category', item ->> 'category',
        'karat', item -> 'karat',
        'count', item ->> 'count',
        'milligrams', 'null'::jsonb
      ))
      from jsonb_array_elements(v_state #> '{counts,stock}') as item
    ), '[]'::jsonb)
  );
  if (public.close_daily_ledger_day_v2(
    'b3300000-0000-4000-8000-000000000013',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    v_counts
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'close_failed %', v_counts;
  end if;
  v_home := public.get_daily_ledger_home_v1();
  if v_home ->> 'day_reset' is distinct from 'true'
    or v_home -> 'feed' is distinct from '[]'::jsonb
    or v_home #>> '{day_summary,sale_piastres}' is distinct from '0'
    or v_home #>> '{day_summary,sale_count}' is distinct from '0'
    or v_home ->> 'last_closed_business_date' is distinct from v_closed
    or v_home -> 'cash' is distinct from v_cash
    or v_home -> 'stock' is distinct from v_stock
    or v_home -> 'scrap' is distinct from v_scrap then
    raise exception 'closed_home_wrong %', jsonb_build_object(
      'reset', v_home -> 'day_reset',
      'sale', v_home #> '{day_summary,sale_piastres}',
      'count', v_home #> '{day_summary,sale_count}',
      'date', v_home -> 'last_closed_business_date',
      'cash_same', v_home -> 'cash' = v_cash
    );
  end if;

  perform set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000002', true);
  v_home := public.get_daily_ledger_home_v1();
  if v_home -> 'feed' is distinct from '[]'::jsonb
    or v_home ? 'day_summary'
    or v_home ->> 'day_reset' is distinct from 'true' then
    raise exception 'employee_closed_home_wrong %', v_home;
  end if;

  perform set_config('request.jwt.claim.sub', 'b1100000-0000-4000-8000-000000000001', true);
  perform public.open_daily_ledger_day('b3300000-0000-4000-8000-000000000014');
  v_home := public.get_daily_ledger_home_v1();
  if v_home ->> 'day_reset' is distinct from 'false'
    or exists (
      select 1 from jsonb_array_elements(v_home -> 'feed') as item
      where item ->> 'kind' in ('sale', 'purchase', 'expense', 'repair_fee')
    ) then
    raise exception 'new_day_home_wrong %', v_home -> 'feed';
  end if;
  v_date := public.get_ledger_date_v1(v_closed::date, null, 20);
  if (v_date #>> '{day_summary,sale_piastres}')::numeric < 500000
    or jsonb_array_length(v_date #> '{feed_page,items}') < 1 then
    raise exception 'closed_date_was_deleted %', v_date -> 'day_summary';
  end if;
end;
$reset$;

rollback;

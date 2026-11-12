-- U5 (device pass 2026-11-11): the current-app ledger reads carry an expense's
-- description in item_summary (one line, at most 200 characters); a sale keeps
-- its item names and the legacy home read is unchanged. Rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('f4900000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'expense-feed-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('f4900000-0000-4000-8000-0000000000a1', 'متجر المصروفات', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('f4900000-0000-4000-8000-0000000000a1', 'f4900000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('f4900000-0000-4000-8000-0000000000a1', now() - interval '1 day', now() + interval '30 days');

do $priv$
begin
  if has_function_privilege('authenticated', 'private.feed_expense_descriptions(jsonb)', 'execute')
    or has_function_privilege('anon', 'public.get_daily_ledger_home_v2()', 'execute') then
    raise exception 'privilege_leak';
  end if;
end;
$priv$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f4900000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'f4900000-0000-4000-8000-000000000100',
  '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2"}],"scrap":[]}'::jsonb
);

do $feed$
declare
  v_expense uuid;
  v_sale uuid;
  v_row jsonb;
  v_day uuid;
begin
  v_expense := (public.post_daily_ledger_trade(
    'f4900000-0000-4000-8000-000000000201',
    jsonb_build_object(
      'version', 1, 'kind', 'expense', 'total_piastres', '500000',
      'tenders', '[{"method":"cash","piastres":"500000"}]'::jsonb, 'items', '[]'::jsonb,
      'description', E'  إيجار\nالمحل  ' || repeat('ا', 250),
      'customer_name', '', 'customer_phone', '', 'note', '')
  ) ->> 'operation_id')::uuid;
  v_sale := (public.post_daily_ledger_trade(
    'f4900000-0000-4000-8000-000000000203',
    '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خواتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  ) ->> 'operation_id')::uuid;

  select item into v_row
  from jsonb_array_elements(public.get_daily_ledger_home_v2() -> 'feed') as item
  where item ->> 'operation_id' = v_expense::text;
  if v_row ->> 'item_summary' is distinct from left('إيجار المحل ' || repeat('ا', 250), 200) then
    raise exception 'home_expense_summary %', v_row ->> 'item_summary';
  end if;
  select item into v_row
  from jsonb_array_elements(public.get_daily_ledger_home_v2() -> 'feed') as item
  where item ->> 'operation_id' = v_sale::text;
  if v_row ->> 'item_summary' is distinct from 'خواتم' then
    raise exception 'sale_summary_changed %', v_row;
  end if;

  select item into v_row
  from jsonb_array_elements(public.get_ledger_date_v2() #> '{feed_page,items}') as item
  where item ->> 'operation_id' = v_expense::text;
  if v_row ->> 'item_summary' is null or position(E'\n' in v_row ->> 'item_summary') > 0 then
    raise exception 'date_expense_summary %', v_row;
  end if;

  v_day := (public.get_daily_ledger_day_state() ->> 'business_day_id')::uuid;
  select item into v_row
  from jsonb_array_elements(public.get_ledger_operation_page_v2(v_day, null, null, 50) -> 'items') as item
  where item ->> 'operation_id' = v_expense::text;
  if v_row ->> 'item_summary' is null then
    raise exception 'page_expense_summary %', v_row;
  end if;

  -- The 361ad2e home read keeps its own shape.
  select item into v_row
  from jsonb_array_elements(public.get_daily_ledger_home_v1() -> 'feed') as item
  where item ->> 'operation_id' = v_expense::text;
  if v_row is null then
    raise exception 'legacy_home_missing_expense';
  end if;
end;
$feed$;

rollback;

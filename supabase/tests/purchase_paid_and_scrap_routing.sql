-- Public purchases are paid in full. New jewelry lines are scrap.
-- Edit replacements may keep a worked-jewelry line; new purchases may not.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('91919191-9191-4191-8191-919191919191', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paid-owner@example.test', false, now(), now()),
  ('92929292-9292-4292-8292-929292929292', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'paid-employee@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1919191-9191-4191-8191-919191919191', 'متجر الدفع', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1919191-9191-4191-8191-919191919191', '91919191-9191-4191-8191-919191919191', 'owner'),
  ('b1919191-9191-4191-8191-919191919191', '92929292-9292-4292-8292-929292929292', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('b1919191-9191-4191-8191-919191919191', '92929292-9292-4292-8292-929292929292', 'sale', '91919191-9191-4191-8191-919191919191');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1919191-9191-4191-8191-919191919191', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', '91919191-9191-4191-8191-919191919191', true);
select public.confirm_opening_balances(
  'c1919191-9191-4191-8191-919191919191',
  '{"version":1,"cash":{"cash":"10000000"},"stock":[],"scrap":[]}'::jsonb
);

do $test$
declare
  v_shop uuid := 'b1919191-9191-4191-8191-919191919191';
  v_paid jsonb := '{"version":2,"kind":"purchase","total_piastres":"6000000","tenders":[{"method":"cash","piastres":"6000000"}],"items":[{"category":"scrap","karat":21,"milligrams":"10000","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_state jsonb;
  v_posted jsonb;
  v_result jsonb;
  v_op uuid;
  v_replacement jsonb;
  v_review jsonb;
  v_cash bigint;
  v_scrap bigint;
begin
  v_state := public.get_daily_ledger_day_state();
  v_paid := v_paid || jsonb_build_object(
    'expected_day_id', v_state ->> 'business_day_id',
    'expected_day_version', v_state ->> 'day_version'
  );
  begin
    perform public.post_daily_ledger_trade_v2(
      'c1919191-9191-4191-8191-9191919191a1',
      jsonb_set(v_paid, '{tenders}', '[]'::jsonb));
    raise exception 'empty tenders accepted';
  exception when others then
    if sqlerrm is distinct from 'purchase_must_be_paid' then raise; end if;
  end;

  begin
    perform public.post_daily_ledger_trade(
      'c1919191-9191-4191-8191-9191919191a2',
      jsonb_set(v_paid, '{tenders}', '[{"method":"cash","piastres":"1000"}]'::jsonb));
    raise exception 'partial tenders accepted';
  exception when others then
    if sqlerrm is distinct from 'purchase_must_be_paid' then raise; end if;
  end;

  begin
    perform public.post_daily_ledger_trade_v2(
      'c1919191-9191-4191-8191-9191919191a3',
      v_paid || jsonb_build_object('purchase_obligation_piastres', '0'));
    raise exception 'obligation key accepted';
  exception when others then
    if sqlerrm is distinct from 'purchase_must_be_paid' then raise; end if;
  end;

  begin
    perform public.post_daily_ledger_trade_v2(
      'c1919191-9191-4191-8191-9191919191a4',
      jsonb_set(v_paid, '{items}',
        '[{"category":"worked_jewelry","karat":21,"milligrams":"10000","count":"1","item_name":"خاتم","line_price_piastres":null}]'::jsonb));
    raise exception 'jewelry purchase accepted';
  exception when others then
    if sqlerrm is distinct from 'purchase_jewelry_is_scrap' then raise; end if;
  end;

  v_posted := v_paid;
  v_result := public.post_daily_ledger_trade_v2(
    'c1919191-9191-4191-8191-9191919191b1', v_posted);
  v_op := (v_result ->> 'operation_id')::uuid;
  select amount into v_cash from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash';
  select amount into v_scrap from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'scrap_metal' and karat = 21;
  if v_result ->> 'ok' is distinct from 'true'
    or v_result ->> 'replayed' is distinct from 'false'
    or v_cash is distinct from 4000000
    or v_scrap is distinct from 10000
    or (select count(*) from public.financial_operations
        where shop_id = v_shop and kind = 'purchase') <> 1 then
    raise exception 'paid scrap purchase mismatch cash % scrap %', v_cash, v_scrap;
  end if;

  if public.post_daily_ledger_trade_v2(
      'c1919191-9191-4191-8191-9191919191b1', v_posted) ->> 'replayed'
      is distinct from 'true'
    or (select amount from public.ledger_account_balances
        where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash')
      is distinct from 4000000 then
    raise exception 'paid purchase replay failed';
  end if;

  v_state := public.get_daily_ledger_day_state();
  v_result := public.post_daily_ledger_trade_v2(
    'c1919191-9191-4191-8191-9191919191c1',
    '{"version":2,"kind":"purchase","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"coin","karat":21,"milligrams":"8000","count":"1","item_name":"جنيه","line_price_piastres":"1000"}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
      || jsonb_build_object(
        'expected_day_id', v_state ->> 'business_day_id',
        'expected_day_version', v_state ->> 'day_version'));
  if (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_metal'
        and category_code = 'coin' and karat = 21) is distinct from 8000
    or (select amount from public.ledger_account_balances
        where shop_id = v_shop and account_kind = 'scrap_metal' and karat = 21)
      is distinct from 10000 then
    raise exception 'coin purchase changed scrap';
  end if;

  v_state := public.get_daily_ledger_day_state();
  perform public.post_daily_ledger_trade_v2(
    'c1919191-9191-4191-8191-9191919191c2',
    '{"version":2,"kind":"purchase","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"bullion","karat":24,"milligrams":"5000","count":"1","item_name":"سبيكة","line_price_piastres":"1000"}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
      || jsonb_build_object(
        'expected_day_id', v_state ->> 'business_day_id',
        'expected_day_version', v_state ->> 'day_version'));
  if (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_metal'
        and category_code = 'bullion' and karat = 24) is distinct from 5000 then
    raise exception 'bullion purchase missed stock';
  end if;

  begin
    perform public.review_ledger_trade_change_v1(
      v_op, 'edit',
      jsonb_set(v_paid, '{tenders}', '[{"method":"cash","piastres":"1000"}]'::jsonb));
    raise exception 'partial purchase edit accepted';
  exception when others then
    if sqlerrm is distinct from 'purchase_must_be_paid' then raise; end if;
  end;

  -- The app posts new trades through v1. A new jewelry purchase is refused there too.
  begin
    perform public.post_daily_ledger_trade(
      'c1919191-9191-4191-8191-9191919191a5',
      jsonb_set(v_paid - 'expected_day_id' - 'expected_day_version', '{version}', '1'::jsonb)
        || '{"items":[{"category":"worked_jewelry","karat":21,"milligrams":"10000","count":"1","item_name":"خاتم","line_price_piastres":null}]}'::jsonb);
    raise exception 'v1 jewelry purchase accepted';
  exception when others then
    if sqlerrm is distinct from 'purchase_jewelry_is_scrap' then raise; end if;
  end;

  -- An edit replacement may keep a worked-jewelry line (ADR 0040), paid in full.
  v_replacement := jsonb_set(v_paid - 'expected_day_id' - 'expected_day_version', '{version}', '1'::jsonb)
    || '{"items":[{"category":"worked_jewelry","karat":21,"milligrams":"10000","count":"1","item_name":"خاتم قديم","line_price_piastres":null}]}'::jsonb;
  v_review := public.review_ledger_trade_change_v1(v_op, 'edit', v_replacement);
  v_result := public.post_ledger_trade_change_v1(
    'c1919191-9191-4191-8191-9191919191e1', v_op, 'edit', v_replacement,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token');
  if v_result ->> 'replacement_operation_id' is null
    or (select amount from public.ledger_account_balances
        where shop_id = v_shop and account_kind = 'saleable_metal'
          and category_code = 'worked_jewelry' and karat = 21) is distinct from 10000
    or (select amount from public.ledger_account_balances
        where shop_id = v_shop and account_kind = 'scrap_metal' and karat = 21) is distinct from 0
    or (select amount from public.ledger_account_balances
        where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash')
      is distinct from 3998000 then
    raise exception 'jewelry edit replacement mismatch %', v_result;
  end if;

  -- The edit exemption ends with the edit. A later new jewelry purchase is refused.
  begin
    perform public.post_daily_ledger_trade(
      'c1919191-9191-4191-8191-9191919191a6',
      v_replacement);
    raise exception 'exemption leaked past the edit';
  exception when others then
    if sqlerrm is distinct from 'purchase_jewelry_is_scrap' then raise; end if;
  end;

  perform set_config('request.jwt.claim.sub', '92929292-9292-4292-8292-929292929292', true);
  begin
    perform public.post_daily_ledger_trade_v2(
      'c1919191-9191-4191-8191-9191919191d1', v_paid);
    raise exception 'purchase without grant accepted';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then raise; end if;
  end;
end;
$test$;

rollback;

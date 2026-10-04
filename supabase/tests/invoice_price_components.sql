-- Synthetic owner-only exact pricing. No Auth HTTP, real data edits or commits.
begin;
insert into auth.users(id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values ('93111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'pricing-owner@example.test', false, now(), now());
insert into public.shops(id, name, owner_display_name, time_zone)
values ('93222222-2222-4222-8222-222222222222', 'متجر السعر التجريبي', 'مالك تجريبي', 'Africa/Cairo');
insert into public.shop_memberships(shop_id, user_id, role)
values ('93222222-2222-4222-8222-222222222222', '93111111-1111-4111-8111-111111111111', 'owner');
insert into public.shop_entitlements(shop_id, starts_at, expires_at)
values ('93222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '1 day');
set local role authenticated;
select set_config('request.jwt.claim.sub', '93111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"93111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select public.confirm_opening_balances('93333333-3333-4333-8333-333333333333',
  '{"version":1,"cash":{"cash":"100000","card":"0","instant_transfer":"0","wallet":"0"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"5000","count":"5"}],"scrap":[]}'::jsonb);

do $pricing$
declare
  v_payload jsonb := '{"version":2,"kind":"sale","total_piastres":"104002","tenders":[{"method":"cash","piastres":"50000"},{"method":"card","piastres":"54002"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1830","count":"1","item_name":"خاتم","line_price_piastres":"100001"}],"description":"","customer_name":"","customer_phone":"","note":"","pricing":{"base_piastres":"100001","workmanship_piastres":"5002","other_charges_piastres":"1003","other_charges_label":"تغليف","discount_piastres":"2004"}}'::jsonb;
  v_result jsonb;
  v_operation uuid;
  v_bad jsonb;
  v_before bigint;
  v_error text;
begin
  v_result := public.post_daily_ledger_trade('93444444-4444-4444-8444-444444444444', v_payload);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'adjusted_sale_failed'; end if;
  v_operation := (v_result ->> 'operation_id')::uuid;
  if (public.get_daily_ledger_operation(v_operation) -> 'payload' -> 'pricing')
      is distinct from v_payload -> 'pricing' then raise exception 'price_components_not_frozen'; end if;
  if (public.post_daily_ledger_trade('93444444-4444-4444-8444-444444444444', v_payload) ->> 'replayed')
      is distinct from 'true' then raise exception 'pricing_replay_failed'; end if;
  if (select amount from public.ledger_account_balances where shop_id = '93222222-2222-4222-8222-222222222222'
      and account_kind = 'cash_method' and method_code = 'cash') <> 150000
    or (select amount from public.ledger_account_balances where shop_id = '93222222-2222-4222-8222-222222222222'
      and account_kind = 'cash_method' and method_code = 'card') <> 54002 then
    raise exception 'adjusted_split_cash_inexact';
  end if;
  if (select count(*) from public.financial_audit_events where operation_id = v_operation) <> 1
    or (select count(*) from public.financial_outbox where operation_id = v_operation) <> 1 then
    raise exception 'pricing_audit_outbox_missing';
  end if;
  begin
    perform public.post_daily_ledger_trade('93444444-4444-4444-8444-444444444444',
      jsonb_set(v_payload, '{pricing,discount_piastres}', '"2005"'));
    raise exception 'expected_payload_mismatch' using errcode = 'P0004';
  exception when others then
    if sqlerrm <> 'payload_mismatch' then raise; end if;
  end;
  select count(*) into v_before from public.financial_operations
    where shop_id = '93222222-2222-4222-8222-222222222222';
  for v_bad, v_error in select * from (values
    (jsonb_set(v_payload, '{pricing,discount_piastres}', '"2005"'), 'pricing_mismatch'),
    (jsonb_set(v_payload, '{pricing,other_charges_label}', '""'), 'invalid_input'),
    (jsonb_set(v_payload, '{pricing,workmanship_piastres}', '5002'), 'invalid_input'),
    (jsonb_set(v_payload, '{pricing,workmanship_piastres}', '"-1"'), 'negative_amount'),
    (jsonb_set(v_payload, '{pricing,workmanship_piastres}', '"0.01"'), 'invalid_input'),
    (jsonb_set(v_payload, '{pricing,extra}', '"hidden"'), 'invalid_input'),
    (jsonb_set(v_payload, '{items,0,line_price_piastres}', '"104002"'), 'line_price_mismatch'),
    (jsonb_set(v_payload, '{version}', '1'), 'invalid_input'),
    (v_payload - 'pricing', 'invalid_input'),
    (jsonb_set(jsonb_set(v_payload, '{pricing,base_piastres}', '"9223372036854775807"'),
      '{pricing,discount_piastres}', '"0"'), 'overflow')
  ) as cases(payload, error) loop
    begin
      perform public.post_daily_ledger_trade('93555555-5555-4555-8555-555555555555', v_bad);
      raise exception 'invalid_pricing_accepted' using errcode = 'P0004';
    exception when others then
      if sqlerrm <> v_error then raise; end if;
    end;
  end loop;
  if (select count(*) from public.financial_operations
      where shop_id = '93222222-2222-4222-8222-222222222222') <> v_before then
    raise exception 'invalid_pricing_left_effects';
  end if;
  execute 'set constraints all immediate';
  execute 'set constraints all deferred';
end;
$pricing$;

reset role;
set local role anon;
do $denial$
begin
  begin
    perform public.post_daily_ledger_trade('93666666-6666-4666-8666-666666666666', '{}'::jsonb);
    raise exception 'anonymous_pricing_allowed' using errcode = 'P0004';
  exception when insufficient_privilege then null;
  end;
end;
$denial$;
reset role;
select 'invoice_price_components_passed' as result;
rollback;

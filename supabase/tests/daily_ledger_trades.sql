-- Synthetic daily-ledger command tests. One connection, one transaction, ROLLBACK.
-- Run after daily_ledger_scrap_to_stock.sql. All fixture data rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('81818181-8181-4181-8181-818181818181', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-a@example.test', false, now(), now()),
  ('82828282-8282-4282-8282-828282828282', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-b@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1818181-8181-4181-8181-818181818181', 'متجر أ', 'المالك أ', 'Africa/Cairo'),
  ('b2828282-8282-4282-8282-828282828282', 'متجر ب', 'المالك ب', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1818181-8181-4181-8181-818181818181', '81818181-8181-4181-8181-818181818181', 'owner'),
  ('b2828282-8282-4282-8282-828282828282', '82828282-8282-4282-8282-828282828282', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1818181-8181-4181-8181-818181818181', now() - interval '1 day', now() + interval '30 days'),
  ('b2828282-8282-4282-8282-828282828282', now() - interval '1 day', now() + interval '30 days');

create temp table ledger_test_operation (id uuid not null);
grant select, insert on ledger_test_operation to authenticated;
create temp table ledger_test_payable (id uuid not null);
grant select, insert on ledger_test_payable to authenticated;
set constraints all deferred;
set local role authenticated;
select set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
select public.confirm_opening_balances(
  'c1818181-8181-4181-8181-818181818181',
  '{"version":1,"cash":{"cash":"10000","card":"3000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"3000","count":"3"}],"scrap":[]}'::jsonb
);

do $test$
declare
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"3000"},{"method":"card","piastres":"2000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null},{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"سلسلة","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":"ملاحظة تجريبية"}'::jsonb;
  v_purchase jsonb := '{"version":1,"kind":"purchase","total_piastres":"2000","tenders":[{"method":"cash","piastres":"2000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":"2000"}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_expense jsonb := '{"version":1,"kind":"expense","total_piastres":"500","tenders":[{"method":"cash","piastres":"500"}],"items":[],"description":"إيجار","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_partial jsonb := '{"version":1,"kind":"purchase","total_piastres":"5000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"سوار","line_price_piastres":null}],"description":"","customer_name":"تاجر تجريبي","customer_phone":"","note":"","purchase_obligation_piastres":"4000"}'::jsonb;
  v_result jsonb;
  v_state jsonb;
  v_counts jsonb;
  v_day uuid;
  v_version bigint;
  v_before bigint;
  v_purchase_op uuid;
  v_sale_op uuid;
  v_gold_before numeric;
  v_cash_before numeric;
  v_card_before numeric;
  v_transfer jsonb := '{"version":1,"kind":"cash_transfer","from_method":"cash","to_method":"card","amount_piastres":"300","note":"تحويل تجريبي"}'::jsonb;
  v_scrap_buy jsonb := '{"version":1,"kind":"purchase","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"scrap","karat":21,"milligrams":"500","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_scrap_sale jsonb := '{"version":1,"kind":"scrap_sale","total_piastres":"2000","tenders":[{"method":"cash","piastres":"1000"},{"method":"card","piastres":"1000"}],"items":[{"category":"scrap","karat":21,"milligrams":"300","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":"اختبار كسر"}'::jsonb;
  v_scrap_to_stock jsonb := '{"version":1,"kind":"scrap_to_stock","category":"coin","karat":21,"milligrams":"150","count":"2","item_name":"جنيه ذهب","note":"تحويل تجريبي"}'::jsonb;
begin
  v_result := public.post_daily_ledger_trade('c2828282-8282-4282-8282-828282828282', v_sale);
  if v_result ->> 'ok' is distinct from 'true' or v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'sale did not commit';
  end if;
  insert into ledger_test_operation (id) values ((v_result ->> 'operation_id')::uuid);
  v_sale_op := (v_result ->> 'operation_id')::uuid;
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'operation_id' = (v_result ->> 'operation_id')
      and movement.value ->> 'has_note' = 'true'
  ) then
    raise exception 'sale note marker missing';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed') as row(value)
    where row.value ->> 'operation_id' = (v_result ->> 'operation_id')
      and row.value ->> 'total_pounds' = '50.00'
      and row.value ->> 'weight_grams' = '2.000'
      and row.value ->> 'karat' = '18'
      and row.value ->> 'payment_label' = 'فيزا + كاش'
  ) then
    raise exception 'exact business summary missing from sale journal';
  end if;
  if jsonb_array_length(public.get_pending_invoice_sends(null) -> 'items') <> 1 then
    raise exception 'confirmed sale absent from pending-send queue';
  end if;
  if (public.get_invoice_dispatch_state((v_result ->> 'operation_id')::uuid) ->> 'status')
      is distinct from 'unconfirmed' then
    raise exception 'invoice handoff was falsely marked sent';
  end if;
  v_result := public.confirm_invoice_whatsapp_send(
    (v_result ->> 'operation_id')::uuid,
    'd1818181-8181-4181-8181-818181818181');
  if v_result ->> 'ok' is distinct from 'true'
    or v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'invoice confirmation failed';
  end if;
  if (public.confirm_invoice_whatsapp_send(
      (v_result ->> 'operation_id')::uuid,
      'd1818181-8181-4181-8181-818181818181') ->> 'replayed')
      is distinct from 'true' then
    raise exception 'invoice confirmation replay failed';
  end if;
  if (select count(*) from public.financial_audit_events
      where action = 'invoice_send_confirmed'
        and operation_id = (v_result ->> 'operation_id')::uuid) <> 1 then
    raise exception 'invoice confirmation duplicated audit';
  end if;
  if jsonb_array_length(public.get_pending_invoice_sends(null) -> 'items') <> 0 then
    raise exception 'confirmed send remained in pending-send queue';
  end if;
  if (public.post_daily_ledger_trade('c2828282-8282-4282-8282-828282828282', v_sale) ->> 'replayed') is distinct from 'true' then
    raise exception 'sale replay did not reconcile';
  end if;
  begin
    perform public.post_daily_ledger_trade('c2828282-8282-4282-8282-828282828282', v_purchase);
    raise exception 'mismatched key accepted';
  exception when others then
    if sqlerrm is distinct from 'payload_mismatch' then raise; end if;
  end;
  v_result := public.post_daily_ledger_trade('c3838383-8383-4383-8383-838383838383', v_purchase);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'purchase did not commit'; end if;
  v_result := public.post_daily_ledger_trade('c4848484-8484-4484-8484-848484848484', v_expense);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'expense did not commit'; end if;
  execute 'set constraints all immediate';
  execute 'set constraints all deferred';

  v_state := public.get_daily_ledger_day_state();
  v_counts := v_state -> 'counts';
  if v_counts -> 'cash' ->> 'cash' is distinct from '10500'
    or v_counts -> 'cash' ->> 'card' is distinct from '5000'
    or v_counts -> 'stock' -> 0 ->> 'milligrams' is distinct from '2000'
    or v_counts -> 'stock' -> 0 ->> 'count' is distinct from '2' then
    raise exception 'balance or repeated-bucket arithmetic mismatch';
  end if;
  if jsonb_array_length(public.get_daily_ledger_v2() -> 'feed') <> 4 then
    raise exception 'daily feed missing confirmed operations';
  end if;
  if (public.get_daily_ledger_v2() -> 'day_summary' ->> 'sale_piastres') is distinct from '5000'
    or (public.get_daily_ledger_v2() -> 'day_summary' ->> 'purchase_piastres') is distinct from '2000'
    or (public.get_daily_ledger_v2() -> 'day_summary' ->> 'expense_piastres') is distinct from '500' then
    raise exception 'daily movement summary mismatch';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(
      public.get_daily_ledger_v2() -> 'day_summary' -> 'gold_by_bucket'
    ) as movement(value)
    where movement.value ->> 'kind' = 'sale'
      and movement.value ->> 'category' = 'worked_jewelry'
      and movement.value ->> 'karat' = '18'
      and movement.value ->> 'milligrams' = '2000'
      and movement.value ->> 'count' = '2'
  ) or not exists (
    select 1 from jsonb_array_elements(
      public.get_daily_ledger_v2() -> 'day_summary' -> 'gold_by_bucket'
    ) as movement(value)
    where movement.value ->> 'kind' = 'purchase'
      and movement.value ->> 'category' = 'worked_jewelry'
      and movement.value ->> 'karat' = '18'
      and movement.value ->> 'milligrams' = '1000'
      and movement.value ->> 'count' = '1'
  ) then
    raise exception 'daily gold movement summary mismatch';
  end if;
  v_before := (select count(*) from public.financial_operations where shop_id = 'b1818181-8181-4181-8181-818181818181');
  begin
    perform public.post_daily_ledger_trade('c5151515-5151-4515-8515-515151515151', v_sale - 'items');
    raise exception 'sale without items accepted';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then raise; end if;
  end;
  begin
    perform public.post_daily_ledger_trade('c5252525-5252-4525-8525-525252525252',
      jsonb_set(v_sale, '{items,0,item_name}', '123'::jsonb));
    raise exception 'non-text item name accepted';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then raise; end if;
  end;
  begin
    perform public.post_daily_ledger_trade('c5353535-5353-4535-8535-535353535353',
      jsonb_set(v_sale, '{tenders,0,piastres}', '3000'::jsonb));
    raise exception 'numeric tender wire value accepted';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then raise; end if;
  end;
  begin
    perform public.post_daily_ledger_trade('c5858585-8585-4585-8585-858585858585',
      jsonb_set(v_sale, '{items,0,milligrams}', '"9000"'::jsonb));
    execute 'set constraints all immediate';
    raise exception 'oversold stock accepted';
  exception when others then
    if sqlerrm not in ('negative_owned_balance', 'insufficient_stock') then raise; end if;
  end;
  execute 'set constraints all deferred';
  begin
    perform public.post_daily_ledger_trade('c5959595-9595-4595-8595-959595959595',
      jsonb_set(v_sale, '{items}', '[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"2","item_name":"اختبار","line_price_piastres":null}]'::jsonb));
    execute 'set constraints all immediate';
    raise exception 'unpaired stock accepted';
  exception when others then
    if sqlerrm is distinct from 'stock_pair_mismatch' then raise; end if;
  end;
  execute 'set constraints all deferred';
  if (select count(*) from public.financial_operations where shop_id = 'b1818181-8181-4181-8181-818181818181') <> v_before then
    raise exception 'failed sale left an operation';
  end if;
  v_day := (v_state ->> 'business_day_id')::uuid;
  v_version := (v_state ->> 'day_version')::bigint;
  v_result := public.close_daily_ledger_day('c6868686-8686-4686-8686-868686868686', v_day, v_version,
    jsonb_set(v_counts, '{cash,cash}', '"10501"'::jsonb));
  if v_result ->> 'reason' is distinct from 'count_mismatch' then
    raise exception 'count discrepancy was not blocked';
  end if;
  v_result := public.close_daily_ledger_day('c7878787-8787-4787-8787-878787878787', v_day, v_version, v_counts);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'close did not commit'; end if;
  if (public.close_daily_ledger_day('c7878787-8787-4787-8787-878787878787', v_day, v_version, v_counts) ->> 'replayed') is distinct from 'true' then
    raise exception 'close replay failed';
  end if;
  begin
    perform public.post_daily_ledger_trade('c8888888-8888-4888-8888-888888888888', v_sale);
    raise exception 'closed day accepted sale';
  exception when others then
    if sqlerrm is distinct from 'day_closed' then raise; end if;
  end;
  v_result := public.open_daily_ledger_day('c9898989-8989-4989-8989-898989898989');
  if v_result ->> 'ok' is distinct from 'true' or public.get_daily_ledger_day_state() ->> 'state' is distinct from 'open' then
    raise exception 'new day did not open';
  end if;
  begin
    perform public.post_daily_ledger_trade('d3131313-3131-4313-8313-313131313131',
      v_partial - 'purchase_obligation_piastres');
    raise exception 'unrecorded partial payable accepted';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then raise; end if;
  end;
  v_result := public.post_daily_ledger_trade('d3232323-3232-4323-8323-323232323232',
    v_partial);
  v_purchase_op := (v_result ->> 'operation_id')::uuid;
  insert into ledger_test_payable (id) values (v_purchase_op);
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'operation_id' = v_purchase_op::text
      and movement.value ->> 'has_note' = 'false'
  ) then
    raise exception 'purchase note marker mismatch';
  end if;
  if (select remaining_piastres from public.purchase_cash_payables
      where operation_id = v_purchase_op) <> 4000 then
    raise exception 'partial purchase payable missing';
  end if;
  v_gold_before := (select amount from public.ledger_account_balances
    where shop_id = 'b1818181-8181-4181-8181-818181818181'
      and account_kind = 'saleable_metal'
      and category_code = 'worked_jewelry' and karat = 18);
  v_result := public.settle_purchase_cash_payable(
    'd3333333-3333-4333-8333-333333333333', v_purchase_op,
    '[{"method":"cash","piastres":"2000"}]'::jsonb);
  if v_result ->> 'remaining_piastres' is distinct from '2000'
    or (select remaining_piastres from public.purchase_cash_payables
      where operation_id = v_purchase_op) <> 2000 then
    raise exception 'partial settlement mismatch';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'kind' = 'purchase_settlement'
      and movement.value ->> 'label_ar' = 'سداد شراء'
      and movement.value ->> 'has_note' = 'false'
  ) then
    raise exception 'settlement missing from confirmed feed';
  end if;
  if (public.settle_purchase_cash_payable(
      'd3333333-3333-4333-8333-333333333333', v_purchase_op,
      '[{"method":"cash","piastres":"2000"}]'::jsonb) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'settlement replay failed';
  end if;
  if (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'saleable_metal'
        and category_code = 'worked_jewelry' and karat = 18) <> v_gold_before then
    raise exception 'settlement moved stock twice';
  end if;
  begin
    perform public.settle_purchase_cash_payable(
      'd3434343-3434-4343-8343-343434343434', v_purchase_op,
      '[{"method":"cash","piastres":"3000"}]'::jsonb);
    raise exception 'oversettlement accepted';
  exception when others then
    if sqlerrm is distinct from 'settlement_exceeds_obligation' then raise; end if;
  end;
  v_result := public.post_daily_ledger_trade(
    'd3535353-3535-4353-8353-353535353535',
    jsonb_set(jsonb_set(v_partial, '{tenders}', '[]'::jsonb),
      '{purchase_obligation_piastres}', '"5000"'::jsonb));
  if (select remaining_piastres from public.purchase_cash_payables
      where operation_id = (v_result ->> 'operation_id')::uuid) <> 5000 then
    raise exception 'zero-cash purchase obligation missing';
  end if;
  select amount into v_cash_before from public.ledger_account_balances
  where shop_id = 'b1818181-8181-4181-8181-818181818181'
    and account_kind = 'cash_method' and method_code = 'cash';
  select amount into v_card_before from public.ledger_account_balances
  where shop_id = 'b1818181-8181-4181-8181-818181818181'
    and account_kind = 'cash_method' and method_code = 'card';
  v_result := public.post_daily_ledger_cash_transfer(
    'd3737373-3737-4373-8373-373737373737', v_transfer);
  if v_result ->> 'ok' is distinct from 'true'
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'cash_method' and method_code = 'cash')
      <> v_cash_before - 300
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'cash_method' and method_code = 'card')
      <> v_card_before + 300 then
    raise exception 'cash transfer balances mismatch';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'kind' = 'cash_transfer'
      and movement.value ->> 'label_ar' = 'تحويل نقدية'
      and movement.value ->> 'has_note' = 'true'
  ) then
    raise exception 'cash transfer missing from feed';
  end if;
  if (public.post_daily_ledger_cash_transfer(
    'd3737373-3737-4373-8373-373737373737', v_transfer) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'cash transfer replay failed';
  end if;
  begin
    perform public.post_daily_ledger_cash_transfer(
      'd3838383-3838-4383-8383-383838383838',
      jsonb_set(v_transfer, '{to_method}', '"cash"'::jsonb));
    raise exception 'same-method transfer accepted';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then raise; end if;
  end;
  begin
    perform public.post_daily_ledger_cash_transfer(
      'd3939393-3939-4393-8393-393939393939',
      jsonb_set(v_transfer, '{amount_piastres}', '"99999999"'::jsonb));
    execute 'set constraints all immediate';
    raise exception 'cash overdraft accepted';
  exception when others then
    if sqlerrm is distinct from 'negative_owned_balance' then raise; end if;
  end;
  execute 'set constraints all deferred';
  perform public.post_daily_ledger_trade(
    'd4040404-4040-4404-8404-404040404040', v_scrap_buy);
  v_result := public.post_daily_ledger_trade(
    'd4141414-4141-4414-8414-414141414141', v_scrap_sale);
  if v_result ->> 'ok' is distinct from 'true'
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'scrap_metal' and karat = 21) <> 200
    or public.get_daily_ledger_v2() -> 'day_summary' ->> 'sale_piastres'
      is distinct from '2000' then
    raise exception 'scrap sale cash or gold mismatch';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(
      public.get_daily_ledger_v2() -> 'day_summary' -> 'gold_by_bucket')
      as movement(value)
    where movement.value ->> 'kind' = 'sale'
      and movement.value ->> 'category' = 'scrap'
      and movement.value ->> 'karat' = '21'
      and movement.value ->> 'milligrams' = '300'
  ) or not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'kind' = 'scrap_sale'
      and movement.value ->> 'label_ar' = 'بيع كسر'
      and movement.value ->> 'has_note' = 'true'
  ) then
    raise exception 'scrap sale missing from ledger';
  end if;
  if (public.post_daily_ledger_trade(
    'd4141414-4141-4414-8414-414141414141', v_scrap_sale)
      ->> 'replayed') is distinct from 'true' then
    raise exception 'scrap sale replay failed';
  end if;
  begin
    perform public.post_daily_ledger_trade(
      'd4242424-4242-4424-8424-424242424242',
      jsonb_set(v_scrap_sale, '{items}',
        '[{"category":"worked_jewelry","karat":18,"milligrams":"300","count":"1","item_name":"خاتم","line_price_piastres":null}]'::jsonb));
    raise exception 'non-scrap quick action accepted';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then raise; end if;
  end;
  begin
    perform public.post_daily_ledger_trade(
      'd4343434-4343-4434-8434-434343434343',
      jsonb_set(v_scrap_sale, '{items}',
        '[{"category":"scrap","karat":21,"milligrams":"999999","count":null,"item_name":"كسر","line_price_piastres":null}]'::jsonb));
    execute 'set constraints all immediate';
    raise exception 'scrap overdraft accepted';
  exception when others then
    if sqlerrm is distinct from 'negative_owned_balance' then raise; end if;
  end;
  execute 'set constraints all deferred';
  v_cash_before := (select amount from public.ledger_account_balances
    where shop_id = 'b1818181-8181-4181-8181-818181818181'
      and account_kind = 'cash_method' and method_code = 'cash');
  v_result := public.post_daily_ledger_scrap_to_stock(
    'd4444444-4444-4444-8444-444444444444', v_scrap_to_stock);
  execute 'set constraints all immediate';
  if v_result ->> 'ok' is distinct from 'true'
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'scrap_metal' and karat = 21) <> 50
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'saleable_metal' and category_code = 'coin'
        and karat = 21) <> 150
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'saleable_count' and category_code = 'coin'
        and karat = 21) <> 2
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'cash_method' and method_code = 'cash')
      is distinct from v_cash_before then
    raise exception 'scrap-to-stock balance effect mismatch';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'kind' = 'scrap_to_stock'
      and movement.value ->> 'label_ar' = 'تحويل كسر إلى مخزون'
      and movement.value ->> 'has_note' = 'true'
  ) then
    raise exception 'scrap-to-stock missing from ledger feed';
  end if;
  if (public.post_daily_ledger_scrap_to_stock(
    'd4444444-4444-4444-8444-444444444444', v_scrap_to_stock)
      ->> 'replayed') is distinct from 'true' then
    raise exception 'scrap-to-stock replay failed';
  end if;
  execute 'set constraints all deferred';
  begin
    perform public.post_daily_ledger_scrap_to_stock(
      'd4545454-4545-4454-8454-454545454545',
      jsonb_set(v_scrap_to_stock, '{milligrams}', '"51"'::jsonb));
    execute 'set constraints all immediate';
    raise exception 'scrap-to-stock overdraft accepted';
  exception when others then
    if sqlerrm is distinct from 'negative_owned_balance' then raise; end if;
  end;
  execute 'set constraints all deferred';
  v_cash_before := (select amount from public.ledger_account_balances
    where shop_id = 'b1818181-8181-4181-8181-818181818181'
      and account_kind = 'cash_method' and method_code = 'cash');
  v_gold_before := (select amount from public.ledger_account_balances
    where shop_id = 'b1818181-8181-4181-8181-818181818181'
      and account_kind = 'saleable_metal' and category_code = 'worked_jewelry'
      and karat = 18);
  v_result := public.post_daily_ledger_return(
    'd4646464-4646-4464-8464-464646464646', v_sale_op, 'مرتجع اختبار');
  execute 'set constraints all immediate';
  if v_result ->> 'ok' is distinct from 'true'
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'cash_method' and method_code = 'cash')
      <> v_cash_before - 3000
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'saleable_metal'
        and category_code = 'worked_jewelry' and karat = 18)
      <> v_gold_before + 2000 then
    raise exception 'sale return did not reverse original journals';
  end if;
  if (public.post_daily_ledger_return(
    'd4646464-4646-4464-8464-464646464646', v_sale_op, 'مرتجع اختبار')
      ->> 'replayed') is distinct from 'true' then
    raise exception 'sale return replay failed';
  end if;
  execute 'set constraints all deferred';
  begin
    perform public.post_daily_ledger_return(
      'd4747474-4747-4474-8474-474747474747', v_sale_op, 'تكرار');
    raise exception 'duplicate return accepted';
  exception when others then
    if sqlerrm is distinct from 'already_returned' then raise; end if;
  end;
  v_cash_before := (select amount from public.ledger_account_balances
    where shop_id = 'b1818181-8181-4181-8181-818181818181'
      and account_kind = 'cash_method' and method_code = 'cash');
  v_gold_before := (select amount from public.ledger_account_balances
    where shop_id = 'b1818181-8181-4181-8181-818181818181'
      and account_kind = 'saleable_metal' and category_code = 'worked_jewelry'
      and karat = 18);
  v_result := public.post_daily_ledger_return(
    'd4848484-4848-4484-8484-484848484848', v_purchase_op, 'إلغاء شراء');
  execute 'set constraints all immediate';
  if v_result ->> 'ok' is distinct from 'true'
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'cash_method' and method_code = 'cash')
      <> v_cash_before + 3000
    or (select amount from public.ledger_account_balances
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and account_kind = 'saleable_metal'
        and category_code = 'worked_jewelry' and karat = 18)
      <> v_gold_before - 1000
    or (select remaining_piastres from public.purchase_cash_payables
      where shop_id = 'b1818181-8181-4181-8181-818181818181'
        and operation_id = v_purchase_op) <> 0 then
    raise exception 'purchase return cash, gold, or payable mismatch';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'kind' = 'sale_return'
      and movement.value ->> 'label_ar' = 'مرتجع بيع'
  ) or not exists (
    select 1 from jsonb_array_elements(public.get_daily_ledger_v2() -> 'feed')
      as movement(value)
    where movement.value ->> 'kind' = 'purchase_return'
      and movement.value ->> 'label_ar' = 'مرتجع شراء'
  ) then
    raise exception 'linked returns missing from feed';
  end if;
  execute 'set constraints all deferred';
  execute 'set constraints all immediate';
end;
$test$;

-- The second owner may read only the second shop and cannot fetch the first owner's operation.
select set_config('request.jwt.claim.sub', '82828282-8282-4282-8282-828282828282', true);
do $test$
declare v_op uuid; v_payable uuid;
begin
  if (public.get_daily_ledger_day_state() ->> 'state') is distinct from 'uninitialized' then
    raise exception 'cross-shop day leaked';
  end if;
  if jsonb_array_length(public.get_pending_invoice_sends(null) -> 'items') <> 0 then
    raise exception 'cross-shop pending-send queue leaked';
  end if;
  if exists (select 1 from public.financial_operations
    where shop_id = 'b1818181-8181-4181-8181-818181818181') then
    raise exception 'cross-shop operation leaked through RLS';
  end if;
  select id into v_op from ledger_test_operation limit 1;
  select id into v_payable from ledger_test_payable limit 1;
  if exists (select 1 from public.purchase_cash_payables
      where operation_id = v_payable) then
    raise exception 'cross-shop payable leaked through RLS';
  end if;
  begin
    perform public.settle_purchase_cash_payable(
      'd3636363-3636-4363-8363-363636363636', v_payable,
      '[{"method":"cash","piastres":"100"}]'::jsonb);
    raise exception 'cross-shop settlement accepted';
  exception when others then
    if sqlerrm is distinct from 'not_found' then raise; end if;
  end;
  begin
    perform public.get_invoice_dispatch_state(v_op);
    raise exception 'cross-shop invoice dispatch leaked';
  exception when others then
    if sqlerrm is distinct from 'not_found' then raise; end if;
  end;
  begin
    perform public.confirm_invoice_whatsapp_send(
      v_op, 'd2828282-8282-4282-8282-828282828282');
    raise exception 'cross-shop invoice confirmation accepted';
  exception when others then
    if sqlerrm is distinct from 'not_found' then raise; end if;
  end;
  begin
    perform public.get_daily_ledger_operation(v_op);
    raise exception 'cross-shop detail leaked';
  exception when others then
    if sqlerrm is distinct from 'not_found' then raise; end if;
  end;
end;
$test$;

rollback;

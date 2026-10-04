-- Milestone 3 inventory, custody, and one-unit obligations.
-- Synthetic fixtures, one connection, one transaction, ROLLBACK.
-- This session does not claim a concurrent race.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('a1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a3-owner@example.test', false, now(), now()),
  ('a2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'a3-other@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('a1222222-2222-4222-8222-222222222222', 'متجر المخزون', 'مالك المخزون', 'Africa/Cairo'),
  ('a2222222-2222-4222-8222-222222222222', 'متجر الآخر', 'مالك الآخر', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('a1222222-2222-4222-8222-222222222222', 'a1111111-1111-4111-8111-111111111111', 'owner'),
  ('a2222222-2222-4222-8222-222222222222', 'a2111111-1111-4111-8111-111111111111', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('a2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

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

create function pg_temp.expect_error(p_sql text, p_code text)
returns void language plpgsql security invoker set search_path = '' as $fn$
begin
  begin
    execute p_sql;
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception using message = 'expected_' || p_code;
      elsif sqlerrm is distinct from p_code then
        raise exception using message = 'expected_' || p_code || '_got_' || sqlerrm;
      end if;
  end;
end;
$fn$;

create function pg_temp.owned_mg(p_shop uuid, p_category text, p_karat integer)
returns bigint language sql security invoker set search_path = '' as $fn$
  select coalesce(sum(posting.amount), 0)::bigint
  from public.journal_postings as posting
  join public.ledger_accounts as account
    on account.id = posting.account_id and account.shop_id = posting.shop_id
  where posting.shop_id = p_shop
    and account.category_code = p_category and account.karat = p_karat
    and account.account_kind in ('saleable_metal', 'scrap_metal');
$fn$;

create function pg_temp.lot_mg(p_shop uuid, p_category text, p_karat integer, p_class text)
returns bigint language sql security invoker set search_path = '' as $fn$
  select coalesce(sum(movement.delta_milligrams), 0)::bigint
  from public.inventory_lot_movements as movement
  join public.inventory_lots as lot
    on lot.id = movement.lot_id and lot.shop_id = movement.shop_id
  where lot.shop_id = p_shop and lot.category_code = p_category
    and lot.karat = p_karat and lot.stock_class = p_class;
$fn$;

create function pg_temp.cash_method(p_shop uuid, p_method text)
returns bigint language sql security invoker set search_path = '' as $fn$
  select amount from public.ledger_account_balances
  where shop_id = p_shop and account_kind = 'cash_method' and method_code = p_method;
$fn$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

select public.confirm_opening_balances(
  'a1333333-3333-4333-8333-333333333333',
  '{"version":1,"cash":{"cash":"10000000","card":"3000000","instant_transfer":"2000000","wallet":"1000000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"40000","count":"10"},{"category":"worked_jewelry","karat":21,"milligrams":"60000","count":"10"},{"category":"bullion","karat":24,"milligrams":"20000","count":"4"},{"category":"coin","karat":21,"milligrams":"16000","count":"2"}],"scrap":[{"karat":18,"milligrams":"20000"},{"karat":21,"milligrams":"30000"}]}'::jsonb
);

do $m3$
declare
  v_shop uuid := 'a1222222-2222-4222-8222-222222222222';
  v_result jsonb;
  v_totals jsonb;
  v_items jsonb;
  v_lot uuid;
  v_lot18 uuid;
  v_scrap18 uuid;
  v_scrap21 uuid;
  v_jewel21 uuid;
  v_denom uuid;
  v_coin uuid;
  v_trader uuid;
  v_receipt uuid;
  v_pending uuid;
  v_add_op uuid;
  v_add_lot uuid;
  v_transfer_op uuid;
  v_gold_op uuid;
  v_before_ops bigint;
  v_before_cash bigint;
  v_page jsonb;
  v_cursor text;
  v_payload jsonb;
  v_effects jsonb;
begin
  if (select count(*) from public.inventory_lots where shop_id = v_shop) <> 6 then
    raise exception 'opening_lots_missing';
  end if;
  if exists (
    select 1 from public.inventory_lots
    where shop_id = v_shop and legacy_aggregate
  ) then
    raise exception 'new_opening_marked_legacy';
  end if;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 40000
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 18, 'owned_available') <> 40000 then
    raise exception 'opening_lot_journal_mismatch';
  end if;
  v_totals := public.get_inventory_totals_v1();
  if v_totals -> 'buckets' -> 0 ->> 'available_milligrams' is null then
    raise exception 'totals_empty';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(v_totals -> 'buckets') as bucket(value)
    where bucket.value ->> 'category' = 'worked_jewelry'
      and bucket.value ->> 'karat' = '18'
      and bucket.value ->> 'available_milligrams' = '40000'
      and bucket.value ->> 'available_count' = '10'
      and bucket.value ->> 'pending_milligrams' = '0'
      and bucket.value ->> 'held_milligrams' = '0'
  ) then
    raise exception 'opening_totals_mismatch';
  end if;

  v_result := public.save_inventory_product_v1(
    'a1400001-0001-4001-8001-000000000001',
    pg_temp.with_day('{"version":1,"kind":"product","name":"سبيكة خمس جرامات","category":"bullion","karat":24}'::jsonb)
  );
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'product_save_failed'; end if;
  if (public.save_inventory_product_v1(
      'a1400001-0001-4001-8001-000000000001',
      pg_temp.with_day('{"version":1,"kind":"product","name":"سبيكة خمس جرامات","category":"bullion","karat":24}'::jsonb)
    ) ->> 'replayed') is distinct from 'true' then
    raise exception 'product_replay_failed';
  end if;
  v_result := public.save_bullion_denomination_v1(
    'a1400002-0002-4002-8002-000000000002',
    pg_temp.with_day('{"version":1,"kind":"bullion_denomination","label":"5 جرام","nominal_milligrams":"5000","active":true}'::jsonb)
  );
  v_denom := (v_result ->> 'id')::uuid;
  v_result := public.save_coin_type_v1(
    'a1400003-0003-4003-8003-000000000003',
    pg_temp.with_day('{"version":1,"kind":"coin_type","label":"نصف جنيه","nominal_milligrams":"4000","active":true}'::jsonb)
  );
  v_coin := (v_result ->> 'id')::uuid;
  v_result := public.save_trader_v1(
    'a1400004-0004-4004-8004-000000000004',
    pg_temp.with_day('{"version":1,"kind":"trader","display_name":"تاجر تجريبي","phone":"+201000000001","note":"","active":true}'::jsonb)
  );
  v_trader := (v_result ->> 'id')::uuid;
  if (public.search_traders_v1('تاجر') -> 'items' -> 0 ->> 'trader_id') is distinct from v_trader::text then
    raise exception 'trader_search_missed';
  end if;

  select lot.id into v_lot18 from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.category_code = 'worked_jewelry' and lot.karat = 18
    order by lot.created_at, lot.id limit 1;
  select lot.id into v_jewel21 from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.category_code = 'worked_jewelry' and lot.karat = 21
    order by lot.created_at, lot.id limit 1;
  select lot.id into v_scrap18 from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.category_code = 'scrap' and lot.karat = 18
    order by lot.created_at, lot.id limit 1;
  select lot.id into v_scrap21 from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.category_code = 'scrap' and lot.karat = 21
    order by lot.created_at, lot.id limit 1;

  v_result := public.post_daily_ledger_trade(
    'a1500001-0001-4001-8001-000000000001',
    '{"version":1,"kind":"sale","total_piastres":"420000","tenders":[{"method":"cash","piastres":"420000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1830","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'fifo_sale_failed'; end if;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 38170
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 18, 'owned_available') <> 38170 then
    raise exception 'fifo_sale_lots_diverged';
  end if;
  if pg_temp.cash_method(v_shop, 'cash') <> 10420000 then
    raise exception 'fifo_sale_cash_mismatch';
  end if;

  v_payload := pg_temp.with_day(jsonb_build_object(
    'version', 2, 'kind', 'sale', 'total_piastres', '107000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '107000')),
    'items', jsonb_build_array(jsonb_build_object(
      'category', 'worked_jewelry', 'karat', 18, 'milligrams', '1000', 'count', '1',
      'item_name', 'خاتم', 'line_price_piastres', '100000')),
    'description', '', 'customer_name', '', 'customer_phone', '', 'note', '',
    'lot_selections', jsonb_build_array(jsonb_build_object(
      'lot_id', v_lot18, 'milligrams', '1000', 'count', '1')),
    'pricing', jsonb_build_object(
      'base_piastres', '100000', 'workmanship_piastres', '10000',
      'other_charges_piastres', '2000', 'other_charges_label', 'تغليف',
      'discount_piastres', '5000')
  ));
  v_result := public.post_daily_ledger_trade_v2(
    'a1500002-0002-4002-8002-000000000002', v_payload);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'explicit_priced_sale_failed'; end if;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 37170
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 18, 'owned_available') <> 37170 then
    raise exception 'explicit_sale_lots_diverged';
  end if;
  if pg_temp.cash_method(v_shop, 'cash') <> 10527000 then
    raise exception 'priced_sale_cash_mismatch';
  end if;
  if (public.post_daily_ledger_trade_v2(
      'a1500002-0002-4002-8002-000000000002', v_payload) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'explicit_sale_replay_failed';
  end if;
  begin
    perform public.post_daily_ledger_trade_v2(
      'a1500002-0002-4002-8002-000000000002',
      jsonb_set(v_payload, '{pricing,discount_piastres}', '"5001"'));
    raise exception 'expected_payload_mismatch';
  exception when others then
    if sqlerrm <> 'payload_mismatch' then raise; end if;
  end;

  v_payload := pg_temp.with_day(jsonb_build_object(
    'version', 2, 'kind', 'purchase', 'total_piastres', '3000000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '3000000')),
    'items', jsonb_build_array(jsonb_build_object(
      'category', 'bullion', 'karat', 24, 'milligrams', '4998', 'count', '1',
      'item_name', 'سبيكة خمس جرامات', 'line_price_piastres', '3000000')),
    'description', '', 'customer_name', '', 'customer_phone', '', 'note', '',
    'lot_identities', jsonb_build_array(jsonb_build_object(
      'denomination_id', v_denom, 'coin_type_id', null))
  ));
  v_result := public.post_daily_ledger_trade_v2(
    'a1500003-0003-4003-8003-000000000003', v_payload);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'measured_bullion_failed'; end if;
  if not exists (
    select 1 from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.category_code = 'bullion'
      and lot.original_milligrams = 4998 and lot.denomination_id = v_denom
      and lot.origin_operation_id = (v_result ->> 'operation_id')::uuid
  ) then
    raise exception 'nominal_weight_substituted';
  end if;
  if pg_temp.owned_mg(v_shop, 'bullion', 24) <> 24998 then
    raise exception 'bullion_measured_total_mismatch';
  end if;

  v_result := public.post_daily_ledger_trade(
    'a1500004-0004-4004-8004-000000000004',
    '{"version":1,"kind":"purchase","total_piastres":"4000000","tenders":[{"method":"cash","piastres":"4000000"}],"items":[{"category":"coin","karat":21,"milligrams":"3998","count":"1","item_name":"نصف جنيه","line_price_piastres":"2000000"},{"category":"scrap","karat":21,"milligrams":"3998","count":null,"item_name":"كسر جنيه","line_price_piastres":"2000000"}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  if pg_temp.owned_mg(v_shop, 'coin', 21) <> 19998
    or pg_temp.owned_mg(v_shop, 'scrap', 21) <> 33998 then
    raise exception 'coin_routing_mismatch';
  end if;

  v_result := public.post_daily_ledger_trade(
    'a1500005-0005-4005-8005-000000000005',
    '{"version":1,"kind":"scrap_sale","total_piastres":"750000","tenders":[{"method":"cash","piastres":"500000"},{"method":"card","piastres":"250000"}],"items":[{"category":"scrap","karat":18,"milligrams":"2000","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true'
    or pg_temp.owned_mg(v_shop, 'scrap', 18) <> 18000
    or pg_temp.lot_mg(v_shop, 'scrap', 18, 'owned_available') <> 18000 then
    raise exception 'legacy_scrap_sale_incompatible';
  end if;

  v_before_cash := pg_temp.cash_method(v_shop, 'cash');
  v_payload := pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"إضافة يدوية مطابقة للإيصال","lines":[{"item_name":"سوار","category":"worked_jewelry","karat":21,"milligrams":"3000","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb);
  v_result := public.post_inventory_addition_v1(
    'a1600001-0001-4001-8001-000000000001', v_payload);
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'manual_add_failed'; end if;
  v_add_op := (v_result ->> 'operation_id')::uuid;
  v_effects := v_result -> 'effects' -> 'movements';
  if jsonb_array_length(v_effects) <> 1
    or v_effects -> 0 ->> 'delta_milligrams' <> '3000' then
    raise exception 'manual_add_effects_missing';
  end if;
  if pg_temp.cash_method(v_shop, 'cash') is distinct from v_before_cash then
    raise exception 'manual_add_touched_cash';
  end if;
  if (public.post_inventory_addition_v1(
      'a1600001-0001-4001-8001-000000000001', v_payload) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'manual_add_replay_failed';
  end if;
  select lot.id into v_add_lot from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.origin_operation_id = v_add_op;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 21) <> 63000 then
    raise exception 'manual_add_owned_mismatch';
  end if;

  v_result := public.post_inventory_receipt_v1(
    'a1700001-0001-4001-8001-000000000001',
    pg_temp.with_day('{"version":1,"kind":"inventory_receipt","owner_kind":"shop","trader_id":null,"counterparty_name":"مورد","product_name":"سوار","category":"worked_jewelry","karat":21,"milligrams":"3000","count":"1","recognition":"deferred","denomination_id":null,"coin_type_id":null,"note":""}'::jsonb)
  );
  v_pending := (v_result -> 'effects' ->> 'receipt_id')::uuid;
  if v_pending is null then raise exception 'deferred_receipt_id_missing'; end if;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 21) <> 63000
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 21, 'owned_pending') <> 3000 then
    raise exception 'deferred_receipt_posted_owned';
  end if;
  if (public.get_inventory_totals_v1('worked_jewelry', 21::smallint) -> 'buckets' -> 0 ->> 'pending_milligrams')
      is distinct from '3000' then
    raise exception 'pending_totals_mismatch';
  end if;

  v_result := public.post_receipt_manual_allocation_v1(
    'a1700002-0002-4002-8002-000000000002',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'receipt_manual_allocation',
      'receipt_id', v_pending, 'manual_operation_id', v_add_op, 'lot_id', v_add_lot,
      'milligrams', '3000', 'count', '1', 'reason', 'ربط الإيصال بالإضافة اليدوية'
    ))
  );
  if v_result ->> 'ok' is distinct from 'true' then raise exception 'manual_link_failed'; end if;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 21) <> 63000
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 21, 'owned_pending') <> 0 then
    raise exception 'manual_link_double_posted';
  end if;
  v_before_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  begin
    perform public.post_receipt_manual_allocation_v1(
      'a1700003-0003-4003-8003-000000000003',
      pg_temp.with_day(jsonb_build_object(
        'version', 1, 'kind', 'receipt_manual_allocation',
        'receipt_id', v_pending, 'manual_operation_id', v_add_op, 'lot_id', v_add_lot,
        'milligrams', '3000', 'count', '1', 'reason', 'تكرار الربط'
      ))
    );
    raise exception 'duplicate_manual_link_accepted';
  exception when others then
    if sqlerrm <> 'already_allocated' then raise; end if;
  end;
  if (select count(*) from public.financial_operations where shop_id = v_shop) <> v_before_ops then
    raise exception 'duplicate_link_left_rows';
  end if;

  v_result := public.post_inventory_receipt_v1(
    'a1700004-0004-4004-8004-000000000004',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_receipt', 'owner_kind', 'trader',
      'trader_id', v_trader, 'counterparty_name', 'تاجر تجريبي',
      'product_name', 'طقم', 'category', 'worked_jewelry', 'karat', 21,
      'milligrams', '10000', 'count', '2', 'recognition', 'custody',
      'denomination_id', null, 'coin_type_id', null, 'note', ''
    ))
  );
  v_receipt := (v_result -> 'effects' ->> 'receipt_id')::uuid;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 21) <> 63000
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 21, 'trader_custody') <> 10000
    or pg_temp.cash_method(v_shop, 'cash') is distinct from v_before_cash then
    raise exception 'custody_leaked_into_owned';
  end if;
  if (public.get_trader_v1(v_trader) ->> 'original_held_milligrams') is distinct from '10000'
    or (public.get_trader_v1(v_trader) ->> 'current_held_milligrams') is distinct from '10000'
    or (public.get_trader_v1(v_trader) ->> 'pending_receipt_count') is distinct from '1' then
    raise exception 'trader_detail_mismatch';
  end if;
  begin
    perform public.post_inventory_recognition_v1(
      'a1700005-0005-4005-8005-000000000005',
      pg_temp.with_day(jsonb_build_object(
        'version', 1, 'kind', 'inventory_recognition', 'receipt_id', v_receipt,
        'milligrams', '10000', 'count', '2', 'reason', 'اعتراف غير مسموح'
      ))
    );
    raise exception 'custody_recognition_accepted';
  exception when others then
    if sqlerrm <> 'custody_requires_transfer' then raise; end if;
  end;
  begin
    perform public.post_receipt_manual_allocation_v1(
      'a1700006-0006-4006-8006-000000000006',
      pg_temp.with_day(jsonb_build_object(
        'version', 1, 'kind', 'receipt_manual_allocation',
        'receipt_id', v_receipt, 'manual_operation_id', v_add_op, 'lot_id', v_add_lot,
        'milligrams', '10000', 'count', '2', 'reason', 'ربط عهدة'
      ))
    );
    raise exception 'custody_manual_link_accepted';
  exception when others then
    if sqlerrm <> 'custody_requires_transfer' then raise; end if;
  end;

  v_before_cash := pg_temp.cash_method(v_shop, 'cash');
  v_result := public.post_ownership_transfer_v1(
    'a1700007-0007-4007-8007-000000000007',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'ownership_transfer', 'receipt_id', v_receipt,
      'milligrams', '10000', 'count', '2', 'reason', 'شراء من التاجر',
      'price_piastres', '6000000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '2000000')),
      'purchase_obligation_piastres', '4000000'
    ))
  );
  v_transfer_op := (v_result ->> 'operation_id')::uuid;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 21) <> 73000
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 21, 'trader_custody') <> 0
    or pg_temp.cash_method(v_shop, 'cash') <> v_before_cash - 2000000 then
    raise exception 'ownership_transfer_mismatch';
  end if;
  if (select remaining_piastres from public.purchase_cash_payables
      where operation_id = v_transfer_op) <> 4000000 then
    raise exception 'egp_payable_not_reused';
  end if;
  if exists (
    select 1 from public.gold_obligations where operation_id = v_transfer_op
  ) then
    raise exception 'mixed_obligation_created';
  end if;
  if (select trader_id from public.purchase_cash_payables
      where operation_id = v_transfer_op) is distinct from v_trader then
    raise exception 'ownership_transfer_trader_unlinked';
  end if;
  if (public.get_trader_v1(v_trader) ->> 'cash_payable_remaining_piastres')
      is distinct from '4000000' then
    raise exception 'trader_cash_before_settlement_mismatch';
  end if;
  v_result := public.settle_purchase_cash_payable(
    'a1700008-0008-4008-8008-000000000008', v_transfer_op,
    '[{"method":"cash","piastres":"1000000"}]'::jsonb);
  if v_result ->> 'remaining_piastres' is distinct from '3000000'
    or pg_temp.owned_mg(v_shop, 'worked_jewelry', 21) <> 73000 then
    raise exception 'egp_settlement_moved_gold';
  end if;
  if (public.get_trader_v1(v_trader) ->> 'current_held_milligrams') is distinct from '0'
    or (public.get_trader_v1(v_trader) ->> 'pending_receipt_count') is distinct from '0'
    or (public.get_trader_v1(v_trader) ->> 'cash_payable_remaining_piastres')
      is distinct from '3000000' then
    raise exception 'trader_after_transfer_mismatch';
  end if;
  if jsonb_array_length(public.list_trader_activity_v1(v_trader) -> 'items') < 2 then
    raise exception 'trader_activity_missing';
  end if;
  if (
    select count(*) from jsonb_array_elements(public.list_trader_activity_v1(v_trader, 100) -> 'items')
      as activity(value)
    where activity.value ->> 'kind' = 'purchase_settlement'
  ) <> 1 then
    raise exception 'settlement_activity_not_once';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(public.list_trader_obligations_v1(v_trader) -> 'items')
      as item(value)
    where item.value ->> 'unit' = 'egp_piastres'
      and item.value ->> 'operation_id' = v_transfer_op::text
      and item.value ->> 'remaining' = '3000000'
      and item.value ->> 'original' = '4000000'
      and item.value ->> 'karat' is null
  ) then
    raise exception 'trader_cash_obligation_list_mismatch';
  end if;
  v_result := public.post_daily_ledger_trade(
    'a1700013-0013-4013-8013-000000000013',
    '{"version":1,"kind":"purchase","total_piastres":"5000","tenders":[],"items":[{"category":"scrap","karat":14,"milligrams":"100","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"تاجر تجريبي","customer_phone":"","note":"","purchase_obligation_piastres":"5000"}'::jsonb
  );
  if (select trader_id from public.purchase_cash_payables
      where operation_id = (v_result ->> 'operation_id')::uuid) is not null then
    raise exception 'named_seller_guessed_as_trader';
  end if;
  if (public.get_trader_v1(v_trader) ->> 'cash_payable_remaining_piastres')
      is distinct from '3000000' then
    raise exception 'unlinked_payable_attributed';
  end if;

  v_result := public.post_gold_obligation_acquisition_v1(
    'a1800001-0001-4001-8001-000000000001',
    pg_temp.with_day('{"version":1,"kind":"gold_obligation_acquisition","category":"worked_jewelry","karat":18,"milligrams":"5000","count":"1","item_name":"غويشة","obligation_karat":18,"obligation_milligrams":"4000","counterparty_name":"تاجر ذهب","note":"","denomination_id":null,"coin_type_id":null}'::jsonb)
  );
  v_gold_op := (v_result ->> 'operation_id')::uuid;
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 42170
    or exists (select 1 from public.purchase_cash_payables where operation_id = v_gold_op)
    or (select trader_id from public.gold_obligations where operation_id = v_gold_op) is not null
    or jsonb_array_length(public.get_trader_v1(v_trader) -> 'gold_remaining') <> 0 then
    raise exception 'gold_acquisition_opened_cash_payable';
  end if;
  v_result := public.post_gold_obligation_settlement_v1(
    'a1800002-0002-4002-8002-000000000002',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'gold_obligation_settlement',
      'obligation_operation_id', v_gold_op, 'reason', 'تسليم كسر جزئي',
      'deliveries', jsonb_build_array(jsonb_build_object(
        'lot_id', v_scrap18, 'milligrams', '1500', 'count', null))
    ))
  );
  if v_result ->> 'ok' is distinct from 'true'
    or (select remaining_milligrams from public.gold_obligations where operation_id = v_gold_op) <> 2500
    or pg_temp.owned_mg(v_shop, 'scrap', 18) <> 16500
    or pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 42170 then
    raise exception 'partial_gold_settlement_mismatch';
  end if;
  v_result := public.post_gold_obligation_acquisition_v1(
    'a1800004-0004-4004-8004-000000000004',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'gold_obligation_acquisition', 'category', 'worked_jewelry',
      'karat', 18, 'milligrams', '1000', 'count', '1', 'item_name', 'غويشة',
      'obligation_karat', 18, 'obligation_milligrams', '800',
      'counterparty_name', 'تاجر تجريبي', 'note', '',
      'denomination_id', null, 'coin_type_id', null, 'trader_id', v_trader
    ))
  );
  if (select trader_id from public.gold_obligations
      where operation_id = (v_result ->> 'operation_id')::uuid) is distinct from v_trader
    or (public.get_trader_v1(v_trader) -> 'gold_remaining' -> 0 ->> 'remaining_milligrams')
      is distinct from '800' then
    raise exception 'linked_gold_obligation_mismatch';
  end if;
  v_result := public.post_gold_obligation_settlement_v1(
    'a1800005-0005-4005-8005-000000000005',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'gold_obligation_settlement',
      'obligation_operation_id', (v_result ->> 'operation_id')::uuid,
      'reason', 'تسليم مرتبط',
      'deliveries', jsonb_build_array(jsonb_build_object(
        'lot_id', v_scrap18, 'milligrams', '800', 'count', null))
    ))
  );
  if (public.get_trader_v1(v_trader) -> 'gold_remaining' -> 0 ->> 'remaining_milligrams')
      is distinct from '0' then
    raise exception 'linked_gold_settlement_balance';
  end if;
  if (
    select count(*) from jsonb_array_elements(public.list_trader_activity_v1(v_trader, 100) -> 'items')
      as activity(value)
    where activity.value ->> 'kind' = 'gold_obligation_settlement'
  ) <> 1 then
    raise exception 'gold_settlement_activity_not_once';
  end if;
  if not exists (
    select 1 from jsonb_array_elements(
      public.list_inventory_receipts_v1('trader', v_trader, 'custody') -> 'items')
      as item(value)
    where item.value ->> 'receipt_id' = v_receipt::text
      and item.value ->> 'remaining_milligrams' = '0'
      and item.value ->> 'remaining_count' = '0'
      and item.value ->> 'owner_kind' = 'trader'
  ) then
    raise exception 'receipt_list_remaining_mismatch';
  end if;
  v_page := public.list_inventory_receipts_v1(null, null, null, 1, null);
  if jsonb_array_length(v_page -> 'items') <> 1 or v_page ->> 'next_cursor' is null then
    raise exception 'receipt_pagination_missing';
  end if;
  begin
    perform public.post_gold_obligation_settlement_v1(
      'a1800003-0003-4003-8003-000000000003',
      pg_temp.with_day(jsonb_build_object(
        'version', 1, 'kind', 'gold_obligation_settlement',
        'obligation_operation_id', v_gold_op, 'reason', 'تجاوز',
        'deliveries', jsonb_build_array(jsonb_build_object(
          'lot_id', v_scrap18, 'milligrams', '3000', 'count', null))
      ))
    );
    raise exception 'gold_oversettlement_accepted';
  exception when others then
    if sqlerrm <> 'settlement_exceeds_obligation' then raise; end if;
  end;

  v_result := public.post_inventory_receipt_v1(
    'a1700009-0009-4009-8009-000000000009',
    pg_temp.with_day('{"version":1,"kind":"inventory_receipt","owner_kind":"shop","counterparty_name":"مورد فوري","product_name":"حلق","category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","recognition":"immediate","denomination_id":null,"coin_type_id":null,"note":""}'::jsonb)
  );
  if pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 45170 then
    raise exception 'immediate_receipt_not_owned';
  end if;
  v_result := public.post_inventory_receipt_v1(
    'a1700010-0010-4010-8010-000000000010',
    pg_temp.with_day('{"version":1,"kind":"inventory_receipt","owner_kind":"shop","counterparty_name":"مورد لاحق","product_name":"دبوس","category":"worked_jewelry","karat":18,"milligrams":"1500","count":"1","recognition":"deferred","denomination_id":null,"coin_type_id":null,"note":""}'::jsonb)
  );
  v_pending := (v_result -> 'effects' ->> 'receipt_id')::uuid;
  v_payload := pg_temp.with_day(jsonb_build_object(
    'version', 1, 'kind', 'inventory_recognition', 'receipt_id', v_pending,
    'milligrams', '1500', 'count', '1', 'reason', 'اعتراف لاحق'
  ));
  v_result := public.post_inventory_recognition_v1(
    'a1700011-0011-4011-8011-000000000011', v_payload);
  if v_result ->> 'ok' is distinct from 'true'
    or pg_temp.owned_mg(v_shop, 'worked_jewelry', 18) <> 46670
    or pg_temp.lot_mg(v_shop, 'worked_jewelry', 18, 'owned_pending') <> 0 then
    raise exception 'later_recognition_mismatch';
  end if;
  if (public.post_inventory_recognition_v1(
      'a1700011-0011-4011-8011-000000000011', v_payload) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'recognition_replay_failed';
  end if;
  begin
    perform public.post_inventory_recognition_v1(
      'a1700012-0012-4012-8012-000000000012',
      pg_temp.with_day(jsonb_build_object(
        'version', 1, 'kind', 'inventory_recognition', 'receipt_id', v_pending,
        'milligrams', '1500', 'count', '1', 'reason', 'اعتراف مكرر'
      ))
    );
    raise exception 'duplicate_recognition_accepted';
  exception when others then
    if sqlerrm <> 'already_allocated' then raise; end if;
  end;

  v_before_cash := pg_temp.cash_method(v_shop, 'cash');
  v_result := public.post_inventory_correction_v1(
    'a1600002-0002-4002-8002-000000000002',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_correction', 'reason', 'جرد فعلي',
      'cash_deltas', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '-10000')),
      'metal_deltas', jsonb_build_array(jsonb_build_object(
        'lot_id', v_lot18, 'milligrams', '-1000', 'count', '-1'))
    ))
  );
  if v_result ->> 'ok' is distinct from 'true'
    or pg_temp.cash_method(v_shop, 'cash') <> v_before_cash - 10000
    or pg_temp.owned_mg(v_shop, 'worked_jewelry', 18)
      <> pg_temp.lot_mg(v_shop, 'worked_jewelry', 18, 'owned_available') then
    raise exception 'correction_mismatch';
  end if;

  v_result := public.post_inventory_conversion_v1(
    'a1600003-0003-4003-8003-000000000003',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_conversion', 'reason', 'تحويل كسر إلى مشغول',
      'karat', 21, 'milligrams', '150', 'source_category', 'scrap',
      'source_lot_id', v_scrap21, 'source_count', null,
      'destination_category', 'coin', 'destination_count', '2', 'item_name', 'جنيه ذهب'
    ))
  );
  if v_result ->> 'ok' is distinct from 'true'
    or pg_temp.owned_mg(v_shop, 'scrap', 21) <> 33848
    or pg_temp.lot_mg(v_shop, 'scrap', 21, 'owned_available') <> 33848 then
    raise exception 'conversion_mismatch';
  end if;

  begin
    perform public.post_inventory_removal_v1(
      'a1600004-0004-4004-8004-000000000004',
      pg_temp.with_day(jsonb_build_object(
        'version', 1, 'kind', 'inventory_removal', 'reason', 'إتلاف عينة',
        'lines', jsonb_build_array(jsonb_build_object(
          'lot_id', v_add_lot, 'milligrams', '500', 'count', '1'))
      ))
    );
    raise exception 'piece_pair_removal_accepted';
  exception when others then
    if sqlerrm <> 'stock_pair_mismatch' then raise; end if;
  end;
  v_result := public.post_inventory_removal_v1(
    'a1600005-0005-4005-8005-000000000005',
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_removal', 'reason', 'إتلاف القطعة كاملة',
      'lines', jsonb_build_array(jsonb_build_object(
        'lot_id', v_add_lot, 'milligrams', '3000', 'count', '1'))
    ))
  );
  if v_result ->> 'ok' is distinct from 'true'
    or pg_temp.owned_mg(v_shop, 'worked_jewelry', 21)
      <> pg_temp.lot_mg(v_shop, 'worked_jewelry', 21, 'owned_available') then
    raise exception 'full_piece_removal_mismatch';
  end if;

  v_before_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  begin
    perform public.post_daily_ledger_trade(
      'a1500006-0006-4006-8006-000000000006',
      '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"999999","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
    );
    raise exception 'oversold_fifo_accepted';
  exception when others then
    if sqlerrm not in ('negative_owned_balance', 'insufficient_stock') then raise; end if;
  end;
  begin
    perform public.post_inventory_addition_v1(
      'a1600006-0006-4006-8006-000000000006',
      pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"حقل زائد","extra":"x","lines":[{"item_name":"سوار","category":"worked_jewelry","karat":21,"milligrams":"100","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb)
    );
    raise exception 'unknown_field_accepted';
  exception when others then
    if sqlerrm <> 'invalid_input' then raise; end if;
  end;
  begin
    perform public.post_inventory_addition_v1(
      'a1600007-0007-4007-8007-000000000007',
      jsonb_set(pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"نسخة قديمة","lines":[{"item_name":"سوار","category":"worked_jewelry","karat":21,"milligrams":"100","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb),
        '{expected_day_version}', '"0"')
    );
    raise exception 'stale_day_accepted';
  exception when others then
    if sqlerrm <> 'stale_day' then raise; end if;
  end;
  begin
    perform public.post_inventory_addition_v1(
      'a1600008-0008-4008-8008-000000000008',
      pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"عيار مرفوض","lines":[{"item_name":"سوار","category":"worked_jewelry","karat":24,"milligrams":"100","count":"1","denomination_id":null,"coin_type_id":null}]}'::jsonb)
    );
    raise exception 'invalid_pair_accepted';
  exception when others then
    if sqlerrm <> 'unsupported_category_karat' then raise; end if;
  end;
  if (select count(*) from public.financial_operations where shop_id = v_shop) <> v_before_ops then
    raise exception 'rejected_commands_left_rows';
  end if;

  v_page := public.list_inventory_lots_v1('worked_jewelry', 18::smallint, 'owned_available', null, 1, null);
  if jsonb_array_length(v_page -> 'items') <> 1 or v_page ->> 'next_cursor' is null then
    raise exception 'lot_pagination_missing';
  end if;
  v_cursor := v_page ->> 'next_cursor';
  v_page := public.list_inventory_lots_v1('worked_jewelry', 18::smallint, 'owned_available', null, 1, v_cursor);
  if jsonb_array_length(v_page -> 'items') < 1 then
    raise exception 'lot_pagination_second_page_empty';
  end if;
  v_lot := (public.list_inventory_lots_v1(null, null, null, 'سبيكة', 10, null) -> 'items' -> 0 ->> 'lot_id')::uuid;
  if v_lot is null then raise exception 'lot_search_missed'; end if;
  if jsonb_array_length(public.list_lot_movements_v1(v_lot18, 5, null) -> 'items') < 1 then
    raise exception 'movement_history_empty';
  end if;
  if public.get_inventory_totals_v1('scrap', 18::smallint) -> 'buckets' -> 0 ->> 'available_count' is not null then
    raise exception 'scrap_count_not_null';
  end if;
  if exists (
    select 1 from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.lot_id = lot.id
    group by lot.id
    having coalesce(sum(movement.delta_milligrams), 0) < 0
      or coalesce(sum(movement.delta_count), 0) < 0
  ) then
    raise exception 'negative_lot_remainder';
  end if;
  if exists (
    select 1 from public.journals as journal
    join public.journal_postings as posting on posting.journal_id = journal.id
    where journal.shop_id = v_shop
    group by journal.id
    having sum(posting.amount) <> 0
  ) then
    raise exception 'journal_imbalance_after_inventory';
  end if;
end;
$m3$;

reset role;
select set_config('request.jwt.claim.sub', 'a2111111-1111-4111-8111-111111111111', true);
set local role authenticated;
do $cross$
begin
  if jsonb_array_length(public.list_inventory_lots_v1() -> 'items') <> 0 then
    raise exception 'cross_shop_lots_visible';
  end if;
  begin
    perform public.get_trader_v1('a1400004-0004-4004-8004-000000000004');
    raise exception 'cross_shop_trader_visible';
  exception when others then
    if sqlerrm <> 'not_found' then raise; end if;
  end;
  if jsonb_array_length(public.list_inventory_receipts_v1() -> 'items') <> 0 then
    raise exception 'cross_shop_receipts_visible';
  end if;
end;
$cross$;

reset role;
select 'milestone_3_inventory_passed' as result;
rollback;



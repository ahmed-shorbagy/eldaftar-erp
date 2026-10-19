-- Current-day sale and purchase edit/delete. One transaction, then ROLLBACK.
-- Authenticated return and exchange writes stay revoked here. Historic suites
-- restore those grants inside their own disposable transactions.
begin;
set local time zone 'UTC';
-- Conservation and owned-balance triggers stay deferred. Opening and trade
-- posting insert a journal before its lines, and a same-method edit refund is
-- negative until the replacement posts. The trade-change final assert rejects
-- a negative end state inside the statement. This file rolls back, so the
-- deferred balance trigger is checked explicitly after the net refund.

create temp table trade_ids (
  name text primary key,
  id uuid,
  body jsonb
);
grant all on table trade_ids to authenticated;

create function pg_temp.catch(p_sql text) returns text
language plpgsql as $fn$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlerrm;
end;
$fn$;

create function pg_temp.call_json(p_sql text) returns jsonb
language plpgsql as $fn$
declare
  v_result jsonb;
begin
  execute p_sql into v_result;
  return v_result;
end;
$fn$;

create function pg_temp.fail_replacement() returns trigger
language plpgsql as $fn$
begin
  if pg_catalog.current_setting('eldaftar.fail_trade_replacement', true) = 'on'
    and new.kind in ('sale', 'purchase') then
    raise exception 'injected_rollback';
  end if;
  return new;
end;
$fn$;

create function pg_temp.money_balance(p_shop uuid, p_method text)
returns bigint
language sql
stable
as $fn$
  select coalesce(max(balance.amount), 0)::bigint
  from public.ledger_account_balances as balance
  where balance.shop_id = p_shop
    and balance.account_kind = 'cash_method'
    and balance.method_code = p_method;
$fn$;

do $privileges$
begin
  if has_function_privilege('authenticated', 'public.post_linked_return_v1(uuid,jsonb)', 'execute')
    or has_function_privilege('authenticated', 'public.post_exchange_v1(uuid,jsonb)', 'execute')
    or has_function_privilege('authenticated', 'public.post_daily_ledger_return(uuid,uuid,text)', 'execute') then
    raise exception 'return_write_still_granted';
  end if;
  if not has_function_privilege('authenticated', 'public.post_ledger_correction_v1(uuid,jsonb)', 'execute') then
    raise exception 'correction_write_revoked';
  end if;
  if not has_function_privilege('authenticated', 'public.get_return_remainder_v1(uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.review_ledger_trade_change_v1(uuid,text,jsonb)', 'execute')
    or not has_function_privilege('authenticated', 'public.post_ledger_trade_change_v1(uuid,uuid,text,jsonb,uuid,bigint,text,text)', 'execute') then
    raise exception 'trade_read_or_write_missing';
  end if;
  if has_function_privilege('anon', 'public.review_ledger_trade_change_v1(uuid,text,jsonb)', 'execute')
    or has_function_privilege('anon', 'public.post_ledger_trade_change_v1(uuid,uuid,text,jsonb,uuid,bigint,text,text)', 'execute')
    or has_function_privilege('public', 'private.post_linked_return_core(uuid,uuid,jsonb,uuid,uuid,timestamptz,boolean,boolean)', 'execute') then
    raise exception 'anon_or_public_execute';
  end if;
end;
$privileges$;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'trade-a@example.test', false, now(), now()),
  ('e9e9e9e9-e9e9-49e9-89e9-e9e9e9e9e9e9', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'trade-b@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8', 'متجر تعديل', 'مالك التعديل', 'Africa/Cairo'),
  ('eaeaeaea-eaea-4aea-8aea-eaeaeaeaeaea', 'متجر آخر', 'مالك آخر', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', 'owner'),
  ('eaeaeaea-eaea-4aea-8aea-eaeaeaeaeaea', 'e9e9e9e9-e9e9-49e9-89e9-e9e9e9e9e9e9', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8', now() - interval '1 day', now() + interval '30 days'),
  ('eaeaeaea-eaea-4aea-8aea-eaeaeaeaeaea', now() - interval '1 day', now() + interval '30 days');

set local role anon;
do $anon$
declare
  v_error text;
begin
  v_error := pg_temp.catch($sql$select public.review_ledger_trade_change_v1('e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', 'delete', null)$sql$);
  if v_error not like 'permission denied%' then
    raise exception 'anon_review %', v_error;
  end if;
  v_error := pg_temp.catch($sql$select public.post_exchange_v1('e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', '{}'::jsonb)$sql$);
  if v_error not like 'permission denied%' then
    raise exception 'anon_exchange %', v_error;
  end if;
end;
$anon$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);

do $main$
declare
  v_shop uuid := 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"10000","tenders":[{"method":"cash","piastres":"10000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"عميل تجريبي","customer_phone":"","note":""}'::jsonb;
  v_card jsonb := '{"version":1,"kind":"sale","total_piastres":"10000","tenders":[{"method":"card","piastres":"10000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"عميل تجريبي","customer_phone":"","note":"تعديل طريقة الدفع"}'::jsonb;
  v_priced jsonb := '{"version":2,"kind":"sale","total_piastres":"10000","tenders":[{"method":"cash","piastres":"10000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"1","item_name":"خاتم","line_price_piastres":"8000"}],"description":"","customer_name":"","customer_phone":"","note":"","pricing":{"base_piastres":"8000","workmanship_piastres":"2000","other_charges_piastres":"0","other_charges_label":"","discount_piastres":"0"}}'::jsonb;
  v_partial jsonb := '{"version":1,"kind":"purchase","total_piastres":"10000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"3000","count":"1","item_name":"سوار","line_price_piastres":null}],"description":"","customer_name":"تاجر تجريبي","customer_phone":"","note":"","purchase_obligation_piastres":"6000"}'::jsonb;
  v_unpaid jsonb := '{"version":1,"kind":"purchase","total_piastres":"5000","tenders":[],"items":[{"category":"scrap","karat":22,"milligrams":"1000","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"تاجر كسر","customer_phone":"","note":"","purchase_obligation_piastres":"5000"}'::jsonb;
  v_topup jsonb := '{"version":1,"kind":"purchase","total_piastres":"20000","tenders":[{"method":"cash","piastres":"20000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"8000","count":"4","item_name":"رصيد","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_expense jsonb := '{"version":1,"kind":"expense","total_piastres":"500","tenders":[{"method":"cash","piastres":"500"}],"items":[],"description":"إيجار","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_sale_id uuid;
  v_edit_id uuid;
  v_priced_id uuid;
  v_partial_id uuid;
  v_unpaid_id uuid;
  v_keep_id uuid;
  v_follow_sale uuid;
  v_settle_id uuid;
  v_lot_purchase uuid;
  v_review jsonb;
  v_posted jsonb;
  v_state jsonb;
  v_before integer;
  v_after integer;
  v_error text;
  v_cash bigint;
  v_mg bigint;
  v_pieces bigint;
  v_feed jsonb;
  v_pending jsonb;
  v_operation jsonb;
  v_summary jsonb;
  v_status jsonb;
  v_note text;
  v_replacement uuid;
  v_customer jsonb;
  v_stats jsonb;
  v_debt jsonb;
  v_item jsonb;
  v_effects jsonb;
  v_commands integer;
  v_audits integer;
  v_outbox integer;
  v_changes integer;
  v_shop_b uuid := 'eaeaeaea-eaea-4aea-8aea-eaeaeaeaeaea';
  v_pair uuid;
  v_return_sale uuid;
  v_inject_sale uuid;
begin
  perform public.confirm_opening_balances(
    '11111111-1111-4111-8111-111111111111',
    '{"version":1,"cash":{"cash":"500000","card":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"20000","count":"4"}],"scrap":[{"karat":21,"milligrams":"5000"}]}'::jsonb
  );
  perform public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111112', v_topup);

  v_sale_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111113', v_sale) ->> 'operation_id')::uuid;
  insert into trade_ids (name, id) values ('sale', v_sale_id);
  select count(*) into v_commands from public.financial_command_requests where shop_id = v_shop;
  select count(*) into v_audits from public.financial_audit_events where shop_id = v_shop;
  select count(*) into v_outbox from public.financial_outbox where shop_id = v_shop;
  select count(*) into v_before from public.financial_operations where shop_id = v_shop;
  v_review := public.review_ledger_trade_change_v1(v_sale_id, 'delete', null);
  if (select count(*) from public.financial_command_requests where shop_id = v_shop) <> v_commands
    or (select count(*) from public.financial_audit_events where shop_id = v_shop) <> v_audits
    or (select count(*) from public.financial_outbox where shop_id = v_shop) <> v_outbox
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_before
    or (select count(*) from public.ledger_trade_changes where shop_id = v_shop) <> 0 then
    raise exception 'review_wrote';
  end if;
  v_effects := v_review -> 'effects';
  if v_review ->> 'version' <> '1'
    or v_review ->> 'action' <> 'delete'
    or (v_review ->> 'operation_id')::uuid <> v_sale_id
    or v_review ->> 'source_sha256' !~ '^[0-9a-f]{64}$'
    or v_review ->> 'review_token' !~ '^[0-9a-f]{64}$'
    or v_review -> 'source' ->> 'kind' <> 'sale'
    or (v_review -> 'source' -> 'payload') <> v_sale
    or v_effects -> 'cash' <> '[{"method":"cash","delta_piastres":"-10000"}]'::jsonb
    or v_effects -> 'stock' <> '[{"category":"worked_jewelry","karat":21,"delta_milligrams":"2000","delta_count":"1"}]'::jsonb
    or v_effects -> 'scrap' <> '[]'::jsonb
    or v_effects ->> 'payable_delta_piastres' <> '0' then
    raise exception 'delete_sale_effects %', v_review;
  end if;
  raise notice 'DELETE_SALE_EFFECTS %', v_effects;
  v_state := public.get_daily_ledger_day_state();
  v_posted := public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111114', v_sale_id, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  if v_posted ->> 'ok' <> 'true' or v_posted ->> 'replayed' <> 'false'
    or v_posted ? 'replacement_operation_id' then
    raise exception 'delete_post %', v_posted;
  end if;
  insert into trade_ids (name, id) values ('sale_reversal', (v_posted ->> 'operation_id')::uuid);
  if pg_temp.money_balance(v_shop, 'cash') <> 480000
    or pg_temp.money_balance(v_shop, 'card') <> 100000 then
    raise exception 'delete_sale_cash % %', pg_temp.money_balance(v_shop, 'cash'), pg_temp.money_balance(v_shop, 'card');
  end if;
  select metal.amount, coalesce(piece.amount, 0) into v_mg, v_pieces
  from public.ledger_account_balances as metal
  left join public.ledger_account_balances as piece
    on piece.shop_id = metal.shop_id and piece.account_kind = 'saleable_count'
   and piece.category_code = metal.category_code and piece.karat = metal.karat
  where metal.shop_id = v_shop and metal.account_kind = 'saleable_metal'
    and metal.category_code = 'worked_jewelry' and metal.karat = 21;
  if v_mg <> 28000 or v_pieces <> 8 then
    raise exception 'delete_sale_stock % %', v_mg, v_pieces;
  end if;
  v_status := public.get_opening_status('11111111-1111-4111-8111-111111111114');
  if v_status ->> 'status' <> 'completed'
    or (v_status ->> 'operation_id')::uuid <> (v_posted ->> 'operation_id')::uuid then
    raise exception 'delete_status %', v_status;
  end if;
  if (public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111114', v_sale_id, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  ) ->> 'replayed') <> 'true' then
    raise exception 'delete_replay_failed';
  end if;
  v_error := pg_temp.catch($sql$select public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111114', '11111111-1111-4111-8111-111111111113', 'delete', null,
    '11111111-1111-4111-8111-111111111111', 1, repeat('a', 64), repeat('b', 64))$sql$);
  if v_error <> 'payload_mismatch' then
    raise exception 'mismatch %', v_error;
  end if;
  v_operation := public.get_daily_ledger_operation(v_sale_id);
  if v_operation -> 'payload' <> v_sale
    or v_operation -> 'trade_change' <> '{"action":"delete"}'::jsonb then
    raise exception 'source_audit %', v_operation -> 'trade_change';
  end if;
  v_operation := public.get_daily_ledger_operation((v_posted ->> 'operation_id')::uuid);
  if v_operation -> 'trade_change' ->> 'role' <> 'reversal'
    or (v_operation -> 'trade_change' ->> 'source_operation_id')::uuid <> v_sale_id then
    raise exception 'reversal_meta %', v_operation -> 'trade_change';
  end if;
  if not exists (
    select 1 from public.financial_audit_events
    where shop_id = v_shop and operation_id = v_sale_id and action = 'sale_confirmed'
  ) or not exists (
    select 1 from public.financial_audit_events
    where shop_id = v_shop and operation_id = v_sale_id and action = 'trade_deleted'
  ) or not exists (
    select 1 from public.journal_postings where shop_id = v_shop and operation_id = v_sale_id
  ) then
    raise exception 'original_history_missing';
  end if;
  v_feed := public.get_daily_ledger_v2() -> 'feed';
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(v_feed) as item
    where (item.value ->> 'operation_id')::uuid in (v_sale_id, (v_posted ->> 'operation_id')::uuid)
  ) then
    raise exception 'deleted_visible_in_feed';
  end if;
  v_summary := public.get_daily_ledger_v2() -> 'day_summary';
  if v_summary ->> 'sale_count' <> '0' or v_summary ->> 'sale_piastres' <> '0' then
    raise exception 'deleted_still_in_summary %', v_summary;
  end if;
  v_summary := public.get_ledger_compensation_summary_v1();
  if v_summary ->> 'gross_sale_piastres' <> '0' or v_summary ->> 'sale_return_piastres' <> '0' then
    raise exception 'deleted_inflates_compensation %', v_summary;
  end if;
  v_pending := public.get_pending_invoice_sends(null);
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(v_pending -> 'items') as item
    where (item.value ->> 'operation_id')::uuid = v_sale_id
  ) then
    raise exception 'deleted_pending_invoice';
  end if;

  v_edit_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111115', v_sale) ->> 'operation_id')::uuid;
  v_review := public.review_ledger_trade_change_v1(v_edit_id, 'edit', v_card);
  v_effects := v_review -> 'effects';
  if v_effects -> 'cash' <> '[{"delta_piastres":"-10000","method":"cash"},{"delta_piastres":"10000","method":"card"}]'::jsonb
    and v_effects -> 'cash' <> '[{"method":"cash","delta_piastres":"-10000"},{"method":"card","delta_piastres":"10000"}]'::jsonb then
    raise exception 'edit_cash_effects %', v_effects;
  end if;
  if v_effects -> 'stock' <> '[]'::jsonb or v_effects -> 'scrap' <> '[]'::jsonb
    or v_effects ->> 'payable_delta_piastres' <> '0' then
    raise exception 'edit_stock_effects %', v_effects;
  end if;
  raise notice 'EDIT_CARD_EFFECTS %', v_effects;
  v_posted := public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111116', v_edit_id, 'edit', v_card,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  v_replacement := (v_posted ->> 'replacement_operation_id')::uuid;
  if v_posted ->> 'replayed' <> 'false' or v_replacement is null then
    raise exception 'edit_post %', v_posted;
  end if;
  if pg_temp.money_balance(v_shop, 'cash') <> 480000
    or pg_temp.money_balance(v_shop, 'card') <> 110000 then
    raise exception 'edit_balances % %', pg_temp.money_balance(v_shop, 'cash'), pg_temp.money_balance(v_shop, 'card');
  end if;
  v_feed := public.get_daily_ledger_v2() -> 'feed';
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(v_feed) as item
    where (item.value ->> 'operation_id')::uuid in (v_edit_id, (v_posted ->> 'operation_id')::uuid)
  ) or not exists (
    select 1 from pg_catalog.jsonb_array_elements(v_feed) as item
    where (item.value ->> 'operation_id')::uuid = v_replacement
  ) then
    raise exception 'edit_feed_mismatch';
  end if;
  v_summary := public.get_daily_ledger_v2() -> 'day_summary';
  if v_summary ->> 'sale_count' <> '1' or v_summary ->> 'sale_piastres' <> '10000' then
    raise exception 'edit_summary %', v_summary;
  end if;
  v_summary := public.get_ledger_compensation_summary_v1();
  if v_summary ->> 'gross_sale_piastres' <> '10000' or v_summary ->> 'sale_return_piastres' <> '0' then
    raise exception 'edit_compensation %', v_summary;
  end if;
  v_pending := public.get_pending_invoice_sends(null);
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(v_pending -> 'items') as item
    where (item.value ->> 'operation_id')::uuid = v_edit_id
  ) or not exists (
    select 1 from pg_catalog.jsonb_array_elements(v_pending -> 'items') as item
    where (item.value ->> 'operation_id')::uuid = v_replacement
  ) then
    raise exception 'edit_pending_mismatch';
  end if;
  v_operation := public.get_daily_ledger_operation(v_edit_id);
  if v_operation -> 'payload' <> v_sale
    or (v_operation -> 'trade_change' ->> 'replacement_operation_id')::uuid <> v_replacement
    or v_operation -> 'trade_change' ->> 'action' <> 'edit' then
    raise exception 'edit_source_meta %', v_operation -> 'trade_change';
  end if;
  if not exists (
    select 1 from public.financial_audit_events
    where shop_id = v_shop and operation_id = v_edit_id and action = 'trade_edited'
  ) then
    raise exception 'edit_audit_missing';
  end if;
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_edit_id
  ));
  if v_error <> 'trade_inactive' then
    raise exception 'inactive_review %', v_error;
  end if;
  v_error := pg_temp.catch(format(
    'select public.post_ledger_trade_change_v1(%L::uuid, %L::uuid, ''delete'', null, %L::uuid, %s, %L, %L)',
    '11111111-1111-4111-8111-111111111117', v_edit_id,
    v_review ->> 'expected_day_id', v_review ->> 'expected_day_version',
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  ));
  if v_error <> 'operation_replaced' then
    raise exception 'replaced_post %', v_error;
  end if;

  v_priced_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111118', v_priced) ->> 'operation_id')::uuid;
  v_note := v_priced || jsonb_build_object('note', 'تعديل ملاحظة');
  v_review := public.review_ledger_trade_change_v1(v_priced_id, 'edit', v_note::jsonb);
  if v_review -> 'effects' -> 'cash' <> '[]'::jsonb
    or v_review -> 'effects' -> 'stock' <> '[]'::jsonb
    or v_review -> 'effects' -> 'scrap' <> '[]'::jsonb
    or v_review -> 'effects' ->> 'payable_delta_piastres' <> '0' then
    raise exception 'note_effects %', v_review -> 'effects';
  end if;
  raise notice 'NOTE_EDIT_EFFECTS %', v_review -> 'effects';
  perform public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111119', v_priced_id, 'edit', v_note::jsonb,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );

  v_partial_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111120', v_partial) ->> 'operation_id')::uuid;
  v_review := public.review_ledger_trade_change_v1(v_partial_id, 'delete', null);
  v_effects := v_review -> 'effects';
  if v_effects -> 'cash' <> '[{"method":"cash","delta_piastres":"4000"}]'::jsonb
    or v_effects -> 'stock' <> '[{"category":"worked_jewelry","karat":18,"delta_milligrams":"-3000","delta_count":"-1"}]'::jsonb
    or v_effects ->> 'payable_delta_piastres' <> '-6000' then
    raise exception 'partial_effects %', v_effects;
  end if;
  raise notice 'DELETE_PARTIAL_PURCHASE_EFFECTS %', v_effects;
  perform public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111121', v_partial_id, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  v_debt := public.get_debt_list_v1('', 'open', 20, null);
  if exists (
    select 1 from pg_catalog.jsonb_array_elements(coalesce(v_debt -> 'items', '[]'::jsonb)) as item
    where item.value ->> 'source_id' = v_partial_id::text
      or item.value ->> 'debt_key' = 'purchase_cash_payable:' || v_partial_id::text
  ) then
    raise exception 'cancelled_payable_still_open %', v_debt;
  end if;
  v_debt := public.get_debt_list_v1('', 'all', 20, null);
  select item.value into v_item
  from pg_catalog.jsonb_array_elements(coalesce(v_debt -> 'items', '[]'::jsonb)) as item
  where item.value ->> 'source_id' = v_partial_id::text
    or item.value ->> 'debt_key' = 'purchase_cash_payable:' || v_partial_id::text;
  if v_item is null or v_item ->> 'display_status' <> 'settled'
    or v_item ->> 'cancelled_amount' not in ('6000', '6000.00')
    or v_item ->> 'remaining_amount' not in ('0', '0.00') then
    raise exception 'partial_debt_history %', coalesce(v_item, v_debt);
  end if;
  raise notice 'PARTIAL_DEBT_ITEM %', v_item;

  v_unpaid_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111122', v_unpaid) ->> 'operation_id')::uuid;
  v_review := public.review_ledger_trade_change_v1(v_unpaid_id, 'delete', null);
  v_effects := v_review -> 'effects';
  if v_effects -> 'cash' <> '[]'::jsonb
    or v_effects -> 'scrap' <> '[{"karat":22,"delta_milligrams":"-1000"}]'::jsonb
    or v_effects ->> 'payable_delta_piastres' <> '-5000' then
    raise exception 'unpaid_effects %', v_effects;
  end if;
  raise notice 'DELETE_UNPAID_PURCHASE_EFFECTS %', v_effects;
  perform public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111123', v_unpaid_id, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );

  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)',
    (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111124', v_expense) ->> 'operation_id')
  ));
  if v_error <> 'trade_not_editable' then
    raise exception 'expense_editable %', v_error;
  end if;

  v_keep_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111125', v_sale) ->> 'operation_id')::uuid;
  insert into trade_ids (name, id, body) values ('keep', v_keep_id, v_sale);
  v_review := public.review_ledger_trade_change_v1(v_keep_id, 'delete', null);
  insert into trade_ids (name, body) values ('stale_review', v_review);
  perform public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111126', v_expense);
  v_error := pg_temp.catch(format(
    'select public.post_ledger_trade_change_v1(%L::uuid, %L::uuid, ''delete'', null, %L::uuid, %s, %L, %L)',
    '11111111-1111-4111-8111-111111111127', v_keep_id,
    v_review ->> 'expected_day_id', v_review ->> 'expected_day_version',
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  ));
  if v_error <> 'stale_trade_review' then
    raise exception 'stale %', v_error;
  end if;
  if exists (select 1 from public.ledger_trade_changes where source_operation_id = v_keep_id) then
    raise exception 'stale_wrote';
  end if;

  v_follow_sale := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111128', v_sale) ->> 'operation_id')::uuid;
  insert into trade_ids (name, id, body) values ('follow_sale', v_follow_sale, v_sale);
  v_settle_id := (public.post_daily_ledger_trade('11111111-1111-4111-8111-111111111129', v_partial) ->> 'operation_id')::uuid;
  insert into trade_ids (name, id) values ('settle', v_settle_id);
  v_lot_purchase := (public.post_daily_ledger_trade(
    '11111111-1111-4111-8111-111111111130',
    '{"version":1,"kind":"purchase","total_piastres":"8000","tenders":[{"method":"cash","piastres":"8000"}],"items":[{"category":"worked_jewelry","karat":22,"milligrams":"3000","count":"1","item_name":"قطعة","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  ) ->> 'operation_id')::uuid;
  insert into trade_ids (name, id) values ('lot_purchase', v_lot_purchase);
  perform public.post_daily_ledger_trade(
    '11111111-1111-4111-8111-111111111131',
    '{"version":1,"kind":"sale","total_piastres":"8000","tenders":[{"method":"card","piastres":"8000"}],"items":[{"category":"worked_jewelry","karat":22,"milligrams":"3000","count":"1","item_name":"قطعة","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_lot_purchase
  ));
  if v_error <> 'trade_has_followups' then
    raise exception 'lot_followup %', v_error;
  end if;

  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''edit'', %L::jsonb)',
    v_follow_sale,
    (v_sale || jsonb_build_object(
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'worked_jewelry', 'karat', 21, 'milligrams', '30000', 'count', '4',
        'item_name', 'خاتم', 'line_price_piastres', null
      )),
      'total_piastres', '10000'
    ))::text
  ));
  if v_error <> 'negative_owned_balance' then
    raise exception 'insufficient_stock %', v_error;
  end if;

  v_review := public.review_ledger_trade_change_v1(
    v_follow_sale, 'edit',
    v_sale || jsonb_build_object(
      'tenders', jsonb_build_array(jsonb_build_object('method', 'wallet', 'piastres', '10000'))
    )
  );
  if v_review -> 'effects' -> 'cash' <> jsonb_build_array(
    jsonb_build_object('method', 'cash', 'delta_piastres', '-10000'),
    jsonb_build_object('method', 'wallet', 'delta_piastres', '10000')
  ) then
    raise exception 'wallet_effects %', v_review -> 'effects';
  end if;

  v_customer := public.post_customer_create_v1(
    '11111111-1111-4111-8111-111111111133',
    '{"version":1,"kind":"customer_create","display_name":"عميل التعديل","phones":[],"is_vip":false,"has_open_request":false}'::jsonb
  );
  perform public.post_customer_link_v1(
    '11111111-1111-4111-8111-111111111134',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_link',
      'customer_id', v_customer ->> 'customer_id',
      'expected_version', v_customer ->> 'record_version',
      'operation_id', v_follow_sale
    )
  );
  v_state := public.get_daily_ledger_day_state();
  v_review := public.review_ledger_trade_change_v1(
    v_follow_sale, 'edit', v_sale || jsonb_build_object('note', 'ربط عميل')
  );
  v_posted := public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111135', v_follow_sale, 'edit',
    v_sale || jsonb_build_object('note', 'ربط عميل'),
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  v_replacement := (v_posted ->> 'replacement_operation_id')::uuid;
  v_stats := public.get_customer_v2((v_customer ->> 'customer_id')::uuid, 20, null, 20, null, 20, null) -> 'statistics';
  if v_stats ->> 'bought_count' <> '1' then
    raise exception 'customer_after_edit %', v_stats;
  end if;
  v_review := public.review_ledger_trade_change_v1(v_replacement, 'delete', null);
  perform public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111136', v_replacement, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  v_stats := public.get_customer_v2((v_customer ->> 'customer_id')::uuid, 20, null, 20, null, 20, null) -> 'statistics';
  if v_stats ->> 'bought_count' <> '0' then
    raise exception 'customer_after_delete %', v_stats;
  end if;
  raise notice 'CUSTOMER_BOUGHT_AFTER_DELETE %', v_stats ->> 'bought_count';

  v_cash := pg_temp.money_balance(v_shop, 'cash');
  v_error := pg_temp.catch(format(
    'select public.post_daily_ledger_trade(%L::uuid, %L::jsonb)',
    '11111111-1111-4111-8111-111111111132',
    jsonb_build_object(
      'version', 1, 'kind', 'expense', 'total_piastres', v_cash::text,
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', v_cash::text)),
      'items', '[]'::jsonb, 'description', 'تصفير', 'customer_name', '',
      'customer_phone', '', 'note', ''
    )
  ));
  if v_error <> 'ok' then raise exception 'drain_cash %', v_error; end if;
  v_commands := (select count(*) from public.ledger_trade_changes where shop_id = v_shop);
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_keep_id
  ));
  if v_error <> 'negative_owned_balance' then
    raise exception 'insufficient_cash %', v_error;
  end if;
  if (select count(*) from public.ledger_trade_changes where shop_id = v_shop) <> v_commands then
    raise exception 'insufficient_cash_wrote';
  end if;

  if public.confirm_invoice_whatsapp_send(v_keep_id, '11111111-1111-4111-8111-111111111137') ->> 'ok' <> 'true' then
    raise exception 'active_invoice_send_failed';
  end if;
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_keep_id
  ));
  if v_error <> 'trade_has_followups' then
    raise exception 'invoice_followup %', v_error;
  end if;
  v_error := pg_temp.catch(format(
    'select public.get_invoice_brand_source_v1(%L::uuid)', v_sale_id
  ));
  if v_error <> 'trade_inactive' then
    raise exception 'brand_source %', v_error;
  end if;
  v_error := pg_temp.catch(format(
    'select public.get_invoice_message_source_v1(%L::uuid)', v_sale_id
  ));
  if v_error <> 'trade_inactive' then
    raise exception 'message_source %', v_error;
  end if;
  v_error := pg_temp.catch(format(
    'select public.confirm_invoice_whatsapp_send(%L::uuid, %L::uuid)',
    v_sale_id, '11111111-1111-4111-8111-111111111138'
  ));
  if v_error <> 'trade_inactive' then
    raise exception 'inactive_send %', v_error;
  end if;
  v_operation := public.get_invoice_dispatch_state(v_sale_id);
  if v_operation ->> 'sendable' <> 'false' or v_operation -> 'trade_change' ->> 'action' <> 'delete' then
    raise exception 'dispatch_state %', v_operation;
  end if;
  v_error := pg_temp.catch(format(
    'select public.get_invoice_presentations_v1(%L::uuid)', v_sale_id
  ));
  if v_error = 'trade_inactive' then
    raise exception 'presentations_blocked';
  end if;
  if pg_catalog.to_regprocedure('public.get_invoice_presentation_v1(uuid,bigint)') is not null then
    v_error := pg_temp.catch(format(
      'select public.get_invoice_presentation_v1(%L::uuid, 1)', v_sale_id
    ));
    if v_error = 'trade_inactive' then raise exception 'presentation_blocked'; end if;
  end if;

  if public.settle_purchase_cash_payable(
    '11111111-1111-4111-8111-111111111170',
    v_settle_id,
    '[{"method":"card","piastres":"1000"}]'::jsonb
  ) ->> 'ok' <> 'true' then
    raise exception 'settlement_failed';
  end if;
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_settle_id
  ));
  if v_error <> 'trade_has_followups' then
    raise exception 'settlement_followup %', v_error;
  end if;

  select change.replacement_operation_id into v_pair
  from public.ledger_trade_changes as change
  where change.source_operation_id = v_priced_id;
  select metal.amount, coalesce(piece.amount, 0) into v_mg, v_pieces
  from public.ledger_account_balances as metal
  left join public.ledger_account_balances as piece
    on piece.shop_id = metal.shop_id and piece.account_kind = 'saleable_count'
   and piece.category_code = metal.category_code and piece.karat = metal.karat
  where metal.shop_id = v_shop and metal.account_kind = 'saleable_metal'
    and metal.category_code = 'worked_jewelry' and metal.karat = 21;
  if v_mg < 1 or v_pieces < 1 then
    raise exception 'pair_fixture_stock % %', v_mg, v_pieces;
  end if;
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''edit'', %L::jsonb)',
    v_pair,
    jsonb_build_object(
      'version', 1, 'kind', 'sale', 'total_piastres', '10000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '10000')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'worked_jewelry', 'karat', 21,
        'milligrams', (v_mg + 2000)::text, 'count', v_pieces::text,
        'item_name', 'خاتم', 'line_price_piastres', null
      )),
      'description', '', 'customer_name', '', 'customer_phone', '', 'note', 'كسر الزوج'
    )::text
  ));
  if v_error <> 'stock_pair_mismatch' then
    raise exception 'stock_pair %', v_error;
  end if;

  v_error := pg_temp.catch($sql$select public.post_linked_return_v1('11111111-1111-4111-8111-111111111171', '{}'::jsonb)$sql$);
  if v_error not like 'permission denied%' then
    raise exception 'authenticated_return %', v_error;
  end if;
  v_error := pg_temp.catch($sql$select public.post_exchange_v1('11111111-1111-4111-8111-111111111172', '{}'::jsonb)$sql$);
  if v_error not like 'permission denied%' then
    raise exception 'authenticated_exchange %', v_error;
  end if;
  v_error := pg_temp.catch($sql$select public.post_daily_ledger_return('11111111-1111-4111-8111-111111111173', '11111111-1111-4111-8111-111111111174', 'مرتجع')$sql$);
  if v_error not like 'permission denied%' then
    raise exception 'authenticated_legacy_return %', v_error;
  end if;
  v_error := pg_temp.catch($sql$select private.post_linked_return_core(
    'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8',
    '11111111-1111-4111-8111-111111111175',
    '{}'::jsonb,
    'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8',
    'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7',
    now(), false, false)$sql$);
  if v_error not like 'permission denied%' then
    raise exception 'authenticated_core %', v_error;
  end if;

  v_return_sale := (public.post_daily_ledger_trade(
    '11111111-1111-4111-8111-111111111176',
    v_sale || jsonb_build_object('note', 'بيع يرتجع لاحقا')
  ) ->> 'operation_id')::uuid;
  v_inject_sale := (public.post_daily_ledger_trade(
    '11111111-1111-4111-8111-111111111177',
    v_sale || jsonb_build_object('note', 'بيع يفشل استبداله')
  ) ->> 'operation_id')::uuid;
  insert into trade_ids (name, id, body) values
    ('return_sale', v_return_sale, v_sale || jsonb_build_object('note', 'بيع يرتجع لاحقا')),
    ('inject_sale', v_inject_sale, v_sale || jsonb_build_object('note', 'بيع يفشل استبداله'));

  perform set_config('request.jwt.claim.sub', 'e9e9e9e9-e9e9-49e9-89e9-e9e9e9e9e9e9', true);
  perform public.confirm_opening_balances(
    '11111111-1111-4111-8111-111111111160',
    '{"version":1,"cash":{"cash":"8000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"2"}],"scrap":[]}'::jsonb
  );
  v_sale_id := (public.post_daily_ledger_trade(
    '11111111-1111-4111-8111-111111111161', v_sale
  ) ->> 'operation_id')::uuid;
  perform public.post_daily_ledger_trade(
    '11111111-1111-4111-8111-111111111162',
    '{"version":1,"kind":"expense","total_piastres":"10000","tenders":[{"method":"cash","piastres":"10000"}],"items":[],"description":"صرف جزئي","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  if pg_temp.money_balance(v_shop_b, 'cash') <> 8000 then
    raise exception 'net_setup_cash %', pg_temp.money_balance(v_shop_b, 'cash');
  end if;
  v_card := v_sale || jsonb_build_object(
    'total_piastres', '4000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '4000')),
    'note', 'تحصيل أقل'
  );
  v_review := public.review_ledger_trade_change_v1(v_sale_id, 'edit', v_card);
  if v_review -> 'effects' -> 'cash' <> '[{"method":"cash","delta_piastres":"-6000"}]'::jsonb
    and v_review -> 'effects' -> 'cash' <> '[{"delta_piastres":"-6000","method":"cash"}]'::jsonb then
    raise exception 'net_refund_effects %', v_review -> 'effects';
  end if;
  v_posted := public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111163', v_sale_id, 'edit', v_card,
    (v_review ->> 'expected_day_id')::uuid, (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  if v_posted ->> 'ok' <> 'true' or pg_temp.money_balance(v_shop_b, 'cash') <> 2000 then
    raise exception 'net_refund_post % cash %', v_posted, pg_temp.money_balance(v_shop_b, 'cash');
  end if;
  raise notice 'NET_REFUND_CASH %', pg_temp.money_balance(v_shop_b, 'cash');
  perform set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
end;
$main$;

set constraints journal_postings_nonnegative_trg immediate;
set constraints journal_postings_nonnegative_trg deferred;

reset role;

-- Opening creates a zero wallet account, so collecting into it is valid.
-- invalid_input applies only when that cash_method row is absent.
do $missing_wallet$
declare
  v_shop uuid := 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
  v_sale uuid;
  v_body jsonb;
  v_error text;
begin
  select id, body into v_sale, v_body from trade_ids where name = 'return_sale';
  begin
    delete from public.ledger_accounts as account
    where account.shop_id = v_shop
      and account.account_kind = 'cash_method'
      and account.method_code = 'wallet'
      and not exists (
        select 1 from public.journal_postings as posting
        where posting.shop_id = account.shop_id and posting.account_id = account.id
      );
    if not found then
      raise exception 'wallet_account_had_postings';
    end if;
    set local role authenticated;
    v_error := pg_temp.catch(format(
      'select public.review_ledger_trade_change_v1(%L::uuid, ''edit'', %L::jsonb)',
      v_sale,
      (v_body || jsonb_build_object(
        'tenders', jsonb_build_array(jsonb_build_object('method', 'wallet', 'piastres', '10000'))
      ))::text
    ));
    if v_error <> 'invalid_input' then
      raise exception 'missing_wallet %', v_error;
    end if;
    raise exception 'missing_wallet_rollback';
  exception
    when others then
      if sqlerrm is distinct from 'missing_wallet_rollback' then
        raise;
      end if;
  end;
end;
$missing_wallet$;
do $return_core$
declare
  v_shop uuid := 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
  v_sale uuid;
  v_day uuid;
  v_body jsonb;
  v_payload jsonb;
  v_result jsonb;
begin
  select id, body into v_sale, v_body from trade_ids where name = 'return_sale';
  select operation.business_day_id into v_day
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = v_sale;
  v_payload := jsonb_build_object(
    'version', 1,
    'kind', 'sale_return',
    'original_operation_id', v_sale,
    'note', 'مرتجع متابعة',
    'items', jsonb_build_array(jsonb_build_object(
      'item_index', '0', 'milligrams', '2000', 'count', '1'
    )),
    'consideration_piastres', '10000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '10000'))
  );
  if pg_catalog.current_setting('eldaftar.trade_change_net', true) = 'on' then
    raise exception 'return_core_saw_net_guc';
  end if;
  v_result := private.post_linked_return_core(
    v_shop,
    '11111111-1111-4111-8111-111111111178',
    v_payload,
    v_day,
    'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7',
    pg_catalog.clock_timestamp(),
    false,
    false
  );
  if v_result ->> 'operation_id' is null then
    raise exception 'return_core_failed %', v_result;
  end if;
  raise notice 'RETURN_CORE_OPERATION %', v_result ->> 'operation_id';
end;
$return_core$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);
do $return_blocks$
declare
  v_sale uuid;
  v_error text;
begin
  select id into v_sale from trade_ids where name = 'return_sale';
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'trade_has_followups' then
    raise exception 'return_followup %', v_error;
  end if;
end;
$return_blocks$;

reset role;
create trigger trade_fail_replacement
  before insert on public.financial_operations
  for each row execute function pg_temp.fail_replacement();
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);
do $injected$
declare
  v_shop uuid := 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
  v_sale uuid;
  v_body jsonb;
  v_review jsonb;
  v_error text;
  v_cash bigint;
  v_changes integer;
  v_operations integer;
begin
  select id, body into v_sale, v_body from trade_ids where name = 'inject_sale';
  v_review := public.review_ledger_trade_change_v1(
    v_sale, 'edit', v_body || jsonb_build_object('note', 'لن يُحفظ')
  );
  v_cash := pg_temp.money_balance(v_shop, 'cash');
  select count(*) into v_changes from public.ledger_trade_changes where shop_id = v_shop;
  select count(*) into v_operations from public.financial_operations where shop_id = v_shop;
  perform set_config('eldaftar.fail_trade_replacement', 'on', true);
  v_error := pg_temp.catch(format(
    'select public.post_ledger_trade_change_v1(%L::uuid, %L::uuid, ''edit'', %L::jsonb, %L::uuid, %s, %L, %L)',
    '11111111-1111-4111-8111-111111111179', v_sale,
    (v_body || jsonb_build_object('note', 'لن يُحفظ'))::text,
    v_review ->> 'expected_day_id', v_review ->> 'expected_day_version',
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  ));
  perform set_config('eldaftar.fail_trade_replacement', 'off', true);
  if v_error <> 'injected_rollback' then
    raise exception 'injected %', v_error;
  end if;
  if pg_temp.money_balance(v_shop, 'cash') <> v_cash
    or (select count(*) from public.ledger_trade_changes where shop_id = v_shop) <> v_changes
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_operations
    or exists (select 1 from public.ledger_trade_changes where source_operation_id = v_sale) then
    raise exception 'injected_wrote';
  end if;
  raise notice 'INJECTED_ROLLBACK_KEPT_CASH %', v_cash;
end;
$injected$;

reset role;
drop trigger trade_fail_replacement on public.financial_operations;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);
do $closed$
declare
  v_state jsonb;
  v_closed jsonb;
  v_sale uuid;
  v_error text;
begin
  select id into v_sale from trade_ids where name = 'inject_sale';
  v_state := public.get_daily_ledger_day_state();
  v_closed := public.close_daily_ledger_day(
    '11111111-1111-4111-8111-111111111180',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    v_state -> 'counts'
  );
  if v_closed ->> 'ok' <> 'true' then
    raise exception 'close_failed %', v_closed;
  end if;
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'day_closed' then
    raise exception 'closed_review %', v_error;
  end if;
  perform public.open_daily_ledger_day('11111111-1111-4111-8111-111111111181');
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'trade_not_editable' then
    raise exception 'previous_day %', v_error;
  end if;
end;
$closed$;

reset role;
update public.shop_entitlements
set expires_at = now() - interval '1 minute'
where shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);
do $expired$
declare
  v_command jsonb;
  v_posted jsonb;
  v_error text;
  v_sale uuid;
begin
  select request.payload_canonical into v_command
  from public.financial_command_requests as request
  where request.shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8'
    and request.idempotency_key = '11111111-1111-4111-8111-111111111114';
  v_posted := public.post_ledger_trade_change_v1(
    '11111111-1111-4111-8111-111111111114',
    (v_command ->> 'operation_id')::uuid,
    v_command ->> 'action',
    v_command -> 'replacement',
    (v_command ->> 'expected_day_id')::uuid,
    (v_command ->> 'expected_day_version')::bigint,
    v_command ->> 'source_sha256',
    v_command ->> 'review_token'
  );
  if v_posted ->> 'replayed' <> 'true' then
    raise exception 'expired_replay %', v_posted;
  end if;
  select id into v_sale from trade_ids where name = 'inject_sale';
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'shop_not_active' then
    raise exception 'expired_review %', v_error;
  end if;
end;
$expired$;

reset role;
update public.shop_entitlements
set expires_at = now() + interval '30 days'
where shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
update public.shop_memberships
set revoked_at = now()
where shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8'
  and user_id = 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);
do $revoked$
declare
  v_error text;
  v_sale uuid;
begin
  select id into v_sale from trade_ids where name = 'inject_sale';
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'forbidden' then
    raise exception 'revoked %', v_error;
  end if;
end;
$revoked$;

reset role;
update public.shop_memberships
set revoked_at = null
where shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8'
  and user_id = 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '11111111-1111-4111-8111-111111111199', true);
do $session$
declare
  v_error text;
  v_sale uuid;
begin
  select id into v_sale from trade_ids where name = 'inject_sale';
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'session_expired' then
    raise exception 'session %', v_error;
  end if;
end;
$session$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e9e9e9e9-e9e9-49e9-89e9-e9e9e9e9e9e9', true);
select set_config('request.jwt.claim.session_id', '', true);
do $other$
declare
  v_sale uuid;
  v_error text;
  v_visible integer;
begin
  select id into v_sale from trade_ids where name = 'sale';
  v_error := pg_temp.catch(format(
    'select public.review_ledger_trade_change_v1(%L::uuid, ''delete'', null)', v_sale
  ));
  if v_error <> 'not_found' then
    raise exception 'wrong_owner %', v_error;
  end if;
  select count(*) into v_visible
  from public.ledger_trade_changes
  where shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
  if v_visible <> 0 then
    raise exception 'cross_shop_visible %', v_visible;
  end if;
end;
$other$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7', true);
select set_config('request.jwt.claim.session_id', '', true);
do $rls$
declare
  v_error text;
  v_visible integer;
begin
  v_error := pg_temp.catch($sql$
    insert into public.ledger_trade_changes (
      shop_id, source_operation_id, action, reversal_operation_id,
      actor_user_id, created_at, source_sha256, review_token, command_key
    ) values (
      'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8',
      '11111111-1111-4111-8111-111111111190',
      'delete',
      '11111111-1111-4111-8111-111111111191',
      'e7e7e7e7-e7e7-47e7-87e7-e7e7e7e7e7e7',
      now(), repeat('a', 64), repeat('b', 64),
      '11111111-1111-4111-8111-111111111192'
    )
  $sql$);
  if v_error not like 'permission denied%' then
    raise exception 'client_insert %', v_error;
  end if;
  select count(*) into v_visible
  from public.ledger_trade_changes
  where shop_id = 'e8e8e8e8-e8e8-48e8-88e8-e8e8e8e8e8e8';
  if v_visible < 1 then
    raise exception 'owner_cannot_read_history';
  end if;
  raise notice 'TRADE_CHANGE_ROWS %', v_visible;
end;
$rls$;

rollback;
do $passed$
begin
  raise notice 'TRADE_CHANGE_SQL_PASSED';
end;
$passed$;

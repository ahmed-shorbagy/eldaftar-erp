-- Convert shop-owned scrap into saleable stock at the same karat and exact weight.
begin;

alter table public.financial_operations drop constraint financial_operations_kind_check;
alter table public.financial_operations add constraint financial_operations_kind_check
  check (kind in ('opening_balances', 'sale', 'purchase', 'expense',
    'close_day', 'open_day', 'purchase_settlement', 'cash_transfer',
    'scrap_sale', 'scrap_to_stock'));
alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled',
    'invoice_send_confirmed', 'cash_transfer_confirmed',
    'scrap_sale_confirmed', 'scrap_to_stock_confirmed'));
alter table public.financial_outbox drop constraint financial_outbox_event_check;
alter table public.financial_outbox add constraint financial_outbox_event_check
  check (event_type in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled',
    'cash_transfer_confirmed', 'scrap_sale_confirmed',
    'scrap_to_stock_confirmed'));

create function public.post_daily_ledger_scrap_to_stock(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_request public.financial_command_requests%rowtype;
  v_hash bytea;
  v_day uuid;
  v_day_version bigint;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_actor uuid;
  v_at timestamptz;
  v_sequence bigint;
  v_operation uuid;
  v_source uuid;
  v_destination uuid;
  v_gold_clear uuid;
  v_count_account uuid;
  v_count_clear uuid;
  v_journal uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_payload is null
    or jsonb_typeof(p_payload) <> 'object' then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key for update;
  if found then
    if v_request.payload_canonical = p_payload
      and v_request.payload_sha256 = v_hash then
      return jsonb_build_object('ok', true,
        'operation_id', v_request.operation_id, 'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if p_payload -> 'version' is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'scrap_to_stock'
    or not (p_payload ?& array[
      'version', 'kind', 'category', 'karat', 'milligrams',
      'count', 'item_name', 'note'
    ])
    or p_payload - 'version' - 'kind' - 'category' - 'karat'
      - 'milligrams' - 'count' - 'item_name' - 'note' <> '{}'::jsonb
    or jsonb_typeof(p_payload -> 'category') <> 'string'
    or jsonb_typeof(p_payload -> 'karat') <> 'number'
    or jsonb_typeof(p_payload -> 'milligrams') <> 'string'
    or jsonb_typeof(p_payload -> 'count') <> 'string'
    or jsonb_typeof(p_payload -> 'item_name') <> 'string'
    or jsonb_typeof(p_payload -> 'note') <> 'string'
    or nullif(btrim(p_payload ->> 'item_name'), '') is null
    or length(p_payload ->> 'item_name') > 120
    or length(p_payload ->> 'note') > 1000 then
    raise exception 'invalid_input';
  end if;
  v_category := p_payload ->> 'category';
  v_karat := (p_payload ->> 'karat')::smallint;
  if v_category not in ('worked_jewelry', 'bullion', 'coin')
    or not private.opening_pair_allowed(v_category, v_karat)
    or not private.opening_pair_allowed('scrap', v_karat) then
    raise exception 'invalid_input';
  end if;
  v_mg := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'milligrams'));
  v_count := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'count'));
  if v_mg <= 0 or v_count <= 0 then raise exception 'invalid_input'; end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  v_source := private.financial_account(v_shop, 'scrap_metal', 'gold_mg',
    'scrap', v_karat, null, false);
  if v_source is null then raise exception 'insufficient_stock'; end if;
  v_destination := private.financial_account(v_shop, 'saleable_metal', 'gold_mg',
    v_category, v_karat, null, true);
  v_gold_clear := private.financial_account(v_shop, 'movement_gold_clearing',
    'gold_mg', null, v_karat, null, true);
  v_count_account := private.financial_account(v_shop, 'saleable_count', 'count',
    v_category, v_karat, null, true);
  v_count_clear := private.financial_account(v_shop, 'movement_count_clearing',
    'count', v_category, v_karat, null, true);
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, 'scrap_to_stock', v_day, v_actor, v_at)
  returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_operation, v_shop, p_payload, v_at);
  insert into public.journals (
    shop_id, operation_id, unit_kind, karat, bucket_key
  ) values (v_shop, v_operation, 'gold_mg', v_karat,
    'gold:scrap:' || v_karat::text) returning id into v_journal;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values
    (v_shop, v_journal, v_source, v_operation, -v_mg),
    (v_shop, v_journal, v_gold_clear, v_operation, v_mg);
  insert into public.journals (
    shop_id, operation_id, unit_kind, karat, bucket_key
  ) values (v_shop, v_operation, 'gold_mg', v_karat,
    'gold:' || v_category || ':' || v_karat::text) returning id into v_journal;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values
    (v_shop, v_journal, v_destination, v_operation, v_mg),
    (v_shop, v_journal, v_gold_clear, v_operation, -v_mg);
  insert into public.journals (
    shop_id, operation_id, unit_kind, karat, bucket_key
  ) values (v_shop, v_operation, 'count', v_karat,
    'count:' || v_category || ':' || v_karat::text) returning id into v_journal;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values
    (v_shop, v_journal, v_count_account, v_operation, v_count),
    (v_shop, v_journal, v_count_clear, v_operation, -v_count);
  update public.business_days set day_version = day_version + 1 where id = v_day;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, 'scrap_to_stock_confirmed', v_operation, v_at,
    jsonb_build_object('business_day_id', v_day, 'operation_id', v_operation));
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_operation, 'scrap_to_stock_confirmed', v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, p_payload, v_hash, v_operation, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_operation,
    'business_day_id', v_day, 'day_version', v_day_version + 1,
    'replayed', false);
end;
$fn$;

revoke all on function public.post_daily_ledger_scrap_to_stock(uuid, jsonb)
  from public, anon;
grant execute on function public.post_daily_ledger_scrap_to_stock(uuid, jsonb)
  to authenticated;

alter function public.get_daily_ledger_v2()
  rename to get_daily_ledger_v2_before_scrap_to_stock;
revoke all on function public.get_daily_ledger_v2_before_scrap_to_stock()
  from public, anon, authenticated;
create function public.get_daily_ledger_v2()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_result jsonb; v_feed jsonb;
begin
  v_result := public.get_daily_ledger_v2_before_scrap_to_stock();
  if v_result ->> 'state' <> 'confirmed' then return v_result; end if;
  select coalesce(jsonb_agg(
    case when item.value ->> 'kind' = 'scrap_to_stock'
      then jsonb_set(item.value, '{label_ar}', '"تحويل كسر إلى مخزون"'::jsonb)
      else item.value end
    order by item.ordinality
  ), '[]'::jsonb) into v_feed
  from jsonb_array_elements(v_result -> 'feed') with ordinality as item(value, ordinality);
  return jsonb_set(v_result, '{feed}', v_feed);
end;
$fn$;
revoke all on function public.get_daily_ledger_v2() from public, anon;
grant execute on function public.get_daily_ledger_v2() to authenticated;

commit;

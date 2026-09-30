-- Owner-only settlement of a cash-denominated purchase balance.
begin;

alter table public.financial_operations drop constraint financial_operations_kind_check;
alter table public.financial_operations add constraint financial_operations_kind_check
  check (kind in ('opening_balances', 'sale', 'purchase', 'expense',
    'close_day', 'open_day', 'purchase_settlement'));
alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'invoice_send_confirmed', 'purchase_settled'));
alter table public.financial_outbox drop constraint financial_outbox_event_check;
alter table public.financial_outbox add constraint financial_outbox_event_check
  check (event_type in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled'));

create function public.settle_purchase_cash_payable(
  p_idempotency_key uuid, p_purchase_operation_id uuid, p_tenders jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_day uuid;
  v_day_version bigint;
  v_payable public.purchase_cash_payables%rowtype;
  v_request public.financial_command_requests%rowtype;
  v_payload jsonb;
  v_hash bytea;
  v_seen text[] := '{}';
  v_tender jsonb;
  v_method text;
  v_amount bigint;
  v_sum numeric := 0;
  v_at timestamptz;
  v_actor uuid;
  v_sequence bigint;
  v_op uuid;
  v_journal uuid;
  v_account uuid;
  v_clear uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_purchase_operation_id is null
    or jsonb_typeof(p_tenders) is distinct from 'array'
    or jsonb_array_length(p_tenders) not between 1 and 4 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_payload := jsonb_build_object('version', 1, 'kind', 'purchase_settlement',
    'purchase_operation_id', p_purchase_operation_id, 'tenders', p_tenders);
  v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = v_payload and v_request.payload_sha256 = v_hash then
      return jsonb_build_object('ok', true, 'operation_id', v_request.operation_id,
        'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select payable.* into v_payable from public.purchase_cash_payables as payable
  where payable.shop_id = v_shop
    and payable.operation_id = p_purchase_operation_id for update;
  if v_payable.operation_id is null then raise exception 'not_found'; end if;
  if v_payable.remaining_piastres = 0 then raise exception 'already_settled'; end if;
  for v_tender in select value from jsonb_array_elements(p_tenders) as t(value)
  loop
    if jsonb_typeof(v_tender) is distinct from 'object'
      or not (v_tender ?& array['method', 'piastres'])
      or v_tender - 'method' - 'piastres' <> '{}'::jsonb
      or jsonb_typeof(v_tender -> 'method') is distinct from 'string'
      or jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any(v_seen) then raise exception 'invalid_input'; end if;
    v_seen := array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_amount <= 0 then raise exception 'invalid_input'; end if;
    v_sum := v_sum + v_amount;
  end loop;
  if v_sum > v_payable.remaining_piastres then
    raise exception 'settlement_exceeds_obligation';
  end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  v_at := pg_catalog.clock_timestamp();
  v_actor := auth.uid();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, 'purchase_settlement', v_day, v_actor, v_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, v_shop, v_payload, v_at);
  update public.purchase_cash_payables
  set remaining_piastres = remaining_piastres - v_sum::bigint, updated_at = v_at
  where shop_id = v_shop and operation_id = p_purchase_operation_id;
  update public.business_days set day_version = day_version + 1 where id = v_day;
  v_clear := private.financial_account(v_shop, 'movement_money_clearing',
    'money', null, null, null, true);
  insert into public.journals (
    shop_id, operation_id, unit_kind, currency_code, bucket_key
  ) values (v_shop, v_op, 'money', 'EGP', 'money') returning id into v_journal;
  for v_tender in select value from jsonb_array_elements(p_tenders) as t(value)
  loop
    v_account := private.financial_account(v_shop, 'cash_method', 'money',
      null, null, v_tender ->> 'method', false);
    if v_account is null then raise exception 'invalid_input'; end if;
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values (v_shop, v_journal, v_account, v_op, -v_amount);
  end loop;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values (v_shop, v_journal, v_clear, v_op, v_sum::bigint);
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, 'purchase_settled', v_op, v_at,
    jsonb_build_object('purchase_operation_id', p_purchase_operation_id,
      'paid_piastres', v_sum::text,
      'remaining_piastres', (v_payable.remaining_piastres - v_sum)::text));
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_op, 'purchase_settled', v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, v_payload, v_hash, v_op, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_op,
    'remaining_piastres', (v_payable.remaining_piastres - v_sum)::text,
    'day_version', v_day_version + 1, 'replayed', false);
end;
$fn$;

revoke all on function public.settle_purchase_cash_payable(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.settle_purchase_cash_payable(uuid, uuid, jsonb)
  to authenticated;

commit;

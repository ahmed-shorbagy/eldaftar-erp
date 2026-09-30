-- Owner-only cash transfer between existing payment methods.
begin;

alter table public.financial_operations drop constraint financial_operations_kind_check;
alter table public.financial_operations add constraint financial_operations_kind_check
  check (kind in ('opening_balances', 'sale', 'purchase', 'expense',
    'close_day', 'open_day', 'purchase_settlement', 'cash_transfer'));
alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled',
    'invoice_send_confirmed', 'cash_transfer_confirmed'));
alter table public.financial_outbox drop constraint financial_outbox_event_check;
alter table public.financial_outbox add constraint financial_outbox_event_check
  check (event_type in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled',
    'cash_transfer_confirmed'));

create function public.post_daily_ledger_cash_transfer(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_request public.financial_command_requests%rowtype;
  v_hash bytea;
  v_from text;
  v_to text;
  v_amount bigint;
  v_from_account uuid;
  v_to_account uuid;
  v_day uuid;
  v_day_version bigint;
  v_at timestamptz;
  v_actor uuid;
  v_sequence bigint;
  v_operation uuid;
  v_journal uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_payload is null
    or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
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
    or p_payload ->> 'kind' is distinct from 'cash_transfer'
    or not (p_payload ?& array[
      'version', 'kind', 'from_method', 'to_method',
      'amount_piastres', 'note'
    ])
    or p_payload - 'version' - 'kind' - 'from_method'
      - 'to_method' - 'amount_piastres' - 'note' <> '{}'::jsonb
    or jsonb_typeof(p_payload -> 'from_method') <> 'string'
    or jsonb_typeof(p_payload -> 'to_method') <> 'string'
    or jsonb_typeof(p_payload -> 'amount_piastres') <> 'string'
    or jsonb_typeof(p_payload -> 'note') <> 'string'
    or length(p_payload ->> 'note') > 1000 then
    raise exception 'invalid_input';
  end if;
  v_from := p_payload ->> 'from_method';
  v_to := p_payload ->> 'to_method';
  if v_from not in ('cash', 'instant_transfer', 'wallet', 'card')
    or v_to not in ('cash', 'instant_transfer', 'wallet', 'card')
    or v_from = v_to then raise exception 'invalid_input'; end if;
  v_amount := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'amount_piastres'));
  if v_amount <= 0 then raise exception 'invalid_input'; end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  v_from_account := private.financial_account(v_shop, 'cash_method', 'money',
    null, null, v_from, false);
  v_to_account := private.financial_account(v_shop, 'cash_method', 'money',
    null, null, v_to, false);
  if v_from_account is null or v_to_account is null then
    raise exception 'invalid_input';
  end if;
  v_at := pg_catalog.clock_timestamp();
  v_actor := auth.uid();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, 'cash_transfer', v_day, v_actor, v_at)
  returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_operation, v_shop, p_payload, v_at);
  insert into public.journals (
    shop_id, operation_id, unit_kind, currency_code, bucket_key
  ) values (v_shop, v_operation, 'money', 'EGP', 'money') returning id into v_journal;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values
    (v_shop, v_journal, v_from_account, v_operation, -v_amount),
    (v_shop, v_journal, v_to_account, v_operation, v_amount);
  update public.business_days set day_version = day_version + 1 where id = v_day;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, 'cash_transfer_confirmed', v_operation, v_at,
    jsonb_build_object('business_day_id', v_day, 'operation_id', v_operation)
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_operation, 'cash_transfer_confirmed', v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, p_payload, v_hash, v_operation, v_at);
  return jsonb_build_object('ok', true,
    'operation_id', v_operation, 'business_day_id', v_day,
    'day_version', v_day_version + 1, 'replayed', false);
end;
$fn$;

revoke all on function public.post_daily_ledger_cash_transfer(uuid, jsonb)
  from public, anon;
grant execute on function public.post_daily_ledger_cash_transfer(uuid, jsonb)
  to authenticated;

create or replace function public.get_daily_ledger_v2()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_base jsonb;
  v_day public.business_days%rowtype;
  v_feed jsonb;
  v_summary jsonb;
  v_gold jsonb;
  v_name text;
begin
  v_shop := private.opening_require_reader_shop();
  v_base := public.get_daily_ledger();
  if v_base ->> 'state' <> 'confirmed' then return v_base; end if;
  select day.* into v_day from public.business_days as day
  where day.shop_id = v_shop order by day.opened_at desc, day.id desc limit 1;
  select shop.owner_display_name into v_name from public.shops as shop
  where shop.id = v_shop;
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', operation.kind,
    'label_ar', case operation.kind
      when 'opening_balances' then 'رصيد افتتاحي'
      when 'sale' then 'بيع'
      when 'purchase' then 'شراء'
      when 'expense' then 'مصروف'
      when 'purchase_settlement' then 'سداد شراء'
      when 'cash_transfer' then 'تحويل نقدية'
      when 'close_day' then 'تقفيل اليومية'
      when 'open_day' then 'فتح اليومية'
    end,
    'operation_id', operation.id,
    'actor_display_name', coalesce(v_name, ''),
    'occurred_at', pg_catalog.to_jsonb(operation.created_at),
    'occurred_at_cairo', to_char(
      operation.created_at at time zone 'Africa/Cairo',
      'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'has_note', coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
  ) order by operation.shop_sequence desc), '[]'::jsonb) into v_feed
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop and operation.business_day_id = v_day.id;
  select jsonb_build_object(
    'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'sale'), 0)::text,
    'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'purchase'), 0)::text,
    'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'expense'), 0)::text,
    'sale_count', count(*) filter (where operation.kind = 'sale'),
    'purchase_count', count(*) filter (where operation.kind = 'purchase'),
    'expense_count', count(*) filter (where operation.kind = 'expense')
  ) into v_summary
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop and operation.business_day_id = v_day.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', bucket.kind,
    'category', bucket.category,
    'karat', bucket.karat,
    'milligrams', bucket.milligrams::text,
    'count', bucket.pieces::text
  ) order by bucket.kind, bucket.category, bucket.karat), '[]'::jsonb)
    into v_gold
  from (
    select operation.kind,
      item.value ->> 'category' as category,
      (item.value ->> 'karat')::smallint as karat,
      sum((item.value ->> 'milligrams')::numeric) as milligrams,
      sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id
     and detail.operation_id = operation.id
    cross join lateral jsonb_array_elements(detail.payload -> 'items') as item(value)
    where operation.shop_id = v_shop and operation.business_day_id = v_day.id
      and operation.kind in ('sale', 'purchase')
    group by operation.kind, item.value ->> 'category',
      (item.value ->> 'karat')::smallint
  ) as bucket;
  v_summary := v_summary || jsonb_build_object('gold_by_bucket', v_gold);
  return jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_base,
    '{read_model_version}', '2'::jsonb),
    '{business_day}', jsonb_build_object(
      'id', v_day.id,
      'business_date', to_char(v_day.business_date, 'YYYY-MM-DD'),
      'opened_at', pg_catalog.to_jsonb(v_day.opened_at)
    )), '{feed}', v_feed), '{day_summary}', v_summary);
end;
$fn$;

commit;


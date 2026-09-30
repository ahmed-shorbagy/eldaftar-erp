-- Full, linked reversals for confirmed sales and purchases.
begin;

alter table public.financial_operations drop constraint financial_operations_kind_check;
alter table public.financial_operations add constraint financial_operations_kind_check
  check (kind in ('opening_balances', 'sale', 'purchase', 'expense',
    'close_day', 'open_day', 'purchase_settlement', 'cash_transfer',
    'scrap_sale', 'scrap_to_stock', 'sale_return', 'purchase_return'));
alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled', 'invoice_send_confirmed',
    'cash_transfer_confirmed', 'scrap_sale_confirmed',
    'scrap_to_stock_confirmed', 'sale_return_confirmed',
    'purchase_return_confirmed'));
alter table public.financial_outbox drop constraint financial_outbox_event_check;
alter table public.financial_outbox add constraint financial_outbox_event_check
  check (event_type in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled', 'cash_transfer_confirmed',
    'scrap_sale_confirmed', 'scrap_to_stock_confirmed',
    'sale_return_confirmed', 'purchase_return_confirmed'));

create function public.post_daily_ledger_return(
  p_idempotency_key uuid, p_original_operation_id uuid, p_note text
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_original public.financial_operations%rowtype;
  v_original_payload jsonb;
  v_kind text;
  v_payload jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_day uuid;
  v_day_version bigint;
  v_actor uuid;
  v_at timestamptz;
  v_sequence bigint;
  v_operation uuid;
  v_source_journal record;
  v_new_journal uuid;
  v_action text;
  v_remaining bigint := 0;
  v_original_paid numeric := 0;
  v_settled numeric := 0;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_original_operation_id is null
    or p_note is null or length(p_note) > 1000 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select operation.* into v_original
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_original_operation_id
  for update;
  if v_original.id is null then raise exception 'not_found'; end if;
  if v_original.kind not in ('sale', 'purchase') then
    raise exception 'invalid_input';
  end if;
  select detail.payload into v_original_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop and detail.operation_id = v_original.id;
  if v_original_payload is null then raise exception 'not_found'; end if;
  v_kind := v_original.kind || '_return';
  v_payload := jsonb_build_object(
    'version', 1,
    'kind', v_kind,
    'original_operation_id', v_original.id,
    'original_sequence', v_original.shop_sequence::text,
    'original_kind', v_original.kind,
    'total_piastres', v_original_payload ->> 'total_piastres',
    'tenders', coalesce(v_original_payload -> 'tenders', '[]'::jsonb),
    'items', coalesce(v_original_payload -> 'items', '[]'::jsonb),
    'customer_name', coalesce(v_original_payload ->> 'customer_name', ''),
    'note', p_note
  );
  v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key for update;
  if found then
    if v_request.payload_canonical ->> 'kind' = v_kind
      and v_request.payload_canonical ->> 'original_operation_id' = v_original.id::text
      and v_request.payload_canonical ->> 'note' = p_note then
      return jsonb_build_object('ok', true,
        'operation_id', v_request.operation_id, 'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if exists (
    select 1 from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = v_shop
      and operation.kind in ('sale_return', 'purchase_return')
      and detail.payload ->> 'original_operation_id' = v_original.id::text
  ) then
    raise exception 'already_returned';
  end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if v_original.kind = 'purchase' then
    select payable.remaining_piastres into v_remaining
    from public.purchase_cash_payables as payable
    where payable.shop_id = v_shop and payable.operation_id = v_original.id
    for update;
    v_remaining := coalesce(v_remaining, 0);
    select coalesce(sum((tender.value ->> 'piastres')::numeric), 0)
      into v_original_paid
    from jsonb_array_elements(coalesce(v_original_payload -> 'tenders', '[]'::jsonb))
      as tender(value);
    select coalesce(sum((tender.value ->> 'piastres')::numeric), 0)
      into v_settled
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral jsonb_array_elements(detail.payload -> 'tenders') as tender(value)
    where operation.shop_id = v_shop and operation.kind = 'purchase_settlement'
      and detail.payload ->> 'purchase_operation_id' = v_original.id::text;
    v_payload := jsonb_set(v_payload, '{cash_returned_piastres}',
      to_jsonb((v_original_paid + v_settled)::bigint::text));
    v_payload := jsonb_set(v_payload, '{cancelled_payable_piastres}',
      to_jsonb(v_remaining::text));
    v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  else
    v_payload := jsonb_set(v_payload, '{cash_returned_piastres}',
      to_jsonb((v_original_payload ->> 'total_piastres')));
    v_payload := jsonb_set(v_payload, '{cancelled_payable_piastres}', '"0"'::jsonb);
    v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  end if;
  -- Recheck idempotency after adding server-derived settlement fields.
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key for update;
  if found then
    if v_request.payload_canonical = v_payload
      and v_request.payload_sha256 = v_hash then
      return jsonb_build_object('ok', true,
        'operation_id', v_request.operation_id, 'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, v_kind, v_day, v_actor, v_at)
  returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_operation, v_shop, v_payload, v_at);
  for v_source_journal in
    select journal.* from public.journals as journal
    where journal.shop_id = v_shop and (
      journal.operation_id = v_original.id or (
        v_original.kind = 'purchase' and journal.operation_id in (
          select operation.id from public.financial_operations as operation
          join public.financial_operation_details as detail
            on detail.shop_id = operation.shop_id
           and detail.operation_id = operation.id
          where operation.shop_id = v_shop
            and operation.kind = 'purchase_settlement'
            and detail.payload ->> 'purchase_operation_id' = v_original.id::text
        )
      )
    ) order by journal.id
  loop
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_operation, v_source_journal.unit_kind,
      v_source_journal.currency_code, v_source_journal.karat,
      v_source_journal.bucket_key
    ) returning id into v_new_journal;
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) select v_shop, v_new_journal, posting.account_id, v_operation,
        -posting.amount
      from public.journal_postings as posting
      where posting.shop_id = v_shop
        and posting.journal_id = v_source_journal.id;
  end loop;
  if v_original.kind = 'purchase' then
    update public.purchase_cash_payables
    set remaining_piastres = 0, updated_at = v_at
    where shop_id = v_shop and operation_id = v_original.id;
  end if;
  update public.business_days set day_version = day_version + 1 where id = v_day;
  v_action := v_kind || '_confirmed';
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, v_action, v_operation, v_at,
    jsonb_build_object('business_day_id', v_day,
      'original_operation_id', v_original.id,
      'operation_id', v_operation));
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_operation, v_action, v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, v_payload, v_hash, v_operation, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_operation,
    'business_day_id', v_day, 'day_version', v_day_version + 1,
    'replayed', false);
end;
$fn$;

revoke all on function public.post_daily_ledger_return(uuid, uuid, text)
  from public, anon;
grant execute on function public.post_daily_ledger_return(uuid, uuid, text)
  to authenticated;

alter function public.get_daily_ledger_v2()
  rename to get_daily_ledger_v2_before_linked_returns;
revoke all on function public.get_daily_ledger_v2_before_linked_returns()
  from public, anon, authenticated;
create function public.get_daily_ledger_v2()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_result jsonb; v_feed jsonb;
begin
  v_result := public.get_daily_ledger_v2_before_linked_returns();
  if v_result ->> 'state' <> 'confirmed' then return v_result; end if;
  select coalesce(jsonb_agg(
    case item.value ->> 'kind'
      when 'sale_return' then jsonb_set(item.value, '{label_ar}', '"مرتجع بيع"'::jsonb)
      when 'purchase_return' then jsonb_set(item.value, '{label_ar}', '"مرتجع شراء"'::jsonb)
      else item.value end order by item.ordinality
  ), '[]'::jsonb) into v_feed
  from jsonb_array_elements(v_result -> 'feed') with ordinality as item(value, ordinality);
  return jsonb_set(v_result, '{feed}', v_feed);
end;
$fn$;
revoke all on function public.get_daily_ledger_v2() from public, anon;
grant execute on function public.get_daily_ledger_v2() to authenticated;

alter function public.get_daily_ledger_operation(uuid)
  rename to get_daily_ledger_operation_before_linked_returns;
revoke all on function public.get_daily_ledger_operation_before_linked_returns(uuid)
  from public, anon, authenticated;
create function public.get_daily_ledger_operation(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_result jsonb; v_return uuid;
begin
  v_result := public.get_daily_ledger_operation_before_linked_returns(p_operation_id);
  v_shop := private.opening_require_reader_shop();
  select operation.id into v_return
  from public.financial_operations as operation
  join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop
    and operation.kind in ('sale_return', 'purchase_return')
    and detail.payload ->> 'original_operation_id' = p_operation_id::text
  limit 1;
  return jsonb_set(v_result, '{returned_by_operation_id}',
    coalesce(to_jsonb(v_return::text), 'null'::jsonb));
end;
$fn$;
revoke all on function public.get_daily_ledger_operation(uuid) from public, anon;
grant execute on function public.get_daily_ledger_operation(uuid) to authenticated;

commit;

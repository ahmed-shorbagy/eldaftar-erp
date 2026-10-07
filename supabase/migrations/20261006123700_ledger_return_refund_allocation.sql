-- Explicit owner-selected refund allocation; cumulative paid-total bounds remain.
begin;

do $compatibility$
begin
  if md5(replace(pg_get_functiondef('private.post_linked_return_core(uuid,uuid,jsonb,uuid,uuid,timestamptz,boolean,boolean)'::regprocedure),E'\r',''))
    <> 'a610f5e6488cec40bf21019fbf00498f' then
    raise exception 'compensation_predecessor_changed';
  end if;
end;
$compatibility$;

create or replace function private.post_linked_return_core(
  p_shop uuid, p_key uuid, p_payload jsonb, p_day uuid,
  p_actor uuid, p_at timestamptz, p_bump boolean, p_allow_zero boolean
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_original uuid;
  v_original_payload jsonb;
  v_bounds jsonb;
  v_item jsonb;
  v_source record;
  v_seen integer[] := '{}';
  v_index integer;
  v_mg bigint;
  v_count bigint;
  v_rem_mg bigint;
  v_rem_count bigint;
  v_consideration bigint;
  v_remainder bigint;
  v_tender_sum numeric;
  v_tender jsonb;
  v_method text;
  v_amount bigint;
  v_refundable bigint;
  v_payable bigint;
  v_cancel bigint;
  v_cash bigint;
  v_operation uuid;
  v_component text;
  v_components text[] := array[
    'base_piastres', 'workmanship_piastres', 'other_charges_piastres', 'discount_piastres'];
  v_price_sum numeric;
  v_book_mg bigint;
  v_book_count bigint;
  v_version bigint;
  v_hash bytea;
  v_qty_left boolean := false;
  v_line_count integer := 0;
  v_detail jsonb;
  v_detail_items jsonb;
begin
  perform private.json_keys_allowed(p_payload, array[
    'version', 'kind', 'original_operation_id', 'note', 'items',
    'consideration_piastres', 'tenders'
  ], array['pricing', 'expected_day_id', 'expected_day_version']);
  if p_payload -> 'version' is distinct from '1'::jsonb then raise exception 'invalid_input'; end if;
  v_kind := p_payload ->> 'kind';
  if v_kind not in ('sale_return', 'purchase_return')
    or pg_catalog.jsonb_typeof(p_payload -> 'original_operation_id') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'note') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'consideration_piastres') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or char_length(p_payload ->> 'note') > 1000 then
    raise exception 'invalid_input';
  end if;
  begin
    v_original := (p_payload ->> 'original_operation_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_input';
  end;
  perform 1 from public.financial_operations as operation
  where operation.shop_id = p_shop and operation.id = v_original
    and operation.kind = case when v_kind = 'sale_return' then 'sale' else 'purchase' end
  for update;
  if not found then raise exception 'not_found'; end if;
  select detail.payload into v_original_payload
  from public.financial_operation_details as detail
  where detail.shop_id = p_shop and detail.operation_id = v_original;
  v_bounds := private.return_bounds(p_shop, v_original);
  if (v_bounds ->> 'fully_returned')::boolean then raise exception 'already_returned'; end if;
  v_consideration := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'consideration_piastres'));
  v_remainder := private.checked_signed_bigint(
    private.parse_signed_amount(v_bounds ->> 'remainder_consideration_piastres'));
  if v_consideration < 0 or v_consideration > v_remainder then
    raise exception 'return_exceeds_original';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(v_bounds -> 'items') loop
    if coalesce((v_item ->> 'remainder_milligrams')::bigint, 0) <> 0
      or coalesce((v_item ->> 'remainder_count')::bigint, 0) <> 0 then
      v_qty_left := true;
    end if;
  end loop;
  v_line_count := pg_catalog.jsonb_array_length(p_payload -> 'items');
  if v_line_count = 0 and (v_qty_left or v_consideration = 0) then
    raise exception 'invalid_input';
  end if;
  if v_line_count > 50 then raise exception 'invalid_input'; end if;
  for v_item in select value from pg_catalog.jsonb_array_elements(p_payload -> 'items') loop
    if v_kind = 'sale_return' then
      perform private.json_keys_allowed(
        v_item, array['item_index', 'milligrams'], array['count']);
    else
      perform private.json_keys_allowed(
        v_item, array['item_index', 'milligrams'], array['count']);
    end if;
    if pg_catalog.jsonb_typeof(v_item -> 'item_index') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'milligrams') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_index := private.opening_checked_bigint(
      private.opening_parse_amount(v_item ->> 'item_index'))::integer;
    if v_index = any(v_seen) then raise exception 'invalid_input'; end if;
    v_seen := pg_catalog.array_append(v_seen, v_index);
    select * into v_source from private.return_movement_lines(p_shop, p_payload) as line
    where line.item_index = v_index limit 1;
    if v_source.item_index is null then raise exception 'invalid_input'; end if;
    select (item.value ->> 'remainder_milligrams')::bigint,
      case when item.value ->> 'remainder_count' is null then 0
        else (item.value ->> 'remainder_count')::bigint end
      into v_rem_mg, v_rem_count
    from pg_catalog.jsonb_array_elements(v_bounds -> 'items') as item(value)
    where (item.value ->> 'item_index') = v_index::text;
    v_mg := v_source.milligrams;
    v_count := v_source.piece_count;
    if v_mg <= 0 or v_mg > v_rem_mg or v_count < 0 or v_count > v_rem_count then
      raise exception 'return_exceeds_original';
    end if;
    if v_source.category = 'scrap' then
      if v_item ? 'count' and v_item -> 'count' <> 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    else
      if v_count <= 0 or (v_mg = 0) <> (v_count = 0) then
        raise exception 'stock_pair_mismatch';
      end if;
      if (v_rem_mg - v_mg = 0) <> (v_rem_count - v_count = 0) then
        raise exception 'stock_pair_mismatch';
      end if;
      select balance.milligrams, balance.piece_count into v_book_mg, v_book_count
      from private.metal_balance(p_shop, v_source.category, v_source.karat, null) as balance;
      if v_kind = 'purchase_return' then
        if v_book_mg < v_mg or v_book_count < v_count then
          raise exception 'negative_owned_balance';
        end if;
        if (v_book_mg - v_mg = 0) <> (v_book_count - v_count = 0) then
          raise exception 'stock_pair_mismatch';
        end if;
      end if;
    end if;
    if v_kind = 'purchase_return' and v_source.category = 'scrap' then
      select balance.milligrams into v_book_mg
      from private.metal_balance(p_shop, 'scrap', v_source.karat, null) as balance;
      if v_book_mg < v_mg then raise exception 'negative_owned_balance'; end if;
    end if;
  end loop;
  if (v_bounds ->> 'has_pricing')::boolean then
    if pg_catalog.jsonb_typeof(p_payload -> 'pricing') is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
    perform private.json_keys_allowed(p_payload -> 'pricing', v_components,
      array['other_charges_label']);
    v_price_sum := 0;
    foreach v_component in array v_components loop
      if pg_catalog.jsonb_typeof(p_payload -> 'pricing' -> v_component) is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(p_payload -> 'pricing' ->> v_component));
      v_rem_mg := private.checked_signed_bigint(private.parse_signed_amount(
        v_bounds -> 'pricing' -> v_component ->> 'remainder'));
      if v_rem_mg < 0 or v_amount > v_rem_mg then raise exception 'return_exceeds_original'; end if;
      if v_component = 'discount_piastres' then v_price_sum := v_price_sum - v_amount;
      else v_price_sum := v_price_sum + v_amount; end if;
    end loop;
    if pg_catalog.jsonb_typeof(p_payload -> 'pricing' -> 'other_charges_label') is distinct from 'string'
      or char_length(p_payload -> 'pricing' ->> 'other_charges_label') > 120 then
      raise exception 'invalid_input';
    end if;
    if private.opening_parse_amount(p_payload -> 'pricing' ->> 'other_charges_piastres') > 0
      and nullif(btrim(p_payload -> 'pricing' ->> 'other_charges_label'), '') is null then
      raise exception 'invalid_input';
    end if;
    if v_price_sum <> v_consideration then raise exception 'pricing_mismatch'; end if;
  elsif p_payload ? 'pricing' then
    raise exception 'invalid_input';
  end if;
  v_payable := (v_bounds ->> 'payable_remaining_piastres')::bigint;
  if v_kind = 'purchase_return' then
    v_cancel := least(v_consideration, v_payable);
    v_cash := v_consideration - v_cancel;
  else
    v_cancel := 0;
    v_cash := v_consideration;
  end if;
  v_tender_sum := private.validated_tender_sum(p_payload -> 'tenders');
  if v_tender_sum <> v_cash then raise exception 'tender_mismatch'; end if;
  for v_tender in select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') loop
    v_method := v_tender ->> 'method';
    v_amount := private.opening_checked_bigint(private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_kind = 'sale_return'
      and private.method_balance(p_shop, v_method, null) < v_amount then
      raise exception 'negative_owned_balance';
    end if;
  end loop;
  -- Any explicitly reviewed refund method is permitted. Bound cumulative
  -- refunds by actual paid consideration and sale outflows by shop balances.
  if v_kind in ('sale_return','purchase_return') then
    v_refundable := 0;
    foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
      v_refundable := v_refundable + private.checked_signed_bigint(
        private.parse_signed_amount(v_bounds -> 'refundable_by_method' ->> v_method));
    end loop;
    if v_cash > v_refundable then raise exception 'return_exceeds_original'; end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'item_index', line.item_index::text, 'category', line.category,
    'karat', line.karat, 'item_name', line.item_name,
    'milligrams', line.milligrams::text,
    'count', case when line.category = 'scrap' then null else line.piece_count::text end
  ) order by line.item_index), '[]'::jsonb) into v_detail_items
  from private.return_movement_lines(p_shop, p_payload) line;
  v_detail := p_payload || jsonb_build_object(
    'items', v_detail_items, 'total_piastres', v_consideration::text,
    'original_sequence', (select shop_sequence::text from public.financial_operations where id = v_original and shop_id = p_shop),
    'original_kind', v_bounds ->> 'kind',
    'customer_name', coalesce(v_original_payload ->> 'customer_name', ''),
    'cash_returned_piastres', v_cash::text, 'cancelled_payable_piastres', v_cancel::text);
  v_operation := private.insert_operation(
    p_shop, v_kind, p_day, p_actor, p_at, v_detail);
  for v_source in select * from private.return_movement_lines(p_shop, p_payload) loop
    perform private.post_account_delta(
      p_shop, v_operation,
      case when v_source.category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
      'gold_mg', v_source.category, v_source.karat, null,
      case when v_kind = 'sale_return' then v_source.milligrams else -v_source.milligrams end,
      'movement_gold_clearing', v_kind = 'sale_return');
    if v_source.category <> 'scrap' then
      perform private.post_account_delta(
        p_shop, v_operation, 'saleable_count', 'count',
        v_source.category, v_source.karat, null,
        case when v_kind = 'sale_return' then v_source.piece_count else -v_source.piece_count end,
        'movement_count_clearing', v_kind = 'sale_return');
    end if;
  end loop;
  for v_tender in select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') loop
    v_amount := private.opening_checked_bigint(private.opening_parse_amount(v_tender ->> 'piastres'));
    perform private.post_account_delta(
      p_shop, v_operation, 'cash_method', 'money', null, null, v_tender ->> 'method',
      case when v_kind = 'sale_return' then -v_amount else v_amount end,
      'movement_money_clearing', v_kind = 'purchase_return');
  end loop;
  if v_cancel > 0 then
    update public.purchase_cash_payables
    set remaining_piastres = remaining_piastres - v_cancel, updated_at = p_at
    where shop_id = p_shop and operation_id = v_original;
  end if;
  if p_bump then
    return private.finish_financial_command(
      p_shop, v_operation, p_actor, p_at, p_day, v_kind || '_confirmed',
      p_key, p_payload,
      pg_catalog.jsonb_build_object(
        'business_day_id', p_day, 'operation_id', v_operation,
        'original_operation_id', v_original,
        'cancelled_payable_piastres', v_cancel::text,
        'cash_refund_piastres', v_cash::text))
      || pg_catalog.jsonb_build_object(
        'cancelled_payable_piastres', v_cancel::text,
        'cash_refund_piastres', v_cash::text);
  end if;
  select day.day_version into v_version
  from public.business_days as day where day.id = p_day and day.shop_id = p_shop;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    p_shop, p_actor, v_kind || '_confirmed', v_operation, p_at,
    pg_catalog.jsonb_build_object('business_day_id', p_day, 'operation_id', v_operation,
      'original_operation_id', v_original));
  insert into public.financial_outbox (shop_id, operation_id, event_type, created_at)
  values (p_shop, v_operation, v_kind || '_confirmed', p_at);
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (p_shop, p_key, p_payload, v_hash, v_operation, p_at);
  perform private.sync_operation_lots(p_shop, v_operation, true);
  return pg_catalog.jsonb_build_object(
    'ok', true, 'operation_id', v_operation, 'business_day_id', p_day,
    'day_version', v_version, 'replayed', false,
    'cancelled_payable_piastres', v_cancel::text,
    'cash_refund_piastres', v_cash::text,
    'effects', private.operation_effects(p_shop, v_operation));
end;
$fn$;



commit;

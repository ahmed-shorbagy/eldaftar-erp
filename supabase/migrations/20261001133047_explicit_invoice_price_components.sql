-- Explicit agreed price components. Historical version-one payloads stay intact.
-- Version-two line prices sum to base; tenders/payable match the adjusted total.
begin;

create or replace function private.validate_trade_pricing(p_payload jsonb)
returns void language plpgsql immutable set search_path = '' as $fn$
declare
  v_price jsonb := p_payload -> 'pricing';
  v_base numeric;
  v_workmanship numeric;
  v_other numeric;
  v_discount numeric;
  v_total bigint;
  v_key text;
begin
  if p_payload -> 'version' = '1'::jsonb then
    if p_payload ? 'pricing' then raise exception 'invalid_input'; end if;
    return;
  end if;
  if p_payload -> 'version' is distinct from '2'::jsonb
    or p_payload ->> 'kind' not in ('sale', 'purchase')
    or jsonb_typeof(v_price) is distinct from 'object'
    or not (v_price ?& array['base_piastres', 'workmanship_piastres',
      'other_charges_piastres', 'other_charges_label', 'discount_piastres'])
    or v_price - 'base_piastres' - 'workmanship_piastres'
      - 'other_charges_piastres' - 'other_charges_label' - 'discount_piastres'
      <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  foreach v_key in array array['base_piastres', 'workmanship_piastres',
    'other_charges_piastres', 'discount_piastres'] loop
    if jsonb_typeof(v_price -> v_key) is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    perform private.opening_checked_bigint(
      private.opening_parse_amount(v_price ->> v_key));
  end loop;
  if jsonb_typeof(v_price -> 'other_charges_label') is distinct from 'string'
    or length(v_price ->> 'other_charges_label') > 120 then
    raise exception 'invalid_input';
  end if;
  v_base := private.opening_parse_amount(v_price ->> 'base_piastres');
  v_workmanship := private.opening_parse_amount(v_price ->> 'workmanship_piastres');
  v_other := private.opening_parse_amount(v_price ->> 'other_charges_piastres');
  v_discount := private.opening_parse_amount(v_price ->> 'discount_piastres');
  if v_other > 0 and nullif(btrim(v_price ->> 'other_charges_label'), '') is null then
    raise exception 'invalid_input';
  end if;
  if v_base + v_workmanship + v_other - v_discount <= 0 then
    raise exception 'pricing_mismatch';
  end if;
  v_total := private.opening_checked_bigint(v_base + v_workmanship + v_other - v_discount);
  if v_total <> private.opening_parse_amount(p_payload ->> 'total_piastres') then
    raise exception 'pricing_mismatch';
  end if;
end;
$fn$;
revoke all on function private.validate_trade_pricing(jsonb)
  from public, anon, authenticated;

create or replace function public.post_daily_ledger_trade(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_day uuid;
  v_day_version bigint;
  v_kind text;
  v_actor uuid;
  v_at timestamptz;
  v_sequence bigint;
  v_op uuid;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_total bigint;
  v_tender_sum numeric := 0;
  v_payable bigint := 0;
  v_line_sum numeric := 0;
  v_priced integer := 0;
  v_tender jsonb;
  v_line jsonb;
  v_method text;
  v_seen text[] := '{}';
  v_amount bigint;
  v_money_journal uuid;
  v_clear uuid;
  v_account uuid;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_gold_journal uuid;
  v_count_journal uuid;
  v_sign integer;
  v_action text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_payload is null
    or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = p_payload and v_request.payload_sha256 = v_hash then
      return jsonb_build_object('ok', true, 'operation_id', v_request.operation_id,
        'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if p_payload -> 'version' is null or p_payload -> 'version' not in ('1'::jsonb, '2'::jsonb) then
    raise exception 'invalid_input';
  end if;
  v_kind := p_payload ->> 'kind';
  if v_kind is null or v_kind not in ('sale', 'purchase', 'expense', 'scrap_sale')
    or not (p_payload ?& array[
      'version', 'kind', 'total_piastres', 'tenders', 'items',
      'description', 'customer_name', 'customer_phone', 'note'
    ])
    or p_payload - 'version' - 'kind' - 'total_piastres' - 'tenders'
      - 'items' - 'description' - 'customer_name' - 'customer_phone' - 'note'
      - 'purchase_obligation_piastres' - 'pricing'
      <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'tenders') not between
      (case when v_kind = 'purchase' then 0 else 1 end) and 4
    or jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'items') > 50 then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'total_piastres') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'description') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'customer_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'customer_phone') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'note') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  if coalesce(length(p_payload ->> 'note'), 0) > 1000
    or coalesce(length(p_payload ->> 'customer_name'), 0) > 200
    or coalesce(length(p_payload ->> 'customer_phone'), 0) > 20
    or coalesce(length(p_payload ->> 'description'), 0) > 300 then
    raise exception 'invalid_input';
  end if;
  if coalesce(p_payload ->> 'customer_phone', '') <> ''
    and (p_payload ->> 'customer_phone') !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  if v_kind = 'expense' then
    if jsonb_array_length(p_payload -> 'items') <> 0
      or nullif(btrim(p_payload ->> 'description'), '') is null then
      raise exception 'invalid_input';
    end if;
  elsif jsonb_array_length(p_payload -> 'items') = 0 then
    raise exception 'invalid_input';
  end if;
  v_total := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'total_piastres'));
  if v_total <= 0 then raise exception 'invalid_input'; end if;
  perform private.validate_trade_pricing(p_payload);
  for v_tender in select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
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
    v_tender_sum := v_tender_sum + v_amount;
  end loop;
  if v_kind = 'purchase' then
    if v_tender_sum > v_total then raise exception 'tender_mismatch'; end if;
    v_payable := private.opening_checked_bigint(v_total - v_tender_sum);
    if v_payable > 0 then
      if jsonb_typeof(p_payload -> 'purchase_obligation_piastres')
          is distinct from 'string'
        or private.opening_checked_bigint(private.opening_parse_amount(
          p_payload ->> 'purchase_obligation_piastres')) <> v_payable
        or nullif(btrim(p_payload ->> 'customer_name'), '') is null then
        raise exception 'invalid_input';
      end if;
    elsif p_payload ? 'purchase_obligation_piastres' then
      raise exception 'invalid_input';
    end if;
  else
    if p_payload ? 'purchase_obligation_piastres' then
      raise exception 'invalid_input';
    end if;
    if v_tender_sum <> v_total then raise exception 'tender_mismatch'; end if;
  end if;
  for v_line in select value from jsonb_array_elements(p_payload -> 'items') as l(value)
  loop
    if jsonb_typeof(v_line) is distinct from 'object'
      or not (v_line ?& array[
        'category', 'karat', 'milligrams', 'count',
        'item_name', 'line_price_piastres'
      ])
      or v_line - 'category' - 'karat' - 'milligrams' - 'count'
        - 'item_name' - 'line_price_piastres' <> '{}'::jsonb
      or jsonb_typeof(v_line -> 'category') is distinct from 'string'
      or jsonb_typeof(v_line -> 'milligrams') is distinct from 'string'
      or jsonb_typeof(v_line -> 'item_name') is distinct from 'string'
      or jsonb_typeof(v_line -> 'line_price_piastres')
        not in ('string', 'null') then
      raise exception 'invalid_input';
    end if;
    v_category := v_line ->> 'category';
    if jsonb_typeof(v_line -> 'karat') <> 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$' then
      raise exception 'invalid_input';
    end if;
    v_karat := (v_line ->> 'karat')::smallint;
    if not private.opening_pair_allowed(v_category, v_karat)
      or (v_kind = 'sale' and v_category = 'scrap')
      or (v_kind = 'scrap_sale' and v_category <> 'scrap')
      or nullif(btrim(v_line ->> 'item_name'), '') is null
      or length(v_line ->> 'item_name') > 120 then
      raise exception 'invalid_input';
    end if;
    v_mg := private.opening_checked_bigint(
      private.opening_parse_amount(v_line ->> 'milligrams'));
    if v_mg <= 0 then raise exception 'invalid_input'; end if;
    if v_category = 'scrap' then
      if v_line ? 'count' and v_line -> 'count' <> 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    else
      if jsonb_typeof(v_line -> 'count') is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_count := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'count'));
      if v_count <= 0 then raise exception 'invalid_input'; end if;
    end if;
    if v_line ? 'line_price_piastres'
      and v_line -> 'line_price_piastres' <> 'null'::jsonb then
      v_priced := v_priced + 1;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'line_price_piastres'));
      if v_amount <= 0 then raise exception 'invalid_input'; end if;
      v_line_sum := v_line_sum + v_amount;
    end if;
  end loop;
  if v_priced <> 0 and
    (v_priced <> jsonb_array_length(p_payload -> 'items') or v_line_sum <> case when p_payload -> 'version' = '2'::jsonb
      then private.opening_parse_amount(p_payload -> 'pricing' ->> 'base_piastres')
      else v_total end) then
    raise exception 'line_price_mismatch';
  end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, v_kind, v_day, v_actor, v_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, v_shop, p_payload, v_at);
  if v_payable > 0 then
    insert into public.purchase_cash_payables (
      operation_id, shop_id, seller_name, initial_piastres,
      remaining_piastres, created_at, updated_at
    ) values (v_op, v_shop, btrim(p_payload ->> 'customer_name'),
      v_payable, v_payable, v_at, v_at);
  end if;
  update public.business_days set day_version = day_version + 1 where id = v_day;

  v_sign := case when v_kind in ('sale', 'scrap_sale') then 1 else -1 end;
  if v_tender_sum > 0 then
    v_clear := private.financial_account(v_shop, 'movement_money_clearing',
      'money', null, null, null, true);
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, bucket_key
    ) values (v_shop, v_op, 'money', 'EGP', 'money') returning id into v_money_journal;
    for v_tender in select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
    loop
      v_account := private.financial_account(v_shop, 'cash_method', 'money',
        null, null, v_tender ->> 'method', false);
      if v_account is null then raise exception 'invalid_input'; end if;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_tender ->> 'piastres'));
      insert into public.journal_postings (
        shop_id, journal_id, account_id, operation_id, amount
      ) values (v_shop, v_money_journal, v_account, v_op, v_sign * v_amount);
    end loop;
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values (v_shop, v_money_journal, v_clear, v_op, -v_sign * v_tender_sum);
  end if;

  if v_kind <> 'expense' then
    for v_line in select value from jsonb_array_elements(p_payload -> 'items') as l(value)
    loop
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      v_mg := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'milligrams'));
      v_account := private.financial_account(v_shop,
        case when v_category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
        'gold_mg', v_category, v_karat, null, v_kind = 'purchase');
      if v_account is null then raise exception 'insufficient_stock'; end if;
      v_clear := private.financial_account(v_shop, 'movement_gold_clearing',
        'gold_mg', null, v_karat, null, true);
      insert into public.journals (
        shop_id, operation_id, unit_kind, karat, bucket_key
      ) values (
        v_shop, v_op, 'gold_mg', v_karat,
        'gold:' || v_category || ':' || v_karat::text
      ) returning id into v_gold_journal;
      insert into public.journal_postings (
        shop_id, journal_id, account_id, operation_id, amount
      ) values
        (v_shop, v_gold_journal, v_account, v_op, -v_sign * v_mg),
        (v_shop, v_gold_journal, v_clear, v_op, v_sign * v_mg);
      if v_category <> 'scrap' then
        v_count := private.opening_checked_bigint(
          private.opening_parse_amount(v_line ->> 'count'));
        v_account := private.financial_account(v_shop, 'saleable_count',
          'count', v_category, v_karat, null, v_kind = 'purchase');
        if v_account is null then raise exception 'insufficient_stock'; end if;
        v_clear := private.financial_account(v_shop, 'movement_count_clearing',
          'count', v_category, v_karat, null, true);
        insert into public.journals (
          shop_id, operation_id, unit_kind, karat, bucket_key
        ) values (
          v_shop, v_op, 'count', v_karat,
          'count:' || v_category || ':' || v_karat::text
        ) returning id into v_count_journal;
        insert into public.journal_postings (
          shop_id, journal_id, account_id, operation_id, amount
        ) values
          (v_shop, v_count_journal, v_account, v_op, -v_sign * v_count),
          (v_shop, v_count_journal, v_clear, v_op, v_sign * v_count);
      end if;
    end loop;
  end if;
  v_action := v_kind || '_confirmed';
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, v_action, v_op, v_at,
    jsonb_build_object('business_day_id', v_day, 'operation_id', v_op)
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_op, v_action, v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, p_payload, v_hash, v_op, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_op,
    'business_day_id', v_day, 'day_version', v_day_version + 1,
    'replayed', false);
end;
$fn$;

revoke all on function public.post_daily_ledger_trade(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_trade(uuid, jsonb) to authenticated;
commit;

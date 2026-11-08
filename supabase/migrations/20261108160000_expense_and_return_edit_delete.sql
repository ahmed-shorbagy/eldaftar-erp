-- Expense and customer_return edit/delete on the open day.
-- Wrap the current public trade-change RPCs; sale/purchase keep the paid-purchase
-- path. New kinds reverse through a journal/lot mirror.

begin;

select private.compensation_extend_in_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  array['expense_reversal', 'customer_return_reversal']
);

-- Mirror the source journals and lot movements with opposite signs.
create function private.post_mirror_reversal(
  p_shop uuid,
  p_key uuid,
  p_source uuid,
  p_kind text,
  p_day uuid,
  p_actor uuid,
  p_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_sequence bigint;
  v_op uuid;
  v_journal uuid;
  v_src_journal record;
  v_src_posting record;
  v_src_movement record;
  v_hash bytea;
  v_payload jsonb;
begin
  if p_kind not in ('expense_reversal', 'customer_return_reversal') then
    raise exception 'invalid_input';
  end if;
  if not exists (
    select 1 from public.financial_operations as operation
    where operation.shop_id = p_shop and operation.id = p_source
  ) then
    raise exception 'not_found';
  end if;
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation
  where operation.shop_id = p_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    p_shop, v_sequence, p_kind, p_day, p_actor, p_at
  ) returning id into v_op;
  v_payload := pg_catalog.jsonb_build_object(
    'version', 1,
    'kind', p_kind,
    'source_operation_id', p_source
  );
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, p_shop, v_payload, p_at);
  for v_src_journal in
    select journal.id, journal.unit_kind, journal.currency_code,
           journal.karat, journal.bucket_key
    from public.journals as journal
    where journal.shop_id = p_shop and journal.operation_id = p_source
    order by journal.id
  loop
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      p_shop, v_op, v_src_journal.unit_kind, v_src_journal.currency_code,
      v_src_journal.karat, v_src_journal.bucket_key
    ) returning id into v_journal;
    for v_src_posting in
      select posting.account_id, posting.amount
      from public.journal_postings as posting
      where posting.shop_id = p_shop and posting.journal_id = v_src_journal.id
      order by posting.id
    loop
      insert into public.journal_postings (
        shop_id, journal_id, account_id, operation_id, amount
      ) values (
        p_shop, v_journal, v_src_posting.account_id, v_op, -v_src_posting.amount
      );
    end loop;
  end loop;
  for v_src_movement in
    select movement.lot_id, movement.delta_milligrams, movement.delta_count
    from public.inventory_lot_movements as movement
    where movement.shop_id = p_shop and movement.operation_id = p_source
    order by movement.created_at, movement.id
  loop
    perform private.add_lot_movement(
      p_shop,
      v_src_movement.lot_id,
      v_op,
      -v_src_movement.delta_milligrams,
      -v_src_movement.delta_count,
      'return',
      'return_mirror'
    );
  end loop;
  v_hash := extensions.digest(pg_catalog.convert_to(v_payload::text, 'UTF8'), 'sha256');
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (p_shop, p_key, v_payload, v_hash, v_op, p_at);
  return v_op;
end;
$fn$;

revoke all on function private.post_mirror_reversal(
  uuid, uuid, uuid, text, uuid, uuid, timestamptz
) from public, anon, authenticated;

-- Accept expense (description, no items) and customer_return (M4 contract).
create or replace function private.trade_change_assert_draft(
  p_payload jsonb, p_expected_kind text
)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_kind text;
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
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
begin
  if pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  if p_payload -> 'version' is null
    or p_payload -> 'version' not in ('1'::jsonb, '2'::jsonb) then
    raise exception 'invalid_input';
  end if;
  v_kind := p_payload ->> 'kind';
  if v_kind is null
    or (p_expected_kind is not null and v_kind is distinct from p_expected_kind) then
    raise exception 'invalid_input';
  end if;

  if v_kind = 'customer_return' then
    if p_payload -> 'version' is distinct from '1'::jsonb
      or not (p_payload ?& array[
        'version', 'kind', 'total_piastres', 'tenders', 'items',
        'customer_name', 'customer_phone', 'note'
      ])
      or p_payload - 'version' - 'kind' - 'total_piastres' - 'tenders'
        - 'items' - 'customer_name' - 'customer_phone' - 'note'
        <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
    if pg_catalog.jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
      or pg_catalog.jsonb_array_length(p_payload -> 'tenders') not between 1 and 4
      or pg_catalog.jsonb_typeof(p_payload -> 'items') is distinct from 'array'
      or pg_catalog.jsonb_array_length(p_payload -> 'items') not between 1 and 50
      or pg_catalog.jsonb_typeof(p_payload -> 'total_piastres') is distinct from 'string'
      or pg_catalog.jsonb_typeof(p_payload -> 'customer_name') is distinct from 'string'
      or pg_catalog.jsonb_typeof(p_payload -> 'customer_phone') is distinct from 'string'
      or pg_catalog.jsonb_typeof(p_payload -> 'note') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    if coalesce(pg_catalog.length(p_payload ->> 'note'), 0) > 1000
      or coalesce(pg_catalog.length(p_payload ->> 'customer_name'), 0) > 200
      or coalesce(pg_catalog.length(p_payload ->> 'customer_phone'), 0) > 20 then
      raise exception 'invalid_input';
    end if;
    if coalesce(p_payload ->> 'customer_phone', '') <> ''
      and (p_payload ->> 'customer_phone') !~ '^\+?[0-9]{7,15}$' then
      raise exception 'invalid_input';
    end if;
    v_total := private.opening_checked_bigint(
      private.opening_parse_amount(p_payload ->> 'total_piastres'));
    if v_total <= 0 then raise exception 'invalid_input'; end if;
    for v_tender in
      select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') as tender(value)
    loop
      if pg_catalog.jsonb_typeof(v_tender) is distinct from 'object'
        or not (v_tender ?& array['method', 'piastres'])
        or v_tender - 'method' - 'piastres' <> '{}'::jsonb
        or pg_catalog.jsonb_typeof(v_tender -> 'method') is distinct from 'string'
        or pg_catalog.jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_method := v_tender ->> 'method';
      if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
        or v_method = any (v_seen) then
        raise exception 'invalid_input';
      end if;
      v_seen := pg_catalog.array_append(v_seen, v_method);
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_tender ->> 'piastres'));
      if v_amount <= 0 then raise exception 'invalid_input'; end if;
      v_tender_sum := v_tender_sum + v_amount;
    end loop;
    if v_tender_sum <> v_total then raise exception 'tender_mismatch'; end if;
    for v_line in
      select value from pg_catalog.jsonb_array_elements(p_payload -> 'items') as line(value)
    loop
      if pg_catalog.jsonb_typeof(v_line) is distinct from 'object'
        or not (v_line ?& array[
          'category', 'karat', 'milligrams', 'count',
          'item_name', 'line_price_piastres'
        ])
        or v_line - 'category' - 'karat' - 'milligrams' - 'count'
          - 'item_name' - 'line_price_piastres' <> '{}'::jsonb
        or pg_catalog.jsonb_typeof(v_line -> 'category') is distinct from 'string'
        or pg_catalog.jsonb_typeof(v_line -> 'milligrams') is distinct from 'string'
        or pg_catalog.jsonb_typeof(v_line -> 'count') is distinct from 'string'
        or pg_catalog.jsonb_typeof(v_line -> 'item_name') is distinct from 'string'
        or pg_catalog.jsonb_typeof(v_line -> 'line_price_piastres')
          not in ('string', 'null')
        or pg_catalog.jsonb_typeof(v_line -> 'karat') <> 'number'
        or (v_line ->> 'karat') !~ '^[0-9]{2}$' then
        raise exception 'invalid_input';
      end if;
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      if v_category not in ('worked_jewelry', 'coin', 'bullion')
        or not private.opening_pair_allowed(v_category, v_karat)
        or nullif(pg_catalog.btrim(v_line ->> 'item_name'), '') is null
        or pg_catalog.length(v_line ->> 'item_name') > 120 then
        raise exception 'invalid_input';
      end if;
      v_mg := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'milligrams'));
      v_count := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'count'));
      if v_mg <= 0 or v_count <= 0 then raise exception 'invalid_input'; end if;
      if v_line -> 'line_price_piastres' <> 'null'::jsonb then
        v_priced := v_priced + 1;
        v_amount := private.opening_checked_bigint(
          private.opening_parse_amount(v_line ->> 'line_price_piastres'));
        if v_amount <= 0 then raise exception 'invalid_input'; end if;
        v_line_sum := v_line_sum + v_amount;
      end if;
    end loop;
    if v_priced <> 0 and (
      v_priced <> pg_catalog.jsonb_array_length(p_payload -> 'items')
      or v_line_sum <> v_total
    ) then
      raise exception 'line_price_mismatch';
    end if;
    return;
  end if;

  if v_kind not in ('sale', 'purchase', 'expense')
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
  if pg_catalog.jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_payload -> 'tenders') not between
      (case when v_kind = 'purchase' then 0 else 1 end) and 4
    or pg_catalog.jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or (
      v_kind = 'expense'
      and pg_catalog.jsonb_array_length(p_payload -> 'items') <> 0
    )
    or (
      v_kind <> 'expense'
      and pg_catalog.jsonb_array_length(p_payload -> 'items') not between 1 and 50
    ) then
    raise exception 'invalid_input';
  end if;
  if pg_catalog.jsonb_typeof(p_payload -> 'total_piastres') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'description') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'customer_name') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'customer_phone') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'note') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  if coalesce(pg_catalog.length(p_payload ->> 'note'), 0) > 1000
    or coalesce(pg_catalog.length(p_payload ->> 'customer_name'), 0) > 200
    or coalesce(pg_catalog.length(p_payload ->> 'customer_phone'), 0) > 20
    or coalesce(pg_catalog.length(p_payload ->> 'description'), 0) > 300 then
    raise exception 'invalid_input';
  end if;
  if v_kind = 'expense'
    and nullif(pg_catalog.btrim(p_payload ->> 'description'), '') is null then
    raise exception 'invalid_input';
  end if;
  if coalesce(p_payload ->> 'customer_phone', '') <> ''
    and (p_payload ->> 'customer_phone') !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  v_total := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'total_piastres'));
  if v_total <= 0 then raise exception 'invalid_input'; end if;
  if v_kind <> 'expense' then
    perform private.validate_trade_pricing(p_payload);
  elsif p_payload ? 'pricing' then
    raise exception 'invalid_input';
  end if;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') as tender(value)
  loop
    if pg_catalog.jsonb_typeof(v_tender) is distinct from 'object'
      or not (v_tender ?& array['method', 'piastres'])
      or v_tender - 'method' - 'piastres' <> '{}'::jsonb
      or pg_catalog.jsonb_typeof(v_tender -> 'method') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any (v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_amount <= 0 then raise exception 'invalid_input'; end if;
    v_tender_sum := v_tender_sum + v_amount;
  end loop;
  if v_kind = 'purchase' then
    if v_tender_sum > v_total then raise exception 'tender_mismatch'; end if;
    v_payable := private.opening_checked_bigint(v_total - v_tender_sum);
    if v_payable > 0 then
      if pg_catalog.jsonb_typeof(p_payload -> 'purchase_obligation_piastres')
          is distinct from 'string'
        or private.opening_checked_bigint(private.opening_parse_amount(
          p_payload ->> 'purchase_obligation_piastres')) <> v_payable then
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
  for v_line in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'items') as line(value)
  loop
    if pg_catalog.jsonb_typeof(v_line) is distinct from 'object'
      or not (v_line ?& array[
        'category', 'karat', 'milligrams', 'count',
        'item_name', 'line_price_piastres'
      ])
      or v_line - 'category' - 'karat' - 'milligrams' - 'count'
        - 'item_name' - 'line_price_piastres' <> '{}'::jsonb
      or pg_catalog.jsonb_typeof(v_line -> 'category') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'milligrams') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'item_name') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'line_price_piastres')
        not in ('string', 'null') then
      raise exception 'invalid_input';
    end if;
    v_category := v_line ->> 'category';
    if pg_catalog.jsonb_typeof(v_line -> 'karat') <> 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$' then
      raise exception 'invalid_input';
    end if;
    v_karat := (v_line ->> 'karat')::smallint;
    if not private.opening_pair_allowed(v_category, v_karat)
      or (v_kind = 'sale' and v_category = 'scrap')
      or nullif(pg_catalog.btrim(v_line ->> 'item_name'), '') is null
      or pg_catalog.length(v_line ->> 'item_name') > 120 then
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
      if pg_catalog.jsonb_typeof(v_line -> 'count') is distinct from 'string' then
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
  if v_priced <> 0 and (
    v_priced <> pg_catalog.jsonb_array_length(p_payload -> 'items')
    or v_line_sum <> case
      when p_payload -> 'version' = '2'::jsonb
        then private.opening_parse_amount(p_payload -> 'pricing' ->> 'base_piastres')
      else v_total
    end
  ) then
    raise exception 'line_price_mismatch';
  end if;
end;
$fn$;

-- A returned lot later sold (or any later outbound movement) blocks change.
create or replace function private.trade_change_assert_followups(
  p_shop uuid, p_operation uuid, p_kind text
) returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_initial bigint;
  v_remaining bigint;
begin
  if exists (
    select 1
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = p_shop
      and operation.kind in ('sale_return', 'purchase_return')
      and detail.payload ->> 'original_operation_id' = p_operation::text
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = p_shop
      and operation.kind = 'purchase_settlement'
      and detail.payload ->> 'purchase_operation_id' = p_operation::text
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1 from public.invoice_dispatch_confirmations as dispatch
    where dispatch.shop_id = p_shop and dispatch.operation_id = p_operation
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1 from public.debt_source_archives as archive
    where archive.shop_id = p_shop and archive.source_id = p_operation
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1 from public.gold_obligations as gold
    where gold.shop_id = p_shop and gold.operation_id = p_operation
  ) then
    raise exception 'trade_has_followups';
  end if;
  select payable.initial_piastres, payable.remaining_piastres
    into v_initial, v_remaining
  from public.purchase_cash_payables as payable
  where payable.shop_id = p_shop and payable.operation_id = p_operation;
  if found and v_remaining is distinct from v_initial then
    raise exception 'trade_has_followups';
  end if;
  if p_kind in ('purchase', 'customer_return') and exists (
    select 1
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = p_shop
      and lot.origin_operation_id = p_operation
      and movement.operation_id is distinct from p_operation
      and (movement.delta_milligrams < 0 or movement.delta_count < 0)
  ) then
    raise exception 'trade_has_followups';
  end if;
end;
$fn$;

alter function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  rename to review_ledger_trade_change_v1_before_expense_return_change;
revoke all on function public.review_ledger_trade_change_v1_before_expense_return_change(
  uuid, text, jsonb
) from public, anon, authenticated;

create function public.review_ledger_trade_change_v1(
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_kind text;
  v_source_day uuid;
  v_payload jsonb;
  v_day uuid;
  v_version bigint;
  v_source_sha text;
  v_replacement_sha text;
  v_effects jsonb;
  v_token text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_operation_id is null or p_action is null then
    raise exception 'invalid_input';
  end if;
  if p_replacement = 'null'::jsonb then
    p_replacement := null;
  end if;
  if p_action = 'delete' then
    if p_replacement is not null then raise exception 'invalid_input'; end if;
  elsif p_action = 'edit' then
    if pg_catalog.jsonb_typeof(p_replacement) is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select operation.kind into v_kind
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if v_kind in ('sale', 'purchase') or v_kind is null then
    return public.review_ledger_trade_change_v1_before_expense_return_change(
      p_operation_id, p_action, p_replacement
    );
  end if;
  if v_kind not in ('expense', 'customer_return') then
    raise exception 'trade_not_editable';
  end if;
  if v_kind = 'expense' then
    perform private.allow_member_permission('expense');
  else
    perform private.allow_member_permission('sale');
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select operation.kind, operation.business_day_id
    into v_kind, v_source_day
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if not found then raise exception 'not_found'; end if;
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = v_shop and change.source_operation_id = p_operation_id
  ) then
    raise exception 'trade_inactive';
  end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  order by day.opened_at desc
  limit 1;
  if v_day is null then raise exception 'day_closed'; end if;
  if v_source_day is distinct from v_day then
    raise exception 'trade_not_editable';
  end if;
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop and detail.operation_id = p_operation_id;
  if v_payload is null then raise exception 'not_found'; end if;
  if p_action = 'edit' then
    perform private.trade_change_assert_draft(p_replacement, v_kind);
  end if;
  perform private.trade_change_assert_followups(v_shop, p_operation_id, v_kind);
  v_effects := private.trade_change_effects(v_kind, v_payload, p_action, p_replacement);
  perform private.trade_change_assert_affordable(v_shop, v_effects);
  v_source_sha := private.trade_payload_sha256(v_payload);
  v_replacement_sha := case
    when p_action = 'delete' then ''
    else private.trade_payload_sha256(p_replacement)
  end;
  v_token := private.trade_change_token(
    v_shop, p_operation_id, p_action, v_source_sha, v_replacement_sha,
    v_day, v_version, v_effects
  );
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'operation_id', p_operation_id,
    'action', p_action,
    'expected_day_id', v_day,
    'expected_day_version', v_version,
    'source_sha256', v_source_sha,
    'review_token', v_token,
    'source', pg_catalog.jsonb_build_object('kind', v_kind, 'payload', v_payload),
    'effects', v_effects
  );
end;
$fn$;

revoke all on function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  from public, anon;
grant execute on function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  to authenticated;

alter function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) rename to post_ledger_trade_change_v1_before_expense_return_change;
revoke all on function public.post_ledger_trade_change_v1_before_expense_return_change(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon, authenticated;

create function public.post_ledger_trade_change_v1(
  p_idempotency_key uuid,
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb,
  p_expected_day_id uuid,
  p_expected_day_version bigint,
  p_source_sha256 text,
  p_review_token text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_actor uuid;
  v_at timestamptz;
  v_command jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_change public.ledger_trade_changes%rowtype;
  v_kind text;
  v_source_day uuid;
  v_payload jsonb;
  v_day uuid;
  v_version bigint;
  v_source_sha text;
  v_replacement_sha text;
  v_effects jsonb;
  v_token text;
  v_reversal_key uuid;
  v_replacement_key uuid;
  v_reversal_id uuid;
  v_trade jsonb;
  v_replacement_id uuid;
  v_audit_action text;
  v_reversal_kind text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_operation_id is null or p_action is null
    or p_expected_day_id is null or p_expected_day_version is null
    or p_source_sha256 is null or p_review_token is null
    or p_source_sha256 !~ '^[0-9a-f]{64}$'
    or p_review_token !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_input';
  end if;
  if p_replacement = 'null'::jsonb then
    p_replacement := null;
  end if;
  if p_action = 'delete' then
    if p_replacement is not null then raise exception 'invalid_input'; end if;
  elsif p_action = 'edit' then
    if pg_catalog.jsonb_typeof(p_replacement) is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select operation.kind into v_kind
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if v_kind in ('sale', 'purchase') or v_kind is null then
    return public.post_ledger_trade_change_v1_before_expense_return_change(
      p_idempotency_key, p_operation_id, p_action, p_replacement,
      p_expected_day_id, p_expected_day_version, p_source_sha256, p_review_token
    );
  end if;
  if v_kind not in ('expense', 'customer_return') then
    raise exception 'trade_not_editable';
  end if;
  if v_kind = 'expense' then
    perform private.allow_member_permission('expense');
  else
    perform private.allow_member_permission('sale');
  end if;

  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_command := private.trade_change_command_payload(
    p_action, p_operation_id, p_replacement, p_expected_day_id,
    p_expected_day_version, p_source_sha256, p_review_token
  );
  v_hash := extensions.digest(pg_catalog.convert_to(v_command::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = v_command and v_request.payload_sha256 = v_hash then
      select change.* into v_change
      from public.ledger_trade_changes as change
      where change.shop_id = v_shop and change.command_key = p_idempotency_key;
      if v_change.source_operation_id is null then
        raise exception 'invalid_input';
      end if;
      return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'ok', true,
        'operation_id', v_change.reversal_operation_id,
        'replayed', true,
        'replacement_operation_id', v_change.replacement_operation_id
      ));
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select operation.kind, operation.business_day_id
    into v_kind, v_source_day
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id
  for update;
  if not found then raise exception 'not_found'; end if;
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = v_shop and change.source_operation_id = p_operation_id
  ) then
    raise exception 'operation_replaced';
  end if;
  if v_kind not in ('expense', 'customer_return') then
    raise exception 'trade_not_editable';
  end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  order by day.opened_at desc
  limit 1
  for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if v_source_day is distinct from v_day then
    raise exception 'trade_not_editable';
  end if;
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop and detail.operation_id = p_operation_id;
  if v_payload is null then raise exception 'not_found'; end if;
  v_source_sha := private.trade_payload_sha256(v_payload);
  if v_source_sha is distinct from p_source_sha256
    or p_expected_day_id is distinct from v_day
    or p_expected_day_version is distinct from v_version then
    raise exception 'stale_trade_review';
  end if;
  perform private.trade_change_assert_followups(v_shop, p_operation_id, v_kind);
  if p_action = 'edit' then
    perform private.trade_change_assert_draft(p_replacement, v_kind);
    v_replacement_sha := private.trade_payload_sha256(p_replacement);
  else
    v_replacement_sha := '';
  end if;
  v_effects := private.trade_change_effects(v_kind, v_payload, p_action, p_replacement);
  v_token := private.trade_change_token(
    v_shop, p_operation_id, p_action, v_source_sha, v_replacement_sha,
    v_day, v_version, v_effects
  );
  if v_token is distinct from p_review_token then
    raise exception 'stale_trade_review';
  end if;
  perform private.trade_change_assert_affordable(v_shop, v_effects);
  v_reversal_key := private.compensation_child_key(p_idempotency_key, ':trade-reversal');
  v_replacement_key := private.compensation_child_key(p_idempotency_key, ':trade-replacement');
  if exists (
    select 1 from public.financial_command_requests as request
    where request.shop_id = v_shop
      and request.idempotency_key in (v_reversal_key, v_replacement_key)
  ) then
    raise exception 'payload_mismatch';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  v_reversal_kind := case
    when v_kind = 'expense' then 'expense_reversal'
    else 'customer_return_reversal'
  end;
  v_reversal_id := private.post_mirror_reversal(
    v_shop, v_reversal_key, p_operation_id, v_reversal_kind,
    v_day, v_actor, v_at
  );
  if p_action = 'edit' then
    if v_kind = 'expense' then
      perform pg_catalog.set_config('eldaftar.purchase_keep_category', 'on', true);
      v_trade := public.post_daily_ledger_trade(v_replacement_key, p_replacement);
      perform pg_catalog.set_config('eldaftar.purchase_keep_category', 'off', true);
      v_replacement_id := (v_trade ->> 'operation_id')::uuid;
    else
      v_trade := private.post_customer_return_core(
        v_shop, v_replacement_key, p_replacement, v_day, v_actor, v_at
      );
      v_replacement_id := (v_trade ->> 'operation_id')::uuid;
    end if;
  else
    update public.business_days
    set day_version = day_version + 1
    where id = v_day and shop_id = v_shop;
  end if;
  perform private.trade_change_assert_final(v_shop);
  insert into public.ledger_trade_changes (
    shop_id, source_operation_id, action, reversal_operation_id,
    replacement_operation_id, actor_user_id, created_at, source_sha256,
    review_token, command_key
  ) values (
    v_shop, p_operation_id, p_action, v_reversal_id, v_replacement_id,
    v_actor, v_at, v_source_sha, v_token, p_idempotency_key
  );
  v_audit_action := case when p_action = 'edit' then 'trade_edited' else 'trade_deleted' end;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, v_audit_action, p_operation_id, v_at,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'business_day_id', v_day,
      'operation_id', p_operation_id,
      'reversal_operation_id', v_reversal_id,
      'replacement_operation_id', v_replacement_id,
      'action', p_action
    ))
  );
  insert into public.financial_outbox (shop_id, operation_id, event_type, created_at)
  values (v_shop, p_operation_id, v_audit_action, v_at);
  insert into public.ledger_trade_change_audits (
    shop_id, source_operation_id, actor_user_id, action, created_at, details
  ) values (
    v_shop, p_operation_id, v_actor, v_audit_action, v_at,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'reversal_operation_id', v_reversal_id,
      'replacement_operation_id', v_replacement_id,
      'command_key', p_idempotency_key,
      'source_sha256', v_source_sha
    ))
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (
    v_shop, p_idempotency_key, v_command, v_hash, v_reversal_id, v_at
  );
  perform private.bump_shop_sync(v_shop, 'invoice');
  perform private.bump_shop_sync(v_shop, 'debt');
  perform private.bump_shop_sync(v_shop, 'customer');
  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'ok', true,
    'operation_id', v_reversal_id,
    'replayed', false,
    'replacement_operation_id', v_replacement_id
  ));
end;
$fn$;

revoke all on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon;
grant execute on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) to authenticated;

commit;

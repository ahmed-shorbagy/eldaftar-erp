-- Standalone customer_return. Cash goes out like a reversed sale.
-- The item returns to the same saleable stock and a named lot.

begin;

select private.compensation_extend_in_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  array['customer_return']
);
select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  array['customer_return_confirmed']
);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  array['customer_return_confirmed']
);

create or replace function private.ledger_operation_label(p_kind text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case p_kind
    when 'opening_balances' then 'رصيد افتتاحي'
    when 'sale' then 'بيع'
    when 'purchase' then 'شراء'
    when 'expense' then 'مصروف'
    when 'purchase_settlement' then 'سداد شراء'
    when 'cash_transfer' then 'تحويل نقدية'
    when 'scrap_sale' then 'بيع كسر'
    when 'scrap_to_stock' then 'تحويل كسر إلى مخزون'
    when 'sale_return' then 'مرتجع بيع'
    when 'purchase_return' then 'مرتجع شراء'
    when 'customer_return' then 'مرتجع'
    when 'close_day' then 'تقفيل اليومية'
    when 'open_day' then 'فتح اليومية'
    when 'ledger_correction' then 'تسوية فرق الجرد'
    when 'exchange' then 'استبدال'
    when 'daily_note' then 'ملاحظة يومية'
    when 'repair_fee' then 'أجرة إصلاح'
    when 'debt_settlement' then 'سداد دين'
    when 'gold_obligation_acquisition' then 'استلام ذهب مقابل التزام'
    when 'gold_obligation_settlement' then 'سداد التزام ذهب'
    else null
  end;
$fn$;

create or replace function private.audit_trail_family(p_action text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case p_action
    when 'trade_edited' then 'change'
    when 'ledger_correction_confirmed' then 'change'
    when 'exchange_confirmed' then 'change'
    when 'inventory_correction_confirmed' then 'change'
    when 'trade_deleted' then 'delete'
    when 'daily_note_edited' then 'change'
    when 'daily_note_deleted' then 'delete'
    when 'expense_confirmed' then 'deduction'
    when 'inventory_removal_confirmed' then 'deduction'
    when 'sale_return_confirmed' then 'deduction'
    when 'purchase_return_confirmed' then 'deduction'
    when 'customer_return_confirmed' then 'deduction'
    else 'post'
  end;
$fn$;

create or replace function private.audit_trail_action_label(p_action text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case p_action
    when 'opening_balances_confirmed' then 'رصيد افتتاحي'
    when 'sale_confirmed' then 'بيع'
    when 'purchase_confirmed' then 'شراء'
    when 'expense_confirmed' then 'مصروف'
    when 'business_day_closed' then 'إقفال اليوم'
    when 'business_day_opened' then 'فتح اليوم'
    when 'purchase_settled' then 'تسوية شراء'
    when 'invoice_send_confirmed' then 'تأكيد إرسال فاتورة'
    when 'cash_transfer_confirmed' then 'تحويل نقدي'
    when 'scrap_sale_confirmed' then 'بيع كسر'
    when 'scrap_to_stock_confirmed' then 'تحويل كسر إلى مخزون'
    when 'sale_return_confirmed' then 'مرتجع بيع'
    when 'purchase_return_confirmed' then 'مرتجع شراء'
    when 'customer_return_confirmed' then 'تسجيل مرتجع'
    when 'inventory_addition_confirmed' then 'إضافة مخزون'
    when 'inventory_removal_confirmed' then 'خصم مخزون'
    when 'inventory_correction_confirmed' then 'تصحيح مخزون'
    when 'inventory_conversion_confirmed' then 'تحويل مخزون'
    when 'inventory_receipt_confirmed' then 'استلام مخزون'
    when 'inventory_recognition_confirmed' then 'إثبات مخزون'
    when 'ownership_transfer_confirmed' then 'نقل ملكية'
    when 'gold_obligation_acquisition_confirmed' then 'أمانة ذهب'
    when 'gold_obligation_settled' then 'تسوية أمانة ذهب'
    when 'receipt_manual_allocation_confirmed' then 'ربط استلام يدوي'
    when 'daily_note_recorded' then 'ملاحظة يومية'
    when 'daily_note_edited' then 'تعديل ملاحظة'
    when 'daily_note_deleted' then 'مسح ملاحظة'
    when 'ledger_correction_confirmed' then 'تصحيح دفتر'
    when 'exchange_confirmed' then 'استبدال'
    when 'repair_fee_confirmed' then 'أجرة صيانة'
    when 'debt_settlement_confirmed' then 'تسوية دين'
    when 'trade_edited' then 'تعديل عملية'
    when 'trade_deleted' then 'حذف عملية'
    else 'عملية مسجّلة'
  end;
$fn$;

-- Purchase lots live in the pre-compensation function. The live
-- apply_operation_lots falls through to it for this kind.
do $lots$
declare
  v_def text;
  v_old text := 'elsif v_kind = ''purchase'' then';
  v_new text := $branch$elsif v_kind = 'customer_return' then
    for v_line in
      select value from jsonb_array_elements(coalesce(v_payload -> 'items', '[]'::jsonb))
    loop
      perform private.create_stock_lot(
        p_shop, p_operation, v_line ->> 'item_name', v_line ->> 'category',
        (v_line ->> 'karat')::smallint,
        private.line_milligrams(v_line),
        private.line_count(v_line, v_line ->> 'category'),
        'owned_available', null, false, null, null, 'return', 'manual'
      );
    end loop;
  elsif v_kind = 'purchase' then$branch$;
begin
  v_def := pg_catalog.pg_get_functiondef(
    'private.apply_operation_lots_before_compensation(uuid, uuid)'::regprocedure
  );
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_lot_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$lots$;

create function private.post_customer_return_core(
  p_shop uuid,
  p_key uuid,
  p_payload jsonb,
  p_day uuid,
  p_actor uuid,
  p_at timestamptz
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_day_version bigint;
  v_sequence bigint;
  v_op uuid;
  v_hash bytea;
  v_total bigint;
  v_tender_sum bigint := 0;
  v_line_sum bigint := 0;
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
  v_name text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload -> 'version' is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'customer_return'
    or not (p_payload ?& array[
      'version', 'kind', 'total_piastres', 'tenders', 'items',
      'customer_name', 'customer_phone', 'note'
    ])
    or p_payload - 'version' - 'kind' - 'total_piastres' - 'tenders'
      - 'items' - 'customer_name' - 'customer_phone' - 'note'
      <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'tenders') not between 1 and 4
    or jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'items') not between 1 and 50
    or jsonb_typeof(p_payload -> 'total_piastres') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'customer_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'customer_phone') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'note') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  if coalesce(length(p_payload ->> 'note'), 0) > 1000
    or coalesce(length(p_payload ->> 'customer_name'), 0) > 200
    or coalesce(length(p_payload ->> 'customer_phone'), 0) > 20 then
    raise exception 'invalid_input';
  end if;
  if coalesce(p_payload ->> 'customer_phone', '') <> ''
    and (p_payload ->> 'customer_phone') !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  v_total := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'total_piastres')
  );
  if v_total <= 0 then
    raise exception 'invalid_input';
  end if;
  perform private.assert_active_cash_methods(p_shop, p_payload);
  for v_tender in
    select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
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
      or v_method = any(v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres')
    );
    if v_amount <= 0 then
      raise exception 'invalid_input';
    end if;
    v_tender_sum := v_tender_sum + v_amount;
  end loop;
  if v_tender_sum <> v_total then
    raise exception 'invalid_input';
  end if;
  for v_line in
    select value from jsonb_array_elements(p_payload -> 'items') as l(value)
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
      or jsonb_typeof(v_line -> 'count') is distinct from 'string'
      or jsonb_typeof(v_line -> 'item_name') is distinct from 'string'
      or jsonb_typeof(v_line -> 'line_price_piastres') not in ('string', 'null')
      or jsonb_typeof(v_line -> 'karat') <> 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$' then
      raise exception 'invalid_input';
    end if;
    v_category := v_line ->> 'category';
    v_karat := (v_line ->> 'karat')::smallint;
    v_name := v_line ->> 'item_name';
    if v_category not in ('worked_jewelry', 'coin', 'bullion')
      or not private.opening_pair_allowed(v_category, v_karat)
      or v_name is null
      or v_name <> btrim(v_name)
      or char_length(v_name) not between 1 and 120 then
      raise exception 'invalid_input';
    end if;
    v_mg := private.opening_checked_bigint(
      private.opening_parse_amount(v_line ->> 'milligrams')
    );
    v_count := private.opening_checked_bigint(
      private.opening_parse_amount(v_line ->> 'count')
    );
    if v_mg <= 0 or v_count <= 0 then
      raise exception 'invalid_input';
    end if;
    if v_line -> 'line_price_piastres' <> 'null'::jsonb then
      v_priced := v_priced + 1;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'line_price_piastres')
      );
      if v_amount <= 0 then
        raise exception 'invalid_input';
      end if;
      v_line_sum := v_line_sum + v_amount;
    end if;
  end loop;
  if v_priced <> 0 and (
    v_priced <> jsonb_array_length(p_payload -> 'items') or v_line_sum <> v_total
  ) then
    raise exception 'invalid_input';
  end if;

  select day.day_version into v_day_version
  from public.business_days as day
  where day.id = p_day and day.shop_id = p_shop;
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation
  where operation.shop_id = p_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    p_shop, v_sequence, 'customer_return', p_day, p_actor, p_at
  ) returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, p_shop, p_payload, p_at);
  update public.business_days
    set day_version = day_version + 1
    where id = p_day;

  v_clear := private.financial_account(
    p_shop, 'movement_money_clearing', 'money', null, null, null, true
  );
  insert into public.journals (
    shop_id, operation_id, unit_kind, currency_code, bucket_key
  ) values (p_shop, v_op, 'money', 'EGP', 'money')
  returning id into v_money_journal;
  for v_tender in
    select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
  loop
    v_account := private.financial_account(
      p_shop, 'cash_method', 'money', null, null, v_tender ->> 'method', false
    );
    if v_account is null then
      raise exception 'invalid_input';
    end if;
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres')
    );
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values (p_shop, v_money_journal, v_account, v_op, -v_amount);
  end loop;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values (p_shop, v_money_journal, v_clear, v_op, v_tender_sum);

  for v_line in
    select value from jsonb_array_elements(p_payload -> 'items') as l(value)
  loop
    v_category := v_line ->> 'category';
    v_karat := (v_line ->> 'karat')::smallint;
    v_mg := private.opening_checked_bigint(
      private.opening_parse_amount(v_line ->> 'milligrams')
    );
    v_count := private.opening_checked_bigint(
      private.opening_parse_amount(v_line ->> 'count')
    );
    v_account := private.financial_account(
      p_shop, 'saleable_metal', 'gold_mg', v_category, v_karat, null, true
    );
    v_clear := private.financial_account(
      p_shop, 'movement_gold_clearing', 'gold_mg', null, v_karat, null, true
    );
    insert into public.journals (
      shop_id, operation_id, unit_kind, karat, bucket_key
    ) values (
      p_shop, v_op, 'gold_mg', v_karat,
      'gold:' || v_category || ':' || v_karat::text
    ) returning id into v_gold_journal;
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values
      (p_shop, v_gold_journal, v_account, v_op, v_mg),
      (p_shop, v_gold_journal, v_clear, v_op, -v_mg);
    v_account := private.financial_account(
      p_shop, 'saleable_count', 'count', v_category, v_karat, null, true
    );
    v_clear := private.financial_account(
      p_shop, 'movement_count_clearing', 'count', v_category, v_karat, null, true
    );
    insert into public.journals (
      shop_id, operation_id, unit_kind, karat, bucket_key
    ) values (
      p_shop, v_op, 'count', v_karat,
      'count:' || v_category || ':' || v_karat::text
    ) returning id into v_count_journal;
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values
      (p_shop, v_count_journal, v_account, v_op, v_count),
      (p_shop, v_count_journal, v_clear, v_op, -v_count);
  end loop;

  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    p_shop, p_actor, 'customer_return_confirmed', v_op, p_at,
    jsonb_build_object('business_day_id', p_day, 'operation_id', v_op)
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (p_shop, v_op, 'customer_return_confirmed', p_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (p_shop, p_key, p_payload, v_hash, v_op, p_at);
  perform private.bump_shop_sync(p_shop, 'customer');
  return jsonb_build_object(
    'ok', true,
    'operation_id', v_op,
    'business_day_id', p_day,
    'day_version', v_day_version + 1,
    'replayed', false
  );
end;
$fn$;

revoke all on function private.post_customer_return_core(uuid, uuid, jsonb, uuid, uuid, timestamptz)
  from public, anon, authenticated;

create function public.post_customer_return_v1(
  p_idempotency_key uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_day uuid;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null or p_payload is null then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission('sale');
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = p_payload
      and v_request.payload_sha256 = v_hash then
      return jsonb_build_object(
        'ok', true,
        'operation_id', v_request.operation_id,
        'replayed', true
      );
    end if;
    raise exception 'payload_mismatch';
  end if;
  select day.id into v_day
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  for update;
  if v_day is null then
    raise exception 'day_closed';
  end if;
  return private.post_customer_return_core(
    v_shop, p_idempotency_key, p_payload, v_day, auth.uid(),
    pg_catalog.clock_timestamp()
  );
end;
$fn$;

revoke all on function public.post_customer_return_v1(uuid, jsonb) from public, anon;
grant execute on function public.post_customer_return_v1(uuid, jsonb) to authenticated;

do $reads$
declare
  r record;
  v_def text;
  v_old text;
  v_new text;
  v_hits integer := 0;
begin
  v_old := $o$'is_return', kept.kind in ('sale_return', 'purchase_return')$o$;
  v_new := $n$'is_return', kept.kind in ('sale_return', 'purchase_return', 'customer_return')$n$;
  for r in
    select proc.oid
    from pg_catalog.pg_proc as proc
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = proc.pronamespace
    where namespace.nspname in ('public', 'private')
      -- pg_get_functiondef rejects aggregates; only plain functions apply.
      and proc.prokind = 'f'
      and pg_catalog.strpos(pg_catalog.pg_get_functiondef(proc.oid), v_old) > 0
  loop
    v_def := pg_catalog.replace(pg_catalog.pg_get_functiondef(r.oid), v_old, v_new);
    execute v_def;
    v_hits := v_hits + 1;
  end loop;
  if v_hits = 0 then
    raise exception 'customer_return_is_return_anchor';
  end if;

  v_def := pg_catalog.pg_get_functiondef(
    'public.get_daily_ledger_home_v1_before_staff()'::regprocedure
  );
  v_old := 'operation.kind in (''sale_return'', ''purchase_return'')';
  v_new := 'operation.kind in (''sale_return'', ''purchase_return'', ''customer_return'')';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_count_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);

  v_def := pg_catalog.pg_get_functiondef(
    'public.get_financial_day_report_v1_before_staff(uuid)'::regprocedure
  );
  v_old := 'when kind = ''sale_return'' then -private.return_consideration(payload) else 0 end sale';
  v_new := 'when kind = ''customer_return'' then -coalesce((payload->>''total_piastres'')::numeric,0) when kind = ''sale_return'' then -private.return_consideration(payload) else 0 end sale';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_sale_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_old, v_new);
  v_old := 'where o.kind in (''sale'',''scrap_sale'',''purchase'')';
  v_new := 'where o.kind in (''sale'',''scrap_sale'',''purchase'',''customer_return'')';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_lines_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_old, v_new);
  v_old := 'when kind = ''sale_return'' then -mg else 0 end sold';
  v_new := 'when kind in (''sale_return'', ''customer_return'') then -mg else 0 end sold';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_gold_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_old, v_new);
  v_old := '''return_count'',count(*) filter(where not hidden and kind in (''sale_return'',''purchase_return''))';
  v_new := '''return_count'',count(*) filter(where not hidden and kind in (''sale_return'',''purchase_return'',''customer_return''))';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_report_count_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);

  v_def := pg_catalog.pg_get_functiondef(
    'public.get_financial_period_analytics_v1(text, date)'::regprocedure
  );
  v_old := 'and o.kind in (''sale'', ''scrap_sale'', ''purchase'', ''sale_return'', ''purchase_return'')';
  v_new := 'and o.kind in (''sale'', ''scrap_sale'', ''purchase'', ''sale_return'', ''purchase_return'', ''customer_return'')';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_analytics_kind_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_old, v_new);
  v_old := 'where o.kind in (''sale'', ''scrap_sale'', ''purchase'')';
  v_new := 'where o.kind in (''sale'', ''scrap_sale'', ''purchase'', ''customer_return'')';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_analytics_lines_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_old, v_new);
  v_old := 'when kind = ''sale_return'' then -mg else 0 end as sold';
  v_new := 'when kind in (''sale_return'', ''customer_return'') then -mg else 0 end as sold';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'customer_return_analytics_gold_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$reads$;

notify pgrst, 'reload schema';

commit;

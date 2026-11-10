-- Batch C review fixes (ADR 0044).
-- 1. C-D1: the 361ad2e feed parser rejects a row whose label differs from its
--    fixed map or whose kind it does not know. C-D7 relabels repair_fee to
--    «أجرة مرمة», and repair_fee_collection (2026-11-09) is unknown to it, so a
--    single handed-over repair broke the legacy home, date, and page reads.
--    Legacy reads now return feed rows in the 361ad2e vocabulary; the current
--    app reads the *_v2 names.
-- 2. C-D1: customer_status accepts the 361ad2e payload (no in_whatsapp_group)
--    and keeps the stored flag.
-- 3. C-D9: get_customer_list_v3 accepts the whatsapp_group filter.
-- 4. C-D7: audit trail labels say «مرمة».

begin;

-- ---------------------------------------------------------------------------
-- 1. Legacy feed rows
-- ---------------------------------------------------------------------------
create function private.legacy_361ad2e_feed(p_rows jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $fn$
  select coalesce(pg_catalog.jsonb_agg(
    (
      select pg_catalog.jsonb_object_agg(field.key, field.value)
      from pg_catalog.jsonb_each(
        case
          when row_item.value ->> 'kind' in ('repair_fee', 'repair_fee_collection')
            then row_item.value
              || '{"kind":"repair_fee","label_ar":"أجرة إصلاح"}'::jsonb
          else row_item.value
        end
      ) as field(key, value)
      where field.key in (
        'kind', 'label_ar', 'operation_id', 'actor_display_name',
        'occurred_at', 'occurred_at_cairo', 'has_note', 'shop_sequence',
        'is_daily_note', 'is_return', 'occurred_at_shop', 'party_name',
        'party_phone', 'total_pounds', 'weight_grams', 'karat',
        'payment_label', 'item_summary', 'piece_count', 'text', 'edited',
        'edited_at'
      )
    )
    order by row_item.ordinality
  ), '[]'::jsonb)
  from pg_catalog.jsonb_array_elements(
    case when pg_catalog.jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end
  ) with ordinality as row_item(value, ordinality)
  where row_item.value ->> 'kind' in (
    'opening_balances_confirmed', 'opening_balances', 'sale', 'purchase',
    'expense', 'purchase_settlement', 'cash_transfer', 'scrap_sale',
    'scrap_to_stock', 'sale_return', 'purchase_return', 'customer_return',
    'ledger_correction', 'exchange', 'close_day', 'open_day', 'daily_note',
    'repair_fee', 'repair_fee_collection'
  );
$fn$;

revoke all on function private.legacy_361ad2e_feed(jsonb)
  from public, anon, authenticated;

comment on function private.legacy_361ad2e_feed(jsonb) is
  'Feed rows in the 361ad2e parser vocabulary: known kinds, old labels, old keys (ADR 0044 C-D1).';

create or replace function public.get_daily_ledger_home_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_summary jsonb;
begin
  -- Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).
  v_result := public.get_daily_ledger_home_v1_full();
  v_result := v_result - 'day_reset' - 'last_closed_business_date';
  if pg_catalog.jsonb_typeof(v_result -> 'day_summary') = 'object' then
    v_summary := (v_result -> 'day_summary')
      - 'repair_piastres'
      - 'repair_count';
    v_result := pg_catalog.jsonb_set(v_result, '{day_summary}', v_summary);
  end if;
  if pg_catalog.jsonb_typeof(v_result -> 'feed') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{feed}', private.legacy_361ad2e_feed(v_result -> 'feed')
    );
  end if;
  return v_result;
end;
$fn$;

create or replace function public.get_ledger_date_v1(
  p_business_date date default null,
  p_before_sequence text default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_summary jsonb;
begin
  -- Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).
  v_result := public.get_ledger_date_v1_full(
    p_business_date, p_before_sequence, p_limit
  );
  if pg_catalog.jsonb_typeof(v_result -> 'day_summary') = 'object' then
    v_summary := (v_result -> 'day_summary')
      - 'repair_piastres'
      - 'repair_count';
    v_result := pg_catalog.jsonb_set(v_result, '{day_summary}', v_summary);
  end if;
  if pg_catalog.jsonb_typeof(v_result #> '{feed_page,items}') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{feed_page,items}',
      private.legacy_361ad2e_feed(v_result #> '{feed_page,items}')
    );
  end if;
  return v_result;
end;
$fn$;

-- Operation pages: the current app moves to _v2; the legacy name normalizes.
alter function public.get_ledger_operation_page(uuid, text, text, integer)
  rename to get_ledger_operation_page_full;
revoke all on function public.get_ledger_operation_page_full(uuid, text, text, integer)
  from public, anon, authenticated;

create function public.get_ledger_operation_page_v2(
  p_day_id uuid,
  p_before_sequence text,
  p_after_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  return public.get_ledger_operation_page_full(
    p_day_id, p_before_sequence, p_after_sequence, p_limit
  );
end;
$fn$;

revoke all on function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  from public, anon;
grant execute on function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  to authenticated;

comment on function public.get_ledger_operation_page_v2(uuid, text, text, integer) is
  'Current-app operation page with current labels and kinds (ADR 0044).';

create function public.get_ledger_operation_page(
  p_day_id uuid,
  p_before_sequence text,
  p_after_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  -- Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).
  v_result := public.get_ledger_operation_page_full(
    p_day_id, p_before_sequence, p_after_sequence, p_limit
  );
  if pg_catalog.jsonb_typeof(v_result -> 'items') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{items}', private.legacy_361ad2e_feed(v_result -> 'items')
    );
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_ledger_operation_page(uuid, text, text, integer)
  from public, anon;
grant execute on function public.get_ledger_operation_page(uuid, text, text, integer)
  to authenticated;

comment on function public.get_ledger_operation_page(uuid, text, text, integer) is
  'Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).';

-- ---------------------------------------------------------------------------
-- 2. customer_status: in_whatsapp_group is optional for older builds
-- ---------------------------------------------------------------------------
create or replace function private.customer_status(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_id uuid;
  v_expected bigint;
  v_vip boolean;
  v_open boolean;
  v_group boolean;
  v_row public.customers%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_status');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  -- Builds up to 361ad2e send no in_whatsapp_group; they keep the stored flag
  -- (ADR 0044 C-D1, C-D9).
  if p_payload ? 'in_whatsapp_group' then
    perform private.customer_require_keys(p_payload, array[
      'customer_id', 'expected_version', 'has_open_request', 'in_whatsapp_group',
      'is_vip', 'kind', 'version'
    ]);
  else
    perform private.customer_require_keys(p_payload, array[
      'customer_id', 'expected_version', 'has_open_request',
      'is_vip', 'kind', 'version'
    ]);
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_vip := private.customer_bool(p_payload -> 'is_vip');
  v_open := private.customer_bool(p_payload -> 'has_open_request');
  if p_payload ? 'in_whatsapp_group' then
    v_group := private.customer_bool(p_payload -> 'in_whatsapp_group');
  end if;
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  v_group := coalesce(v_group, v_row.in_whatsapp_group);
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customers as customer
    set is_vip = v_vip,
        has_open_request = v_open,
        in_whatsapp_group = v_group,
        record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'status_changed', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'is_vip', v_vip,
      'has_open_request', v_open,
      'in_whatsapp_group', v_group,
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true, 'replayed', false, 'command_kind', 'customer_status'
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_status', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

revoke all on function private.customer_status(uuid, jsonb)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. get_customer_list_v3 accepts the whatsapp_group filter
-- ---------------------------------------------------------------------------
do $patch_filter$
declare
  v_def text;
  v_old text := $old$v_filter not in ('active', 'archived', 'vip', 'open_request', 'all')$old$;
  v_new text := $new$v_filter not in ('active', 'archived', 'vip', 'open_request', 'whatsapp_group', 'all')$new$;
  v_count integer;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.get_customer_list_v3(text,text,text,integer,text)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if pg_catalog.strpos(v_def, v_new) > 0 then
    return;
  end if;
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, ''))
  ) / pg_catalog.length(v_old);
  if v_count <> 1 then
    raise exception 'customer_list_filter_whitelist_anchor %', v_count;
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_filter$;

-- ---------------------------------------------------------------------------
-- 4. Audit trail labels: «مرمة»
-- ---------------------------------------------------------------------------
create or replace function private.audit_trail_action_label(p_action text)
returns text
language sql
immutable
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
    when 'repair_fee_confirmed' then 'أجرة مرمة'
    when 'repair_fee_collection_confirmed' then 'تحصيل متبقي مرمة'
    when 'debt_settlement_confirmed' then 'تسوية دين'
    when 'trade_edited' then 'تعديل عملية'
    when 'trade_deleted' then 'حذف عملية'
    else 'عملية مسجّلة'
  end;
$fn$;

revoke all on function private.audit_trail_action_label(text)
  from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;

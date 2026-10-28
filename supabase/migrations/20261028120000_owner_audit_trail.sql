-- AUD-01 owner audit browser. Read-only feed over existing append-only
-- public.financial_audit_events. No second history, no financial post, no
-- media kind. Other append-only domains stay out of this feed: identity,
-- grant, invoice appearance/message, closing delegation, support inquiries,
-- and ledger_trade_change_audits (trade edit/delete already land here as
-- trade_edited / trade_deleted).
begin;

create index financial_audit_events_shop_feed_idx
  on public.financial_audit_events (shop_id, created_at desc, id desc);

-- Owner of this shop, accepted session, non-anonymous, entitlement already
-- started. Expiry does not remove the read (D13). Partners, employees and
-- count-only assignments are not owners.
create function private.audit_trail_owner_visible(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select auth.uid() is not null
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
    )
    and private.is_shop_owner(p_shop_id)
    and exists (
      select 1
      from public.shop_entitlements as entitlement
      where entitlement.shop_id = p_shop_id
        and entitlement.starts_at <= pg_catalog.now()
    );
$fn$;

revoke all on function private.audit_trail_owner_visible(uuid) from public, anon;
grant execute on function private.audit_trail_owner_visible(uuid) to authenticated;

drop policy if exists financial_audit_events_select_opening
  on public.financial_audit_events;
create policy financial_audit_events_select_owner
  on public.financial_audit_events
  for select
  to authenticated
  using (private.audit_trail_owner_visible(shop_id));

create function private.audit_trail_family(p_action text)
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
    when 'expense_confirmed' then 'deduction'
    when 'inventory_removal_confirmed' then 'deduction'
    when 'sale_return_confirmed' then 'deduction'
    when 'purchase_return_confirmed' then 'deduction'
    else 'post'
  end;
$fn$;

create function private.audit_trail_action_label(p_action text)
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
    when 'ledger_correction_confirmed' then 'تصحيح دفتر'
    when 'exchange_confirmed' then 'استبدال'
    when 'repair_fee_confirmed' then 'أجرة صيانة'
    when 'debt_settlement_confirmed' then 'تسوية دين'
    when 'trade_edited' then 'تعديل عملية'
    when 'trade_deleted' then 'حذف عملية'
    else 'عملية مسجّلة'
  end;
$fn$;

-- Whitelisted compact summary. Free-text detail keys (phones, emails,
-- exception text, count snapshots, object keys) are never copied.
create function private.audit_trail_summary(
  p_action text,
  p_details jsonb,
  p_sequence bigint,
  p_date date
)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_details jsonb := coalesce(p_details, '{}'::jsonb);
  v_parts text[] := array[]::text[];
  v_channel text;
  v_piastres text;
begin
  if pg_catalog.jsonb_typeof(v_details) is distinct from 'object' then
    v_details := '{}'::jsonb;
  end if;
  if p_sequence is not null then
    v_parts := pg_catalog.array_append(v_parts, 'تسلسل ' || p_sequence::text);
  end if;
  if p_date is not null then
    v_parts := pg_catalog.array_append(
      v_parts, pg_catalog.to_char(p_date, 'YYYY-MM-DD')
    );
  end if;
  if p_action = 'trade_edited' and v_details ? 'replacement_operation_id' then
    v_parts := pg_catalog.array_append(v_parts, 'مع عملية بديلة');
  elsif p_action = 'trade_deleted' then
    v_parts := pg_catalog.array_append(v_parts, 'حذف دون بديل');
  elsif p_action = 'business_day_closed' then
    v_parts := pg_catalog.array_append(v_parts, 'جرد الإغلاق مسجّل');
  end if;
  if pg_catalog.jsonb_typeof(v_details -> 'has_attachment') = 'boolean' then
    v_parts := pg_catalog.array_append(
      v_parts,
      case
        when (v_details ->> 'has_attachment')::boolean then 'مع مرفق'
        else 'بدون مرفق'
      end
    );
  end if;
  v_channel := v_details ->> 'channel';
  if v_channel = 'whatsapp' then
    v_parts := pg_catalog.array_append(v_parts, 'واتساب');
  end if;
  v_piastres := v_details ->> 'cash_refund_piastres';
  if v_piastres ~ '^[0-9]+$' then
    v_parts := pg_catalog.array_append(
      v_parts, 'استرداد نقدي ' || v_piastres || ' قرش'
    );
  end if;
  v_piastres := v_details ->> 'cancelled_payable_piastres';
  if v_piastres ~ '^[0-9]+$' then
    v_parts := pg_catalog.array_append(
      v_parts, 'ملغى من الآجل ' || v_piastres || ' قرش'
    );
  end if;
  if pg_catalog.cardinality(v_parts) = 0 then
    return 'سجل مالي';
  end if;
  return pg_catalog.array_to_string(v_parts, ' · ');
end;
$fn$;

create function private.audit_trail_actor_name(p_shop uuid, p_actor uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(
    nullif(pg_catalog.btrim(identity.raw_user_meta_data ->> 'display_name'), ''),
    case
      when membership.role = 'owner'
        then nullif(pg_catalog.btrim(shop.owner_display_name), '')
    end
  )
  from public.shops as shop
  left join auth.users as identity on identity.id = p_actor
  left join public.shop_memberships as membership
    on membership.shop_id = p_shop
   and membership.user_id = p_actor
  where shop.id = p_shop;
$fn$;

revoke all on function private.audit_trail_family(text) from public, anon, authenticated;
revoke all on function private.audit_trail_action_label(text) from public, anon, authenticated;
revoke all on function private.audit_trail_summary(text, jsonb, bigint, date)
  from public, anon, authenticated;
revoke all on function private.audit_trail_actor_name(uuid, uuid)
  from public, anon, authenticated;

create function public.list_shop_audit_trail_v1(
  p_family text default null,
  p_before_at timestamptz default null,
  p_before_id uuid default null,
  p_limit integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_size integer;
  v_result jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_family is not null
    and p_family not in ('change', 'delete', 'deduction', 'post') then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_shop := private.require_shop_owner();
  select private.shop_display_zone(shop.time_zone)
    into v_zone
  from public.shops as shop
  where shop.id = v_shop;

  if p_before_id is not null then
    if p_before_at is null then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
    if not exists (
      select 1
      from public.financial_audit_events as event
      where event.shop_id = v_shop
        and event.id = p_before_id
        and event.created_at = p_before_at
        and (
          p_family is null
          or private.audit_trail_family(event.action) = p_family
        )
    ) then
      raise exception 'stale_cursor' using errcode = 'P0001';
    end if;
  elsif p_before_at is not null then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  v_size := least(greatest(coalesce(p_limit, 20), 1), 50);

  with page as (
    select
      event.id,
      event.action,
      event.actor_user_id,
      event.created_at,
      event.operation_id,
      event.details,
      operation.shop_sequence,
      day.business_date
    from public.financial_audit_events as event
    join public.financial_operations as operation
      on operation.shop_id = event.shop_id
     and operation.id = event.operation_id
    join public.business_days as day
      on day.shop_id = operation.shop_id
     and day.id = operation.business_day_id
    where event.shop_id = v_shop
      and (
        p_family is null
        or private.audit_trail_family(event.action) = p_family
      )
      and (
        p_before_id is null
        or event.created_at < p_before_at
        or (event.created_at = p_before_at and event.id < p_before_id)
      )
    order by event.created_at desc, event.id desc
    limit v_size + 1
  ),
  numbered as (
    select
      pg_catalog.jsonb_build_object(
        'id', entry.id,
        'action', entry.action,
        'action_label', private.audit_trail_action_label(entry.action),
        'action_family', private.audit_trail_family(entry.action),
        'actor_user_id', entry.actor_user_id,
        'actor_display_name', private.audit_trail_actor_name(v_shop, entry.actor_user_id),
        'created_at', entry.created_at,
        'created_at_shop', pg_catalog.to_char(
          entry.created_at at time zone v_zone, 'YYYY-MM-DD HH24:MI:SS'
        ),
        'operation_id', entry.operation_id,
        'shop_sequence', entry.shop_sequence::text,
        'business_date', entry.business_date::text,
        'summary', private.audit_trail_summary(
          entry.action, entry.details, entry.shop_sequence, entry.business_date
        )
      ) as entry,
      entry.created_at,
      entry.id,
      row_number() over (order by entry.created_at desc, entry.id desc) as rn
    from page as entry
  )
  select pg_catalog.jsonb_build_object(
    'entries', coalesce((
      select pg_catalog.jsonb_agg(numbered.entry order by numbered.rn)
      from numbered
      where numbered.rn <= v_size
    ), '[]'::jsonb),
    'next_cursor_at', case
      when exists (select 1 from numbered where rn = v_size + 1)
      then (select created_at from numbered where rn = v_size)
    end,
    'next_cursor_id', case
      when exists (select 1 from numbered where rn = v_size + 1)
      then (select id from numbered where rn = v_size)
    end,
    'time_zone', v_zone,
    'snapshot_at', pg_catalog.now()
  )
  into v_result;
  return v_result;
end;
$fn$;

revoke all on function public.list_shop_audit_trail_v1(text, timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.list_shop_audit_trail_v1(text, timestamptz, uuid, integer)
  to authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.list_shop_audit_trail_v1(text, timestamptz, uuid, integer) from service_role';
    execute 'revoke all on function private.audit_trail_owner_visible(uuid) from service_role';
    execute 'revoke all on function private.audit_trail_actor_name(uuid, uuid) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

-- ADR 0033 staff grants: restore the grant declaration on entry points that
-- lost it or never had it, found by the 2026-11-15 end-to-end staff run.
--
-- `private.opening_require_reader_shop()` admits a partner or employee only
-- when the caller first declares the required grant with
-- `private.allow_member_permission`. These entry points never declared one,
-- so every partner and employee got `forbidden` even with the grant:
--
-- * post_daily_ledger_trade (sale, purchase, expense, scrap sale; the path
--   the app uses for every trade). Only post_daily_ledger_trade_v2 was wrapped.
-- * get_inventory_totals_v1 (its 2026-10-26 wrapper was replaced the same day
--   by `create or replace` in 20261026130000).
-- * get_ledger_day_v1 and get_ledger_operation_page_v2 (written after ADR 0033).
-- * the invoice presentation, source, dispatch and pending-send reads and the
--   presentation command (only confirm_invoice_whatsapp_send was wrapped).
--
-- The declared grant is a transaction-local setting. These wrappers restore
-- the previous value when they return, so a later owner-only call in the same
-- transaction never inherits it.
--
-- Owners are unaffected: the gate returns before the grant check. Employees
-- stay limited to their own operations wherever the wrapped body does not
-- already filter them. Day close, opening, customers, debts, repairs, traders,
-- notes, payment-method and profile settings stay owner-only.

begin;

-- Declares a grant for the duration of one wrapper call; returns the value to restore.
-- A null grant keeps whatever an enclosing wrapper declared.
create or replace function private.begin_member_permission(p_permission text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_prev text := coalesce(pg_catalog.current_setting('app.required_shop_permission', true), '');
begin
  if p_permission is not null then
    perform private.allow_member_permission(p_permission);
  end if;
  return v_prev;
end;
$fn$;
revoke all on function private.begin_member_permission(text) from public, anon;
grant execute on function private.begin_member_permission(text) to authenticated;

create or replace function private.end_member_permission(p_previous text)
returns void
language sql
volatile
security definer
set search_path = ''
as $fn$
  select pg_catalog.set_config('app.required_shop_permission', coalesce(p_previous, ''), true);
$fn$;
revoke all on function private.end_member_permission(text) from public, anon;
grant execute on function private.end_member_permission(text) to authenticated;

-- An employee may act only on operations they recorded; partners and owners on
-- any operation of their shop. Unknown operations are left to the wrapped body.
create or replace function private.staff_operation_allowed(p_operation_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_actor uuid;
begin
  select membership.shop_id into v_shop
  from public.shop_memberships as membership
  where membership.user_id = auth.uid()
    and membership.revoked_at is null
    and membership.role = 'employee';
  if v_shop is null then
    return true;
  end if;
  select operation.actor_user_id into v_actor
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  return v_actor is null or v_actor = auth.uid();
end;
$fn$;
revoke all on function private.staff_operation_allowed(uuid) from public, anon;
grant execute on function private.staff_operation_allowed(uuid) to authenticated;

create or replace function private.caller_is_employee()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1 from public.shop_memberships as membership
    where membership.user_id = auth.uid()
      and membership.revoked_at is null
      and membership.role = 'employee'
  );
$fn$;
revoke all on function private.caller_is_employee() from public, anon;
grant execute on function private.caller_is_employee() to authenticated;

-- Reads the operation id an invoice payload names, or null.
create or replace function private.payload_operation_id(p_payload jsonb)
returns uuid
language plpgsql
immutable
set search_path = ''
as $fn$
begin
  return (p_payload ->> 'operation_id')::uuid;
exception when others then
  return null;
end;
$fn$;
revoke all on function private.payload_operation_id(jsonb) from public, anon;
grant execute on function private.payload_operation_id(jsonb) to authenticated;

-- Trades: the grant follows the payload kind, as in post_daily_ledger_trade_v2.
-- Any other kind declares nothing, so staff fail closed unless an enclosing
-- wrapper (for example post_daily_ledger_return) already declared a grant.
alter function public.post_daily_ledger_trade(uuid, jsonb)
  rename to post_daily_ledger_trade_before_grant_fix;
revoke all on function public.post_daily_ledger_trade_before_grant_fix(uuid, jsonb)
  from public, anon, authenticated;

create function public.post_daily_ledger_trade(
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
  v_prev text;
  v_result jsonb;
begin
  v_prev := private.begin_member_permission(case p_payload ->> 'kind'
    when 'sale' then 'sale'
    when 'scrap_sale' then 'sale'
    when 'purchase' then 'purchase'
    when 'expense' then 'expense'
    else null
  end);
  v_result := public.post_daily_ledger_trade_before_grant_fix(p_idempotency_key, p_payload);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.post_daily_ledger_trade(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_trade(uuid, jsonb) to authenticated;

-- Inventory totals: restore the 2026-10-26 `inventory` grant.
alter function public.get_inventory_totals_v1(text, smallint)
  rename to get_inventory_totals_v1_before_grant_fix;
revoke all on function public.get_inventory_totals_v1_before_grant_fix(text, smallint)
  from public, anon, authenticated;

create function public.get_inventory_totals_v1(
  p_category text default null,
  p_karat smallint default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_prev text := private.begin_member_permission('inventory');
  v_result jsonb;
begin
  v_result := public.get_inventory_totals_v1_before_grant_fix(p_category, p_karat);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_inventory_totals_v1(text, smallint) from public, anon;
grant execute on function public.get_inventory_totals_v1(text, smallint) to authenticated;

-- Closed-day ledger: built on get_ledger_date_v2, which already limits an
-- employee to their own operations and omits shop balances.
alter function public.get_ledger_day_v1(uuid, text, integer)
  rename to get_ledger_day_v1_before_grant_fix;
revoke all on function public.get_ledger_day_v1_before_grant_fix(uuid, text, integer)
  from public, anon, authenticated;

create function public.get_ledger_day_v1(
  p_day_id uuid,
  p_before_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_prev text := private.begin_member_permission('ledger_read');
  v_result jsonb;
begin
  v_result := public.get_ledger_day_v1_before_grant_fix(p_day_id, p_before_sequence, p_limit);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_ledger_day_v1(uuid, text, integer) from public, anon;
grant execute on function public.get_ledger_day_v1(uuid, text, integer) to authenticated;

-- Operation pages read every operation of a day, so employees stay refused.
alter function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  rename to get_ledger_operation_page_v2_before_grant_fix;
revoke all on function public.get_ledger_operation_page_v2_before_grant_fix(uuid, text, text, integer)
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
declare
  v_prev text;
  v_result jsonb;
begin
  if private.caller_is_employee() then
    raise exception 'forbidden';
  end if;
  v_prev := private.begin_member_permission('ledger_read');
  v_result := public.get_ledger_operation_page_v2_before_grant_fix(
    p_day_id, p_before_sequence, p_after_sequence, p_limit
  );
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  from public, anon;
grant execute on function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  to authenticated;

-- Invoices: `invoice_send`, and an employee only for their own sales.
alter function public.get_invoice_presentations_v1(uuid)
  rename to get_invoice_presentations_v1_before_grant_fix;
revoke all on function public.get_invoice_presentations_v1_before_grant_fix(uuid)
  from public, anon, authenticated;
create function public.get_invoice_presentations_v1(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  if not private.staff_operation_allowed(p_operation_id) then raise exception 'forbidden'; end if;
  v_result := public.get_invoice_presentations_v1_before_grant_fix(p_operation_id);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_presentations_v1(uuid) from public, anon;
grant execute on function public.get_invoice_presentations_v1(uuid) to authenticated;

alter function public.get_invoice_presentation_v1(uuid, bigint)
  rename to get_invoice_presentation_v1_before_grant_fix;
revoke all on function public.get_invoice_presentation_v1_before_grant_fix(uuid, bigint)
  from public, anon, authenticated;
create function public.get_invoice_presentation_v1(p_operation_id uuid, p_edition bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  if not private.staff_operation_allowed(p_operation_id) then raise exception 'forbidden'; end if;
  v_result := public.get_invoice_presentation_v1_before_grant_fix(p_operation_id, p_edition);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_presentation_v1(uuid, bigint) from public, anon;
grant execute on function public.get_invoice_presentation_v1(uuid, bigint) to authenticated;

alter function public.get_invoice_dispatch_state(uuid)
  rename to get_invoice_dispatch_state_before_grant_fix;
revoke all on function public.get_invoice_dispatch_state_before_grant_fix(uuid)
  from public, anon, authenticated;
create function public.get_invoice_dispatch_state(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  if not private.staff_operation_allowed(p_operation_id) then raise exception 'forbidden'; end if;
  v_result := public.get_invoice_dispatch_state_before_grant_fix(p_operation_id);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_dispatch_state(uuid) from public, anon;
grant execute on function public.get_invoice_dispatch_state(uuid) to authenticated;

alter function public.get_invoice_brand_source_v1(uuid)
  rename to get_invoice_brand_source_v1_before_grant_fix;
revoke all on function public.get_invoice_brand_source_v1_before_grant_fix(uuid)
  from public, anon, authenticated;
create function public.get_invoice_brand_source_v1(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  if not private.staff_operation_allowed(p_operation_id) then raise exception 'forbidden'; end if;
  v_result := public.get_invoice_brand_source_v1_before_grant_fix(p_operation_id);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_brand_source_v1(uuid) from public, anon;
grant execute on function public.get_invoice_brand_source_v1(uuid) to authenticated;

alter function public.get_invoice_message_source_v1(uuid)
  rename to get_invoice_message_source_v1_before_grant_fix;
revoke all on function public.get_invoice_message_source_v1_before_grant_fix(uuid)
  from public, anon, authenticated;
create function public.get_invoice_message_source_v1(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  if not private.staff_operation_allowed(p_operation_id) then raise exception 'forbidden'; end if;
  v_result := public.get_invoice_message_source_v1_before_grant_fix(p_operation_id);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_message_source_v1(uuid) from public, anon;
grant execute on function public.get_invoice_message_source_v1(uuid) to authenticated;

alter function public.get_invoice_appearance_v1()
  rename to get_invoice_appearance_v1_before_grant_fix;
revoke all on function public.get_invoice_appearance_v1_before_grant_fix()
  from public, anon, authenticated;
create function public.get_invoice_appearance_v1()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  v_result := public.get_invoice_appearance_v1_before_grant_fix();
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_appearance_v1() from public, anon;
grant execute on function public.get_invoice_appearance_v1() to authenticated;

alter function public.get_invoice_message_v1()
  rename to get_invoice_message_v1_before_grant_fix;
revoke all on function public.get_invoice_message_v1_before_grant_fix()
  from public, anon, authenticated;
create function public.get_invoice_message_v1()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  v_result := public.get_invoice_message_v1_before_grant_fix();
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_message_v1() from public, anon;
grant execute on function public.get_invoice_message_v1() to authenticated;

alter function public.post_invoice_presentation_v2(uuid, jsonb)
  rename to post_invoice_presentation_v2_before_grant_fix;
revoke all on function public.post_invoice_presentation_v2_before_grant_fix(uuid, jsonb)
  from public, anon, authenticated;
create function public.post_invoice_presentation_v2(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_operation uuid := private.payload_operation_id(p_payload);
  v_result jsonb;
begin
  if v_operation is not null and not private.staff_operation_allowed(v_operation) then
    raise exception 'forbidden';
  end if;
  v_result := public.post_invoice_presentation_v2_before_grant_fix(p_idempotency_key, p_payload);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.post_invoice_presentation_v2(uuid, jsonb) from public, anon;
grant execute on function public.post_invoice_presentation_v2(uuid, jsonb) to authenticated;

alter function public.get_invoice_presentation_status_v1(uuid, jsonb)
  rename to get_invoice_presentation_status_v1_before_grant_fix;
revoke all on function public.get_invoice_presentation_status_v1_before_grant_fix(uuid, jsonb)
  from public, anon, authenticated;
create function public.get_invoice_presentation_status_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_operation uuid := private.payload_operation_id(p_payload);
  v_result jsonb;
begin
  if v_operation is not null and not private.staff_operation_allowed(v_operation) then
    raise exception 'forbidden';
  end if;
  v_result := public.get_invoice_presentation_status_v1_before_grant_fix(p_idempotency_key, p_payload);
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_invoice_presentation_status_v1(uuid, jsonb) from public, anon;
grant execute on function public.get_invoice_presentation_status_v1(uuid, jsonb) to authenticated;

-- Pending sends: an employee sees only their own sales in the queue.
alter function public.get_pending_invoice_sends(bigint)
  rename to get_pending_invoice_sends_before_grant_fix;
revoke all on function public.get_pending_invoice_sends_before_grant_fix(bigint)
  from public, anon, authenticated;
create function public.get_pending_invoice_sends(p_before_sequence bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  v_result := public.get_pending_invoice_sends_before_grant_fix(p_before_sequence);
  if private.caller_is_employee() then
    v_result := pg_catalog.jsonb_set(v_result, '{items}', coalesce((
      select pg_catalog.jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
      from pg_catalog.jsonb_array_elements(v_result -> 'items') as item
      where private.staff_operation_allowed((item ->> 'operation_id')::uuid)
    ), '[]'::jsonb));
  end if;
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;
revoke all on function public.get_pending_invoice_sends(bigint) from public, anon;
grant execute on function public.get_pending_invoice_sends(bigint) to authenticated;

-- The existing dispatch confirmation wrapper gains the employee own-sale rule
-- and the same scoped grant.
create or replace function public.confirm_invoice_whatsapp_send(
  p_operation_id uuid,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_prev text := private.begin_member_permission('invoice_send');
  v_result jsonb;
begin
  if not private.staff_operation_allowed(p_operation_id) then
    raise exception 'forbidden';
  end if;
  v_result := public.confirm_invoice_whatsapp_send_before_staff(
    p_operation_id, p_idempotency_key
  );
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;

notify pgrst, 'reload schema';
commit;

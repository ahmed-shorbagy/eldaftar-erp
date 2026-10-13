-- DEBT-01. Standalone debts are reviewed historical declarations with no
-- cash, stock, or custody journal. Linked purchase cash payables and gold
-- obligations stay the authoritative balances; this module reads them live.
-- A source settlement calls the existing purchase-cash or gold-obligation
-- command under the locks already held here. That keeps the original
-- operation kind and link payload, and it updates the balance once. The debt
-- registry stores the full debt envelope and does not post a second
-- settlement. A standalone move still uses debt_settlement. A standalone
-- no-ledger settlement posts nothing. Incoming gold is an owned receipt.
-- Custody return duty is separate.
begin;

select private.compensation_extend_in_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  array['debt_settlement']
);
select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  array['debt_settlement_confirmed']
);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  array['debt_settlement_confirmed']
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

alter table public.shop_sync_signals
  add column debt_revision bigint not null default 0
  check (debt_revision >= 0);

create or replace function private.bump_shop_sync(p_shop_id uuid, p_scope text)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if p_shop_id is null or p_scope is null then
    return;
  end if;
  if not exists (select 1 from public.shops as shop where shop.id = p_shop_id) then
    return;
  end if;
  insert into public.shop_sync_signals (
    shop_id, revision, ledger_revision, inventory_revision, trader_revision,
    invoice_revision, day_revision, location_revision, subscription_revision,
    repair_revision, debt_revision, updated_at
  ) values (
    p_shop_id, 1,
    case when p_scope = 'ledger' then 1 else 0 end,
    case when p_scope = 'inventory' then 1 else 0 end,
    case when p_scope = 'trader' then 1 else 0 end,
    case when p_scope = 'invoice' then 1 else 0 end,
    case when p_scope = 'day' then 1 else 0 end,
    case when p_scope = 'location' then 1 else 0 end,
    case when p_scope = 'subscription' then 1 else 0 end,
    case when p_scope = 'repair' then 1 else 0 end,
    case when p_scope = 'debt' then 1 else 0 end,
    pg_catalog.clock_timestamp()
  )
  on conflict (shop_id) do update
    set revision = public.shop_sync_signals.revision + 1,
        ledger_revision = public.shop_sync_signals.ledger_revision
          + case when p_scope = 'ledger' then 1 else 0 end,
        inventory_revision = public.shop_sync_signals.inventory_revision
          + case when p_scope = 'inventory' then 1 else 0 end,
        trader_revision = public.shop_sync_signals.trader_revision
          + case when p_scope = 'trader' then 1 else 0 end,
        invoice_revision = public.shop_sync_signals.invoice_revision
          + case when p_scope = 'invoice' then 1 else 0 end,
        day_revision = public.shop_sync_signals.day_revision
          + case when p_scope = 'day' then 1 else 0 end,
        location_revision = public.shop_sync_signals.location_revision
          + case when p_scope = 'location' then 1 else 0 end,
        subscription_revision = public.shop_sync_signals.subscription_revision
          + case when p_scope = 'subscription' then 1 else 0 end,
        repair_revision = public.shop_sync_signals.repair_revision
          + case when p_scope = 'repair' then 1 else 0 end,
        debt_revision = public.shop_sync_signals.debt_revision
          + case when p_scope = 'debt' then 1 else 0 end,
        updated_at = pg_catalog.clock_timestamp();
end;
$fn$;

create or replace function private.shop_sync_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_scope text;
begin
  if tg_table_name = 'shops' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    v_shop := new.id;
  elsif tg_op = 'DELETE' then
    v_shop := old.shop_id;
  else
    v_shop := new.shop_id;
  end if;
  v_scope := case tg_table_name
    when 'shops' then 'location'
    when 'shop_memberships' then 'location'
    when 'shop_entitlements' then 'subscription'
    when 'business_days' then 'day'
    when 'invoice_dispatch_confirmations' then 'invoice'
    when 'inventory_lots' then 'inventory'
    when 'inventory_lot_movements' then 'inventory'
    when 'inventory_receipts' then 'inventory'
    when 'inventory_lot_sync' then 'inventory'
    when 'inventory_products' then 'inventory'
    when 'bullion_denominations' then 'inventory'
    when 'coin_types' then 'inventory'
    when 'traders' then 'trader'
    when 'gold_obligations' then 'trader'
    when 'repairs' then 'repair'
    when 'repair_events' then 'repair'
    when 'repair_custody_events' then 'repair'
    when 'shop_debts' then 'debt'
    when 'debt_events' then 'debt'
    else 'ledger'
  end;
  perform private.bump_shop_sync(v_shop, v_scope);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$fn$;

create table public.shop_debts (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  status text not null,
  record_version bigint not null,
  direction text not null,
  unit text not null,
  karat smallint,
  original_amount bigint not null,
  settled_amount bigint not null,
  remaining_amount bigint not null,
  party_name text not null,
  contact_phone text not null,
  reason text not null,
  external_reference text,
  declaration_payload jsonb not null,
  created_at timestamptz not null,
  actor_user_id uuid not null,
  updated_at timestamptz not null,
  cancellation_reason text,
  archived_from_status text,
  constraint shop_debts_status_check check (status in ('open', 'cancelled', 'archived')),
  constraint shop_debts_version_check check (record_version >= 1),
  constraint shop_debts_direction_check check (direction in ('shop_owes', 'owed_to_shop')),
  constraint shop_debts_unit_check check (unit in ('money', 'gold')),
  constraint shop_debts_karat_check check (
    (unit = 'money' and karat is null)
    or (
      unit = 'gold'
      and karat is not null
      and karat in (14, 18, 21, 22, 24)
    )
  ),
  constraint shop_debts_amounts_check check (
    original_amount > 0
    and settled_amount >= 0
    and settled_amount <= original_amount
    and remaining_amount >= 0
    and (
      (status = 'cancelled' and settled_amount = 0 and remaining_amount = 0)
      or (
        status = 'archived'
        and archived_from_status = 'cancelled'
        and settled_amount = 0
        and remaining_amount = 0
      )
      or (remaining_amount = original_amount - settled_amount)
    )
  ),
  constraint shop_debts_party_check check (char_length(party_name) between 1 and 200),
  constraint shop_debts_phone_check check (
    char_length(contact_phone) <= 20
    and (contact_phone = '' or contact_phone ~ '^\+?[0-9]{7,15}$')
  ),
  constraint shop_debts_reason_check check (char_length(reason) between 1 and 500),
  constraint shop_debts_external_check check (
    external_reference is null or char_length(external_reference) between 1 and 80
  ),
  constraint shop_debts_payload_check check (jsonb_typeof(declaration_payload) = 'object'),
  constraint shop_debts_cancel_reason_check check (
    cancellation_reason is null or char_length(cancellation_reason) between 1 and 500
  ),
  constraint shop_debts_archive_source_check check (
    archived_from_status is null
    or archived_from_status in ('open', 'cancelled')
  ),
  constraint shop_debts_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create unique index shop_debts_external_uidx
  on public.shop_debts (shop_id, external_reference)
  where external_reference is not null;
create index shop_debts_shop_created_idx
  on public.shop_debts (shop_id, created_at desc, id desc);
create index shop_debts_actor_idx
  on public.shop_debts (shop_id, actor_user_id);

create table public.debt_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  source_kind text not null,
  source_id uuid not null,
  event_type text not null,
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  payload jsonb not null,
  constraint debt_events_kind_check check (
    source_kind in ('standalone', 'purchase_cash_payable', 'gold_obligation')
  ),
  constraint debt_events_type_check check (
    event_type in ('declared', 'settled', 'cancelled', 'archived')
  ),
  constraint debt_events_payload_check check (jsonb_typeof(payload) = 'object'),
  constraint debt_events_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);
create index debt_events_source_idx
  on public.debt_events (shop_id, source_kind, source_id, created_at, id);
create index debt_events_actor_idx
  on public.debt_events (shop_id, actor_user_id);

create table public.debt_command_requests (
  shop_id uuid not null references public.shops (id),
  idempotency_key uuid not null,
  command_kind text not null,
  payload_canonical jsonb not null,
  payload_sha256 bytea not null,
  source_kind text not null,
  source_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null,
  primary key (shop_id, idempotency_key),
  constraint debt_command_requests_kind_check check (
    command_kind in ('debt_declare', 'debt_settle', 'debt_cancel', 'debt_archive')
  ),
  constraint debt_command_requests_source_check check (
    source_kind in ('standalone', 'purchase_cash_payable', 'gold_obligation')
  ),
  constraint debt_command_requests_payload_check check (
    jsonb_typeof(payload_canonical) = 'object' and jsonb_typeof(result) = 'object'
  )
);

create table public.debt_source_archives (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  source_kind text not null,
  source_id uuid not null,
  reason text not null,
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  payload jsonb not null,
  constraint debt_source_archives_kind_check check (
    source_kind in ('purchase_cash_payable', 'gold_obligation')
  ),
  constraint debt_source_archives_reason_check check (char_length(reason) between 1 and 500),
  constraint debt_source_archives_payload_check check (jsonb_typeof(payload) = 'object'),
  constraint debt_source_archives_unique unique (shop_id, source_kind, source_id),
  constraint debt_source_archives_operation_fkey
    foreign key (shop_id, source_id)
    references public.financial_operations (shop_id, id),
  constraint debt_source_archives_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);
create index debt_source_archives_operation_idx
  on public.debt_source_archives (shop_id, source_id);
create index debt_source_archives_actor_idx
  on public.debt_source_archives (shop_id, actor_user_id);

create table public.debt_settlement_references (
  shop_id uuid not null references public.shops (id),
  settlement_reference uuid not null,
  source_kind text not null,
  source_id uuid not null,
  idempotency_key uuid not null,
  amount bigint not null,
  unit text not null,
  created_at timestamptz not null,
  primary key (shop_id, settlement_reference),
  constraint debt_settlement_references_kind_check check (
    source_kind in ('standalone', 'purchase_cash_payable', 'gold_obligation')
  ),
  constraint debt_settlement_references_amount_check check (amount > 0),
  constraint debt_settlement_references_unit_check check (unit in ('money', 'gold'))
);
create index debt_settlement_source_idx
  on public.debt_settlement_references (shop_id, source_kind, source_id);

create function private.debt_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'audit_append_only';
  end if;
  if tg_op = 'INSERT' then
    if new.status is distinct from 'open'
      or new.record_version <> 1
      or new.settled_amount <> 0
      or new.remaining_amount is distinct from new.original_amount
      or new.cancellation_reason is not null
      or new.archived_from_status is not null then
      raise exception 'invalid_input';
    end if;
    return new;
  end if;
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.direction is distinct from old.direction
    or new.unit is distinct from old.unit
    or new.karat is distinct from old.karat
    or new.original_amount is distinct from old.original_amount
    or new.party_name is distinct from old.party_name
    or new.contact_phone is distinct from old.contact_phone
    or new.reason is distinct from old.reason
    or new.external_reference is distinct from old.external_reference
    or new.declaration_payload is distinct from old.declaration_payload
    or new.created_at is distinct from old.created_at
    or new.actor_user_id is distinct from old.actor_user_id then
    raise exception 'audit_append_only';
  end if;
  if new.record_version is distinct from old.record_version + 1 then
    raise exception 'invalid_input';
  end if;
  if new.settled_amount < old.settled_amount
    or new.settled_amount > new.original_amount then
    raise exception 'invalid_input';
  end if;
  if old.status = 'open' and new.status not in ('open', 'cancelled', 'archived') then
    raise exception 'invalid_input';
  end if;
  if old.status = 'cancelled' and new.status not in ('cancelled', 'archived') then
    raise exception 'invalid_input';
  end if;
  if old.status = 'archived' and new.status is distinct from 'archived' then
    raise exception 'invalid_input';
  end if;
  if new.status = 'cancelled' and (
    old.status is distinct from 'open'
    or old.settled_amount <> 0
    or new.settled_amount <> 0
    or new.remaining_amount <> 0
    or new.cancellation_reason is null
  ) then
    raise exception 'invalid_input';
  end if;
  if new.cancellation_reason is distinct from old.cancellation_reason
    and not (
      old.cancellation_reason is null
      and new.status = 'cancelled'
      and old.status = 'open'
    ) then
    raise exception 'audit_append_only';
  end if;
  if new.status = 'archived' and old.status is distinct from 'archived' then
    if new.archived_from_status is distinct from old.status then
      raise exception 'invalid_input';
    end if;
  elsif new.archived_from_status is distinct from old.archived_from_status then
    raise exception 'audit_append_only';
  end if;
  if new.status is distinct from 'cancelled' then
    if new.status = 'archived'
      and new.archived_from_status = 'cancelled'
      and new.settled_amount = 0
      and new.remaining_amount = 0 then
      null;
    elsif new.remaining_amount is distinct from (new.original_amount - new.settled_amount) then
      raise exception 'invalid_input';
    end if;
  end if;
  return new;
end;
$fn$;

create trigger shop_debts_guard
before insert or update or delete on public.shop_debts
for each row execute function private.debt_guard();

create function private.debt_reject_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  raise exception 'audit_append_only';
end;
$fn$;

create trigger debt_events_append_only
before update or delete on public.debt_events
for each row execute function private.debt_reject_mutation();
create trigger debt_commands_append_only
before update or delete on public.debt_command_requests
for each row execute function private.debt_reject_mutation();
create trigger debt_source_archives_append_only
before update or delete on public.debt_source_archives
for each row execute function private.debt_reject_mutation();
create trigger debt_settlement_references_append_only
before update or delete on public.debt_settlement_references
for each row execute function private.debt_reject_mutation();

create trigger shop_sync_shop_debts
after insert or update or delete on public.shop_debts
for each row execute function private.shop_sync_touch();
create trigger shop_sync_debt_events
after insert or update or delete on public.debt_events
for each row execute function private.shop_sync_touch();

alter table public.shop_debts enable row level security;
alter table public.shop_debts force row level security;
alter table public.debt_events enable row level security;
alter table public.debt_events force row level security;
alter table public.debt_command_requests enable row level security;
alter table public.debt_command_requests force row level security;
alter table public.debt_source_archives enable row level security;
alter table public.debt_source_archives force row level security;
alter table public.debt_settlement_references enable row level security;
alter table public.debt_settlement_references force row level security;

revoke all on table public.shop_debts from public, anon, authenticated;
revoke all on table public.debt_events from public, anon, authenticated;
revoke all on table public.debt_command_requests from public, anon, authenticated;
revoke all on table public.debt_source_archives from public, anon, authenticated;
revoke all on table public.debt_settlement_references from public, anon, authenticated;
grant select on table public.shop_debts to authenticated;
grant select on table public.debt_events to authenticated;
grant select on table public.debt_command_requests to authenticated;
grant select on table public.debt_source_archives to authenticated;
grant select on table public.debt_settlement_references to authenticated;

create policy shop_debts_owner_read
  on public.shop_debts for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy debt_events_owner_read
  on public.debt_events for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy debt_commands_owner_read
  on public.debt_command_requests for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy debt_source_archives_owner_read
  on public.debt_source_archives for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy debt_settlement_references_owner_read
  on public.debt_settlement_references for select to authenticated
  using (private.opening_financial_visible(shop_id));

create function private.debt_exact_text(p_value jsonb, p_min integer, p_max integer)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
begin
  v_text := private.repair_text(p_value, p_min, p_max);
  if v_text is distinct from (p_value #>> '{}') then
    raise exception 'invalid_input';
  end if;
  return v_text;
end;
$fn$;

create function private.debt_phone(p_value jsonb)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
begin
  v_text := private.debt_exact_text(p_value, 0, 20);
  if v_text <> '' and v_text !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  return v_text;
end;
$fn$;

create function private.debt_karat(p_value jsonb, p_unit text)
returns smallint
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if p_unit = 'money' then
    if p_value is distinct from 'null'::jsonb then
      raise exception 'invalid_input';
    end if;
    return null;
  end if;
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'number'
    or (p_value #>> '{}') !~ '^(14|18|21|22|24)$' then
    raise exception 'invalid_input';
  end if;
  return (p_value #>> '{}')::smallint;
end;
$fn$;

create function private.debt_optional_reference(p_value jsonb)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if p_value is not distinct from 'null'::jsonb then
    return null;
  end if;
  return private.debt_exact_text(p_value, 1, 80);
end;
$fn$;

create function private.debt_claim(p_key uuid, p_payload jsonb, p_kind text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_hash bytea;
  v_request public.debt_command_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_key is null or p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(pg_catalog.convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.debt_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_key
  for update;
  if found then
    if v_request.command_kind = p_kind
      and v_request.payload_canonical = p_payload
      and v_request.payload_sha256 = v_hash then
      return pg_catalog.jsonb_build_object(
        'continue', false,
        'result', v_request.result || pg_catalog.jsonb_build_object('replayed', true)
      );
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  if p_payload -> 'version' is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from p_kind then
    raise exception 'invalid_input';
  end if;
  return pg_catalog.jsonb_build_object(
    'continue', true,
    'shop_id', v_shop,
    'hash', pg_catalog.encode(v_hash, 'hex')
  );
end;
$fn$;

create function private.debt_finish(
  p_shop uuid, p_key uuid, p_kind text, p_payload jsonb, p_hash text,
  p_source_kind text, p_source_id uuid, p_result jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  insert into public.debt_command_requests (
    shop_id, idempotency_key, command_kind, payload_canonical, payload_sha256,
    source_kind, source_id, result, created_at
  ) values (
    p_shop, p_key, p_kind, p_payload, pg_catalog.decode(p_hash, 'hex'),
    p_source_kind, p_source_id, p_result, pg_catalog.clock_timestamp()
  );
  return p_result;
end;
$fn$;

create function private.debt_event(
  p_shop uuid, p_source_kind text, p_source_id uuid, p_type text,
  p_actor uuid, p_name text, p_at timestamptz, p_payload jsonb
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  insert into public.debt_events (
    shop_id, source_kind, source_id, event_type, actor_user_id,
    actor_display_name, created_at, payload
  ) values (
    p_shop, p_source_kind, p_source_id, p_type, p_actor, p_name, p_at, p_payload
  );
end;
$fn$;

create function private.debt_effect(
  p_cash bigint, p_gold bigint, p_count bigint, p_saleable bigint
) returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select pg_catalog.jsonb_build_object(
    'cash_piastres', p_cash::text,
    'gold_milligrams', p_gold::text,
    'gold_count', p_count::text,
    'custody_milligrams', '0',
    'saleable_stock_milligrams', p_saleable::text
  );
$fn$;

create function private.debt_result(
  p_kind text, p_source_kind text, p_source_id uuid, p_direction text,
  p_unit text, p_karat smallint, p_original bigint, p_settled bigint,
  p_cancelled bigint, p_remaining bigint, p_version bigint, p_display text,
  p_ledger text, p_operation uuid, p_effect jsonb
) returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'command_kind', p_kind,
    'source_kind', p_source_kind,
    'source_id', p_source_id,
    'debt_key', p_source_kind || ':' || p_source_id::text,
    'direction', p_direction,
    'unit', p_unit,
    'karat', p_karat,
    'original_amount', p_original::text,
    'settled_amount', p_settled::text,
    'cancelled_amount', p_cancelled::text,
    'remaining_amount', p_remaining::text,
    'record_version', case when p_version is null then null else p_version::text end,
    'display_status', p_display,
    'ledger_effect', p_ledger,
    'operation_id', p_operation
  ) || p_effect;
$fn$;

create function private.debt_lock_day(p_shop uuid, p_day uuid, p_version bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_day public.business_days%rowtype;
begin
  select day.* into v_day
  from public.business_days as day
  where day.shop_id = p_shop and day.id = p_day
  for update;
  if v_day.id is null or v_day.status <> 'open' then
    raise exception 'day_closed';
  end if;
  if v_day.day_version is distinct from p_version then
    raise exception 'stale_day';
  end if;
end;
$fn$;

create function private.debt_post_money(
  p_shop uuid, p_operation uuid, p_direction text, p_tenders jsonb
) returns void
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_tender jsonb;
  v_amount bigint;
  v_account uuid;
  v_sign integer;
begin
  v_sign := case when p_direction = 'shop_owes' then -1 else 1 end;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_tenders) as item(value)
  loop
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres')
    );
    v_account := private.financial_account(
      p_shop, 'cash_method', 'money', null, null, v_tender ->> 'method', false
    );
    if v_account is null then
      raise exception 'invalid_input';
    end if;
    if v_sign < 0 and private.method_balance(p_shop, v_tender ->> 'method', null) < v_amount then
      raise exception 'negative_owned_balance';
    end if;
    perform private.post_account_delta(
      p_shop, p_operation, 'cash_method', 'money', null, null,
      v_tender ->> 'method', v_sign * v_amount, 'movement_money_clearing', false
    );
  end loop;
end;
$fn$;

create function private.debt_delivery_ids(p_deliveries jsonb, p_amount bigint)
returns uuid[]
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_line jsonb;
  v_id uuid;
  v_seen uuid[] := '{}';
  v_sum numeric := 0;
begin
  if pg_catalog.jsonb_typeof(p_deliveries) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_deliveries) not between 1 and 20 then
    raise exception 'invalid_input';
  end if;
  for v_line in
    select value from pg_catalog.jsonb_array_elements(p_deliveries) as item(value)
  loop
    if pg_catalog.jsonb_typeof(v_line) is distinct from 'object'
      or v_line - 'lot_id' - 'milligrams' - 'count' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
    v_id := private.uuid_or_null(v_line -> 'lot_id');
    if v_id is null or v_id = any (v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_id);
    v_sum := v_sum + private.opening_parse_amount(v_line ->> 'milligrams');
  end loop;
  if private.opening_checked_bigint(v_sum) is distinct from p_amount then
    raise exception 'invalid_input';
  end if;
  return v_seen;
end;
$fn$;

create function private.debt_check_receipt(
  p_receipt jsonb, p_karat smallint, p_amount bigint
) returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_category text;
  v_mg bigint;
begin
  if pg_catalog.jsonb_typeof(p_receipt) is distinct from 'object'
    or p_receipt - 'category' - 'product_name' - 'milligrams' - 'count' <> '{}'::jsonb
    or pg_catalog.jsonb_typeof(p_receipt -> 'category') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_category := p_receipt ->> 'category';
  if not private.opening_pair_allowed(v_category, p_karat) then
    raise exception 'unsupported_category_karat';
  end if;
  perform private.debt_exact_text(p_receipt -> 'product_name', 1, 120);
  perform private.category_quantity(p_receipt, v_category, 'milligrams', 'count');
  v_mg := private.opening_checked_bigint(
    private.opening_parse_amount(p_receipt ->> 'milligrams')
  );
  if v_mg is distinct from p_amount then
    raise exception 'invalid_input';
  end if;
end;
$fn$;

create function private.debt_post_gold_out(
  p_shop uuid, p_operation uuid, p_karat smallint, p_amount bigint, p_deliveries jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_line jsonb;
  v_lot public.inventory_lots%rowtype;
  v_mg bigint;
  v_count bigint;
  v_move bigint;
  v_gold bigint := 0;
  v_pieces bigint := 0;
  v_saleable bigint := 0;
begin
  perform private.lock_lots_ordered(
    p_shop, private.debt_delivery_ids(p_deliveries, p_amount)
  );
  for v_line in
    select value from pg_catalog.jsonb_array_elements(p_deliveries) as item(value)
  loop
    select lot.* into v_lot
    from public.inventory_lots as lot
    where lot.shop_id = p_shop and lot.id = (v_line ->> 'lot_id')::uuid;
    if v_lot.id is null or v_lot.stock_class is distinct from 'owned_available'
      or v_lot.karat is distinct from p_karat then
      raise exception 'invalid_input';
    end if;
    select quantity.milligrams, quantity.piece_count into v_mg, v_count
    from private.category_quantity(
      v_line, v_lot.category_code, 'milligrams', 'count'
    ) as quantity;
    v_move := case when v_lot.tracks_count then v_count else 0 end;
    perform private.consume_named_lot(
      p_shop, p_operation, v_lot.id, v_mg, v_move, 'gold_settlement', 'gold_settlement'
    );
    perform private.post_account_delta(
      p_shop, p_operation,
      case when v_lot.category_code = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
      'gold_mg', v_lot.category_code, v_lot.karat, null, -v_mg,
      'movement_gold_clearing', false
    );
    if v_lot.tracks_count then
      perform private.post_account_delta(
        p_shop, p_operation, 'saleable_count', 'count', v_lot.category_code,
        v_lot.karat, null, -v_count, 'movement_count_clearing', false
      );
      v_pieces := v_pieces + v_count;
    end if;
    v_gold := v_gold + v_mg;
    if v_lot.category_code <> 'scrap' then
      v_saleable := v_saleable + v_mg;
    end if;
  end loop;
  if v_gold is distinct from p_amount then
    raise exception 'invalid_input';
  end if;
  return private.debt_effect(0, -v_gold, -v_pieces, -v_saleable);
end;
$fn$;

create function private.debt_post_gold_in(
  p_shop uuid, p_operation uuid, p_karat smallint, p_amount bigint,
  p_party text, p_at timestamptz, p_receipt jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_category text;
  v_name text;
  v_mg bigint;
  v_count bigint;
  v_lot uuid;
  v_product uuid;
  v_receipt uuid;
  v_pieces bigint;
  v_saleable bigint;
begin
  perform private.debt_check_receipt(p_receipt, p_karat, p_amount);
  v_category := p_receipt ->> 'category';
  v_name := private.debt_exact_text(p_receipt -> 'product_name', 1, 120);
  select quantity.milligrams, quantity.piece_count into v_mg, v_count
  from private.category_quantity(
    p_receipt, v_category, 'milligrams', 'count'
  ) as quantity;
  v_lot := private.create_stock_lot(
    p_shop, p_operation, v_name, v_category, p_karat, v_mg, v_count,
    'owned_available', null, false, null, null, 'receipt', 'manual'
  );
  select lot.product_id into v_product
  from public.inventory_lots as lot
  where lot.id = v_lot and lot.shop_id = p_shop;
  insert into public.inventory_receipts (
    shop_id, owner_kind, trader_id, custodian_kind, counterparty_name,
    product_id, lot_id, category_code, karat, milligrams, piece_count,
    received_at, operation_id, recognition_policy
  ) values (
    p_shop, 'shop', null, 'shop', p_party,
    v_product, v_lot, v_category, p_karat, v_mg, v_count,
    p_at, p_operation, 'immediate'
  ) returning id into v_receipt;
  perform private.post_owned_increase(
    p_shop, p_operation, v_category, p_karat, v_mg, v_count, 'movement'
  );
  perform private.insert_receipt_allocation(
    p_shop, v_receipt, p_operation, 'recognize', v_mg, v_count, v_lot
  );
  v_pieces := case when v_category = 'scrap' then 0 else v_count end;
  v_saleable := case when v_category = 'scrap' then 0 else v_mg end;
  return private.debt_effect(0, v_mg, v_pieces, v_saleable);
end;
$fn$;

create function private.debt_operation_effect(p_shop uuid, p_operation uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select private.debt_effect(
    coalesce(sum(posting.amount) filter (
      where account.account_kind = 'cash_method'
    ), 0)::bigint,
    coalesce(sum(posting.amount) filter (
      where account.account_kind in ('saleable_metal', 'scrap_metal')
    ), 0)::bigint,
    coalesce(sum(posting.amount) filter (
      where account.account_kind = 'saleable_count'
    ), 0)::bigint,
    coalesce(sum(posting.amount) filter (
      where account.account_kind = 'saleable_metal'
    ), 0)::bigint
  )
  from public.journal_postings as posting
  join public.ledger_accounts as account
    on account.shop_id = posting.shop_id and account.id = posting.account_id
  where posting.shop_id = p_shop and posting.operation_id = p_operation;
$fn$;

create function private.debt_source_figures(
  p_shop uuid, p_kind text, p_source uuid
) returns table (
  original_amount bigint,
  settled_amount bigint,
  cancelled_amount bigint,
  remaining_amount bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_remaining bigint;
  v_original bigint;
  v_settled bigint;
  v_cancelled bigint;
begin
  if p_kind = 'purchase_cash_payable' then
    select payable.initial_piastres, payable.remaining_piastres into v_original, v_remaining
    from public.purchase_cash_payables as payable
    where payable.shop_id = p_shop and payable.operation_id = p_source;
    if v_remaining is null then
      return;
    end if;
    select coalesce(sum(
      private.opening_checked_bigint(private.opening_parse_amount(tender.value ->> 'piastres'))
    ), 0)::bigint into v_settled
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral pg_catalog.jsonb_array_elements(
      coalesce(detail.payload -> 'tenders', '[]'::jsonb)
    ) as tender(value)
    where operation.shop_id = p_shop
      and operation.kind = 'purchase_settlement'
      and detail.payload ->> 'purchase_operation_id' = p_source::text;
    select coalesce(sum(
      private.opening_checked_bigint(
        private.opening_parse_amount(detail.payload ->> 'cancelled_payable_piastres')
      )
    ), 0)::bigint into v_cancelled
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = p_shop
      and operation.kind = 'purchase_return'
      and detail.payload ->> 'original_operation_id' = p_source::text;
  elsif p_kind = 'gold_obligation' then
    select obligation.initial_milligrams, obligation.remaining_milligrams into v_original, v_remaining
    from public.gold_obligations as obligation
    where obligation.shop_id = p_shop and obligation.operation_id = p_source;
    if v_remaining is null then
      return;
    end if;
    select coalesce(sum(
      private.opening_checked_bigint(private.opening_parse_amount(line.value ->> 'milligrams'))
    ), 0)::bigint into v_settled
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral pg_catalog.jsonb_array_elements(
      coalesce(detail.payload -> 'deliveries', '[]'::jsonb)
    ) as line(value)
    where operation.shop_id = p_shop
      and operation.kind = 'gold_obligation_settlement'
      and detail.payload ->> 'obligation_operation_id' = p_source::text;
    v_cancelled := 0;
  else
    return;
  end if;
  if v_original <> v_settled + v_cancelled + v_remaining then
    raise exception using errcode = 'P0001', message = 'inconsistent_debt_source';
  end if;
  original_amount := v_original;
  settled_amount := v_settled;
  cancelled_amount := v_cancelled;
  remaining_amount := v_remaining;
  return next;
end;
$fn$;

create function private.debt_balances(p_shop uuid)
returns table (
  debt_key text,
  source_kind text,
  source_id uuid,
  direction text,
  unit text,
  karat smallint,
  party_name text,
  contact_phone text,
  reason text,
  external_reference text,
  original_amount bigint,
  settled_amount bigint,
  cancelled_amount bigint,
  remaining_amount bigint,
  display_status text,
  record_version bigint,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $fn$
  select
    'standalone:' || debt.id::text,
    'standalone'::text,
    debt.id,
    debt.direction,
    debt.unit,
    debt.karat,
    debt.party_name,
    debt.contact_phone,
    debt.reason,
    debt.external_reference,
    debt.original_amount,
    debt.settled_amount,
    case
      when debt.status = 'cancelled' then debt.original_amount
      when debt.status = 'archived' and debt.archived_from_status = 'cancelled'
        then debt.original_amount
      else 0
    end,
    debt.remaining_amount,
    case
      when debt.status = 'cancelled' then 'cancelled'
      when debt.status = 'archived' then 'archived'
      when debt.remaining_amount = 0 then 'settled'
      else 'open'
    end,
    debt.record_version,
    debt.created_at
  from public.shop_debts as debt
  where debt.shop_id = p_shop
  union all
  select
    'purchase_cash_payable:' || payable.operation_id::text,
    'purchase_cash_payable',
    payable.operation_id,
    'shop_owes',
    'money',
    null::smallint,
    payable.seller_name,
    coalesce(
      (
        select nullif(detail.payload ->> 'customer_phone', '')
        from public.financial_operation_details as detail
        where detail.shop_id = payable.shop_id
          and detail.operation_id = payable.operation_id
      ),
      (
        select nullif(trader.phone, '')
        from public.traders as trader
        where trader.shop_id = payable.shop_id and trader.id = payable.trader_id
      )
    ),
    'رصيد شراء آجل',
    null::text,
    figures.original_amount,
    figures.settled_amount,
    figures.cancelled_amount,
    figures.remaining_amount,
    case
      when exists (
        select 1 from public.debt_source_archives as archive
        where archive.shop_id = payable.shop_id
          and archive.source_kind = 'purchase_cash_payable'
          and archive.source_id = payable.operation_id
      ) then 'archived'
      when payable.remaining_piastres = 0 then 'settled'
      else 'open'
    end,
    null::bigint,
    payable.created_at
  from public.purchase_cash_payables as payable
  join lateral private.debt_source_figures(
    payable.shop_id, 'purchase_cash_payable', payable.operation_id
  ) as figures on true
  where payable.shop_id = p_shop
  union all
  select
    'gold_obligation:' || obligation.operation_id::text,
    'gold_obligation',
    obligation.operation_id,
    'shop_owes',
    'gold',
    obligation.karat,
    obligation.counterparty_name,
    (
      select nullif(trader.phone, '')
      from public.traders as trader
      where trader.shop_id = obligation.shop_id and trader.id = obligation.trader_id
    ),
    'التزام ذهب',
    null::text,
    figures.original_amount,
    figures.settled_amount,
    figures.cancelled_amount,
    figures.remaining_amount,
    case
      when exists (
        select 1 from public.debt_source_archives as archive
        where archive.shop_id = obligation.shop_id
          and archive.source_kind = 'gold_obligation'
          and archive.source_id = obligation.operation_id
      ) then 'archived'
      when obligation.remaining_milligrams = 0 then 'settled'
      else 'open'
    end,
    null::bigint,
    obligation.created_at
  from public.gold_obligations as obligation
  join lateral private.debt_source_figures(
    obligation.shop_id, 'gold_obligation', obligation.operation_id
  ) as figures on true
  where obligation.shop_id = p_shop;
$fn$;

create function private.debt_history(
  p_shop uuid, p_kind text, p_source uuid, p_zone text
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_rows jsonb;
  v_name text;
begin
  select coalesce(shop.owner_display_name, '') into v_name
  from public.shops as shop
  where shop.id = p_shop;
  select coalesce(pg_catalog.jsonb_agg(entry.row order by entry.created_at, entry.id), '[]'::jsonb)
  into v_rows
  from (
    select
      operation.created_at,
      operation.id,
      pg_catalog.jsonb_build_object(
        'id', operation.id,
        'at', pg_catalog.to_char(operation.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'at_shop', pg_catalog.to_char(operation.created_at at time zone p_zone, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'event_type', case
          when operation.id = p_source then 'posted'
          when operation.kind in ('purchase_return', 'sale_return') then 'linked_return'
          when operation.kind in ('purchase_settlement', 'gold_obligation_settlement') then 'linked_settlement'
          else 'linked'
        end,
        'kind', operation.kind,
        'label_ar', coalesce(private.ledger_operation_label(operation.kind), 'عملية مرتبطة'),
        'actor_user_id', operation.actor_user_id,
        'actor_display_name', v_name,
        'amount', case operation.kind
          when 'purchase_settlement' then coalesce((
            select sum(private.opening_checked_bigint(
              private.opening_parse_amount(tender.value ->> 'piastres')
            ))
            from pg_catalog.jsonb_array_elements(coalesce(detail.payload -> 'tenders', '[]'::jsonb)) as tender(value)
          ), 0)::text
          when 'gold_obligation_settlement' then coalesce((
            select sum(private.opening_checked_bigint(
              private.opening_parse_amount(line.value ->> 'milligrams')
            ))
            from pg_catalog.jsonb_array_elements(coalesce(detail.payload -> 'deliveries', '[]'::jsonb)) as line(value)
          ), 0)::text
          when 'purchase_return' then coalesce(detail.payload ->> 'cancelled_payable_piastres', '0')
          when 'purchase' then coalesce(detail.payload ->> 'purchase_obligation_piastres', '0')
          when 'gold_obligation_acquisition' then coalesce(detail.payload ->> 'obligation_milligrams', '0')
          else '0'
        end,
        'cancelled_amount', case
          when operation.kind = 'purchase_return'
            then coalesce(detail.payload ->> 'cancelled_payable_piastres', '0')
          else '0'
        end,
        'payload', detail.payload
      ) || private.debt_operation_effect(p_shop, operation.id) as row
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where p_kind <> 'standalone'
      and operation.shop_id = p_shop
      and operation.kind is distinct from 'debt_settlement'
      and (
        operation.id = p_source
        or detail.payload ->> 'purchase_operation_id' = p_source::text
        or detail.payload ->> 'obligation_operation_id' = p_source::text
        or detail.payload ->> 'original_operation_id' = p_source::text
      )
    union all
    select
      event.created_at,
      event.id,
      pg_catalog.jsonb_build_object(
        'id', event.id,
        'at', pg_catalog.to_char(event.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'at_shop', pg_catalog.to_char(event.created_at at time zone p_zone, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'event_type', event.event_type,
        'kind', event.event_type,
        'label_ar', case event.event_type
          when 'declared' then 'تسجيل دين'
          when 'settled' then 'سداد دين'
          when 'cancelled' then 'إلغاء دين'
          when 'archived' then 'أرشفة دين'
          else 'حدث دين'
        end,
        'actor_user_id', event.actor_user_id,
        'actor_display_name', event.actor_display_name,
        'amount', case event.event_type
          when 'declared' then coalesce(event.payload ->> 'amount', '0')
          when 'settled' then coalesce(event.payload ->> 'amount', '0')
          else '0'
        end,
        'cancelled_amount', case
          when event.event_type = 'cancelled'
            then coalesce(event.payload ->> 'original_amount', '0')
          else '0'
        end,
        'cash_piastres', coalesce(event.payload ->> 'cash_piastres', '0'),
        'gold_milligrams', coalesce(event.payload ->> 'gold_milligrams', '0'),
        'gold_count', coalesce(event.payload ->> 'gold_count', '0'),
        'custody_milligrams', coalesce(event.payload ->> 'custody_milligrams', '0'),
        'saleable_stock_milligrams', coalesce(event.payload ->> 'saleable_stock_milligrams', '0'),
        'payload', event.payload
      )
    from public.debt_events as event
    where event.shop_id = p_shop
      and event.source_kind = p_kind
      and event.source_id = p_source
      and not (
        event.event_type = 'settled'
        and exists (
          select 1
          from public.financial_operations as operation
          where operation.shop_id = event.shop_id
            and operation.id::text = event.payload ->> 'operation_id'
            and operation.kind in ('purchase_settlement', 'gold_obligation_settlement')
        )
      )
  ) as entry;
  return v_rows;
end;
$fn$;

create function private.debt_declare(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_direction text;
  v_unit text;
  v_karat smallint;
  v_amount bigint;
  v_party text;
  v_phone text;
  v_reason text;
  v_external text;
  v_actor uuid;
  v_name text;
  v_at timestamptz;
  v_id uuid;
  v_result jsonb;
begin
  v_claim := private.debt_claim(p_key, p_payload, 'debt_declare');
  if (v_claim ->> 'continue')::boolean is distinct from true then
    return v_claim -> 'result';
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  perform private.repair_require_keys(p_payload, array[
    'amount', 'contact_phone', 'direction', 'external_reference', 'karat',
    'kind', 'party_name', 'reason', 'unit', 'version'
  ]);
  if pg_catalog.jsonb_typeof(p_payload -> 'direction') is distinct from 'string'
    or p_payload ->> 'direction' not in ('shop_owes', 'owed_to_shop')
    or pg_catalog.jsonb_typeof(p_payload -> 'unit') is distinct from 'string'
    or p_payload ->> 'unit' not in ('money', 'gold') then
    raise exception 'invalid_input';
  end if;
  v_direction := p_payload ->> 'direction';
  v_unit := p_payload ->> 'unit';
  v_karat := private.debt_karat(p_payload -> 'karat', v_unit);
  v_amount := private.repair_money(p_payload -> 'amount', false);
  v_party := private.debt_exact_text(p_payload -> 'party_name', 1, 200);
  v_phone := private.debt_phone(p_payload -> 'contact_phone');
  v_reason := private.debt_exact_text(p_payload -> 'reason', 1, 500);
  v_external := private.debt_optional_reference(p_payload -> 'external_reference');
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select shop.owner_display_name into v_name
  from public.shops as shop where shop.id = v_shop;
  if exists (
    select 1 from public.shop_debts as debt
    where debt.shop_id = v_shop
      and debt.direction = v_direction
      and debt.unit = v_unit
      and debt.karat is not distinct from v_karat
      and debt.original_amount = v_amount
      and debt.party_name = v_party
      and debt.contact_phone = v_phone
      and debt.reason = v_reason
      and debt.external_reference is not distinct from v_external
  ) then
    raise exception 'duplicate_debt';
  end if;
  if v_external is not null and exists (
    select 1
    from public.purchase_cash_payables as payable
    where payable.shop_id = v_shop
      and lower(v_external) in (
        payable.operation_id::text,
        'purchase_cash_payable:' || payable.operation_id::text
      )
    union all
    select 1
    from public.gold_obligations as obligation
    where obligation.shop_id = v_shop
      and lower(v_external) in (
        obligation.operation_id::text,
        'gold_obligation:' || obligation.operation_id::text
      )
  ) then
    raise exception 'duplicate_debt';
  end if;
  begin
    insert into public.shop_debts (
      shop_id, status, record_version, direction, unit, karat,
      original_amount, settled_amount, remaining_amount, party_name,
      contact_phone, reason, external_reference, declaration_payload,
      created_at, actor_user_id, updated_at
    ) values (
      v_shop, 'open', 1, v_direction, v_unit, v_karat,
      v_amount, 0, v_amount, v_party, v_phone, v_reason, v_external, p_payload,
      v_at, v_actor, v_at
    ) returning id into v_id;
  exception
    when unique_violation then
      raise exception 'duplicate_reference';
  end;
  perform private.debt_event(
    v_shop, 'standalone', v_id, 'declared', v_actor, v_name, v_at,
    pg_catalog.jsonb_build_object(
      'direction', v_direction, 'unit', v_unit, 'karat', v_karat,
      'amount', v_amount::text, 'party_name', v_party, 'reason', v_reason
    )
  );
  v_result := private.debt_result(
    'debt_declare', 'standalone', v_id, v_direction, v_unit, v_karat,
    v_amount, 0, 0, v_amount, 1, 'open', 'none', null,
    private.debt_effect(0, 0, 0, 0)
  );
  return private.debt_finish(
    v_shop, p_key, 'debt_declare', p_payload, v_claim ->> 'hash',
    'standalone', v_id, v_result
  );
end;
$fn$;

create function private.debt_settle(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_source_kind text;
  v_source_id uuid;
  v_direction text;
  v_unit text;
  v_karat smallint;
  v_amount bigint;
  v_reason text;
  v_reference uuid;
  v_effect_choice text;
  v_expected_remaining bigint;
  v_expected_version bigint;
  v_day uuid;
  v_day_version bigint;
  v_actor uuid;
  v_name text;
  v_at timestamptz;
  v_debt public.shop_debts%rowtype;
  v_payable public.purchase_cash_payables%rowtype;
  v_obligation public.gold_obligations%rowtype;
  v_original bigint;
  v_settled bigint;
  v_cancelled bigint := 0;
  v_remaining bigint;
  v_version bigint;
  v_archived boolean := false;
  v_party text;
  v_operation uuid;
  v_effect jsonb;
  v_display text;
  v_result jsonb;
  v_cash bigint;
  v_posted jsonb;
  v_legacy jsonb;
begin
  v_claim := private.debt_claim(p_key, p_payload, 'debt_settle');
  if (v_claim ->> 'continue')::boolean is distinct from true then
    return v_claim -> 'result';
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  perform private.repair_require_keys(p_payload, array[
    'amount', 'deliveries', 'direction', 'expected_day_id', 'expected_day_version',
    'expected_remaining', 'expected_version', 'karat', 'kind', 'ledger_effect',
    'reason', 'receipt', 'settlement_reference', 'source_id', 'source_kind',
    'tenders', 'unit', 'version'
  ]);
  if pg_catalog.jsonb_typeof(p_payload -> 'source_kind') is distinct from 'string'
    or p_payload ->> 'source_kind' not in ('standalone', 'purchase_cash_payable', 'gold_obligation')
    or pg_catalog.jsonb_typeof(p_payload -> 'direction') is distinct from 'string'
    or p_payload ->> 'direction' not in ('shop_owes', 'owed_to_shop')
    or pg_catalog.jsonb_typeof(p_payload -> 'unit') is distinct from 'string'
    or p_payload ->> 'unit' not in ('money', 'gold')
    or pg_catalog.jsonb_typeof(p_payload -> 'ledger_effect') is distinct from 'string'
    or p_payload ->> 'ledger_effect' not in ('move', 'none') then
    raise exception 'invalid_input';
  end if;
  v_source_kind := p_payload ->> 'source_kind';
  v_source_id := private.repair_uuid(p_payload -> 'source_id');
  v_direction := p_payload ->> 'direction';
  v_unit := p_payload ->> 'unit';
  v_karat := private.debt_karat(p_payload -> 'karat', v_unit);
  v_amount := private.repair_money(p_payload -> 'amount', false);
  v_reason := private.debt_exact_text(p_payload -> 'reason', 1, 500);
  v_reference := private.repair_uuid(p_payload -> 'settlement_reference');
  v_effect_choice := p_payload ->> 'ledger_effect';
  v_expected_remaining := private.repair_money(p_payload -> 'expected_remaining', true);
  if p_payload -> 'expected_version' is not distinct from 'null'::jsonb then
    v_expected_version := null;
  elsif pg_catalog.jsonb_typeof(p_payload -> 'expected_version') = 'string' then
    v_expected_version := private.repair_money(p_payload -> 'expected_version', false);
  else
    raise exception 'invalid_input';
  end if;
  if v_source_kind = 'standalone' then
    if v_expected_version is null then
      raise exception 'invalid_input';
    end if;
  else
    if v_expected_version is not null or v_direction is distinct from 'shop_owes' then
      raise exception 'invalid_input';
    end if;
  end if;
  if v_effect_choice = 'none' then
    if v_source_kind is distinct from 'standalone' then
      raise exception 'ledger_effect_required';
    end if;
    if p_payload -> 'expected_day_id' is distinct from 'null'::jsonb
      or p_payload -> 'expected_day_version' is distinct from 'null'::jsonb
      or p_payload -> 'tenders' is distinct from 'null'::jsonb
      or p_payload -> 'deliveries' is distinct from 'null'::jsonb
      or p_payload -> 'receipt' is distinct from 'null'::jsonb then
      raise exception 'invalid_input';
    end if;
  else
    v_day := private.parse_expected_day(p_payload);
    v_day_version := private.parse_expected_version(p_payload);
    if v_unit = 'money' then
      if private.validated_tender_sum(p_payload -> 'tenders') is distinct from v_amount
        or p_payload -> 'deliveries' is distinct from 'null'::jsonb
        or p_payload -> 'receipt' is distinct from 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    elsif v_direction = 'shop_owes' then
      perform private.debt_delivery_ids(p_payload -> 'deliveries', v_amount);
      if p_payload -> 'tenders' is distinct from 'null'::jsonb
        or p_payload -> 'receipt' is distinct from 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    else
      perform private.debt_check_receipt(p_payload -> 'receipt', v_karat, v_amount);
      if p_payload -> 'tenders' is distinct from 'null'::jsonb
        or p_payload -> 'deliveries' is distinct from 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    end if;
  end if;
  if exists (
    select 1 from public.financial_command_requests as request
    where request.shop_id = v_shop and request.idempotency_key = p_key
  ) then
    raise exception 'payload_mismatch';
  end if;
  if exists (
    select 1 from public.debt_settlement_references as known
    where known.shop_id = v_shop and known.settlement_reference = v_reference
  ) then
    raise exception 'duplicate_reference';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select shop.owner_display_name into v_name
  from public.shops as shop where shop.id = v_shop;
  if v_source_kind = 'standalone' then
    select debt.* into v_debt
    from public.shop_debts as debt
    where debt.shop_id = v_shop and debt.id = v_source_id
    for update;
    if v_debt.id is null then
      raise exception 'not_found';
    end if;
    if v_debt.direction is distinct from v_direction
      or v_debt.unit is distinct from v_unit
      or v_debt.karat is distinct from v_karat
      or v_debt.record_version is distinct from v_expected_version
      or v_debt.remaining_amount is distinct from v_expected_remaining then
      if v_debt.direction is distinct from v_direction
        or v_debt.unit is distinct from v_unit
        or v_debt.karat is distinct from v_karat then
        raise exception 'invalid_input';
      end if;
      raise exception 'stale_debt';
    end if;
    if v_debt.status = 'cancelled' then
      raise exception 'settlement_not_allowed';
    end if;
    if v_amount > v_debt.remaining_amount then
      raise exception 'settlement_exceeds_obligation';
    end if;
    v_original := v_debt.original_amount;
    v_settled := v_debt.settled_amount + v_amount;
    v_remaining := v_debt.remaining_amount - v_amount;
    v_archived := v_debt.status = 'archived';
    v_party := v_debt.party_name;
  elsif v_source_kind = 'purchase_cash_payable' then
    if v_unit is distinct from 'money' or v_karat is not null then
      raise exception 'invalid_input';
    end if;
    select payable.* into v_payable
    from public.purchase_cash_payables as payable
    where payable.shop_id = v_shop and payable.operation_id = v_source_id
    for update;
    if v_payable.operation_id is null then
      raise exception 'not_found';
    end if;
    if v_payable.remaining_piastres is distinct from v_expected_remaining then
      raise exception 'stale_debt';
    end if;
    if v_amount > v_payable.remaining_piastres then
      raise exception 'settlement_exceeds_obligation';
    end if;
    v_party := v_payable.seller_name;
    v_archived := exists (
      select 1 from public.debt_source_archives as archive
      where archive.shop_id = v_shop
        and archive.source_kind = 'purchase_cash_payable'
        and archive.source_id = v_source_id
    );
  else
    if v_unit is distinct from 'gold' then
      raise exception 'invalid_input';
    end if;
    select obligation.* into v_obligation
    from public.gold_obligations as obligation
    where obligation.shop_id = v_shop and obligation.operation_id = v_source_id
    for update;
    if v_obligation.operation_id is null then
      raise exception 'not_found';
    end if;
    if v_obligation.karat is distinct from v_karat then
      raise exception 'invalid_input';
    end if;
    if v_obligation.remaining_milligrams is distinct from v_expected_remaining then
      raise exception 'stale_debt';
    end if;
    if v_amount > v_obligation.remaining_milligrams then
      raise exception 'settlement_exceeds_obligation';
    end if;
    v_party := v_obligation.counterparty_name;
    v_archived := exists (
      select 1 from public.debt_source_archives as archive
      where archive.shop_id = v_shop
        and archive.source_kind = 'gold_obligation'
        and archive.source_id = v_source_id
    );
  end if;
  v_effect := private.debt_effect(0, 0, 0, 0);
  if v_effect_choice = 'move' and v_source_kind = 'standalone' then
    perform private.debt_lock_day(v_shop, v_day, v_day_version);
    v_operation := private.insert_operation(
      v_shop, 'debt_settlement', v_day, v_actor, v_at, p_payload
    );
    if v_unit = 'money' then
      perform private.debt_post_money(v_shop, v_operation, v_direction, p_payload -> 'tenders');
      v_cash := case when v_direction = 'shop_owes' then -v_amount else v_amount end;
      v_effect := private.debt_effect(v_cash, 0, 0, 0);
    elsif v_direction = 'shop_owes' then
      v_effect := private.debt_post_gold_out(
        v_shop, v_operation, v_karat, v_amount, p_payload -> 'deliveries'
      );
    else
      v_effect := private.debt_post_gold_in(
        v_shop, v_operation, v_karat, v_amount, v_party, v_at, p_payload -> 'receipt'
      );
    end if;
    perform private.finish_financial_command(
      v_shop, v_operation, v_actor, v_at, v_day, 'debt_settlement_confirmed',
      p_key, p_payload,
      pg_catalog.jsonb_build_object(
        'source_kind', v_source_kind,
        'source_id', v_source_id,
        'amount', v_amount::text,
        'ledger_effect', 'move'
      )
    );
  elsif v_effect_choice = 'move' and v_source_kind = 'purchase_cash_payable' then
    perform private.debt_lock_day(v_shop, v_day, v_day_version);
    v_posted := public.settle_purchase_cash_payable(
      p_key, v_source_id, p_payload -> 'tenders'
    );
    v_operation := (v_posted ->> 'operation_id')::uuid;
    v_effect := private.debt_operation_effect(v_shop, v_operation);
  elsif v_effect_choice = 'move' then
    perform private.debt_lock_day(v_shop, v_day, v_day_version);
    v_legacy := pg_catalog.jsonb_build_object(
      'version', 1,
      'kind', 'gold_obligation_settlement',
      'expected_day_id', p_payload -> 'expected_day_id',
      'expected_day_version', p_payload -> 'expected_day_version',
      'obligation_operation_id', v_source_id,
      'deliveries', p_payload -> 'deliveries',
      'reason', v_reason
    );
    v_posted := public.post_gold_obligation_settlement_v1(p_key, v_legacy);
    v_operation := (v_posted ->> 'operation_id')::uuid;
    v_effect := private.debt_operation_effect(v_shop, v_operation);
  end if;
  if v_source_kind = 'standalone' then
    update public.shop_debts
    set settled_amount = v_settled,
        remaining_amount = v_remaining,
        record_version = record_version + 1,
        updated_at = v_at
    where shop_id = v_shop and id = v_source_id
    returning record_version into v_version;
  else
    select
      figures.original_amount,
      figures.settled_amount,
      figures.cancelled_amount,
      figures.remaining_amount
    into v_original, v_settled, v_cancelled, v_remaining
    from private.debt_source_figures(v_shop, v_source_kind, v_source_id) as figures;
    v_version := null;
  end if;
  begin
    insert into public.debt_settlement_references (
      shop_id, settlement_reference, source_kind, source_id, idempotency_key,
      amount, unit, created_at
    ) values (
      v_shop, v_reference, v_source_kind, v_source_id, p_key,
      v_amount, v_unit, v_at
    );
  exception
    when unique_violation then
      raise exception 'duplicate_reference';
  end;
  v_display := case
    when v_archived then 'archived'
    when v_remaining = 0 then 'settled'
    else 'open'
  end;
  perform private.debt_event(
    v_shop, v_source_kind, v_source_id, 'settled', v_actor, v_name, v_at,
    p_payload || v_effect || pg_catalog.jsonb_build_object(
      'operation_id', v_operation,
      'settled_amount', v_settled::text,
      'remaining_amount', v_remaining::text
    )
  );
  v_result := private.debt_result(
    'debt_settle', v_source_kind, v_source_id, v_direction, v_unit, v_karat,
    v_original, v_settled, v_cancelled, v_remaining, v_version, v_display,
    v_effect_choice, v_operation, v_effect
  );
  return private.debt_finish(
    v_shop, p_key, 'debt_settle', p_payload, v_claim ->> 'hash',
    v_source_kind, v_source_id, v_result
  );
end;
$fn$;

create function private.debt_cancel(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_source_kind text;
  v_source_id uuid;
  v_reason text;
  v_expected_remaining bigint;
  v_expected_version bigint;
  v_debt public.shop_debts%rowtype;
  v_actor uuid;
  v_name text;
  v_at timestamptz;
  v_version bigint;
  v_result jsonb;
begin
  v_claim := private.debt_claim(p_key, p_payload, 'debt_cancel');
  if (v_claim ->> 'continue')::boolean is distinct from true then
    return v_claim -> 'result';
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  perform private.repair_require_keys(p_payload, array[
    'expected_remaining', 'expected_version', 'kind', 'reason',
    'source_id', 'source_kind', 'version'
  ]);
  if pg_catalog.jsonb_typeof(p_payload -> 'source_kind') is distinct from 'string'
    or p_payload ->> 'source_kind' not in (
      'standalone', 'purchase_cash_payable', 'gold_obligation'
    ) then
    raise exception 'invalid_input';
  end if;
  v_source_kind := p_payload ->> 'source_kind';
  if v_source_kind is distinct from 'standalone' then
    raise exception 'source_cancel_forbidden';
  end if;
  v_source_id := private.repair_uuid(p_payload -> 'source_id');
  v_reason := private.debt_exact_text(p_payload -> 'reason', 1, 500);
  v_expected_remaining := private.repair_money(p_payload -> 'expected_remaining', true);
  if pg_catalog.jsonb_typeof(p_payload -> 'expected_version') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_expected_version := private.repair_money(p_payload -> 'expected_version', false);
  select debt.* into v_debt
  from public.shop_debts as debt
  where debt.shop_id = v_shop and debt.id = v_source_id
  for update;
  if v_debt.id is null then
    raise exception 'not_found';
  end if;
  if v_debt.record_version is distinct from v_expected_version
    or v_debt.remaining_amount is distinct from v_expected_remaining then
    raise exception 'stale_debt';
  end if;
  if v_debt.settled_amount <> 0 then
    raise exception 'partly_settled';
  end if;
  if v_debt.status is distinct from 'open' then
    raise exception 'cancel_not_allowed';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select shop.owner_display_name into v_name
  from public.shops as shop where shop.id = v_shop;
  update public.shop_debts
  set status = 'cancelled',
      remaining_amount = 0,
      cancellation_reason = v_reason,
      record_version = record_version + 1,
      updated_at = v_at
  where shop_id = v_shop and id = v_source_id
  returning record_version into v_version;
  perform private.debt_event(
    v_shop, 'standalone', v_source_id, 'cancelled', v_actor, v_name, v_at,
    pg_catalog.jsonb_build_object(
      'reason', v_reason,
      'original_amount', v_debt.original_amount::text,
      'cash_piastres', '0',
      'gold_milligrams', '0',
      'custody_milligrams', '0'
    )
  );
  v_result := private.debt_result(
    'debt_cancel', 'standalone', v_source_id, v_debt.direction, v_debt.unit,
    v_debt.karat, v_debt.original_amount, 0, v_debt.original_amount, 0,
    v_version, 'cancelled', 'none', null, private.debt_effect(0, 0, 0, 0)
  );
  return private.debt_finish(
    v_shop, p_key, 'debt_cancel', p_payload, v_claim ->> 'hash',
    'standalone', v_source_id, v_result
  );
end;
$fn$;

create function private.debt_archive(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_source_kind text;
  v_source_id uuid;
  v_reason text;
  v_expected_remaining bigint;
  v_expected_version bigint;
  v_debt public.shop_debts%rowtype;
  v_payable public.purchase_cash_payables%rowtype;
  v_obligation public.gold_obligations%rowtype;
  v_actor uuid;
  v_name text;
  v_at timestamptz;
  v_version bigint;
  v_direction text;
  v_unit text;
  v_karat smallint;
  v_original bigint;
  v_settled bigint;
  v_cancelled bigint := 0;
  v_remaining bigint;
  v_result jsonb;
begin
  v_claim := private.debt_claim(p_key, p_payload, 'debt_archive');
  if (v_claim ->> 'continue')::boolean is distinct from true then
    return v_claim -> 'result';
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  perform private.repair_require_keys(p_payload, array[
    'expected_remaining', 'expected_version', 'kind', 'reason',
    'source_id', 'source_kind', 'version'
  ]);
  if pg_catalog.jsonb_typeof(p_payload -> 'source_kind') is distinct from 'string'
    or p_payload ->> 'source_kind' not in (
      'standalone', 'purchase_cash_payable', 'gold_obligation'
    ) then
    raise exception 'invalid_input';
  end if;
  v_source_kind := p_payload ->> 'source_kind';
  v_source_id := private.repair_uuid(p_payload -> 'source_id');
  v_reason := private.debt_exact_text(p_payload -> 'reason', 1, 500);
  v_expected_remaining := private.repair_money(p_payload -> 'expected_remaining', true);
  if v_source_kind = 'standalone' then
    if pg_catalog.jsonb_typeof(p_payload -> 'expected_version') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_expected_version := private.repair_money(p_payload -> 'expected_version', false);
  elsif p_payload -> 'expected_version' is distinct from 'null'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select shop.owner_display_name into v_name
  from public.shops as shop where shop.id = v_shop;
  if v_source_kind = 'standalone' then
    select debt.* into v_debt
    from public.shop_debts as debt
    where debt.shop_id = v_shop and debt.id = v_source_id
    for update;
    if v_debt.id is null then
      raise exception 'not_found';
    end if;
    if v_debt.record_version is distinct from v_expected_version
      or v_debt.remaining_amount is distinct from v_expected_remaining then
      raise exception 'stale_debt';
    end if;
    if v_debt.status = 'archived' then
      raise exception 'archive_not_allowed';
    end if;
    update public.shop_debts
    set status = 'archived',
        archived_from_status = v_debt.status,
        record_version = record_version + 1,
        updated_at = v_at
    where shop_id = v_shop and id = v_source_id
    returning record_version into v_version;
    v_direction := v_debt.direction;
    v_unit := v_debt.unit;
    v_karat := v_debt.karat;
    v_original := v_debt.original_amount;
    v_settled := v_debt.settled_amount;
    v_remaining := v_debt.remaining_amount;
    v_cancelled := case
      when v_debt.status = 'cancelled' then v_debt.original_amount
      else 0
    end;
  elsif v_source_kind = 'purchase_cash_payable' then
    select payable.* into v_payable
    from public.purchase_cash_payables as payable
    where payable.shop_id = v_shop and payable.operation_id = v_source_id
    for update;
    if v_payable.operation_id is null then
      raise exception 'not_found';
    end if;
    if v_payable.remaining_piastres is distinct from v_expected_remaining then
      raise exception 'stale_debt';
    end if;
    if exists (
      select 1 from public.debt_source_archives as archive
      where archive.shop_id = v_shop
        and archive.source_kind = 'purchase_cash_payable'
        and archive.source_id = v_source_id
    ) then
      raise exception 'duplicate_archive';
    end if;
    v_direction := 'shop_owes';
    v_unit := 'money';
    v_karat := null;
    select
      figures.original_amount, figures.settled_amount,
      figures.cancelled_amount, figures.remaining_amount
    into v_original, v_settled, v_cancelled, v_remaining
    from private.debt_source_figures(
      v_shop, 'purchase_cash_payable', v_source_id
    ) as figures;
    v_version := null;
  else
    select obligation.* into v_obligation
    from public.gold_obligations as obligation
    where obligation.shop_id = v_shop and obligation.operation_id = v_source_id
    for update;
    if v_obligation.operation_id is null then
      raise exception 'not_found';
    end if;
    if v_obligation.remaining_milligrams is distinct from v_expected_remaining then
      raise exception 'stale_debt';
    end if;
    if exists (
      select 1 from public.debt_source_archives as archive
      where archive.shop_id = v_shop
        and archive.source_kind = 'gold_obligation'
        and archive.source_id = v_source_id
    ) then
      raise exception 'duplicate_archive';
    end if;
    v_direction := 'shop_owes';
    v_unit := 'gold';
    v_karat := v_obligation.karat;
    select
      figures.original_amount, figures.settled_amount,
      figures.cancelled_amount, figures.remaining_amount
    into v_original, v_settled, v_cancelled, v_remaining
    from private.debt_source_figures(v_shop, 'gold_obligation', v_source_id) as figures;
    v_version := null;
  end if;
  if v_source_kind <> 'standalone' then
    begin
      insert into public.debt_source_archives (
        shop_id, source_kind, source_id, reason, actor_user_id,
        actor_display_name, created_at, payload
      ) values (
        v_shop, v_source_kind, v_source_id, v_reason, v_actor, v_name, v_at, p_payload
      );
    exception
      when unique_violation then
        raise exception 'duplicate_archive';
    end;
  end if;
  perform private.debt_event(
    v_shop, v_source_kind, v_source_id, 'archived', v_actor, v_name, v_at,
    pg_catalog.jsonb_build_object(
      'reason', v_reason,
      'remaining_amount', v_remaining::text,
      'settled_amount', v_settled::text,
      'original_amount', v_original::text
    )
  );
  v_result := private.debt_result(
    'debt_archive', v_source_kind, v_source_id, v_direction, v_unit, v_karat,
    v_original, v_settled, v_cancelled, v_remaining, v_version, 'archived',
    'none', null, private.debt_effect(0, 0, 0, 0)
  );
  return private.debt_finish(
    v_shop, p_key, 'debt_archive', p_payload, v_claim ->> 'hash',
    v_source_kind, v_source_id, v_result
  );
end;
$fn$;

create function public.post_debt_declare_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.debt_declare(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_debt_settle_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.debt_settle(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_debt_cancel_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.debt_cancel(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_debt_archive_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.debt_archive(p_idempotency_key, p_payload);
end;
$fn$;

create function public.get_debt_command_status_v1(p_idempotency_key uuid)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_request public.debt_command_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select request.* into v_request
  from public.debt_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key;
  if v_request.idempotency_key is null then
    return pg_catalog.jsonb_build_object('status', 'absent');
  end if;
  return pg_catalog.jsonb_build_object(
    'status', 'completed',
    'command_kind', v_request.command_kind,
    'source_kind', v_request.source_kind,
    'source_id', v_request.source_id,
    'result', v_request.result
  );
end;
$fn$;

create function public.get_debt_context_v1()
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_day public.business_days%rowtype;
  v_cash jsonb;
  v_lots jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  v_shop := private.opening_require_reader_shop();
  select shop.time_zone into v_zone from public.shops as shop where shop.id = v_shop;
  select day.* into v_day
  from public.business_days as day
  where day.shop_id = v_shop
  order by day.opened_at desc, day.id desc
  limit 1;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'method', balance.method_code,
    'balance_piastres', balance.amount::text
  ) order by balance.method_code), '[]'::jsonb)
  into v_cash
  from (
    select account.method_code, coalesce(sum(posting.amount), 0)::bigint as amount
    from public.ledger_accounts as account
    left join public.journal_postings as posting
      on posting.shop_id = account.shop_id and posting.account_id = account.id
    where account.shop_id = v_shop and account.account_kind = 'cash_method'
    group by account.method_code
  ) as balance;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'lot_id', lot.id,
    'category', lot.category_code,
    'karat', lot.karat,
    'display_name', lot.display_name,
    'milligrams', remaining.milligrams::text,
    'count', case when lot.tracks_count then remaining.piece_count::text else null end,
    'tracks_count', lot.tracks_count
  ) order by lot.karat, lot.category_code, lot.display_name, lot.id), '[]'::jsonb)
  into v_lots
  from public.inventory_lots as lot
  join lateral private.lot_remaining(lot.id) as remaining on true
  where lot.shop_id = v_shop
    and lot.stock_class = 'owned_available'
    and remaining.milligrams > 0;
  return pg_catalog.jsonb_build_object(
    'time_zone', v_zone,
    'day', case
      when v_day.id is null then pg_catalog.jsonb_build_object('state', 'uninitialized')
      else pg_catalog.jsonb_build_object(
        'state', v_day.status,
        'business_day_id', v_day.id,
        'business_date', pg_catalog.to_char(v_day.business_date, 'YYYY-MM-DD'),
        'day_version', v_day.day_version::text
      )
    end,
    'cash_methods', coalesce(v_cash, '[]'::jsonb),
    'lots', coalesce(v_lots, '[]'::jsonb)
  );
end;
$fn$;

create function public.get_debt_list_v1(
  p_query text, p_filter text, p_limit integer, p_cursor text
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_filter text := coalesce(p_filter, 'open');
  v_limit integer := coalesce(p_limit, 20);
  v_query text := coalesce(pg_catalog.btrim(p_query), '');
  v_like text;
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_next text;
  v_row record;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if v_filter not in ('open', 'settled', 'remaining', 'cancelled', 'archived', 'all')
    or v_limit < 1 or v_limit > 50
    or pg_catalog.char_length(v_query) > 80 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select shop.time_zone into v_zone from public.shops as shop where shop.id = v_shop;
  if p_cursor is not null and pg_catalog.btrim(p_cursor) <> '' then
    v_cursor_at := private.cursor_time(p_cursor);
    v_cursor_id := private.cursor_id(p_cursor);
  end if;
  v_like := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  for v_row in
    select debt.*
    from private.debt_balances(v_shop) as debt
    where (
      v_filter = 'all'
      or (v_filter = 'open' and debt.display_status = 'open')
      or (v_filter = 'settled' and debt.display_status = 'settled')
      or (
        v_filter = 'remaining'
        and debt.remaining_amount > 0
        and debt.display_status <> 'cancelled'
      )
      or (v_filter = 'cancelled' and debt.display_status = 'cancelled')
      or (v_filter = 'archived' and debt.display_status = 'archived')
    )
    and (
      v_query = ''
      or debt.party_name ilike v_like escape '\'
      or coalesce(debt.contact_phone, '') ilike v_like escape '\'
      or debt.reason ilike v_like escape '\'
      or coalesce(debt.external_reference, '') ilike v_like escape '\'
    )
    and (
      v_cursor_at is null
      or debt.created_at < v_cursor_at
      or (debt.created_at = v_cursor_at and debt.source_id < v_cursor_id)
    )
    order by debt.created_at desc, debt.source_id desc
    limit v_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_limit then
      v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'debt_key', v_row.debt_key,
        'source_kind', v_row.source_kind,
        'source_id', v_row.source_id,
        'direction', v_row.direction,
        'unit', v_row.unit,
        'karat', v_row.karat,
        'party_name', v_row.party_name,
        'contact_phone', v_row.contact_phone,
        'reason', v_row.reason,
        'external_reference', v_row.external_reference,
        'original_amount', v_row.original_amount::text,
        'settled_amount', v_row.settled_amount::text,
        'cancelled_amount', v_row.cancelled_amount::text,
        'remaining_amount', v_row.remaining_amount::text,
        'display_status', v_row.display_status,
        'record_version', case
          when v_row.record_version is null then null else v_row.record_version::text
        end,
        'created_at', pg_catalog.to_char(
          v_row.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
        ),
        'created_at_shop', pg_catalog.to_char(
          v_row.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
        )
      ));
      v_next := private.cursor_text(v_row.created_at, v_row.source_id);
    end if;
  end loop;
  if v_count <= v_limit then
    v_next := null;
  end if;
  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next,
    'time_zone', v_zone
  );
end;
$fn$;

create function public.get_debt_v1(p_source_kind text, p_source_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_row record;
  v_declaration jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_source_kind not in ('standalone', 'purchase_cash_payable', 'gold_obligation')
    or p_source_id is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select shop.time_zone into v_zone from public.shops as shop where shop.id = v_shop;
  select debt.* into v_row
  from private.debt_balances(v_shop) as debt
  where debt.source_kind = p_source_kind and debt.source_id = p_source_id;
  if v_row.source_id is null then
    raise exception 'not_found';
  end if;
  if p_source_kind = 'standalone' then
    select debt.declaration_payload into v_declaration
    from public.shop_debts as debt
    where debt.shop_id = v_shop and debt.id = p_source_id;
  end if;
  return pg_catalog.jsonb_build_object(
    'debt_key', v_row.debt_key,
    'source_kind', v_row.source_kind,
    'source_id', v_row.source_id,
    'direction', v_row.direction,
    'unit', v_row.unit,
    'karat', v_row.karat,
    'party_name', v_row.party_name,
    'contact_phone', v_row.contact_phone,
    'reason', v_row.reason,
    'external_reference', v_row.external_reference,
    'original_amount', v_row.original_amount::text,
    'settled_amount', v_row.settled_amount::text,
    'cancelled_amount', v_row.cancelled_amount::text,
    'remaining_amount', v_row.remaining_amount::text,
    'display_status', v_row.display_status,
    'record_version', case
      when v_row.record_version is null then null else v_row.record_version::text
    end,
    'created_at', pg_catalog.to_char(
      v_row.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'
    ),
    'created_at_shop', pg_catalog.to_char(
      v_row.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'time_zone', v_zone,
    'can_settle', v_row.remaining_amount > 0 and v_row.display_status <> 'cancelled',
    'can_cancel', v_row.source_kind = 'standalone'
      and v_row.display_status = 'open'
      and v_row.settled_amount = 0,
    'can_archive', v_row.display_status <> 'archived',
    'no_ledger_allowed', v_row.source_kind = 'standalone',
    'declaration_payload', v_declaration,
    'history', private.debt_history(v_shop, p_source_kind, p_source_id, v_zone)
  );
end;
$fn$;

revoke all on function private.debt_guard() from public, anon, authenticated;
revoke all on function private.debt_reject_mutation() from public, anon, authenticated;
revoke all on function private.debt_exact_text(jsonb, integer, integer) from public, anon, authenticated;
revoke all on function private.debt_phone(jsonb) from public, anon, authenticated;
revoke all on function private.debt_karat(jsonb, text) from public, anon, authenticated;
revoke all on function private.debt_optional_reference(jsonb) from public, anon, authenticated;
revoke all on function private.debt_claim(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function private.debt_finish(uuid, uuid, text, jsonb, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function private.debt_event(uuid, text, uuid, text, uuid, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function private.debt_effect(bigint, bigint, bigint, bigint) from public, anon, authenticated;
revoke all on function private.debt_result(text, text, uuid, text, text, smallint, bigint, bigint, bigint, bigint, bigint, text, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function private.debt_operation_effect(uuid, uuid) from public, anon, authenticated;
revoke all on function private.debt_source_figures(uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.debt_lock_day(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function private.debt_post_money(uuid, uuid, text, jsonb) from public, anon, authenticated;
revoke all on function private.debt_delivery_ids(jsonb, bigint) from public, anon, authenticated;
revoke all on function private.debt_check_receipt(jsonb, smallint, bigint) from public, anon, authenticated;
revoke all on function private.debt_post_gold_out(uuid, uuid, smallint, bigint, jsonb) from public, anon, authenticated;
revoke all on function private.debt_post_gold_in(uuid, uuid, smallint, bigint, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function private.debt_balances(uuid) from public, anon, authenticated;
revoke all on function private.debt_history(uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function private.debt_declare(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.debt_settle(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.debt_cancel(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.debt_archive(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.bump_shop_sync(uuid, text) from public, anon, authenticated;
revoke all on function private.shop_sync_touch() from public, anon, authenticated;
revoke all on function private.ledger_operation_label(text) from public, anon, authenticated;

revoke all on function public.post_debt_declare_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_debt_settle_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_debt_cancel_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_debt_archive_v1(uuid, jsonb) from public, anon;
revoke all on function public.get_debt_command_status_v1(uuid) from public, anon;
revoke all on function public.get_debt_context_v1() from public, anon;
revoke all on function public.get_debt_list_v1(text, text, integer, text) from public, anon;
revoke all on function public.get_debt_v1(text, uuid) from public, anon;

grant execute on function public.post_debt_declare_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_debt_settle_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_debt_cancel_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_debt_archive_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_debt_command_status_v1(uuid) to authenticated;
grant execute on function public.get_debt_context_v1() to authenticated;
grant execute on function public.get_debt_list_v1(text, text, integer, text) to authenticated;
grant execute on function public.get_debt_v1(text, uuid) to authenticated;

commit;

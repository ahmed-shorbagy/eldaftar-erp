-- Milestone 4 repairs (REP-01/02/03). Custody is not saleable stock.
-- A collected handover fee posts once through the existing cash journal,
-- open-day version, and financial command registry. Outstanding fee stays
-- on the repair. No debt, scrap, catalog, or lot quantity is written.
-- Cancellation of an active repair confirms return to the customer,
-- releases custody once, and posts no fee. Archive does not reverse money.
-- get_opening_status does not see custody commands, so repair status is separate.
begin;

select private.compensation_extend_in_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  array['repair_fee']
);
select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  array['repair_fee_confirmed']
);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  array['repair_fee_confirmed']
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
    else null
  end;
$fn$;

alter table public.shop_sync_signals
  add column repair_revision bigint not null default 0
  check (repair_revision >= 0);

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
    repair_revision, updated_at
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
    else 'ledger'
  end;
  perform private.bump_shop_sync(v_shop, v_scope);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$fn$;

create table public.repairs (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  status text not null,
  record_version bigint not null,
  customer_name text not null,
  customer_phone text not null,
  item_description text not null,
  measured_milligrams bigint not null,
  karat smallint not null,
  issue text not null,
  intake_notes text not null,
  estimated_fee_piastres bigint,
  final_fee_piastres bigint,
  collected_piastres bigint not null,
  outstanding_piastres bigint not null,
  custody_held boolean not null,
  intake_payload jsonb not null,
  intake_actor_user_id uuid not null,
  intake_at timestamptz not null,
  updated_at timestamptz not null,
  financial_operation_id uuid,
  cancellation_reason text,
  archived_from_status text,
  constraint repairs_status_check check (
    status in ('received', 'in_progress', 'ready', 'delivered', 'cancelled', 'archived')
  ),
  constraint repairs_version_check check (record_version >= 1),
  constraint repairs_name_check check (char_length(customer_name) between 1 and 200),
  constraint repairs_phone_check check (
    char_length(customer_phone) <= 20
    and (customer_phone = '' or customer_phone ~ '^\+?[0-9]{7,15}$')
  ),
  constraint repairs_item_check check (char_length(item_description) between 1 and 300),
  constraint repairs_issue_check check (char_length(issue) between 1 and 500),
  constraint repairs_notes_check check (char_length(intake_notes) <= 1000),
  constraint repairs_weight_check check (measured_milligrams > 0),
  constraint repairs_karat_check check (karat in (14, 18, 21, 22, 24)),
  constraint repairs_estimate_check check (
    estimated_fee_piastres is null or estimated_fee_piastres >= 0
  ),
  constraint repairs_collected_check check (collected_piastres >= 0),
  constraint repairs_outstanding_check check (outstanding_piastres >= 0),
  constraint repairs_payload_check check (jsonb_typeof(intake_payload) = 'object'),
  constraint repairs_reason_check check (
    cancellation_reason is null or char_length(cancellation_reason) between 1 and 500
  ),
  constraint repairs_archive_source_check check (
    archived_from_status is null
    or archived_from_status in ('delivered', 'cancelled')
  ),
  constraint repairs_fee_operation_fkey
    foreign key (shop_id, financial_operation_id)
    references public.financial_operations (shop_id, id),
  constraint repairs_actor_fkey
    foreign key (shop_id, intake_actor_user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint repairs_state_check check (
    (
      status in ('received', 'in_progress', 'ready')
      and custody_held
      and final_fee_piastres is null
      and collected_piastres = 0
      and outstanding_piastres = 0
      and financial_operation_id is null
      and cancellation_reason is null
      and archived_from_status is null
    )
    or (
      status = 'delivered'
      and not custody_held
      and final_fee_piastres is not null
      and collected_piastres <= final_fee_piastres
      and outstanding_piastres = final_fee_piastres - collected_piastres
      and cancellation_reason is null
      and archived_from_status is null
      and (
        (collected_piastres = 0 and financial_operation_id is null)
        or (collected_piastres > 0 and financial_operation_id is not null)
      )
    )
    or (
      status = 'cancelled'
      and not custody_held
      and final_fee_piastres is null
      and collected_piastres = 0
      and outstanding_piastres = 0
      and financial_operation_id is null
      and cancellation_reason is not null
      and archived_from_status is null
    )
    or (
      status = 'archived'
      and not custody_held
      and (
        (
          archived_from_status = 'delivered'
          and final_fee_piastres is not null
          and collected_piastres <= final_fee_piastres
          and outstanding_piastres = final_fee_piastres - collected_piastres
          and (
            (collected_piastres = 0 and financial_operation_id is null)
            or (collected_piastres > 0 and financial_operation_id is not null)
          )
        )
        or (
          archived_from_status = 'cancelled'
          and final_fee_piastres is null
          and collected_piastres = 0
          and outstanding_piastres = 0
          and financial_operation_id is null
          and cancellation_reason is not null
        )
      )
    )
  )
);

create unique index repairs_fee_operation_key
  on public.repairs (financial_operation_id)
  where financial_operation_id is not null;
create index repairs_shop_intake_idx
  on public.repairs (shop_id, intake_at desc, id desc);
create index repairs_shop_status_idx
  on public.repairs (shop_id, status, intake_at desc, id desc);
create index repairs_shop_outstanding_idx
  on public.repairs (shop_id, intake_at desc, id desc)
  where outstanding_piastres > 0;
create unique index repairs_shop_id_key on public.repairs (shop_id, id);

create table public.repair_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  repair_id uuid not null,
  event_type text not null,
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  payload jsonb not null,
  constraint repair_events_type_check check (
    event_type in (
      'repair_intake', 'repair_status', 'repair_handover',
      'repair_cancel', 'repair_archive'
    )
  ),
  constraint repair_events_payload_check check (jsonb_typeof(payload) = 'object'),
  constraint repair_events_repair_fkey
    foreign key (shop_id, repair_id) references public.repairs (shop_id, id),
  constraint repair_events_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create index repair_events_shop_repair_idx
  on public.repair_events (shop_id, repair_id, created_at, id);

create table public.repair_custody_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  repair_id uuid not null,
  direction text not null,
  measured_milligrams bigint not null,
  karat smallint not null,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  constraint repair_custody_direction_check check (direction in ('intake', 'release')),
  constraint repair_custody_weight_check check (measured_milligrams > 0),
  constraint repair_custody_karat_check check (karat in (14, 18, 21, 22, 24)),
  constraint repair_custody_once unique (repair_id, direction),
  constraint repair_custody_repair_fkey
    foreign key (shop_id, repair_id) references public.repairs (shop_id, id),
  constraint repair_custody_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create index repair_custody_shop_idx
  on public.repair_custody_events (shop_id, repair_id, created_at);

create table public.repair_command_requests (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  idempotency_key uuid not null,
  command_kind text not null,
  payload_canonical jsonb not null,
  payload_sha256 bytea not null,
  repair_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null,
  constraint repair_commands_shop_key unique (shop_id, idempotency_key),
  constraint repair_commands_kind_check check (
    command_kind in (
      'repair_intake', 'repair_status', 'repair_handover',
      'repair_cancel', 'repair_archive'
    )
  ),
  constraint repair_commands_hash_check check (octet_length(payload_sha256) = 32),
  constraint repair_commands_payload_check check (jsonb_typeof(payload_canonical) = 'object'),
  constraint repair_commands_result_check check (jsonb_typeof(result) = 'object'),
  constraint repair_commands_repair_fkey
    foreign key (shop_id, repair_id) references public.repairs (shop_id, id)
);

create index repair_commands_repair_idx
  on public.repair_command_requests (shop_id, repair_id);

comment on table public.repairs is
  'Customer gold held for repair. Custody is never saleable stock. Outstanding fee is repair-local and is not a debt obligation.';
comment on table public.repair_events is
  'Append-only repair audit. Actor and timestamp are the signed-in owner and server UTC.';
comment on table public.repair_custody_events is
  'Immutable intake and single release. Customer gold is not an inventory lot.';
comment on table public.repair_command_requests is
  'Repair idempotency registry. Absent from get_opening_status. A collected fee also writes financial_command_requests.';

create function private.repair_guard()
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
    if new.status <> 'received'
      or new.record_version <> 1
      or not new.custody_held
      or new.final_fee_piastres is not null
      or new.collected_piastres <> 0
      or new.outstanding_piastres <> 0
      or new.financial_operation_id is not null
      or new.cancellation_reason is not null
      or new.archived_from_status is not null then
      raise exception 'invalid_input';
    end if;
    return new;
  end if;
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.customer_name is distinct from old.customer_name
    or new.customer_phone is distinct from old.customer_phone
    or new.item_description is distinct from old.item_description
    or new.measured_milligrams is distinct from old.measured_milligrams
    or new.karat is distinct from old.karat
    or new.issue is distinct from old.issue
    or new.intake_notes is distinct from old.intake_notes
    or new.estimated_fee_piastres is distinct from old.estimated_fee_piastres
    or new.intake_payload is distinct from old.intake_payload
    or new.intake_actor_user_id is distinct from old.intake_actor_user_id
    or new.intake_at is distinct from old.intake_at then
    raise exception 'audit_append_only';
  end if;
  if new.record_version is distinct from old.record_version + 1 then
    raise exception 'stale_repair';
  end if;
  if old.status = 'archived' or new.status = old.status then
    raise exception 'audit_append_only';
  end if;
  if old.status = 'received' and new.status = 'in_progress' then
    if new.custody_held
      and new.final_fee_piastres is null
      and new.collected_piastres = 0
      and new.outstanding_piastres = 0
      and new.financial_operation_id is null
      and new.cancellation_reason is null
      and new.archived_from_status is null then
      return new;
    end if;
  elsif old.status = 'in_progress' and new.status = 'ready' then
    if new.custody_held
      and new.final_fee_piastres is null
      and new.collected_piastres = 0
      and new.outstanding_piastres = 0
      and new.financial_operation_id is null
      and new.cancellation_reason is null
      and new.archived_from_status is null then
      return new;
    end if;
  elsif old.status = 'ready' and new.status = 'delivered' then
    if not new.custody_held
      and new.cancellation_reason is null
      and new.archived_from_status is null
      and new.final_fee_piastres is not null
      and new.collected_piastres between 0 and new.final_fee_piastres
      and new.outstanding_piastres = new.final_fee_piastres - new.collected_piastres
      and (
        (new.collected_piastres = 0 and new.financial_operation_id is null)
        or (new.collected_piastres > 0 and new.financial_operation_id is not null)
      ) then
      return new;
    end if;
  elsif old.status in ('received', 'in_progress', 'ready')
    and new.status = 'cancelled' then
    if not new.custody_held
      and new.final_fee_piastres is null
      and new.collected_piastres = 0
      and new.outstanding_piastres = 0
      and new.financial_operation_id is null
      and new.cancellation_reason is not null
      and new.archived_from_status is null then
      return new;
    end if;
  elsif old.status in ('delivered', 'cancelled') and new.status = 'archived' then
    if new.archived_from_status = old.status
      and new.custody_held = old.custody_held
      and new.final_fee_piastres is not distinct from old.final_fee_piastres
      and new.collected_piastres = old.collected_piastres
      and new.outstanding_piastres = old.outstanding_piastres
      and new.financial_operation_id is not distinct from old.financial_operation_id
      and new.cancellation_reason is not distinct from old.cancellation_reason then
      return new;
    end if;
  end if;
  raise exception 'invalid_input';
end;
$fn$;

create trigger repairs_guard
before insert or update or delete on public.repairs
for each row execute function private.repair_guard();

create function private.repair_reject_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  raise exception 'audit_append_only';
end;
$fn$;

create trigger repair_events_append_only
before update or delete on public.repair_events
for each row execute function private.repair_reject_mutation();
create trigger repair_custody_append_only
before update or delete on public.repair_custody_events
for each row execute function private.repair_reject_mutation();
create trigger repair_commands_append_only
before update or delete on public.repair_command_requests
for each row execute function private.repair_reject_mutation();

create trigger shop_sync_repairs
after insert or update or delete on public.repairs
for each row execute function private.shop_sync_touch();
create trigger shop_sync_repair_events
after insert or update or delete on public.repair_events
for each row execute function private.shop_sync_touch();
create trigger shop_sync_repair_custody_events
after insert or update or delete on public.repair_custody_events
for each row execute function private.shop_sync_touch();

alter table public.repairs enable row level security;
alter table public.repairs force row level security;
alter table public.repair_events enable row level security;
alter table public.repair_events force row level security;
alter table public.repair_custody_events enable row level security;
alter table public.repair_custody_events force row level security;
alter table public.repair_command_requests enable row level security;
alter table public.repair_command_requests force row level security;

revoke all on table public.repairs from public, anon, authenticated;
revoke all on table public.repair_events from public, anon, authenticated;
revoke all on table public.repair_custody_events from public, anon, authenticated;
revoke all on table public.repair_command_requests from public, anon, authenticated;
grant select on table public.repairs to authenticated;
grant select on table public.repair_events to authenticated;
grant select on table public.repair_custody_events to authenticated;
grant select on table public.repair_command_requests to authenticated;

create policy repairs_owner_read
  on public.repairs for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy repair_events_owner_read
  on public.repair_events for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy repair_custody_owner_read
  on public.repair_custody_events for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy repair_commands_owner_read
  on public.repair_command_requests for select to authenticated
  using (private.opening_financial_visible(shop_id));

create function private.repair_require_keys(p_payload jsonb, p_keys text[])
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_actual text[];
  v_expected text[];
begin
  select coalesce(pg_catalog.array_agg(entry.key order by entry.key), '{}')
    into v_actual
  from pg_catalog.jsonb_object_keys(p_payload) as entry(key);
  select coalesce(pg_catalog.array_agg(entry.key order by entry.key), '{}')
    into v_expected
  from pg_catalog.unnest(p_keys) as entry(key);
  if v_actual is distinct from v_expected then
    raise exception 'invalid_input';
  end if;
end;
$fn$;

create function private.repair_allow_keys(
  p_payload jsonb, p_required text[], p_optional text[]
) returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_key text;
  v_seen integer := 0;
begin
  for v_key in
    select entry.key from pg_catalog.jsonb_object_keys(p_payload) as entry(key)
  loop
    v_seen := v_seen + 1;
    if not (v_key = any(p_required) or v_key = any(p_optional)) then
      raise exception 'invalid_input';
    end if;
  end loop;
  if v_seen = 0 then
    raise exception 'invalid_input';
  end if;
  foreach v_key in array p_required loop
    if not (p_payload ? v_key) then
      raise exception 'invalid_input';
    end if;
  end loop;
end;
$fn$;

create function private.repair_text(
  p_value jsonb, p_min integer, p_max integer
) returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_text := pg_catalog.btrim(p_value #>> '{}');
  if pg_catalog.char_length(v_text) < p_min
    or pg_catalog.char_length(v_text) > p_max then
    raise exception 'invalid_input';
  end if;
  return v_text;
end;
$fn$;

create function private.repair_money(p_value jsonb, p_allow_zero boolean)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_amount bigint;
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_amount := private.opening_checked_bigint(
    private.opening_parse_amount(p_value #>> '{}')
  );
  if v_amount < 0 or (v_amount = 0 and not p_allow_zero) then
    raise exception 'invalid_input';
  end if;
  return v_amount;
end;
$fn$;

create function private.repair_uuid(p_value jsonb)
returns uuid
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  begin
    return (p_value #>> '{}')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'invalid_input';
  end;
end;
$fn$;

create function private.repair_claim(
  p_key uuid, p_payload jsonb, p_kind text
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_hash bytea;
  v_request public.repair_command_requests%rowtype;
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
  from public.repair_command_requests as request
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

create function private.repair_finish(
  p_shop uuid, p_key uuid, p_kind text, p_payload jsonb, p_hash text,
  p_repair uuid, p_result jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  insert into public.repair_command_requests (
    shop_id, idempotency_key, command_kind, payload_canonical, payload_sha256,
    repair_id, result, created_at
  ) values (
    p_shop, p_key, p_kind, p_payload, pg_catalog.decode(p_hash, 'hex'),
    p_repair, p_result, pg_catalog.clock_timestamp()
  );
  return p_result;
end;
$fn$;

create function private.repair_event(
  p_shop uuid, p_repair uuid, p_type text, p_actor uuid, p_name text,
  p_at timestamptz, p_payload jsonb
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  insert into public.repair_events (
    shop_id, repair_id, event_type, actor_user_id, actor_display_name,
    created_at, payload
  ) values (p_shop, p_repair, p_type, p_actor, p_name, p_at, p_payload);
end;
$fn$;

create function private.repair_post_fee(
  p_shop uuid, p_repair uuid, p_key uuid, p_payload jsonb, p_hash text,
  p_actor uuid, p_at timestamptz, p_collected bigint, p_day uuid,
  p_day_version bigint
) returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_day public.business_days%rowtype;
  v_hash bytea := pg_catalog.decode(p_hash, 'hex');
  v_request public.financial_command_requests%rowtype;
  v_sequence bigint;
  v_op uuid;
  v_journal uuid;
  v_clear uuid;
  v_account uuid;
  v_tender jsonb;
  v_amount bigint;
begin
  perform 1 from public.financial_command_requests as request
  where request.shop_id = p_shop and request.idempotency_key = p_key
  for update;
  if found then
    raise exception 'payload_mismatch';
  end if;
  select day.* into v_day
  from public.business_days as day
  where day.shop_id = p_shop and day.id = p_day
  for update;
  if v_day.id is null or v_day.status <> 'open' then
    raise exception 'day_closed';
  end if;
  if v_day.day_version <> p_day_version then
    raise exception 'stale_day';
  end if;
  select coalesce(pg_catalog.max(operation.shop_sequence), 0) + 1
    into v_sequence
  from public.financial_operations as operation
  where operation.shop_id = p_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (p_shop, v_sequence, 'repair_fee', v_day.id, p_actor, p_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, p_shop, p_payload || (
    select pg_catalog.jsonb_build_object(
      'total_piastres', p_collected::text,
      'outstanding_piastres', ((p_payload ->> 'final_fee_piastres')::bigint - p_collected)::text,
      'customer_name', repair.customer_name,
      'customer_phone', repair.customer_phone,
      'description', repair.item_description
    ) from public.repairs as repair where repair.id = p_repair and repair.shop_id = p_shop
  ), p_at);
  update public.business_days
    set day_version = day_version + 1
  where id = v_day.id;
  v_clear := private.financial_account(
    p_shop, 'movement_money_clearing', 'money', null, null, null, true
  );
  insert into public.journals (
    shop_id, operation_id, unit_kind, currency_code, bucket_key
  ) values (p_shop, v_op, 'money', 'EGP', 'money')
  returning id into v_journal;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') as tender(value)
  loop
    v_account := private.financial_account(
      p_shop, 'cash_method', 'money', null, null, v_tender ->> 'method', false
    );
    if v_account is null then
      raise exception 'invalid_input';
    end if;
    v_amount := private.repair_money(v_tender -> 'piastres', false);
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values (p_shop, v_journal, v_account, v_op, v_amount);
  end loop;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values (p_shop, v_journal, v_clear, v_op, -p_collected);
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    p_shop, p_actor, 'repair_fee_confirmed', v_op, p_at,
    pg_catalog.jsonb_build_object(
      'business_day_id', v_day.id,
      'operation_id', v_op,
      'repair_id', p_repair,
      'collected_piastres', p_collected::text
    )
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (p_shop, v_op, 'repair_fee_confirmed', p_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (p_shop, p_key, p_payload, v_hash, v_op, p_at);
  return v_op;
end;
$fn$;

create function public.post_repair_intake_v1(
  p_idempotency_key uuid, p_payload jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_name text;
  v_phone text;
  v_item text;
  v_issue text;
  v_notes text;
  v_mg bigint;
  v_karat smallint;
  v_estimate bigint;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_repair uuid;
  v_result jsonb;
begin
  v_claim := private.repair_claim(p_idempotency_key, p_payload, 'repair_intake');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.repair_require_keys(p_payload, array[
    'customer_name', 'customer_phone', 'estimated_fee_piastres', 'intake_notes',
    'issue', 'item_description', 'karat', 'kind', 'measured_milligrams', 'version'
  ]);
  v_name := private.repair_text(p_payload -> 'customer_name', 1, 200);
  v_phone := private.repair_text(p_payload -> 'customer_phone', 0, 20);
  if v_phone <> '' and v_phone !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  v_item := private.repair_text(p_payload -> 'item_description', 1, 300);
  v_issue := private.repair_text(p_payload -> 'issue', 1, 500);
  v_notes := private.repair_text(p_payload -> 'intake_notes', 0, 1000);
  if pg_catalog.jsonb_typeof(p_payload -> 'measured_milligrams') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'karat') is distinct from 'number'
    or (p_payload ->> 'karat') !~ '^(14|18|21|22|24)$' then
    raise exception 'invalid_input';
  end if;
  v_mg := private.repair_money(p_payload -> 'measured_milligrams', false);
  v_karat := (p_payload ->> 'karat')::smallint;
  if pg_catalog.jsonb_typeof(p_payload -> 'estimated_fee_piastres') = 'null' then
    v_estimate := null;
  else
    v_estimate := private.repair_money(p_payload -> 'estimated_fee_piastres', true);
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_actor := auth.uid();
  select shop.owner_display_name into v_actor_name
  from public.shops as shop where shop.id = v_shop;
  v_at := pg_catalog.clock_timestamp();
  insert into public.repairs (
    shop_id, status, record_version, customer_name, customer_phone,
    item_description, measured_milligrams, karat, issue, intake_notes,
    estimated_fee_piastres, final_fee_piastres, collected_piastres,
    outstanding_piastres, custody_held, intake_payload, intake_actor_user_id,
    intake_at, updated_at
  ) values (
    v_shop, 'received', 1, v_name, v_phone, v_item, v_mg, v_karat, v_issue,
    v_notes, v_estimate, null, 0, 0, true, p_payload, v_actor, v_at, v_at
  ) returning id into v_repair;
  insert into public.repair_custody_events (
    shop_id, repair_id, direction, measured_milligrams, karat, actor_user_id, created_at
  ) values (v_shop, v_repair, 'intake', v_mg, v_karat, v_actor, v_at);
  perform private.repair_event(
    v_shop, v_repair, 'repair_intake', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'measured_milligrams', v_mg::text,
      'karat', v_karat,
      'estimated_fee_piastres', v_estimate::text,
      'stock_milligrams', '0',
      'cash_piastres', '0'
    )
  );
  v_result := pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'repair_id', v_repair,
    'status', 'received',
    'record_version', '1',
    'custody_milligrams', v_mg::text,
    'stock_milligrams', '0',
    'cash_piastres', '0'
  );
  return private.repair_finish(
    v_shop, p_idempotency_key, 'repair_intake', p_payload,
    v_claim ->> 'hash', v_repair, v_result
  );
end;
$fn$;

create function private.repair_lock(p_shop uuid, p_repair uuid, p_expected bigint)
returns public.repairs
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_repair public.repairs%rowtype;
begin
  select repair.* into v_repair
  from public.repairs as repair
  where repair.shop_id = p_shop and repair.id = p_repair
  for update;
  if v_repair.id is null then
    raise exception 'not_found';
  end if;
  if v_repair.record_version <> p_expected then
    raise exception 'stale_repair';
  end if;
  return v_repair;
end;
$fn$;

create function public.post_repair_status_v1(
  p_idempotency_key uuid, p_payload jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_repair public.repairs%rowtype;
  v_status text;
  v_expected bigint;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_version bigint;
  v_result jsonb;
begin
  v_claim := private.repair_claim(p_idempotency_key, p_payload, 'repair_status');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.repair_require_keys(p_payload, array[
    'expected_version', 'kind', 'repair_id', 'status', 'version'
  ]);
  v_status := p_payload ->> 'status';
  if pg_catalog.jsonb_typeof(p_payload -> 'status') is distinct from 'string'
    or v_status not in ('in_progress', 'ready') then
    raise exception 'invalid_input';
  end if;
  v_expected := private.repair_money(p_payload -> 'expected_version', false);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_repair := private.repair_lock(v_shop, private.repair_uuid(p_payload -> 'repair_id'), v_expected);
  if not (
    (v_repair.status = 'received' and v_status = 'in_progress')
    or (v_repair.status = 'in_progress' and v_status = 'ready')
  ) then
    raise exception 'invalid_input';
  end if;
  v_actor := auth.uid();
  select shop.owner_display_name into v_actor_name
  from public.shops as shop where shop.id = v_shop;
  v_at := pg_catalog.clock_timestamp();
  update public.repairs
    set status = v_status,
        record_version = record_version + 1,
        updated_at = v_at
  where id = v_repair.id
  returning record_version into v_version;
  perform private.repair_event(
    v_shop, v_repair.id, 'repair_status', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'from_status', v_repair.status,
      'status', v_status,
      'record_version', v_version::text
    )
  );
  v_result := pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'repair_id', v_repair.id,
    'status', v_status,
    'record_version', v_version::text
  );
  return private.repair_finish(
    v_shop, p_idempotency_key, 'repair_status', p_payload,
    v_claim ->> 'hash', v_repair.id, v_result
  );
end;
$fn$;

create function private.repair_tenders(p_tenders jsonb, p_expected bigint)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_tender jsonb;
  v_seen text[] := '{}';
  v_method text;
  v_sum numeric := 0;
  v_count integer;
begin
  if pg_catalog.jsonb_typeof(p_tenders) is distinct from 'array' then
    raise exception 'invalid_input';
  end if;
  v_count := pg_catalog.jsonb_array_length(p_tenders);
  if p_expected = 0 then
    if v_count <> 0 then
      raise exception 'invalid_input';
    end if;
    return;
  end if;
  if v_count < 1 or v_count > 4 then
    raise exception 'invalid_input';
  end if;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_tenders) as tender(value)
  loop
    if pg_catalog.jsonb_typeof(v_tender) is distinct from 'object'
      or not (v_tender ?& array['method', 'piastres'])
      or v_tender - 'method' - 'piastres' <> '{}'::jsonb
      or pg_catalog.jsonb_typeof(v_tender -> 'method') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any(v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_method);
    v_sum := v_sum + private.repair_money(v_tender -> 'piastres', false);
  end loop;
  if v_sum <> p_expected then
    raise exception 'tender_mismatch';
  end if;
end;
$fn$;

create function public.post_repair_handover_v1(
  p_idempotency_key uuid, p_payload jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_repair public.repairs%rowtype;
  v_expected bigint;
  v_final bigint;
  v_collected bigint;
  v_collection text;
  v_day uuid;
  v_day_version bigint;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_op uuid;
  v_version bigint;
  v_outstanding bigint;
  v_result jsonb;
begin
  v_claim := private.repair_claim(p_idempotency_key, p_payload, 'repair_handover');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.repair_allow_keys(
    p_payload,
    array[
      'collected_piastres', 'collection', 'expected_version', 'final_fee_piastres',
      'kind', 'repair_id', 'tenders', 'version'
    ],
    array['expected_day_id', 'expected_day_version']
  );
  v_collection := p_payload ->> 'collection';
  if pg_catalog.jsonb_typeof(p_payload -> 'collection') is distinct from 'string'
    or v_collection not in ('all', 'part', 'none') then
    raise exception 'invalid_input';
  end if;
  v_expected := private.repair_money(p_payload -> 'expected_version', false);
  v_final := private.repair_money(p_payload -> 'final_fee_piastres', true);
  v_collected := private.repair_money(p_payload -> 'collected_piastres', true);
  if v_collected > v_final or v_final = 0 and v_collection <> 'none' then
    raise exception 'invalid_input';
  end if;
  if v_collection = 'none' then
    if v_collected <> 0
      or (p_payload ? 'expected_day_id')
      or (p_payload ? 'expected_day_version') then
      raise exception 'invalid_input';
    end if;
  elsif v_collection = 'all' then
    if v_collected <> v_final or v_collected <= 0 then
      raise exception 'invalid_input';
    end if;
  elsif v_collected <= 0 or v_collected >= v_final then
    raise exception 'invalid_input';
  end if;
  perform private.repair_tenders(p_payload -> 'tenders', v_collected);
  if v_collected > 0 then
    if not (p_payload ? 'expected_day_id')
      or not (p_payload ? 'expected_day_version')
      or pg_catalog.jsonb_typeof(p_payload -> 'expected_day_id') is distinct from 'string'
      or pg_catalog.jsonb_typeof(p_payload -> 'expected_day_version') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_day := private.repair_uuid(p_payload -> 'expected_day_id');
    v_day_version := private.repair_money(p_payload -> 'expected_day_version', false);
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_repair := private.repair_lock(
    v_shop, private.repair_uuid(p_payload -> 'repair_id'), v_expected
  );
  if v_repair.status <> 'ready' or not v_repair.custody_held then
    raise exception 'repair_not_ready';
  end if;
  v_actor := auth.uid();
  select shop.owner_display_name into v_actor_name
  from public.shops as shop where shop.id = v_shop;
  v_at := pg_catalog.clock_timestamp();
  v_outstanding := v_final - v_collected;
  if v_collected > 0 then
    v_op := private.repair_post_fee(
      v_shop, v_repair.id, p_idempotency_key, p_payload, v_claim ->> 'hash',
      v_actor, v_at, v_collected, v_day, v_day_version
    );
  end if;
  update public.repairs
    set status = 'delivered',
        record_version = record_version + 1,
        final_fee_piastres = v_final,
        collected_piastres = v_collected,
        outstanding_piastres = v_outstanding,
        custody_held = false,
        financial_operation_id = v_op,
        updated_at = v_at
  where id = v_repair.id
  returning record_version into v_version;
  insert into public.repair_custody_events (
    shop_id, repair_id, direction, measured_milligrams, karat, actor_user_id, created_at
  ) values (
    v_shop, v_repair.id, 'release', v_repair.measured_milligrams,
    v_repair.karat, v_actor, v_at
  );
  perform private.repair_event(
    v_shop, v_repair.id, 'repair_handover', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'final_fee_piastres', v_final::text,
      'collected_piastres', v_collected::text,
      'outstanding_piastres', v_outstanding::text,
      'custody_released_milligrams', v_repair.measured_milligrams::text,
      'stock_milligrams', '0',
      'operation_id', v_op
    )
  );
  v_result := pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'repair_id', v_repair.id,
    'status', 'delivered',
    'record_version', v_version::text,
    'final_fee_piastres', v_final::text,
    'collected_piastres', v_collected::text,
    'outstanding_piastres', v_outstanding::text,
    'custody_released_milligrams', v_repair.measured_milligrams::text,
    'stock_milligrams', '0',
    'operation_id', v_op,
    'business_day_id', case when v_op is null then null else v_day end,
    'day_version', case
      when v_op is null then null
      else (v_day_version + 1)::text
    end
  );
  return private.repair_finish(
    v_shop, p_idempotency_key, 'repair_handover', p_payload,
    v_claim ->> 'hash', v_repair.id, v_result
  );
end;
$fn$;

create function public.post_repair_cancel_v1(
  p_idempotency_key uuid, p_payload jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_repair public.repairs%rowtype;
  v_expected bigint;
  v_reason text;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_version bigint;
  v_result jsonb;
begin
  v_claim := private.repair_claim(p_idempotency_key, p_payload, 'repair_cancel');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.repair_require_keys(p_payload, array[
    'confirm_return', 'expected_version', 'kind', 'reason', 'repair_id', 'version'
  ]);
  if p_payload -> 'confirm_return' is distinct from 'true'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_reason := private.repair_text(p_payload -> 'reason', 1, 500);
  v_expected := private.repair_money(p_payload -> 'expected_version', false);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_repair := private.repair_lock(
    v_shop, private.repair_uuid(p_payload -> 'repair_id'), v_expected
  );
  if v_repair.status not in ('received', 'in_progress', 'ready')
    or not v_repair.custody_held then
    raise exception 'repair_not_active';
  end if;
  v_actor := auth.uid();
  select shop.owner_display_name into v_actor_name
  from public.shops as shop where shop.id = v_shop;
  v_at := pg_catalog.clock_timestamp();
  update public.repairs
    set status = 'cancelled',
        record_version = record_version + 1,
        custody_held = false,
        cancellation_reason = v_reason,
        updated_at = v_at
  where id = v_repair.id
  returning record_version into v_version;
  insert into public.repair_custody_events (
    shop_id, repair_id, direction, measured_milligrams, karat, actor_user_id, created_at
  ) values (
    v_shop, v_repair.id, 'release', v_repair.measured_milligrams,
    v_repair.karat, v_actor, v_at
  );
  perform private.repair_event(
    v_shop, v_repair.id, 'repair_cancel', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'reason', v_reason,
      'custody_released_milligrams', v_repair.measured_milligrams::text,
      'cash_piastres', '0',
      'stock_milligrams', '0'
    )
  );
  v_result := pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'repair_id', v_repair.id,
    'status', 'cancelled',
    'record_version', v_version::text,
    'custody_released_milligrams', v_repair.measured_milligrams::text,
    'cash_piastres', '0',
    'stock_milligrams', '0'
  );
  return private.repair_finish(
    v_shop, p_idempotency_key, 'repair_cancel', p_payload,
    v_claim ->> 'hash', v_repair.id, v_result
  );
end;
$fn$;

create function public.post_repair_archive_v1(
  p_idempotency_key uuid, p_payload jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_repair public.repairs%rowtype;
  v_expected bigint;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_version bigint;
  v_result jsonb;
begin
  v_claim := private.repair_claim(p_idempotency_key, p_payload, 'repair_archive');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.repair_require_keys(p_payload, array[
    'confirm_archive', 'expected_version', 'kind', 'repair_id', 'version'
  ]);
  if p_payload -> 'confirm_archive' is distinct from 'true'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_expected := private.repair_money(p_payload -> 'expected_version', false);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_repair := private.repair_lock(
    v_shop, private.repair_uuid(p_payload -> 'repair_id'), v_expected
  );
  if v_repair.status not in ('delivered', 'cancelled') then
    raise exception 'repair_not_terminal';
  end if;
  v_actor := auth.uid();
  select shop.owner_display_name into v_actor_name
  from public.shops as shop where shop.id = v_shop;
  v_at := pg_catalog.clock_timestamp();
  update public.repairs
    set status = 'archived',
        archived_from_status = v_repair.status,
        record_version = record_version + 1,
        updated_at = v_at
  where id = v_repair.id
  returning record_version into v_version;
  perform private.repair_event(
    v_shop, v_repair.id, 'repair_archive', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'from_status', v_repair.status,
      'outstanding_piastres', v_repair.outstanding_piastres::text,
      'cash_piastres', '0'
    )
  );
  v_result := pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'repair_id', v_repair.id,
    'status', 'archived',
    'record_version', v_version::text,
    'outstanding_piastres', v_repair.outstanding_piastres::text,
    'cash_piastres', '0'
  );
  return private.repair_finish(
    v_shop, p_idempotency_key, 'repair_archive', p_payload,
    v_claim ->> 'hash', v_repair.id, v_result
  );
end;
$fn$;

create function public.get_repair_command_status(p_idempotency_key uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_request public.repair_command_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select request.* into v_request
  from public.repair_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key;
  if v_request.id is null then
    return pg_catalog.jsonb_build_object('status', 'absent');
  end if;
  return pg_catalog.jsonb_build_object(
    'status', 'completed',
    'repair_id', v_request.repair_id,
    'command_kind', v_request.command_kind,
    'result', v_request.result
  );
end;
$fn$;

create function public.get_repair_context_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_day public.business_days%rowtype;
  v_cash jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  v_shop := private.opening_require_reader_shop();
  select shop.time_zone into v_zone
  from public.shops as shop where shop.id = v_shop;
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
    'cash_methods', coalesce(v_cash, '[]'::jsonb)
  );
end;
$fn$;

create function public.list_repairs_v1(
  p_query text, p_filter text, p_limit integer, p_cursor text
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_filter text := coalesce(p_filter, 'open');
  v_limit integer := coalesce(p_limit, 20);
  v_query text := coalesce(pg_catalog.btrim(p_query), '');
  v_like text;
  v_cursor uuid;
  v_cursor_at timestamptz;
  v_rows jsonb;
  v_next text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if v_filter not in ('open', 'delivered', 'cancelled', 'archived', 'outstanding', 'all')
    or v_limit < 1 or v_limit > 50
    or pg_catalog.char_length(v_query) > 80 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select shop.time_zone into v_zone from public.shops as shop where shop.id = v_shop;
  if p_cursor is not null and pg_catalog.btrim(p_cursor) <> '' then
    begin
      v_cursor := pg_catalog.btrim(p_cursor)::uuid;
    exception
      when invalid_text_representation then
        raise exception 'invalid_input';
    end;
    select repair.intake_at into v_cursor_at
    from public.repairs as repair
    where repair.shop_id = v_shop and repair.id = v_cursor;
    if v_cursor_at is null then
      raise exception 'invalid_input';
    end if;
  end if;
  v_like := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  with matched as (
    select repair.*
    from public.repairs as repair
    where repair.shop_id = v_shop
      and (
        v_filter = 'all'
        or (v_filter = 'open' and repair.status in ('received', 'in_progress', 'ready'))
        or (v_filter = 'delivered' and repair.status = 'delivered')
        or (v_filter = 'cancelled' and repair.status = 'cancelled')
        or (v_filter = 'archived' and repair.status = 'archived')
        or (v_filter = 'outstanding' and repair.outstanding_piastres > 0)
      )
      and (
        v_query = ''
        or repair.customer_name ilike v_like escape '\'
        or repair.customer_phone ilike v_like escape '\'
        or repair.item_description ilike v_like escape '\'
        or repair.issue ilike v_like escape '\'
      )
      and (
        v_cursor is null
        or (repair.intake_at, repair.id) < (v_cursor_at, v_cursor)
      )
    order by repair.intake_at desc, repair.id desc
    limit v_limit + 1
  ), page as (
    select matched.*
    from matched
    order by matched.intake_at desc, matched.id desc
    limit v_limit
  )
  select
    coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'repair_id', item.id,
        'status', item.status,
        'record_version', item.record_version::text,
        'customer_name', item.customer_name,
        'customer_phone', item.customer_phone,
        'item_description', item.item_description,
        'measured_milligrams', item.measured_milligrams::text,
        'karat', item.karat,
        'issue', item.issue,
        'custody_held', item.custody_held,
        'estimated_fee_piastres', item.estimated_fee_piastres::text,
        'final_fee_piastres', item.final_fee_piastres::text,
        'collected_piastres', item.collected_piastres::text,
        'outstanding_piastres', item.outstanding_piastres::text,
        'intake_at', pg_catalog.to_char(item.intake_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'intake_at_shop', pg_catalog.to_char(
          item.intake_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
        )
      ) order by item.intake_at desc, item.id desc)
      from page as item
    ), '[]'::jsonb),
    case
      when (select count(*) from matched) > v_limit then (
        select edge.id::text
        from page as edge
        order by edge.intake_at asc, edge.id asc
        limit 1
      )
      else null
    end
  into v_rows, v_next;
  return pg_catalog.jsonb_build_object(
    'items', coalesce(v_rows, '[]'::jsonb),
    'next_cursor', v_next
  );
end;
$fn$;

create function public.get_repair_v1(p_repair_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_repair public.repairs%rowtype;
  v_events jsonb;
  v_custody jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_repair_id is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select shop.time_zone into v_zone from public.shops as shop where shop.id = v_shop;
  select repair.* into v_repair
  from public.repairs as repair
  where repair.shop_id = v_shop and repair.id = p_repair_id;
  if v_repair.id is null then
    raise exception 'not_found';
  end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', event.id,
    'event_type', event.event_type,
    'actor_user_id', event.actor_user_id,
    'actor_display_name', event.actor_display_name,
    'created_at', pg_catalog.to_char(event.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'created_at_shop', pg_catalog.to_char(
      event.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'payload', event.payload
  ) order by event.created_at, event.id), '[]'::jsonb)
    into v_events
  from public.repair_events as event
  where event.shop_id = v_shop and event.repair_id = v_repair.id;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'id', custody.id,
    'direction', custody.direction,
    'measured_milligrams', custody.measured_milligrams::text,
    'karat', custody.karat,
    'actor_user_id', custody.actor_user_id,
    'created_at', pg_catalog.to_char(custody.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'created_at_shop', pg_catalog.to_char(
      custody.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
    )
  ) order by custody.created_at, custody.id), '[]'::jsonb)
    into v_custody
  from public.repair_custody_events as custody
  where custody.shop_id = v_shop and custody.repair_id = v_repair.id;
  return pg_catalog.jsonb_build_object(
    'repair_id', v_repair.id,
    'status', v_repair.status,
    'record_version', v_repair.record_version::text,
    'customer_name', v_repair.customer_name,
    'customer_phone', v_repair.customer_phone,
    'item_description', v_repair.item_description,
    'measured_milligrams', v_repair.measured_milligrams::text,
    'karat', v_repair.karat,
    'issue', v_repair.issue,
    'intake_notes', v_repair.intake_notes,
    'estimated_fee_piastres', v_repair.estimated_fee_piastres::text,
    'final_fee_piastres', v_repair.final_fee_piastres::text,
    'collected_piastres', v_repair.collected_piastres::text,
    'outstanding_piastres', v_repair.outstanding_piastres::text,
    'custody_held', v_repair.custody_held,
    'financial_operation_id', v_repair.financial_operation_id,
    'cancellation_reason', v_repair.cancellation_reason,
    'archived_from_status', v_repair.archived_from_status,
    'intake_actor_user_id', v_repair.intake_actor_user_id,
    'intake_at', pg_catalog.to_char(v_repair.intake_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'intake_at_shop', pg_catalog.to_char(
      v_repair.intake_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'time_zone', v_zone,
    'original_intake', v_repair.intake_payload,
    'events', v_events,
    'custody_events', v_custody
  );
end;
$fn$;

revoke all on function private.repair_guard() from public, anon, authenticated;
revoke all on function private.repair_reject_mutation() from public, anon, authenticated;
revoke all on function private.repair_require_keys(jsonb, text[]) from public, anon, authenticated;
revoke all on function private.repair_allow_keys(jsonb, text[], text[]) from public, anon, authenticated;
revoke all on function private.repair_text(jsonb, integer, integer) from public, anon, authenticated;
revoke all on function private.repair_money(jsonb, boolean) from public, anon, authenticated;
revoke all on function private.repair_uuid(jsonb) from public, anon, authenticated;
revoke all on function private.repair_claim(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function private.repair_finish(uuid, uuid, text, jsonb, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function private.repair_event(uuid, uuid, text, uuid, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function private.repair_post_fee(uuid, uuid, uuid, jsonb, text, uuid, timestamptz, bigint, uuid, bigint) from public, anon, authenticated;
revoke all on function private.repair_lock(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function private.repair_tenders(jsonb, bigint) from public, anon, authenticated;
revoke all on function private.bump_shop_sync(uuid, text) from public, anon, authenticated;
revoke all on function private.shop_sync_touch() from public, anon, authenticated;
revoke all on function private.ledger_operation_label(text) from public, anon, authenticated;

revoke all on function public.post_repair_intake_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_repair_status_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_repair_handover_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_repair_cancel_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_repair_archive_v1(uuid, jsonb) from public, anon;
revoke all on function public.get_repair_command_status(uuid) from public, anon;
revoke all on function public.get_repair_context_v1() from public, anon;
revoke all on function public.list_repairs_v1(text, text, integer, text) from public, anon;
revoke all on function public.get_repair_v1(uuid) from public, anon;

grant execute on function public.post_repair_intake_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_repair_status_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_repair_handover_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_repair_cancel_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_repair_archive_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_repair_command_status(uuid) to authenticated;
grant execute on function public.get_repair_context_v1() to authenticated;
grant execute on function public.list_repairs_v1(text, text, integer, text) to authenticated;
grant execute on function public.get_repair_v1(uuid) to authenticated;

commit;

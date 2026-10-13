-- CRM-01 / CRM-03. Customers, phones, append-only notes, and explicit links
-- to confirmed sale/purchase operations. Links do not change cash, stock,
-- debt, business days, or immutable financial payloads. Archive/restore is
-- the deletion policy. A customer may have no phone. Shop locale is Arabic
-- because shops store a time zone and not a separate locale column.
begin;

alter table public.shop_sync_signals
  add column customer_revision bigint not null default 0
  check (customer_revision >= 0);

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
    repair_revision, debt_revision, customer_revision, updated_at
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
    case when p_scope = 'customer' then 1 else 0 end,
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
        customer_revision = public.shop_sync_signals.customer_revision
          + case when p_scope = 'customer' then 1 else 0 end,
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
    when 'customers' then 'customer'
    when 'customer_phones' then 'customer'
    when 'customer_notes' then 'customer'
    when 'customer_events' then 'customer'
    when 'customer_operation_links' then 'customer'
    else 'ledger'
  end;
  perform private.bump_shop_sync(v_shop, v_scope);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$fn$;

create table public.customers (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  status text not null,
  record_version bigint not null,
  display_name text not null,
  is_vip boolean not null,
  has_open_request boolean not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  archived_at timestamptz,
  created_by uuid not null,
  constraint customers_shop_id_id_key unique (shop_id, id),
  constraint customers_status_check check (status in ('active', 'archived')),
  constraint customers_version_check check (record_version >= 1),
  constraint customers_name_check check (
    pg_catalog.char_length(display_name) between 1 and 200
    and display_name = pg_catalog.btrim(display_name)
    and display_name ~ '[ء-ي]'
  ),
  constraint customers_archive_check check (
    (status = 'active' and archived_at is null)
    or (status = 'archived' and archived_at is not null)
  ),
  constraint customers_actor_fkey
    foreign key (shop_id, created_by)
    references public.shop_memberships (shop_id, user_id)
);

create index customers_shop_name_idx
  on public.customers (shop_id, display_name, id);
create index customers_shop_status_idx
  on public.customers (shop_id, status, id);
create index customers_actor_idx
  on public.customers (shop_id, created_by);

create table public.customer_phones (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  customer_id uuid not null,
  raw_number text not null,
  normalized_number text not null,
  is_primary boolean not null,
  created_at timestamptz not null,
  constraint customer_phones_raw_check check (
    pg_catalog.char_length(raw_number) between 1 and 32
    and raw_number = pg_catalog.btrim(raw_number)
  ),
  constraint customer_phones_normalized_check check (
    normalized_number ~ '^\+[1-9][0-9]{6,14}$'
    and (
      pg_catalog.left(normalized_number, 3) <> '+20'
      or normalized_number ~ '^\+201[0125][0-9]{8}$'
      or normalized_number ~ '^\+20[2-9][0-9]{7,8}$'
    )
  ),
  constraint customer_phones_customer_fkey
    foreign key (shop_id, customer_id)
    references public.customers (shop_id, id)
);

create unique index customer_phones_normalized_uidx
  on public.customer_phones (shop_id, normalized_number);
create unique index customer_phones_one_primary_uidx
  on public.customer_phones (customer_id)
  where is_primary;
create index customer_phones_customer_idx
  on public.customer_phones (shop_id, customer_id);

create table public.customer_notes (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  customer_id uuid not null,
  body text not null,
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  constraint customer_notes_body_check check (
    pg_catalog.char_length(body) between 1 and 1000
    and body = pg_catalog.btrim(body)
  ),
  constraint customer_notes_customer_fkey
    foreign key (shop_id, customer_id)
    references public.customers (shop_id, id),
  constraint customer_notes_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create index customer_notes_customer_idx
  on public.customer_notes (shop_id, customer_id, created_at desc, id desc);
create index customer_notes_actor_idx
  on public.customer_notes (shop_id, actor_user_id);

create table public.customer_events (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  customer_id uuid not null,
  event_type text not null,
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  payload jsonb not null,
  constraint customer_events_type_check check (
    event_type in (
      'created', 'edited', 'note_added', 'status_changed',
      'archived', 'restored', 'linked', 'unlinked'
    )
  ),
  constraint customer_events_payload_check check (pg_catalog.jsonb_typeof(payload) = 'object'),
  constraint customer_events_customer_fkey
    foreign key (shop_id, customer_id)
    references public.customers (shop_id, id),
  constraint customer_events_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create index customer_events_customer_idx
  on public.customer_events (shop_id, customer_id, created_at desc, id desc);
create index customer_events_actor_idx
  on public.customer_events (shop_id, actor_user_id);

create table public.customer_command_requests (
  shop_id uuid not null references public.shops (id),
  idempotency_key uuid not null,
  command_kind text not null,
  customer_id uuid not null,
  payload_canonical jsonb not null,
  payload_sha256 bytea not null,
  result jsonb not null,
  created_at timestamptz not null,
  primary key (shop_id, idempotency_key),
  constraint customer_command_requests_kind_check check (
    command_kind in (
      'customer_create', 'customer_edit', 'customer_note', 'customer_status',
      'customer_archive', 'customer_restore', 'customer_link', 'customer_unlink'
    )
  ),
  constraint customer_command_requests_payload_check check (
    pg_catalog.jsonb_typeof(payload_canonical) = 'object'
    and pg_catalog.jsonb_typeof(result) = 'object'
    and pg_catalog.octet_length(payload_sha256) = 32
  ),
  constraint customer_command_requests_customer_fkey
    foreign key (shop_id, customer_id)
    references public.customers (shop_id, id)
);

create index customer_command_requests_customer_idx
  on public.customer_command_requests (shop_id, customer_id);

create table public.customer_operation_links (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  customer_id uuid not null,
  operation_id uuid not null,
  status text not null,
  linked_at timestamptz not null,
  linked_by uuid not null,
  unlinked_at timestamptz,
  unlinked_by uuid,
  constraint customer_operation_links_status_check check (status in ('active', 'unlinked')),
  constraint customer_operation_links_unlink_check check (
    (status = 'active' and unlinked_at is null and unlinked_by is null)
    or (status = 'unlinked' and unlinked_at is not null and unlinked_by is not null)
  ),
  constraint customer_operation_links_customer_fkey
    foreign key (shop_id, customer_id)
    references public.customers (shop_id, id),
  constraint customer_operation_links_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint customer_operation_links_linked_by_fkey
    foreign key (shop_id, linked_by)
    references public.shop_memberships (shop_id, user_id),
  constraint customer_operation_links_unlinked_by_fkey
    foreign key (shop_id, unlinked_by)
    references public.shop_memberships (shop_id, user_id)
);

create unique index customer_operation_links_one_active_uidx
  on public.customer_operation_links (shop_id, operation_id)
  where status = 'active';
create index customer_operation_links_customer_idx
  on public.customer_operation_links (shop_id, customer_id, status);
create index customer_operation_links_operation_idx
  on public.customer_operation_links (shop_id, operation_id);
create index customer_operation_links_linked_by_idx
  on public.customer_operation_links (shop_id, linked_by);
create index customer_operation_links_unlinked_by_idx
  on public.customer_operation_links (shop_id, unlinked_by)
  where unlinked_by is not null;

create function private.customer_guard()
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
    if new.status is distinct from 'active'
      or new.record_version <> 1
      or new.archived_at is not null
      or new.created_at is null
      or new.updated_at is null then
      raise exception 'invalid_input';
    end if;
    return new;
  end if;
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.created_at is distinct from old.created_at
    or new.created_by is distinct from old.created_by then
    raise exception 'audit_append_only';
  end if;
  if new.record_version is distinct from old.record_version + 1 then
    raise exception 'invalid_input';
  end if;
  if old.status = 'active' and new.status not in ('active', 'archived') then
    raise exception 'invalid_input';
  end if;
  if old.status = 'archived' and new.status not in ('archived', 'active') then
    raise exception 'invalid_input';
  end if;
  if new.status = 'archived' and old.status = 'active' then
    if new.archived_at is null then
      raise exception 'invalid_input';
    end if;
  elsif new.status = 'active' and old.status = 'archived' then
    if new.archived_at is not null then
      raise exception 'invalid_input';
    end if;
  elsif new.archived_at is distinct from old.archived_at then
    raise exception 'audit_append_only';
  end if;
  return new;
end;
$fn$;

create trigger customers_guard
before insert or update or delete on public.customers
for each row execute function private.customer_guard();

create function private.customer_reject_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  raise exception 'audit_append_only';
end;
$fn$;

create trigger customer_notes_append_only
before update or delete on public.customer_notes
for each row execute function private.customer_reject_mutation();
create trigger customer_events_append_only
before update or delete on public.customer_events
for each row execute function private.customer_reject_mutation();
create trigger customer_commands_append_only
before update or delete on public.customer_command_requests
for each row execute function private.customer_reject_mutation();

create function private.customer_phone_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' then
    raise exception 'audit_append_only';
  end if;
  return coalesce(new, old);
end;
$fn$;

create trigger customer_phones_no_update
before update on public.customer_phones
for each row execute function private.customer_phone_guard();

create function private.customer_link_guard()
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
    if new.status is distinct from 'active'
      or new.unlinked_at is not null
      or new.unlinked_by is not null then
      raise exception 'invalid_input';
    end if;
    return new;
  end if;
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.customer_id is distinct from old.customer_id
    or new.operation_id is distinct from old.operation_id
    or new.linked_at is distinct from old.linked_at
    or new.linked_by is distinct from old.linked_by then
    raise exception 'audit_append_only';
  end if;
  if old.status is distinct from 'active' or new.status is distinct from 'unlinked' then
    raise exception 'invalid_input';
  end if;
  if new.unlinked_at is null or new.unlinked_by is null then
    raise exception 'invalid_input';
  end if;
  return new;
end;
$fn$;

create trigger customer_operation_links_guard
before insert or update or delete on public.customer_operation_links
for each row execute function private.customer_link_guard();

create trigger shop_sync_customers
after insert or update or delete on public.customers
for each row execute function private.shop_sync_touch();
create trigger shop_sync_customer_phones
after insert or update or delete on public.customer_phones
for each row execute function private.shop_sync_touch();
create trigger shop_sync_customer_notes
after insert or update or delete on public.customer_notes
for each row execute function private.shop_sync_touch();
create trigger shop_sync_customer_events
after insert or update or delete on public.customer_events
for each row execute function private.shop_sync_touch();
create trigger shop_sync_customer_operation_links
after insert or update or delete on public.customer_operation_links
for each row execute function private.shop_sync_touch();

alter table public.customers enable row level security;
alter table public.customers force row level security;
alter table public.customer_phones enable row level security;
alter table public.customer_phones force row level security;
alter table public.customer_notes enable row level security;
alter table public.customer_notes force row level security;
alter table public.customer_events enable row level security;
alter table public.customer_events force row level security;
alter table public.customer_command_requests enable row level security;
alter table public.customer_command_requests force row level security;
alter table public.customer_operation_links enable row level security;
alter table public.customer_operation_links force row level security;

revoke all on table public.customers from public, anon, authenticated;
revoke all on table public.customer_phones from public, anon, authenticated;
revoke all on table public.customer_notes from public, anon, authenticated;
revoke all on table public.customer_events from public, anon, authenticated;
revoke all on table public.customer_command_requests from public, anon, authenticated;
revoke all on table public.customer_operation_links from public, anon, authenticated;
grant select on table public.customers to authenticated;
grant select on table public.customer_phones to authenticated;
grant select on table public.customer_notes to authenticated;
grant select on table public.customer_events to authenticated;
grant select on table public.customer_command_requests to authenticated;
grant select on table public.customer_operation_links to authenticated;

create policy customers_owner_read
  on public.customers for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy customer_phones_owner_read
  on public.customer_phones for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy customer_notes_owner_read
  on public.customer_notes for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy customer_events_owner_read
  on public.customer_events for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy customer_commands_owner_read
  on public.customer_command_requests for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy customer_links_owner_read
  on public.customer_operation_links for select to authenticated
  using (private.opening_financial_visible(shop_id));

create function private.customer_require_keys(p_payload jsonb, p_keys text[])
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

create function private.customer_exact_text(p_value jsonb, p_min integer, p_max integer)
returns text
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
  v_text := p_value #>> '{}';
  if v_text is distinct from pg_catalog.btrim(v_text)
    or v_text ~ '[[:cntrl:]]'
    or pg_catalog.char_length(v_text) < p_min
    or pg_catalog.char_length(v_text) > p_max then
    raise exception 'invalid_input';
  end if;
  return v_text;
end;
$fn$;

create function private.customer_note_body(p_value jsonb) returns text
language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_text text;
begin
 if jsonb_typeof(p_value) is distinct from 'string' then raise exception 'invalid_input'; end if;
 v_text := p_value #>> '{}';
 if char_length(v_text) not between 1 and 1000 or v_text <> btrim(v_text,E' \t\r\n')
  or translate(v_text,E'\t\r\n','') ~ '[[:cntrl:]]' then raise exception 'invalid_input'; end if;
 return v_text;
end;$fn$;

create function private.customer_name(p_value jsonb)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
begin
  v_text := private.customer_exact_text(p_value, 1, 200);
  if v_text !~ '[ء-ي]' then
    raise exception 'invalid_name';
  end if;
  return v_text;
end;
$fn$;

create function private.customer_bool(p_value jsonb)
returns boolean
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'boolean' then
    raise exception 'invalid_input';
  end if;
  return p_value = 'true'::jsonb;
end;
$fn$;

create function private.customer_uuid(p_value jsonb)
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

create function private.customer_expected_version(p_value jsonb)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string'
    or (p_value #>> '{}') !~ '^[1-9][0-9]{0,18}$' then
    raise exception 'invalid_input';
  end if;
  return (p_value #>> '{}')::bigint;
end;
$fn$;

create function private.customer_fold_digits(p_text text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select pg_catalog.translate(
    coalesce(p_text, ''),
    '٠١٢٣٤٥٦٧٨٩۰۱۲۳۴۵۶۷۸۹',
    '01234567890123456789'
  );
$fn$;

create function private.customer_normalize_phone(p_raw text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
  v_national text;
begin
  if p_raw is null
    or p_raw <> pg_catalog.btrim(p_raw)
    or pg_catalog.char_length(p_raw) < 1
    or pg_catalog.char_length(p_raw) > 32
    or p_raw ~ '[[:cntrl:]]' then
    raise exception 'invalid_phone';
  end if;
  v_text := private.customer_fold_digits(p_raw);
  if v_text ~ '[^0-9+ ().-]' then
    raise exception 'invalid_phone';
  end if;
  v_text := pg_catalog.regexp_replace(v_text, '[ ().-]', '', 'g');
  if v_text = '' then
    raise exception 'invalid_phone';
  end if;
  if pg_catalog.left(v_text, 2) = '00' then
    v_text := '+' || pg_catalog.substring(v_text, 3);
  end if;
  if pg_catalog.left(v_text, 1) = '0' then
    v_national := pg_catalog.substring(v_text, 2);
    if v_national ~ '^1[0125][0-9]{8}$' or v_national ~ '^[2-9][0-9]{7,8}$' then
      v_text := '+20' || v_national;
    else
      raise exception 'invalid_phone';
    end if;
  end if;
  if v_text !~ '^\+[1-9][0-9]{6,14}$' then
    raise exception 'invalid_phone';
  end if;
  if pg_catalog.left(v_text, 3) = '+20'
    and v_text !~ '^\+201[0125][0-9]{8}$'
    and v_text !~ '^\+20[2-9][0-9]{7,8}$' then
    raise exception 'invalid_phone';
  end if;
  return v_text;
end;
$fn$;

create function private.customer_parse_phones(p_phones jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_phone jsonb;
  v_raw text;
  v_norm text;
  v_primary boolean;
  v_seen text[] := '{}';
  v_primary_count integer := 0;
  v_count integer := 0;
  v_rows jsonb := '[]'::jsonb;
begin
  if pg_catalog.jsonb_typeof(p_phones) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_phones) > 10 then
    raise exception 'invalid_input';
  end if;
  for v_phone in
    select entry.value from pg_catalog.jsonb_array_elements(p_phones) as entry(value)
  loop
    v_count := v_count + 1;
    perform private.customer_require_keys(v_phone, array['is_primary', 'number']);
    if pg_catalog.jsonb_typeof(v_phone -> 'number') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_raw := v_phone ->> 'number';
    v_norm := private.customer_normalize_phone(v_raw);
    v_primary := private.customer_bool(v_phone -> 'is_primary');
    if v_norm = any(v_seen) then
      raise exception 'duplicate_phone';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_norm);
    if v_primary then
      v_primary_count := v_primary_count + 1;
    end if;
    v_rows := v_rows || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'raw', v_raw,
      'normalized', v_norm,
      'is_primary', v_primary
    ));
  end loop;
  if v_count = 0 and v_primary_count <> 0 then
    raise exception 'invalid_input';
  end if;
  if v_count > 0 and v_primary_count = 0 then
    raise exception 'primary_required';
  end if;
  if v_primary_count > 1 then
    raise exception 'duplicate_primary';
  end if;
  return v_rows;
end;
$fn$;

create function private.customer_limit(p_limit integer)
returns integer
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if p_limit is null then
    return 20;
  end if;
  if p_limit < 1 or p_limit > 50 then
    raise exception 'invalid_input';
  end if;
  return p_limit;
end;
$fn$;

create function private.customer_utc(p_at timestamptz)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case
    when p_at is null then null
    else pg_catalog.to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
  end;
$fn$;

create function private.customer_local(p_at timestamptz, p_zone text)
returns text
language sql
stable
security invoker
set search_path = ''
as $fn$
  select case
    when p_at is null then null
    else pg_catalog.to_char(p_at at time zone p_zone, 'YYYY-MM-DD"T"HH24:MI:SS')
  end;
$fn$;

create function private.customer_cursor_read(
  p_cursor text, p_sort text, p_filter text, p_query text
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_name text;
  v_at timestamptz;
  v_id uuid;
  v_hex text;
  v_time text;
begin
  if p_cursor is null or pg_catalog.btrim(p_cursor) = '' then
    return null;
  end if;
  if pg_catalog.split_part(p_cursor, '|', 1) is distinct from 'v1'
    or pg_catalog.split_part(p_cursor, '|', 2) is distinct from p_sort
    or pg_catalog.split_part(p_cursor, '|', 3) is distinct from p_filter
    or pg_catalog.split_part(p_cursor, '|', 4) is distinct from pg_catalog.md5(coalesce(p_query, ''))
    or pg_catalog.split_part(p_cursor, '|', 5) = ''
    or pg_catalog.split_part(p_cursor, '|', 6) = ''
    or pg_catalog.split_part(p_cursor, '|', 7) = ''
    or pg_catalog.split_part(p_cursor, '|', 8) <> '' then
    return null;
  end if;
  begin
    v_id := pg_catalog.split_part(p_cursor, '|', 7)::uuid;
    v_hex := pg_catalog.split_part(p_cursor, '|', 5);
    v_time := pg_catalog.split_part(p_cursor, '|', 6);
    if p_sort = 'name' then
      if v_hex = '-' or v_time <> '-' then
        return null;
      end if;
      v_name := pg_catalog.convert_from(pg_catalog.decode(v_hex, 'hex'), 'UTF8');
      v_at := null;
    elsif p_sort = 'last_operation' then
      if v_hex <> '-' then
        return null;
      end if;
      v_name := null;
      if v_time = '-' then
        v_at := null;
      else
        v_at := v_time::timestamptz;
      end if;
    else
      return null;
    end if;
  exception
    when others then
      return null;
  end;
  return pg_catalog.jsonb_build_object(
    'name', v_name,
    'at', case when v_at is null then null else private.customer_utc(v_at) end,
    'id', v_id,
    'has_time', v_at is not null
  );
end;
$fn$;

create function private.customer_cursor_pack(
  p_sort text, p_filter text, p_query text, p_name text, p_at timestamptz, p_id uuid
) returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select 'v1|' || p_sort || '|' || p_filter || '|' || pg_catalog.md5(coalesce(p_query, ''))
    || '|' || case
      when p_name is null then '-'
      else pg_catalog.encode(pg_catalog.convert_to(p_name, 'UTF8'), 'hex')
    end
    || '|' || coalesce(
      pg_catalog.to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"+00"'),
      '-'
    )
    || '|' || p_id::text;
$fn$;

create function private.customer_zone(p_shop uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_zone text;
begin
  select shop.time_zone into v_zone from public.shops as shop where shop.id = p_shop;
  return private.shop_display_zone(v_zone);
end;
$fn$;

create function private.customer_actor_name(p_shop uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_name text;
begin
  select shop.owner_display_name into v_name
  from public.shops as shop where shop.id = p_shop;
  return coalesce(nullif(pg_catalog.btrim(v_name), ''), 'المالك');
end;
$fn$;

create function private.customer_last_operation_at(p_shop uuid, p_customer uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $fn$
  select max(operation.created_at)
  from public.customer_operation_links as link
  join public.financial_operations as operation
    on operation.shop_id = link.shop_id
   and operation.id = link.operation_id
  where link.shop_id = p_shop
    and link.customer_id = p_customer
    and link.status = 'active'
    and operation.kind in ('sale', 'purchase');
$fn$;

create function private.customer_view(p_customer public.customers, p_zone text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_phones jsonb;
  v_body text;
  v_note_at timestamptz;
  v_last timestamptz;
begin
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'phone_id', phone.id,
    'raw', phone.raw_number,
    'normalized', phone.normalized_number,
    'is_primary', phone.is_primary
  ) order by phone.is_primary desc, phone.normalized_number, phone.id), '[]'::jsonb)
  into v_phones
  from public.customer_phones as phone
  where phone.shop_id = p_customer.shop_id
    and phone.customer_id = p_customer.id;
  select note.body, note.created_at
    into v_body, v_note_at
  from public.customer_notes as note
  where note.shop_id = p_customer.shop_id
    and note.customer_id = p_customer.id
  order by note.created_at desc, note.id desc
  limit 1;
  v_last := private.customer_last_operation_at(p_customer.shop_id, p_customer.id);
  return pg_catalog.jsonb_build_object(
    'customer_id', p_customer.id,
    'display_name', p_customer.display_name,
    'status', p_customer.status,
    'record_version', p_customer.record_version::text,
    'is_vip', p_customer.is_vip,
    'has_open_request', p_customer.has_open_request,
    'phones', coalesce(v_phones, '[]'::jsonb),
    'latest_note_preview', case
      when v_body is null then null
      else pg_catalog.left(v_body, 120)
    end,
    'latest_note_at', private.customer_utc(v_note_at),
    'latest_note_at_shop', private.customer_local(v_note_at, p_zone),
    'updated_at', private.customer_utc(p_customer.updated_at),
    'updated_at_shop', private.customer_local(p_customer.updated_at, p_zone),
    'created_at', private.customer_utc(p_customer.created_at),
    'created_at_shop', private.customer_local(p_customer.created_at, p_zone),
    'last_operation_at', private.customer_utc(v_last),
    'last_operation_at_shop', private.customer_local(v_last, p_zone),
    'time_zone', p_zone,
    'locale', 'ar'
  );
end;
$fn$;

create function private.customer_operation_public(
  p_operation public.financial_operations, p_zone text
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_payload jsonb;
  v_date date;
begin
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = p_operation.shop_id
    and detail.operation_id = p_operation.id;
  select day.business_date into v_date
  from public.business_days as day
  where day.shop_id = p_operation.shop_id
    and day.id = p_operation.business_day_id;
  return pg_catalog.jsonb_build_object(
    'operation_id', p_operation.id,
    'operation_kind', p_operation.kind,
    'label_ar', private.ledger_operation_label(p_operation.kind),
    'shop_sequence', p_operation.shop_sequence::text,
    'party_name', nullif(pg_catalog.btrim(v_payload ->> 'customer_name'), ''),
    'party_phone', nullif(pg_catalog.btrim(v_payload ->> 'customer_phone'), ''),
    'note', nullif(pg_catalog.btrim(v_payload ->> 'note'), ''),
    'operation_created_at', private.customer_utc(p_operation.created_at),
    'operation_created_at_shop', private.customer_local(p_operation.created_at, p_zone),
    'business_date', case
      when v_date is null then null
      else pg_catalog.to_char(v_date, 'YYYY-MM-DD')
    end
  );
end;
$fn$;

create function private.customer_claim(p_key uuid, p_payload jsonb, p_kind text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_hash bytea;
  v_request public.customer_command_requests%rowtype;
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
  from public.customer_command_requests as request
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

create function private.customer_finish(
  p_shop uuid, p_key uuid, p_kind text, p_payload jsonb, p_hash text,
  p_customer uuid, p_result jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  insert into public.customer_command_requests (
    shop_id, idempotency_key, command_kind, customer_id, payload_canonical,
    payload_sha256, result, created_at
  ) values (
    p_shop, p_key, p_kind, p_customer, p_payload, pg_catalog.decode(p_hash, 'hex'),
    p_result, pg_catalog.clock_timestamp()
  );
  return p_result;
end;
$fn$;

create function private.customer_event(
  p_shop uuid, p_customer uuid, p_type text, p_actor uuid, p_name text,
  p_at timestamptz, p_payload jsonb
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  insert into public.customer_events (
    shop_id, customer_id, event_type, actor_user_id, actor_display_name,
    created_at, payload
  ) values (
    p_shop, p_customer, p_type, p_actor, p_name, p_at, p_payload
  );
end;
$fn$;

create function private.customer_lock(p_shop uuid, p_customer uuid, p_expected bigint)
returns public.customers
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_row public.customers%rowtype;
begin
  select customer.* into v_row
  from public.customers as customer
  where customer.shop_id = p_shop and customer.id = p_customer
  for update;
  if v_row.id is null then
    raise exception 'not_found';
  end if;
  if v_row.record_version is distinct from p_expected then
    raise exception 'stale_customer';
  end if;
  return v_row;
end;
$fn$;

create function private.customer_replace_phones(
  p_shop uuid, p_customer uuid, p_phones jsonb, p_at timestamptz
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_phone jsonb;
begin
  delete from public.customer_phones as phone
  where phone.shop_id = p_shop and phone.customer_id = p_customer;
  for v_phone in
    select entry.value from pg_catalog.jsonb_array_elements(p_phones) as entry(value)
  loop
    if exists (
      select 1 from public.customer_phones as phone
      where phone.shop_id = p_shop
        and phone.normalized_number = v_phone ->> 'normalized'
        and phone.customer_id is distinct from p_customer
    ) then
      raise exception 'phone_conflict';
    end if;
    begin
      insert into public.customer_phones (
        shop_id, customer_id, raw_number, normalized_number, is_primary, created_at
      ) values (
        p_shop, p_customer, v_phone ->> 'raw', v_phone ->> 'normalized',
        (v_phone ->> 'is_primary')::boolean, p_at
      );
    exception
      when unique_violation then
        raise exception 'phone_conflict';
    end;
  end loop;
end;
$fn$;

create function private.customer_require_operation(p_shop uuid, p_operation uuid)
returns public.financial_operations
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_row public.financial_operations%rowtype;
begin
  if p_operation is null then
    raise exception 'invalid_input';
  end if;
  select operation.* into v_row
  from public.financial_operations as operation
  where operation.id = p_operation;
  if v_row.id is null then
    raise exception 'not_found';
  end if;
  if v_row.shop_id is distinct from p_shop then
    raise exception 'cross_shop';
  end if;
  if v_row.kind not in ('sale', 'purchase') then
    raise exception 'wrong_operation_kind';
  end if;
  if not exists (
    select 1 from public.financial_operation_details as detail
    where detail.shop_id = p_shop and detail.operation_id = p_operation
  ) or not exists (
    select 1 from public.financial_audit_events as audit_event
    where audit_event.shop_id = p_shop
      and audit_event.operation_id = p_operation
      and audit_event.action = v_row.kind || '_confirmed'
  ) then
    raise exception 'operation_not_confirmed';
  end if;
  return v_row;
end;
$fn$;

create function private.customer_create(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_name text;
  v_vip boolean;
  v_open boolean;
  v_phones jsonb;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_id uuid;
  v_row public.customers%rowtype;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_create');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'display_name', 'has_open_request', 'is_vip', 'kind', 'phones', 'version'
  ]);
  v_name := private.customer_name(p_payload -> 'display_name');
  v_vip := private.customer_bool(p_payload -> 'is_vip');
  v_open := private.customer_bool(p_payload -> 'has_open_request');
  v_phones := private.customer_parse_phones(p_payload -> 'phones');
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  insert into public.customers (
    shop_id, status, record_version, display_name, is_vip, has_open_request,
    created_at, updated_at, archived_at, created_by
  ) values (
    v_shop, 'active', 1, v_name, v_vip, v_open, v_at, v_at, null, v_actor
  ) returning id into v_id;
  perform private.customer_replace_phones(v_shop, v_id, v_phones, v_at);
  perform private.customer_event(
    v_shop, v_id, 'created', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'display_name', v_name,
      'is_vip', v_vip,
      'has_open_request', v_open,
      'phones', v_phones,
      'record_version', '1'
    )
  );
  select customer.* into v_row from public.customers as customer where customer.id = v_id;
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true, 'replayed', false, 'command_kind', 'customer_create'
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_create', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_edit(p_key uuid, p_payload jsonb)
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
  v_row public.customers%rowtype;
  v_name text;
  v_phones jsonb;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_result jsonb;
  v_before jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_edit');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'display_name', 'expected_version', 'kind', 'phones', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_name := private.customer_name(p_payload -> 'display_name');
  v_phones := private.customer_parse_phones(p_payload -> 'phones');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  v_before := private.customer_view(v_row, private.customer_zone(v_shop));
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customers as customer
    set display_name = v_name,
        record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_row.id
  returning customer.* into v_row;
  perform private.customer_replace_phones(v_shop, v_id, v_phones, v_at);
  perform private.customer_event(
    v_shop, v_id, 'edited', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'display_name', v_name,
      'phones', v_phones,
      'before', jsonb_build_object('display_name',v_before -> 'display_name','phones',v_before -> 'phones'),
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true, 'replayed', false, 'command_kind', 'customer_edit'
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_edit', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_note(p_key uuid, p_payload jsonb)
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
  v_body text;
  v_row public.customers%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_note uuid;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_note');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'body', 'customer_id', 'expected_version', 'kind', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_body := private.customer_note_body(p_payload -> 'body');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  insert into public.customer_notes (
    shop_id, customer_id, body, actor_user_id, actor_display_name, created_at
  ) values (
    v_shop, v_id, v_body, v_actor, v_actor_name, v_at
  ) returning id into v_note;
  update public.customers as customer
    set record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'note_added', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'note_id', v_note,
      'preview', pg_catalog.left(v_body, 120),
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true,
      'replayed', false,
      'command_kind', 'customer_note',
      'note_id', v_note
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_note', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_status(p_key uuid, p_payload jsonb)
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
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'expected_version', 'has_open_request', 'is_vip', 'kind', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_vip := private.customer_bool(p_payload -> 'is_vip');
  v_open := private.customer_bool(p_payload -> 'has_open_request');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customers as customer
    set is_vip = v_vip,
        has_open_request = v_open,
        record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'status_changed', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'is_vip', v_vip,
      'has_open_request', v_open,
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

create function private.customer_archive(p_key uuid, p_payload jsonb)
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
  v_row public.customers%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_archive');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'expected_version', 'kind', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  if v_row.status is distinct from 'active' then
    raise exception 'invalid_state';
  end if;
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customers as customer
    set status = 'archived',
        archived_at = v_at,
        record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'archived', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'status', 'archived',
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true, 'replayed', false, 'command_kind', 'customer_archive'
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_archive', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_restore(p_key uuid, p_payload jsonb)
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
  v_row public.customers%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_restore');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'expected_version', 'kind', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  if v_row.status is distinct from 'archived' then
    raise exception 'invalid_state';
  end if;
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customers as customer
    set status = 'active',
        archived_at = null,
        record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'restored', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'status', 'active',
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true, 'replayed', false, 'command_kind', 'customer_restore'
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_restore', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_link(p_key uuid, p_payload jsonb)
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
  v_operation uuid;
  v_expected bigint;
  v_row public.customers%rowtype;
  v_op public.financial_operations%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_link uuid;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_link');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'expected_version', 'kind', 'operation_id', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_operation := private.customer_uuid(p_payload -> 'operation_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  if v_row.status is distinct from 'active' then
    raise exception 'customer_archived';
  end if;
  v_op := private.customer_require_operation(v_shop, v_operation);
  if exists (
    select 1 from public.customer_operation_links as link
    where link.shop_id = v_shop
      and link.operation_id = v_operation
      and link.status = 'active'
  ) then
    raise exception 'duplicate_link';
  end if;
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  insert into public.customer_operation_links (
    shop_id, customer_id, operation_id, status, linked_at, linked_by
  ) values (
    v_shop, v_id, v_operation, 'active', v_at, v_actor
  ) returning id into v_link;
  update public.customers as customer
    set record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'linked', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'link_id', v_link,
      'operation_id', v_operation,
      'operation_kind', v_op.kind,
      'shop_sequence', v_op.shop_sequence::text,
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true,
      'replayed', false,
      'command_kind', 'customer_link',
      'link_id', v_link,
      'operation_id', v_operation
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_link', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_unlink(p_key uuid, p_payload jsonb)
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
  v_operation uuid;
  v_expected bigint;
  v_row public.customers%rowtype;
  v_link public.customer_operation_links%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_unlink');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'expected_version', 'kind', 'operation_id', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_operation := private.customer_uuid(p_payload -> 'operation_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  select link.* into v_link
  from public.customer_operation_links as link
  where link.shop_id = v_shop
    and link.customer_id = v_id
    and link.operation_id = v_operation
    and link.status = 'active'
  for update;
  if v_link.id is null then
    raise exception 'not_linked';
  end if;
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customer_operation_links as link
    set status = 'unlinked',
        unlinked_at = v_at,
        unlinked_by = v_actor
  where link.id = v_link.id;
  update public.customers as customer
    set record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'unlinked', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'link_id', v_link.id,
      'operation_id', v_operation,
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true,
      'replayed', false,
      'command_kind', 'customer_unlink',
      'link_id', v_link.id,
      'operation_id', v_operation
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_unlink', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

create function private.customer_page_pack(
  p_channel text, p_at timestamptz, p_id uuid
) returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select p_channel || '|' || private.cursor_text(p_at, p_id);
$fn$;

create function private.customer_page_cursor(p_cursor text, p_channel text)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_at timestamptz;
  v_id uuid;
  v_inner text;
begin
  if p_cursor is null or pg_catalog.btrim(p_cursor) = '' or p_channel is null then
    return null;
  end if;
  if pg_catalog.split_part(p_cursor, '|', 1) is distinct from p_channel
    or pg_catalog.split_part(p_cursor, '|', 2) = ''
    or pg_catalog.split_part(p_cursor, '|', 3) = ''
    or pg_catalog.split_part(p_cursor, '|', 4) <> '' then
    return null;
  end if;
  v_inner := pg_catalog.split_part(p_cursor, '|', 2)
    || '|' || pg_catalog.split_part(p_cursor, '|', 3);
  begin
    v_at := private.cursor_time(v_inner);
    v_id := private.cursor_id(v_inner);
  exception
    when others then
      return null;
  end;
  return pg_catalog.jsonb_build_object('at', private.customer_utc(v_at), 'id', v_id);
end;
$fn$;

create function public.post_customer_create_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_create(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_edit_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_edit(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_note_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_note(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_status_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_status(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_archive_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_archive(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_restore_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_restore(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_link_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_link(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_customer_unlink_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  return private.customer_unlink(p_idempotency_key, p_payload);
end;
$fn$;

create function public.get_customer_command_status_v1(
  p_idempotency_key uuid, p_command_kind text, p_customer_id uuid, p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_request public.customer_command_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null
    or p_command_kind not in (
      'customer_create', 'customer_edit', 'customer_note', 'customer_status',
      'customer_archive', 'customer_restore', 'customer_link', 'customer_unlink'
    )
    or p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object'
    or p_payload ->> 'kind' is distinct from p_command_kind then
    raise exception 'invalid_input';
  end if;
  if p_payload ? 'customer_id' and (
    p_customer_id is null
    or p_payload ->> 'customer_id' is distinct from p_customer_id::text
  ) then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select request.* into v_request
  from public.customer_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key;
  if v_request.idempotency_key is null then
    return pg_catalog.jsonb_build_object('status', 'absent');
  end if;
  if v_request.command_kind is distinct from p_command_kind
    or v_request.payload_canonical is distinct from p_payload
    or (p_customer_id is not null and v_request.customer_id is distinct from p_customer_id) then
    raise exception 'payload_mismatch';
  end if;
  return pg_catalog.jsonb_build_object(
    'status', 'completed',
    'command_kind', v_request.command_kind,
    'customer_id', v_request.customer_id,
    'result', v_request.result
  );
end;
$fn$;

create function public.get_customer_list_v1(
  p_query text, p_sort text, p_filter text, p_limit integer, p_cursor text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_sort text := coalesce(p_sort, 'name');
  v_filter text := coalesce(p_filter, 'active');
  v_query text := coalesce(pg_catalog.btrim(p_query), '');
  v_limit integer;
  v_like text;
  v_phone text;
  v_cursor jsonb;
  v_use boolean := false;
  v_cursor_name text;
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_cursor_has_time boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_next text;
  v_row record;
  v_loaded public.customers%rowtype;
  v_folded text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if v_sort not in ('name', 'last_operation')
    or v_filter not in ('active', 'archived', 'vip', 'open_request', 'all')
    or pg_catalog.char_length(v_query) > 80 then
    raise exception 'invalid_input';
  end if;
  v_limit := private.customer_limit(p_limit);
  v_shop := private.opening_require_reader_shop();
  v_zone := private.customer_zone(v_shop);
  v_cursor := private.customer_cursor_read(p_cursor, v_sort, v_filter, v_query);
  if nullif(btrim(p_cursor),'') is not null and v_cursor is null then raise exception 'invalid_cursor'; end if;
  if v_cursor is not null then
    v_use := true;
    v_cursor_id := (v_cursor ->> 'id')::uuid;
    v_cursor_name := v_cursor ->> 'name';
    v_cursor_has_time := coalesce((v_cursor ->> 'has_time')::boolean, false);
    if v_cursor_has_time then
      v_cursor_at := (v_cursor ->> 'at')::timestamptz;
    end if;
  end if;
  v_folded := private.customer_fold_digits(v_query);
  v_like := '%' || replace(replace(replace(v_folded, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  if v_query <> '' then
    begin
      v_phone := private.customer_normalize_phone(v_query);
    exception
      when others then
        if sqlerrm = 'invalid_phone' then
          v_phone := null;
        else
          raise;
        end if;
    end;
  end if;
  if v_sort = 'name' then
    for v_row in
      select customer.*
      from public.customers as customer
      where customer.shop_id = v_shop
        and (
          v_filter = 'all'
          or (v_filter = 'active' and customer.status = 'active')
          or (v_filter = 'archived' and customer.status = 'archived')
          or (v_filter = 'vip' and customer.is_vip)
          or (v_filter = 'open_request' and customer.has_open_request)
        )
        and (
          v_query = ''
          or private.customer_fold_digits(customer.display_name) ilike v_like escape '\'
          or exists (
            select 1 from public.customer_phones as phone
            where phone.shop_id = customer.shop_id
              and phone.customer_id = customer.id
              and (
                private.customer_fold_digits(phone.raw_number) ilike v_like escape '\'
                or phone.normalized_number ilike v_like escape '\'
                or (v_phone is not null and phone.normalized_number = v_phone)
              )
          )
        )
        and (
          not v_use
          or customer.display_name > v_cursor_name
          or (customer.display_name = v_cursor_name and customer.id > v_cursor_id)
        )
      order by customer.display_name asc, customer.id asc
      limit v_limit + 1
    loop
      v_count := v_count + 1;
      if v_count <= v_limit then
        select customer.* into v_loaded
        from public.customers as customer
        where customer.id = v_row.id;
        v_items := v_items || pg_catalog.jsonb_build_array(
          private.customer_view(v_loaded, v_zone)
        );
        v_next := private.customer_cursor_pack(
          v_sort, v_filter, v_query, v_loaded.display_name, null, v_loaded.id
        );
      end if;
    end loop;
  else
    for v_row in
      select customer.*, activity.last_operation_at
      from public.customers as customer
      left join lateral (
        select max(operation.created_at) as last_operation_at
        from public.customer_operation_links as link
        join public.financial_operations as operation
          on operation.shop_id = link.shop_id
         and operation.id = link.operation_id
        where link.shop_id = customer.shop_id
          and link.customer_id = customer.id
          and link.status = 'active'
          and operation.kind in ('sale', 'purchase')
      ) as activity on true
      where customer.shop_id = v_shop
        and (
          v_filter = 'all'
          or (v_filter = 'active' and customer.status = 'active')
          or (v_filter = 'archived' and customer.status = 'archived')
          or (v_filter = 'vip' and customer.is_vip)
          or (v_filter = 'open_request' and customer.has_open_request)
        )
        and (
          v_query = ''
          or private.customer_fold_digits(customer.display_name) ilike v_like escape '\'
          or exists (
            select 1 from public.customer_phones as phone
            where phone.shop_id = customer.shop_id
              and phone.customer_id = customer.id
              and (
                private.customer_fold_digits(phone.raw_number) ilike v_like escape '\'
                or phone.normalized_number ilike v_like escape '\'
                or (v_phone is not null and phone.normalized_number = v_phone)
              )
          )
        )
        and (
          not v_use
          or (
            v_cursor_has_time
            and (
              activity.last_operation_at < v_cursor_at
              or (activity.last_operation_at = v_cursor_at and customer.id < v_cursor_id)
              or activity.last_operation_at is null
            )
          )
          or (
            v_use and not v_cursor_has_time
            and activity.last_operation_at is null
            and customer.id < v_cursor_id
          )
        )
      order by activity.last_operation_at desc nulls last, customer.id desc
      limit v_limit + 1
    loop
      v_count := v_count + 1;
      if v_count <= v_limit then
        select customer.* into v_loaded
        from public.customers as customer
        where customer.id = v_row.id;
        v_items := v_items || pg_catalog.jsonb_build_array(
          private.customer_view(v_loaded, v_zone)
        );
        v_next := private.customer_cursor_pack(
          v_sort, v_filter, v_query, null, v_row.last_operation_at, v_loaded.id
        );
      end if;
    end loop;
  end if;
  if v_count <= v_limit then
    v_next := null;
  end if;
  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next,
    'time_zone', v_zone,
    'locale', 'ar',
    'sort', v_sort,
    'filter', v_filter
  );
end;
$fn$;

create function public.get_customer_v1(
  p_customer_id uuid,
  p_notes_limit integer, p_notes_cursor text,
  p_history_limit integer, p_history_cursor text,
  p_links_limit integer, p_links_cursor text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_row public.customers%rowtype;
  v_notes_limit integer;
  v_history_limit integer;
  v_links_limit integer;
  v_notes_cursor jsonb;
  v_history_cursor jsonb;
  v_links_cursor jsonb;
  v_notes jsonb := '[]'::jsonb;
  v_history jsonb := '[]'::jsonb;
  v_links jsonb := '[]'::jsonb;
  v_count integer;
  v_next text;
  v_note public.customer_notes%rowtype;
  v_event public.customer_events%rowtype;
  v_link record;
  v_op public.financial_operations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_customer_id is null then
    raise exception 'invalid_input';
  end if;
  v_notes_limit := private.customer_limit(p_notes_limit);
  v_history_limit := private.customer_limit(p_history_limit);
  v_links_limit := private.customer_limit(p_links_limit);
  v_shop := private.opening_require_reader_shop();
  v_zone := private.customer_zone(v_shop);
  select customer.* into v_row
  from public.customers as customer
  where customer.shop_id = v_shop and customer.id = p_customer_id;
  if v_row.id is null then
    raise exception 'not_found';
  end if;
  v_notes_cursor := private.customer_page_cursor(p_notes_cursor, 'notes:' || p_customer_id::text);
  v_history_cursor := private.customer_page_cursor(p_history_cursor, 'history:' || p_customer_id::text);
  v_links_cursor := private.customer_page_cursor(p_links_cursor, 'links:' || p_customer_id::text);
  if (nullif(btrim(p_notes_cursor),'') is not null and v_notes_cursor is null) or (nullif(btrim(p_history_cursor),'') is not null and v_history_cursor is null) or (nullif(btrim(p_links_cursor),'') is not null and v_links_cursor is null) then raise exception 'invalid_cursor'; end if;
  v_count := 0;
  v_next := null;
  for v_note in
    select note.*
    from public.customer_notes as note
    where note.shop_id = v_shop and note.customer_id = p_customer_id
      and (
        v_notes_cursor is null
        or note.created_at < (v_notes_cursor ->> 'at')::timestamptz
        or (
          note.created_at = (v_notes_cursor ->> 'at')::timestamptz
          and note.id < (v_notes_cursor ->> 'id')::uuid
        )
      )
    order by note.created_at desc, note.id desc
    limit v_notes_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_notes_limit then
      v_notes := v_notes || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'note_id', v_note.id,
        'body', v_note.body,
        'created_at', private.customer_utc(v_note.created_at),
        'created_at_shop', private.customer_local(v_note.created_at, v_zone),
        'actor_user_id', v_note.actor_user_id,
        'actor_display_name', v_note.actor_display_name
      ));
      v_next := private.customer_page_pack('notes:' || p_customer_id::text, v_note.created_at, v_note.id);
    end if;
  end loop;
  if v_count <= v_notes_limit then
    v_next := null;
  end if;
  v_notes := pg_catalog.jsonb_build_object('items', v_notes, 'next_cursor', v_next);
  v_count := 0;
  v_next := null;
  for v_event in
    select event.*
    from public.customer_events as event
    where event.shop_id = v_shop and event.customer_id = p_customer_id
      and (
        v_history_cursor is null
        or event.created_at < (v_history_cursor ->> 'at')::timestamptz
        or (
          event.created_at = (v_history_cursor ->> 'at')::timestamptz
          and event.id < (v_history_cursor ->> 'id')::uuid
        )
      )
    order by event.created_at desc, event.id desc
    limit v_history_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_history_limit then
      v_history := v_history || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'event_id', v_event.id,
        'event_type', v_event.event_type,
        'created_at', private.customer_utc(v_event.created_at),
        'created_at_shop', private.customer_local(v_event.created_at, v_zone),
        'actor_user_id', v_event.actor_user_id,
        'actor_display_name', v_event.actor_display_name,
        'payload', v_event.payload
      ));
      v_next := private.customer_page_pack('history:' || p_customer_id::text, v_event.created_at, v_event.id);
    end if;
  end loop;
  if v_count <= v_history_limit then
    v_next := null;
  end if;
  v_history := pg_catalog.jsonb_build_object('items', v_history, 'next_cursor', v_next);
  v_count := 0;
  v_next := null;
  for v_link in
    select link.*, operation.created_at as operation_created_at
    from public.customer_operation_links as link
    join public.financial_operations as operation
      on operation.shop_id = link.shop_id
     and operation.id = link.operation_id
    where link.shop_id = v_shop and link.customer_id = p_customer_id
      and (
        v_links_cursor is null
        or operation.created_at < (v_links_cursor ->> 'at')::timestamptz
        or (
          operation.created_at = (v_links_cursor ->> 'at')::timestamptz
          and link.id < (v_links_cursor ->> 'id')::uuid
        )
      )
    order by operation.created_at desc, link.id desc
    limit v_links_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_links_limit then
      select operation.* into v_op
      from public.financial_operations as operation
      where operation.shop_id = v_shop and operation.id = v_link.operation_id;
      v_links := v_links || pg_catalog.jsonb_build_array(
        private.customer_operation_public(v_op, v_zone)
        || pg_catalog.jsonb_build_object(
          'link_id', v_link.id,
          'link_status', v_link.status,
          'linked_at', private.customer_utc(v_link.linked_at),
          'linked_at_shop', private.customer_local(v_link.linked_at, v_zone),
          'unlinked_at', private.customer_utc(v_link.unlinked_at),
          'unlinked_at_shop', private.customer_local(v_link.unlinked_at, v_zone)
        )
      );
      v_next := private.customer_page_pack('links:' || p_customer_id::text, v_link.operation_created_at, v_link.id);
    end if;
  end loop;
  if v_count <= v_links_limit then
    v_next := null;
  end if;
  return private.customer_view(v_row, v_zone) || pg_catalog.jsonb_build_object(
    'notes', v_notes,
    'history', v_history,
    'links', pg_catalog.jsonb_build_object('items', v_links, 'next_cursor', v_next)
  );
end;
$fn$;

create function public.get_customer_link_candidates_v1(
  p_query text, p_limit integer, p_cursor text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_query text := coalesce(pg_catalog.btrim(p_query), '');
  v_limit integer;
  v_like text;
  v_cursor jsonb;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_next text;
  v_row public.financial_operations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if pg_catalog.char_length(v_query) > 80 then
    raise exception 'invalid_input';
  end if;
  v_limit := private.customer_limit(p_limit);
  v_shop := private.opening_require_reader_shop();
  v_zone := private.customer_zone(v_shop);
  v_cursor := private.customer_page_cursor(
    p_cursor, 'candidates:' || pg_catalog.md5(v_query)
  );
  if nullif(btrim(p_cursor),'') is not null and v_cursor is null then raise exception 'invalid_cursor'; end if;
  v_like := '%' || replace(replace(replace(v_query, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  for v_row in
    select operation.*
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id
     and detail.operation_id = operation.id
    where operation.shop_id = v_shop
      and operation.kind in ('sale', 'purchase')
      and exists (
        select 1 from public.financial_audit_events as audit_event
        where audit_event.shop_id = operation.shop_id
          and audit_event.operation_id = operation.id
          and audit_event.action = operation.kind || '_confirmed'
      )
      and not exists (
        select 1 from public.customer_operation_links as link
        where link.shop_id = operation.shop_id
          and link.operation_id = operation.id
          and link.status = 'active'
      )
      and (
        v_query = ''
        or coalesce(detail.payload ->> 'customer_name', '') ilike v_like escape '\'
        or coalesce(detail.payload ->> 'customer_phone', '') ilike v_like escape '\'
        or operation.shop_sequence::text ilike v_like escape '\'
        or coalesce(detail.payload ->> 'note', '') ilike v_like escape '\'
      )
      and (
        v_cursor is null
        or operation.created_at < (v_cursor ->> 'at')::timestamptz
        or (
          operation.created_at = (v_cursor ->> 'at')::timestamptz
          and operation.id < (v_cursor ->> 'id')::uuid
        )
      )
    order by operation.created_at desc, operation.id desc
    limit v_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_limit then
      v_items := v_items || pg_catalog.jsonb_build_array(
        private.customer_operation_public(v_row, v_zone)
      );
      v_next := private.customer_page_pack(
        'candidates:' || pg_catalog.md5(v_query), v_row.created_at, v_row.id
      );
    end if;
  end loop;
  if v_count <= v_limit then
    v_next := null;
  end if;
  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next,
    'time_zone', v_zone,
    'locale', 'ar'
  );
end;
$fn$;

revoke all on function private.customer_guard() from public, anon, authenticated;
revoke all on function private.customer_reject_mutation() from public, anon, authenticated;
revoke all on function private.customer_phone_guard() from public, anon, authenticated;
revoke all on function private.customer_link_guard() from public, anon, authenticated;
revoke all on function private.customer_require_keys(jsonb, text[]) from public, anon, authenticated;
revoke all on function private.customer_exact_text(jsonb, integer, integer) from public, anon, authenticated;
revoke all on function private.customer_note_body(jsonb) from public, anon, authenticated;
revoke all on function private.customer_name(jsonb) from public, anon, authenticated;
revoke all on function private.customer_bool(jsonb) from public, anon, authenticated;
revoke all on function private.customer_uuid(jsonb) from public, anon, authenticated;
revoke all on function private.customer_expected_version(jsonb) from public, anon, authenticated;
revoke all on function private.customer_fold_digits(text) from public, anon, authenticated;
revoke all on function private.customer_normalize_phone(text) from public, anon, authenticated;
revoke all on function private.customer_parse_phones(jsonb) from public, anon, authenticated;
revoke all on function private.customer_limit(integer) from public, anon, authenticated;
revoke all on function private.customer_utc(timestamptz) from public, anon, authenticated;
revoke all on function private.customer_local(timestamptz, text) from public, anon, authenticated;
revoke all on function private.customer_cursor_read(text, text, text, text) from public, anon, authenticated;
revoke all on function private.customer_cursor_pack(text, text, text, text, timestamptz, uuid) from public, anon, authenticated;
revoke all on function private.customer_zone(uuid) from public, anon, authenticated;
revoke all on function private.customer_actor_name(uuid) from public, anon, authenticated;
revoke all on function private.customer_last_operation_at(uuid, uuid) from public, anon, authenticated;
revoke all on function private.customer_view(public.customers, text) from public, anon, authenticated;
revoke all on function private.customer_operation_public(public.financial_operations, text) from public, anon, authenticated;
revoke all on function private.customer_claim(uuid, jsonb, text) from public, anon, authenticated;
revoke all on function private.customer_finish(uuid, uuid, text, jsonb, text, uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_event(uuid, uuid, text, uuid, text, timestamptz, jsonb) from public, anon, authenticated;
revoke all on function private.customer_lock(uuid, uuid, bigint) from public, anon, authenticated;
revoke all on function private.customer_replace_phones(uuid, uuid, jsonb, timestamptz) from public, anon, authenticated;
revoke all on function private.customer_require_operation(uuid, uuid) from public, anon, authenticated;
revoke all on function private.customer_create(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_edit(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_note(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_status(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_archive(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_restore(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_link(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_unlink(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.customer_page_pack(text, timestamptz, uuid) from public, anon, authenticated;
revoke all on function private.customer_page_cursor(text, text) from public, anon, authenticated;
revoke all on function private.bump_shop_sync(uuid, text) from public, anon, authenticated;
revoke all on function private.shop_sync_touch() from public, anon, authenticated;

revoke all on function public.post_customer_create_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_edit_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_note_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_status_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_archive_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_restore_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_link_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_customer_unlink_v1(uuid, jsonb) from public, anon;
revoke all on function public.get_customer_command_status_v1(uuid, text, uuid, jsonb) from public, anon;
revoke all on function public.get_customer_list_v1(text, text, text, integer, text) from public, anon;
revoke all on function public.get_customer_v1(uuid, integer, text, integer, text, integer, text) from public, anon;
revoke all on function public.get_customer_link_candidates_v1(text, integer, text) from public, anon;

grant execute on function public.post_customer_create_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_edit_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_note_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_status_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_archive_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_restore_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_link_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_customer_unlink_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_customer_command_status_v1(uuid, text, uuid, jsonb) to authenticated;
grant execute on function public.get_customer_list_v1(text, text, text, integer, text) to authenticated;
grant execute on function public.get_customer_v1(uuid, integer, text, integer, text, integer, text) to authenticated;
grant execute on function public.get_customer_link_candidates_v1(text, integer, text) to authenticated;

notify pgrst, 'reload schema';
commit;


-- Required signup location, hashed subscription redemption, and RLS-safe
-- shop sync signals. Historical empty CC: and EG:text profiles remain stored
-- and replayable; new registration requests must supply a catalog Egyptian
-- governorate or a non-empty city/region for other supported countries.
begin;

-- Legacy stored profiles may still use empty CC: or EG:text labels.
create or replace function private.registration_region_stored_valid(p_region text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
select coalesce(
  exists (select 1 from public.egypt_governorates where code = p_region)
  or (
    private.registration_dial_code(p_region) is not null
    and substring(p_region from 3 for 1) = ':'
    and char_length(substring(p_region from 4)) between 0 and 120
    and substring(p_region from 4) = btrim(substring(p_region from 4))
    and p_region !~ '[[:cntrl:]]'
  ),
  false
);
$fn$;
revoke all on function private.registration_region_stored_valid(text) from public, anon, authenticated;

comment on function private.registration_region_stored_valid(text) is
  'Accepts catalog EG codes plus historical CC: and EG:text stored profiles for replay and table checks.';

-- New requests: Egypt must be a catalog code; other countries need a non-empty region.
create or replace function private.registration_region_valid(p_region text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
select coalesce(
  exists (select 1 from public.egypt_governorates where code = p_region)
  or (
    private.registration_dial_code(p_region) is not null
    and left(p_region, 2) <> 'EG'
    and substring(p_region from 3 for 1) = ':'
    and char_length(substring(p_region from 4)) between 1 and 120
    and substring(p_region from 4) = btrim(substring(p_region from 4))
    and p_region !~ '[[:cntrl:]]'
  ),
  false
);
$fn$;
revoke all on function private.registration_region_valid(text) from public, anon, authenticated;

comment on function private.registration_region_valid(text) is
  'New registration requests: ISO Egyptian catalog codes or CC:label with a required non-empty city/region.';

alter table public.shops drop constraint if exists shops_registered_profile_check;
alter table public.shops add constraint shops_registered_profile_check check (
  (email is null and governorate_code is null) or
  (email is not null and governorate_code is not null and phone is not null
    and private.registration_region_stored_valid(governorate_code)
    and phone = private.registration_phone(phone, governorate_code)
    and private.registration_phone(phone, governorate_code) is not null
    and owner_display_name is not null and length(btrim(owner_display_name)) between 1 and 120
    and time_zone = private.registration_time_zone(governorate_code))
);

alter table private.owner_registration_reservations
  drop constraint if exists owner_registration_phone_check;
alter table private.owner_registration_reservations add constraint owner_registration_phone_check check (
  private.registration_region_stored_valid(governorate_code)
  and private.registration_phone(phone, governorate_code) is not null
  and phone = private.registration_phone(phone, governorate_code)
);

create or replace function public.begin_owner_registration(
  p_request_key uuid,
  p_owner_display_name text,
  p_business_name text,
  p_email text,
  p_phone text,
  p_governorate_code text
)
returns table (
  request_key uuid,
  reserved_user_id uuid,
  email text,
  phone text,
  auth_phone text,
  owner_display_name text,
  business_name text,
  governorate_code text,
  status text,
  shop_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner text;
  v_business text;
  v_email text;
  v_phone text;
  v_governorate text;
  v_existing private.owner_registration_reservations%rowtype;
begin
  v_owner := btrim(p_owner_display_name);
  v_business := btrim(p_business_name);
  if p_request_key is null
    or v_owner is null
    or char_length(v_owner) not between 1 and 120
    or v_business is null
    or char_length(v_business) not between 1 and 120
    or v_owner ~ '[[:cntrl:]]'
    or v_business ~ '[[:cntrl:]]' then
    raise exception 'invalid_registration' using errcode = '22023';
  end if;

  v_email := private.normalize_registration_email(p_email);
  if v_email is null then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  v_governorate := btrim(p_governorate_code);
  -- Stored-compatible syntax (catalog or historical CC:/EG:text) before phone
  -- so malformed locations such as EG-XXX raise invalid_governorate, not invalid_phone.
  if v_governorate is null
    or v_governorate = ''
    or not private.registration_region_stored_valid(v_governorate) then
    raise exception 'invalid_governorate' using errcode = '22023';
  end if;

  v_phone := private.registration_phone(p_phone, v_governorate);
  if v_phone is null then
    raise exception 'invalid_phone' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(840261, hashtext(p_request_key::text));
  perform pg_advisory_xact_lock(840262, hashtext(v_email));
  perform pg_advisory_xact_lock(840263, hashtext(v_phone));

  select * into v_existing
  from private.owner_registration_reservations as existing_reservation
  where existing_reservation.request_key = p_request_key
  for update;

  if found then
    if v_existing.email <> v_email
      or v_existing.phone <> v_phone
      or v_existing.owner_display_name <> v_owner
      or v_existing.business_name <> v_business
      or v_existing.governorate_code <> v_governorate then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return query
    select * from private.owner_registration_result(p_request_key);
    return;
  end if;

  if not private.registration_region_valid(v_governorate) then
    raise exception 'invalid_governorate' using errcode = '22023';
  end if;

  if exists (
    select 1
    from private.owner_registration_reservations as reservation
    where reservation.email = v_email
      or reservation.phone = v_phone
  ) or exists (
    select 1
    from public.shops as shop
    where shop.email = v_email
      or shop.phone = v_phone
      or private.normalize_egypt_mobile(shop.phone) = v_phone
  ) or exists (
    select 1
    from auth.users as identity
    where lower(btrim(identity.email)) = v_email
      or private.auth_phone_matches(identity.phone, v_phone)
  ) then
    raise exception 'identifier_already_registered' using errcode = '23505';
  end if;

  begin
    insert into private.owner_registration_reservations (
      request_key,
      reserved_user_id,
      email,
      phone,
      owner_display_name,
      business_name,
      governorate_code,
      status,
      created_at
    ) values (
      p_request_key,
      gen_random_uuid(),
      v_email,
      v_phone,
      v_owner,
      v_business,
      v_governorate,
      'reserved',
      clock_timestamp()
    );
  exception
    when unique_violation then
      select * into v_existing
      from private.owner_registration_reservations as existing_reservation
      where existing_reservation.request_key = p_request_key;
      if found
        and v_existing.email = v_email
        and v_existing.phone = v_phone
        and v_existing.owner_display_name = v_owner
        and v_existing.business_name = v_business
        and v_existing.governorate_code = v_governorate then
        return query
        select * from private.owner_registration_result(p_request_key);
        return;
      end if;
      if found then
        raise exception 'request_key_reused' using errcode = '23505';
      end if;
      raise exception 'identifier_already_registered' using errcode = '23505';
  end;

  return query
  select * from private.owner_registration_result(p_request_key);
end;
$function$;

-- ---------------------------------------------------------------------------
-- Shop sync signals: RLS-protected version rows, no financial payloads.
-- ---------------------------------------------------------------------------
create table public.shop_sync_signals (
  shop_id uuid primary key references public.shops (id) on delete cascade,
  revision bigint not null default 1 check (revision >= 1),
  ledger_revision bigint not null default 0 check (ledger_revision >= 0),
  inventory_revision bigint not null default 0 check (inventory_revision >= 0),
  trader_revision bigint not null default 0 check (trader_revision >= 0),
  invoice_revision bigint not null default 0 check (invoice_revision >= 0),
  day_revision bigint not null default 0 check (day_revision >= 0),
  location_revision bigint not null default 0 check (location_revision >= 0),
  subscription_revision bigint not null default 0 check (subscription_revision >= 0),
  updated_at timestamptz not null default now()
);

comment on table public.shop_sync_signals is
  'Minimal per-shop revision notifications. Clients refetch snapshots; rows never carry cash, grams, or customer payloads.';

alter table public.shop_sync_signals enable row level security;
alter table public.shop_sync_signals force row level security;
revoke all on table public.shop_sync_signals from public, anon, authenticated;
grant select on table public.shop_sync_signals to authenticated;

-- Pending owners may read revision rows only. Financial tables stay behind
-- is_active_shop_member (entitlement required).
create function private.is_unrevoked_shop_owner(p_shop_id uuid)
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
    and exists (
      select 1
      from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = auth.uid()
        and membership.role = 'owner'
        and membership.revoked_at is null
    );
$fn$;
revoke all on function private.is_unrevoked_shop_owner(uuid) from public, anon;
grant execute on function private.is_unrevoked_shop_owner(uuid) to authenticated;

create policy shop_sync_signals_owner_read
on public.shop_sync_signals
for select
to authenticated
using (private.is_unrevoked_shop_owner(shop_id));

create function private.bump_shop_sync(p_shop_id uuid, p_scope text)
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
    shop_id,
    revision,
    ledger_revision,
    inventory_revision,
    trader_revision,
    invoice_revision,
    day_revision,
    location_revision,
    subscription_revision,
    updated_at
  ) values (
    p_shop_id,
    1,
    case when p_scope = 'ledger' then 1 else 0 end,
    case when p_scope = 'inventory' then 1 else 0 end,
    case when p_scope = 'trader' then 1 else 0 end,
    case when p_scope = 'invoice' then 1 else 0 end,
    case when p_scope = 'day' then 1 else 0 end,
    case when p_scope = 'location' then 1 else 0 end,
    case when p_scope = 'subscription' then 1 else 0 end,
    clock_timestamp()
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
        updated_at = clock_timestamp();
end;
$fn$;
revoke all on function private.bump_shop_sync(uuid, text) from public, anon, authenticated;

create function private.shop_sync_touch()
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
    -- A deleted shop cannot have a signal row reinserted after its cascade.
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
    else 'ledger'
  end;
  perform private.bump_shop_sync(v_shop, v_scope);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$fn$;
revoke all on function private.shop_sync_touch() from public, anon, authenticated;

do $sync_triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'shops',
    'shop_entitlements',
    'business_days',
    'financial_operations',
    'financial_operation_details',
    'journals',
    'journal_postings',
    'ledger_accounts',
    'purchase_cash_payables',
    'invoice_dispatch_confirmations',
    'inventory_lots',
    'inventory_lot_movements',
    'inventory_receipts',
    'inventory_lot_sync',
    'inventory_products',
    'bullion_denominations',
    'coin_types',
    'shop_memberships',
    'traders',
    'gold_obligations'
  ]
  loop
    if to_regclass('public.' || v_table) is null then
      continue;
    end if;
    execute format(
      'drop trigger if exists shop_sync_%I on public.%I',
      v_table,
      v_table
    );
    execute format(
      'create trigger shop_sync_%I after insert or update or delete on public.%I for each row execute function private.shop_sync_touch()',
      v_table,
      v_table
    );
  end loop;
end;
$sync_triggers$;

insert into public.shop_sync_signals (shop_id)
select id from public.shops
on conflict (shop_id) do nothing;

do $realtime$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shop_sync_signals'
  ) then
    execute 'alter publication supabase_realtime add table public.shop_sync_signals';
  end if;
end;
$realtime$;

-- ---------------------------------------------------------------------------
-- Subscription codes: hashed, single-use, bound, operator-issued.
-- ---------------------------------------------------------------------------
create table private.subscription_codes (
  id uuid primary key default gen_random_uuid(),
  code_hash bytea not null unique,
  shop_id uuid not null references public.shops (id),
  owner_user_id uuid not null references auth.users (id),
  duration_days integer not null check (duration_days between 1 and 3660),
  code_ttl_days integer not null default 30 check (code_ttl_days between 1 and 365),
  code_expires_at timestamptz not null,
  issued_at timestamptz not null default now(),
  issued_by uuid,
  issued_via text not null check (issued_via in ('platform_admin', 'service_role')),
  issue_request_key uuid not null unique,
  redeemed_at timestamptz,
  redeemed_by uuid,
  redeemed_request_key uuid,
  constraint subscription_codes_hash_len check (octet_length(code_hash) = 32),
  constraint subscription_codes_expiry_after_issue check (code_expires_at > issued_at),
  constraint subscription_codes_redeemed_pair check (
    (redeemed_at is null and redeemed_by is null and redeemed_request_key is null)
    or (redeemed_at is not null and redeemed_by is not null and redeemed_request_key is not null)
  ),
  constraint subscription_codes_issuer_check check (
    (issued_via = 'platform_admin' and issued_by is not null)
    or (issued_via = 'service_role' and issued_by is null)
  )
);

create index subscription_codes_shop_id_idx on private.subscription_codes (shop_id);
create index subscription_codes_owner_user_id_idx on private.subscription_codes (owner_user_id);

comment on table private.subscription_codes is
  'Hashed high-entropy subscription codes. Raw codes are never stored. Owners have no table privilege.';

alter table private.subscription_codes enable row level security;
alter table private.subscription_codes force row level security;
revoke all on table private.subscription_codes from public, anon, authenticated;

create table private.subscription_code_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  attempted_at timestamptz not null default now(),
  accepted boolean not null
);

create index subscription_code_attempts_user_recent_idx
  on private.subscription_code_attempts (user_id, attempted_at desc);

alter table private.subscription_code_attempts enable row level security;
alter table private.subscription_code_attempts force row level security;
revoke all on table private.subscription_code_attempts from public, anon, authenticated;

create table private.subscription_redemption_requests (
  request_key uuid primary key,
  owner_user_id uuid not null,
  shop_id uuid not null references public.shops (id),
  code_hash bytea not null,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint subscription_redemption_requests_hash_len check (octet_length(code_hash) = 32),
  constraint subscription_redemption_requests_term check (expires_at > starts_at)
);

alter table private.subscription_redemption_requests enable row level security;
alter table private.subscription_redemption_requests force row level security;
revoke all on table private.subscription_redemption_requests from public, anon, authenticated;

create table private.subscription_code_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  actor_user_id uuid,
  action text not null check (char_length(action) between 1 and 80),
  created_at timestamptz not null default now(),
  correlation_id uuid not null,
  details jsonb not null default '{}'::jsonb,
  constraint subscription_code_events_details_object check (jsonb_typeof(details) = 'object'),
  constraint subscription_code_events_no_secrets check (
    details::text !~* '"(password|passwd|token|token_hash|secret|access_token|refresh_token|api_key|authorization|cookie|code|code_hash|raw_code)"[[:space:]]*:'
  )
);

create index subscription_code_events_shop_created_idx
  on private.subscription_code_events (shop_id, created_at);

alter table private.subscription_code_events enable row level security;
alter table private.subscription_code_events force row level security;
revoke all on table private.subscription_code_events from public, anon, authenticated;

create function private.subscription_code_hash(p_code text)
returns bytea
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select extensions.digest(convert_to(upper(btrim(coalesce(p_code, ''))), 'UTF8'), 'sha256');
$fn$;
revoke all on function private.subscription_code_hash(text) from public, anon, authenticated;

create function private.normalize_subscription_code(p_code text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case
    when p_code is null then null
    when upper(btrim(p_code)) ~ '^[A-F0-9]{32}$' then upper(btrim(p_code))
    else null
  end;
$fn$;
revoke all on function private.normalize_subscription_code(text) from public, anon, authenticated;

create function private.subscription_caller_is_service_role()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    auth.jwt() ->> 'role'
  ) = 'service_role';
$fn$;
revoke all on function private.subscription_caller_is_service_role() from public, anon, authenticated;

create function private.subscription_platform_admin_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select public.is_platform_admin()
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
    );
$fn$;
revoke all on function private.subscription_platform_admin_session() from public, anon, authenticated;

create function public.issue_subscription_code(
  p_shop_id uuid,
  p_duration_days integer,
  p_code_ttl_days integer default 30,
  p_request_key uuid default null
)
returns table (
  code text,
  shop_id uuid,
  owner_user_id uuid,
  duration_days integer,
  code_expires_at timestamptz,
  status text,
  request_key uuid,
  issued_via text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner uuid;
  v_code text;
  v_hash bytea;
  v_ttl integer;
  v_expires timestamptz;
  v_issued_by uuid;
  v_issued_via text;
  v_request uuid;
  v_existing private.subscription_codes%rowtype;
  v_now timestamptz;
begin
  if private.subscription_caller_is_service_role() then
    v_issued_via := 'service_role';
    v_issued_by := null;
  elsif private.subscription_platform_admin_session() then
    v_issued_via := 'platform_admin';
    v_issued_by := auth.uid();
  else
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_shop_id is null
    or p_duration_days is null
    or p_duration_days not between 1 and 3660 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_ttl := coalesce(p_code_ttl_days, 30);
  if v_ttl not between 1 and 365 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if p_request_key is null
    or p_request_key::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_request := p_request_key;

  select ownership.user_id into v_owner
  from public.shop_memberships as ownership
  where ownership.shop_id = p_shop_id
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_owner is null then
    raise exception 'shop_not_found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(840274, hashtext(v_request::text));
  perform pg_advisory_xact_lock(840275, hashtext(p_shop_id::text));
  v_now := clock_timestamp();

  select * into v_existing
  from private.subscription_codes as prior
  where prior.issue_request_key = v_request
  for update;

  if found then
    if v_existing.shop_id <> p_shop_id
      or v_existing.duration_days <> p_duration_days
      or v_existing.code_ttl_days <> v_ttl
      or v_existing.owner_user_id <> v_owner then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    -- Retry confirms the prior issuance. The raw code is never stored.
    return query
    select
      null::text,
      v_existing.shop_id,
      v_existing.owner_user_id,
      v_existing.duration_days,
      v_existing.code_expires_at,
      'replayed'::text,
      v_existing.issue_request_key,
      v_existing.issued_via;
    return;
  end if;

  v_code := upper(encode(extensions.gen_random_bytes(16), 'hex'));
  v_hash := private.subscription_code_hash(v_code);
  v_expires := v_now + make_interval(days => v_ttl);

  insert into private.subscription_codes (
    code_hash,
    shop_id,
    owner_user_id,
    duration_days,
    code_expires_at,
    issued_at,
    issued_by,
    issued_via,
    issue_request_key,
    code_ttl_days
  ) values (
    v_hash,
    p_shop_id,
    v_owner,
    p_duration_days,
    v_expires,
    v_now,
    v_issued_by,
    v_issued_via,
    v_request,
    v_ttl
  );

  insert into private.subscription_code_events (
    shop_id,
    actor_user_id,
    action,
    correlation_id,
    details
  ) values (
    p_shop_id,
    v_issued_by,
    'subscription_code_issued',
    v_request,
    jsonb_build_object(
      'duration_days', p_duration_days,
      'code_expires_at', v_expires,
      'issued_via', v_issued_via
    )
  );

  return query
  select
    v_code,
    p_shop_id,
    v_owner,
    p_duration_days,
    v_expires,
    'issued'::text,
    v_request,
    v_issued_via;
end;
$function$;

revoke all on function public.issue_subscription_code(uuid, integer, integer, uuid) from public, anon;
grant execute on function public.issue_subscription_code(uuid, integer, integer, uuid) to authenticated, service_role;

create function public.redeem_subscription_code(
  p_request_key uuid,
  p_code text
)
returns table (
  shop_id uuid,
  starts_at timestamptz,
  expires_at timestamptz,
  status text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid;
  v_shop uuid;
  v_code text;
  v_hash bytea;
  v_existing private.subscription_redemption_requests%rowtype;
  v_row private.subscription_codes%rowtype;
  v_failures integer;
  v_now timestamptz;
  v_starts timestamptz;
  v_expires timestamptz;
  v_entitlement public.shop_entitlements%rowtype;
begin
  v_user := auth.uid();
  if v_user is null
    or not private.caller_session_accepted()
    or exists (
      select 1
      from auth.users as identity
      where identity.id = v_user
        and (
          coalesce(identity.is_anonymous, false)
          or identity.deleted_at is not null
        )
    ) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if p_request_key is null
    or p_request_key::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select ownership.shop_id into v_shop
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(840271, hashtext(v_user::text));
  perform pg_advisory_xact_lock(840272, hashtext(p_request_key::text));
  v_now := clock_timestamp();

  select * into v_existing
  from private.subscription_redemption_requests as prior
  where prior.request_key = p_request_key
  for update;

  if found then
    v_code := private.normalize_subscription_code(p_code);
    v_hash := case
      when v_code is null then null
      else private.subscription_code_hash(v_code)
    end;
    if v_existing.owner_user_id <> v_user
      or v_existing.shop_id <> v_shop
      or v_hash is null
      or v_existing.code_hash <> v_hash then
      return query
      select null::uuid, null::timestamptz, null::timestamptz, 'request_key_reused'::text;
      return;
    end if;
    return query
    select v_existing.shop_id, v_existing.starts_at, v_existing.expires_at, 'replayed'::text;
    return;
  end if;

  select count(*) into v_failures
  from private.subscription_code_attempts as attempt
  where attempt.user_id = v_user
    and attempt.accepted = false
    and attempt.attempted_at > v_now - interval '15 minutes';
  if v_failures >= 8 then
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  v_code := private.normalize_subscription_code(p_code);
  if v_code is null then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'invalid_code'::text;
    return;
  end if;
  v_hash := private.subscription_code_hash(v_code);
  perform pg_advisory_xact_lock(840273, hashtext(encode(v_hash, 'hex')));
  v_now := clock_timestamp();

  select count(*) into v_failures
  from private.subscription_code_attempts as attempt
  where attempt.user_id = v_user
    and attempt.accepted = false
    and attempt.attempted_at > v_now - interval '15 minutes';
  if v_failures >= 8 then
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  select * into v_row
  from private.subscription_codes as code_row
  where code_row.code_hash = v_hash
  for update;
  v_now := clock_timestamp();

  if not found then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'invalid_code'::text;
    return;
  end if;

  if v_row.owner_user_id <> v_user or v_row.shop_id <> v_shop then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'foreign_owner'::text;
    return;
  end if;

  if v_row.redeemed_at is not null then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'reused_code'::text;
    return;
  end if;

  if v_row.code_expires_at <= v_now then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'expired_code'::text;
    return;
  end if;

  select * into v_entitlement
  from public.shop_entitlements as entitlement
  where entitlement.shop_id = v_shop
  for update;

  if not found then
    v_starts := v_now;
    v_expires := v_now + make_interval(days => v_row.duration_days);
    insert into public.shop_entitlements (shop_id, starts_at, expires_at)
    values (v_shop, v_starts, v_expires);
  elsif v_now < v_entitlement.expires_at and v_now >= v_entitlement.starts_at then
    v_starts := v_entitlement.starts_at;
    v_expires := v_entitlement.expires_at + make_interval(days => v_row.duration_days);
    update public.shop_entitlements
      set expires_at = v_expires
      where shop_id = v_shop;
  else
    v_starts := v_now;
    v_expires := v_now + make_interval(days => v_row.duration_days);
    update public.shop_entitlements
      set starts_at = v_starts,
          expires_at = v_expires
      where shop_id = v_shop;
  end if;

  update private.subscription_codes
    set redeemed_at = v_now,
        redeemed_by = v_user,
        redeemed_request_key = p_request_key
    where id = v_row.id;

  insert into private.subscription_redemption_requests (
    request_key,
    owner_user_id,
    shop_id,
    code_hash,
    starts_at,
    expires_at,
    created_at
  ) values (
    p_request_key,
    v_user,
    v_shop,
    v_hash,
    v_starts,
    v_expires,
    v_now
  );

  insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
  values (v_user, v_now, true);

  insert into public.identity_audit_events (
    shop_id,
    actor_user_id,
    action,
    subject_user_id,
    correlation_id,
    details
  ) values (
    v_shop,
    v_user,
    'subscription_redeemed',
    v_user,
    p_request_key,
    jsonb_build_object(
      'duration_days', v_row.duration_days,
      'starts_at', v_starts,
      'expires_at', v_expires
    )
  );

  insert into private.subscription_code_events (
    shop_id,
    actor_user_id,
    action,
    correlation_id,
    details
  ) values (
    v_shop,
    v_user,
    'subscription_code_redeemed',
    p_request_key,
    jsonb_build_object(
      'duration_days', v_row.duration_days,
      'expires_at', v_expires
    )
  );

  return query
  select v_shop, v_starts, v_expires, 'activated'::text;
end;
$function$;

revoke all on function public.redeem_subscription_code(uuid, text) from public, anon;
grant execute on function public.redeem_subscription_code(uuid, text) to authenticated;

commit;

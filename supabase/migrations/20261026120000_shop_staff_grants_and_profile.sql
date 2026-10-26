-- ADR 0033: partner/employee memberships, grants, shop profile.
-- opening_require_reader_shop accepts members only when app.required_shop_permission
-- is set for this transaction (staff default deny). Owners always pass.

begin;

-- ---------------------------------------------------------------------------
-- Memberships and grants
-- ---------------------------------------------------------------------------
alter table public.shop_memberships
  drop constraint if exists shop_memberships_role_check;
alter table public.shop_memberships
  add constraint shop_memberships_role_check
  check (role in ('owner', 'partner', 'employee'));

alter table public.shop_memberships
  drop constraint if exists shop_memberships_one_owner_per_shop;

create unique index if not exists shop_memberships_one_owner_per_shop
  on public.shop_memberships (shop_id)
  where role = 'owner' and revoked_at is null;

comment on table public.shop_memberships is
  'Shop membership. One owner per shop; partners and employees allowed; one shop per Auth user.';
comment on column public.shop_memberships.role is
  'owner, partner, or employee. Owner cardinality is enforced by a partial unique index.';

create table if not exists public.shop_member_grants (
  shop_id uuid not null references public.shops (id),
  user_id uuid not null references auth.users (id),
  permission text not null
    check (permission in (
      'sale', 'purchase', 'inventory', 'expense', 'reports', 'invoice_send'
    )),
  granted_at timestamptz not null default clock_timestamp(),
  granted_by uuid not null references auth.users (id),
  primary key (shop_id, user_id, permission),
  foreign key (shop_id, user_id)
    references public.shop_memberships (shop_id, user_id)
);

create table if not exists public.shop_member_grant_audits (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops (id),
  actor_user_id uuid not null references auth.users (id),
  subject_user_id uuid not null references auth.users (id),
  action text not null check (action in (
    'staff_created', 'grants_set', 'staff_revoked', 'profile_updated'
  )),
  details jsonb not null default '{}'::jsonb,
  request_key uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id, request_key)
);

create table if not exists private.shop_staff_creation_requests (
  shop_id uuid not null references public.shops (id),
  key uuid not null,
  owner_user_id uuid not null references auth.users (id),
  reserved_user_id uuid not null unique default gen_random_uuid(),
  display_name text not null,
  phone text not null,
  role text not null check (role in ('partner', 'employee')),
  grants text[] not null,
  password_proof text not null,
  member_user_id uuid references auth.users (id),
  created_at timestamptz not null default clock_timestamp(),
  primary key (shop_id, key)
);

create table if not exists private.shop_profile_commands (
  shop_id uuid not null references public.shops (id),
  actor_user_id uuid not null references auth.users (id),
  key uuid not null,
  payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (shop_id, key)
);

alter table public.shop_member_grants enable row level security;
alter table public.shop_member_grant_audits enable row level security;
alter table private.shop_staff_creation_requests enable row level security;
alter table private.shop_profile_commands enable row level security;

revoke all on public.shop_member_grants, public.shop_member_grant_audits,
  private.shop_staff_creation_requests, private.shop_profile_commands
  from public, anon, authenticated;

create or replace function private.shop_member_grant_audits_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  raise exception 'append_only';
end;
$fn$;

drop trigger if exists shop_member_grant_audits_append_only
  on public.shop_member_grant_audits;
create trigger shop_member_grant_audits_append_only
  before update or delete on public.shop_member_grant_audits
  for each row execute function private.shop_member_grant_audits_append_only();

-- ---------------------------------------------------------------------------
-- Auth helpers
-- ---------------------------------------------------------------------------
create or replace function private.is_shop_owner(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select auth.uid() is not null
    and exists (
      select 1
      from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = auth.uid()
        and membership.role = 'owner'
        and membership.revoked_at is null
    );
$fn$;

revoke all on function private.is_shop_owner(uuid) from public, anon;
grant execute on function private.is_shop_owner(uuid) to authenticated;

create or replace function private.has_shop_permission(p_shop_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select case
    when private.is_shop_owner(p_shop_id) then true
    when p_permission = 'ledger_read' then exists (
      select 1
      from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = auth.uid()
        and membership.role in ('partner', 'employee')
        and membership.revoked_at is null
    )
    else exists (
      select 1
      from public.shop_memberships as membership
      join public.shop_member_grants as grant_row
        on grant_row.shop_id = membership.shop_id
       and grant_row.user_id = membership.user_id
      where membership.shop_id = p_shop_id
        and membership.user_id = auth.uid()
        and membership.role in ('partner', 'employee')
        and membership.revoked_at is null
        and grant_row.permission = p_permission
    )
  end;
$fn$;

revoke all on function private.has_shop_permission(uuid, text) from public, anon;
grant execute on function private.has_shop_permission(uuid, text) to authenticated;

create or replace function private.allow_member_permission(p_permission text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  if p_permission is null or p_permission not in (
    'sale', 'purchase', 'inventory', 'expense', 'reports',
    'invoice_send', 'ledger_read'
  ) then
    raise exception 'forbidden';
  end if;
  perform set_config('app.required_shop_permission', p_permission, true);
end;
$fn$;

revoke all on function private.allow_member_permission(text) from public, anon;
grant execute on function private.allow_member_permission(text) to authenticated;

create or replace function private.is_active_shop_member(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
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
        and membership.role in ('owner', 'partner', 'employee')
        and membership.revoked_at is null
    )
    and exists (
      select 1
      from public.shop_entitlements as entitlement
      where entitlement.shop_id = p_shop_id
    );
$function$;

create or replace function private.opening_require_reader_shop()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_user uuid := auth.uid();
  v_shop uuid;
  v_role text;
  v_perm text;
begin
  if v_user is null then
    raise exception 'unauthenticated';
  end if;
  if not private.caller_session_accepted() then
    raise exception 'session_expired';
  end if;
  if not exists (
    select 1
    from auth.users as identity
    where identity.id = v_user
      and coalesce(identity.is_anonymous, false) = false
      and identity.deleted_at is null
  ) then
    raise exception 'forbidden';
  end if;
  select membership.shop_id, membership.role
    into v_shop, v_role
  from public.shop_memberships as membership
  where membership.user_id = v_user
    and membership.role in ('owner', 'partner', 'employee')
    and membership.revoked_at is null;
  if v_shop is null then
    raise exception 'forbidden';
  end if;
  if not private.is_active_shop_member(v_shop)
    or not exists (
      select 1
      from public.shop_entitlements as entitlement
      where entitlement.shop_id = v_shop
        and entitlement.starts_at <= pg_catalog.now()
    ) then
    raise exception 'shop_unavailable';
  end if;
  if v_role = 'owner' then
    return v_shop;
  end if;
  v_perm := nullif(current_setting('app.required_shop_permission', true), '');
  if v_perm is null or not private.has_shop_permission(v_shop, v_perm) then
    raise exception 'forbidden';
  end if;
  return v_shop;
end;
$fn$;

create or replace function private.require_shop_owner()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  v_shop := private.opening_require_reader_shop();
  if not private.is_shop_owner(v_shop) then
    raise exception 'forbidden';
  end if;
  return v_shop;
end;
$fn$;

revoke all on function private.require_shop_owner() from public, anon;
grant execute on function private.require_shop_owner() to authenticated;

create or replace function private.shop_member_role(p_shop_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select membership.role
  from public.shop_memberships as membership
  where membership.shop_id = p_shop_id
    and membership.user_id = auth.uid()
    and membership.revoked_at is null;
$fn$;

revoke all on function private.shop_member_role(uuid) from public, anon;

-- ---------------------------------------------------------------------------
-- list_my_shop_accounts — role + grants
-- ---------------------------------------------------------------------------
drop function if exists public.list_my_shop_accounts();

create function public.list_my_shop_accounts()
returns table (
  shop_id uuid,
  shop_name text,
  member_role text,
  subscription_expires_at timestamptz,
  entitlement_status text,
  shop_image_sha256 text,
  grants text[]
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    shop.id,
    shop.name,
    membership.role,
    entitlement.expires_at,
    case
      when entitlement.shop_id is null or now() < entitlement.starts_at then 'pending'
      when entitlement.starts_at <= now() and now() < entitlement.expires_at then 'active'
      else 'expired'
    end,
    asset.sha256,
    case
      when membership.role = 'owner' then array[
        'sale', 'purchase', 'inventory', 'expense', 'reports', 'invoice_send'
      ]::text[]
      else coalesce((
        select array_agg(grant_row.permission order by grant_row.permission)
        from public.shop_member_grants as grant_row
        where grant_row.shop_id = membership.shop_id
          and grant_row.user_id = membership.user_id
      ), '{}'::text[])
    end
  from public.shop_memberships as membership
  join public.shops as shop on shop.id = membership.shop_id
  left join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  left join public.shop_image_assets as asset
    on asset.shop_id = shop.id
   and asset.id = shop.image_asset_id
  where membership.user_id = auth.uid()
    and membership.role in ('owner', 'partner', 'employee')
    and membership.revoked_at is null
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
    )
  order by shop.created_at;
$function$;

revoke all on function public.list_my_shop_accounts() from public, anon;
grant execute on function public.list_my_shop_accounts() to authenticated;

-- ---------------------------------------------------------------------------
-- Shop profile (owner only)
-- ---------------------------------------------------------------------------
create or replace function public.update_shop_profile_v1(
  p_key uuid,
  p_name text,
  p_owner_display_name text,
  p_phone text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_prior private.shop_profile_commands%rowtype;
  v_payload jsonb;
  v_phone text;
  v_region text;
  v_name text;
  v_owner text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_key is null
    or p_name is null or length(btrim(p_name)) not between 1 and 120
    or p_name ~ '[[:cntrl:]]'
    or p_owner_display_name is null
    or length(btrim(p_owner_display_name)) not between 1 and 120
    or p_owner_display_name ~ '[[:cntrl:]]'
    or p_phone is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.require_shop_owner();
  perform 1 from public.shops where id = v_shop for update;
  if not private.is_shop_owner(v_shop) then raise exception 'forbidden'; end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select shop.governorate_code into v_region from public.shops as shop where shop.id = v_shop;
  v_phone := private.registration_phone(p_phone, v_region);
  if v_phone is null then raise exception 'invalid_input'; end if;
  v_name := btrim(p_name);
  v_owner := btrim(p_owner_display_name);
  v_payload := jsonb_build_object(
    'name', v_name,
    'owner_display_name', v_owner,
    'phone', v_phone
  );
  select * into v_prior
  from private.shop_profile_commands
  where shop_id = v_shop and key = p_key;
  if found then
    if v_prior.actor_user_id is distinct from auth.uid()
      or v_prior.payload is distinct from v_payload then
      raise exception 'payload_mismatch';
    end if;
    return v_prior.result || jsonb_build_object('replayed', true);
  end if;
  if exists (
    select 1 from public.shops as other
    where other.phone = v_phone and other.id is distinct from v_shop
  ) or exists (
    select 1 from auth.users as identity
    where identity.phone = ltrim(v_phone, '+')
      and identity.id is distinct from auth.uid()
      and identity.deleted_at is null
  ) then
    raise exception 'identifier_taken';
  end if;
  update public.shops
  set name = v_name,
      owner_display_name = v_owner,
      phone = v_phone
  where id = v_shop;
  update auth.users
  set phone = ltrim(v_phone, '+'),
      phone_change = '',
      phone_change_token = '',
      updated_at = clock_timestamp()
  where id = auth.uid();
  insert into public.shop_member_grant_audits (
    shop_id, actor_user_id, subject_user_id, action, details, request_key
  ) values (
    v_shop, auth.uid(), auth.uid(), 'profile_updated', v_payload, p_key
  );
  insert into private.shop_profile_commands (
    shop_id, actor_user_id, key, payload, result
  ) values (
    v_shop, auth.uid(), p_key, v_payload,
    jsonb_build_object(
      'ok', true,
      'shop_id', v_shop,
      'name', v_name,
      'owner_display_name', v_owner,
      'phone', v_phone,
      'replayed', false
    )
  );
  return jsonb_build_object(
    'ok', true,
    'shop_id', v_shop,
    'name', v_name,
    'owner_display_name', v_owner,
    'phone', v_phone,
    'replayed', false
  );
end;
$fn$;

revoke all on function public.update_shop_profile_v1(uuid, text, text, text)
  from public, anon;
grant execute on function public.update_shop_profile_v1(uuid, text, text, text)
  to authenticated;

create or replace function public.get_shop_profile_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_row public.shops%rowtype;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.require_shop_owner();
  select * into v_row from public.shops where id = v_shop;
  return jsonb_build_object(
    'shop_id', v_row.id,
    'name', v_row.name,
    'owner_display_name', v_row.owner_display_name,
    'phone', v_row.phone,
    'governorate_code', v_row.governorate_code
  );
end;
$fn$;

revoke all on function public.get_shop_profile_v1() from public, anon;
grant execute on function public.get_shop_profile_v1() to authenticated;

notify pgrst, 'reload schema';
commit;

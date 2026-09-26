-- Egypt owner registration (ADR 0002). Not membership and not an entitlement.
--
-- Edge (not created here) calls begin_owner_registration with the service role,
-- then auth.admin.createUser({ id: reserved_user_id, email, phone: auth_phone,
-- password, email_confirm: true, phone_confirm: true }). auth_phone is digits
-- without a leading plus. A lost Auth response retries getUserById on the same
-- reserved id. complete_owner_registration then inserts one shop, one owner
-- membership, and one audit row. SQL accepts no password and stores none.
-- Custom Auth ids: https://supabase.com/docs/guides/platform/migrating-to-supabase/auth0#custom-user-id
--
-- email_confirm / phone_confirm only suppress Auth messages and set Auth's own
-- timestamps. Those timestamps are not authorization and are not proof that the
-- person controls the mailbox or handset.
--
-- Abandoned reservations are kept. Do not add cleanup that deletes auth.users.

create table public.egypt_governorates (
  code text primary key,
  name_ar text not null,
  display_order smallint not null,
  constraint egypt_governorates_code_check check (code ~ '^EG-[A-Z0-9]{1,3}$'),
  constraint egypt_governorates_name_check check (
    char_length(btrim(name_ar)) between 2 and 40
    and name_ar = btrim(name_ar)
  ),
  constraint egypt_governorates_display_order_check check (display_order between 1 and 27),
  constraint egypt_governorates_name_ar_key unique (name_ar),
  constraint egypt_governorates_display_order_key unique (display_order)
);

comment on table public.egypt_governorates is
  'Egyptian governorates for signup. ISO 3166-2 codes are stable. Arabic labels are display text. Clients may read and may not write.';

insert into public.egypt_governorates (code, name_ar, display_order)
values
  ('EG-ALX', 'الإسكندرية', 1),
  ('EG-IS', 'الإسماعيلية', 2),
  ('EG-LX', 'الأقصر', 3),
  ('EG-BA', 'البحر الأحمر', 4),
  ('EG-BH', 'البحيرة', 5),
  ('EG-GZ', 'الجيزة', 6),
  ('EG-DK', 'الدقهلية', 7),
  ('EG-SUZ', 'السويس', 8),
  ('EG-SHR', 'الشرقية', 9),
  ('EG-GH', 'الغربية', 10),
  ('EG-FYM', 'الفيوم', 11),
  ('EG-C', 'القاهرة', 12),
  ('EG-KB', 'القليوبية', 13),
  ('EG-MNF', 'المنوفية', 14),
  ('EG-MN', 'المنيا', 15),
  ('EG-WAD', 'الوادي الجديد', 16),
  ('EG-ASN', 'أسوان', 17),
  ('EG-AST', 'أسيوط', 18),
  ('EG-BNS', 'بني سويف', 19),
  ('EG-PTS', 'بورسعيد', 20),
  ('EG-JS', 'جنوب سيناء', 21),
  ('EG-DT', 'دمياط', 22),
  ('EG-SHG', 'سوهاج', 23),
  ('EG-SIN', 'شمال سيناء', 24),
  ('EG-KN', 'قنا', 25),
  ('EG-KFS', 'كفر الشيخ', 26),
  ('EG-MT', 'مطروح', 27);

alter table public.egypt_governorates enable row level security;
revoke all on table public.egypt_governorates from public, anon, authenticated;
grant select on table public.egypt_governorates to anon, authenticated;

create policy egypt_governorates_public_read
on public.egypt_governorates
for select
to anon, authenticated
using (true);

-- New columns stay nullable so shops created before this migration remain valid.
-- A row that sets either registration column must set the full protected profile.
alter table public.shops
  add column email text,
  add column governorate_code text;

alter table public.shops
  add constraint shops_governorate_code_fkey
    foreign key (governorate_code) references public.egypt_governorates (code),
  add constraint shops_email_canonical_check check (
    email is null
    or (
      char_length(email) between 3 and 320
      and email = lower(email)
      and email = btrim(email)
      and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    )
  ),
  add constraint shops_registered_profile_check check (
    (email is null and governorate_code is null)
    or (
      email is not null
      and governorate_code is not null
      and phone is not null
      and phone ~ '^\+201[0125][0-9]{8}$'
      and owner_display_name is not null
      and length(btrim(owner_display_name)) between 1 and 120
      and time_zone = 'Africa/Cairo'
    )
  );

create unique index shops_email_canonical_key
  on public.shops (email)
  where email is not null;

create unique index shops_phone_canonical_key
  on public.shops (phone)
  where phone is not null and phone ~ '^\+201[0125][0-9]{8}$';

create table private.owner_registration_reservations (
  request_key uuid primary key,
  reserved_user_id uuid not null unique default gen_random_uuid(),
  email text not null,
  phone text not null,
  owner_display_name text not null,
  business_name text not null,
  governorate_code text not null references public.egypt_governorates (code),
  status text not null default 'reserved',
  shop_id uuid references public.shops (id),
  created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  constraint owner_registration_email_key unique (email),
  constraint owner_registration_phone_key unique (phone),
  constraint owner_registration_email_check check (
    char_length(email) between 3 and 320
    and email = lower(email)
    and email = btrim(email)
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint owner_registration_phone_check check (phone ~ '^\+201[0125][0-9]{8}$'),
  constraint owner_registration_names_check check (
    char_length(owner_display_name) between 1 and 120
    and owner_display_name = btrim(owner_display_name)
    and char_length(business_name) between 1 and 120
    and business_name = btrim(business_name)
  ),
  constraint owner_registration_status_check check (status in ('reserved', 'completed')),
  constraint owner_registration_completion_check check (
    (status = 'reserved' and shop_id is null and completed_at is null)
    or (status = 'completed' and shop_id is not null and completed_at is not null)
  )
);

comment on table private.owner_registration_reservations is
  'Service-only signup reservation. Not a membership, grant, or entitlement. reserved_user_id is allocated before the Auth user exists, so it does not reference auth.users. Cleanup must not delete auth.users.';

create index owner_registration_reservations_reserved_idx
  on private.owner_registration_reservations (created_at)
  where status = 'reserved';

alter table private.owner_registration_reservations enable row level security;
alter table private.owner_registration_reservations force row level security;
revoke all on table private.owner_registration_reservations from public, anon, authenticated;

create function private.normalize_registration_email(p_email text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  v_email text;
begin
  if p_email is null then
    return null;
  end if;
  v_email := lower(btrim(p_email));
  if char_length(v_email) < 3 or char_length(v_email) > 320 then
    return null;
  end if;
  if v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return null;
  end if;
  return v_email;
end;
$function$;

revoke all on function private.normalize_registration_email(text) from public, anon, authenticated;

-- Accept local 010/011/012/015 plus eight digits, or the same number as +20 or 0020.
-- Spaces, ASCII hyphens, and parentheses are removed. Any other character fails.
-- Canonical form is +201[0125] and eight digits. Bare 20... without + or 00 fails.
create function private.normalize_egypt_mobile(p_phone text)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $function$
declare
  v_stripped text;
  v_national text;
begin
  if p_phone is null or btrim(p_phone) = '' then
    return null;
  end if;
  if p_phone ~ '[^0-9+ ()-]' then
    return null;
  end if;
  v_stripped := regexp_replace(p_phone, '[ ()-]', '', 'g');
  if v_stripped !~ '^\+?[0-9]+$' then
    return null;
  end if;
  if left(v_stripped, 3) = '+20' then
    v_national := substring(v_stripped from 4);
  elsif left(v_stripped, 4) = '0020' then
    v_national := substring(v_stripped from 5);
  elsif left(v_stripped, 1) = '0' then
    v_national := substring(v_stripped from 2);
  else
    return null;
  end if;
  if v_national ~ '^1[0125][0-9]{8}$' then
    return '+20' || v_national;
  end if;
  return null;
end;
$function$;

revoke all on function private.normalize_egypt_mobile(text) from public, anon, authenticated;

create function private.egypt_mobile_digits(p_canonical text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $function$
  select case
    when p_canonical ~ '^\+201[0125][0-9]{8}$' then substring(p_canonical from 2)
    else null
  end;
$function$;

revoke all on function private.egypt_mobile_digits(text) from public, anon, authenticated;

-- Auth stores the phone as digits without the leading plus. Also accept a stored
-- value that still contains a plus, spaces, or hyphens, compared by digits only.
create function private.auth_phone_matches(p_auth_phone text, p_canonical text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $function$
  select private.egypt_mobile_digits(p_canonical) is not null
    and regexp_replace(coalesce(p_auth_phone, ''), '[^0-9]', '', 'g')
      = private.egypt_mobile_digits(p_canonical);
$function$;

revoke all on function private.auth_phone_matches(text, text) from public, anon, authenticated;

-- A real GoTrue access token includes session_id. When that claim is present it
-- must match a live auth.sessions row for auth.uid(). When it is absent, actor
-- checks still apply; SQL tests can impersonate with request.jwt.claim.sub only.
create function private.caller_session_accepted()
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_raw text;
  v_session uuid;
begin
  v_raw := nullif(btrim(current_setting('request.jwt.claim.session_id', true)), '');
  if v_raw is null then
    begin
      v_raw := nullif(btrim(
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id'
      ), '');
    exception
      when others then
        return false;
    end;
  end if;
  if v_raw is null then
    return true;
  end if;
  begin
    v_session := v_raw::uuid;
  exception
    when invalid_text_representation then
      return false;
  end;
  if auth.uid() is null then
    return false;
  end if;
  return exists (
    select 1
    from auth.sessions as session_row
    where session_row.id = v_session
      and session_row.user_id = auth.uid()
      and (session_row.not_after is null or session_row.not_after > now())
  );
end;
$function$;

revoke all on function private.caller_session_accepted() from public, anon, authenticated;

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
        and membership.revoked_at is null
    )
    and exists (
      select 1
      from public.shop_entitlements as entitlement
      where entitlement.shop_id = p_shop_id
    );
$function$;

revoke all on function private.is_active_shop_member(uuid) from public, anon;
grant execute on function private.is_active_shop_member(uuid) to authenticated;

create or replace function public.list_my_shop_accounts()
returns table (
  shop_id uuid,
  shop_name text,
  member_role text,
  subscription_expires_at timestamptz,
  entitlement_status text
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
    end
  from public.shop_memberships as membership
  join public.shops as shop on shop.id = membership.shop_id
  left join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  where membership.user_id = auth.uid()
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

create or replace function public.is_platform_admin()
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
      from public.platform_admins as admin
      where admin.user_id = auth.uid()
    );
$function$;

revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- Legacy setup and invitation RPCs bypass required registration or bind an
-- invitation to an unverified contact. Close them for API roles. Grant and
-- revoke staff commands stay as they are. Invitation binding is undecided.
revoke all on function public.create_shop_account(text, text, text, text, uuid) from public, anon, authenticated;
revoke all on function public.create_staff_invitation(uuid, text, text, uuid, uuid) from public, anon, authenticated;
revoke all on function public.accept_staff_invitation(uuid) from public, anon, authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.create_shop_account(text, text, text, text, uuid) from service_role';
    execute 'revoke all on function public.create_staff_invitation(uuid, text, text, uuid, uuid) from service_role';
    execute 'revoke all on function public.accept_staff_invitation(uuid) from service_role';
  end if;
end;
$revoke_service$;

create function private.owner_registration_result(p_request_key uuid)
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
language sql
stable
security definer
set search_path = ''
as $function$
  select
    reservation.request_key,
    reservation.reserved_user_id,
    reservation.email,
    reservation.phone,
    substring(reservation.phone from 2),
    reservation.owner_display_name,
    reservation.business_name,
    reservation.governorate_code,
    reservation.status,
    reservation.shop_id
  from private.owner_registration_reservations as reservation
  where reservation.request_key = p_request_key;
$function$;

revoke all on function private.owner_registration_result(uuid) from public, anon, authenticated;

create function public.begin_owner_registration(
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

  v_phone := private.normalize_egypt_mobile(p_phone);
  if v_phone is null then
    raise exception 'invalid_phone' using errcode = '22023';
  end if;

  v_governorate := btrim(p_governorate_code);
  if v_governorate is null
    or v_governorate = ''
    or not exists (
      select 1
      from public.egypt_governorates as governorate
      where governorate.code = v_governorate
    ) then
    raise exception 'invalid_governorate' using errcode = '22023';
  end if;

  -- Same order on every call: request key, then email, then phone.
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

comment on function public.begin_owner_registration(uuid, text, text, text, text, text) is
  'Service-only. Validates the owner profile, reserves a new UUID v4 Auth id, and replays the same request key only for the same normalized profile. Takes no password and no caller-supplied user id.';

revoke all on function public.begin_owner_registration(uuid, text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.begin_owner_registration(uuid, text, text, text, text, text) to service_role;

create function public.complete_owner_registration(p_request_key uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reservation private.owner_registration_reservations%rowtype;
  v_identity auth.users%rowtype;
  v_shop uuid;
begin
  if p_request_key is null then
    raise exception 'invalid_registration' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(840261, hashtext(p_request_key::text));

  select * into v_reservation
  from private.owner_registration_reservations
  where request_key = p_request_key
  for update;

  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;

  if v_reservation.status = 'completed' then
    return v_reservation.shop_id;
  end if;

  select * into v_identity
  from auth.users
  where id = v_reservation.reserved_user_id
  for update;

  if not found
    or coalesce(v_identity.is_anonymous, false)
    or v_identity.deleted_at is not null then
    raise exception 'auth_user_not_ready' using errcode = 'P0001';
  end if;

  if lower(btrim(coalesce(v_identity.email, ''))) <> v_reservation.email
    or not private.auth_phone_matches(v_identity.phone, v_reservation.phone) then
    raise exception 'auth_contact_mismatch' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.shop_memberships as membership
    where membership.user_id = v_reservation.reserved_user_id
  ) then
    raise exception 'registration_conflict' using errcode = '23505';
  end if;

  begin
    insert into public.shops (
      name,
      owner_display_name,
      phone,
      email,
      governorate_code,
      time_zone,
      created_by,
      setup_request_key
    ) values (
      v_reservation.business_name,
      v_reservation.owner_display_name,
      v_reservation.phone,
      v_reservation.email,
      v_reservation.governorate_code,
      'Africa/Cairo',
      v_reservation.reserved_user_id,
      v_reservation.request_key
    )
    returning id into v_shop;

    insert into public.shop_memberships (shop_id, user_id, role)
    values (v_shop, v_reservation.reserved_user_id, 'owner');

    insert into public.identity_audit_events (
      shop_id,
      actor_user_id,
      action,
      subject_user_id,
      correlation_id,
      details
    ) values (
      v_shop,
      v_reservation.reserved_user_id,
      'owner_registered',
      v_reservation.reserved_user_id,
      v_reservation.request_key,
      jsonb_build_object('governorate_code', v_reservation.governorate_code)
    );

    update private.owner_registration_reservations
    set status = 'completed',
        shop_id = v_shop,
        completed_at = clock_timestamp()
    where request_key = v_reservation.request_key;
  exception
    when unique_violation then
      raise exception 'registration_conflict' using errcode = '23505';
  end;

  return v_shop;
end;
$function$;

comment on function public.complete_owner_registration(uuid) is
  'Service-only. Completes one reserved Auth user whose email and phone both match. Inserts one shop, owner membership, and audit row, or rolls all of that back. Does not insert an entitlement or a trial.';

revoke all on function public.complete_owner_registration(uuid) from public, anon, authenticated;
grant execute on function public.complete_owner_registration(uuid) to service_role;

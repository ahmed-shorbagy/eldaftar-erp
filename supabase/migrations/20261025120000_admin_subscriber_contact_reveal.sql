-- ADM-07: platform-admin PII reveal for phone/country/city.
-- Does not widen admin_list_subscribers_v1 / admin_get_subscriber_v1.

begin;

alter table public.platform_admins
  add column if not exists can_view_subscriber_contact boolean not null default false;

comment on column public.platform_admins.can_view_subscriber_contact is
  'When true, the platform admin may call admin_get_subscriber_contact_v1.';

update public.platform_admins
set can_view_subscriber_contact = true
where can_view_subscriber_contact is distinct from true;

create table public.admin_subscriber_contact_reveals (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops (id),
  admin_user_id uuid not null references auth.users (id),
  revealed_at timestamptz not null default timezone('utc', now())
);

create index admin_subscriber_contact_reveals_shop_idx
  on public.admin_subscriber_contact_reveals (shop_id, revealed_at desc);

alter table public.admin_subscriber_contact_reveals enable row level security;
revoke all on table public.admin_subscriber_contact_reveals from anon, authenticated;

create function private.admin_subscriber_contact_gate()
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select case
    when private.admin_subscriber_gate() is distinct from 'ok' then private.admin_subscriber_gate()
    when exists (
      select 1
      from public.platform_admins as admin
      where admin.user_id = auth.uid()
        and admin.can_view_subscriber_contact
    ) then 'ok'
    else 'forbidden'
  end;
$fn$;

revoke all on function private.admin_subscriber_contact_gate()
  from public, anon, authenticated;

create function public.admin_get_subscriber_contact_v1(p_shop_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_gate text;
  v_phone text;
  v_country text;
  v_governorate text;
  v_region text;
  v_location text;
begin
  v_gate := private.admin_subscriber_contact_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  if p_shop_id is null then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select shop.phone, shop.country_code, shop.governorate_code, shop.region_name
  into v_phone, v_country, v_governorate, v_region
  from public.shops as shop
  where shop.id = p_shop_id;

  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  if v_country = 'EG' then
    select gov.name_ar into v_location
    from public.egypt_governorates as gov
    where gov.code = v_governorate;
    v_location := coalesce(v_location, v_governorate);
  else
    v_location := nullif(btrim(coalesce(v_region, '')), '');
    if v_location is null and v_governorate like '__:%' then
      v_location := nullif(btrim(substr(v_governorate, 4)), '');
    end if;
  end if;

  insert into public.admin_subscriber_contact_reveals (shop_id, admin_user_id)
  values (p_shop_id, auth.uid());

  return jsonb_build_object(
    'shop_id', p_shop_id,
    'phone', v_phone,
    'country_code', v_country,
    'location_display_ar', v_location
  );
end;
$function$;

revoke all on function public.admin_get_subscriber_contact_v1(uuid)
  from public, anon;
grant execute on function public.admin_get_subscriber_contact_v1(uuid)
  to authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'revoke all on function private.admin_subscriber_contact_gate() from service_role';
    execute 'revoke all on function public.admin_get_subscriber_contact_v1(uuid) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';

commit;

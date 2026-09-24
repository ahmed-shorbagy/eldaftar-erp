-- Account setup is separate from subscription activation. A new shop has no
-- entitlement until the owner-controlled subscription process provisions it.
alter table public.shops
  add column phone text,
  add column owner_display_name text,
  add column time_zone text not null default 'Africa/Cairo',
  add column created_by uuid references auth.users(id),
  add column setup_request_key uuid;
alter table public.shops
  add constraint shops_name_nonblank check (length(btrim(name)) between 1 and 120),
  add constraint shops_owner_name_nonblank check (
    owner_display_name is null or length(btrim(owner_display_name)) between 1 and 120
  ),
  add constraint shops_setup_identity check (
    (created_by is null and setup_request_key is null)
    or (created_by is not null and setup_request_key is not null)
  ),
  add constraint shops_setup_request_unique unique (created_by, setup_request_key);

create function public.create_shop_account(
  p_name text,
  p_owner_display_name text,
  p_phone text,
  p_time_zone text,
  p_request_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_shop uuid;
  v_existing public.shops%rowtype;
begin
  if v_actor is null or not exists (
    select 1 from auth.users as identity
    where identity.id = v_actor and identity.email_confirmed_at is not null
  ) then
    raise exception 'verified_email_required' using errcode = '42501';
  end if;
  if p_request_key is null or p_name is null or length(btrim(p_name)) not between 1 and 120
    or p_owner_display_name is null or length(btrim(p_owner_display_name)) not between 1 and 120
    or p_time_zone is null or not exists (
      select 1 from pg_timezone_names where name = p_time_zone
    ) then
    raise exception 'invalid_shop_setup' using errcode = '22023';
  end if;
  if p_phone is not null and length(btrim(p_phone)) > 30 then
    raise exception 'invalid_shop_phone' using errcode = '22023';
  end if;

  insert into public.shops (name, owner_display_name, phone, time_zone, created_by, setup_request_key)
  values (btrim(p_name), btrim(p_owner_display_name), nullif(btrim(p_phone), ''), p_time_zone, v_actor, p_request_key)
  on conflict (created_by, setup_request_key) do nothing
  returning id into v_shop;

  if v_shop is null then
    select * into v_existing
    from public.shops
    where created_by = v_actor and setup_request_key = p_request_key;
    if v_existing.id is null
      or v_existing.name <> btrim(p_name)
      or v_existing.owner_display_name <> btrim(p_owner_display_name)
      or v_existing.phone is distinct from nullif(btrim(p_phone), '')
      or v_existing.time_zone <> p_time_zone then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return v_existing.id;
  end if;

  insert into public.shop_memberships (shop_id, user_id, role)
  values (v_shop, v_actor, 'owner');
  insert into public.identity_audit_events
    (shop_id, actor_user_id, action, subject_user_id, correlation_id)
  values (v_shop, v_actor, 'shop_created', v_actor, p_request_key);
  return v_shop;
end;
$function$;

revoke all on function public.create_shop_account(text,text,text,text,uuid) from public, anon;
grant execute on function public.create_shop_account(text,text,text,text,uuid) to authenticated;

-- This lookup includes the caller's pending-activation shop, while ordinary
-- shop table reads remain behind the entitlement-aware RLS policy.
create function public.list_my_shop_accounts()
returns table (
  shop_id uuid,
  shop_name text,
  member_role text,
  subscription_expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select shop.id, shop.name, membership.role, entitlement.expires_at
  from public.shop_memberships as membership
  join public.shops as shop on shop.id = membership.shop_id
  left join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  where membership.user_id = auth.uid()
    and membership.revoked_at is null
    and exists (
      select 1 from auth.users as identity
      where identity.id = auth.uid()
        and identity.email_confirmed_at is not null
    )
  order by shop.created_at;
$function$;

revoke all on function public.list_my_shop_accounts() from public, anon;
grant execute on function public.list_my_shop_accounts() to authenticated;

-- Owner-only access model.
-- Product decision 2026-09-26: each shop has one owner Auth account. Staff,
-- partner, invitation, and per-user permission concepts are removed entirely.

do $owner_only_preflight$
begin
  if exists (
    select 1
    from public.shop_memberships
    where role <> 'owner'
  ) then
    raise exception 'owner_only_migration_requires_non_owner_membership_cleanup';
  end if;
  if exists (
    select shop_id
    from public.shop_memberships
    group by shop_id
    having count(*) > 1
  ) then
    raise exception 'owner_only_migration_requires_duplicate_shop_cleanup';
  end if;
  if exists (
    select user_id
    from public.shop_memberships
    group by user_id
    having count(*) > 1
  ) then
    raise exception 'owner_only_migration_requires_duplicate_user_cleanup';
  end if;
end;
$owner_only_preflight$;

drop policy if exists shop_memberships_select_self_or_staff_manager
  on public.shop_memberships;
drop policy if exists shop_member_grants_select_self_or_staff_manager
  on public.shop_member_grants;

drop function if exists public.create_staff_invitation(uuid, text, text, uuid, uuid) cascade;
drop function if exists public.accept_staff_invitation(uuid) cascade;
drop function if exists public.set_staff_permission(uuid, uuid, text, boolean, uuid) cascade;
drop function if exists public.revoke_staff_member(uuid, uuid, uuid) cascade;
drop function if exists private.can_manage_staff(uuid) cascade;
drop function if exists private.has_shop_permission(uuid, text) cascade;

drop table if exists public.shop_invitations cascade;
drop table if exists public.shop_member_grants cascade;

alter table public.shop_memberships
  drop constraint shop_memberships_role_check,
  add constraint shop_memberships_role_check check (role = 'owner'),
  add constraint shop_memberships_one_owner_per_shop unique (shop_id),
  add constraint shop_memberships_one_shop_per_user unique (user_id);

comment on table public.shop_memberships is
  'Owner-account association. Exactly one owner Auth user per shop and one shop per Auth user. revoked_at suspends that owner account.';
comment on column public.shop_memberships.role is
  'Compatibility field constrained to owner. Staff and partner roles do not exist.';

create policy shop_memberships_select_self
on public.shop_memberships
for select
to authenticated
using (
  private.is_active_shop_member(shop_id)
  and user_id = (select auth.uid())
);

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
      from public.shop_memberships as ownership
      where ownership.shop_id = p_shop_id
        and ownership.user_id = auth.uid()
        and ownership.role = 'owner'
        and ownership.revoked_at is null
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
    'owner'::text,
    entitlement.expires_at,
    case
      when entitlement.shop_id is null or now() < entitlement.starts_at then 'pending'
      when entitlement.starts_at <= now() and now() < entitlement.expires_at then 'active'
      else 'expired'
    end
  from public.shop_memberships as ownership
  join public.shops as shop on shop.id = ownership.shop_id
  left join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  where ownership.user_id = auth.uid()
    and ownership.role = 'owner'
    and ownership.revoked_at is null
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

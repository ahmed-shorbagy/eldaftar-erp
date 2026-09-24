-- Read access for shop members.
-- is_active_shop_member requires a non-revoked membership for auth.uid() and an entitlement row.
-- An expired entitlement still passes; a missing entitlement does not.
-- Authenticated SELECT policies call that helper. Membership and grant rows are limited
-- to the caller unless can_manage_staff allows every row in that shop.
-- Clients receive no write privileges. shop_invitations is not granted, so token_hash stays inaccessible.

create schema if not exists private;

revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create function private.is_active_shop_member(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null
    and exists (
      select 1
      from public.shop_memberships as shop_membership
      where shop_membership.shop_id = p_shop_id
        and shop_membership.user_id = auth.uid()
        and shop_membership.revoked_at is null
    )
    and exists (
      select 1
      from public.shop_entitlements as shop_entitlement
      where shop_entitlement.shop_id = p_shop_id
    );
$$;

revoke execute on function private.is_active_shop_member(uuid) from public, anon;
grant execute on function private.is_active_shop_member(uuid) to authenticated;

-- Owner membership is enough. Partner and employee need an explicit staff_manage grant.
-- SECURITY DEFINER reads membership and grants directly so SELECT policies do not recurse through RLS.
create function private.can_manage_staff(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    private.is_active_shop_member(p_shop_id)
    and exists (
      select 1
      from public.shop_memberships as shop_membership
      where shop_membership.shop_id = p_shop_id
        and shop_membership.user_id = auth.uid()
        and shop_membership.revoked_at is null
        and (
          shop_membership.role = 'owner'
          or (
            shop_membership.role in ('partner', 'employee')
            and exists (
              select 1
              from public.shop_member_grants as shop_member_grant
              where shop_member_grant.shop_id = shop_membership.shop_id
                and shop_member_grant.user_id = shop_membership.user_id
                and shop_member_grant.permission = 'staff_manage'
            )
          )
        )
    );
$$;

revoke execute on function private.can_manage_staff(uuid) from public, anon;
grant execute on function private.can_manage_staff(uuid) to authenticated;

grant select on table
  public.shops,
  public.shop_memberships,
  public.shop_entitlements,
  public.shop_member_grants
to authenticated;

create policy shops_select_active_member
on public.shops
for select
to authenticated
using (private.is_active_shop_member(id));

create policy shop_entitlements_select_active_member
on public.shop_entitlements
for select
to authenticated
using (private.is_active_shop_member(shop_id));

create policy shop_memberships_select_self_or_staff_manager
on public.shop_memberships
for select
to authenticated
using (
  private.is_active_shop_member(shop_id)
  and (
    user_id = auth.uid()
    or private.can_manage_staff(shop_id)
  )
);

create policy shop_member_grants_select_self_or_staff_manager
on public.shop_member_grants
for select
to authenticated
using (
  private.is_active_shop_member(shop_id)
  and (
    user_id = auth.uid()
    or private.can_manage_staff(shop_id)
  )
);

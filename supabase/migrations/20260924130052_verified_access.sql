-- Complete the identity boundary before any business tables use these helpers.
-- SQL functions have a fixed search path and never trust caller-supplied actor IDs.
create or replace function private.is_active_shop_member(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1 from auth.users as identity
      where identity.id = auth.uid()
        and identity.email_confirmed_at is not null
    )
    and exists (
      select 1 from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = auth.uid()
        and membership.revoked_at is null
    )
    and exists (
      select 1 from public.shop_entitlements as entitlement
      where entitlement.shop_id = p_shop_id
    );
$function$;

create function private.can_write_shop(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select private.is_active_shop_member(p_shop_id)
    and exists (
      select 1 from public.shop_entitlements as entitlement
      where entitlement.shop_id = p_shop_id
        and entitlement.starts_at <= now()
        and now() < entitlement.expires_at
    );
$function$;

revoke execute on function private.can_write_shop(uuid) from public, anon;
grant execute on function private.can_write_shop(uuid) to authenticated;

create function private.has_shop_permission(p_shop_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select p_permission in (
      'sale','purchase','expense','close_day','inventory_edit',
      'invoice_dispatch','report_view','staff_manage','shop_settings'
    )
    and private.is_active_shop_member(p_shop_id)
    and exists (
      select 1 from public.shop_memberships as membership
      where membership.shop_id = p_shop_id
        and membership.user_id = auth.uid()
        and membership.revoked_at is null
        and (
          membership.role = 'owner'
          or exists (
            select 1 from public.shop_member_grants as member_grant
            where member_grant.shop_id = p_shop_id
              and member_grant.user_id = auth.uid()
              and member_grant.permission = p_permission
          )
        )
    );
$function$;

revoke execute on function private.has_shop_permission(uuid, text) from public, anon;
grant execute on function private.has_shop_permission(uuid, text) to authenticated;

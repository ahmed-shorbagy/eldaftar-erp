-- Replace list_my_shop_accounts so shop selection can read a server-calculated
-- entitlement_status. DROP is required because the result type gains a column.
drop function if exists public.list_my_shop_accounts();

create function public.list_my_shop_accounts()
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
    and exists (
      select 1 from auth.users as identity
      where identity.id = auth.uid()
        and identity.email_confirmed_at is not null
    )
  order by shop.created_at;
$function$;

revoke all on function public.list_my_shop_accounts() from public, anon;
grant execute on function public.list_my_shop_accounts() to authenticated;

-- ADM-03: server-timed in-app subscription expiry notices and durable dismissals.
-- Does not change list_my_shop_accounts, entitlements, or financial write gates.

begin;

create table public.subscription_notice_dismissals (
  shop_id uuid not null references public.shops (id),
  user_id uuid not null references auth.users (id),
  kind text not null,
  entitlement_expires_at timestamptz not null,
  dismissed_at timestamptz not null default now(),
  constraint subscription_notice_dismissals_kind_check
    check (kind in ('renewal_due', 'expired')),
  constraint subscription_notice_dismissals_pkey
    primary key (shop_id, user_id, kind, entitlement_expires_at)
);

create index subscription_notice_dismissals_user_idx
  on public.subscription_notice_dismissals (user_id);

alter table public.subscription_notice_dismissals enable row level security;

revoke all on table public.subscription_notice_dismissals from anon, authenticated;

create function private.subscription_notice_kind(
  p_starts_at timestamptz,
  p_expires_at timestamptz,
  p_now timestamptz default now()
)
returns text
language sql
immutable
set search_path = ''
as $function$
  select case
    when p_starts_at is null or p_expires_at is null then null
    when p_now < p_starts_at then null
    when p_starts_at <= p_now
      and p_now < p_expires_at
      and p_now >= p_expires_at - interval '72 hours' then 'renewal_due'
    when p_now >= p_expires_at then 'expired'
    else null
  end;
$function$;

revoke all on function private.subscription_notice_kind(timestamptz, timestamptz, timestamptz)
  from public, anon, authenticated;

create function private.subscription_notice_owner_session()
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
        and (identity.banned_until is null or identity.banned_until <= now())
    );
$function$;

revoke all on function private.subscription_notice_owner_session()
  from public, anon, authenticated;

create function public.list_my_subscription_notices_v1()
returns table (
  shop_id uuid,
  kind text,
  entitlement_expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    shop.id,
    private.subscription_notice_kind(
      entitlement.starts_at,
      entitlement.expires_at,
      now()
    ),
    entitlement.expires_at
  from public.shop_memberships as ownership
  join public.shops as shop on shop.id = ownership.shop_id
  join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  where ownership.user_id = auth.uid()
    and ownership.role = 'owner'
    and ownership.revoked_at is null
    and private.subscription_notice_owner_session()
    and private.subscription_notice_kind(
      entitlement.starts_at,
      entitlement.expires_at,
      now()
    ) is not null
    and not exists (
      select 1
      from public.subscription_notice_dismissals as dismissal
      where dismissal.shop_id = shop.id
        and dismissal.user_id = auth.uid()
        and dismissal.kind = private.subscription_notice_kind(
          entitlement.starts_at,
          entitlement.expires_at,
          now()
        )
        and dismissal.entitlement_expires_at = entitlement.expires_at
    )
  order by shop.created_at;
$function$;

revoke all on function public.list_my_subscription_notices_v1() from public, anon;
grant execute on function public.list_my_subscription_notices_v1() to authenticated;

create function public.dismiss_subscription_notice_v1(
  p_shop_id uuid,
  p_kind text,
  p_expires_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_starts timestamptz;
  v_expires timestamptz;
  v_kind text;
begin
  if p_shop_id is null
    or p_kind is null
    or p_kind not in ('renewal_due', 'expired')
    or p_expires_at is null then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if not private.subscription_notice_owner_session() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.shop_memberships as ownership
    where ownership.shop_id = p_shop_id
      and ownership.user_id = auth.uid()
      and ownership.role = 'owner'
      and ownership.revoked_at is null
  ) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select entitlement.starts_at, entitlement.expires_at
    into v_starts, v_expires
  from public.shop_entitlements as entitlement
  where entitlement.shop_id = p_shop_id
  for share;

  if v_expires is null then
    raise exception 'notice_unavailable' using errcode = 'P0002';
  end if;

  v_kind := private.subscription_notice_kind(v_starts, v_expires, now());
  if v_kind is null
    or v_kind is distinct from p_kind
    or v_expires is distinct from p_expires_at then
    raise exception 'notice_stale' using errcode = 'P0001';
  end if;

  insert into public.subscription_notice_dismissals (
    shop_id,
    user_id,
    kind,
    entitlement_expires_at
  ) values (
    p_shop_id,
    auth.uid(),
    p_kind,
    p_expires_at
  )
  on conflict do nothing;

  return jsonb_build_object(
    'shop_id', p_shop_id,
    'kind', p_kind,
    'entitlement_expires_at', p_expires_at,
    'status', 'dismissed'
  );
end;
$function$;

revoke all on function public.dismiss_subscription_notice_v1(uuid, text, timestamptz)
  from public, anon;
grant execute on function public.dismiss_subscription_notice_v1(uuid, text, timestamptz)
  to authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.list_my_subscription_notices_v1() from service_role';
    execute 'revoke all on function public.dismiss_subscription_notice_v1(uuid, text, timestamptz) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';

commit;

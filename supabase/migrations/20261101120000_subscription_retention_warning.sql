-- RET-01 / RET-02: four calendar months of retention after expiry, and one
-- dismissible owner warning during the last 30 shop-local days. No deletion,
-- no reset, and no change to redeem_subscription_code or financial rows.

begin;

alter table public.subscription_notice_dismissals
  drop constraint subscription_notice_dismissals_kind_check;

alter table public.subscription_notice_dismissals
  add constraint subscription_notice_dismissals_kind_check
  check (kind in ('renewal_due', 'expired', 'retention_ending'));

create function private.subscription_retention_ends_at(
  p_expires_at timestamptz,
  p_time_zone text
)
returns timestamptz
language sql
stable
set search_path = ''
as $function$
  select (
    (p_expires_at at time zone private.shop_display_zone(p_time_zone))
    + interval '4 months'
  ) at time zone private.shop_display_zone(p_time_zone);
$function$;

revoke all on function private.subscription_retention_ends_at(timestamptz, text)
  from public, anon, authenticated;

drop function public.dismiss_subscription_notice_v1(uuid, text, timestamptz);
drop function public.list_my_subscription_notices_v1();
drop function private.subscription_notice_kind(timestamptz, timestamptz, timestamptz);

create function private.subscription_notice_kind(
  p_starts_at timestamptz,
  p_expires_at timestamptz,
  p_now timestamptz default now(),
  p_time_zone text default 'Africa/Cairo'
)
returns text
language plpgsql
stable
set search_path = ''
as $function$
declare
  v_zone text;
  v_retention_end timestamptz;
  v_warning_start timestamptz;
begin
  if p_starts_at is null or p_expires_at is null or p_now < p_starts_at then
    return null;
  end if;

  if p_starts_at <= p_now and p_now < p_expires_at then
    if p_now >= p_expires_at - interval '72 hours' then
      return 'renewal_due';
    end if;
    return null;
  end if;

  if p_now >= p_expires_at then
    v_zone := private.shop_display_zone(p_time_zone);
    v_retention_end := private.subscription_retention_ends_at(p_expires_at, v_zone);
    v_warning_start := (
      (v_retention_end at time zone v_zone) - interval '30 days'
    ) at time zone v_zone;
    if p_now >= v_warning_start and p_now < v_retention_end then
      return 'retention_ending';
    end if;
    return 'expired';
  end if;

  return null;
end;
$function$;

revoke all on function private.subscription_notice_kind(timestamptz, timestamptz, timestamptz, text)
  from public, anon, authenticated;

create function public.list_my_subscription_notices_v1()
returns table (
  shop_id uuid,
  kind text,
  entitlement_expires_at timestamptz,
  retention_ends_at timestamptz,
  retention_ends_on text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    shop.id,
    notice.kind,
    entitlement.expires_at,
    case
      when notice.kind = 'retention_ending' then notice.retention_ends_at
      else null
    end,
    case
      when notice.kind = 'retention_ending' then notice.retention_ends_on
      else null
    end
  from public.shop_memberships as ownership
  join public.shops as shop on shop.id = ownership.shop_id
  join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  cross join lateral (
    select
      private.subscription_notice_kind(
        entitlement.starts_at,
        entitlement.expires_at,
        now(),
        shop.time_zone
      ) as kind,
      private.subscription_retention_ends_at(
        entitlement.expires_at,
        shop.time_zone
      ) as retention_ends_at,
      to_char(
        private.subscription_retention_ends_at(
          entitlement.expires_at,
          shop.time_zone
        ) at time zone private.shop_display_zone(shop.time_zone),
        'YYYY-MM-DD'
      ) as retention_ends_on
  ) as notice
  where ownership.user_id = auth.uid()
    and ownership.role = 'owner'
    and ownership.revoked_at is null
    and private.subscription_notice_owner_session()
    and notice.kind is not null
    and not exists (
      select 1
      from public.subscription_notice_dismissals as dismissal
      where dismissal.shop_id = shop.id
        and dismissal.user_id = auth.uid()
        and dismissal.kind = notice.kind
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
  v_zone text;
  v_kind text;
begin
  if p_shop_id is null
    or p_kind is null
    or p_kind not in ('renewal_due', 'expired', 'retention_ending')
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

  select entitlement.starts_at, entitlement.expires_at, shop.time_zone
    into v_starts, v_expires, v_zone
  from public.shop_entitlements as entitlement
  join public.shops as shop on shop.id = entitlement.shop_id
  where entitlement.shop_id = p_shop_id
  for share;

  if v_expires is null then
    raise exception 'notice_unavailable' using errcode = 'P0002';
  end if;

  v_kind := private.subscription_notice_kind(v_starts, v_expires, now(), v_zone);
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
    execute 'revoke all on function private.subscription_retention_ends_at(timestamptz, text) from service_role';
    execute 'revoke all on function private.subscription_notice_kind(timestamptz, timestamptz, timestamptz, text) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';

commit;

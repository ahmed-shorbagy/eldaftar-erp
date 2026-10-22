-- ADM-01 read-only subscriber directory.
-- Each response is one statement snapshot of shop id/name, registration
-- time, entitlement bounds and the existing pending/active/expired rule.
-- The cursor is a keyset position for a later page, not a snapshot frozen
-- across pages. No contact, location, Auth, financial, media or audit
-- columns. User metadata is not read.
-- Counts travel as exact decimal strings. Platform-admin checks run inside
-- the same statement as the rows they protect.
begin;

create index shops_registration_order_idx
  on public.shops (created_at, id);

comment on index public.shops_registration_order_idx is
  'Keyset order for the platform-admin subscriber directory: registration time, then shop id.';

create function private.admin_subscriber_gate()
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select case
    when auth.uid() is null then 'unauthenticated'
    when not private.caller_session_accepted() then 'session_expired'
    when exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and identity.banned_until > pg_catalog.now()
    ) then 'forbidden'
    when public.is_platform_admin() then 'ok'
    else 'forbidden'
  end;
$fn$;

revoke all on function private.admin_subscriber_gate() from public, anon, authenticated;

create function private.admin_list_subscribers_payload(
  p_status text,
  p_search text,
  p_cursor_at timestamptz,
  p_cursor_id uuid,
  p_page_size integer
) returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  with gate as (
    select private.admin_subscriber_gate() as reason
  )
  select case
    when gate.reason <> 'ok' then pg_catalog.jsonb_build_object('error', gate.reason)
    when p_cursor_id is not null and not exists (
      select 1
      from public.shops as cursor_shop
      where cursor_shop.id = p_cursor_id
        and cursor_shop.created_at = p_cursor_at
    ) then pg_catalog.jsonb_build_object('error', 'stale_cursor')
    else (
      with search_shop as (
        select case
          when p_search ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
            then p_search::uuid
          else null
        end as shop_id
      ),
      classified as (
        select
          shop.id,
          shop.name,
          shop.created_at,
          entitlement.starts_at,
          entitlement.expires_at,
          case
            when entitlement.shop_id is null
              or pg_catalog.now() < entitlement.starts_at then 'pending'
            when entitlement.starts_at <= pg_catalog.now()
              and pg_catalog.now() < entitlement.expires_at then 'active'
            else 'expired'
          end as subscription_status
        from public.shops as shop
        left join public.shop_entitlements as entitlement
          on entitlement.shop_id = shop.id
      ),
      globals as (
        select
          count(*)::text as all_count,
          count(*) filter (where subscription_status = 'active')::text as active_count,
          count(*) filter (where subscription_status = 'pending')::text as pending_count,
          count(*) filter (where subscription_status = 'expired')::text as expired_count
        from classified
      ),
      filtered as (
        select classified.*
        from classified
        cross join search_shop
        where (p_status = 'all' or classified.subscription_status = p_status)
          and (
            p_search = ''
            or pg_catalog.strpos(
              pg_catalog.lower(classified.name),
              pg_catalog.lower(p_search)
            ) > 0
            or classified.id = search_shop.shop_id
          )
      ),
      window_rows as (
        select filtered.*
        from filtered
        where p_cursor_id is null
          or (filtered.created_at, filtered.id) > (p_cursor_at, p_cursor_id)
        order by filtered.created_at, filtered.id
        limit (p_page_size + 1)
      ),
      page_rows as (
        select window_rows.*
        from window_rows
        order by window_rows.created_at, window_rows.id
        limit p_page_size
      )
      select pg_catalog.jsonb_build_object(
        'snapshot_at', pg_catalog.now(),
        'counts', pg_catalog.jsonb_build_object(
          'all', (select all_count from globals),
          'active', (select active_count from globals),
          'pending', (select pending_count from globals),
          'expired', (select expired_count from globals)
        ),
        'filtered_count', (select count(*)::text from filtered),
        'page_size', p_page_size,
        'rows', coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'shop_id', page_rows.id,
              'shop_name', page_rows.name,
              'registered_at', page_rows.created_at,
              'entitlement_starts_at', page_rows.starts_at,
              'entitlement_expires_at', page_rows.expires_at,
              'subscription_status', page_rows.subscription_status
            )
            order by page_rows.created_at, page_rows.id
          )
          from page_rows
        ), '[]'::jsonb),
        'next_cursor', case
          when (select count(*) from window_rows) > p_page_size then (
            select 'v1|'
              || pg_catalog.to_char(
                page_rows.created_at at time zone 'UTC',
                'YYYY-MM-DD HH24:MI:SS.US'
              )
              || '|'
              || page_rows.id::text
            from page_rows
            order by page_rows.created_at desc, page_rows.id desc
            limit 1
          )
          else null
        end
      )
    )
  end
  from gate;
$fn$;

revoke all on function private.admin_list_subscribers_payload(text, text, timestamptz, uuid, integer)
  from public, anon, authenticated;

create function private.admin_get_subscriber_payload(p_shop_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  with gate as (
    select private.admin_subscriber_gate() as reason
  )
  select case
    when gate.reason <> 'ok' then pg_catalog.jsonb_build_object('error', gate.reason)
    else coalesce((
      select pg_catalog.jsonb_build_object(
        'snapshot_at', pg_catalog.now(),
        'shop_id', shop.id,
        'shop_name', shop.name,
        'registered_at', shop.created_at,
        'entitlement_starts_at', entitlement.starts_at,
        'entitlement_expires_at', entitlement.expires_at,
        'subscription_status', case
          when entitlement.shop_id is null
            or pg_catalog.now() < entitlement.starts_at then 'pending'
          when entitlement.starts_at <= pg_catalog.now()
            and pg_catalog.now() < entitlement.expires_at then 'active'
          else 'expired'
        end
      )
      from public.shops as shop
      left join public.shop_entitlements as entitlement
        on entitlement.shop_id = shop.id
      where shop.id = p_shop_id
    ), pg_catalog.jsonb_build_object('error', 'not_found'))
  end
  from gate;
$fn$;

revoke all on function private.admin_get_subscriber_payload(uuid)
  from public, anon, authenticated;

create function public.admin_list_subscribers_v1(
  p_status text default 'all',
  p_search text default '',
  p_cursor text default null,
  p_page_size integer default 20
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_status text := coalesce(p_status, 'all');
  v_search text := coalesce(pg_catalog.btrim(p_search), '');
  v_size integer := coalesce(p_page_size, 20);
  v_cursor text := nullif(pg_catalog.btrim(p_cursor), '');
  v_at timestamptz;
  v_id uuid;
  v_result jsonb;
  v_error text;
begin
  if v_status not in ('all', 'pending', 'active', 'expired') then
    raise exception 'invalid_status' using errcode = '22023';
  end if;
  if pg_catalog.char_length(v_search) > 120 or v_search ~ '[[:cntrl:]]' then
    raise exception 'invalid_search' using errcode = '22023';
  end if;
  if v_size < 1 or v_size > 25 then
    raise exception 'invalid_page_size' using errcode = '22023';
  end if;
  if v_cursor is not null then
    -- v1| + YYYY-MM-DD HH24:MI:SS.US + | + uuid = 66 characters, three fields.
    if pg_catalog.char_length(v_cursor) <> 66
      or pg_catalog.array_length(pg_catalog.string_to_array(v_cursor, '|'), 1) is distinct from 3
      or pg_catalog.split_part(v_cursor, '|', 1) <> 'v1'
      or pg_catalog.split_part(v_cursor, '|', 2) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}$'
      or pg_catalog.split_part(v_cursor, '|', 3) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      raise exception 'invalid_cursor' using errcode = '22023';
    end if;
    begin
      v_at := pg_catalog.timezone(
        'UTC',
        pg_catalog.split_part(v_cursor, '|', 2)::timestamp
      );
      v_id := pg_catalog.split_part(v_cursor, '|', 3)::uuid;
    exception
      when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
        raise exception 'invalid_cursor' using errcode = '22023';
    end;
  end if;
  v_result := private.admin_list_subscribers_payload(v_status, v_search, v_at, v_id, v_size);
  v_error := v_result->>'error';
  if v_error is not null then
    if v_error in ('unauthenticated', 'forbidden', 'session_expired') then
      raise exception '%', v_error using errcode = '42501';
    end if;
    raise exception '%', v_error using errcode = '22023';
  end if;
  return v_result;
end;
$fn$;

create function public.admin_get_subscriber_v1(p_shop_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_error text;
begin
  if p_shop_id is null then
    raise exception 'invalid_shop' using errcode = '22023';
  end if;
  v_result := private.admin_get_subscriber_payload(p_shop_id);
  v_error := v_result->>'error';
  if v_error is not null then
    if v_error in ('unauthenticated', 'forbidden', 'session_expired') then
      raise exception '%', v_error using errcode = '42501';
    end if;
    raise exception '%', v_error using errcode = '22023';
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.admin_list_subscribers_v1(text, text, text, integer)
  from public, anon, authenticated;
revoke all on function public.admin_get_subscriber_v1(uuid)
  from public, anon, authenticated;
grant execute on function public.admin_list_subscribers_v1(text, text, text, integer)
  to authenticated;
grant execute on function public.admin_get_subscriber_v1(uuid)
  to authenticated;

comment on function public.admin_list_subscribers_v1(text, text, text, integer) is
  'Platform-admin subscriber page. Each call is one snapshot and a keyset cursor. Later pages are separate snapshots. Shop contact and financial fields are not selected.';
comment on function public.admin_get_subscriber_v1(uuid) is
  'Platform-admin subscription detail for one shop. Same allowlist and status rule as the directory page.';

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function private.admin_subscriber_gate() from service_role';
    execute 'revoke all on function private.admin_list_subscribers_payload(text, text, timestamptz, uuid, integer) from service_role';
    execute 'revoke all on function private.admin_get_subscriber_payload(uuid) from service_role';
    execute 'revoke all on function public.admin_list_subscribers_v1(text, text, text, integer) from service_role';
    execute 'revoke all on function public.admin_get_subscriber_v1(uuid) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

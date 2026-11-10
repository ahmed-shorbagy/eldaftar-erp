-- Admin overview (Phase 2 of the admin completion plan, ADR 0045).
-- One platform-admin read returns every overview figure from one statement
-- snapshot: subscription counts with the ADM-01 status rule, active shops
-- whose term ends within rolling 3/7/30-day windows, rolling 7/30-day
-- registrations, open support inquiries by status, per-platform forced-update
-- minimums and whether an announcement is published. Counts travel as exact
-- decimal strings. No shop names, ids, contact, location, Auth, financial,
-- media or audit columns are selected.
-- The directory gains matching expiring_3/expiring_7/expiring_30 status
-- filters so each overview figure can open the list behind it. Existing
-- filters, ordering, cursors and response fields are unchanged.
begin;

create function private.admin_overview_payload()
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
    else (
      with classified as (
        select
          shop.created_at,
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
      shop_figures as (
        select
          count(*)::text as all_count,
          count(*) filter (where subscription_status = 'active')::text as active_count,
          count(*) filter (where subscription_status = 'pending')::text as pending_count,
          count(*) filter (where subscription_status = 'expired')::text as expired_count,
          count(*) filter (
            where subscription_status = 'active'
              and expires_at <= pg_catalog.now() + interval '3 days'
          )::text as expiring_3,
          count(*) filter (
            where subscription_status = 'active'
              and expires_at <= pg_catalog.now() + interval '7 days'
          )::text as expiring_7,
          count(*) filter (
            where subscription_status = 'active'
              and expires_at <= pg_catalog.now() + interval '30 days'
          )::text as expiring_30,
          count(*) filter (
            where created_at > pg_catalog.now() - interval '7 days'
              and created_at <= pg_catalog.now()
          )::text as registered_7,
          count(*) filter (
            where created_at > pg_catalog.now() - interval '30 days'
              and created_at <= pg_catalog.now()
          )::text as registered_30
        from classified
      ),
      support_figures as (
        select
          count(*) filter (where status = 'new')::text as new_count,
          count(*) filter (where status = 'in_progress')::text as in_progress_count,
          count(*) filter (where status = 'answered')::text as answered_count
        from public.support_inquiries
      )
      select pg_catalog.jsonb_build_object(
        'snapshot_at', pg_catalog.now(),
        'subscriptions', pg_catalog.jsonb_build_object(
          'all', shop_figures.all_count,
          'active', shop_figures.active_count,
          'pending', shop_figures.pending_count,
          'expired', shop_figures.expired_count
        ),
        'expiring', pg_catalog.jsonb_build_object(
          'within_3_days', shop_figures.expiring_3,
          'within_7_days', shop_figures.expiring_7,
          'within_30_days', shop_figures.expiring_30
        ),
        'registrations', pg_catalog.jsonb_build_object(
          'last_7_days', shop_figures.registered_7,
          'last_30_days', shop_figures.registered_30
        ),
        'support', pg_catalog.jsonb_build_object(
          'new', support_figures.new_count,
          'in_progress', support_figures.in_progress_count,
          'answered', support_figures.answered_count
        ),
        'app_versions', (
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'platform', platform.name,
              'min_version', policy.min_version
            )
            order by platform.position
          )
          from (values ('android', 1), ('ios', 2), ('windows', 3)) as platform(name, position)
          left join public.app_version_policies as policy
            on policy.platform = platform.name
        ),
        'announcement_published', coalesce((
          select announcement.published
          from public.platform_announcements as announcement
          where announcement.id = 1
        ), false)
      )
      from shop_figures
      cross join support_figures
    )
  end
  from gate;
$fn$;

revoke all on function private.admin_overview_payload() from public, anon, authenticated;

create function public.admin_get_overview_v1()
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
  v_result := private.admin_overview_payload();
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

revoke all on function public.admin_get_overview_v1() from public, anon, authenticated;
grant execute on function public.admin_get_overview_v1() to authenticated;

comment on function public.admin_get_overview_v1() is
  'Platform-admin overview figures from one snapshot: subscription counts, rolling expiring and registration windows, open support inquiries, forced-update minimums and announcement state. Counts only; no shop rows.';

-- Directory: accept expiring_3/expiring_7/expiring_30 (active shops whose term
-- ends within that many days of the snapshot). Body otherwise identical to
-- 20261022094412_admin_subscriber_directory.sql.
create or replace function private.admin_list_subscribers_payload(
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
      expiring_window as (
        select case p_status
          when 'expiring_3' then interval '3 days'
          when 'expiring_7' then interval '7 days'
          when 'expiring_30' then interval '30 days'
          else null
        end as span
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
        cross join expiring_window
        where (
            p_status = 'all'
            or classified.subscription_status = p_status
            or (
              expiring_window.span is not null
              and classified.subscription_status = 'active'
              and classified.expires_at <= pg_catalog.now() + expiring_window.span
            )
          )
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

create or replace function public.admin_list_subscribers_v1(
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
  if v_status not in (
    'all', 'pending', 'active', 'expired', 'expiring_3', 'expiring_7', 'expiring_30'
  ) then
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

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function private.admin_overview_payload() from service_role';
    execute 'revoke all on function public.admin_get_overview_v1() from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

-- ADM-02 code revocation and history v2 (ADR 0048).
-- An admin may revoke an unused, unexpired code with a reason. Revocation
-- marks the row and ends code validity at the revocation time, so the
-- unchanged redeem_subscription_code rejects it as expired_code. Entitlements
-- are never touched. issue/redeem and history v1 keep their bodies.
begin;

alter table private.subscription_codes
  add column revoked_at timestamptz,
  add column revoked_by uuid,
  add column revoke_reason text,
  add column revoke_request_key uuid unique;

alter table private.subscription_codes
  add constraint subscription_codes_revoked_set check (
    (revoked_at is null and revoked_by is null and revoke_reason is null and revoke_request_key is null)
    or (revoked_at is not null and revoked_by is not null and revoke_reason is not null and revoke_request_key is not null)
  ),
  add constraint subscription_codes_revoke_reason_len check (
    revoke_reason is null or char_length(revoke_reason) between 3 and 200
  ),
  add constraint subscription_codes_not_revoked_and_redeemed check (
    revoked_at is null or redeemed_at is null
  );

create function public.admin_revoke_subscription_code_v1(
  p_code_id uuid,
  p_reason text,
  p_request_key uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_admin uuid;
  v_reason text;
  v_row private.subscription_codes%rowtype;
  v_prior private.subscription_codes%rowtype;
  v_now timestamptz;
begin
  if not private.subscription_platform_admin_session() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_admin := auth.uid();
  v_reason := pg_catalog.btrim(coalesce(p_reason, ''));
  if p_code_id is null
    or p_request_key is null
    or p_request_key::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    or pg_catalog.char_length(v_reason) not between 3 and 200
    or v_reason ~ '[[:cntrl:]]' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(840276, hashtext(p_request_key::text));

  select * into v_row
  from private.subscription_codes as code_row
  where code_row.id = p_code_id
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  v_now := pg_catalog.clock_timestamp();

  if not private.subscription_platform_admin_session()
    or auth.uid() is distinct from v_admin
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select * into v_prior
  from private.subscription_codes as prior
  where prior.revoke_request_key = p_request_key;
  if found then
    if v_prior.id <> p_code_id or v_prior.revoke_reason <> v_reason then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return pg_catalog.jsonb_build_object(
      'status', 'replayed',
      'code_id', v_prior.id,
      'shop_id', v_prior.shop_id,
      'revoked_at', v_prior.revoked_at
    );
  end if;

  if v_row.revoked_at is not null then
    return pg_catalog.jsonb_build_object(
      'status', 'already_revoked', 'code_id', v_row.id, 'shop_id', v_row.shop_id, 'revoked_at', v_row.revoked_at
    );
  end if;
  if v_row.redeemed_at is not null then
    return pg_catalog.jsonb_build_object(
      'status', 'redeemed', 'code_id', v_row.id, 'shop_id', v_row.shop_id, 'revoked_at', null
    );
  end if;
  if v_row.code_expires_at <= v_now then
    return pg_catalog.jsonb_build_object(
      'status', 'expired', 'code_id', v_row.id, 'shop_id', v_row.shop_id, 'revoked_at', null
    );
  end if;

  update private.subscription_codes
    set revoked_at = v_now,
        revoked_by = v_admin,
        revoke_reason = v_reason,
        revoke_request_key = p_request_key,
        code_expires_at = v_now
    where id = v_row.id;

  insert into private.subscription_code_events (
    shop_id, actor_user_id, action, correlation_id, details
  ) values (
    v_row.shop_id,
    v_admin,
    'subscription_code_revoked',
    p_request_key,
    pg_catalog.jsonb_build_object(
      'code_id', v_row.id,
      'duration_days', v_row.duration_days,
      'original_code_expires_at', v_row.code_expires_at,
      'reason', v_reason
    )
  );

  return pg_catalog.jsonb_build_object(
    'status', 'revoked', 'code_id', v_row.id, 'shop_id', v_row.shop_id, 'revoked_at', v_now
  );
end;
$fn$;

revoke all on function public.admin_revoke_subscription_code_v1(uuid, text, uuid) from public, anon, authenticated;
grant execute on function public.admin_revoke_subscription_code_v1(uuid, text, uuid) to authenticated;

comment on function public.admin_revoke_subscription_code_v1(uuid, text, uuid) is
  'Platform-admin revocation of one unused, unexpired subscription code with a reason. Idempotent by request key. Never changes an entitlement.';

-- History v2: v1 plus revoked_at / revoke_reason and a revoked status.
create function private.admin_list_subscription_codes_v2_payload(
  p_shop_id uuid,
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
    when not exists (
      select 1 from public.shops as shop where shop.id = p_shop_id
    ) then pg_catalog.jsonb_build_object('error', 'not_found')
    when p_cursor_id is not null and not exists (
      select 1
      from private.subscription_codes as cursor_row
      where cursor_row.id = p_cursor_id
        and cursor_row.shop_id = p_shop_id
        and cursor_row.issued_at = p_cursor_at
    ) then pg_catalog.jsonb_build_object('error', 'stale_cursor')
    else (
      with shop_row as (
        select shop.id, shop.name
        from public.shops as shop
        where shop.id = p_shop_id
      ),
      classified as (
        select
          code_row.id,
          code_row.issued_at,
          code_row.duration_days,
          code_row.code_ttl_days,
          code_row.code_expires_at,
          code_row.issued_via,
          code_row.redeemed_at,
          code_row.revoked_at,
          code_row.revoke_reason,
          case
            when code_row.redeemed_at is not null then 'redeemed'
            when code_row.revoked_at is not null then 'revoked'
            when code_row.code_expires_at <= pg_catalog.now() then 'expired'
            else 'unused'
          end as code_status
        from private.subscription_codes as code_row
        where code_row.shop_id = p_shop_id
      ),
      window_rows as (
        select classified.*
        from classified
        where p_cursor_id is null
          or (classified.issued_at, classified.id) < (p_cursor_at, p_cursor_id)
        order by classified.issued_at desc, classified.id desc
        limit (p_page_size + 1)
      ),
      page_rows as (
        select window_rows.*
        from window_rows
        order by window_rows.issued_at desc, window_rows.id desc
        limit p_page_size
      )
      select pg_catalog.jsonb_build_object(
        'snapshot_at', pg_catalog.now(),
        'shop_id', (select id from shop_row),
        'shop_name', (select name from shop_row),
        'row_count', (select count(*)::text from classified),
        'page_size', p_page_size,
        'rows', coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'id', page_rows.id,
              'issued_at', page_rows.issued_at,
              'duration_days', page_rows.duration_days,
              'code_ttl_days', page_rows.code_ttl_days,
              'code_expires_at', page_rows.code_expires_at,
              'issued_via', page_rows.issued_via,
              'code_status', page_rows.code_status,
              'redeemed_at', page_rows.redeemed_at,
              'revoked_at', page_rows.revoked_at,
              'revoke_reason', page_rows.revoke_reason
            )
            order by page_rows.issued_at desc, page_rows.id desc
          )
          from page_rows
        ), '[]'::jsonb),
        'next_cursor', case
          when (select count(*) from window_rows) > p_page_size then (
            select 'v1|'
              || pg_catalog.to_char(
                page_rows.issued_at at time zone 'UTC',
                'YYYY-MM-DD HH24:MI:SS.US'
              )
              || '|'
              || page_rows.id::text
            from page_rows
            order by page_rows.issued_at asc, page_rows.id asc
            limit 1
          )
          else null
        end
      )
    )
  end
  from gate;
$fn$;

revoke all on function private.admin_list_subscription_codes_v2_payload(uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;

create function public.admin_list_subscription_codes_v2(
  p_shop_id uuid,
  p_cursor text default null,
  p_page_size integer default 20
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_size integer := coalesce(p_page_size, 20);
  v_cursor text := nullif(pg_catalog.btrim(p_cursor), '');
  v_at timestamptz;
  v_id uuid;
  v_result jsonb;
  v_error text;
begin
  if p_shop_id is null then
    raise exception 'invalid_shop' using errcode = '22023';
  end if;
  if v_size < 1 or v_size > 25 then
    raise exception 'invalid_page_size' using errcode = '22023';
  end if;
  if v_cursor is not null then
    if pg_catalog.char_length(v_cursor) <> 66
      or pg_catalog.array_length(pg_catalog.string_to_array(v_cursor, '|'), 1) is distinct from 3
      or pg_catalog.split_part(v_cursor, '|', 1) <> 'v1'
      or pg_catalog.split_part(v_cursor, '|', 2) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}$'
      or pg_catalog.split_part(v_cursor, '|', 3) !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' then
      raise exception 'invalid_cursor' using errcode = '22023';
    end if;
    begin
      v_at := pg_catalog.timezone('UTC', pg_catalog.split_part(v_cursor, '|', 2)::timestamp);
      v_id := pg_catalog.split_part(v_cursor, '|', 3)::uuid;
    exception
      when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
        raise exception 'invalid_cursor' using errcode = '22023';
    end;
  end if;
  v_result := private.admin_list_subscription_codes_v2_payload(p_shop_id, v_at, v_id, v_size);
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

revoke all on function public.admin_list_subscription_codes_v2(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.admin_list_subscription_codes_v2(uuid, text, integer)
  to authenticated;

comment on function public.admin_list_subscription_codes_v2(uuid, text, integer) is
  'Platform-admin code history for one shop (v1 shape plus revoked_at, revoke_reason and a revoked status). Raw codes, hashes and owner identity are not selected.';

-- Audit read: include code revocations in the codes family.
create or replace function private.admin_list_audit_events_payload(
  p_family text,
  p_actor uuid,
  p_cursor_at timestamptz,
  p_cursor_key text,
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
    else (
      with events as (
        select
          'code:' || code_event.id::text as event_key,
          code_event.created_at as occurred_at,
          'codes'::text as family,
          code_event.action,
          code_event.actor_user_id,
          code_event.shop_id,
          case code_event.action
            when 'subscription_code_issued' then pg_catalog.jsonb_build_object(
              'duration_days', code_event.details->'duration_days',
              'code_expires_at', code_event.details->'code_expires_at',
              'issued_via', code_event.details->'issued_via'
            )
            else pg_catalog.jsonb_build_object(
              'duration_days', code_event.details->'duration_days',
              'reason', pg_catalog.left(code_event.details->>'reason', 120)
            )
          end as details
        from private.subscription_code_events as code_event
        where code_event.action in ('subscription_code_issued', 'subscription_code_revoked')
        union all
        select
          'contact:' || reveal.id::text,
          reveal.revealed_at,
          'contact',
          'subscriber_contact_revealed',
          reveal.admin_user_id,
          reveal.shop_id,
          '{}'::jsonb
        from public.admin_subscriber_contact_reveals as reveal
        union all
        select
          'support:' || status_event.id::text,
          status_event.created_at,
          'support',
          'support_status_changed',
          status_event.actor_user_id,
          inquiry.shop_id,
          pg_catalog.jsonb_build_object(
            'from_status', status_event.from_status,
            'to_status', status_event.to_status
          )
        from public.support_inquiry_events as status_event
        join public.support_inquiries as inquiry
          on inquiry.id = status_event.inquiry_id
        where status_event.from_status is not null
        union all
        select
          'platform:' || platform_event.id::text,
          platform_event.occurred_at,
          platform_event.family,
          platform_event.action,
          platform_event.actor_user_id,
          null::uuid,
          platform_event.details
        from public.platform_admin_audit_events as platform_event
      ),
      filtered as (
        select events.*
        from events
        where (p_family = 'all' or events.family = p_family)
          and (p_actor is null or events.actor_user_id = p_actor)
      ),
      window_rows as (
        select filtered.*
        from filtered
        where p_cursor_key is null
          or (filtered.occurred_at, filtered.event_key) < (p_cursor_at, p_cursor_key)
        order by filtered.occurred_at desc, filtered.event_key desc
        limit (p_page_size + 1)
      ),
      page_rows as (
        select window_rows.*
        from window_rows
        order by window_rows.occurred_at desc, window_rows.event_key desc
        limit p_page_size
      )
      select pg_catalog.jsonb_build_object(
        'snapshot_at', pg_catalog.now(),
        'page_size', p_page_size,
        'rows', coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object(
              'event_key', page_rows.event_key,
              'occurred_at', page_rows.occurred_at,
              'family', page_rows.family,
              'action', page_rows.action,
              'actor_user_id', page_rows.actor_user_id,
              'actor_email', actor.email,
              'shop_id', page_rows.shop_id,
              'shop_name', shop.name,
              'details', page_rows.details
            )
            order by page_rows.occurred_at desc, page_rows.event_key desc
          )
          from page_rows
          left join auth.users as actor on actor.id = page_rows.actor_user_id
          left join public.shops as shop on shop.id = page_rows.shop_id
        ), '[]'::jsonb),
        'next_cursor', case
          when (select count(*) from window_rows) > p_page_size then (
            select 'v1|'
              || pg_catalog.to_char(
                page_rows.occurred_at at time zone 'UTC',
                'YYYY-MM-DD HH24:MI:SS.US'
              )
              || '|'
              || page_rows.event_key
            from page_rows
            order by page_rows.occurred_at asc, page_rows.event_key asc
            limit 1
          )
          else null
        end,
        'admins', coalesce((
          select pg_catalog.jsonb_agg(
            pg_catalog.jsonb_build_object('user_id', admin_user.id, 'email', admin_user.email)
            order by admin_user.email, admin_user.id
          )
          from public.platform_admins as platform_admin
          join auth.users as admin_user on admin_user.id = platform_admin.user_id
        ), '[]'::jsonb)
      )
    )
  end
  from gate;
$fn$;

revoke all on function private.admin_list_audit_events_payload(text, uuid, timestamptz, text, integer)
  from public, anon, authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.admin_revoke_subscription_code_v1(uuid, text, uuid) from service_role';
    execute 'revoke all on function private.admin_list_subscription_codes_v2_payload(uuid, timestamptz, uuid, integer) from service_role';
    execute 'revoke all on function public.admin_list_subscription_codes_v2(uuid, text, integer) from service_role';
    execute 'revoke all on function private.admin_list_audit_events_payload(text, uuid, timestamptz, text, integer) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

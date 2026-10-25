-- ADM-02/ADM-08 admin subscription-code issuance and selected-shop history.
-- Reuses public.issue_subscription_code and public.redeem_subscription_code.
-- Adds a narrow metadata history RPC. No table grants, no parallel
-- activation system, no revocation or entitlement editing.
begin;

create index if not exists subscription_codes_shop_issued_id_idx
  on private.subscription_codes (shop_id, issued_at, id);

comment on index private.subscription_codes_shop_issued_id_idx is
  'Keyset order for platform-admin subscription-code history of one shop: issued time, then row id.';

create or replace function private.subscription_platform_admin_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select public.is_platform_admin()
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
        and (
          identity.banned_until is null
          or identity.banned_until <= pg_catalog.now()
        )
    );
$fn$;

revoke all on function private.subscription_platform_admin_session() from public, anon, authenticated;

create function private.subscription_owner_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select auth.uid() is not null
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
        and (
          identity.banned_until is null
          or identity.banned_until <= pg_catalog.now()
        )
    );
$fn$;

revoke all on function private.subscription_owner_session() from public, anon, authenticated;

-- Post-lock current-clock check. caller_session_accepted()/now() is the
-- transaction start time, so a session can expire while a row lock is held.
-- Missing session_id claim stays accepted for legacy SQL fixtures.
create function private.subscription_session_live()
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_raw text;
  v_session uuid;
begin
  v_raw := nullif(pg_catalog.btrim(pg_catalog.current_setting('request.jwt.claim.session_id', true)), '');
  if v_raw is null then
    begin
      v_raw := nullif(pg_catalog.btrim(
        nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'session_id'
      ), '');
    exception
      when others then
        return false;
    end;
  end if;

  if auth.uid() is not null
    and not exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
        and (
          identity.banned_until is null
          or identity.banned_until <= pg_catalog.clock_timestamp()
        )
    ) then
    return false;
  end if;

  if v_raw is null then
    return true;
  end if;

  begin
    v_session := v_raw::uuid;
  exception
    when invalid_text_representation then
      return false;
  end;

  if auth.uid() is null then
    return false;
  end if;

  return exists (
    select 1
    from auth.sessions as session_row
    where session_row.id = v_session
      and session_row.user_id = auth.uid()
      and (
        session_row.not_after is null
        or session_row.not_after > pg_catalog.clock_timestamp()
      )
  );
end;
$fn$;

revoke all on function private.subscription_session_live() from public, anon, authenticated;

create or replace function public.issue_subscription_code(
  p_shop_id uuid,
  p_duration_days integer,
  p_code_ttl_days integer default 30,
  p_request_key uuid default null
)
returns table (
  code text,
  shop_id uuid,
  owner_user_id uuid,
  duration_days integer,
  code_expires_at timestamptz,
  status text,
  request_key uuid,
  issued_via text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner uuid;
  v_owner_after uuid;
  v_code text;
  v_hash bytea;
  v_ttl integer;
  v_expires timestamptz;
  v_issued_by uuid;
  v_issued_via text;
  v_request uuid;
  v_existing private.subscription_codes%rowtype;
  v_now timestamptz;
  v_prior_found boolean;
begin
  if private.subscription_caller_is_service_role() then
    v_issued_via := 'service_role';
    v_issued_by := null;
  elsif private.subscription_platform_admin_session() then
    v_issued_via := 'platform_admin';
    v_issued_by := auth.uid();
  else
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_shop_id is null
    or p_duration_days is null
    or p_duration_days not between 1 and 3660 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_ttl := coalesce(p_code_ttl_days, 30);
  if v_ttl not between 1 and 365 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if p_request_key is null
    or p_request_key::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_request := p_request_key;

  select ownership.user_id into v_owner
  from public.shop_memberships as ownership
  where ownership.shop_id = p_shop_id
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_owner is null then
    raise exception 'shop_not_found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(840274, hashtext(v_request::text));
  perform pg_advisory_xact_lock(840275, hashtext(p_shop_id::text));
  v_now := clock_timestamp();

  if v_issued_via = 'service_role' then
    if not private.subscription_caller_is_service_role() then
      raise exception 'unauthorized' using errcode = '42501';
    end if;
  elsif not private.subscription_platform_admin_session()
    or auth.uid() is distinct from v_issued_by
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select ownership.user_id into v_owner_after
  from public.shop_memberships as ownership
  where ownership.shop_id = p_shop_id
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_owner_after is null or v_owner_after is distinct from v_owner then
    raise exception 'shop_not_found' using errcode = 'P0002';
  end if;

  select * into v_existing
  from private.subscription_codes as prior
  where prior.issue_request_key = v_request
  for update;
  v_prior_found := found;
  v_now := clock_timestamp();

  if v_issued_via = 'service_role' then
    if not private.subscription_caller_is_service_role() then
      raise exception 'unauthorized' using errcode = '42501';
    end if;
  elsif not private.subscription_platform_admin_session()
    or auth.uid() is distinct from v_issued_by
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select ownership.user_id into v_owner_after
  from public.shop_memberships as ownership
  where ownership.shop_id = p_shop_id
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_owner_after is null or v_owner_after is distinct from v_owner then
    raise exception 'shop_not_found' using errcode = 'P0002';
  end if;

  if v_prior_found then
    if v_existing.shop_id <> p_shop_id
      or v_existing.duration_days <> p_duration_days
      or v_existing.code_ttl_days <> v_ttl
      or v_existing.owner_user_id <> v_owner then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    -- Retry confirms the prior issuance. The raw code is never stored.
    return query
    select
      null::text,
      v_existing.shop_id,
      v_existing.owner_user_id,
      v_existing.duration_days,
      v_existing.code_expires_at,
      'replayed'::text,
      v_existing.issue_request_key,
      v_existing.issued_via;
    return;
  end if;

  v_code := upper(encode(extensions.gen_random_bytes(16), 'hex'));
  v_hash := private.subscription_code_hash(v_code);
  v_expires := v_now + make_interval(days => v_ttl);

  insert into private.subscription_codes (
    code_hash,
    shop_id,
    owner_user_id,
    duration_days,
    code_expires_at,
    issued_at,
    issued_by,
    issued_via,
    issue_request_key,
    code_ttl_days
  ) values (
    v_hash,
    p_shop_id,
    v_owner,
    p_duration_days,
    v_expires,
    v_now,
    v_issued_by,
    v_issued_via,
    v_request,
    v_ttl
  );

  insert into private.subscription_code_events (
    shop_id,
    actor_user_id,
    action,
    correlation_id,
    details
  ) values (
    p_shop_id,
    v_issued_by,
    'subscription_code_issued',
    v_request,
    jsonb_build_object(
      'duration_days', p_duration_days,
      'code_expires_at', v_expires,
      'issued_via', v_issued_via
    )
  );

  return query
  select
    v_code,
    p_shop_id,
    v_owner,
    p_duration_days,
    v_expires,
    'issued'::text,
    v_request,
    v_issued_via;
end;
$function$;

revoke all on function public.issue_subscription_code(uuid, integer, integer, uuid) from public, anon;
grant execute on function public.issue_subscription_code(uuid, integer, integer, uuid) to authenticated, service_role;

create or replace function public.redeem_subscription_code(
  p_request_key uuid,
  p_code text
)
returns table (
  shop_id uuid,
  starts_at timestamptz,
  expires_at timestamptz,
  status text
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user uuid;
  v_shop uuid;
  v_shop_after uuid;
  v_code text;
  v_hash bytea;
  v_existing private.subscription_redemption_requests%rowtype;
  v_row private.subscription_codes%rowtype;
  v_failures integer;
  v_now timestamptz;
  v_starts timestamptz;
  v_expires timestamptz;
  v_entitlement public.shop_entitlements%rowtype;
  v_prior_found boolean;
  v_code_found boolean;
  v_entitlement_found boolean;
begin
  v_user := auth.uid();
  if v_user is null or not private.subscription_owner_session() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if p_request_key is null
    or p_request_key::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select ownership.shop_id into v_shop
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(840271, hashtext(v_user::text));
  perform pg_advisory_xact_lock(840272, hashtext(p_request_key::text));
  v_now := clock_timestamp();

  if auth.uid() is distinct from v_user
    or not private.subscription_owner_session()
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select ownership.shop_id into v_shop_after
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop_after is null or v_shop_after is distinct from v_shop then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select * into v_existing
  from private.subscription_redemption_requests as prior
  where prior.request_key = p_request_key
  for update;
  v_prior_found := found;

  if auth.uid() is distinct from v_user
    or not private.subscription_owner_session()
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select ownership.shop_id into v_shop_after
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop_after is null or v_shop_after is distinct from v_shop then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if v_prior_found then
    v_code := private.normalize_subscription_code(p_code);
    v_hash := case
      when v_code is null then null
      else private.subscription_code_hash(v_code)
    end;
    if v_existing.owner_user_id <> v_user
      or v_existing.shop_id <> v_shop
      or v_hash is null
      or v_existing.code_hash <> v_hash then
      return query
      select null::uuid, null::timestamptz, null::timestamptz, 'request_key_reused'::text;
      return;
    end if;
    return query
    select v_existing.shop_id, v_existing.starts_at, v_existing.expires_at, 'replayed'::text;
    return;
  end if;

  select count(*) into v_failures
  from private.subscription_code_attempts as attempt
  where attempt.user_id = v_user
    and attempt.accepted = false
    and attempt.attempted_at > v_now - interval '15 minutes';
  if v_failures >= 8 then
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  v_code := private.normalize_subscription_code(p_code);
  if v_code is null then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'invalid_code'::text;
    return;
  end if;
  v_hash := private.subscription_code_hash(v_code);
  perform pg_advisory_xact_lock(840273, hashtext(encode(v_hash, 'hex')));
  v_now := clock_timestamp();

  if auth.uid() is distinct from v_user
    or not private.subscription_owner_session()
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select ownership.shop_id into v_shop_after
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop_after is null or v_shop_after is distinct from v_shop then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select count(*) into v_failures
  from private.subscription_code_attempts as attempt
  where attempt.user_id = v_user
    and attempt.accepted = false
    and attempt.attempted_at > v_now - interval '15 minutes';
  if v_failures >= 8 then
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'rate_limited'::text;
    return;
  end if;

  select * into v_row
  from private.subscription_codes as code_row
  where code_row.code_hash = v_hash
  for update;
  v_code_found := found;
  v_now := clock_timestamp();

  if auth.uid() is distinct from v_user
    or not private.subscription_owner_session()
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select ownership.shop_id into v_shop_after
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop_after is null or v_shop_after is distinct from v_shop then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if not v_code_found then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'invalid_code'::text;
    return;
  end if;

  if v_row.owner_user_id <> v_user or v_row.shop_id <> v_shop then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'foreign_owner'::text;
    return;
  end if;

  if v_row.redeemed_at is not null then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'reused_code'::text;
    return;
  end if;

  if v_row.code_expires_at <= v_now then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'expired_code'::text;
    return;
  end if;

  select * into v_entitlement
  from public.shop_entitlements as entitlement
  where entitlement.shop_id = v_shop
  for update;
  v_entitlement_found := found;
  v_now := clock_timestamp();

  if auth.uid() is distinct from v_user
    or not private.subscription_owner_session()
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select ownership.shop_id into v_shop_after
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop_after is null or v_shop_after is distinct from v_shop then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if v_row.code_expires_at <= v_now then
    insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
    values (v_user, v_now, false);
    return query
    select null::uuid, null::timestamptz, null::timestamptz, 'expired_code'::text;
    return;
  end if;

  if not v_entitlement_found then
    v_starts := v_now;
    v_expires := v_now + make_interval(days => v_row.duration_days);
    insert into public.shop_entitlements (shop_id, starts_at, expires_at)
    values (v_shop, v_starts, v_expires);
  elsif v_now < v_entitlement.expires_at and v_now >= v_entitlement.starts_at then
    v_starts := v_entitlement.starts_at;
    v_expires := v_entitlement.expires_at + make_interval(days => v_row.duration_days);
    update public.shop_entitlements as entitlement
      set expires_at = v_expires
      where entitlement.shop_id = v_shop;
  else
    v_starts := v_now;
    v_expires := v_now + make_interval(days => v_row.duration_days);
    update public.shop_entitlements as entitlement
      set starts_at = v_starts,
          expires_at = v_expires
      where entitlement.shop_id = v_shop;
  end if;

  update private.subscription_codes
    set redeemed_at = v_now,
        redeemed_by = v_user,
        redeemed_request_key = p_request_key
    where id = v_row.id;

  insert into private.subscription_redemption_requests (
    request_key,
    owner_user_id,
    shop_id,
    code_hash,
    starts_at,
    expires_at,
    created_at
  ) values (
    p_request_key,
    v_user,
    v_shop,
    v_hash,
    v_starts,
    v_expires,
    v_now
  );

  insert into private.subscription_code_attempts (user_id, attempted_at, accepted)
  values (v_user, v_now, true);

  insert into public.identity_audit_events (
    shop_id,
    actor_user_id,
    action,
    subject_user_id,
    correlation_id,
    details
  ) values (
    v_shop,
    v_user,
    'subscription_redeemed',
    v_user,
    p_request_key,
    jsonb_build_object(
      'duration_days', v_row.duration_days,
      'starts_at', v_starts,
      'expires_at', v_expires
    )
  );

  insert into private.subscription_code_events (
    shop_id,
    actor_user_id,
    action,
    correlation_id,
    details
  ) values (
    v_shop,
    v_user,
    'subscription_code_redeemed',
    p_request_key,
    jsonb_build_object(
      'duration_days', v_row.duration_days,
      'expires_at', v_expires
    )
  );

  return query
  select v_shop, v_starts, v_expires, 'activated'::text;
end;
$function$;

revoke all on function public.redeem_subscription_code(uuid, text) from public, anon;
grant execute on function public.redeem_subscription_code(uuid, text) to authenticated;

create function private.admin_list_subscription_codes_payload(
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
          case
            when code_row.redeemed_at is not null then 'redeemed'
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
              'redeemed_at', page_rows.redeemed_at
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

revoke all on function private.admin_list_subscription_codes_payload(uuid, timestamptz, uuid, integer)
  from public, anon, authenticated;

create function public.admin_list_subscription_codes_v1(
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
  v_result := private.admin_list_subscription_codes_payload(p_shop_id, v_at, v_id, v_size);
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

revoke all on function public.admin_list_subscription_codes_v1(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.admin_list_subscription_codes_v1(uuid, text, integer)
  to authenticated;

comment on function public.admin_list_subscription_codes_v1(uuid, text, integer) is
  'Platform-admin history of hashed subscription codes for one selected shop. Safe metadata only. Raw codes, hashes, owner identity and contact are not selected.';

comment on function public.issue_subscription_code(uuid, integer, integer, uuid) is
  'Issue a hashed single-use subscription code for one shop. Platform-admin or service_role. Issuance does not activate or extend the entitlement.';

comment on function public.redeem_subscription_code(uuid, text) is
  'Owner redemption of a hashed subscription code. Single use, bound to the owner and shop. Replay is confirmed before the invalid-attempt throttle.';

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function private.subscription_platform_admin_session() from service_role';
    execute 'revoke all on function private.subscription_owner_session() from service_role';
    execute 'revoke all on function private.subscription_session_live() from service_role';
    execute 'revoke all on function private.admin_list_subscription_codes_payload(uuid, timestamptz, uuid, integer) from service_role';
    execute 'revoke all on function public.admin_list_subscription_codes_v1(uuid, text, integer) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

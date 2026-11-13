-- ADM-06 subscriber broadcasts (ADR 0048, owner decision D-A3).
-- In-app only. Recipients are shop owners. The recipient list is frozen on
-- the server when the admin confirms the send. Visibility (scheduled start,
-- end date, withdrawal) is computed at read time, so no scheduler is needed.
-- Tables have no client privileges; every read and write is an RPC.
begin;

create table public.platform_broadcasts (
  id uuid primary key default gen_random_uuid(),
  request_key uuid not null unique,
  request_digest text not null,
  created_by uuid not null,
  created_at timestamptz not null default now(),
  segment text not null,
  segment_days integer,
  segment_shop_id uuid references public.shops (id),
  title_ar text not null,
  body_ar text not null,
  link_url text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  recipient_count integer not null,
  withdrawn_at timestamptz,
  withdrawn_by uuid,
  withdraw_reason text,
  constraint platform_broadcasts_segment_check
    check (segment in ('all', 'active', 'pending', 'expired', 'expiring', 'shop')),
  constraint platform_broadcasts_segment_params check (
    (segment = 'expiring' and segment_days between 1 and 90 and segment_shop_id is null)
    or (segment = 'shop' and segment_days is null and segment_shop_id is not null)
    or (segment in ('all', 'active', 'pending', 'expired') and segment_days is null and segment_shop_id is null)
  ),
  constraint platform_broadcasts_title_len check (char_length(title_ar) between 1 and 80),
  constraint platform_broadcasts_body_len check (char_length(body_ar) between 1 and 1000),
  constraint platform_broadcasts_link check (
    link_url is null
    or (char_length(link_url) between 12 and 2048 and lower(link_url) like 'https://%')
  ),
  constraint platform_broadcasts_window check (
    ends_at > starts_at and ends_at <= starts_at + interval '365 days'
  ),
  constraint platform_broadcasts_recipients check (recipient_count >= 1),
  constraint platform_broadcasts_withdrawn_set check (
    (withdrawn_at is null and withdrawn_by is null and withdraw_reason is null)
    or (withdrawn_at is not null and withdrawn_by is not null
      and char_length(withdraw_reason) between 3 and 200)
  )
);

comment on table public.platform_broadcasts is
  'Platform-admin in-app messages to shop owners (ADM-06). Immutable after send except one audited withdrawal. Read and written only through RPCs.';

create index platform_broadcasts_order_idx
  on public.platform_broadcasts (created_at desc, id desc);

create table public.platform_broadcast_recipients (
  broadcast_id uuid not null references public.platform_broadcasts (id),
  shop_id uuid not null references public.shops (id),
  delivered_at timestamptz,
  read_at timestamptz,
  primary key (broadcast_id, shop_id),
  constraint platform_broadcast_recipients_read_after_delivery
    check (read_at is null or delivered_at is not null)
);

comment on table public.platform_broadcast_recipients is
  'Frozen recipient shops of one broadcast with per-shop delivery and read times. Shop ids only.';

create index platform_broadcast_recipients_shop_idx
  on public.platform_broadcast_recipients (shop_id, broadcast_id);

alter table public.platform_broadcasts enable row level security;
alter table public.platform_broadcast_recipients enable row level security;
revoke all on table public.platform_broadcasts from public, anon, authenticated;
revoke all on table public.platform_broadcast_recipients from public, anon, authenticated;

-- A sent message cannot be edited or deleted; only the withdrawal fields
-- may be set once. Recipient rows keep their keys and only gain times.
create function private.platform_broadcasts_immutable()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'broadcast_immutable';
  end if;
  if (old.id, old.request_key, old.request_digest, old.created_by, old.created_at,
      old.segment, old.segment_days, old.segment_shop_id, old.title_ar, old.body_ar,
      old.link_url, old.starts_at, old.ends_at, old.recipient_count)
    is distinct from
     (new.id, new.request_key, new.request_digest, new.created_by, new.created_at,
      new.segment, new.segment_days, new.segment_shop_id, new.title_ar, new.body_ar,
      new.link_url, new.starts_at, new.ends_at, new.recipient_count)
    or (old.withdrawn_at is not null and (old.withdrawn_at, old.withdrawn_by, old.withdraw_reason)
      is distinct from (new.withdrawn_at, new.withdrawn_by, new.withdraw_reason)) then
    raise exception 'broadcast_immutable';
  end if;
  return new;
end;
$fn$;

revoke all on function private.platform_broadcasts_immutable() from public, anon, authenticated;

create trigger platform_broadcasts_immutable
  before update or delete on public.platform_broadcasts
  for each row execute function private.platform_broadcasts_immutable();

create function private.platform_broadcast_recipients_guard()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE'
    or new.broadcast_id is distinct from old.broadcast_id
    or new.shop_id is distinct from old.shop_id
    or (old.delivered_at is not null and new.delivered_at is distinct from old.delivered_at)
    or (old.read_at is not null and new.read_at is distinct from old.read_at) then
    raise exception 'broadcast_recipient_immutable';
  end if;
  return new;
end;
$fn$;

revoke all on function private.platform_broadcast_recipients_guard() from public, anon, authenticated;

create trigger platform_broadcast_recipients_guard
  before update or delete on public.platform_broadcast_recipients
  for each row execute function private.platform_broadcast_recipients_guard();

-- Audit families/actions for broadcasts.
alter table public.platform_admin_audit_events
  drop constraint platform_admin_audit_events_family_check,
  drop constraint platform_admin_audit_events_action_check;
alter table public.platform_admin_audit_events
  add constraint platform_admin_audit_events_family_check
    check (family in ('app_version', 'help', 'announcement', 'broadcast')),
  add constraint platform_admin_audit_events_action_check check (action in (
    'app_version_set', 'app_version_cleared',
    'help_topic_created', 'help_topic_updated', 'help_topic_deleted',
    'help_article_created', 'help_article_updated', 'help_article_deleted',
    'announcement_published', 'announcement_updated', 'announcement_cleared',
    'broadcast_sent', 'broadcast_withdrawn'
  ));

-- Audience ---------------------------------------------------------------------
-- Same pending/active/expired rule as the directory (ADR 0027), at p_now.
create function private.broadcast_audience(
  p_segment text,
  p_days integer,
  p_shop_id uuid,
  p_now timestamptz
) returns table (shop_id uuid)
language sql
stable
security definer
set search_path = ''
as $fn$
  select shop.id
  from public.shops as shop
  left join public.shop_entitlements as entitlement
    on entitlement.shop_id = shop.id
  cross join lateral (
    select case
      when entitlement.shop_id is null or p_now < entitlement.starts_at then 'pending'
      when entitlement.starts_at <= p_now and p_now < entitlement.expires_at then 'active'
      else 'expired'
    end as subscription_status
  ) as classified
  where exists (
      select 1
      from public.shop_memberships as ownership
      where ownership.shop_id = shop.id
        and ownership.role = 'owner'
        and ownership.revoked_at is null
    )
    and case p_segment
      when 'all' then true
      when 'shop' then shop.id = p_shop_id
      when 'expiring' then classified.subscription_status = 'active'
        and entitlement.expires_at <= p_now + pg_catalog.make_interval(days => p_days)
      else classified.subscription_status = p_segment
    end;
$fn$;

revoke all on function private.broadcast_audience(text, integer, uuid, timestamptz)
  from public, anon, authenticated;

create function private.broadcast_check_segment(
  p_segment text,
  p_days integer,
  p_shop_id uuid
) returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if p_segment is null
    or p_segment not in ('all', 'active', 'pending', 'expired', 'expiring', 'shop')
    or (p_segment = 'expiring' and (p_days is null or p_days not between 1 and 90 or p_shop_id is not null))
    or (p_segment = 'shop' and (p_shop_id is null or p_days is not null))
    or (p_segment in ('all', 'active', 'pending', 'expired') and (p_days is not null or p_shop_id is not null)) then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if p_segment = 'shop' and not exists (select 1 from public.shops where id = p_shop_id) then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
end;
$fn$;

revoke all on function private.broadcast_check_segment(text, integer, uuid)
  from public, anon, authenticated;

create function private.broadcast_admin_gate()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_gate text := private.admin_subscriber_gate();
begin
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;
end;
$fn$;

revoke all on function private.broadcast_admin_gate() from public, anon, authenticated;

create function public.admin_preview_broadcast_audience_v1(
  p_segment text,
  p_days integer default null,
  p_shop_id uuid default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  perform private.broadcast_admin_gate();
  perform private.broadcast_check_segment(p_segment, p_days, p_shop_id);
  return pg_catalog.jsonb_build_object(
    'snapshot_at', pg_catalog.now(),
    'recipient_count', (
      select count(*)::text
      from private.broadcast_audience(p_segment, p_days, p_shop_id, pg_catalog.now())
    )
  );
end;
$fn$;

revoke all on function public.admin_preview_broadcast_audience_v1(text, integer, uuid) from public, anon, authenticated;
grant execute on function public.admin_preview_broadcast_audience_v1(text, integer, uuid) to authenticated;

-- Send -------------------------------------------------------------------------
create function public.admin_send_broadcast_v1(
  p_request_key uuid,
  p_segment text,
  p_days integer,
  p_shop_id uuid,
  p_title_ar text,
  p_body_ar text,
  p_link_url text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_expected_count integer
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_admin uuid;
  v_title text;
  v_body text;
  v_link text;
  v_digest text;
  v_now timestamptz;
  v_starts timestamptz;
  v_ends timestamptz;
  v_count integer;
  v_shops uuid[];
  v_prior public.platform_broadcasts%rowtype;
  v_id uuid;
begin
  if not private.subscription_platform_admin_session() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_admin := auth.uid();
  if p_request_key is null
    or p_request_key::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  perform private.broadcast_check_segment(p_segment, p_days, p_shop_id);

  v_title := pg_catalog.btrim(coalesce(p_title_ar, ''));
  v_body := pg_catalog.btrim(pg_catalog.replace(coalesce(p_body_ar, ''), E'\r\n', E'\n'));
  v_link := nullif(pg_catalog.btrim(coalesce(p_link_url, '')), '');
  if pg_catalog.char_length(v_title) not between 1 and 80
    or v_title ~ '[[:cntrl:]]'
    or pg_catalog.char_length(v_body) not between 1 and 1000
    or pg_catalog.replace(v_body, E'\n', '') ~ '[[:cntrl:]]'
    or (v_link is not null and (
      pg_catalog.char_length(v_link) not between 12 and 2048
      or pg_catalog.lower(v_link) not like 'https://%'
      or v_link ~ '[[:space:][:cntrl:]]'
    ))
    or (p_expected_count is not null and p_expected_count < 0) then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  v_digest := pg_catalog.md5(pg_catalog.jsonb_build_array(
    p_segment, p_days, p_shop_id, v_title, v_body, v_link, p_starts_at, p_ends_at, p_expected_count
  )::text);

  perform pg_advisory_xact_lock(840277, hashtext(p_request_key::text));
  -- Statement time, the same instant the directory and audience rule use.
  v_now := pg_catalog.now();
  if not private.subscription_platform_admin_session()
    or auth.uid() is distinct from v_admin
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  select * into v_prior
  from public.platform_broadcasts as prior
  where prior.request_key = p_request_key;
  if found then
    if v_prior.request_digest <> v_digest or v_prior.created_by <> v_admin then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return pg_catalog.jsonb_build_object(
      'status', 'replayed',
      'broadcast_id', v_prior.id,
      'recipient_count', v_prior.recipient_count::text,
      'starts_at', v_prior.starts_at,
      'ends_at', v_prior.ends_at
    );
  end if;

  v_starts := case when p_starts_at is null or p_starts_at <= v_now then v_now else p_starts_at end;
  if v_starts > v_now + interval '90 days' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_ends := coalesce(p_ends_at, v_starts + interval '30 days');
  if v_ends <= v_starts or v_ends > v_starts + interval '365 days' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select coalesce(pg_catalog.array_agg(audience.shop_id), '{}'::uuid[])
    into v_shops
  from private.broadcast_audience(p_segment, p_days, p_shop_id, v_now) as audience;
  v_count := coalesce(pg_catalog.array_length(v_shops, 1), 0);

  if v_count = 0 then
    raise exception 'empty_audience' using errcode = 'P0001';
  end if;
  if p_expected_count is null or v_count <> p_expected_count then
    raise exception 'audience_changed' using errcode = 'P0001';
  end if;

  insert into public.platform_broadcasts (
    request_key, request_digest, created_by, created_at, segment, segment_days, segment_shop_id,
    title_ar, body_ar, link_url, starts_at, ends_at, recipient_count
  ) values (
    p_request_key, v_digest, v_admin, v_now, p_segment, p_days, p_shop_id,
    v_title, v_body, v_link, v_starts, v_ends, v_count
  ) returning id into v_id;

  insert into public.platform_broadcast_recipients (broadcast_id, shop_id)
  select v_id, frozen.shop_id from pg_catalog.unnest(v_shops) as frozen (shop_id);

  insert into public.platform_admin_audit_events (occurred_at, actor_user_id, family, action, target, details)
  values (
    v_now, v_admin, 'broadcast', 'broadcast_sent', v_id::text,
    pg_catalog.jsonb_build_object(
      'title_ar', pg_catalog.left(v_title, 120),
      'segment', p_segment,
      'segment_days', p_days,
      'recipient_count', v_count,
      'starts_at', v_starts,
      'ends_at', v_ends
    )
  );

  return pg_catalog.jsonb_build_object(
    'status', 'sent',
    'broadcast_id', v_id,
    'recipient_count', v_count::text,
    'starts_at', v_starts,
    'ends_at', v_ends
  );
end;
$fn$;

revoke all on function public.admin_send_broadcast_v1(uuid, text, integer, uuid, text, text, text, timestamptz, timestamptz, integer)
  from public, anon, authenticated;
grant execute on function public.admin_send_broadcast_v1(uuid, text, integer, uuid, text, text, text, timestamptz, timestamptz, integer)
  to authenticated;

-- Withdraw ---------------------------------------------------------------------
create function public.admin_withdraw_broadcast_v1(
  p_broadcast_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_admin uuid;
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  v_row public.platform_broadcasts%rowtype;
  v_now timestamptz;
begin
  if not private.subscription_platform_admin_session() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  v_admin := auth.uid();
  if p_broadcast_id is null
    or pg_catalog.char_length(v_reason) not between 3 and 200
    or v_reason ~ '[[:cntrl:]]' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select * into v_row from public.platform_broadcasts where id = p_broadcast_id for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  v_now := pg_catalog.clock_timestamp();
  if not private.subscription_platform_admin_session()
    or auth.uid() is distinct from v_admin
    or not private.subscription_session_live() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if v_row.withdrawn_at is not null then
    return pg_catalog.jsonb_build_object(
      'status', 'already_withdrawn', 'broadcast_id', v_row.id, 'withdrawn_at', v_row.withdrawn_at
    );
  end if;

  update public.platform_broadcasts
    set withdrawn_at = v_now, withdrawn_by = v_admin, withdraw_reason = v_reason
    where id = v_row.id;

  insert into public.platform_admin_audit_events (occurred_at, actor_user_id, family, action, target, details)
  values (
    v_now, v_admin, 'broadcast', 'broadcast_withdrawn', v_row.id::text,
    pg_catalog.jsonb_build_object(
      'title_ar', pg_catalog.left(v_row.title_ar, 120),
      'reason', pg_catalog.left(v_reason, 120)
    )
  );

  return pg_catalog.jsonb_build_object(
    'status', 'withdrawn', 'broadcast_id', v_row.id, 'withdrawn_at', v_now
  );
end;
$fn$;

revoke all on function public.admin_withdraw_broadcast_v1(uuid, text) from public, anon, authenticated;
grant execute on function public.admin_withdraw_broadcast_v1(uuid, text) to authenticated;

-- Admin history ----------------------------------------------------------------
create function public.admin_list_broadcasts_v1(
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
begin
  perform private.broadcast_admin_gate();
  if v_size < 1 or v_size > 50 then
    raise exception 'invalid_page_size' using errcode = '22023';
  end if;
  if v_cursor is not null then
    if pg_catalog.char_length(v_cursor) <> 66
      or pg_catalog.split_part(v_cursor, '|', 1) <> 'v1'
      or pg_catalog.split_part(v_cursor, '|', 2) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}$'
      or pg_catalog.split_part(v_cursor, '|', 3) !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      raise exception 'invalid_cursor' using errcode = '22023';
    end if;
    begin
      v_at := pg_catalog.timezone('UTC', pg_catalog.split_part(v_cursor, '|', 2)::timestamp);
      v_id := pg_catalog.split_part(v_cursor, '|', 3)::uuid;
    exception
      when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
        raise exception 'invalid_cursor' using errcode = '22023';
    end;
    if not exists (select 1 from public.platform_broadcasts where id = v_id and created_at = v_at) then
      raise exception 'stale_cursor' using errcode = '22023';
    end if;
  end if;

  return (
    with window_rows as (
      select broadcast.*
      from public.platform_broadcasts as broadcast
      where v_id is null or (broadcast.created_at, broadcast.id) < (v_at, v_id)
      order by broadcast.created_at desc, broadcast.id desc
      limit (v_size + 1)
    ),
    page_rows as (
      select window_rows.*
      from window_rows
      order by window_rows.created_at desc, window_rows.id desc
      limit v_size
    )
    select pg_catalog.jsonb_build_object(
      'snapshot_at', pg_catalog.now(),
      'page_size', v_size,
      'rows', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', page_rows.id,
            'created_at', page_rows.created_at,
            'created_by_email', author.email,
            'segment', page_rows.segment,
            'segment_days', page_rows.segment_days,
            'segment_shop_id', page_rows.segment_shop_id,
            'segment_shop_name', segment_shop.name,
            'title_ar', page_rows.title_ar,
            'body_ar', page_rows.body_ar,
            'link_url', page_rows.link_url,
            'starts_at', page_rows.starts_at,
            'ends_at', page_rows.ends_at,
            'state', case
              when page_rows.withdrawn_at is not null then 'withdrawn'
              when pg_catalog.now() < page_rows.starts_at then 'scheduled'
              when pg_catalog.now() >= page_rows.ends_at then 'ended'
              else 'active'
            end,
            'recipient_count', page_rows.recipient_count::text,
            'delivered_count', (
              select count(*)::text from public.platform_broadcast_recipients as recipient
              where recipient.broadcast_id = page_rows.id and recipient.delivered_at is not null
            ),
            'read_count', (
              select count(*)::text from public.platform_broadcast_recipients as recipient
              where recipient.broadcast_id = page_rows.id and recipient.read_at is not null
            ),
            'withdrawn_at', page_rows.withdrawn_at,
            'withdraw_reason', page_rows.withdraw_reason
          )
          order by page_rows.created_at desc, page_rows.id desc
        )
        from page_rows
        left join auth.users as author on author.id = page_rows.created_by
        left join public.shops as segment_shop on segment_shop.id = page_rows.segment_shop_id
      ), '[]'::jsonb),
      'next_cursor', case
        when (select count(*) from window_rows) > v_size then (
          select 'v1|'
            || pg_catalog.to_char(page_rows.created_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
            || '|' || page_rows.id::text
          from page_rows
          order by page_rows.created_at asc, page_rows.id asc
          limit 1
        )
        else null
      end
    )
  );
end;
$fn$;

revoke all on function public.admin_list_broadcasts_v1(text, integer) from public, anon, authenticated;
grant execute on function public.admin_list_broadcasts_v1(text, integer) to authenticated;

-- Owner inbox ------------------------------------------------------------------
create function private.broadcast_owner_shop()
returns uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select ownership.shop_id
  from public.shop_memberships as ownership
  where private.subscription_notice_owner_session()
    and ownership.user_id = auth.uid()
    and ownership.role = 'owner'
    and ownership.revoked_at is null
  limit 1;
$fn$;

revoke all on function private.broadcast_owner_shop() from public, anon, authenticated;

create function public.list_my_broadcasts_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.broadcast_owner_shop();
  v_now timestamptz := pg_catalog.now();
begin
  if v_shop is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  update public.platform_broadcast_recipients as recipient
    set delivered_at = v_now
    from public.platform_broadcasts as broadcast
    where recipient.broadcast_id = broadcast.id
      and recipient.shop_id = v_shop
      and recipient.delivered_at is null
      and broadcast.withdrawn_at is null
      and broadcast.starts_at <= v_now
      and v_now < broadcast.ends_at;

  return (
    with visible as (
      select broadcast.id, broadcast.title_ar, broadcast.body_ar, broadcast.link_url,
        broadcast.starts_at, broadcast.ends_at, recipient.read_at
      from public.platform_broadcast_recipients as recipient
      join public.platform_broadcasts as broadcast on broadcast.id = recipient.broadcast_id
      where recipient.shop_id = v_shop
        and broadcast.withdrawn_at is null
        and broadcast.starts_at <= v_now
        and v_now < broadcast.ends_at
    ),
    newest as (
      select visible.* from visible
      order by visible.starts_at desc, visible.id desc
      limit 50
    )
    select pg_catalog.jsonb_build_object(
      'shop_id', v_shop,
      'time_zone', (select shop.time_zone from public.shops as shop where shop.id = v_shop),
      'unread_count', (select count(*)::text from visible where visible.read_at is null),
      'rows', coalesce((
        select pg_catalog.jsonb_agg(
          pg_catalog.jsonb_build_object(
            'id', newest.id,
            'title_ar', newest.title_ar,
            'body_ar', newest.body_ar,
            'link_url', newest.link_url,
            'starts_at', newest.starts_at,
            'ends_at', newest.ends_at,
            'read_at', newest.read_at
          )
          order by newest.starts_at desc, newest.id desc
        )
        from newest
      ), '[]'::jsonb)
    )
  );
end;
$fn$;

revoke all on function public.list_my_broadcasts_v1() from public, anon, authenticated;
grant execute on function public.list_my_broadcasts_v1() to authenticated;

create function public.mark_broadcast_read_v1(p_broadcast_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.broadcast_owner_shop();
  v_read timestamptz;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if v_shop is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  if p_broadcast_id is null then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select recipient.read_at into v_read
  from public.platform_broadcast_recipients as recipient
  join public.platform_broadcasts as broadcast on broadcast.id = recipient.broadcast_id
  where recipient.broadcast_id = p_broadcast_id
    and recipient.shop_id = v_shop
    and broadcast.withdrawn_at is null
    and broadcast.starts_at <= pg_catalog.now()
  for update of recipient;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;
  if v_read is not null then
    return pg_catalog.jsonb_build_object('status', 'already_read', 'broadcast_id', p_broadcast_id, 'read_at', v_read);
  end if;

  update public.platform_broadcast_recipients
    set delivered_at = coalesce(delivered_at, v_now),
        read_at = v_now
    where broadcast_id = p_broadcast_id and shop_id = v_shop;

  return pg_catalog.jsonb_build_object('status', 'read', 'broadcast_id', p_broadcast_id, 'read_at', v_now);
end;
$fn$;

revoke all on function public.mark_broadcast_read_v1(uuid) from public, anon, authenticated;
grant execute on function public.mark_broadcast_read_v1(uuid) to authenticated;

-- Audit read: accept the broadcast family filter.
create or replace function public.admin_list_audit_events_v1(
  p_family text default 'all',
  p_actor uuid default null,
  p_cursor text default null,
  p_page_size integer default 25
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_family text := coalesce(p_family, 'all');
  v_size integer := coalesce(p_page_size, 25);
  v_cursor text := nullif(pg_catalog.btrim(p_cursor), '');
  v_at timestamptz;
  v_key text;
  v_result jsonb;
  v_error text;
begin
  if v_family not in ('all', 'codes', 'contact', 'support', 'app_version', 'help', 'announcement', 'broadcast') then
    raise exception 'invalid_family' using errcode = '22023';
  end if;
  if v_size < 1 or v_size > 50 then
    raise exception 'invalid_page_size' using errcode = '22023';
  end if;
  if v_cursor is not null then
    if pg_catalog.char_length(v_cursor) > 120
      or pg_catalog.array_length(pg_catalog.string_to_array(v_cursor, '|'), 1) is distinct from 3
      or pg_catalog.split_part(v_cursor, '|', 1) <> 'v1'
      or pg_catalog.split_part(v_cursor, '|', 2) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}[.][0-9]{6}$'
      or pg_catalog.split_part(v_cursor, '|', 3) !~ '^(code|contact|support|platform):[0-9a-f-]{1,36}$' then
      raise exception 'invalid_cursor' using errcode = '22023';
    end if;
    begin
      v_at := pg_catalog.timezone('UTC', pg_catalog.split_part(v_cursor, '|', 2)::timestamp);
    exception
      when invalid_datetime_format or datetime_field_overflow then
        raise exception 'invalid_cursor' using errcode = '22023';
    end;
    v_key := pg_catalog.split_part(v_cursor, '|', 3);
  end if;
  v_result := private.admin_list_audit_events_payload(v_family, p_actor, v_at, v_key, v_size);
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

revoke all on function public.admin_list_audit_events_v1(text, uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.admin_list_audit_events_v1(text, uuid, text, integer)
  to authenticated;

comment on function public.admin_send_broadcast_v1(uuid, text, integer, uuid, text, text, text, timestamptz, timestamptz, integer) is
  'Platform-admin in-app broadcast to shop owners. Freezes the recipient list on the server; raises audience_changed when it differs from the confirmed count. Idempotent by request key.';
comment on function public.list_my_broadcasts_v1() is
  'Owner inbox: visible broadcasts for the caller''s own shop (newest 50) and the unread count. Stamps delivery once.';

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function private.platform_broadcasts_immutable() from service_role';
    execute 'revoke all on function private.platform_broadcast_recipients_guard() from service_role';
    execute 'revoke all on function private.broadcast_audience(text, integer, uuid, timestamptz) from service_role';
    execute 'revoke all on function private.broadcast_check_segment(text, integer, uuid) from service_role';
    execute 'revoke all on function private.broadcast_admin_gate() from service_role';
    execute 'revoke all on function private.broadcast_owner_shop() from service_role';
    execute 'revoke all on function public.admin_preview_broadcast_audience_v1(text, integer, uuid) from service_role';
    execute 'revoke all on function public.admin_send_broadcast_v1(uuid, text, integer, uuid, text, text, text, timestamptz, timestamptz, integer) from service_role';
    execute 'revoke all on function public.admin_withdraw_broadcast_v1(uuid, text) from service_role';
    execute 'revoke all on function public.admin_list_broadcasts_v1(text, integer) from service_role';
    execute 'revoke all on function public.list_my_broadcasts_v1() from service_role';
    execute 'revoke all on function public.mark_broadcast_read_v1(uuid) from service_role';
    execute 'revoke all on table public.platform_broadcasts from service_role';
    execute 'revoke all on table public.platform_broadcast_recipients from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

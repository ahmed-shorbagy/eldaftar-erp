-- Platform-admin audit browser (Phase 3 of the admin completion plan, ADR 0046).
--
-- Gaps filled: forced-update policy, Help topic/article and announcement
-- writes kept only "last updated by" on the current row. Row triggers now
-- append one event per real change to public.platform_admin_audit_events
-- (append-only, no client grants). Unchanged saves do not write, because the
-- admin RPCs already skip identical payloads and the update triggers also
-- compare old and new rows.
--
-- Read: public.admin_list_audit_events_v1 merges, newest first, the six
-- admin action sources: code issuance (private.subscription_code_events),
-- contact reveals, support status changes made by an admin, and the three
-- new families above. Each row carries the acting admin's id and email,
-- the affected shop's id and name when there is one, and a safe summary.
-- Never returned: Help/announcement bodies, support inquiry text or replies,
-- revealed phone/location values, code secrets or hashes, or any shop
-- contact or financial field.
begin;

create table public.platform_admin_audit_events (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  actor_user_id uuid,
  family text not null,
  action text not null,
  target text not null,
  details jsonb not null default '{}'::jsonb,
  constraint platform_admin_audit_events_family_check
    check (family in ('app_version', 'help', 'announcement')),
  constraint platform_admin_audit_events_action_check check (action in (
    'app_version_set', 'app_version_cleared',
    'help_topic_created', 'help_topic_updated', 'help_topic_deleted',
    'help_article_created', 'help_article_updated', 'help_article_deleted',
    'announcement_published', 'announcement_updated', 'announcement_cleared'
  )),
  constraint platform_admin_audit_events_target_check
    check (char_length(target) between 1 and 80),
  constraint platform_admin_audit_events_details_object
    check (jsonb_typeof(details) = 'object')
);

comment on table public.platform_admin_audit_events is
  'Append-only history of platform-admin content and policy changes (forced-update policy, Help, announcement). Written by row triggers; read only through admin_list_audit_events_v1.';

create index platform_admin_audit_events_order_idx
  on public.platform_admin_audit_events (occurred_at desc, id desc);

alter table public.platform_admin_audit_events enable row level security;
revoke all on table public.platform_admin_audit_events from public, anon, authenticated;

create function private.platform_admin_audit_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'append_only';
end;
$fn$;

revoke all on function private.platform_admin_audit_events_append_only()
  from public, anon, authenticated;

create trigger platform_admin_audit_events_append_only
  before update or delete on public.platform_admin_audit_events
  for each row execute function private.platform_admin_audit_events_append_only();

-- Forced-update policy -------------------------------------------------------
create function private.audit_app_version_policy()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.platform_admin_audit_events (actor_user_id, family, action, target, details)
  values (
    auth.uid(),
    'app_version',
    case when new.min_version is null then 'app_version_cleared' else 'app_version_set' end,
    new.platform,
    pg_catalog.jsonb_build_object(
      'platform', new.platform,
      'min_version', new.min_version,
      'previous_min_version', case when tg_op = 'UPDATE' then old.min_version else null end,
      'has_update_url', new.update_url is not null
    )
  );
  return null;
end;
$fn$;

revoke all on function private.audit_app_version_policy() from public, anon, authenticated;

create trigger app_version_policies_audit_insert
  after insert on public.app_version_policies
  for each row execute function private.audit_app_version_policy();
create trigger app_version_policies_audit_update
  after update on public.app_version_policies
  for each row
  when (
    old.min_version is distinct from new.min_version
    or old.message_ar is distinct from new.message_ar
    or old.update_url is distinct from new.update_url
  )
  execute function private.audit_app_version_policy();

-- Help topics ------------------------------------------------------------------
create function private.audit_help_topic()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_row public.help_topics%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  insert into public.platform_admin_audit_events (actor_user_id, family, action, target, details)
  values (
    auth.uid(),
    'help',
    case tg_op
      when 'INSERT' then 'help_topic_created'
      when 'UPDATE' then 'help_topic_updated'
      else 'help_topic_deleted'
    end,
    v_row.id::text,
    pg_catalog.jsonb_build_object(
      'title_ar', pg_catalog.left(v_row.title_ar, 120),
      'published', v_row.published
    )
  );
  return null;
end;
$fn$;

revoke all on function private.audit_help_topic() from public, anon, authenticated;

create trigger help_topics_audit_insert_delete
  after insert or delete on public.help_topics
  for each row execute function private.audit_help_topic();
create trigger help_topics_audit_update
  after update on public.help_topics
  for each row
  when (
    old.title_ar is distinct from new.title_ar
    or old.sort_order is distinct from new.sort_order
    or old.published is distinct from new.published
  )
  execute function private.audit_help_topic();

-- Help articles ----------------------------------------------------------------
create function private.audit_help_article()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_row public.help_articles%rowtype;
begin
  if tg_op = 'DELETE' then
    v_row := old;
  else
    v_row := new;
  end if;
  insert into public.platform_admin_audit_events (actor_user_id, family, action, target, details)
  values (
    auth.uid(),
    'help',
    case tg_op
      when 'INSERT' then 'help_article_created'
      when 'UPDATE' then 'help_article_updated'
      else 'help_article_deleted'
    end,
    v_row.id::text,
    pg_catalog.jsonb_build_object(
      'title_ar', pg_catalog.left(v_row.title_ar, 120),
      'published', v_row.published,
      'topic_id', v_row.topic_id
    )
  );
  return null;
end;
$fn$;

revoke all on function private.audit_help_article() from public, anon, authenticated;

create trigger help_articles_audit_insert_delete
  after insert or delete on public.help_articles
  for each row execute function private.audit_help_article();
create trigger help_articles_audit_update
  after update on public.help_articles
  for each row
  when (
    old.title_ar is distinct from new.title_ar
    or old.body_ar is distinct from new.body_ar
    or old.sort_order is distinct from new.sort_order
    or old.published is distinct from new.published
    or old.topic_id is distinct from new.topic_id
  )
  execute function private.audit_help_article();

-- Announcement -----------------------------------------------------------------
create function private.audit_platform_announcement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.platform_admin_audit_events (actor_user_id, family, action, target, details)
  values (
    auth.uid(),
    'announcement',
    case
      when not new.published then 'announcement_cleared'
      when tg_op = 'UPDATE' and old.published then 'announcement_updated'
      else 'announcement_published'
    end,
    'announcement',
    pg_catalog.jsonb_build_object(
      'title_ar', pg_catalog.left(new.title_ar, 120),
      'published', new.published,
      'has_link', new.link_url is not null
    )
  );
  return null;
end;
$fn$;

revoke all on function private.audit_platform_announcement() from public, anon, authenticated;

create trigger platform_announcements_audit_insert
  after insert on public.platform_announcements
  for each row execute function private.audit_platform_announcement();
create trigger platform_announcements_audit_update
  after update on public.platform_announcements
  for each row
  when (
    old.title_ar is distinct from new.title_ar
    or old.body_ar is distinct from new.body_ar
    or old.link_url is distinct from new.link_url
    or old.published is distinct from new.published
  )
  execute function private.audit_platform_announcement();

-- Read -------------------------------------------------------------------------
create function private.admin_list_audit_events_payload(
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
          'subscription_code_issued'::text as action,
          code_event.actor_user_id,
          code_event.shop_id,
          pg_catalog.jsonb_build_object(
            'duration_days', code_event.details->'duration_days',
            'code_expires_at', code_event.details->'code_expires_at',
            'issued_via', code_event.details->'issued_via'
          ) as details
        from private.subscription_code_events as code_event
        where code_event.action = 'subscription_code_issued'
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

create function public.admin_list_audit_events_v1(
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
  if v_family not in ('all', 'codes', 'contact', 'support', 'app_version', 'help', 'announcement') then
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

comment on function public.admin_list_audit_events_v1(text, uuid, text, integer) is
  'Platform-admin action history, newest first: code issuance, contact reveals, admin support status changes, forced-update, Help and announcement changes. Keyset paging by (occurred_at, event_key). Safe summaries only.';

do $revoke_service$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke all on function private.admin_list_audit_events_payload(text, uuid, timestamptz, text, integer) from service_role';
    execute 'revoke all on function public.admin_list_audit_events_v1(text, uuid, text, integer) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';
commit;

-- ADM-05: platform Help FAQ and one platform announcement.
-- Additive. Text-only; no R2 help media kind. No shop financial changes.

begin;

create table public.help_topics (
  id uuid primary key default gen_random_uuid(),
  title_ar text not null,
  sort_order integer not null default 0,
  published boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users (id),
  constraint help_topics_title_ar_check check (length(btrim(title_ar)) > 0)
);

create table public.help_articles (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.help_topics (id) on delete cascade,
  title_ar text not null,
  body_ar text not null,
  sort_order integer not null default 0,
  published boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users (id),
  constraint help_articles_title_ar_check check (length(btrim(title_ar)) > 0),
  constraint help_articles_body_ar_check check (length(btrim(body_ar)) > 0)
);

create index help_articles_topic_sort_idx
  on public.help_articles (topic_id, sort_order, id);

create table public.platform_announcements (
  id smallint primary key default 1 check (id = 1),
  title_ar text not null default '',
  body_ar text not null default '',
  link_url text,
  published boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now()),
  updated_by uuid references auth.users (id),
  constraint platform_announcements_published_copy_check check (
    (not published and title_ar = '' and body_ar = '' and link_url is null)
    or (
      published
      and length(btrim(title_ar)) > 0
      and length(btrim(body_ar)) > 0
    )
  ),
  constraint platform_announcements_link_url_check check (
    link_url is null
    or (
      length(link_url) between 12 and 2048
      and lower(link_url) like 'https://%'
    )
  )
);

alter table public.help_topics enable row level security;
alter table public.help_articles enable row level security;
alter table public.platform_announcements enable row level security;

revoke all on table public.help_topics from anon, authenticated;
revoke all on table public.help_articles from anon, authenticated;
revoke all on table public.platform_announcements from anon, authenticated;

insert into public.platform_announcements (id, title_ar, body_ar, link_url, published)
values (1, '', '', null, false);

create function public.list_help_catalog_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', topic.id,
        'title_ar', topic.title_ar,
        'sort_order', topic.sort_order,
        'articles', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', article.id,
              'title_ar', article.title_ar,
              'body_ar', article.body_ar,
              'sort_order', article.sort_order
            )
            order by article.sort_order, article.id
          )
          from public.help_articles as article
          where article.topic_id = topic.id
            and article.published
        ), '[]'::jsonb)
      )
      order by topic.sort_order, topic.id
    ),
    '[]'::jsonb
  )
  from public.help_topics as topic
  where topic.published;
$function$;

revoke all on function public.list_help_catalog_v1() from public, anon;
grant execute on function public.list_help_catalog_v1() to authenticated;

create function public.get_platform_announcement_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when announcement.published then jsonb_build_object(
      'title_ar', announcement.title_ar,
      'body_ar', announcement.body_ar,
      'link_url', announcement.link_url,
      'updated_at', announcement.updated_at
    )
    else 'null'::jsonb
  end
  from public.platform_announcements as announcement
  where announcement.id = 1;
$function$;

revoke all on function public.get_platform_announcement_v1() from public, anon;
grant execute on function public.get_platform_announcement_v1() to authenticated;

create function public.admin_list_help_catalog_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_gate text;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;
  return coalesce(
    (
      select jsonb_agg(
        jsonb_build_object(
          'id', topic.id,
          'title_ar', topic.title_ar,
          'sort_order', topic.sort_order,
          'published', topic.published,
          'updated_at', topic.updated_at,
          'articles', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'id', article.id,
                'title_ar', article.title_ar,
                'body_ar', article.body_ar,
                'sort_order', article.sort_order,
                'published', article.published,
                'updated_at', article.updated_at
              )
              order by article.sort_order, article.id
            )
            from public.help_articles as article
            where article.topic_id = topic.id
          ), '[]'::jsonb)
        )
        order by topic.sort_order, topic.id
      )
      from public.help_topics as topic
    ),
    '[]'::jsonb
  );
end;
$function$;

revoke all on function public.admin_list_help_catalog_v1() from public, anon;
grant execute on function public.admin_list_help_catalog_v1() to authenticated;

create function public.admin_upsert_help_topic_v1(
  p_id uuid,
  p_title_ar text,
  p_sort_order integer,
  p_published boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_gate text;
  v_title text;
  v_sort integer;
  v_published boolean;
  v_row public.help_topics%rowtype;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  v_title := btrim(coalesce(p_title_ar, ''));
  v_sort := coalesce(p_sort_order, 0);
  v_published := coalesce(p_published, false);
  if length(v_title) = 0 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.help_topics (title_ar, sort_order, published, updated_by)
    values (v_title, v_sort, v_published, auth.uid())
    returning * into v_row;
    return jsonb_build_object(
      'id', v_row.id,
      'title_ar', v_row.title_ar,
      'sort_order', v_row.sort_order,
      'published', v_row.published,
      'updated_at', v_row.updated_at,
      'status', 'saved'
    );
  end if;

  select * into v_row from public.help_topics where id = p_id for update;
  if not found then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if v_row.title_ar is not distinct from v_title
    and v_row.sort_order is not distinct from v_sort
    and v_row.published is not distinct from v_published then
    return jsonb_build_object(
      'id', v_row.id,
      'title_ar', v_row.title_ar,
      'sort_order', v_row.sort_order,
      'published', v_row.published,
      'updated_at', v_row.updated_at,
      'status', 'unchanged'
    );
  end if;

  update public.help_topics
  set
    title_ar = v_title,
    sort_order = v_sort,
    published = v_published,
    updated_at = timezone('utc', now()),
    updated_by = auth.uid()
  where id = p_id
  returning * into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'title_ar', v_row.title_ar,
    'sort_order', v_row.sort_order,
    'published', v_row.published,
    'updated_at', v_row.updated_at,
    'status', 'saved'
  );
end;
$function$;

revoke all on function public.admin_upsert_help_topic_v1(uuid, text, integer, boolean)
  from public, anon;
grant execute on function public.admin_upsert_help_topic_v1(uuid, text, integer, boolean)
  to authenticated;

create function public.admin_upsert_help_article_v1(
  p_id uuid,
  p_topic_id uuid,
  p_title_ar text,
  p_body_ar text,
  p_sort_order integer,
  p_published boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_gate text;
  v_title text;
  v_body text;
  v_sort integer;
  v_published boolean;
  v_row public.help_articles%rowtype;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  if p_topic_id is null
    or not exists (select 1 from public.help_topics where id = p_topic_id) then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  v_title := btrim(coalesce(p_title_ar, ''));
  v_body := btrim(coalesce(p_body_ar, ''));
  v_sort := coalesce(p_sort_order, 0);
  v_published := coalesce(p_published, false);
  if length(v_title) = 0 or length(v_body) = 0 then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if p_id is null then
    insert into public.help_articles (
      topic_id, title_ar, body_ar, sort_order, published, updated_by
    )
    values (p_topic_id, v_title, v_body, v_sort, v_published, auth.uid())
    returning * into v_row;
    return jsonb_build_object(
      'id', v_row.id,
      'topic_id', v_row.topic_id,
      'title_ar', v_row.title_ar,
      'body_ar', v_row.body_ar,
      'sort_order', v_row.sort_order,
      'published', v_row.published,
      'updated_at', v_row.updated_at,
      'status', 'saved'
    );
  end if;

  select * into v_row from public.help_articles where id = p_id for update;
  if not found then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if v_row.topic_id is not distinct from p_topic_id
    and v_row.title_ar is not distinct from v_title
    and v_row.body_ar is not distinct from v_body
    and v_row.sort_order is not distinct from v_sort
    and v_row.published is not distinct from v_published then
    return jsonb_build_object(
      'id', v_row.id,
      'topic_id', v_row.topic_id,
      'title_ar', v_row.title_ar,
      'body_ar', v_row.body_ar,
      'sort_order', v_row.sort_order,
      'published', v_row.published,
      'updated_at', v_row.updated_at,
      'status', 'unchanged'
    );
  end if;

  update public.help_articles
  set
    topic_id = p_topic_id,
    title_ar = v_title,
    body_ar = v_body,
    sort_order = v_sort,
    published = v_published,
    updated_at = timezone('utc', now()),
    updated_by = auth.uid()
  where id = p_id
  returning * into v_row;

  return jsonb_build_object(
    'id', v_row.id,
    'topic_id', v_row.topic_id,
    'title_ar', v_row.title_ar,
    'body_ar', v_row.body_ar,
    'sort_order', v_row.sort_order,
    'published', v_row.published,
    'updated_at', v_row.updated_at,
    'status', 'saved'
  );
end;
$function$;

revoke all on function public.admin_upsert_help_article_v1(
  uuid, uuid, text, text, integer, boolean
) from public, anon;
grant execute on function public.admin_upsert_help_article_v1(
  uuid, uuid, text, text, integer, boolean
) to authenticated;

create function public.admin_get_platform_announcement_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_gate text;
  v_row public.platform_announcements%rowtype;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;
  select * into v_row from public.platform_announcements where id = 1;
  return jsonb_build_object(
    'title_ar', v_row.title_ar,
    'body_ar', v_row.body_ar,
    'link_url', v_row.link_url,
    'published', v_row.published,
    'updated_at', v_row.updated_at
  );
end;
$function$;

revoke all on function public.admin_get_platform_announcement_v1() from public, anon;
grant execute on function public.admin_get_platform_announcement_v1() to authenticated;

create function public.admin_set_platform_announcement_v1(
  p_title_ar text,
  p_body_ar text,
  p_link_url text,
  p_published boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_gate text;
  v_title text;
  v_body text;
  v_url text;
  v_published boolean;
  v_row public.platform_announcements%rowtype;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  v_published := coalesce(p_published, false);
  if not v_published then
    v_title := '';
    v_body := '';
    v_url := null;
  else
    v_title := btrim(coalesce(p_title_ar, ''));
    v_body := btrim(coalesce(p_body_ar, ''));
    v_url := nullif(btrim(coalesce(p_link_url, '')), '');
    if length(v_title) = 0 or length(v_body) = 0 then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
    if v_url is not null
      and (
        length(v_url) < 12
        or length(v_url) > 2048
        or lower(v_url) not like 'https://%'
      ) then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
  end if;

  select * into v_row from public.platform_announcements where id = 1 for update;

  if v_row.title_ar is not distinct from v_title
    and v_row.body_ar is not distinct from v_body
    and v_row.link_url is not distinct from v_url
    and v_row.published is not distinct from v_published then
    return jsonb_build_object(
      'title_ar', v_row.title_ar,
      'body_ar', v_row.body_ar,
      'link_url', v_row.link_url,
      'published', v_row.published,
      'updated_at', v_row.updated_at,
      'status', 'unchanged'
    );
  end if;

  update public.platform_announcements
  set
    title_ar = v_title,
    body_ar = v_body,
    link_url = v_url,
    published = v_published,
    updated_at = timezone('utc', now()),
    updated_by = auth.uid()
  where id = 1
  returning * into v_row;

  return jsonb_build_object(
    'title_ar', v_row.title_ar,
    'body_ar', v_row.body_ar,
    'link_url', v_row.link_url,
    'published', v_row.published,
    'updated_at', v_row.updated_at,
    'status', 'saved'
  );
end;
$function$;

revoke all on function public.admin_set_platform_announcement_v1(text, text, text, boolean)
  from public, anon;
grant execute on function public.admin_set_platform_announcement_v1(text, text, text, boolean)
  to authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.list_help_catalog_v1() from service_role';
    execute 'revoke all on function public.get_platform_announcement_v1() from service_role';
    execute 'revoke all on function public.admin_list_help_catalog_v1() from service_role';
    execute 'revoke all on function public.admin_upsert_help_topic_v1(uuid, text, integer, boolean) from service_role';
    execute 'revoke all on function public.admin_upsert_help_article_v1(uuid, uuid, text, text, integer, boolean) from service_role';
    execute 'revoke all on function public.admin_get_platform_announcement_v1() from service_role';
    execute 'revoke all on function public.admin_set_platform_announcement_v1(text, text, text, boolean) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';

commit;

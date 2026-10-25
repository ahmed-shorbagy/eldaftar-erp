-- ADM-05 Help catalog and announcement. All fixtures roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('f3000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'help-admin@example.test', now(), false,
   null, null, now(), now()),
  ('f3000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'help-owner@example.test', now(), false,
   null, null, now(), now());

insert into public.platform_admins (user_id)
values ('f3000000-0000-4000-8000-0000000000a1');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('f3300000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('f3300000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day');

create function pg_temp.help_call(
  p_role text, p_user text, p_session text, p_sql text
) returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claim.role', p_role, true);
  execute format('set local role %I', p_role);
  begin
    execute 'select (' || p_sql || ')::text' into v;
    execute 'reset role';
    return v;
  exception when others then
    execute 'reset role';
    return sqlerrm;
  end;
end;
$fn$;

do $test$
declare
  v text;
  v_json jsonb;
  v_topic uuid;
  v_article uuid;
begin
  if has_table_privilege('authenticated', 'public.help_topics', 'SELECT')
    or has_table_privilege('anon', 'public.help_articles', 'SELECT')
    or has_table_privilege('authenticated', 'public.platform_announcements', 'SELECT') then
    raise exception 'help_tables_exposed';
  end if;

  -- Owner cannot upsert topic.
  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000b1',
    'f3300000-0000-4000-8000-000000000002',
    $q$select public.admin_upsert_help_topic_v1(null, 'موضوع', 1, true)$q$);
  if v not ilike '%forbidden%' and v not ilike '%42501%' then
    raise exception 'owner_topic_accepted: %', v;
  end if;

  -- Admin creates unpublished topic: owner catalog empty.
  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000a1',
    'f3300000-0000-4000-8000-000000000001',
    $q$select public.admin_upsert_help_topic_v1(null, 'موضوع مخفي', 1, false)$q$);
  v_json := v::jsonb;
  v_topic := (v_json ->> 'id')::uuid;
  if v_json ->> 'status' is distinct from 'saved' then
    raise exception 'admin_topic_failed: %', v;
  end if;

  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000b1',
    'f3300000-0000-4000-8000-000000000002',
    'select public.list_help_catalog_v1()');
  if v::jsonb <> '[]'::jsonb then
    raise exception 'unpublished_visible: %', v;
  end if;

  -- Publish topic + article.
  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000a1',
    'f3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.admin_upsert_help_topic_v1(%L::uuid, 'موضوع منشور', 1, true)$q$,
      v_topic
    ));
  if (v::jsonb) ->> 'published' is distinct from 'true' then
    raise exception 'publish_topic_failed: %', v;
  end if;

  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000a1',
    'f3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.admin_upsert_help_article_v1(
        null, %L::uuid, 'مقال', 'نص المقال', 1, true)$q$,
      v_topic
    ));
  v_json := v::jsonb;
  v_article := (v_json ->> 'id')::uuid;
  if v_json ->> 'status' is distinct from 'saved' then
    raise exception 'admin_article_failed: %', v;
  end if;

  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000b1',
    'f3300000-0000-4000-8000-000000000002',
    'select public.list_help_catalog_v1()');
  v_json := v::jsonb;
  if jsonb_array_length(v_json) <> 1
    or v_json -> 0 ->> 'title_ar' is distinct from 'موضوع منشور'
    or jsonb_array_length(v_json -> 0 -> 'articles') <> 1 then
    raise exception 'owner_catalog_missing: %', v;
  end if;

  -- Empty article body rejected.
  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000a1',
    'f3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.admin_upsert_help_article_v1(
        %L::uuid, %L::uuid, 'مقال', '  ', 1, true)$q$,
      v_article, v_topic
    ));
  if v not ilike '%invalid%' and v not ilike '%22023%' then
    raise exception 'empty_body_accepted: %', v;
  end if;

  -- Announcement publish + clear.
  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000a1',
    'f3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_platform_announcement_v1(
      'تنبيه', 'نص التنبيه', 'https://example.test/a', true)$q$);
  if (v::jsonb) ->> 'status' is distinct from 'saved' then
    raise exception 'announce_set_failed: %', v;
  end if;

  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000b1',
    'f3300000-0000-4000-8000-000000000002',
    'select public.get_platform_announcement_v1()');
  if (v::jsonb) ->> 'title_ar' is distinct from 'تنبيه' then
    raise exception 'announce_read_failed: %', v;
  end if;

  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000a1',
    'f3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_platform_announcement_v1('', '', null, false)$q$);
  if (v::jsonb) ->> 'published' is distinct from 'false' then
    raise exception 'announce_clear_failed: %', v;
  end if;

  v := pg_temp.help_call(
    'authenticated',
    'f3000000-0000-4000-8000-0000000000b1',
    'f3300000-0000-4000-8000-000000000002',
    'select public.get_platform_announcement_v1()');
  if v is distinct from 'null' then
    raise exception 'announce_still_visible: %', v;
  end if;

  raise notice 'HELP_CONTENT_ANNOUNCEMENTS_SQL_PASSED';
end;
$test$;

rollback;

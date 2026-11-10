-- Rollback-only platform-admin audit checks (ADR 0046) for a disposable local database.
begin;

do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_admin_audit_' then
    raise exception 'local_disposable_database_required';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
  email_confirmed_at, raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until
) values
  ('a6000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-admin-one@example.test', false, now(), now(),
    now(), '{}'::jsonb, '{}'::jsonb, null, null),
  ('a6000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-admin-two@example.test', false, now(), now(),
    now(), '{}'::jsonb, '{}'::jsonb, null, null),
  ('a6000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-owner@example.test', false, now(), now(),
    now(), '{"is_platform_admin":true}'::jsonb, '{"role":"platform_admin"}'::jsonb, null, null);

insert into public.platform_admins (user_id) values
  ('a6000000-0000-4000-8000-0000000000a1'),
  ('a6000000-0000-4000-8000-0000000000a2');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('a6200000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('a6200000-0000-4000-8000-000000000002', 'a6000000-0000-4000-8000-0000000000a1', now(), now(), now() - interval '1 minute');

insert into public.shops (id, name, created_at) values
  ('a6100000-0000-4000-8000-000000000001', 'متجر السجل', now() - interval '30 days');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('a6100000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-0000000000b1', 'owner');

-- Fixtures for the three sources that already had history, at fixed times.
insert into private.subscription_code_events (shop_id, actor_user_id, action, correlation_id, details, created_at) values
  ('a6100000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-0000000000a2', 'subscription_code_issued', gen_random_uuid(),
    '{"duration_days":30,"code_expires_at":"2030-01-01T00:00:00Z","issued_via":"platform_admin"}'::jsonb, now() - interval '5 hours'),
  ('a6100000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-0000000000b1', 'subscription_code_redeemed', gen_random_uuid(),
    '{"duration_days":30}'::jsonb, now() - interval '4 hours');
insert into public.admin_subscriber_contact_reveals (shop_id, admin_user_id, revealed_at) values
  ('a6100000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-0000000000a1', now() - interval '3 hours');
insert into public.support_inquiries (id, shop_id, owner_user_id, category, body_ar, status, idempotency_key, created_at) values
  ('a6300000-0000-4000-8000-000000000001', 'a6100000-0000-4000-8000-000000000001', 'a6000000-0000-4000-8000-0000000000b1',
    'other', 'نص استفسار سري للمالك', 'in_progress', gen_random_uuid(), now() - interval '2 hours');
insert into public.support_inquiry_events (inquiry_id, from_status, to_status, reply_ar, actor_user_id, idempotency_key, created_at) values
  ('a6300000-0000-4000-8000-000000000001', null, 'new', null, 'a6000000-0000-4000-8000-0000000000b1', gen_random_uuid(), now() - interval '2 hours'),
  ('a6300000-0000-4000-8000-000000000001', 'new', 'in_progress', null, 'a6000000-0000-4000-8000-0000000000a2', gen_random_uuid(), now() - interval '1 hour');

create function pg_temp.aud_call(p_role text, p_user text, p_session text, p_sql text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claims', '', true);
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
  v_admin constant text := 'a6000000-0000-4000-8000-0000000000a1';
  v_session constant text := 'a6200000-0000-4000-8000-000000000001';
  v_count integer;
  v_topic uuid;
  v jsonb;
  v_page jsonb;
  v_cursor text;
  v_seen text[] := '{}';
  v_pages integer := 0;
  v_text text;
begin
  -- Grants, shape and append-only storage.
  if has_table_privilege('authenticated', 'public.platform_admin_audit_events', 'select')
    or has_table_privilege('authenticated', 'public.platform_admin_audit_events', 'insert')
    or has_table_privilege('anon', 'public.platform_admin_audit_events', 'select') then
    raise exception 'table_grants';
  end if;
  if has_function_privilege('anon', 'public.admin_list_audit_events_v1(text,uuid,text,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_list_audit_events_v1(text,uuid,text,integer)', 'execute')
    or has_function_privilege('authenticated', 'private.admin_list_audit_events_payload(text,uuid,timestamptz,text,integer)', 'execute')
    or has_function_privilege('authenticated', 'private.audit_app_version_policy()', 'execute') then
    raise exception 'function_grants';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role')
    and has_function_privilege('service_role', 'public.admin_list_audit_events_v1(text,uuid,text,integer)', 'execute') then
    raise exception 'service_role_grant';
  end if;
  v_text := pg_get_functiondef('private.admin_list_audit_events_payload(text,uuid,timestamptz,text,integer)'::regprocedure);
  if position('private.admin_subscriber_gate()' in v_text) = 0
    or v_text ilike '%body_ar%' or v_text ilike '%reply_ar%' or v_text ilike '%phone%'
    or v_text ilike '%governorate%' or v_text ilike '%code_hash%' or v_text ilike '%message_ar%' then
    raise exception 'contract_text';
  end if;

  -- Only a live platform admin may read.
  if pg_temp.aud_call('anon', null, null, 'public.admin_list_audit_events_v1()') not like '%permission denied%'
    or pg_temp.aud_call('authenticated', null, null, 'public.admin_list_audit_events_v1()') <> 'unauthenticated'
    or pg_temp.aud_call('authenticated', 'a6000000-0000-4000-8000-0000000000b1', null, 'public.admin_list_audit_events_v1()') <> 'forbidden'
    or pg_temp.aud_call('authenticated', v_admin, 'a6200000-0000-4000-8000-000000000002', 'public.admin_list_audit_events_v1()') <> 'session_expired' then
    raise exception 'denied_roles';
  end if;

  -- Real admin writes produce one event per change and none for an unchanged save.
  select count(*) into v_count from public.platform_admin_audit_events;
  if v_count <> 0 then raise exception 'fixture_not_empty %', v_count; end if;

  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_set_app_version_policy_v1(''android'', ''2.0.0'', ''حدّث التطبيق الآن'', null)');
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_set_app_version_policy_v1(''android'', ''2.0.0'', ''حدّث التطبيق الآن'', null)');
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_set_app_version_policy_v1(''android'', null, '''', null)');
  if (select array_agg(action order by action) from public.platform_admin_audit_events where family = 'app_version')
    <> array['app_version_cleared', 'app_version_set']
    or exists (select 1 from public.platform_admin_audit_events where actor_user_id is distinct from v_admin::uuid)
    or (select details->>'previous_min_version' from public.platform_admin_audit_events where action = 'app_version_cleared') <> '2.0.0' then
    raise exception 'app_version_events';
  end if;

  v_text := pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_upsert_help_topic_v1(null, ''الاشتراك'', 1, true)');
  v_topic := (v_text::jsonb->>'id')::uuid;
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    format('public.admin_upsert_help_topic_v1(%L, ''الاشتراك'', 1, true)', v_topic));
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    format('public.admin_upsert_help_topic_v1(%L, ''الاشتراك والتجديد'', 1, true)', v_topic));
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    format('public.admin_upsert_help_article_v1(null, %L, ''كيف أجدد؟'', ''نص مقال طويل لا يظهر في السجل'', 1, true)', v_topic));
  if (select array_agg(action order by occurred_at, action) from public.platform_admin_audit_events where family = 'help')
    <> array['help_article_created', 'help_topic_created', 'help_topic_updated'] then
    raise exception 'help_events %', (select array_agg(action) from public.platform_admin_audit_events where family = 'help');
  end if;

  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_set_platform_announcement_v1(''صيانة'', ''نص إعلان لا يظهر في السجل'', null, true)');
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_set_platform_announcement_v1(''صيانة الليلة'', ''نص إعلان لا يظهر في السجل'', null, true)');
  perform pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_set_platform_announcement_v1('''', '''', null, false)');
  if (select array_agg(action order by action) from public.platform_admin_audit_events where family = 'announcement')
    <> array['announcement_cleared', 'announcement_published', 'announcement_updated'] then
    raise exception 'announcement_events %', (select array_agg(action) from public.platform_admin_audit_events where family = 'announcement');
  end if;

  begin
    update public.platform_admin_audit_events set action = 'app_version_set';
    raise exception 'update_allowed';
  exception when others then
    if sqlerrm <> 'append_only' then raise; end if;
  end;
  begin
    delete from public.platform_admin_audit_events;
    raise exception 'delete_allowed';
  exception when others then
    if sqlerrm <> 'append_only' then raise; end if;
  end;

  -- The browser merges every admin source, newest first, with safe summaries.
  v := pg_temp.aud_call('authenticated', v_admin, v_session, 'public.admin_list_audit_events_v1(''all'', null, null, 50)')::jsonb;
  if jsonb_array_length(v->'rows') <> 11 then
    raise exception 'row_count %', jsonb_array_length(v->'rows');
  end if;
  if (select array_agg(distinct row->>'family' order by row->>'family') from jsonb_array_elements(v->'rows') as row)
    <> array['announcement', 'app_version', 'codes', 'contact', 'help', 'support'] then
    raise exception 'families';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v->'rows') with ordinality as a(row, n)
    join jsonb_array_elements(v->'rows') with ordinality as b(row, m) on m = n + 1
    where (a.row->>'occurred_at')::timestamptz < (b.row->>'occurred_at')::timestamptz
  ) then
    raise exception 'not_newest_first';
  end if;
  if v::text like '%subscription_code_redeemed%' or v::text like '%"to_status": "new"%' then
    raise exception 'owner_actions_listed';
  end if;
  if v::text like '%نص استفسار سري%' or v::text like '%لا يظهر في السجل%' or v::text like '%حدّث التطبيق الآن%' then
    raise exception 'body_leak';
  end if;
  select row into v_page from jsonb_array_elements(v->'rows') as row where row->>'family' = 'codes';
  if v_page->>'shop_name' <> 'متجر السجل' or v_page->>'actor_email' <> 'audit-admin-two@example.test'
    or v_page->'details'->>'duration_days' <> '30' then
    raise exception 'code_row %', v_page;
  end if;
  select row into v_page from jsonb_array_elements(v->'rows') as row where row->>'family' = 'support';
  if v_page->'details' <> '{"from_status":"new","to_status":"in_progress"}'::jsonb then
    raise exception 'support_row %', v_page;
  end if;
  if v->'admins' <> '[{"user_id":"a6000000-0000-4000-8000-0000000000a1","email":"audit-admin-one@example.test"},{"user_id":"a6000000-0000-4000-8000-0000000000a2","email":"audit-admin-two@example.test"}]'::jsonb then
    raise exception 'admins %', v->'admins';
  end if;

  -- Filters.
  v := pg_temp.aud_call('authenticated', v_admin, v_session, 'public.admin_list_audit_events_v1(''help'', null, null, 50)')::jsonb;
  if jsonb_array_length(v->'rows') <> 3 then raise exception 'family_filter'; end if;
  v := pg_temp.aud_call('authenticated', v_admin, v_session,
    'public.admin_list_audit_events_v1(''all'', ''a6000000-0000-4000-8000-0000000000a2'', null, 50)')::jsonb;
  if jsonb_array_length(v->'rows') <> 2 then raise exception 'actor_filter %', jsonb_array_length(v->'rows'); end if;

  -- Paging visits every row once.
  v_cursor := null;
  loop
    v_page := pg_temp.aud_call('authenticated', v_admin, v_session,
      format('public.admin_list_audit_events_v1(''all'', null, %L, 2)', v_cursor))::jsonb;
    v_pages := v_pages + 1;
    v_seen := v_seen || array(select row->>'event_key' from jsonb_array_elements(v_page->'rows') as row);
    v_cursor := v_page->>'next_cursor';
    exit when v_cursor is null or v_pages > 10;
  end loop;
  if cardinality(v_seen) <> 11 or (select count(distinct key) from unnest(v_seen) as key) <> 11 or v_pages <> 6 then
    raise exception 'paging % %', cardinality(v_seen), v_pages;
  end if;

  if pg_temp.aud_call('authenticated', v_admin, v_session, 'public.admin_list_audit_events_v1(''finance'', null, null, 25)') <> 'invalid_family'
    or pg_temp.aud_call('authenticated', v_admin, v_session, 'public.admin_list_audit_events_v1(''all'', null, ''v1|bad|x'', 25)') <> 'invalid_cursor'
    or pg_temp.aud_call('authenticated', v_admin, v_session, 'public.admin_list_audit_events_v1(''all'', null, null, 51)') <> 'invalid_page_size' then
    raise exception 'validation';
  end if;
end;
$test$;

rollback;

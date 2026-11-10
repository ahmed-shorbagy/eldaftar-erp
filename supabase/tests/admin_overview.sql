-- Rollback-only admin overview checks (ADR 0045) for a disposable local database.
-- Synthetic shops only. The read must not change finance, entitlements or audits.
begin;

do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_admin_overview_' then
    raise exception 'local_disposable_database_required';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
  raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until
) values
  ('a5000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-admin@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, now() - interval '1 day'),
  ('a5000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-owner@example.test', false, now(), now(),
    '{"is_platform_admin":true}'::jsonb, '{"role":"platform_admin"}'::jsonb, null, null),
  ('a5000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-revoked@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('a5000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-anon@example.test', true, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('a5000000-0000-4000-8000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-deleted@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, now(), null),
  ('a5000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-banned@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, now() + interval '1 day');

insert into public.platform_admins (user_id) values
  ('a5000000-0000-4000-8000-0000000000a1'),
  ('a5000000-0000-4000-8000-0000000000d1'),
  ('a5000000-0000-4000-8000-0000000000e1'),
  ('a5000000-0000-4000-8000-0000000000f1'),
  ('a5000000-0000-4000-8000-0000000000a2');
delete from public.platform_admins where user_id = 'a5000000-0000-4000-8000-0000000000d1';

-- now() is fixed for the whole transaction, so window edges are exact.
-- S1 active, ends in 2 days, registered 1 day ago
-- S2 active, ends in 5 days, registered 10 days ago
-- S3 active, ends in 20 days, registered 40 days ago
-- S4 active, ends in 40 days, registered exactly 7 days ago (outside the 7-day window)
-- S5 pending (no term), registered now
-- S6 pending (future start), registered 2 days ago
-- S7 expired, registered 100 days ago
-- S8 active, ends exactly 3 days from now (inside the 3-day window), registered 50 days ago
insert into public.shops (id, name, created_at) values
  ('a5100000-0000-4000-8000-000000000001', 'نظرة ١', now() - interval '1 day'),
  ('a5100000-0000-4000-8000-000000000002', 'نظرة ٢', now() - interval '10 days'),
  ('a5100000-0000-4000-8000-000000000003', 'نظرة ٣', now() - interval '40 days'),
  ('a5100000-0000-4000-8000-000000000004', 'نظرة ٤', now() - interval '7 days'),
  ('a5100000-0000-4000-8000-000000000005', 'نظرة ٥', now()),
  ('a5100000-0000-4000-8000-000000000006', 'نظرة ٦', now() - interval '2 days'),
  ('a5100000-0000-4000-8000-000000000007', 'نظرة ٧', now() - interval '100 days'),
  ('a5100000-0000-4000-8000-000000000008', 'نظرة ٨', now() - interval '50 days');

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a5100000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '2 days'),
  ('a5100000-0000-4000-8000-000000000002', now() - interval '1 day', now() + interval '5 days'),
  ('a5100000-0000-4000-8000-000000000003', now() - interval '1 day', now() + interval '20 days'),
  ('a5100000-0000-4000-8000-000000000004', now() - interval '1 day', now() + interval '40 days'),
  ('a5100000-0000-4000-8000-000000000006', now() + interval '1 day', now() + interval '3 days'),
  ('a5100000-0000-4000-8000-000000000007', now() - interval '10 days', now() - interval '1 day'),
  ('a5100000-0000-4000-8000-000000000008', now() - interval '1 day', now() + interval '3 days');

insert into public.shop_memberships (shop_id, user_id, role) values
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000b1', 'owner');

insert into public.support_inquiries (
  shop_id, owner_user_id, category, body_ar, status, reply_ar, idempotency_key, answered_at, closed_at
) values
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000b1', 'other', 'استفسار جديد أول', 'new', null, gen_random_uuid(), null, null),
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000b1', 'other', 'استفسار جديد ثان', 'new', null, gen_random_uuid(), null, null),
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000b1', 'technical', 'قيد المعالجة', 'in_progress', null, gen_random_uuid(), null, null),
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000b1', 'technical', 'تم الرد', 'answered', 'رد', gen_random_uuid(), now(), null),
  ('a5100000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000b1', 'technical', 'مغلق', 'closed', 'رد', gen_random_uuid(), now(), now());

insert into public.app_version_policies (platform, min_version, message_ar)
values ('android', '1.2.0', 'حدّث التطبيق')
on conflict (platform) do update set min_version = excluded.min_version, message_ar = excluded.message_ar;
delete from public.app_version_policies where platform in ('ios', 'windows');
delete from public.platform_announcements;

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('a5200000-0000-4000-8000-000000000001', 'a5000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('a5200000-0000-4000-8000-000000000002', 'a5000000-0000-4000-8000-0000000000a1', now(), now(), now() - interval '1 minute');

create function pg_temp.ovw_call(p_role text, p_user text, p_session text, p_sql text)
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

create function pg_temp.ovw_digest() returns text
language sql
as $fn$
  select md5(concat_ws(';',
    (select count(*)::text from public.shops),
    (select coalesce(string_agg(
      shop_id::text
        || pg_catalog.to_char(starts_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
        || pg_catalog.to_char(expires_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'),
      ',' order by shop_id), '') from public.shop_entitlements),
    (select coalesce(string_agg(id::text || status, ',' order by id), '') from public.support_inquiries),
    (select count(*)::text from public.support_inquiry_events),
    (select count(*)::text from public.financial_operations),
    (select count(*)::text from public.financial_audit_events),
    (select count(*)::text from public.identity_audit_events),
    (select count(*)::text from public.shop_memberships)
  ));
$fn$;

do $test$
declare
  v_before text := pg_temp.ovw_digest();
  v_admin constant text := 'a5000000-0000-4000-8000-0000000000a1';
  v jsonb;
  v_def text;
  v_ids text;
begin
  -- Grants and function shape.
  if has_function_privilege('anon', 'public.admin_get_overview_v1()', 'execute')
    or has_function_privilege('public', 'public.admin_get_overview_v1()', 'execute')
    or has_function_privilege('authenticated', 'private.admin_overview_payload()', 'execute') then
    raise exception 'execute_grant';
  end if;
  if not has_function_privilege('authenticated', 'public.admin_get_overview_v1()', 'execute') then
    raise exception 'authenticated_grant_missing';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role')
    and has_function_privilege('service_role', 'public.admin_get_overview_v1()', 'execute') then
    raise exception 'service_role_grant';
  end if;
  if not exists (
    select 1 from pg_proc
    where oid = 'public.admin_get_overview_v1()'::regprocedure
      and prosecdef and provolatile = 's'
      and exists (select 1 from unnest(proconfig) as cfg where cfg like 'search_path=%')
  ) then
    raise exception 'function_security';
  end if;
  v_def := pg_get_functiondef('private.admin_overview_payload()'::regprocedure);
  if position('private.admin_subscriber_gate()' in v_def) = 0
    or v_def ilike '%phone%' or v_def ilike '%email%' or v_def ilike '%governorate%'
    or v_def ilike '%owner_display_name%' or v_def ilike '%user_metadata%'
    or v_def ilike '%body_ar%' or v_def ilike '%reply_ar%' or v_def ilike '%shop.name%' then
    raise exception 'contract_text';
  end if;

  -- Only a live, confirmed, unbanned platform admin may read.
  if pg_temp.ovw_call('anon', null, null, 'public.admin_get_overview_v1()') not like '%permission denied%' then
    raise exception 'anon_call';
  end if;
  if pg_temp.ovw_call('authenticated', null, null, 'public.admin_get_overview_v1()') <> 'unauthenticated' then
    raise exception 'missing_user';
  end if;
  if pg_temp.ovw_call('authenticated', 'a5000000-0000-4000-8000-0000000000b1', null, 'public.admin_get_overview_v1()') <> 'forbidden'
    or pg_temp.ovw_call('authenticated', 'a5000000-0000-4000-8000-0000000000d1', null, 'public.admin_get_overview_v1()') <> 'forbidden'
    or pg_temp.ovw_call('authenticated', 'a5000000-0000-4000-8000-0000000000e1', null, 'public.admin_get_overview_v1()') <> 'forbidden'
    or pg_temp.ovw_call('authenticated', 'a5000000-0000-4000-8000-0000000000f1', null, 'public.admin_get_overview_v1()') <> 'forbidden'
    or pg_temp.ovw_call('authenticated', 'a5000000-0000-4000-8000-0000000000a2', null, 'public.admin_get_overview_v1()') <> 'forbidden' then
    raise exception 'denied_role';
  end if;
  if pg_temp.ovw_call('authenticated', v_admin, 'a5200000-0000-4000-8000-000000000002', 'public.admin_get_overview_v1()') <> 'session_expired' then
    raise exception 'expired_session';
  end if;

  -- Figures from one snapshot.
  v := pg_temp.ovw_call('authenticated', v_admin, 'a5200000-0000-4000-8000-000000000001', 'public.admin_get_overview_v1()')::jsonb;
  if (v->>'snapshot_at')::timestamptz <> now() then
    raise exception 'snapshot_time %', v->>'snapshot_at';
  end if;
  if v->'subscriptions' <> '{"all":"8","active":"5","pending":"2","expired":"1"}'::jsonb then
    raise exception 'subscriptions %', v->'subscriptions';
  end if;
  if v->'expiring' <> '{"within_3_days":"2","within_7_days":"3","within_30_days":"4"}'::jsonb then
    raise exception 'expiring %', v->'expiring';
  end if;
  if v->'registrations' <> '{"last_7_days":"3","last_30_days":"5"}'::jsonb then
    raise exception 'registrations %', v->'registrations';
  end if;
  if v->'support' <> '{"new":"2","in_progress":"1","answered":"1"}'::jsonb then
    raise exception 'support %', v->'support';
  end if;
  if v->'app_versions' <> '[{"platform":"android","min_version":"1.2.0"},{"platform":"ios","min_version":null},{"platform":"windows","min_version":null}]'::jsonb then
    raise exception 'app_versions %', v->'app_versions';
  end if;
  if v->'announcement_published' <> 'false'::jsonb then
    raise exception 'announcement %', v->'announcement_published';
  end if;
  if v::text like '%a5100000%' or v::text like '%نظرة%' or v::text like '%example.test%'
    or v::text like '%استفسار%' then
    raise exception 'row_leak';
  end if;
  if (select array_agg(key order by key) from jsonb_object_keys(v) as key)
    <> array['announcement_published', 'app_versions', 'expiring', 'registrations', 'snapshot_at', 'subscriptions', 'support'] then
    raise exception 'top_level_keys';
  end if;

  insert into public.platform_announcements (id, title_ar, body_ar, published)
  values (1, 'إعلان', 'نص الإعلان', true);
  v := pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_get_overview_v1()')::jsonb;
  if v->'announcement_published' <> 'true'::jsonb then
    raise exception 'announcement_published';
  end if;
  delete from public.platform_announcements;

  -- Directory expiring filters return the same shops, oldest registration first.
  v := pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_list_subscribers_v1(''expiring_3'','''',null,25)')::jsonb;
  select string_agg(row->>'shop_id', ',' order by ordinality) into v_ids
  from jsonb_array_elements(v->'rows') with ordinality as rows(row, ordinality);
  if v->>'filtered_count' <> '2'
    or v_ids <> 'a5100000-0000-4000-8000-000000000008,a5100000-0000-4000-8000-000000000001' then
    raise exception 'expiring_3 % %', v->>'filtered_count', v_ids;
  end if;
  v := pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_list_subscribers_v1(''expiring_7'','''',null,25)')::jsonb;
  if v->>'filtered_count' <> '3' then
    raise exception 'expiring_7 %', v->>'filtered_count';
  end if;
  v := pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_list_subscribers_v1(''expiring_30'','''',null,25)')::jsonb;
  if v->>'filtered_count' <> '4'
    or v->'counts' <> '{"all":"8","active":"5","pending":"2","expired":"1"}'::jsonb then
    raise exception 'expiring_30 % %', v->>'filtered_count', v->'counts';
  end if;
  v := pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_list_subscribers_v1(''expiring_30'',''نظرة ٢'',null,25)')::jsonb;
  if v->>'filtered_count' <> '1' then
    raise exception 'expiring_search %', v->>'filtered_count';
  end if;
  v := pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_list_subscribers_v1(''active'','''',null,25)')::jsonb;
  if v->>'filtered_count' <> '5' then
    raise exception 'active_filter_changed %', v->>'filtered_count';
  end if;
  if pg_temp.ovw_call('authenticated', v_admin, null, 'public.admin_list_subscribers_v1(''expiring_8'','''',null,25)') <> 'invalid_status'
    or pg_temp.ovw_call('authenticated', 'a5000000-0000-4000-8000-0000000000b1', null, 'public.admin_list_subscribers_v1(''expiring_7'','''',null,25)') <> 'forbidden' then
    raise exception 'expiring_validation';
  end if;

  if pg_temp.ovw_digest() <> v_before then
    raise exception 'read_changed_state';
  end if;
end;
$test$;

rollback;

-- Rollback-only ADM-01 directory checks for a disposable local database.
-- Synthetic shops only. Reads must not change finance, entitlements, or audits.
begin;

do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_admin_subscribers_' then
    raise exception 'local_disposable_database_required';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
  raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until
) values
  ('a1000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin@example.test', false, now(), now(),
    '{"role":"owner"}'::jsonb, '{}'::jsonb, null, now() - interval '1 day'),
  ('a1000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@example.test', false, now(), now(),
    '{"is_platform_admin":true}'::jsonb, '{"role":"platform_admin"}'::jsonb, null, null),
  ('a1000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('a1000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'revoked-admin@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('a1000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'anon-admin@example.test', true, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('a1000000-0000-4000-8000-0000000000f1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deleted-admin@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, now(), null),
  ('a1000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'banned-admin@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, now() + interval '1 day'),
  ('a1000000-0000-4000-8000-0000000000a3', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pretend-admin@example.test', false, now(), now(),
    '{"is_platform_admin":true,"role":"platform_admin"}'::jsonb,
    '{"role":"platform_admin"}'::jsonb, null, null);

insert into public.shops (id, name, created_at) values
  ('a1100000-0000-4000-8000-000000000001', 'متجر ألف', timestamptz '2020-01-01 00:00:00+00'),
  ('a1100000-0000-4000-8000-000000000002', 'متجر ألف', timestamptz '2020-01-01 00:00:00+00'),
  ('a1100000-0000-4000-8000-000000000003', 'خصم 100%_عرض', timestamptz '2020-01-02 00:00:00+00'),
  ('a1100000-0000-4000-8000-000000000004', 'متجر منتهي', timestamptz '2020-01-03 00:00:00+00'),
  ('a1100000-0000-4000-8000-000000000005', 'متجر بداية الآن', timestamptz '2020-01-04 00:00:00+00'),
  ('a1100000-0000-4000-8000-000000000006', 'متجر قبل النهاية', timestamptz '2020-01-05 00:00:00+00'),
  ('a1100000-0000-4000-8000-000000000008', 'GoldShop', timestamptz '2020-01-07 00:00:00+00');

insert into public.shops (
  id, name, owner_display_name, email, governorate_code, phone, time_zone, created_at
)
select
  'a1100000-0000-4000-8000-000000000007',
  'متجر ظاهر',
  'اسم مالك سري',
  'leak-adm01@example.test',
  'EG-GZ',
  private.registration_phone('+201099988877', 'EG-GZ'),
  private.registration_time_zone('EG-GZ'),
  timestamptz '2020-01-06 00:00:00+00';

insert into public.shop_memberships (shop_id, user_id, role) values
  ('a1100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000b1', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a1100000-0000-4000-8000-000000000001', now(), now() + interval '1 day'),
  ('a1100000-0000-4000-8000-000000000002', now() + interval '1 microsecond', now() + interval '30 days'),
  ('a1100000-0000-4000-8000-000000000004', now() - interval '2 days', now()),
  ('a1100000-0000-4000-8000-000000000005', now(), now() + interval '1 microsecond'),
  ('a1100000-0000-4000-8000-000000000006', now() - interval '1 day', now() + interval '1 microsecond'),
  ('a1100000-0000-4000-8000-000000000007', now() - interval '10 days', now() - interval '1 day');

insert into public.platform_admins (user_id) values
  ('a1000000-0000-4000-8000-0000000000a1'),
  ('a1000000-0000-4000-8000-0000000000d1'),
  ('a1000000-0000-4000-8000-0000000000e1'),
  ('a1000000-0000-4000-8000-0000000000f1'),
  ('a1000000-0000-4000-8000-0000000000a2');
delete from public.platform_admins where user_id = 'a1000000-0000-4000-8000-0000000000d1';

insert into public.closing_staff_accounts (shop_id, user_id, display_name, phone, created_by) values
  ('a1100000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000c1', 'عدّاد', '+201000000001', 'a1000000-0000-4000-8000-0000000000b1');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('a1200000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('a1200000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-0000000000a1', now(), now(), now() - interval '1 minute');

create function pg_temp.adm_call(p_role text, p_user text, p_session text, p_claims text, p_sql text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claims', coalesce(p_claims, ''), true);
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

create function pg_temp.adm_digest() returns text
language sql
as $fn$
  select md5(concat_ws(';',
    (select count(*)::text from public.shops),
    (select count(*)::text from public.shop_entitlements),
    (select coalesce(string_agg(
      shop_id::text
        || pg_catalog.to_char(starts_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US')
        || pg_catalog.to_char(expires_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI:SS.US'),
      ',' order by shop_id), '') from public.shop_entitlements),
    (select count(*)::text from public.financial_operations),
    (select count(*)::text from public.financial_audit_events),
    (select count(*)::text from public.identity_audit_events),
    (select count(*)::text from public.invoice_dispatch_confirmations),
    (select count(*)::text from public.financial_command_requests),
    (select count(*)::text from public.closing_delegation_audit),
    (select count(*)::text from public.r2_media_objects),
    (select count(*)::text from public.shop_memberships)
  ));
$fn$;

do $test$
declare
  v_before text := pg_temp.adm_digest();
  v_admin constant text := 'a1000000-0000-4000-8000-0000000000a1';
  v jsonb;
  v2 jsonb;
  v_cursor text;
  v_first_cursor text;
  v_page jsonb;
  v_ids text[];
  v_def text;
begin
  if has_function_privilege('anon', 'public.admin_list_subscribers_v1(text,text,text,integer)', 'execute')
    or has_function_privilege('anon', 'public.admin_get_subscriber_v1(uuid)', 'execute')
    or has_function_privilege('authenticated', 'private.admin_subscriber_gate()', 'execute')
    or has_function_privilege('public', 'public.admin_list_subscribers_v1(text,text,text,integer)', 'execute') then
    raise exception 'execute_grant';
  end if;
  if not has_function_privilege('authenticated', 'public.admin_list_subscribers_v1(text,text,text,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_get_subscriber_v1(uuid)', 'execute') then
    raise exception 'authenticated_grant_missing';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role')
    and (
      has_function_privilege('service_role', 'public.admin_list_subscribers_v1(text,text,text,integer)', 'execute')
      or has_function_privilege('service_role', 'public.admin_get_subscriber_v1(uuid)', 'execute')
    ) then
    raise exception 'service_role_grant';
  end if;
  if not exists (
    select 1 from pg_proc
    where oid = 'public.admin_list_subscribers_v1(text,text,text,integer)'::regprocedure
      and prosecdef and provolatile = 's'
      and exists (select 1 from unnest(proconfig) as cfg where cfg like 'search_path=%')
  ) then
    raise exception 'function_security';
  end if;
  v_def := pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure)
    || pg_get_functiondef('private.admin_list_subscribers_payload(text,text,timestamptz,uuid,integer)'::regprocedure)
    || pg_get_functiondef('private.admin_get_subscriber_payload(uuid)'::regprocedure);
  if v_def ilike '%user_metadata%' or v_def ilike '%raw_user_meta_data%' or v_def ilike '%raw_app_meta_data%'
    or v_def ilike '%phone%' or v_def ilike '%email%' or v_def ilike '%governorate%'
    or v_def ilike '%owner_display_name%' or position('banned_until' in v_def) = 0 then
    raise exception 'contract_text';
  end if;
  if position('public.is_platform_admin()' in pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure)) = 0
    or pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure) ilike '%platform_admins%'
    or pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure) ilike '%is_anonymous%'
    or pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure) ilike '%deleted_at%'
    or position('banned_until' in pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure)) = 0
    or position('unauthenticated' in pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure)) = 0
    or position('session_expired' in pg_get_functiondef('private.admin_subscriber_gate()'::regprocedure)) = 0 then
    raise exception 'gate_reuses_platform_admin';
  end if;
  if to_regclass('public.shops_registration_order_idx') is null then
    raise exception 'registration_index_missing';
  end if;

  if pg_temp.adm_call('anon', null, null, null, 'public.admin_list_subscribers_v1()') not like '%permission denied%' then
    raise exception 'anon_call';
  end if;
  if pg_temp.adm_call('authenticated', null, null, null, 'public.admin_list_subscribers_v1()') <> 'unauthenticated' then
    raise exception 'missing_user';
  end if;
  if pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000b1', null, '{"user_metadata":{"is_platform_admin":true},"app_metadata":{"role":"platform_admin"}}', 'public.admin_list_subscribers_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000c1', null, null, 'public.admin_list_subscribers_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000d1', null, null, 'public.admin_list_subscribers_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000e1', null, null, 'public.admin_list_subscribers_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000f1', null, null, 'public.admin_list_subscribers_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000a2', null, null, 'public.admin_list_subscribers_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000a3', null, '{"sub":"a1000000-0000-4000-8000-0000000000a3","user_metadata":{"is_platform_admin":true}}', 'public.admin_list_subscribers_v1()') <> 'forbidden' then
    raise exception 'denied_role';
  end if;
  if pg_temp.adm_call('authenticated', v_admin, 'a1200000-0000-4000-8000-000000000002', null, 'public.admin_list_subscribers_v1()') <> 'session_expired'
    or pg_temp.adm_call('authenticated', v_admin, 'a1200000-0000-4000-8000-000000000099', null, 'public.admin_list_subscribers_v1()') <> 'session_expired' then
    raise exception 'session_boundary';
  end if;

  perform set_config('TimeZone', 'Africa/Cairo', true);
  v := pg_temp.adm_call('authenticated', v_admin, 'a1200000-0000-4000-8000-000000000001', null, 'public.admin_list_subscribers_v1(''all'','''',null,2)')::jsonb;
  perform set_config('TimeZone', 'UTC', true);
  v2 := pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',null,25)')::jsonb;
  if v = v2 then
    raise exception 'page_size_ignored';
  end if;
  if pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',null,25)')::jsonb
    <> pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',null,25)')::jsonb then
    raise exception 'unstable_snapshot';
  end if;

  if v->>'snapshot_at' is null
    or (v->>'snapshot_at')::timestamptz <> now()
    or jsonb_typeof(v->'counts'->'all') <> 'string'
    or v->'counts'->>'all' <> '8'
    or v->'counts'->>'active' <> '3'
    or v->'counts'->>'pending' <> '3'
    or v->'counts'->>'expired' <> '2'
    or v->>'filtered_count' <> '8'
    or jsonb_array_length(v->'rows') <> 2
    or v->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000001'
    or v->'rows'->1->>'shop_id' <> 'a1100000-0000-4000-8000-000000000002'
    or v->'rows'->0->>'subscription_status' <> 'active'
    or v->'rows'->1->>'subscription_status' <> 'pending'
    or v->'rows'->1->>'entitlement_starts_at' is null then
    raise exception 'first_page %', v;
  end if;
  v_first_cursor := v->>'next_cursor';
  if pg_catalog.char_length(v_first_cursor) <> 66
    or pg_catalog.array_length(pg_catalog.string_to_array(v_first_cursor, '|'), 1) <> 3
    or pg_catalog.split_part(v_first_cursor, '|', 1) <> 'v1' then
    raise exception 'cursor_shape %', v_first_cursor;
  end if;
  if (select array(select jsonb_object_keys(v) order by 1))
    <> array['counts','filtered_count','next_cursor','page_size','rows','snapshot_at']
    or (select array(select jsonb_object_keys(v->'rows'->0) order by 1))
    <> array['entitlement_expires_at','entitlement_starts_at','registered_at','shop_id','shop_name','subscription_status'] then
    raise exception 'response_keys';
  end if;
  if v::text like '%leak-adm01@example.test%'
    or v::text like '%+201099988877%'
    or v::text like '%اسم مالك سري%'
    or v::text like '%EG-GZ%'
    or v::text like '%Africa/Cairo%' then
    raise exception 'pii_leak';
  end if;

  v_cursor := v->>'next_cursor';
  perform set_config('TimeZone', 'Asia/Riyadh', true);
  v_page := pg_temp.adm_call('authenticated', v_admin, null, null,
    format('public.admin_list_subscribers_v1(''all'','''',%L,2)', v_cursor))::jsonb;
  perform set_config('TimeZone', 'UTC', true);
  if v_page->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000003'
    or v_page->'rows'->1->>'shop_id' <> 'a1100000-0000-4000-8000-000000000004'
    or v_page->'counts'->>'all' <> '8' then
    raise exception 'second_page %', v_page;
  end if;
  v_cursor := v_page->>'next_cursor';
  v_page := pg_temp.adm_call('authenticated', v_admin, null, null,
    format('public.admin_list_subscribers_v1(''all'','''',%L,2)', v_cursor))::jsonb;
  if v_page->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000005'
    or v_page->'rows'->1->>'shop_id' <> 'a1100000-0000-4000-8000-000000000006' then
    raise exception 'third_page %', v_page;
  end if;
  v_cursor := v_page->>'next_cursor';
  v_page := pg_temp.adm_call('authenticated', v_admin, null, null,
    format('public.admin_list_subscribers_v1(''all'','''',%L,2)', v_cursor))::jsonb;
  if v_page->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000007'
    or v_page->'rows'->1->>'shop_id' <> 'a1100000-0000-4000-8000-000000000008'
    or v_page->>'next_cursor' is not null then
    raise exception 'last_page %', v_page;
  end if;

  if pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''nope'','''',null,2)') <> 'invalid_status'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',null,0)') <> 'invalid_page_size'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',null,26)') <> 'invalid_page_size'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'',repeat(''ا'',121),null,2)') <> 'invalid_search'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'',E''سطر\n'',null,2)') <> 'invalid_search'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''nope'',2)') <> 'invalid_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|not-a-time|a1100000-0000-4000-8000-000000000001'',2)') <> 'invalid_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|2020-01-01 00:00:00.000000|a1100000-0000-4000-8000-000000000099'',2)') <> 'stale_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|2019-01-01 00:00:00.000000|a1100000-0000-4000-8000-000000000001'',2)') <> 'stale_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|2020-01-01 00:00:00.000000|a1100000-0000-4000-8000-000000000001|'',2)') <> 'invalid_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|2020-01-01 00:00:00.000000|a1100000-0000-4000-8000-000000000001|extra'',2)') <> 'invalid_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|2020-01-01 00:00:00.000000||a1100000-0000-4000-8000-000000000001'',2)') <> 'invalid_cursor'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',''v1|2020-13-01 00:00:00.000000|a1100000-0000-4000-8000-000000000001'',2)') <> 'invalid_cursor' then
    raise exception 'invalid_arguments';
  end if;

  v := pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''pending'','''',null,25)')::jsonb;
  select array_agg(item->>'shop_id' order by item->>'shop_id') into v_ids
  from jsonb_array_elements(v->'rows') as item;
  if v->>'filtered_count' <> '3' or v->'counts'->>'all' <> '8' or v->'counts'->>'pending' <> '3'
    or v_ids <> array[
      'a1100000-0000-4000-8000-000000000002',
      'a1100000-0000-4000-8000-000000000003',
      'a1100000-0000-4000-8000-000000000008'
    ] then
    raise exception 'pending_filter %', v;
  end if;
  if exists (
    select 1 from jsonb_array_elements(v->'rows') as item
    where item->>'subscription_status' <> 'pending'
  ) then
    raise exception 'pending_row_status';
  end if;

  v := pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'',''%_'',null,25)')::jsonb;
  if v->>'filtered_count' <> '1'
    or v->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000003'
    or v->'counts'->>'all' <> '8' then
    raise exception 'literal_wildcard %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'',''goldshop'',null,25)')::jsonb;
  if v->>'filtered_count' <> '1' or v->'rows'->0->>'shop_name' <> 'GoldShop' then
    raise exception 'case_fold %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'',''متجر ألف'',null,25)')::jsonb;
  if v->>'filtered_count' <> '2'
    or v->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000001'
    or v->'rows'->1->>'shop_id' <> 'a1100000-0000-4000-8000-000000000002' then
    raise exception 'duplicate_names %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_list_subscribers_v1(''all'',''a1100000-0000-4000-8000-000000000004'',null,25)')::jsonb;
  if v->>'filtered_count' <> '1' or v->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000004'
    or v->'rows'->0->>'subscription_status' <> 'expired' then
    raise exception 'uuid_search %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_list_subscribers_v1(''all'',''a1100000'',null,25)')::jsonb;
  if v->>'filtered_count' <> '0' or jsonb_array_length(v->'rows') <> 0 then
    raise exception 'partial_uuid %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_list_subscribers_v1(''all'',''a1100000-0000-4000-8000-00000000000g'',null,25)')::jsonb;
  if v->>'filtered_count' <> '0' or jsonb_array_length(v->'rows') <> 0 then
    raise exception 'guarded_uuid_cast %', v;
  end if;

  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000003'')')::jsonb;
  if v->>'subscription_status' <> 'pending'
    or v->>'entitlement_starts_at' is not null
    or v->>'entitlement_expires_at' is not null
    or v->>'shop_name' <> 'خصم 100%_عرض' then
    raise exception 'missing_term %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000002'')')::jsonb;
  if v->>'subscription_status' <> 'pending' or v->>'entitlement_starts_at' is null then
    raise exception 'future_term %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000005'')')::jsonb;
  if v->>'subscription_status' <> 'active' then
    raise exception 'exact_start %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000004'')')::jsonb;
  if v->>'subscription_status' <> 'expired' then
    raise exception 'exact_expiry %', v;
  end if;
  v := pg_temp.adm_call('authenticated', v_admin, null, null,
    'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000007'')')::jsonb;
  if v::text like '%leak-adm01@example.test%' or v::text like '%اسم مالك سري%' or v->>'subscription_status' <> 'expired' then
    raise exception 'detail_pii %', v;
  end if;
  if pg_temp.adm_call('authenticated', v_admin, null, null,
      'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000099'')') <> 'not_found'
    or pg_temp.adm_call('authenticated', 'a1000000-0000-4000-8000-0000000000b1', null, null,
      'public.admin_get_subscriber_v1(''a1100000-0000-4000-8000-000000000001'')') <> 'forbidden' then
    raise exception 'detail_boundary';
  end if;

  if pg_temp.adm_call('authenticated', v_admin, null, null, 'public.list_financial_report_days_v1()') <> 'forbidden'
    or pg_temp.adm_call('authenticated', v_admin, null, null, 'public.get_customer_list_v3(null,null,null,null,null)') <> 'forbidden'
    or pg_temp.adm_call('authenticated', v_admin, null, null, '(select count(*) from public.list_my_shop_accounts())') <> '0' then
    raise exception 'shop_api_not_denied';
  end if;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', '', true);
  begin
    execute 'set local role authenticated';
    if (select count(*) from public.shops) <> 0 then
      raise exception 'admin_rls_shops';
    end if;
    execute 'reset role';
  exception
    when insufficient_privilege then
      null;
  end;
  execute 'reset role';
  begin
    execute 'set local role authenticated';
    update public.shop_entitlements set expires_at = expires_at + interval '1 day';
    raise exception 'entitlement_write_allowed';
  exception
    when insufficient_privilege or object_not_in_prerequisite_state then
      null;
    when others then
      if sqlerrm = 'entitlement_write_allowed' then
        raise;
      end if;
  end;
  execute 'reset role';

  if pg_temp.adm_digest() <> v_before then
    raise exception 'read_effect before=% after=%', v_before, pg_temp.adm_digest();
  end if;

  insert into public.shops (id, name, created_at) values
    ('a1100000-0000-4000-8000-000000000009', 'متجر سابق', timestamptz '2019-01-01 00:00:00+00'),
    ('a1100000-0000-4000-8000-000000000010', 'متجر لاحق', timestamptz '2021-01-01 00:00:00+00');
  v_page := pg_temp.adm_call('authenticated', v_admin, null, null,
    format('public.admin_list_subscribers_v1(''all'','''',%L,2)', v_first_cursor))::jsonb;
  if v_page->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000003'
    or v_page->'rows'->1->>'shop_id' <> 'a1100000-0000-4000-8000-000000000004'
    or v_page::text like '%000000000009%'
    or v_page::text like '%000000000010%'
    or v_page::text like '%000000000001%' then
    raise exception 'keyset_duplicate %', v_page;
  end if;
  v2 := pg_temp.adm_call('authenticated', v_admin, null, null, 'public.admin_list_subscribers_v1(''all'','''',null,2)')::jsonb;
  if v2->'rows'->0->>'shop_id' <> 'a1100000-0000-4000-8000-000000000009'
    or v2->'counts'->>'all' <> '10'
    or v2->'counts'->>'pending' <> '5' then
    raise exception 'refresh_sees_insert %', v2;
  end if;
end;
$test$;

rollback;

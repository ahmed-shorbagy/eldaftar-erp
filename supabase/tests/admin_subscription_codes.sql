-- Rollback-only ADM-02/ADM-08 issuance and history checks for a disposable
-- local database. Synthetic shops only. Issuance must not change entitlements.
begin;

do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_admin_subscription_codes_' then
    raise exception 'local_disposable_database_required';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
  raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until
) values
  ('c2000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm02-admin@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, now() - interval '1 day'),
  ('c2000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm02-owner@example.test', false, now(), now(),
    '{"is_platform_admin":true}'::jsonb, '{"role":"platform_admin"}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000c1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm02-staff@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000d1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm02-revoked@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000e1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm02-anon@example.test', true, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'adm02-deleted@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, now(), null),
  ('c2000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'adm02-banned@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, now() + interval '1 day'),
  ('c2000000-0000-4000-8000-0000000000a3', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'adm02-pretend@example.test', false, now(), now(),
    '{"is_platform_admin":true,"role":"platform_admin"}'::jsonb,
    '{"role":"platform_admin"}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000b2', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'adm02-foreign@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000b3', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'adm02-banned-owner@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, now() + interval '1 day'),
  ('c2000000-0000-4000-8000-0000000000b4', '00000000-0000-4000-8000-000000000000', 'authenticated', 'authenticated', 'adm02-expired-owner@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null),
  ('c2000000-0000-4000-8000-0000000000b5', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'adm02-history-owner@example.test', false, now(), now(),
    '{}'::jsonb, '{}'::jsonb, null, null);

insert into public.shops (id, name, created_at) values
  ('c2100000-0000-4000-8000-000000000001', 'متجر إصدار', timestamptz '2020-02-01 00:00:00+00'),
  ('c2100000-0000-4000-8000-000000000002', 'متجر تاريخ', timestamptz '2020-02-02 00:00:00+00'),
  ('c2100000-0000-4000-8000-000000000003', 'متجر أجنبي', timestamptz '2020-02-03 00:00:00+00'),
  ('c2100000-0000-4000-8000-000000000004', 'متجر مالك محظور', timestamptz '2020-02-04 00:00:00+00'),
  ('c2100000-0000-4000-8000-000000000005', 'متجر منتهٍ قابل للتجديد', timestamptz '2020-02-05 00:00:00+00');

insert into public.shops (
  id, name, owner_display_name, email, governorate_code, phone, time_zone, created_at
)
select
  'c2100000-0000-4000-8000-000000000006',
  'متجر ظاهر',
  'اسم مالك سري',
  'leak-adm02@example.test',
  'EG-GZ',
  private.registration_phone('+201099988866', 'EG-GZ'),
  private.registration_time_zone('EG-GZ'),
  timestamptz '2020-02-06 00:00:00+00';

insert into public.shop_memberships (shop_id, user_id, role) values
  ('c2100000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-0000000000b1', 'owner'),
  ('c2100000-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-0000000000b5', 'owner'),
  ('c2100000-0000-4000-8000-000000000003', 'c2000000-0000-4000-8000-0000000000b2', 'owner'),
  ('c2100000-0000-4000-8000-000000000004', 'c2000000-0000-4000-8000-0000000000b3', 'owner'),
  ('c2100000-0000-4000-8000-000000000005', 'c2000000-0000-4000-8000-0000000000b4', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('c2100000-0000-4000-8000-000000000002', now() - interval '10 days', now() + interval '10 days'),
  ('c2100000-0000-4000-8000-000000000005', now() - interval '40 days', now() - interval '1 day');

insert into public.platform_admins (user_id) values
  ('c2000000-0000-4000-8000-0000000000a1'),
  ('c2000000-0000-4000-8000-0000000000d1'),
  ('c2000000-0000-4000-8000-0000000000e1'),
  ('c2000000-0000-4000-8000-0000000000f1'),
  ('c2000000-0000-4000-8000-0000000000a2');
delete from public.platform_admins where user_id = 'c2000000-0000-4000-8000-0000000000d1';

insert into public.closing_staff_accounts (shop_id, user_id, display_name, phone, created_by) values
  ('c2100000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-0000000000c1', 'عدّاد', '+201000000021', 'c2000000-0000-4000-8000-0000000000b1');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('c2200000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('c2200000-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-0000000000a1', now(), now(), now() - interval '1 minute'),
  ('c2200000-0000-4000-8000-000000000003', 'c2000000-0000-4000-8000-0000000000b4', now(), now(), now() + interval '1 day'),
  ('c2200000-0000-4000-8000-000000000004', 'c2000000-0000-4000-8000-0000000000b3', now(), now(), now() + interval '1 day'),
  ('c2200000-0000-4000-8000-000000000005', 'c2000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day');

create function pg_temp.adm02_call(p_role text, p_user text, p_session text, p_claims text, p_sql text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claims', coalesce(p_claims, ''), true);
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

create function pg_temp.adm02_digest() returns text
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
  v_before text := pg_temp.adm02_digest();
  v_admin constant text := 'c2000000-0000-4000-8000-0000000000a1';
  v_session constant text := 'c2200000-0000-4000-8000-000000000001';
  v_shop constant text := 'c2100000-0000-4000-8000-000000000001';
  v_history_shop constant text := 'c2100000-0000-4000-8000-000000000002';
  v_owner constant text := 'c2000000-0000-4000-8000-0000000000b1';
  v_history_owner constant text := 'c2000000-0000-4000-8000-0000000000b5';
  v jsonb;
  v2 jsonb;
  v_code text;
  v_cursor text;
  v_ids uuid[];
  v_def text;
  v_status text;
  v_expires timestamptz;
  v_starts timestamptz;
  v_ent_before timestamptz;
  v_ent_after timestamptz;
  v_i integer;
begin
  if has_table_privilege('authenticated', 'private.subscription_codes', 'SELECT')
    or has_table_privilege('authenticated', 'private.subscription_code_attempts', 'SELECT')
    or has_table_privilege('anon', 'private.subscription_codes', 'SELECT')
    or has_table_privilege('authenticated', 'private.subscription_code_events', 'SELECT') then
    raise exception 'code_tables_exposed';
  end if;
  if has_function_privilege('anon', 'public.admin_list_subscription_codes_v1(uuid,text,integer)', 'execute')
    or has_function_privilege('authenticated', 'private.admin_list_subscription_codes_payload(uuid,timestamptz,uuid,integer)', 'execute')
    or has_function_privilege('authenticated', 'private.subscription_owner_session()', 'execute')
    or has_function_privilege('authenticated', 'private.subscription_session_live()', 'execute')
    or has_function_privilege('public', 'public.admin_list_subscription_codes_v1(uuid,text,integer)', 'execute') then
    raise exception 'execute_grant';
  end if;
  if not has_function_privilege('authenticated', 'public.admin_list_subscription_codes_v1(uuid,text,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.issue_subscription_code(uuid,integer,integer,uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.redeem_subscription_code(uuid,text)', 'execute') then
    raise exception 'authenticated_grant_missing';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role')
    and (
      has_function_privilege('service_role', 'public.admin_list_subscription_codes_v1(uuid,text,integer)', 'execute')
      or has_function_privilege('service_role', 'private.admin_list_subscription_codes_payload(uuid,timestamptz,uuid,integer)', 'execute')
    ) then
    raise exception 'service_role_history_grant';
  end if;
  if exists (select 1 from pg_roles where rolname = 'service_role')
    and not has_function_privilege('service_role', 'public.issue_subscription_code(uuid,integer,integer,uuid)', 'execute') then
    raise exception 'service_role_issue_grant_missing';
  end if;

  v_def := pg_get_functiondef('public.admin_list_subscription_codes_v1(uuid,text,integer)'::regprocedure)
    || pg_get_functiondef('private.admin_list_subscription_codes_payload(uuid,timestamptz,uuid,integer)'::regprocedure);
  if v_def ~* 'owner_user_id|issued_by|redeemed_by|code_hash|issue_request_key|redeemed_request_key|owner_display_name|governorate|email|phone' then
    raise exception 'history_selects_private_fields';
  end if;
  if pg_get_functiondef('public.issue_subscription_code(uuid,integer,integer,uuid)'::regprocedure)
    !~ 'subscription_platform_admin_session'
    or pg_get_functiondef('public.issue_subscription_code(uuid,integer,integer,uuid)'::regprocedure)
      !~ 'subscription_session_live' then
    raise exception 'issue_missing_admin_recheck';
  end if;
  if pg_get_functiondef('public.redeem_subscription_code(uuid,text)'::regprocedure)
    !~ 'subscription_owner_session'
    or pg_get_functiondef('public.redeem_subscription_code(uuid,text)'::regprocedure)
      !~ 'subscription_session_live' then
    raise exception 'redeem_missing_owner_recheck';
  end if;

  if pg_temp.adm02_call('anon', null, null, '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'unauthenticated|permission denied|unauthorized' then
    raise exception 'anon_history';
  end if;
  if pg_temp.adm02_call('authenticated', v_owner, null, '',
    $$public.issue_subscription_code('c2100000-0000-4000-8000-000000000001'::uuid, 30, 30, 'c2300000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'unauthorized|permission denied' then
    raise exception 'owner_issued_code';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000c1', null, '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'forbidden|permission denied' then
    raise exception 'staff_history';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000d1', null, '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'forbidden|permission denied' then
    raise exception 'revoked_admin_history';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000e1', null, '',
    $$public.issue_subscription_code('c2100000-0000-4000-8000-000000000001'::uuid, 30, 30, 'c2300000-0000-4000-8000-0000000000e1'::uuid)$$)
    !~ 'unauthorized|permission denied' then
    raise exception 'anon_admin_issue';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000f1', null, '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'forbidden|permission denied' then
    raise exception 'deleted_admin_history';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000a2', null, '',
    $$public.issue_subscription_code('c2100000-0000-4000-8000-000000000001'::uuid, 30, 30, 'c2300000-0000-4000-8000-0000000000a2'::uuid)$$)
    !~ 'unauthorized|permission denied' then
    raise exception 'banned_admin_issue';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000a2', null, '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'forbidden|permission denied' then
    raise exception 'banned_admin_history';
  end if;
  if pg_temp.adm02_call('authenticated', 'c2000000-0000-4000-8000-0000000000a3', null, '',
    $$public.issue_subscription_code('c2100000-0000-4000-8000-000000000001'::uuid, 30, 30, 'c2300000-0000-4000-8000-0000000000a3'::uuid)$$)
    !~ 'unauthorized|permission denied' then
    raise exception 'metadata_admin_issue';
  end if;
  if pg_temp.adm02_call('authenticated', v_admin, 'c2200000-0000-4000-8000-000000000002', '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000001'::uuid)$$)
    !~ 'session_expired|permission denied' then
    raise exception 'expired_session_history';
  end if;
  if pg_temp.adm02_call('authenticated', v_admin, 'c2200000-0000-4000-8000-000000000099', '',
    $$public.issue_subscription_code('c2100000-0000-4000-8000-000000000001'::uuid, 30, 30, 'c2300000-0000-4000-8000-000000000099'::uuid)$$)
    !~ 'unauthorized|permission denied' then
    raise exception 'unknown_session_issue';
  end if;
  if pg_temp.adm02_call('authenticated', v_admin, v_session, '',
    $$public.admin_list_subscription_codes_v1(null)$$)
    !~ 'invalid_shop' then
    raise exception 'null_shop_history';
  end if;

  select expires_at into v_ent_before
  from public.shop_entitlements
  where shop_id = 'c2100000-0000-4000-8000-000000000002';

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  select t.code, t.status, t.issued_via
    into v_code, v_status, v_def
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000001'::uuid, 30, 14,
    'c2300000-0000-4000-8000-000000000011'::uuid) as t;
  if v_status is distinct from 'issued'
    or v_code is null
    or length(v_code) <> 32
    or v_def is distinct from 'platform_admin' then
    raise exception 'typed_issue_failed';
  end if;
  if v_code !~ '^[A-F0-9]{32}$' then
    raise exception 'code_not_hex';
  end if;

  -- Missing session_id claim remains accepted for a live platform admin.
  perform set_config('request.jwt.claim.session_id', '', true);
  perform set_config('request.jwt.claims', '', true);
  select t.status into v_status
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000001'::uuid, 12, 10,
    'c2300000-0000-4000-8000-000000000018'::uuid) as t;
  if v_status is distinct from 'issued' then
    raise exception 'missing_claim_admin_issue_failed %', v_status;
  end if;
  perform set_config('request.jwt.claim.session_id', v_session, true);

  select t.status, t.code into v_status, v_def
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000001'::uuid, 30, 14,
    'c2300000-0000-4000-8000-000000000011'::uuid) as t;
  if v_status is distinct from 'replayed' or v_def is not null then
    raise exception 'issue_retry_revealed_code';
  end if;

  begin
    perform public.issue_subscription_code(
      'c2100000-0000-4000-8000-000000000001'::uuid, 60, 14,
      'c2300000-0000-4000-8000-000000000011'::uuid);
    raise exception 'issue_key_reused_accepted';
  exception when unique_violation then null;
  end;
  begin
    perform public.issue_subscription_code(
      'c2100000-0000-4000-8000-000000000001'::uuid, 30, 30,
      'c2300000-0000-4000-8000-000000000011'::uuid);
    raise exception 'changed_ttl_replay_accepted';
  exception when unique_violation then null;
  end;
  begin
    perform public.issue_subscription_code(
      'c2100000-0000-4000-8000-000000000001'::uuid, 0, 30,
      'c2300000-0000-4000-8000-000000000012'::uuid);
    raise exception 'zero_duration_accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.issue_subscription_code(
      'c2100000-0000-4000-8000-000000000001'::uuid, 3661, 30,
      'c2300000-0000-4000-8000-000000000013'::uuid);
    raise exception 'overlong_duration_accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.issue_subscription_code(
      'c2100000-0000-4000-8000-000000000001'::uuid, 30, 366,
      'c2300000-0000-4000-8000-000000000014'::uuid);
    raise exception 'overlong_ttl_accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.issue_subscription_code(
      'c2100000-0000-4000-8000-000000000001'::uuid, 30, 30,
      'c2300000-0000-5000-8000-000000000015'::uuid);
    raise exception 'non_v4_key_accepted';
  exception when invalid_parameter_value then null;
  end;
  reset role;

  select expires_at into v_ent_after
  from public.shop_entitlements
  where shop_id = 'c2100000-0000-4000-8000-000000000002';
  if v_ent_before is distinct from v_ent_after then
    raise exception 'issuance_changed_entitlement';
  end if;
  if exists (
    select 1 from public.shop_entitlements
    where shop_id = 'c2100000-0000-4000-8000-000000000001'
  ) then
    raise exception 'issuance_created_entitlement';
  end if;
  if pg_temp.adm02_digest() is distinct from v_before then
    raise exception 'issuance_changed_finance_digest';
  end if;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.session_id', '', true);
  set local role service_role;
  select t.status, t.issued_via, t.code into v_status, v_def, v_code
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000001'::uuid, 10, 7,
    'c2300000-0000-4000-8000-000000000199'::uuid) as t;
  if v_status is distinct from 'issued' or v_def is distinct from 'service_role' or v_code is null then
    raise exception 'service_role_issue_failed';
  end if;
  reset role;
  if exists (
    select 1 from private.subscription_codes
    where issue_request_key = 'c2300000-0000-4000-8000-000000000199'
      and issued_by is not null
  ) then
    raise exception 'service_role_misattributed';
  end if;

  insert into private.subscription_codes (
    id, code_hash, shop_id, owner_user_id, duration_days, code_ttl_days, code_expires_at,
    issued_at, issued_by, issued_via, issue_request_key
  ) values
    (
      'c2400000-0000-4000-8000-000000000001',
      private.subscription_code_hash('11111111111111111111111111111111'),
      v_history_shop::uuid, v_history_owner::uuid, 30, 30, clock_timestamp() + interval '7 days',
      timestamptz '2020-03-01 00:00:00.111111+00', v_admin::uuid, 'platform_admin',
      'c2300000-0000-4000-8000-000000000201'
    ),
    (
      'c2400000-0000-4000-8000-000000000002',
      private.subscription_code_hash('22222222222222222222222222222222'),
      v_history_shop::uuid, v_history_owner::uuid, 60, 14, clock_timestamp() - interval '1 second',
      timestamptz '2020-03-02 00:00:00.222222+00', v_admin::uuid, 'platform_admin',
      'c2300000-0000-4000-8000-000000000202'
    ),
    (
      'c2400000-0000-4000-8000-000000000003',
      private.subscription_code_hash('33333333333333333333333333333333'),
      v_history_shop::uuid, v_history_owner::uuid, 90, 30, clock_timestamp() + interval '7 days',
      timestamptz '2020-03-03 00:00:00.333333+00', v_admin::uuid, 'platform_admin',
      'c2300000-0000-4000-8000-000000000203'
    ),
    (
      'c2400000-0000-4000-8000-000000000004',
      private.subscription_code_hash('44444444444444444444444444444444'),
      v_history_shop::uuid, v_history_owner::uuid, 15, 30, pg_catalog.now(),
      timestamptz '2020-03-04 00:00:00.444444+00', v_admin::uuid, 'platform_admin',
      'c2300000-0000-4000-8000-000000000204'
    );
  update private.subscription_codes
    set redeemed_at = timestamptz '2020-03-10 00:00:00+00',
        redeemed_by = v_history_owner::uuid,
        redeemed_request_key = 'c2500000-0000-4000-8000-000000000001'
    where id = 'c2400000-0000-4000-8000-000000000003';

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  v := public.admin_list_subscription_codes_v1(v_history_shop::uuid, null, 2);
  if v->>'shop_id' is distinct from v_history_shop
    or v->>'shop_name' is distinct from 'متجر تاريخ'
    or v->>'row_count' is distinct from '4'
    or jsonb_array_length(v->'rows') <> 2 then
    raise exception 'history_page_failed %', v;
  end if;
  if v::text ~* '11111111|22222222|code_hash|owner_user_id|issued_by|redeemed_by|leak-adm02|اسم مالك|201099988866' then
    raise exception 'history_leaked_secret';
  end if;
  if (v->'rows'->0->>'code_status') is distinct from 'expired'
    or (v->'rows'->1->>'code_status') is distinct from 'redeemed' then
    raise exception 'history_status_order %', v->'rows';
  end if;
  v_cursor := v->>'next_cursor';
  if v_cursor is null or char_length(v_cursor) <> 66 then
    raise exception 'history_cursor_missing';
  end if;
  v2 := public.admin_list_subscription_codes_v1(v_history_shop::uuid, v_cursor, 2);
  if jsonb_array_length(v2->'rows') <> 2 then
    raise exception 'history_second_page %', v2;
  end if;
  if (v2->'rows'->0->>'id') = (v->'rows'->0->>'id')
    or (v2->'rows'->0->>'id') = (v->'rows'->1->>'id') then
    raise exception 'history_page_overlap';
  end if;
  if (v2->'rows'->0->>'code_status') is distinct from 'expired'
    or (v2->'rows'->1->>'code_status') is distinct from 'unused' then
    raise exception 'history_older_status %', v2->'rows';
  end if;
  begin
    perform public.admin_list_subscription_codes_v1(v_history_shop::uuid, v_cursor || '|x', 2);
    raise exception 'bad_cursor_accepted';
  exception when invalid_parameter_value then null;
  end;
  begin
    perform public.admin_list_subscription_codes_v1(v_history_shop::uuid, null, 26);
    raise exception 'oversize_page_accepted';
  exception when invalid_parameter_value then null;
  end;
  reset role;
  if pg_temp.adm02_call('authenticated', v_admin, v_session, '',
    $$public.admin_list_subscription_codes_v1('c2100000-0000-4000-8000-000000000099'::uuid)$$)
    !~ 'not_found' then
    raise exception 'missing_shop_history';
  end if;

  -- History for shop 1 must not include shop 2 rows.
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  v := public.admin_list_subscription_codes_v1(v_shop::uuid, null, 25);
  if v->>'shop_id' is distinct from v_shop then
    raise exception 'history_wrong_shop';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v->'rows') as row
    where row->>'id' like 'c2400000%'
  ) then
    raise exception 'history_crossed_shops';
  end if;
  reset role;

  -- Banned owner cannot redeem. Expired D13 owner can redeem.
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  select t.code into v_code
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000004'::uuid, 30, 30,
    'c2300000-0000-4000-8000-000000000301'::uuid) as t;
  reset role;
  if pg_temp.adm02_call(
    'authenticated',
    'c2000000-0000-4000-8000-0000000000b3',
    'c2200000-0000-4000-8000-000000000004',
    '',
    format(
      $sql$public.redeem_subscription_code('c2500000-0000-4000-8000-000000000301'::uuid, %L)$sql$,
      v_code
    )
  ) !~ 'unauthorized|permission denied' then
    raise exception 'banned_owner_redeemed';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  select t.code into v_code
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000005'::uuid, 30, 30,
    'c2300000-0000-4000-8000-000000000302'::uuid) as t;
  perform set_config('request.jwt.claim.sub', 'c2000000-0000-4000-8000-0000000000b4', true);
  perform set_config('request.jwt.claim.session_id', 'c2200000-0000-4000-8000-000000000003', true);
  select t.status, t.expires_at into v_status, v_expires
  from public.redeem_subscription_code(
    'c2500000-0000-4000-8000-000000000302'::uuid, v_code) as t;
  if v_status is distinct from 'activated' or v_expires <= clock_timestamp() then
    raise exception 'expired_owner_renewal_failed %', v_status;
  end if;
  reset role;

  -- Owner redeem of the first issued unused code.
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  select t.code into v_code
  from public.issue_subscription_code(
    'c2100000-0000-4000-8000-000000000001'::uuid, 20, 30,
    'c2300000-0000-4000-8000-000000000303'::uuid) as t;
  perform set_config('request.jwt.claim.sub', v_owner, true);
  perform set_config('request.jwt.claim.session_id', 'c2200000-0000-4000-8000-000000000005', true);
  select t.status, t.starts_at, t.expires_at into v_status, v_starts, v_expires
  from public.redeem_subscription_code(
    'c2500000-0000-4000-8000-000000000303'::uuid, v_code) as t;
  if v_status is distinct from 'activated' then
    raise exception 'owner_activation_failed %', v_status;
  end if;
  select t.status into v_status
  from public.redeem_subscription_code(
    'c2500000-0000-4000-8000-000000000303'::uuid, v_code) as t;
  if v_status is distinct from 'replayed' then
    raise exception 'owner_replay_failed %', v_status;
  end if;
  reset role;

  if pg_temp.adm02_call('authenticated', v_admin, v_session, '',
      $$public.list_financial_report_days_v1()$$) <> 'forbidden'
    or pg_temp.adm02_call('authenticated', v_admin, v_session, '',
      $$public.get_customer_list_v3(null,null,null,null,null)$$) <> 'forbidden' then
    raise exception 'admin_financial_access';
  end if;
end;
$test$;

reset role;
rollback;

-- Rollback-only checks for subscription-code revocation and history v2
-- (ADR 0048). Synthetic users, shops and codes exist only inside this
-- transaction. Hosted execution must set the transaction-local
-- eldaftar.test_project_ref to the development project right after `begin`.
begin isolation level repeatable read;

do $guard$
begin
  if not coalesce((
    (inet_server_addr() = '127.0.0.1'::inet
      and current_database() ~ '^eldaftar_code_revocation_')
    or current_setting('eldaftar.test_project_ref', true) = 'xchapwvmvoefriqcxtvn'
  ), false) then
    raise exception 'explicit_development_or_local_test_target_required';
  end if;
  if to_regprocedure('public.admin_revoke_subscription_code_v1(uuid,text,uuid)') is null then
    raise exception 'revocation_migration_missing';
  end if;
end;
$guard$;

-- 1 admin, 2 owner of shop 1, 3 banned admin, 4 owner of shop 2
insert into auth.users
  (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
   raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until)
select ('e4800000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'revoke-hosted-' || n || '@example.test', false, now(), now(),
  '{}'::jsonb, '{}'::jsonb, null,
  case when n = 3 then now() + interval '1 day' else null end
from generate_series(1, 4) n;

insert into public.shops (id, name, created_at)
select ('e4830000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'تحقق_إلغاء_الرموز_' || n,
  timestamptz '2020-05-01 00:00:00.123456+00'
from generate_series(1, 2) n;

insert into public.shop_memberships (shop_id, user_id, role) values
  ('e4830000-0000-4000-8000-000000000001', 'e4800000-0000-4000-8000-000000000002', 'owner'),
  ('e4830000-0000-4000-8000-000000000002', 'e4800000-0000-4000-8000-000000000004', 'owner');

insert into public.platform_admins (user_id) values
  ('e4800000-0000-4000-8000-000000000001'),
  ('e4800000-0000-4000-8000-000000000003');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e4820000-0000-4000-8000-000000000001', 'e4800000-0000-4000-8000-000000000001', now(), now(), now() + interval '1 day'),
  ('e4820000-0000-4000-8000-000000000002', 'e4800000-0000-4000-8000-000000000001', now(), now(), now() - interval '1 second');

create function pg_temp.rv_call(p_user text, p_session text, p_sql text,
  p_role text default 'authenticated') returns text language plpgsql as $fn$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claims', '', true);
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

create function pg_temp.rv_issue(p_shop text, p_days integer, p_key text)
returns text language plpgsql as $fn$
declare v_code text;
begin
  perform set_config('request.jwt.claim.sub', 'e4800000-0000-4000-8000-000000000001', true);
  perform set_config('request.jwt.claim.session_id', 'e4820000-0000-4000-8000-000000000001', true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  select t.code into v_code
  from public.issue_subscription_code(p_shop::uuid, p_days, 30, p_key::uuid) as t;
  reset role;
  return v_code;
end;
$fn$;

do $checks$
declare
  v_admin constant text := 'e4800000-0000-4000-8000-000000000001';
  v_session constant text := 'e4820000-0000-4000-8000-000000000001';
  v_owner constant text := 'e4800000-0000-4000-8000-000000000002';
  v_shop constant text := 'e4830000-0000-4000-8000-000000000001';
  v_code_a text;
  v_code_b text;
  v_id_a uuid;
  v_id_b uuid;
  v_id_c uuid;
  v_ent_expires timestamptz;
  v jsonb;
  v_text text;
begin
  if has_function_privilege('anon', 'public.admin_revoke_subscription_code_v1(uuid,text,uuid)', 'execute')
    or has_function_privilege('anon', 'public.admin_list_subscription_codes_v2(uuid,text,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_revoke_subscription_code_v1(uuid,text,uuid)', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_list_subscription_codes_v2(uuid,text,integer)', 'execute')
    or has_table_privilege('authenticated', 'private.subscription_codes', 'select') then
    raise exception 'grants';
  end if;

  v_code_a := pg_temp.rv_issue(v_shop, 30, 'e4840000-0000-4000-8000-00000000000a');
  v_code_b := pg_temp.rv_issue(v_shop, 90, 'e4840000-0000-4000-8000-00000000000b');
  perform pg_temp.rv_issue(v_shop, 180, 'e4840000-0000-4000-8000-00000000000c');
  select id into v_id_a from private.subscription_codes where issue_request_key = 'e4840000-0000-4000-8000-00000000000a';
  select id into v_id_b from private.subscription_codes where issue_request_key = 'e4840000-0000-4000-8000-00000000000b';
  select id into v_id_c from private.subscription_codes where issue_request_key = 'e4840000-0000-4000-8000-00000000000c';
  if v_code_a is null or v_code_b is null or v_id_a is null or v_id_b is null or v_id_c is null then
    raise exception 'fixture_issue';
  end if;
  -- Code C's validity has already passed (backdated, because history
  -- classifies with transaction-start now()).
  update private.subscription_codes
    set issued_at = now() - interval '2 days',
        code_expires_at = now() - interval '1 day'
    where id = v_id_c;

  -- Boundaries: anonymous, owner, banned admin, expired session.
  if pg_temp.rv_call(null, null, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب كافٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%unauthorized%'
    or pg_temp.rv_call(null, null, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب كافٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a), 'anon')
      not like '%permission denied%'
    or pg_temp.rv_call(v_owner, null, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب كافٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%unauthorized%'
    or pg_temp.rv_call('e4800000-0000-4000-8000-000000000003', null, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب كافٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%unauthorized%'
    or pg_temp.rv_call(v_admin, 'e4820000-0000-4000-8000-000000000002', format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب كافٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%unauthorized%'
    or pg_temp.rv_call(v_owner, null, format('public.admin_list_subscription_codes_v2(%L::uuid)', v_shop)) <> 'forbidden' then
    raise exception 'boundaries';
  end if;
  if (select revoked_at from private.subscription_codes where id = v_id_a) is not null then
    raise exception 'denied_call_wrote';
  end if;

  -- Validation.
  if pg_temp.rv_call(v_admin, v_session, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''  ab '', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%invalid_input%'
    or pg_temp.rv_call(v_admin, v_session, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, E''سطر\nثانٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%invalid_input%'
    or pg_temp.rv_call(v_admin, v_session, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب كافٍ'', ''e4840000-0000-1000-8000-000000000101''::uuid)', v_id_a))
      not like '%invalid_input%'
    or pg_temp.rv_call(v_admin, v_session,
      'public.admin_revoke_subscription_code_v1(''e4890000-0000-4000-8000-000000000001''::uuid, ''سبب كافٍ'', ''e4840000-0000-4000-8000-000000000101''::uuid)')
      not like '%not_found%' then
    raise exception 'validation';
  end if;

  -- Revoke A, replay, key reuse, second key.
  v := pg_temp.rv_call(v_admin, v_session, format(
    'public.admin_revoke_subscription_code_v1(%L::uuid, ''أُرسل إلى رقم خطأ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))::jsonb;
  if v->>'status' <> 'revoked' or v->>'shop_id' <> v_shop or v->>'revoked_at' is null then
    raise exception 'revoke %', v;
  end if;
  v := pg_temp.rv_call(v_admin, v_session, format(
    'public.admin_revoke_subscription_code_v1(%L::uuid, ''أُرسل إلى رقم خطأ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))::jsonb;
  if v->>'status' <> 'replayed' then raise exception 'replay %', v; end if;
  if pg_temp.rv_call(v_admin, v_session, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''سبب مختلف'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_a))
      not like '%request_key_reused%'
    or pg_temp.rv_call(v_admin, v_session, format(
      'public.admin_revoke_subscription_code_v1(%L::uuid, ''أُرسل إلى رقم خطأ'', ''e4840000-0000-4000-8000-000000000101''::uuid)', v_id_b))
      not like '%request_key_reused%' then
    raise exception 'key_reuse';
  end if;
  v := pg_temp.rv_call(v_admin, v_session, format(
    'public.admin_revoke_subscription_code_v1(%L::uuid, ''مرة ثانية'', ''e4840000-0000-4000-8000-000000000102''::uuid)', v_id_a))::jsonb;
  if v->>'status' <> 'already_revoked' then raise exception 'already_revoked %', v; end if;
  if (select count(*) from private.subscription_code_events
      where action = 'subscription_code_revoked' and correlation_id = 'e4840000-0000-4000-8000-000000000101') <> 1
    or (select count(*) from private.subscription_code_events
      where action = 'subscription_code_revoked' and shop_id = v_shop::uuid) <> 1 then
    raise exception 'revoke_event_count';
  end if;

  -- The owner cannot redeem a revoked code; no entitlement is created.
  v_text := pg_temp.rv_call(v_owner, null, format(
    '(select t.status from public.redeem_subscription_code(''e4840000-0000-4000-8000-000000000201''::uuid, %L) as t)', v_code_a));
  if v_text <> 'expired_code' then raise exception 'redeem_revoked %', v_text; end if;
  if exists (select 1 from public.shop_entitlements where shop_id = v_shop::uuid) then
    raise exception 'revoked_code_activated';
  end if;

  -- Redeemed code: revocation refused and the term stays.
  v_text := pg_temp.rv_call(v_owner, null, format(
    '(select t.status from public.redeem_subscription_code(''e4840000-0000-4000-8000-000000000202''::uuid, %L) as t)', v_code_b));
  if v_text <> 'activated' then raise exception 'redeem_b %', v_text; end if;
  select expires_at into v_ent_expires from public.shop_entitlements where shop_id = v_shop::uuid;
  v := pg_temp.rv_call(v_admin, v_session, format(
    'public.admin_revoke_subscription_code_v1(%L::uuid, ''بعد الاستخدام'', ''e4840000-0000-4000-8000-000000000103''::uuid)', v_id_b))::jsonb;
  if v->>'status' <> 'redeemed'
    or (select expires_at from public.shop_entitlements where shop_id = v_shop::uuid) <> v_ent_expires
    or (select revoked_at from private.subscription_codes where id = v_id_b) is not null then
    raise exception 'revoke_redeemed %', v;
  end if;

  -- Expired code: refused, nothing written.
  v := pg_temp.rv_call(v_admin, v_session, format(
    'public.admin_revoke_subscription_code_v1(%L::uuid, ''انتهت صلاحيته'', ''e4840000-0000-4000-8000-000000000104''::uuid)', v_id_c))::jsonb;
  if v->>'status' <> 'expired' or (select revoked_at from private.subscription_codes where id = v_id_c) is not null then
    raise exception 'revoke_expired %', v;
  end if;

  -- History v2 statuses and keys; v1 unchanged.
  v := pg_temp.rv_call(v_admin, v_session, format('public.admin_list_subscription_codes_v2(%L::uuid)', v_shop))::jsonb;
  if v->>'row_count' <> '3'
    or array(select jsonb_object_keys(v->'rows'->0) order by 1) <>
      array['code_expires_at','code_status','code_ttl_days','duration_days','id','issued_at','issued_via','redeemed_at','revoke_reason','revoked_at']
    or (select r->>'code_status' from jsonb_array_elements(v->'rows') r where r->>'id' = v_id_a::text) <> 'revoked'
    or (select r->>'revoke_reason' from jsonb_array_elements(v->'rows') r where r->>'id' = v_id_a::text) <> 'أُرسل إلى رقم خطأ'
    or (select r->>'code_status' from jsonb_array_elements(v->'rows') r where r->>'id' = v_id_b::text) <> 'redeemed'
    or (select r->>'code_status' from jsonb_array_elements(v->'rows') r where r->>'id' = v_id_c::text) <> 'expired'
    or v::text ~* 'code_hash|owner_user_id|revoked_by|revoke_request_key' then
    raise exception 'history_v2 %', v;
  end if;
  v := pg_temp.rv_call(v_admin, v_session, format('public.admin_list_subscription_codes_v1(%L::uuid)', v_shop))::jsonb;
  if array(select jsonb_object_keys(v->'rows'->0) order by 1) <>
      array['code_expires_at','code_status','code_ttl_days','duration_days','id','issued_at','issued_via','redeemed_at']
    -- v1 sees the clamped validity; in a later transaction it reads expired.
    or (select (r->>'code_expires_at')::timestamptz from jsonb_array_elements(v->'rows') r where r->>'id' = v_id_a::text)
      <> (select revoked_at from private.subscription_codes where id = v_id_a) then
    raise exception 'history_v1 %', v;
  end if;

  -- Audit browser lists the revocation with its reason.
  v := pg_temp.rv_call(v_admin, v_session, format(
    'public.admin_list_audit_events_v1(''codes'', %L::uuid, null, 50)', v_admin))::jsonb;
  if (select count(*) from jsonb_array_elements(v->'rows') r where r->>'action' = 'subscription_code_revoked') <> 1
    or (select count(*) from jsonb_array_elements(v->'rows') r where r->>'action' = 'subscription_code_issued') <> 3
    or (select r->'details'->>'reason' from jsonb_array_elements(v->'rows') r
        where r->>'action' = 'subscription_code_revoked') <> 'أُرسل إلى رقم خطأ'
    or (select r->>'shop_id' from jsonb_array_elements(v->'rows') r
        where r->>'action' = 'subscription_code_revoked') <> v_shop then
    raise exception 'audit %', v;
  end if;
end;
$checks$;

select 'SUBSCRIPTION_CODE_REVOCATION_HOSTED_PASSED' as result;

rollback;

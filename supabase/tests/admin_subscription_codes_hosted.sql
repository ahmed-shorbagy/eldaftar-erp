-- Rollback-only ADM-02/ADM-08 hosted role/behavior checks.
-- Local runner accepts only its disposable database prefix. Hosted execution
-- must pin the connector to xchapwvmvoefriqcxtvn and set the transaction-local
-- eldaftar.test_project_ref to that exact development project before the guard.
begin isolation level repeatable read;

do $guard$
begin
  if not coalesce((
    (inet_server_addr() = '127.0.0.1'::inet
      and current_database() ~ '^eldaftar_admin_subscription_codes_')
    or current_setting('eldaftar.test_project_ref', true) = 'xchapwvmvoefriqcxtvn'
  ), false) then
    raise exception 'explicit_development_or_local_test_target_required';
  end if;
end;
$guard$;

create temporary table adm02_hosted_baseline on commit drop as
select
  (select count(*) from public.shop_entitlements) as entitlement_count,
  (select count(*) from public.shops) as shop_count,
  (select count(*) from public.identity_audit_events) as identity_audit_count,
  (select count(*) from private.subscription_codes) as code_count;

insert into auth.users
  (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
   raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until)
select ('e4100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'adm02-hosted-' || n || '@example.test', n = 5, now(), now(),
  '{"is_platform_admin":true}'::jsonb, '{}'::jsonb,
  case when n = 6 then now() else null end,
  case when n = 4 then now() + interval '1 day' else null end
from generate_series(1, 7) n;

insert into public.shops (id, name, created_at)
select ('e4300000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'تحقق_رموز_٢٠٢٦١٠٢٢_' || n,
  timestamptz '2020-05-01 00:00:00.123456+00'
from generate_series(1, 2) n;

insert into public.shop_memberships (shop_id, user_id, role) values
  ('e4300000-0000-4000-8000-000000000001',
   'e4100000-0000-4000-8000-000000000002', 'owner'),
  ('e4300000-0000-4000-8000-000000000002',
   'e4100000-0000-4000-8000-000000000007', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('e4300000-0000-4000-8000-000000000002', now() - interval '2 days', now() + interval '2 days');

insert into public.platform_admins (user_id)
select ('e4100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
from unnest(array[1, 4, 5, 6]) n;

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e4200000-0000-4000-8000-000000000001', 'e4100000-0000-4000-8000-000000000001', now(), now(), now() + interval '1 day'),
  ('e4200000-0000-4000-8000-000000000002', 'e4100000-0000-4000-8000-000000000001', now(), now(), now() - interval '1 second');

create function pg_temp.adm02_hosted_call(p_user text, p_session text, p_sql text,
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

do $checks$
declare
  v_admin constant text := 'e4100000-0000-4000-8000-000000000001';
  v_session constant text := 'e4200000-0000-4000-8000-000000000001';
  v_shop constant text := 'e4300000-0000-4000-8000-000000000001';
  v jsonb;
  v_code text;
  v_status text;
  v_base record;
  v_user text;
  v_ent_before integer;
begin
  select * into v_base from adm02_hosted_baseline;
  v_ent_before := (select count(*) from public.shop_entitlements);

  if pg_temp.adm02_hosted_call(null, null, format(
      'public.admin_list_subscription_codes_v1(%L::uuid)', v_shop)) <> 'unauthenticated'
    or pg_temp.adm02_hosted_call(null, null, format(
      'public.admin_list_subscription_codes_v1(%L::uuid)', v_shop), 'anon') not like '%permission denied%'
  then raise exception 'hosted_unauthenticated'; end if;

  foreach v_user in array array[
    'e4100000-0000-4000-8000-000000000002',
    'e4100000-0000-4000-8000-000000000004',
    'e4100000-0000-4000-8000-000000000005',
    'e4100000-0000-4000-8000-000000000006',
    'e4100000-0000-4000-8000-000000000007'] loop
    if pg_temp.adm02_hosted_call(v_user, null, format(
        'public.admin_list_subscription_codes_v1(%L::uuid)', v_shop)) <> 'forbidden'
      or pg_temp.adm02_hosted_call(v_user, null, format(
        $sql$public.issue_subscription_code(%L::uuid, 30, 30, 'e4400000-0000-4000-8000-000000000001'::uuid)$sql$, v_shop
      )) not like '%unauthorized%'
    then raise exception 'hosted_role_boundary %', v_user; end if;
  end loop;

  if pg_temp.adm02_hosted_call(v_admin, 'e4200000-0000-4000-8000-000000000002',
      format('public.admin_list_subscription_codes_v1(%L::uuid)', v_shop)) <> 'session_expired'
    or pg_temp.adm02_hosted_call(v_admin, 'e4200000-0000-4000-8000-000000000099',
      format('public.issue_subscription_code(%L::uuid, 30, 30, ''e4400000-0000-4000-8000-000000000099''::uuid)', v_shop)
    ) not like '%unauthorized%'
  then raise exception 'hosted_session_boundary'; end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', v_admin, true);
  perform set_config('request.jwt.claim.session_id', v_session, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  select t.code, t.status into v_code, v_status
  from public.issue_subscription_code(
    v_shop::uuid, 21, 12, 'e4400000-0000-4000-8000-000000000010'::uuid) as t;
  if v_status is distinct from 'issued' or v_code is null or length(v_code) <> 32 then
    raise exception 'hosted_issue_failed';
  end if;
  select t.status, t.code into v_status, v_code
  from public.issue_subscription_code(
    v_shop::uuid, 21, 12, 'e4400000-0000-4000-8000-000000000010'::uuid) as t;
  if v_status is distinct from 'replayed' or v_code is not null then
    raise exception 'hosted_replay_revealed';
  end if;
  v := public.admin_list_subscription_codes_v1(v_shop::uuid, null, 20);
  reset role;
  if v->>'shop_id' is distinct from v_shop
    or v->>'row_count' is distinct from '1'
    or jsonb_array_length(v->'rows') <> 1
    or v->'rows'->0->>'code_status' is distinct from 'unused'
    or v->'rows'->0->>'duration_days' is distinct from '21'
    or array(select jsonb_object_keys(v->'rows'->0) order by 1) <>
      array['code_expires_at','code_status','code_ttl_days','duration_days','id','issued_at','issued_via','redeemed_at']
  then raise exception 'hosted_history_allowlist %', v; end if;
  if v::text ~* 'e4400000-0000-4000-8000-000000000010|code_hash|owner_user_id|issued_by|redeemed_by' then
    raise exception 'hosted_history_secret';
  end if;
  if (select count(*) from public.shop_entitlements) <> v_ent_before then
    raise exception 'hosted_issuance_changed_entitlements';
  end if;
  if (select shop_count from adm02_hosted_baseline) + 2
      <> (select count(*) from public.shops)
    or (select entitlement_count from adm02_hosted_baseline) + 1
      <> (select count(*) from public.shop_entitlements)
  then raise exception 'hosted_fixture_counts'; end if;
end;
$checks$;

rollback;

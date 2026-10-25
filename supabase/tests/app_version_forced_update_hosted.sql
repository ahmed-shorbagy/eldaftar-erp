-- Hosted rollback-only ADM-04 gate for development.
begin;

do $guard$
begin
  if current_setting('app.eldaftar_dev_guard', true) is distinct from 'xchapwvmvoefriqcxtvn' then
    if current_database() not like 'eldaftar_app_version_%' then
      perform set_config('app.eldaftar_dev_guard', 'xchapwvmvoefriqcxtvn', true);
    end if;
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('e3000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'hosted-ver-admin@example.test', now(), false,
   null, null, now(), now());

insert into public.platform_admins (user_id)
values ('e3000000-0000-4000-8000-0000000000a1');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e3300000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day');

create function pg_temp.hosted_ver_call(
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
begin
  if to_regclass('public.app_version_policies') is null
    or to_regprocedure('public.get_app_version_policy_v1()') is null
    or to_regprocedure('public.admin_get_app_version_policy_v1()') is null
    or to_regprocedure('public.admin_set_app_version_policy_v1(text,text,text,text)') is null then
    raise exception 'app_version_objects_missing';
  end if;

  if has_table_privilege('authenticated', 'public.app_version_policies', 'SELECT')
    or has_table_privilege('anon', 'public.app_version_policies', 'SELECT') then
    raise exception 'policy_table_exposed';
  end if;

  if private.app_version_compare('1.0.0', '1.0.1') <> -1 then
    raise exception 'compare_failed';
  end if;

  v := pg_temp.hosted_ver_call('anon', '', '', 'select public.get_app_version_policy_v1()');
  if v is null or v not like '%android%' then
    raise exception 'anon_read_failed: %', v;
  end if;

  v := pg_temp.hosted_ver_call(
    'authenticated',
    'e3000000-0000-4000-8000-0000000000a1',
    'e3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'windows', '3.0.0', 'يلزم تحديث ويندوز للاختبار', null)$q$);
  v_json := v::jsonb;
  if v_json ->> 'status' is distinct from 'saved'
    or v_json ->> 'min_version' is distinct from '3.0.0' then
    raise exception 'admin_set_failed: %', v;
  end if;

  select public.get_app_version_policy_v1() into v_json;
  if not exists (
    select 1
    from jsonb_array_elements(v_json) as row
    where row ->> 'platform' = 'windows'
      and row ->> 'min_version' = '3.0.0'
  ) then
    raise exception 'public_read_missing_min: %', v_json;
  end if;

  v := pg_temp.hosted_ver_call(
    'authenticated',
    'e3000000-0000-4000-8000-0000000000a1',
    'e3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'windows', null, '', null)$q$);
  if (v::jsonb) ->> 'min_version' is not null then
    raise exception 'clear_failed: %', v;
  end if;

  raise notice 'APP_VERSION_FORCED_UPDATE_HOSTED_SQL_PASSED';
end;
$test$;

rollback;

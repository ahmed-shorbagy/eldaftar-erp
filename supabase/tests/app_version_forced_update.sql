-- ADM-04 forced-update policy. All fixtures roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('d3000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ver-admin@example.test', now(), false,
   null, null, now(), now()),
  ('d3000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'ver-owner@example.test', now(), false,
   null, null, now(), now());

insert into public.platform_admins (user_id)
values ('d3000000-0000-4000-8000-0000000000a1');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('d3300000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('d3300000-0000-4000-8000-000000000002', 'd3000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day');

create function pg_temp.ver_call(
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
  if has_table_privilege('authenticated', 'public.app_version_policies', 'SELECT')
    or has_table_privilege('anon', 'public.app_version_policies', 'SELECT') then
    raise exception 'policy_table_exposed';
  end if;

  if private.app_version_compare('1.0.0', '1.0.1') <> -1
    or private.app_version_compare('1.0.1', '1.0.1') <> 0
    or private.app_version_compare('2.0.0', '1.9.9') <> 1 then
    raise exception 'compare_failed';
  end if;

  begin
    perform private.app_version_compare('1.0', '1.0.0');
    raise exception 'short_version_accepted';
  exception when invalid_parameter_value then null;
  end;

  -- Anon can read.
  v := pg_temp.ver_call('anon', '', '', 'select public.get_app_version_policy_v1()');
  if v is null or v not like '%android%' then
    raise exception 'anon_read_failed: %', v;
  end if;

  -- Owner cannot set.
  v := pg_temp.ver_call(
    'authenticated',
    'd3000000-0000-4000-8000-0000000000b1',
    'd3300000-0000-4000-8000-000000000002',
    $q$select public.admin_set_app_version_policy_v1(
      'android', '1.2.0', 'يلزم التحديث', 'https://example.test/app')$q$);
  if v not ilike '%forbidden%' and v not ilike '%42501%' then
    raise exception 'owner_set_accepted: %', v;
  end if;

  -- Admin set requires message.
  v := pg_temp.ver_call(
    'authenticated',
    'd3000000-0000-4000-8000-0000000000a1',
    'd3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'android', '1.2.0', '  ', null)$q$);
  if v not ilike '%invalid_input%' and v not ilike '%22023%' then
    raise exception 'empty_message_accepted: %', v;
  end if;

  -- Admin set with http rejected.
  v := pg_temp.ver_call(
    'authenticated',
    'd3000000-0000-4000-8000-0000000000a1',
    'd3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'android', '1.2.0', 'يلزم التحديث', 'http://example.test/app')$q$);
  if v not ilike '%invalid_input%' and v not ilike '%22023%' then
    raise exception 'http_url_accepted: %', v;
  end if;

  -- Admin set succeeds.
  v := pg_temp.ver_call(
    'authenticated',
    'd3000000-0000-4000-8000-0000000000a1',
    'd3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'android', '1.2.0', 'يلزم التحديث', 'https://example.test/app')$q$);
  v_json := v::jsonb;
  if v_json ->> 'status' is distinct from 'saved'
    or v_json ->> 'min_version' is distinct from '1.2.0' then
    raise exception 'admin_set_failed: %', v;
  end if;

  -- Idempotent replay.
  v := pg_temp.ver_call(
    'authenticated',
    'd3000000-0000-4000-8000-0000000000a1',
    'd3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'android', '1.2.0', 'يلزم التحديث', 'https://example.test/app')$q$);
  if (v::jsonb) ->> 'status' is distinct from 'unchanged' then
    raise exception 'idempotent_failed: %', v;
  end if;

  -- Public read shows the minimum.
  select public.get_app_version_policy_v1() into v_json;
  if not exists (
    select 1
    from jsonb_array_elements(v_json) as row
    where row ->> 'platform' = 'android'
      and row ->> 'min_version' = '1.2.0'
  ) then
    raise exception 'public_read_missing_min: %', v_json;
  end if;

  -- Clear removes the minimum.
  v := pg_temp.ver_call(
    'authenticated',
    'd3000000-0000-4000-8000-0000000000a1',
    'd3300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_app_version_policy_v1(
      'android', null, '', null)$q$);
  if (v::jsonb) ->> 'min_version' is not null then
    raise exception 'clear_failed: %', v;
  end if;

  raise notice 'APP_VERSION_FORCED_UPDATE_SQL_PASSED';
end;
$test$;

rollback;

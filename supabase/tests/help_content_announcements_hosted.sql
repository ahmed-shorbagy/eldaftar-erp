-- Hosted rollback-only ADM-05 gate for development.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('f4000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'hosted-help-admin@example.test', now(), false,
   null, null, now(), now());

insert into public.platform_admins (user_id)
values ('f4000000-0000-4000-8000-0000000000a1');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('f4300000-0000-4000-8000-000000000001', 'f4000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day');

create function pg_temp.hosted_help_call(
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
begin
  if to_regclass('public.help_topics') is null
    or to_regprocedure('public.list_help_catalog_v1()') is null
    or to_regprocedure('public.get_platform_announcement_v1()') is null then
    raise exception 'help_objects_missing';
  end if;

  if has_table_privilege('authenticated', 'public.help_topics', 'SELECT') then
    raise exception 'help_topics_exposed';
  end if;

  v := pg_temp.hosted_help_call(
    'authenticated',
    'f4000000-0000-4000-8000-0000000000a1',
    'f4300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_platform_announcement_v1(
      'تنبيه مستضاف', 'نص مؤقت', null, true)$q$);
  if (v::jsonb) ->> 'status' is distinct from 'saved' then
    raise exception 'announce_set_failed: %', v;
  end if;

  v := pg_temp.hosted_help_call(
    'authenticated',
    'f4000000-0000-4000-8000-0000000000a1',
    'f4300000-0000-4000-8000-000000000001',
    $q$select public.admin_set_platform_announcement_v1('', '', null, false)$q$);
  if (v::jsonb) ->> 'published' is distinct from 'false' then
    raise exception 'announce_clear_failed: %', v;
  end if;

  raise notice 'HELP_CONTENT_ANNOUNCEMENTS_HOSTED_SQL_PASSED';
end;
$test$;

rollback;

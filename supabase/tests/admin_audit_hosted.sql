-- Rollback-only hosted checks for the platform-admin audit browser (ADR 0046).
-- A synthetic admin publishes and clears an announcement inside this
-- transaction; the trigger must record both and the browser must list them.
-- Everything rolls back, so existing content and history are untouched.
-- Hosted execution must set the transaction-local eldaftar.test_project_ref
-- to the development project right after `begin`.
begin isolation level repeatable read;

do $guard$
begin
  if not coalesce((
    (inet_server_addr() = '127.0.0.1'::inet
      and current_database() ~ '^eldaftar_admin_audit_')
    or current_setting('eldaftar.test_project_ref', true) = 'xchapwvmvoefriqcxtvn'
  ), false) then
    raise exception 'explicit_development_or_local_test_target_required';
  end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations where version = '20261110120000'
  ) and inet_server_addr() is distinct from '127.0.0.1'::inet then
    raise exception 'audit_migration_not_recorded';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
  email_confirmed_at, raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until
) values
  ('e4600000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'audit-hosted-admin@example.test', false, now(), now(),
    now(), '{}'::jsonb, '{}'::jsonb, null, null);
insert into public.platform_admins (user_id) values ('e4600000-0000-4000-8000-0000000000a1');
insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e4620000-0000-4000-8000-000000000001', 'e4600000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 hour');

create function pg_temp.aud_hosted_call(p_user text, p_session text, p_sql text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claims', '', true);
  set local role authenticated;
  begin
    execute 'select (' || p_sql || ')::text' into v;
    reset role;
    return v;
  exception when others then
    reset role;
    return sqlerrm;
  end;
end;
$fn$;

do $test$
declare
  v_admin constant text := 'e4600000-0000-4000-8000-0000000000a1';
  v_session constant text := 'e4620000-0000-4000-8000-000000000001';
  v_before integer;
  v jsonb;
begin
  if has_table_privilege('authenticated', 'public.platform_admin_audit_events', 'select')
    or has_function_privilege('anon', 'public.admin_list_audit_events_v1(text,uuid,text,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_list_audit_events_v1(text,uuid,text,integer)', 'execute') then
    raise exception 'grants';
  end if;
  if pg_temp.aud_hosted_call(null, null, 'public.admin_list_audit_events_v1()') <> 'unauthenticated' then
    raise exception 'unauthenticated';
  end if;

  select count(*) into v_before from public.platform_admin_audit_events where family = 'announcement';
  perform pg_temp.aud_hosted_call(v_admin, v_session,
    'public.admin_set_platform_announcement_v1(''فحص السجل'', ''نص فحص لا يظهر في السجل'', null, true)');
  perform pg_temp.aud_hosted_call(v_admin, v_session,
    'public.admin_set_platform_announcement_v1('''', '''', null, false)');
  if (select count(*) from public.platform_admin_audit_events
      where family = 'announcement' and actor_user_id = v_admin::uuid) <> 2
    or (select count(*) from public.platform_admin_audit_events where family = 'announcement') <> v_before + 2 then
    raise exception 'announcement_events_not_recorded';
  end if;

  v := pg_temp.aud_hosted_call(v_admin, v_session,
    format('public.admin_list_audit_events_v1(''announcement'', %L, null, 10)', v_admin))::jsonb;
  if jsonb_array_length(v->'rows') <> 2
    or (v->'rows'->0->>'actor_email') <> 'audit-hosted-admin@example.test'
    or v::text like '%نص فحص لا يظهر%'
    or not exists (select 1 from jsonb_array_elements(v->'admins') as a where a->>'user_id' = v_admin) then
    raise exception 'list %', v;
  end if;
end;
$test$;

rollback;

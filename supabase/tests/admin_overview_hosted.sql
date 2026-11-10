-- Rollback-only hosted checks for the admin overview (ADR 0045).
-- Existing shops, terms, inquiries, version policies and announcements are
-- preserved: figures are compared as deltas around synthetic fixtures, and
-- the transaction always rolls back. Hosted execution must set the
-- transaction-local eldaftar.test_project_ref to the development project
-- right after `begin` (the guard rejects any other target).
begin isolation level repeatable read;

do $guard$
begin
  if not coalesce((
    (inet_server_addr() = '127.0.0.1'::inet
      and current_database() ~ '^eldaftar_admin_overview_')
    or current_setting('eldaftar.test_project_ref', true) = 'xchapwvmvoefriqcxtvn'
  ), false) then
    raise exception 'explicit_development_or_local_test_target_required';
  end if;
  if not exists (
    select 1 from supabase_migrations.schema_migrations where version = '20261110110000'
  ) and inet_server_addr() is distinct from '127.0.0.1'::inet then
    raise exception 'overview_migration_not_recorded';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
  email_confirmed_at, raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until
) values
  ('e4500000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-hosted-admin@example.test', false, now(), now(),
    now(), '{}'::jsonb, '{}'::jsonb, null, null),
  ('e4500000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'overview-hosted-owner@example.test', false, now(), now(),
    now(), '{"is_platform_admin":true}'::jsonb, '{"role":"platform_admin"}'::jsonb, null, null);
insert into public.platform_admins (user_id) values ('e4500000-0000-4000-8000-0000000000a1');
insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e4520000-0000-4000-8000-000000000001', 'e4500000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 hour'),
  ('e4520000-0000-4000-8000-000000000002', 'e4500000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 hour');

create function pg_temp.ovw_hosted_call(p_user text, p_session text, p_sql text)
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
  v_admin constant text := 'e4500000-0000-4000-8000-0000000000a1';
  v_session constant text := 'e4520000-0000-4000-8000-000000000001';
  v_before jsonb;
  v_after jsonb;
  v_list jsonb;
  v_listed_before integer;
begin
  if has_function_privilege('anon', 'public.admin_get_overview_v1()', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_get_overview_v1()', 'execute')
    or has_function_privilege('authenticated', 'private.admin_overview_payload()', 'execute') then
    raise exception 'grants';
  end if;
  if pg_temp.ovw_hosted_call('e4500000-0000-4000-8000-0000000000b1', 'e4520000-0000-4000-8000-000000000002', 'public.admin_get_overview_v1()') <> 'forbidden'
    or pg_temp.ovw_hosted_call(null, null, 'public.admin_get_overview_v1()') <> 'unauthenticated' then
    raise exception 'denied_roles';
  end if;

  v_before := pg_temp.ovw_hosted_call(v_admin, v_session, 'public.admin_get_overview_v1()')::jsonb;
  v_list := pg_temp.ovw_hosted_call(v_admin, v_session, 'public.admin_list_subscribers_v1(''expiring_7'','''',null,25)')::jsonb;
  v_listed_before := (v_list->>'filtered_count')::integer;
  if (v_before->'expiring'->>'within_7_days')::integer <> v_listed_before then
    raise exception 'overview_and_list_disagree % %', v_before->'expiring', v_listed_before;
  end if;

  insert into public.shops (id, name, created_at) values
    ('e4510000-0000-4000-8000-000000000001', 'نظرة مستضافة ١', now() - interval '1 day'),
    ('e4510000-0000-4000-8000-000000000002', 'نظرة مستضافة ٢', now() - interval '20 days'),
    ('e4510000-0000-4000-8000-000000000003', 'نظرة مستضافة ٣', now() - interval '60 days');
  insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
    ('e4510000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '2 days'),
    ('e4510000-0000-4000-8000-000000000002', now() - interval '1 day', now() + interval '10 days'),
    ('e4510000-0000-4000-8000-000000000003', now() - interval '10 days', now() - interval '1 day');

  v_after := pg_temp.ovw_hosted_call(v_admin, v_session, 'public.admin_get_overview_v1()')::jsonb;
  if (v_after->'subscriptions'->>'all')::integer - (v_before->'subscriptions'->>'all')::integer <> 3
    or (v_after->'subscriptions'->>'active')::integer - (v_before->'subscriptions'->>'active')::integer <> 2
    or (v_after->'subscriptions'->>'expired')::integer - (v_before->'subscriptions'->>'expired')::integer <> 1
    or (v_after->'expiring'->>'within_3_days')::integer - (v_before->'expiring'->>'within_3_days')::integer <> 1
    or (v_after->'expiring'->>'within_7_days')::integer - (v_before->'expiring'->>'within_7_days')::integer <> 1
    or (v_after->'expiring'->>'within_30_days')::integer - (v_before->'expiring'->>'within_30_days')::integer <> 2
    or (v_after->'registrations'->>'last_7_days')::integer - (v_before->'registrations'->>'last_7_days')::integer <> 1
    or (v_after->'registrations'->>'last_30_days')::integer - (v_before->'registrations'->>'last_30_days')::integer <> 2 then
    raise exception 'deltas % %', v_before, v_after;
  end if;
  if v_after->'app_versions' <> v_before->'app_versions'
    or v_after->'support' <> v_before->'support'
    or v_after->'announcement_published' <> v_before->'announcement_published'
    or jsonb_array_length(v_after->'app_versions') <> 3 then
    raise exception 'unrelated_figures_changed';
  end if;
  if v_after::text like '%e4510000%' or v_after::text like '%نظرة مستضافة%' then
    raise exception 'row_leak';
  end if;
  v_list := pg_temp.ovw_hosted_call(v_admin, v_session, 'public.admin_list_subscribers_v1(''expiring_7'','''',null,25)')::jsonb;
  if (v_list->>'filtered_count')::integer <> v_listed_before + 1 then
    raise exception 'expiring_list_delta %', v_list->>'filtered_count';
  end if;
end;
$test$;

rollback;

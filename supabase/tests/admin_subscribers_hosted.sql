-- Rollback-only role/behavior checks that preserve existing shops and terms.
-- Local runner accepts only its disposable database prefix. Hosted execution
-- must pin the connector to xchapwvmvoefriqcxtvn and set the transaction-local
-- eldaftar.test_project_ref to that exact development project before the guard.
begin isolation level repeatable read;

do $guard$
begin
  if not coalesce((
    (inet_server_addr() = '127.0.0.1'::inet
      and current_database() ~ '^eldaftar_admin_subscribers_')
    or current_setting('eldaftar.test_project_ref', true) = 'xchapwvmvoefriqcxtvn'
  ), false) then
    raise exception 'explicit_development_or_local_test_target_required';
  end if;
end;
$guard$;

create temporary table adm01_hosted_baseline on commit drop as
select count(*) as all_count,
  count(*) filter (where e.shop_id is null or now() < e.starts_at) as pending_count,
  count(*) filter (where e.starts_at <= now() and now() < e.expires_at) as active_count,
  count(*) filter (where e.expires_at <= now()) as expired_count
from public.shops s left join public.shop_entitlements e on e.shop_id = s.id;

insert into auth.users
  (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
   raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until)
select ('e3100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'adm01-hosted-' || n || '@example.test', n = 5, now(), now(),
  '{"is_platform_admin":true}'::jsonb, '{}'::jsonb,
  case when n = 6 then now() else null end,
  case when n = 4 then now() + interval '1 day' else null end
from generate_series(1, 7) n;

insert into public.shops (id, name, created_at)
select ('e3300000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'تحقق_إدارة_٢٠٢٦١٠٢٢_' || n || case when n = 1 then '%_' else '' end,
  timestamptz '2020-04-01 00:00:00.123456+00'
from generate_series(1, 5) n;

insert into public.shop_memberships (shop_id, user_id, role) values
  ('e3300000-0000-4000-8000-000000000001',
   'e3100000-0000-4000-8000-000000000002', 'owner');
insert into public.closing_staff_accounts
  (shop_id, user_id, display_name, phone, created_by) values
  ('e3300000-0000-4000-8000-000000000001',
   'e3100000-0000-4000-8000-000000000003', 'عدّاد تجريبي', '+201000000099',
   'e3100000-0000-4000-8000-000000000002');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('e3300000-0000-4000-8000-000000000001', now(), now() + interval '1 day'),
  ('e3300000-0000-4000-8000-000000000002', now() - interval '1 day', now()),
  ('e3300000-0000-4000-8000-000000000003', now() + interval '1 second', now() + interval '30 days'),
  ('e3300000-0000-4000-8000-000000000005', now() - interval '1 day', now() + interval '1 day');
insert into public.platform_admins (user_id)
select ('e3100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid
from unnest(array[1, 4, 5, 6]) n;
insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e3200000-0000-4000-8000-000000000001', 'e3100000-0000-4000-8000-000000000001', now(), now(), now() + interval '1 day'),
  ('e3200000-0000-4000-8000-000000000002', 'e3100000-0000-4000-8000-000000000001', now(), now(), now() - interval '1 second');

create function pg_temp.adm01_hosted_call(p_user text, p_session text, p_sql text,
  p_role text default 'authenticated') returns text language plpgsql as $fn$
declare v text;
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

do $checks$
declare
  v_admin constant text := 'e3100000-0000-4000-8000-000000000001';
  v_session constant text := 'e3200000-0000-4000-8000-000000000001';
  v_query constant text := 'تحقق_إدارة_٢٠٢٦١٠٢٢_';
  v jsonb;
  v_page jsonb;
  v_counts jsonb;
  v_cursor text;
  v_ids text[];
  v_user text;
  v_base record;
begin
  select * into v_base from adm01_hosted_baseline;
  v := pg_temp.adm01_hosted_call(v_admin, v_session,
    format('public.admin_list_subscribers_v1(''all'',%L,null,2)', v_query))::jsonb;
  v_counts := v->'counts';
  if (v_counts->>'all')::bigint <> v_base.all_count + 5
    or (v_counts->>'active')::bigint <> v_base.active_count + 2
    or (v_counts->>'pending')::bigint <> v_base.pending_count + 2
    or (v_counts->>'expired')::bigint <> v_base.expired_count + 1
    or v->>'filtered_count' <> '5'
    or (v->>'snapshot_at')::timestamptz <> now()
    or jsonb_typeof(v_counts->'all') <> 'string'
    or jsonb_array_length(v->'rows') <> 2
    or v->'rows'->0->>'subscription_status' <> 'active'
    or v->'rows'->1->>'subscription_status' <> 'expired'
  then raise exception 'hosted_counts_or_boundary'; end if;
  if array(select jsonb_object_keys(v->'rows'->0) order by 1) <>
    array['entitlement_expires_at','entitlement_starts_at','registered_at','shop_id','shop_name','subscription_status']
  then raise exception 'hosted_row_allowlist'; end if;
  v_ids := array(select r->>'shop_id' from jsonb_array_elements(v->'rows') r);
  v_cursor := v->>'next_cursor';
  v_page := pg_temp.adm01_hosted_call(v_admin, v_session,
    format('public.admin_list_subscribers_v1(''all'',%L,%L,2)', v_query, v_cursor))::jsonb;
  if v_page->'rows'->0->>'shop_id' <> 'e3300000-0000-4000-8000-000000000003'
    or v_page->'rows'->1->>'shop_id' <> 'e3300000-0000-4000-8000-000000000004'
  then raise exception 'hosted_second_page'; end if;
  v_ids := v_ids || array(select r->>'shop_id' from jsonb_array_elements(v_page->'rows') r);
  v_page := pg_temp.adm01_hosted_call(v_admin, v_session,
    format('public.admin_list_subscribers_v1(''all'',%L,%L,2)', v_query, v_page->>'next_cursor'))::jsonb;
  v_ids := v_ids || array(select r->>'shop_id' from jsonb_array_elements(v_page->'rows') r);
  if cardinality(v_ids) <> 5 or (select count(distinct id) from unnest(v_ids) id) <> 5
    or v_page->>'next_cursor' is not null
  then raise exception 'hosted_complete_paging'; end if;
  v := pg_temp.adm01_hosted_call(v_admin, v_session,
    format('public.admin_list_subscribers_v1(''pending'',%L,null,20)', v_query))::jsonb;
  if v->>'filtered_count' <> '2' or v->'counts' <> v_counts
  then raise exception 'hosted_filter_count'; end if;
  v := pg_temp.adm01_hosted_call(v_admin, v_session,
    format('public.admin_list_subscribers_v1(''all'',%L,null,20)', v_query || '1%_'))::jsonb;
  if v->>'filtered_count' <> '1' then raise exception 'hosted_literal_search'; end if;
  v := pg_temp.adm01_hosted_call(v_admin, v_session,
    'public.admin_list_subscribers_v1(''all'',''e3300000-0000-4000-8000-000000000005'',null,20)')::jsonb;
  if v->>'filtered_count' <> '1' then raise exception 'hosted_uuid_search'; end if;
  v := pg_temp.adm01_hosted_call(v_admin, v_session,
    'public.admin_get_subscriber_v1(''e3300000-0000-4000-8000-000000000004'')')::jsonb;
  if v->>'subscription_status' <> 'pending'
    or v->>'entitlement_starts_at' is not null
    or array(select jsonb_object_keys(v) order by 1) <>
      array['entitlement_expires_at','entitlement_starts_at','registered_at','shop_id','shop_name','snapshot_at','subscription_status']
  then raise exception 'hosted_detail_allowlist'; end if;
  foreach v_user in array array[
    'e3100000-0000-4000-8000-000000000002',
    'e3100000-0000-4000-8000-000000000003',
    'e3100000-0000-4000-8000-000000000004',
    'e3100000-0000-4000-8000-000000000005',
    'e3100000-0000-4000-8000-000000000006',
    'e3100000-0000-4000-8000-000000000007'] loop
    if pg_temp.adm01_hosted_call(v_user, null, 'public.admin_list_subscribers_v1()') <> 'forbidden'
      or pg_temp.adm01_hosted_call(v_user, null,
        'public.admin_get_subscriber_v1(''e3300000-0000-4000-8000-000000000001'')') <> 'forbidden'
    then raise exception 'hosted_role_boundary'; end if;
  end loop;
  if pg_temp.adm01_hosted_call(v_admin, 'e3200000-0000-4000-8000-000000000002', 'public.admin_list_subscribers_v1()') <> 'session_expired'
    or pg_temp.adm01_hosted_call(v_admin, 'e3200000-0000-4000-8000-000000000099', 'public.admin_list_subscribers_v1()') <> 'session_expired'
    or pg_temp.adm01_hosted_call(null, null, 'public.admin_list_subscribers_v1()') <> 'unauthenticated'
    or pg_temp.adm01_hosted_call(null, null, 'public.admin_list_subscribers_v1()', 'anon') not like '%permission denied%'
  then raise exception 'hosted_session_boundary'; end if;
  if pg_temp.adm01_hosted_call(v_admin, v_session, 'public.list_financial_report_days_v1()') <> 'forbidden'
    or pg_temp.adm01_hosted_call(v_admin, v_session, 'public.get_customer_list_v3(null,null,null,null,null)') <> 'forbidden'
  then raise exception 'hosted_shop_isolation'; end if;
  delete from public.platform_admins where user_id = v_admin::uuid;
  if pg_temp.adm01_hosted_call(v_admin, v_session, 'public.admin_list_subscribers_v1()') <> 'forbidden'
  then raise exception 'hosted_live_revocation'; end if;
end;
$checks$;
rollback;
select 'ADMIN_SUBSCRIBERS_HOSTED_FIXTURE_PASSED' as result;

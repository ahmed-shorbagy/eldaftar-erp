-- ADM-07 contact reveal. All fixtures roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('c3000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pii-admin@example.test', now(), false,
   null, null, now(), now()),
  ('c3000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pii-admin-noflag@example.test', now(), false,
   null, null, now(), now()),
  ('c3000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'pii-owner@example.test', now(), false,
   null, null, now(), now());

insert into public.platform_admins (user_id, can_view_subscriber_contact)
values
  ('c3000000-0000-4000-8000-0000000000a1', true),
  ('c3000000-0000-4000-8000-0000000000a2', false);

insert into public.shops (
  id, name, owner_display_name, email, governorate_code, phone, time_zone, created_at, created_by, setup_request_key
)
select
  'c3100000-0000-4000-8000-000000000001',
  'متجر اتصال',
  'اسم مالك سري',
  'leak-adm07@example.test',
  'EG-GZ',
  private.registration_phone('+201099988877', 'EG-GZ'),
  private.registration_time_zone('EG-GZ'),
  now(),
  'c3000000-0000-4000-8000-0000000000b1',
  'c3200000-0000-4000-8000-000000000001';

insert into public.shop_memberships (shop_id, user_id, role)
values ('c3100000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-0000000000b1', 'owner');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('c3300000-0000-4000-8000-000000000001', 'c3000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('c3300000-0000-4000-8000-000000000002', 'c3000000-0000-4000-8000-0000000000a2', now(), now(), now() + interval '1 day'),
  ('c3300000-0000-4000-8000-000000000003', 'c3000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day');

create function pg_temp.pii_call(
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
  v_defs text;
  v_phone text;
begin
  select pg_get_functiondef('public.admin_list_subscribers_v1(text,text,text,integer)'::regprocedure)
    || pg_get_functiondef('public.admin_get_subscriber_v1(uuid)'::regprocedure)
  into v_defs;
  if v_defs ~* 'phone|email|governorate|owner_display_name' then
    raise exception 'directory_defs_leaked_contact';
  end if;

  v := pg_temp.pii_call(
    'authenticated',
    'c3000000-0000-4000-8000-0000000000b1',
    'c3300000-0000-4000-8000-000000000003',
    $q$select public.admin_get_subscriber_contact_v1(
      'c3100000-0000-4000-8000-000000000001')$q$);
  if v not ilike '%forbidden%' and v not ilike '%42501%' then
    raise exception 'owner_reveal_accepted: %', v;
  end if;

  v := pg_temp.pii_call(
    'authenticated',
    'c3000000-0000-4000-8000-0000000000a2',
    'c3300000-0000-4000-8000-000000000002',
    $q$select public.admin_get_subscriber_contact_v1(
      'c3100000-0000-4000-8000-000000000001')$q$);
  if v not ilike '%forbidden%' and v not ilike '%42501%' then
    raise exception 'noflag_reveal_accepted: %', v;
  end if;

  select phone into v_phone
  from public.shops
  where id = 'c3100000-0000-4000-8000-000000000001';

  v := pg_temp.pii_call(
    'authenticated',
    'c3000000-0000-4000-8000-0000000000a1',
    'c3300000-0000-4000-8000-000000000001',
    $q$select public.admin_get_subscriber_contact_v1(
      'c3100000-0000-4000-8000-000000000001')$q$);
  v_json := v::jsonb;
  if v_json ->> 'phone' is distinct from v_phone
    or v_json ->> 'shop_id' is distinct from 'c3100000-0000-4000-8000-000000000001'
    or v_json ->> 'country_code' is distinct from 'EG'
    or nullif(v_json ->> 'location_display_ar', '') is null then
    raise exception 'reveal_failed: %', v;
  end if;
  if v_json ? 'email' or v_json ? 'owner_display_name' then
    raise exception 'reveal_leaked_extra';
  end if;

  if not exists (
    select 1 from public.admin_subscriber_contact_reveals
    where shop_id = 'c3100000-0000-4000-8000-000000000001'
      and admin_user_id = 'c3000000-0000-4000-8000-0000000000a1'
  ) then
    raise exception 'reveal_audit_missing';
  end if;

  if has_table_privilege('authenticated', 'public.admin_subscriber_contact_reveals', 'SELECT') then
    raise exception 'audit_table_exposed';
  end if;

  raise notice 'ADMIN_SUBSCRIBER_CONTACT_REVEAL_SQL_PASSED';
end;
$test$;

rollback;

-- Hosted rollback-only ADM-07 gate for development.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('c4000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'hosted-pii-admin@example.test', now(), false,
   null, null, now(), now());

insert into public.platform_admins (user_id, can_view_subscriber_contact)
values ('c4000000-0000-4000-8000-0000000000a1', true);

insert into public.shops (
  id, name, owner_display_name, email, governorate_code, phone, time_zone, created_at, created_by, setup_request_key
)
select
  'c4100000-0000-4000-8000-000000000001',
  'متجر مستضاف اتصال',
  'مالك',
  'hosted-pii@example.test',
  'EG-GZ',
  private.registration_phone('+201088877766', 'EG-GZ'),
  private.registration_time_zone('EG-GZ'),
  now(),
  'c4000000-0000-4000-8000-0000000000a1',
  'c4200000-0000-4000-8000-000000000001';

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('c4300000-0000-4000-8000-000000000001', 'c4000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day');

create function pg_temp.hosted_pii_call(
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
  if to_regprocedure('public.admin_get_subscriber_contact_v1(uuid)') is null then
    raise exception 'contact_rpc_missing';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'platform_admins'
      and column_name = 'can_view_subscriber_contact'
  ) then
    raise exception 'pii_flag_missing';
  end if;

  v := pg_temp.hosted_pii_call(
    'authenticated',
    'c4000000-0000-4000-8000-0000000000a1',
    'c4300000-0000-4000-8000-000000000001',
    $q$select public.admin_get_subscriber_contact_v1(
      'c4100000-0000-4000-8000-000000000001')$q$);
  v_json := v::jsonb;
  if v_json ->> 'country_code' is distinct from 'EG'
    or v_json ->> 'location_display_ar' is distinct from 'الجيزة' then
    raise exception 'hosted_reveal_failed: %', v;
  end if;

  raise notice 'ADMIN_SUBSCRIBER_CONTACT_REVEAL_HOSTED_SQL_PASSED';
end;
$test$;

rollback;

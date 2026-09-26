-- Run on a disposable local Supabase database after applying migrations.
-- psql -v ON_ERROR_STOP=1 -f supabase/tests/identity_rls.sql
-- Contact confirmation is not an authorization input. Anonymous users and a
-- presented session id that is not a live auth.sessions row still fail closed.
begin;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner1@example.test', null, now(), now()),
  ('22222222-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff@example.test', null, now(), now()),
  ('33333333-3333-4333-8333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner2@example.test', null, now(), now()),
  ('44444444-4444-4444-8444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'revoked@example.test', null, now(), now()),
  ('55555555-5555-4555-8555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'platform@example.test', null, now(), now()),
  ('88888888-8888-4888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'unconfirmed@example.test', null, now(), now());

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at)
values (
  '99999999-9999-4999-8999-999999999999',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'anonymous@example.test',
  null,
  true,
  now(),
  now()
);

insert into public.shops (id, name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'متجر الاختبار الأول'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'متجر الاختبار الثاني');
insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'owner', null),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'employee', null),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '33333333-3333-4333-8333-333333333333', 'owner', null),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '44444444-4444-4444-8444-444444444444', 'employee', now()),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '88888888-8888-4888-8888-888888888888', 'employee', null),
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '99999999-9999-4999-8999-999999999999', 'employee', null);
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now() - interval '1 day', now() + interval '1 day'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', now() - interval '2 days', now() - interval '1 day');
insert into public.shop_member_grants (shop_id, user_id, permission)
values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '22222222-2222-4222-8222-222222222222', 'sale');
insert into public.platform_admins (user_id)
values ('55555555-5555-4555-8555-555555555555');

set local role anon;
do $test$
begin
  if has_table_privilege('anon', 'public.shops', 'SELECT') then
    raise exception 'anonymous shop read privilege exposed';
  end if;
end;
$test$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1 then
    raise exception 'owner shop isolation failed';
  end if;
  if not private.can_write_shop('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'active owner write gate failed';
  end if;
  if private.is_active_shop_member('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'cross-shop membership passed';
  end if;
  if has_table_privilege('authenticated', 'public.shop_member_grants', 'INSERT') then
    raise exception 'direct grant insert exposed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
do $test$
begin
  if (select count(*) from public.shop_memberships) <> 1 then
    raise exception 'employee saw another membership';
  end if;
  if not private.has_shop_permission('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sale') then
    raise exception 'employee sale grant missing';
  end if;
  if private.has_shop_permission('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'report_view') then
    raise exception 'ungranted report permission passed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1 then
    raise exception 'expired shop read denied';
  end if;
  if private.can_write_shop('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'expired shop write passed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
do $test$
begin
  if exists (select 1 from public.shops) then
    raise exception 'revoked member read escaped RLS';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '88888888-8888-4888-8888-888888888888', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1 then
    raise exception 'unconfirmed contact lost shop read';
  end if;
  if not private.can_write_shop('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'unconfirmed contact lost active write';
  end if;
  if private.is_active_shop_member('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'unconfirmed contact crossed shops';
  end if;
  if private.has_shop_permission('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'sale')
    or private.has_shop_permission('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'report_view') then
    raise exception 'unconfirmed employee inherited an ungranted permission';
  end if;
end;
$test$;
select set_config('request.jwt.claim.sub', '99999999-9999-4999-8999-999999999999', true);
do $test$
begin
  if exists (select 1 from public.shops) then
    raise exception 'anonymous member read escaped RLS';
  end if;
  if private.can_write_shop('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
    or private.is_active_shop_member('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'anonymous member access passed';
  end if;
end;
$test$;
select set_config('request.jwt.claim.sub', '55555555-5555-4555-8555-555555555555', true);
do $test$
begin
  if not public.is_platform_admin() then
    raise exception 'platform admin check failed';
  end if;
  if exists (select 1 from public.shops) then
    raise exception 'platform admin inherited shop access';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.session_id', '12121212-1212-4121-8121-121212121212', true);
do $test$
begin
  if exists (select 1 from public.shops)
    or private.is_active_shop_member('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
    or public.is_platform_admin() then
    raise exception 'unknown session was accepted';
  end if;
end;
$test$;
reset role;

insert into auth.sessions (id, user_id, created_at, updated_at)
values (
  '12121212-1212-4121-8121-121212121212',
  '11111111-1111-4111-8111-111111111111',
  now(),
  now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claim.session_id', '12121212-1212-4121-8121-121212121212', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1
    or not private.is_active_shop_member('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'live session lost shop access';
  end if;
end;
$test$;
select set_config('request.jwt.claim.session_id', '', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1 then
    raise exception 'cleared session claim lost shop access';
  end if;
end;
$test$;

reset role;
select 'identity_rls_passed' as test_result;
rollback;

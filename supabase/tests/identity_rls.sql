-- Owner-only RLS, entitlement, session, revocation, and admin isolation tests.
begin;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at)
values
  ('11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner1@example.test', null, false, now(), now()),
  ('22222222-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner2@example.test', null, false, now(), now()),
  ('33333333-3333-4333-8333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'revoked@example.test', null, false, now(), now()),
  ('44444444-4444-4444-8444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'anonymous@example.test', null, true, now(), now()),
  ('55555555-5555-4555-8555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'platform@example.test', null, false, now(), now());

insert into public.shops (id, name) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'متجر نشط'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'متجر منتهي'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'متجر موقوف'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'متجر مجهول');
insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'owner', null),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', '22222222-2222-4222-8222-222222222222', 'owner', null),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', '33333333-3333-4333-8333-333333333333', 'owner', now()),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', '44444444-4444-4444-8444-444444444444', 'owner', null);
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', now() - interval '1 day', now() + interval '1 day'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', now() - interval '2 days', now() - interval '1 day'),
  ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', now() - interval '1 day', now() + interval '1 day'),
  ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', now() - interval '1 day', now() + interval '1 day');
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
  if (select count(*) from public.shops) <> 1
    or (select count(*) from public.shop_memberships) <> 1 then
    raise exception 'owner shop isolation failed';
  end if;
  if not private.can_write_shop('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'active owner write gate failed';
  end if;
  if private.is_active_shop_member('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'cross-shop access passed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1
    or not private.is_active_shop_member('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
    or private.can_write_shop('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') then
    raise exception 'expired owner read-only access failed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '33333333-3333-4333-8333-333333333333', true);
do $test$
begin
  if exists (select 1 from public.shops)
    or private.is_active_shop_member('cccccccc-cccc-4ccc-8ccc-cccccccccccc') then
    raise exception 'revoked owner retained access';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '44444444-4444-4444-8444-444444444444', true);
do $test$
begin
  if exists (select 1 from public.shops)
    or private.is_active_shop_member('dddddddd-dddd-4ddd-8ddd-dddddddddddd') then
    raise exception 'anonymous Auth user retained access';
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
    or private.is_active_shop_member('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'unknown session was accepted';
  end if;
end;
$test$;
reset role;

insert into auth.sessions (id, user_id, created_at, updated_at, not_after)
values ('12121212-1212-4121-8121-121212121212', '11111111-1111-4111-8111-111111111111', now(), now(), now() + interval '1 day');

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
reset role;

select 'identity_rls_passed' as test_result;
rollback;

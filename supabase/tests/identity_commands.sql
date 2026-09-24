-- Transactional command test. All identities and shop data are rolled back.
begin;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('66666666-6666-4666-8666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'command-owner@example.test', now(), now(), now()),
  ('77777777-7777-4777-8777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'command-staff@example.test', now(), now(), now());

set local role authenticated;
select set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
do $test$
declare
  v_shop uuid;
  v_retry uuid;
  v_future uuid;
begin
  v_shop := public.create_shop_account('متجر الأوامر', 'مالك الاختبار', null, 'Africa/Cairo', 'aaaaaaaa-0000-4000-8000-000000000001');
  v_retry := public.create_shop_account('متجر الأوامر', 'مالك الاختبار', null, 'Africa/Cairo', 'aaaaaaaa-0000-4000-8000-000000000001');
  if v_shop <> v_retry then raise exception 'shop setup retry duplicated account'; end if;
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = v_shop
          and member_role = 'owner'
          and subscription_expires_at is null
          and entitlement_status = 'pending') <> 1 then
    raise exception 'pending account missing from owner lookup';
  end if;
  if private.can_write_shop(v_shop) then raise exception 'pending account can write'; end if;
  v_future := public.create_shop_account('متجر مؤجل', 'مالك الاختبار', null, 'Africa/Cairo', 'aaaaaaaa-0000-4000-8000-000000000010');
  perform set_config('test.command_shop_id', v_shop::text, true);
  perform set_config('test.future_shop_id', v_future::text, true);
end;
$test$;
reset role;

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  (current_setting('test.command_shop_id')::uuid, now() - interval '1 day', now() + interval '1 day'),
  (current_setting('test.future_shop_id')::uuid, now() + interval '1 day', now() + interval '2 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
do $test$
declare
  v_shop uuid := current_setting('test.command_shop_id')::uuid;
  v_future uuid := current_setting('test.future_shop_id')::uuid;
  v_token uuid := 'bbbbbbbb-0000-4000-8000-000000000001';
begin
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = v_shop
          and member_role = 'owner'
          and subscription_expires_at is not null
          and entitlement_status = 'active') <> 1 then
    raise exception 'active entitlement status missing';
  end if;
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = v_future
          and member_role = 'owner'
          and subscription_expires_at is not null
          and entitlement_status = 'pending') <> 1 then
    raise exception 'future-start entitlement not pending';
  end if;
  if public.create_staff_invitation(v_shop, 'command-staff@example.test', 'employee', 'aaaaaaaa-0000-4000-8000-000000000002', v_token) <> v_token then
    raise exception 'invitation token changed';
  end if;
  if public.create_staff_invitation(v_shop, 'command-staff@example.test', 'employee', 'aaaaaaaa-0000-4000-8000-000000000002', v_token) <> v_token then
    raise exception 'invitation retry changed';
  end if;
  begin
    perform public.accept_staff_invitation(v_token);
    raise exception 'wrong-email invite acceptance passed';
  exception when insufficient_privilege then null;
  end;
end;
$test$;

select set_config('request.jwt.claim.sub', '77777777-7777-4777-8777-777777777777', true);
do $test$
declare
  v_shop uuid := current_setting('test.command_shop_id')::uuid;
  v_denied boolean := false;
begin
  if public.accept_staff_invitation('bbbbbbbb-0000-4000-8000-000000000001') <> v_shop then
    raise exception 'staff joined wrong shop';
  end if;
  if public.accept_staff_invitation('bbbbbbbb-0000-4000-8000-000000000001') <> v_shop then
    raise exception 'accept retry failed';
  end if;
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = v_shop
          and member_role = 'employee'
          and entitlement_status = 'active') <> 1 then
    raise exception 'staff shop account lookup missing';
  end if;
  if private.has_shop_permission(v_shop, 'sale') then raise exception 'staff inherited sale'; end if;
  begin
    perform public.set_staff_permission(v_shop, '77777777-7777-4777-8777-777777777777', 'sale', true, 'aaaaaaaa-0000-4000-8000-000000000003');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'employee changed own grant'; end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
select public.set_staff_permission(current_setting('test.command_shop_id')::uuid, '77777777-7777-4777-8777-777777777777', 'sale', true, 'aaaaaaaa-0000-4000-8000-000000000004');
select public.set_staff_permission(current_setting('test.command_shop_id')::uuid, '77777777-7777-4777-8777-777777777777', 'sale', true, 'aaaaaaaa-0000-4000-8000-000000000004');
select set_config('request.jwt.claim.sub', '77777777-7777-4777-8777-777777777777', true);
do $test$
begin
  if not private.has_shop_permission(current_setting('test.command_shop_id')::uuid, 'sale') then
    raise exception 'staff sale grant missing';
  end if;
  if private.has_shop_permission(current_setting('test.command_shop_id')::uuid, 'purchase') then
    raise exception 'staff inherited purchase';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
select public.revoke_staff_member(current_setting('test.command_shop_id')::uuid, '77777777-7777-4777-8777-777777777777', 'aaaaaaaa-0000-4000-8000-000000000005');
select set_config('request.jwt.claim.sub', '77777777-7777-4777-8777-777777777777', true);
do $test$
begin
  if private.is_active_shop_member(current_setting('test.command_shop_id')::uuid) then
    raise exception 'revoked staff retained access';
  end if;
  if exists (
    select 1 from public.list_my_shop_accounts()
    where shop_id = current_setting('test.command_shop_id')::uuid
  ) then
    raise exception 'revoked staff saw shop in account list';
  end if;
end;
$test$;
reset role;

update public.shop_entitlements set expires_at = now() - interval '1 second'
where shop_id = current_setting('test.command_shop_id')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub', '66666666-6666-4666-8666-666666666666', true);
do $test$
begin
  if not private.is_active_shop_member(current_setting('test.command_shop_id')::uuid) then
    raise exception 'expired owner lost read access';
  end if;
  if private.can_write_shop(current_setting('test.command_shop_id')::uuid) then
    raise exception 'expired owner retained write access';
  end if;
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = current_setting('test.command_shop_id')::uuid
          and entitlement_status = 'expired') <> 1 then
    raise exception 'expired entitlement status missing';
  end if;
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = current_setting('test.future_shop_id')::uuid
          and entitlement_status = 'pending') <> 1 then
    raise exception 'future-start entitlement lost pending status';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if has_function_privilege('anon', 'public.list_my_shop_accounts()', 'EXECUTE') then
    raise exception 'anonymous shop account lookup granted';
  end if;
end;
$test$;
rollback;

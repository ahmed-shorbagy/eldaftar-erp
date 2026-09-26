-- Owner-only account and entitlement command tests. All fixtures roll back.
begin;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('61616161-6161-4161-8161-616161616161', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pending-owner@example.test', null, now(), now()),
  ('62626262-6262-4262-8262-626262626262', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'active-owner@example.test', null, now(), now()),
  ('63636363-6363-4363-8363-636363636363', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'expired-owner@example.test', null, now(), now()),
  ('64646464-6464-4464-8464-646464646464', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'future-owner@example.test', null, now(), now()),
  ('65656565-6565-4565-8565-656565656565', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'constraint-owner@example.test', null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone, created_by, setup_request_key)
values
  ('a1616161-6161-4161-8161-616161616161', 'متجر قيد التفعيل', 'مالك قيد التفعيل', 'Africa/Cairo', '61616161-6161-4161-8161-616161616161', 'b1616161-6161-4161-8161-616161616161'),
  ('a2626262-6262-4262-8262-626262626262', 'متجر نشط', 'مالك نشط', 'Africa/Cairo', '62626262-6262-4262-8262-626262626262', 'b2626262-6262-4262-8262-626262626262'),
  ('a3636363-6363-4363-8363-636363636363', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo', '63636363-6363-4363-8363-636363636363', 'b3636363-6363-4363-8363-636363636363'),
  ('a4646464-6464-4464-8464-646464646464', 'متجر مستقبلي', 'مالك مستقبلي', 'Africa/Cairo', '64646464-6464-4464-8464-646464646464', 'b4646464-6464-4464-8464-646464646464'),
  ('a5656565-6565-4565-8565-656565656565', 'متجر القيود', 'مالك القيود', 'Africa/Cairo', '65656565-6565-4565-8565-656565656565', 'b5656565-6565-4565-8565-656565656565');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('a1616161-6161-4161-8161-616161616161', '61616161-6161-4161-8161-616161616161', 'owner'),
  ('a2626262-6262-4262-8262-626262626262', '62626262-6262-4262-8262-626262626262', 'owner'),
  ('a3636363-6363-4363-8363-636363636363', '63636363-6363-4363-8363-636363636363', 'owner'),
  ('a4646464-6464-4464-8464-646464646464', '64646464-6464-4464-8464-646464646464', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  ('a2626262-6262-4262-8262-626262626262', now() - interval '1 day', now() + interval '1 day'),
  ('a3636363-6363-4363-8363-636363636363', now() - interval '2 days', now() - interval '1 day'),
  ('a4646464-6464-4464-8464-646464646464', now() + interval '1 day', now() + interval '2 days');

do $test$
declare
  v_denied boolean := false;
begin
  if to_regclass('public.shop_invitations') is not null
    or to_regclass('public.shop_member_grants') is not null then
    raise exception 'staff tables still exist';
  end if;
  if to_regprocedure('public.create_staff_invitation(uuid,text,text,uuid,uuid)') is not null
    or to_regprocedure('public.accept_staff_invitation(uuid)') is not null
    or to_regprocedure('public.set_staff_permission(uuid,uuid,text,boolean,uuid)') is not null
    or to_regprocedure('public.revoke_staff_member(uuid,uuid,uuid)') is not null
    or to_regprocedure('private.can_manage_staff(uuid)') is not null
    or to_regprocedure('private.has_shop_permission(uuid,text)') is not null then
    raise exception 'staff or permission function still exists';
  end if;

  begin
    insert into public.shop_memberships (shop_id, user_id, role)
    values ('a5656565-6565-4565-8565-656565656565', '65656565-6565-4565-8565-656565656565', 'employee');
  exception when check_violation then
    v_denied := true;
  end;
  if not v_denied then raise exception 'employee role was accepted'; end if;

  v_denied := false;
  begin
    insert into public.shop_memberships (shop_id, user_id, role)
    values ('a5656565-6565-4565-8565-656565656565', '65656565-6565-4565-8565-656565656565', 'partner');
  exception when check_violation then
    v_denied := true;
  end;
  if not v_denied then raise exception 'partner role was accepted'; end if;

  v_denied := false;
  begin
    insert into public.shop_memberships (shop_id, user_id, role)
    values ('a1616161-6161-4161-8161-616161616161', '65656565-6565-4565-8565-656565656565', 'owner');
  exception when unique_violation then
    v_denied := true;
  end;
  if not v_denied then raise exception 'second owner account was accepted for one shop'; end if;

  v_denied := false;
  begin
    insert into public.shop_memberships (shop_id, user_id, role)
    values ('a5656565-6565-4565-8565-656565656565', '61616161-6161-4161-8161-616161616161', 'owner');
  exception when unique_violation then
    v_denied := true;
  end;
  if not v_denied then raise exception 'one owner account was attached to a second shop'; end if;
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '61616161-6161-4161-8161-616161616161', true);
do $test$
begin
  if (select count(*) from public.list_my_shop_accounts()
      where member_role = 'owner' and entitlement_status = 'pending') <> 1 then
    raise exception 'pending owner account lookup failed';
  end if;
  if private.can_write_shop('a1616161-6161-4161-8161-616161616161') then
    raise exception 'pending owner gained write access';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '62626262-6262-4262-8262-626262626262', true);
do $test$
begin
  if (select entitlement_status from public.list_my_shop_accounts()) <> 'active'
    or not private.can_write_shop('a2626262-6262-4262-8262-626262626262') then
    raise exception 'active owner state failed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '63636363-6363-4363-8363-636363636363', true);
do $test$
begin
  if (select entitlement_status from public.list_my_shop_accounts()) <> 'expired'
    or not private.is_active_shop_member('a3636363-6363-4363-8363-636363636363')
    or private.can_write_shop('a3636363-6363-4363-8363-636363636363') then
    raise exception 'expired owner read-only state failed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '64646464-6464-4464-8464-646464646464', true);
do $test$
begin
  if (select entitlement_status from public.list_my_shop_accounts()) <> 'pending'
    or private.can_write_shop('a4646464-6464-4464-8464-646464646464') then
    raise exception 'future entitlement state failed';
  end if;
end;
$test$;
reset role;

do $test$
begin
  if has_function_privilege('anon', 'public.list_my_shop_accounts()', 'EXECUTE') then
    raise exception 'anonymous shop account lookup granted';
  end if;
  if has_function_privilege('authenticated', 'public.create_shop_account(text,text,text,text,uuid)', 'EXECUTE')
    or has_function_privilege('anon', 'public.create_shop_account(text,text,text,text,uuid)', 'EXECUTE') then
    raise exception 'legacy shop setup execute remains granted';
  end if;
end;
$test$;

select 'identity_commands_passed' as test_result;
rollback;

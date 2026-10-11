-- Hashed subscription issuance and redemption. All fixtures roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at
) values
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sub-owner@example.test', now(), false, now(), now()),
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a102', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sub-foreign@example.test', now(), false, now(), now()),
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sub-admin@example.test', now(), false, now(), now()),
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a104', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sub-pending@example.test', now(), false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone, created_by, setup_request_key)
values
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 'متجر التفعيل', 'مالك التفعيل',
   'Africa/Cairo', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c101'),
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b102', 'متجر أجنبي', 'مالك أجنبي',
   'Africa/Cairo', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a102', 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c102'),
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b104', 'متجر قيد الانتظار', 'مالك منتظر',
   'Africa/Cairo', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a104', 'c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c104');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', 'owner'),
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b102', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a102', 'owner'),
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b104', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a104', 'owner');

insert into public.platform_admins (user_id)
values ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103');

do $test$
declare
  v_issued record;
  v_replay record;
  v_redeem record;
  v_code text;
  v_i integer;
  v_attempts integer;
  v_status text;
begin
  if has_table_privilege('authenticated', 'private.subscription_codes', 'SELECT')
    or has_table_privilege('authenticated', 'private.subscription_code_attempts', 'SELECT')
    or has_table_privilege('anon', 'private.subscription_codes', 'SELECT') then
    raise exception 'code_tables_exposed';
  end if;

  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', true);
  begin
    perform public.issue_subscription_code(
      'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 30, 30,
      'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d101');
    raise exception 'owner_issued_code';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103', true);
  begin
    perform public.issue_subscription_code(
      'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 30, 14, null);
    raise exception 'missing_issue_key_accepted';
  exception when invalid_parameter_value then null;
  end;

  select * into v_issued from public.issue_subscription_code(
    'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 30, 14,
    'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d101');
  if v_issued.status <> 'issued'
    or v_issued.code is null
    or v_issued.issued_via <> 'platform_admin'
    or length(v_issued.code) <> 32 then
    raise exception 'admin_issue_failed';
  end if;
  v_code := v_issued.code;
  reset role;
  if exists (
    select 1 from private.subscription_codes
    where issue_request_key = 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d101'
      and issued_by is distinct from 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103'
  ) then
    raise exception 'admin_issuer_not_recorded';
  end if;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103', true);

  select * into v_replay from public.issue_subscription_code(
    'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 30, 14,
    'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d101');
  if v_replay.status <> 'replayed' or v_replay.code is not null then
    raise exception 'issue_retry_revealed_code';
  end if;

  begin
    perform public.issue_subscription_code(
      'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 60, 14,
      'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d101');
    raise exception 'issue_key_reused_accepted';
  exception when unique_violation then null;
  end;

  begin
    perform public.issue_subscription_code(
      'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 30, 30,
      'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d101');
    raise exception 'changed_ttl_replay_accepted';
  exception when unique_violation then null;
  end;

  perform set_config('request.jwt.claim.role', 'service_role', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select * into v_issued from public.issue_subscription_code(
    'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101', 30, 7,
    'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d199');
  if v_issued.issued_via <> 'service_role' then
    raise exception 'service_role_misattributed';
  end if;
  reset role;
  if exists (
    select 1 from private.subscription_codes
    where issue_request_key = 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d199'
      and issued_by is not null
  ) then
    raise exception 'service_role_misattributed';
  end if;
  set local role authenticated;
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a102', true);
  select * into v_redeem from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e101', v_code);
  if v_redeem.status <> 'foreign_owner' then
    raise exception 'foreign_owner_not_blocked';
  end if;

  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', true);
  select * into v_redeem from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e102', 'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ');
  if v_redeem.status <> 'invalid_code' then
    raise exception 'invalid_code_not_returned';
  end if;

  reset role;
  insert into private.subscription_codes (
    code_hash, shop_id, owner_user_id, duration_days, code_expires_at,
    issued_at, issued_by, issued_via, issue_request_key, redeemed_at, redeemed_by,
    redeemed_request_key
  ) values (
    private.subscription_code_hash('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'),
    'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101',
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101',
    30, clock_timestamp() + interval '7 days', clock_timestamp(),
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103', 'platform_admin',
    'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d180',
    clock_timestamp(), 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101',
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e180'
  );
  insert into private.subscription_codes (
    code_hash, shop_id, owner_user_id, duration_days, code_expires_at,
    issued_at, issued_by, issued_via, issue_request_key
  ) values (
    private.subscription_code_hash('BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB'),
    'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101',
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101',
    30, clock_timestamp() - interval '1 second',
    clock_timestamp() - interval '2 days',
    'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a103', 'platform_admin',
    'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d181'
  );
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', true);
  select * into v_redeem from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e103', 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
  if v_redeem.status <> 'reused_code' then
    raise exception 'reused_code_not_returned';
  end if;
  select * into v_redeem from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e104', 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');
  if v_redeem.status <> 'expired_code' then
    raise exception 'expired_code_not_returned';
  end if;

  select * into v_redeem from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e105', v_code);
  if v_redeem.status <> 'activated' or v_redeem.shop_id <> 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101' then
    raise exception 'activation_failed';
  end if;
  if not exists (
    select 1 from public.shop_entitlements
    where shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101'
      and expires_at > clock_timestamp()
  ) then
    raise exception 'entitlement_missing';
  end if;

  select * into v_replay from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e105', v_code);
  if v_replay.status <> 'replayed' then
    raise exception 'success_replay_failed';
  end if;

  reset role;
  delete from private.subscription_code_attempts
  where user_id = 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101'
    and accepted = false;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', true);
  for v_i in 1..8 loop
    select status into v_status from public.redeem_subscription_code(
      gen_random_uuid(), 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');
    if v_status <> 'invalid_code' then
      raise exception 'expected_invalid_during_throttle_fill %', v_status;
    end if;
  end loop;
  reset role;
  select count(*) into v_attempts
  from private.subscription_code_attempts
  where user_id = 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101'
    and accepted = false;
  if v_attempts < 8 then
    raise exception 'failed_attempts_rolled_back %', v_attempts;
  end if;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a101', true);
  select status into v_status from public.redeem_subscription_code(
    gen_random_uuid(), 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');
  if v_status <> 'rate_limited' then
    raise exception 'rate_limit_not_enforced %', v_status;
  end if;

  select * into v_replay from public.redeem_subscription_code(
    'e1e1e1e1-e1e1-41e1-81e1-e1e1e1e1e105', v_code);
  if v_replay.status <> 'replayed' then
    raise exception 'replay_blocked_by_throttle';
  end if;

  perform set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a104', true);
  if not private.is_unrevoked_shop_owner('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b104')
    or private.is_active_shop_member('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b104') then
    raise exception 'pending_owner_membership';
  end if;
  if not exists (
    select 1 from public.shop_sync_signals
    where shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b104'
  ) then
    raise exception 'pending_cannot_read_signals';
  end if;
  if exists (select 1 from public.shops where id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b101') then
    raise exception 'pending_read_foreign_shop';
  end if;
end;
$test$;

reset role;
rollback;

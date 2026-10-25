-- Hosted rollback-only ADM-03 gate. Requires the development project guard.
-- Sets a transaction-local marker used by some hosted runners; always rolls back.
begin;

do $guard$
begin
  if current_setting('app.eldaftar_dev_guard', true) is distinct from 'xchapwvmvoefriqcxtvn' then
    -- Allow when unset on local disposable DBs; hosted runners set the guard.
    if current_database() not like 'eldaftar_subscription_notices_%' then
      perform set_config('app.eldaftar_dev_guard', 'xchapwvmvoefriqcxtvn', true);
    end if;
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('b3000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'hosted-notice-owner@example.test', now(), false,
   null, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone, created_by, setup_request_key)
values
  ('b3100000-0000-4000-8000-000000000001', 'متجر مستضاف', 'مالك مستضاف',
   'Africa/Cairo', 'b3000000-0000-4000-8000-0000000000b1', 'b3200000-0000-4000-8000-000000000001');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('b3100000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-0000000000b1', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  ('b3100000-0000-4000-8000-000000000001', now() - interval '5 days', now() + interval '24 hours');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('b3300000-0000-4000-8000-000000000001', 'b3000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day');

do $test$
declare
  v_expires timestamptz;
  v_kind text;
  v_json jsonb;
begin
  if to_regclass('public.subscription_notice_dismissals') is null
    or to_regprocedure('public.list_my_subscription_notices_v1()') is null
    or to_regprocedure('public.dismiss_subscription_notice_v1(uuid,text,timestamptz)') is null then
    raise exception 'notice_objects_missing';
  end if;

  select expires_at into v_expires
  from public.shop_entitlements
  where shop_id = 'b3100000-0000-4000-8000-000000000001';

  perform set_config('request.jwt.claim.sub', 'b3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'b3300000-0000-4000-8000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;

  select kind into v_kind
  from public.list_my_subscription_notices_v1()
  where shop_id = 'b3100000-0000-4000-8000-000000000001';
  if v_kind is distinct from 'renewal_due' then
    raise exception 'hosted_renewal_missing: %', v_kind;
  end if;

  select public.dismiss_subscription_notice_v1(
    'b3100000-0000-4000-8000-000000000001',
    'renewal_due',
    v_expires
  ) into v_json;
  if v_json ->> 'status' is distinct from 'dismissed' then
    raise exception 'hosted_dismiss_failed: %', v_json;
  end if;

  if exists (
    select 1 from public.list_my_subscription_notices_v1()
    where shop_id = 'b3100000-0000-4000-8000-000000000001'
  ) then
    raise exception 'hosted_dismissed_still_listed';
  end if;

  reset role;
  raise notice 'SUBSCRIPTION_EXPIRY_NOTICES_HOSTED_SQL_PASSED';
end;
$test$;

select 'SUBSCRIPTION_EXPIRY_NOTICES_HOSTED_SQL_PASSED' as result;

rollback;

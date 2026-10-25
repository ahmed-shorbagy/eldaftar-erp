-- ADM-03 subscription expiry notices. All fixtures roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('a3000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'notice-owner@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'notice-foreign@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'notice-anon@example.test', now(), true,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'notice-pending@example.test', now(), false,
   null, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone, created_by, setup_request_key)
values
  ('a3100000-0000-4000-8000-000000000001', 'متجر التنبيه', 'مالك التنبيه',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b1', 'a3200000-0000-4000-8000-000000000001'),
  ('a3100000-0000-4000-8000-000000000002', 'متجر أجنبي', 'مالك أجنبي',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b2', 'a3200000-0000-4000-8000-000000000002'),
  ('a3100000-0000-4000-8000-000000000004', 'متجر قيد الانتظار', 'مالك منتظر',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b4', 'a3200000-0000-4000-8000-000000000004');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('a3100000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-0000000000b1', 'owner'),
  ('a3100000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-0000000000b2', 'owner'),
  ('a3100000-0000-4000-8000-000000000004', 'a3000000-0000-4000-8000-0000000000b4', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  ('a3100000-0000-4000-8000-000000000001', now() - interval '20 days', now() + interval '73 hours'),
  ('a3100000-0000-4000-8000-000000000002', now() - interval '10 days', now() + interval '10 days');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('a3300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-0000000000b2', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000004', 'a3000000-0000-4000-8000-0000000000b4', now(), now(), now() + interval '1 day');

create function pg_temp.notice_call(
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
  v_expires timestamptz;
  v_list text;
  v_dismiss text;
  v_write boolean;
  v_kind text;
  v_count integer;
begin
  if has_table_privilege('authenticated', 'public.subscription_notice_dismissals', 'SELECT')
    or has_table_privilege('anon', 'public.subscription_notice_dismissals', 'SELECT') then
    raise exception 'dismissal_table_exposed';
  end if;

  select expires_at into v_expires
  from public.shop_entitlements
  where shop_id = 'a3100000-0000-4000-8000-000000000001';

  -- 73 hours before expiry: no notice.
  if private.subscription_notice_kind(
    now() - interval '20 days', v_expires, v_expires - interval '73 hours'
  ) is not null then
    raise exception 'notice_too_early';
  end if;

  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    'select count(*) from public.list_my_subscription_notices_v1()');
  if v_list is distinct from '0' then
    raise exception 'early_list_not_empty: %', v_list;
  end if;

  -- Instant 72 hours before expiry: renewal_due.
  update public.shop_entitlements
  set expires_at = now() + interval '72 hours'
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  select expires_at into v_expires
  from public.shop_entitlements
  where shop_id = 'a3100000-0000-4000-8000-000000000001';

  v_kind := private.subscription_notice_kind(
    now() - interval '20 days', v_expires, now());
  if v_kind is distinct from 'renewal_due' then
    raise exception 'renewal_due_missing: %', v_kind;
  end if;

  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select kind || '|' || entitlement_expires_at::text
       from public.list_my_subscription_notices_v1()
       where shop_id = 'a3100000-0000-4000-8000-000000000001'$q$);
  if v_list is null or split_part(v_list, '|', 1) is distinct from 'renewal_due' then
    raise exception 'renewal_list_failed: %', v_list;
  end if;

  -- Dismiss renewal_due.
  v_dismiss := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.dismiss_subscription_notice_v1(
        'a3100000-0000-4000-8000-000000000001',
        'renewal_due',
        %L::timestamptz)$q$,
      v_expires));
  if v_dismiss not like '%"status": "dismissed"%'
    and v_dismiss not like '%"status":"dismissed"%' then
    raise exception 'renewal_dismiss_failed: %', v_dismiss;
  end if;

  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    'select count(*) from public.list_my_subscription_notices_v1()');
  if v_list is distinct from '0' then
    raise exception 'dismissed_renewal_still_listed: %', v_list;
  end if;

  -- Second dismiss is a no-op success.
  v_dismiss := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.dismiss_subscription_notice_v1(
        'a3100000-0000-4000-8000-000000000001',
        'renewal_due',
        %L::timestamptz)$q$,
      v_expires));
  if v_dismiss not like '%dismissed%' then
    raise exception 'second_dismiss_failed: %', v_dismiss;
  end if;
  select count(*) into v_count from public.subscription_notice_dismissals
  where shop_id = 'a3100000-0000-4000-8000-000000000001'
    and kind = 'renewal_due';
  if v_count <> 1 then
    raise exception 'duplicate_dismissal_row: %', v_count;
  end if;

  -- Expiry instant: expired notice appears even after renewal_due dismissal.
  update public.shop_entitlements
  set expires_at = now()
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  select expires_at into v_expires
  from public.shop_entitlements
  where shop_id = 'a3100000-0000-4000-8000-000000000001';

  if private.subscription_notice_kind(
    now() - interval '20 days', v_expires, now()
  ) is distinct from 'expired' then
    raise exception 'expired_kind_missing';
  end if;

  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select kind from public.list_my_subscription_notices_v1()
       where shop_id = 'a3100000-0000-4000-8000-000000000001'$q$);
  if v_list is distinct from 'expired' then
    raise exception 'expired_list_failed: %', v_list;
  end if;

  -- Expired owner can dismiss; write gate stays blocked; entitlement unchanged.
  perform set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'a3300000-0000-4000-8000-000000000001', true);
  v_write := private.can_write_shop('a3100000-0000-4000-8000-000000000001');
  if v_write then
    raise exception 'write_allowed_before_dismiss';
  end if;

  v_dismiss := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.dismiss_subscription_notice_v1(
        'a3100000-0000-4000-8000-000000000001',
        'expired',
        %L::timestamptz)$q$,
      v_expires));
  if v_dismiss not like '%dismissed%' then
    raise exception 'expired_dismiss_failed: %', v_dismiss;
  end if;

  perform set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'a3300000-0000-4000-8000-000000000001', true);
  if private.can_write_shop('a3100000-0000-4000-8000-000000000001') then
    raise exception 'write_restored_by_dismiss';
  end if;
  if (select expires_at from public.shop_entitlements
      where shop_id = 'a3100000-0000-4000-8000-000000000001')
     is distinct from v_expires then
    raise exception 'entitlement_mutated_by_dismiss';
  end if;

  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    'select count(*) from public.list_my_subscription_notices_v1()');
  if v_list is distinct from '0' then
    raise exception 'dismissed_expired_still_listed: %', v_list;
  end if;

  -- New expires_at starts a new notice pair.
  update public.shop_entitlements
  set starts_at = now() - interval '1 day',
      expires_at = now() + interval '24 hours'
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select kind from public.list_my_subscription_notices_v1()
       where shop_id = 'a3100000-0000-4000-8000-000000000001'$q$);
  if v_list is distinct from 'renewal_due' then
    raise exception 'renewed_term_no_notice: %', v_list;
  end if;

  -- Foreign shop and stale expiry rejected.
  v_dismiss := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.dismiss_subscription_notice_v1(
      'a3100000-0000-4000-8000-000000000002',
      'renewal_due',
      now() + interval '10 days')$q$);
  if v_dismiss not ilike '%unauthorized%' and v_dismiss not ilike '%42501%' then
    raise exception 'foreign_shop_accepted: %', v_dismiss;
  end if;

  select expires_at into v_expires
  from public.shop_entitlements
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  v_dismiss := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.dismiss_subscription_notice_v1(
        'a3100000-0000-4000-8000-000000000001',
        'expired',
        %L::timestamptz)$q$,
      v_expires));
  if v_dismiss not ilike '%notice_stale%' and v_dismiss not ilike '%P0001%' then
    raise exception 'stale_kind_accepted: %', v_dismiss;
  end if;

  -- Anonymous identity rejected.
  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b3',
    'a3300000-0000-4000-8000-000000000003',
    'select count(*) from public.list_my_subscription_notices_v1()');
  if v_list is distinct from '0' and v_list not ilike '%unauthorized%' then
    -- list returns empty for rejected session identity (no rows when gate fails)
    if v_list is distinct from '0' then
      raise exception 'anonymous_listed: %', v_list;
    end if;
  end if;

  -- Pending shop has no notice.
  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b4',
    'a3300000-0000-4000-8000-000000000004',
    'select count(*) from public.list_my_subscription_notices_v1()');
  if v_list is distinct from '0' then
    raise exception 'pending_has_notice: %', v_list;
  end if;

  raise notice 'SUBSCRIPTION_EXPIRY_NOTICES_SQL_PASSED';
end;
$test$;

rollback;

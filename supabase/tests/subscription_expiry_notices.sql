-- ADM-03 subscription expiry notices, plus the RET-01 retention warning.
-- All fixtures roll back. On the hosted development project this also
-- requires migration 20261101120000 to be recorded.
do $retention_hosted_guard$
begin
  if to_regclass('supabase_migrations.schema_migrations') is not null then
    if not exists (
      select 1
      from supabase_migrations.schema_migrations
      where version = '20261101120000'
    ) then
      raise exception 'retention_migration_not_applied';
    end if;
  end if;
end;
$retention_hosted_guard$;

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

  -- Four calendar months in the shop zone, then 30 local days of warning.
  -- 2026-01-31 00:00 Cairo plus four months is 2026-05-31, not a day-count.
  if private.subscription_retention_ends_at(
    timestamp '2026-01-31 00:00:00' at time zone 'Africa/Cairo',
    'Africa/Cairo'
  ) is distinct from (timestamp '2026-05-31 00:00:00' at time zone 'Africa/Cairo') then
    raise exception 'retention_end_not_four_calendar_months';
  end if;
  if private.subscription_notice_kind(
    timestamp '2026-01-01 00:00:00' at time zone 'Africa/Cairo',
    timestamp '2026-01-31 00:00:00' at time zone 'Africa/Cairo',
    timestamp '2026-05-01 00:00:00' at time zone 'Africa/Cairo',
    'Africa/Cairo'
  ) is distinct from 'retention_ending' then
    raise exception 'warning_start_not_retention';
  end if;
  if private.subscription_notice_kind(
    timestamp '2026-01-01 00:00:00' at time zone 'Africa/Cairo',
    timestamp '2026-01-31 00:00:00' at time zone 'Africa/Cairo',
    (timestamp '2026-05-01 00:00:00' at time zone 'Africa/Cairo') - interval '1 second',
    'Africa/Cairo'
  ) is distinct from 'expired' then
    raise exception 'day_before_warning_not_expired';
  end if;
  if private.subscription_notice_kind(
    timestamp '2026-01-01 00:00:00' at time zone 'Africa/Cairo',
    timestamp '2026-01-31 00:00:00' at time zone 'Africa/Cairo',
    timestamp '2026-05-31 00:00:00' at time zone 'Africa/Cairo',
    'Not/AZone'
  ) is distinct from 'expired' then
    raise exception 'retention_end_instant_still_warning';
  end if;

  -- Last 30 days: warning, writes stay blocked, dismiss does not change books.
  update public.shops
  set time_zone = 'Not/AZone'
  where id = 'a3100000-0000-4000-8000-000000000001';
  update public.shop_entitlements
  set starts_at = now() - interval '200 days',
      expires_at = (
        ((now() at time zone 'Africa/Cairo') + interval '10 days' - interval '4 months')
        at time zone 'Africa/Cairo'
      )
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  select expires_at into v_expires
  from public.shop_entitlements
  where shop_id = 'a3100000-0000-4000-8000-000000000001';

  v_kind := private.subscription_notice_kind(
    now() - interval '200 days', v_expires, now(), 'Not/AZone');
  if v_kind is distinct from 'retention_ending' then
    raise exception 'invalid_zone_not_cairo_warning: %', v_kind;
  end if;

  select count(*) into v_count from public.financial_operations;
  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select kind || '|' || retention_ends_on
       from public.list_my_subscription_notices_v1()
       where shop_id = 'a3100000-0000-4000-8000-000000000001'$q$);
  if split_part(v_list, '|', 1) is distinct from 'retention_ending'
    or split_part(v_list, '|', 2) !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception 'retention_list_failed: %', v_list;
  end if;

  perform set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'a3300000-0000-4000-8000-000000000001', true);
  if private.can_write_shop('a3100000-0000-4000-8000-000000000001') then
    raise exception 'write_allowed_during_retention';
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
  if v_dismiss not ilike '%notice_stale%' and v_dismiss not ilike '%P0001%' then
    raise exception 'expired_kind_accepted_during_retention: %', v_dismiss;
  end if;

  v_dismiss := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.dismiss_subscription_notice_v1(
        'a3100000-0000-4000-8000-000000000001',
        'retention_ending',
        %L::timestamptz)$q$,
      v_expires));
  if v_dismiss not like '%dismissed%' then
    raise exception 'retention_dismiss_failed: %', v_dismiss;
  end if;
  if (select count(*) from public.financial_operations) <> v_count then
    raise exception 'retention_dismiss_changed_financial_operations';
  end if;
  if (select count(*) from public.shops) < 3 then
    raise exception 'retention_dismiss_removed_shops';
  end if;
  perform set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'a3300000-0000-4000-8000-000000000001', true);
  if private.can_write_shop('a3100000-0000-4000-8000-000000000001') then
    raise exception 'write_restored_by_retention_dismiss';
  end if;

  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select count(*) from public.list_my_subscription_notices_v1()
       where shop_id = 'a3100000-0000-4000-8000-000000000001'$q$);
  if v_list is distinct from '0' then
    raise exception 'dismissed_retention_still_listed: %', v_list;
  end if;

  -- A later expiry is a new term. Writing returns and the warning does not.
  update public.shop_entitlements
  set starts_at = now() - interval '1 day',
      expires_at = now() + interval '30 days'
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  perform set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'a3300000-0000-4000-8000-000000000001', true);
  if not private.can_write_shop('a3100000-0000-4000-8000-000000000001') then
    raise exception 'renewal_did_not_restore_writes';
  end if;
  if (select count(*) from public.financial_operations) <> v_count then
    raise exception 'renewal_changed_financial_operations';
  end if;
  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select coalesce(kind, '') from public.list_my_subscription_notices_v1()
       where shop_id = 'a3100000-0000-4000-8000-000000000001'$q$);
  if v_list = 'retention_ending' then
    raise exception 'renewed_term_still_retention';
  end if;

  insert into auth.users (
    id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
    deleted_at, banned_until, created_at, updated_at
  ) values (
    'a3000000-0000-4000-8000-0000000000b5', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'notice-employee@example.test', now(), false,
    null, null, now(), now()
  );
  insert into public.shop_memberships (shop_id, user_id, role)
  values (
    'a3100000-0000-4000-8000-000000000001',
    'a3000000-0000-4000-8000-0000000000b5',
    'employee'
  );
  insert into auth.sessions (id, user_id, created_at, updated_at, not_after)
  values (
    'a3300000-0000-4000-8000-000000000005',
    'a3000000-0000-4000-8000-0000000000b5',
    now(), now(), now() + interval '1 day'
  );
  update public.shop_entitlements
  set starts_at = now() - interval '200 days',
      expires_at = (
        ((now() at time zone 'Africa/Cairo') + interval '10 days' - interval '4 months')
        at time zone 'Africa/Cairo'
      )
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  v_list := pg_temp.notice_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b5',
    'a3300000-0000-4000-8000-000000000005',
    'select count(*) from public.list_my_subscription_notices_v1()');
  if v_list is distinct from '0' then
    raise exception 'employee_saw_retention: %', v_list;
  end if;

  raise notice 'SUBSCRIPTION_EXPIRY_NOTICES_SQL_PASSED';
end;
$test$;

rollback;

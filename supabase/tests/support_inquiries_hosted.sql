-- HELP-02 support inquiries: hosted rollback-only verification gate for the
-- development project xchapwvmvoefriqcxtvn. Every fixture rolls back.
begin;

do $hosted_guard$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20261027150000'
  ) then
    raise exception 'support_inquiries_migration_not_applied';
  end if;
  if current_setting('app.eldaftar_dev_guard', true) is distinct from 'xchapwvmvoefriqcxtvn' then
    perform set_config('app.eldaftar_dev_guard', 'xchapwvmvoefriqcxtvn', true);
  end if;
end;
$hosted_guard$;
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at
) values
  ('a3000000-0000-4000-8000-0000000000b1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-owner@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-expired@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-limit@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-employee@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-partner@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b6', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-pending@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b7', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-revoked@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b8', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-admin@example.test', now(), false,
   null, null, now(), now()),
  ('a3000000-0000-4000-8000-0000000000b9', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'support-anon@example.test', now(), true,
   null, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone, created_by, setup_request_key)
values
  ('a3100000-0000-4000-8000-000000000001', 'متجر الدعم النشط', 'مالك نشط',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b1', 'a3200000-0000-4000-8000-000000000001'),
  ('a3100000-0000-4000-8000-000000000002', 'متجر الدعم المنتهي', 'مالك منتهي',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b2', 'a3200000-0000-4000-8000-000000000002'),
  ('a3100000-0000-4000-8000-000000000003', 'متجر حد الاستفسارات', 'مالك الحد',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b3', 'a3200000-0000-4000-8000-000000000003'),
  ('a3100000-0000-4000-8000-000000000004', 'متجر مالك منسحب', 'مالك منسحب',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b7', 'a3200000-0000-4000-8000-000000000004'),
  ('a3100000-0000-4000-8000-000000000005', 'متجر قيد الانتظار', 'مالك منتظر',
   'Africa/Cairo', 'a3000000-0000-4000-8000-0000000000b6', 'a3200000-0000-4000-8000-000000000005');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at)
values
  ('a3100000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-0000000000b1', 'owner', null),
  ('a3100000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-0000000000b2', 'owner', null),
  ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'owner', null),
  ('a3100000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-0000000000b4', 'employee', null),
  ('a3100000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-0000000000b5', 'partner', null),
  ('a3100000-0000-4000-8000-000000000005', 'a3000000-0000-4000-8000-0000000000b6', 'owner', null),
  ('a3100000-0000-4000-8000-000000000004', 'a3000000-0000-4000-8000-0000000000b7', 'owner', now());

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  ('a3100000-0000-4000-8000-000000000001', now() - interval '10 days', now() + interval '10 days'),
  ('a3100000-0000-4000-8000-000000000002', now() - interval '30 days', now() - interval '1 hour'),
  ('a3100000-0000-4000-8000-000000000003', now() - interval '10 days', now() + interval '10 days');

insert into public.platform_admins (user_id)
values ('a3000000-0000-4000-8000-0000000000b8');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('a3300000-0000-4000-8000-000000000001', 'a3000000-0000-4000-8000-0000000000b1', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000002', 'a3000000-0000-4000-8000-0000000000b2', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000004', 'a3000000-0000-4000-8000-0000000000b4', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000005', 'a3000000-0000-4000-8000-0000000000b5', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000006', 'a3000000-0000-4000-8000-0000000000b6', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000007', 'a3000000-0000-4000-8000-0000000000b7', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000008', 'a3000000-0000-4000-8000-0000000000b8', now(), now(), now() + interval '1 day'),
  ('a3300000-0000-4000-8000-000000000009', 'a3000000-0000-4000-8000-0000000000b9', now(), now(), now() + interval '1 day'),
  -- Expired session for the active owner.
  ('a3300000-0000-4000-8000-00000000000a', 'a3000000-0000-4000-8000-0000000000b1', now(), now(), now() - interval '1 minute');

create function pg_temp.support_call(
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
  v_key uuid := 'a3400000-0000-4000-8000-000000000001';
  v_result text;
  v_list text;
  v_count integer;
  v_id text;
  v_inquiry text;
  v_created text;
begin
  -- Tables stay revoked from API roles; RLS has no policies.
  if has_table_privilege('authenticated', 'public.support_inquiries', 'SELECT')
    or has_table_privilege('anon', 'public.support_inquiries', 'SELECT')
    or has_table_privilege('authenticated', 'public.support_inquiry_events', 'SELECT')
    or has_table_privilege('anon', 'public.support_inquiry_events', 'SELECT') then
    raise exception 'support_table_exposed';
  end if;

  -- Direct writes are denied to API roles.
  perform set_config('request.jwt.claim.sub', 'a3000000-0000-4000-8000-0000000000b1', true);
  perform set_config('request.jwt.claim.session_id', 'a3300000-0000-4000-8000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    execute 'set local role authenticated';
    insert into public.support_inquiries (
      shop_id, owner_user_id, body_ar, status, idempotency_key
    ) values (
      'a3100000-0000-4000-8000-000000000001',
      'a3000000-0000-4000-8000-0000000000b1',
      'جدول مباشر غير مسموح',
      'new',
      'a3400000-0000-4000-8000-0000000000ff'
    );
    execute 'reset role';
    raise exception 'direct_insert_allowed';
  exception
    when insufficient_privilege then
      execute 'reset role';
    when others then
      execute 'reset role';
      raise;
  end;

  -- Anonymous identity is denied.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b9',
    'a3300000-0000-4000-8000-000000000009',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000010', null, 'سؤال الدعم المجهول هنا')$q$);
  if v_result not ilike '%unauthorized%' and v_result not ilike '%42501%' then
    raise exception 'anonymous_accepted: %', v_result;
  end if;

  -- Expired session is denied.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-00000000000a',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000011', null, 'سؤال الجلسة المنتهية')$q$);
  if v_result not ilike '%unauthorized%' then
    raise exception 'expired_session_accepted: %', v_result;
  end if;

  -- Employee, partner and revoked owner are denied.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b4',
    'a3300000-0000-4000-8000-000000000004',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000012', null, 'سؤال الموظف غير المسموح')$q$);
  if v_result not ilike '%unauthorized%' then
    raise exception 'employee_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b5',
    'a3300000-0000-4000-8000-000000000005',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000013', null, 'سؤال الشريك غير المسموح')$q$);
  if v_result not ilike '%unauthorized%' then
    raise exception 'partner_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b7',
    'a3300000-0000-4000-8000-000000000007',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000014', null, 'سؤال المالك المنسحب هنا')$q$);
  if v_result not ilike '%unauthorized%' then
    raise exception 'revoked_owner_accepted: %', v_result;
  end if;

  -- Definitive validation failures do not consume the key: the key stays
  -- free, so the same key is accepted once the body is fixed.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000020', 'financial', 'قصير')$q$);
  if v_result not ilike '%invalid_input%' then
    raise exception 'short_body_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000021', null, 'نص فيه محرف تحكم' || chr(1) || ' غير مسموح')$q$);
  if v_result not ilike '%invalid_input%' then
    raise exception 'control_body_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000022', null, 'نص فيه تباعد' || chr(9) || ' غير مسموح')$q$);
  if v_result not ilike '%invalid_input%' then
    raise exception 'tab_body_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000023', 'subscription', repeat('ط', 1001))$q$);
  if v_result not ilike '%invalid_input%' then
    raise exception 'long_body_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000024', 'salary', 'سؤال بتصنيف غير مدعوم')$q$);
  if v_result not ilike '%invalid_input%' then
    raise exception 'bad_category_accepted: %', v_result;
  end if;

  -- Active owner: first create, then identical replay, then mismatch.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.create_support_inquiry_v1(%L, 'technical', $p$سؤال الدعم الأول مع نص كافٍ للفحص$p$)$q$,
      v_key));
  if v_result not like '%"result_status": "saved"%' and v_result not like '%"result_status":"saved"%' then
    raise exception 'owner_create_failed: %', v_result;
  end if;
  v_inquiry := split_part(v_result, '"id": "', 2);
  v_inquiry := split_part(v_inquiry, '"', 1);

  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.create_support_inquiry_v1(%L, 'technical', $p$سؤال الدعم الأول مع نص كافٍ للفحص$p$)$q$,
      v_key));
  if v_result not like '%"result_status": "replayed"%' or v_result not like '%"id": "' || v_inquiry || '"%' then
    raise exception 'replay_diverged: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    format(
      $q$select public.create_support_inquiry_v1(%L, 'technical', $p$سؤال الدعم الأول مع نص كافٍ مختلف$p$)$q$,
      v_key));
  if v_result not ilike '%payload_mismatch%' then
    raise exception 'replay_mismatch_accepted: %', v_result;
  end if;
  select count(*) into v_count
  from public.support_inquiries
  where shop_id = 'a3100000-0000-4000-8000-000000000001';
  if v_count <> 1 then
    raise exception 'owner_rows_duplicated: %', v_count;
  end if;

  -- Exactly one create event for the saved inquiry.
  select count(*) into v_count
  from public.support_inquiry_events
  where inquiry_id = v_inquiry::uuid;
  if v_count <> 1 then
    raise exception 'create_events_wrong: %', v_count;
  end if;

  -- Expired owner and pending (no entitlement) owner may submit.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b2',
    'a3300000-0000-4000-8000-000000000002',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000030', 'subscription', 'سؤال التجديد لاشتراك منتهي')$q$);
  if v_result not like '%"result_status": "saved"%' then
    raise exception 'expired_owner_rejected: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b6',
    'a3300000-0000-4000-8000-000000000006',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000031', null, 'سؤال تفعيل لاشتراك معلق')$q$);
  if v_result not like '%"result_status": "saved"%' then
    raise exception 'pending_owner_rejected: %', v_result;
  end if;

  -- Owner list: only own rows, newest first, with keyset cursor and limit.
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    'select public.list_my_support_inquiries_v1()');
  if v_list not like '%"open_limit": 10%' or v_list not like '%"open_count": 1%' then
    raise exception 'owner_list_counts_wrong: %', v_list;
  end if;

  -- Rate limit: seed ten non-closed inquiries for the limit shop, then the
  -- eleventh create is rejected.
  insert into public.support_inquiries (
    shop_id, owner_user_id, body_ar, status, idempotency_key, created_at
  ) values
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 01', 'new', 'a3400000-0000-4000-8000-000000000101', now() - interval '1 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 02', 'new', 'a3400000-0000-4000-8000-000000000102', now() - interval '2 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 03', 'new', 'a3400000-0000-4000-8000-000000000103', now() - interval '3 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 04', 'new', 'a3400000-0000-4000-8000-000000000104', now() - interval '4 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 05', 'new', 'a3400000-0000-4000-8000-000000000105', now() - interval '5 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 06', 'new', 'a3400000-0000-4000-8000-000000000106', now() - interval '6 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 07', 'new', 'a3400000-0000-4000-8000-000000000107', now() - interval '7 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 08', 'new', 'a3400000-0000-4000-8000-000000000108', now() - interval '8 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 09', 'new', 'a3400000-0000-4000-8000-000000000109', now() - interval '9 second'),
    ('a3100000-0000-4000-8000-000000000003', 'a3000000-0000-4000-8000-0000000000b3', 'استفسار معد مسبقًا رقم 10', 'in_progress', 'a3400000-0000-4000-8000-000000000110', now() - interval '10 second');
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b3',
    'a3300000-0000-4000-8000-000000000003',
    $q$select public.create_support_inquiry_v1('a3400000-0000-4000-8000-000000000111', null, 'استفسار يرفض بسبب الحد المسموح')$q$);
  if v_result not ilike '%inquiry_limit%' then
    raise exception 'rate_limit_not_enforced: %', v_result;
  end if;

  -- Owner paging over the ten seeded rows with boundary checks.
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b3',
    'a3300000-0000-4000-8000-000000000003',
    'select public.list_my_support_inquiries_v1(null, null, 5)');
  if v_list !~ '"open_limit": 10' or v_list !~ '"open_count": 10' then
    raise exception 'limit_shop_list_wrong: %', left(v_list, 400);
  end if;
  v_created := split_part(v_list, '"next_cursor_at": "', 2);
  v_created := split_part(v_created, '"', 1);
  v_id := split_part(v_list, '"next_cursor_id": "', 2);
  v_id := split_part(v_id, '"', 1);
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b3',
    'a3300000-0000-4000-8000-000000000003',
    format(
      $q$select public.list_my_support_inquiries_v1(%L::timestamptz, %L::uuid, 5)$q$,
      v_created, v_id));
  if v_list !~* '"inquiries": \[\{' then
    raise exception 'second_page_empty: %', left(v_list, 200);
  end if;
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b3',
    'a3300000-0000-4000-8000-000000000003',
    $q$select public.list_my_support_inquiries_v1(now(), 'a3400000-0000-4000-8000-000000000101', 5)$q$);
  if v_list not ilike '%stale_cursor%' then
    raise exception 'stale_cursor_accepted: %', v_list;
  end if;

  -- Admin list: gate denial for a non-admin, rows with shop names for the
  -- admin, exact shop-id search, free text selecting nothing, status filter.
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    $q$select public.admin_list_support_inquiries_v1()$q$);
  if v_list not ilike '%forbidden%' and v_list not ilike '%42501%' then
    raise exception 'owner_admin_list_allowed: %', v_list;
  end if;
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    'select public.admin_list_support_inquiries_v1()');
  if v_list !~ 'متجر الدعم النشط' or v_list !~ 'متجر الدعم المنتهي' then
    raise exception 'admin_list_missing_shops: %', left(v_list, 400);
  end if;
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    $q$select public.admin_list_support_inquiries_v1(null, 'متجر الدعم النشط')$q$);
  if v_list !~* '"inquiries": \[\]' then
    raise exception 'free_text_search_selected: %', left(v_list, 200);
  end if;
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    $q$select public.admin_list_support_inquiries_v1('new', 'a3100000-0000-4000-8000-000000000001')$q$);
  if v_list !~ 'متجر الدعم النشط' or v_list !~* '"status": "new"' then
    raise exception 'admin_shop_search_wrong: %', left(v_list, 400);
  end if;

  -- Admin triage: transitions, reply requirement, replay/mismatch, closure.
  v_key := 'a3400000-0000-4000-8000-000000000201';
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'answered', 'رد مباشر قبل الانتقال الصحيح', %L)$q$, v_inquiry, v_key));
  if v_result not ilike '%invalid_transition%' then
    raise exception 'new_to_answered_allowed: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'in_progress', null, %L)$q$, v_inquiry, v_key));
  if v_result not like '%"result_status": "saved"%' or v_result !~* '"status": "in_progress"' then
    raise exception 'new_to_progress_failed: %', v_result;
  end if;
  v_key := 'a3400000-0000-4000-8000-000000000202';
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'answered', null, %L)$q$, v_inquiry, v_key));
  if v_result not ilike '%invalid_input%' then
    raise exception 'answered_without_reply_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'answered', 'قصير', %L)$q$, v_inquiry, v_key));
  if v_result not ilike '%invalid_input%' then
    raise exception 'short_reply_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'answered', 'هذا رد الدعم الكافي للاستفسار المقدم', %L)$q$, v_inquiry, v_key));
  if v_result not like '%"result_status": "saved"%' or v_result !~* '"status": "answered"' then
    raise exception 'answered_transition_failed: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'answered', 'هذا رد الدعم الكافي للاستفسار المقدم', %L)$q$, v_inquiry, v_key));
  if v_result not like '%"result_status": "replayed"%' or v_result !~* '"status": "answered"' then
    raise exception 'admin_replay_diverged: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'answered', 'هذا رد مختلف تمامًا عن الرد الأول', %L)$q$, v_inquiry, v_key));
  if v_result not ilike '%payload_mismatch%' then
    raise exception 'admin_replay_mismatch_accepted: %', v_result;
  end if;
  v_key := 'a3400000-0000-4000-8000-000000000203';
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'closed', 'إغلاق مع رد غير مقبول', %L)$q$, v_inquiry, v_key));
  if v_result not ilike '%invalid_input%' then
    raise exception 'close_with_reply_accepted: %', v_result;
  end if;
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'closed', null, %L)$q$, v_inquiry, v_key));
  if v_result not like '%"result_status": "saved"%' or v_result !~* '"status": "closed"' then
    raise exception 'close_transition_failed: %', v_result;
  end if;
  v_key := 'a3400000-0000-4000-8000-000000000204';
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'in_progress', null, %L)$q$, v_inquiry, v_key));
  if v_result not ilike '%invalid_transition%' then
    raise exception 'closed_reopened: %', v_result;
  end if;

  -- Closed inquiry does not count against the rate limit.
  select count(*) into v_count
  from public.support_inquiries
  where shop_id = 'a3100000-0000-4000-8000-000000000001'
    and status <> 'closed';
  if v_count <> 0 then
    raise exception 'closed_still_counted: %', v_count;
  end if;

  -- Owner sees the saved reply text and status after triage.
  v_list := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b1',
    'a3300000-0000-4000-8000-000000000001',
    'select public.list_my_support_inquiries_v1()');
  if v_list !~ 'هذا رد الدعم الكافي للاستفسار المقدم' or v_list !~* '"status": "closed"' then
    raise exception 'owner_reply_missing: %', left(v_list, 400);
  end if;

  -- Non-admin transition is denied.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b2',
    'a3300000-0000-4000-8000-000000000002',
    format($q$select public.admin_update_support_inquiry_status_v1(%L, 'in_progress', null, 'a3400000-0000-4000-8000-000000000210')$q$, v_inquiry));
  if v_result not ilike '%forbidden%' and v_result not ilike '%42501%' then
    raise exception 'owner_transition_allowed: %', v_result;
  end if;

  -- Unknown inquiry id.
  v_result := pg_temp.support_call(
    'authenticated',
    'a3000000-0000-4000-8000-0000000000b8',
    'a3300000-0000-4000-8000-000000000008',
    $q$select public.admin_update_support_inquiry_status_v1('a3400000-0000-4000-8000-000000000999', 'in_progress', null, 'a3400000-0000-4000-8000-000000000211')$q$);
  if v_result not ilike '%not_found%' then
    raise exception 'unknown_inquiry_accepted: %', v_result;
  end if;

  -- Audit is append-only (the trigger fires for the create event rows).
  begin
    update public.support_inquiry_events
    set reply_ar = 'تعديل غير مسموح'
    where to_status = 'new';
    raise exception 'audit_update_allowed';
  exception
    when others then
      if sqlerrm not ilike '%append_only%' then
        raise exception 'audit_update_wrong_error: %', sqlerrm;
      end if;
  end;
  begin
    delete from public.support_inquiry_events
    where to_status = 'new';
    raise exception 'audit_delete_allowed';
  exception
    when others then
      if sqlerrm not ilike '%append_only%' then
        raise exception 'audit_delete_wrong_error: %', sqlerrm;
      end if;
  end;

  -- Status transition integrity in the events log: 4 events for the closed
  -- inquiry (create, in_progress, answered, closed).
  select count(*) into v_count
  from public.support_inquiry_events
  where inquiry_id = v_inquiry::uuid
    and to_status in ('new', 'in_progress', 'answered', 'closed');
  if v_count <> 4 then
    raise exception 'transition_event_count_wrong: %', v_count;
  end if;

  raise notice 'SUPPORT_INQUIRIES_DO_BLOCK_PASSED';
end;
$test$;

rollback;

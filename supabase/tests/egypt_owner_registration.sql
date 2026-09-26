-- Egypt owner registration. Synthetic rows only. The final ROLLBACK removes them.
-- No Auth HTTP call and no password is supplied to SQL.
-- psql -v ON_ERROR_STOP=1 -f supabase/tests/egypt_owner_registration.sql
begin;

create procedure pg_temp.expect_error(p_sql text, p_sqlstate text, p_message text)
language plpgsql
as $procedure$
begin
  begin
    execute p_sql;
    raise exception 'statement_succeeded' using errcode = 'P0004';
  exception
    when others then
      if sqlstate = 'P0004' then
        raise exception 'expected % / % but statement succeeded', p_sqlstate, p_message;
      end if;
      if p_message = 'permission denied' then
        if sqlstate is distinct from '42501' or sqlerrm not like 'permission denied%' then
          raise exception 'expected permission denial but got % / %', sqlstate, sqlerrm;
        end if;
      elsif sqlstate is distinct from p_sqlstate or sqlerrm is distinct from p_message then
        raise exception 'expected % / % but got % / %', p_sqlstate, p_message, sqlstate, sqlerrm;
      end if;
  end;
end;
$procedure$;

do $test$
declare
  v_input text;
  v_expected text;
  v_actual text;
begin
  if (select count(*) from public.egypt_governorates) <> 27 then
    raise exception 'governorate count is not 27';
  end if;
  if (select count(distinct display_order) from public.egypt_governorates) <> 27
    or exists (
      select 1 from public.egypt_governorates
      where display_order < 1 or display_order > 27
    ) then
    raise exception 'governorate display order is not 1..27';
  end if;
  if (select name_ar from public.egypt_governorates where code = 'EG-C') <> 'القاهرة' then
    raise exception 'Cairo label mismatch';
  end if;
  if (select name_ar from public.egypt_governorates where code = 'EG-GZ') <> 'الجيزة' then
    raise exception 'Giza label mismatch';
  end if;
  if exists (
    select 1 from public.egypt_governorates
    where code in ('EG-HU', 'EG-SU', 'EG-XX')
  ) then
    raise exception 'obsolete or unknown governorate was seeded';
  end if;

  for v_input, v_expected in
    select sample.input, sample.expected
    from (values
      ('01012345678', '+201012345678'),
      ('01112345678', '+201112345678'),
      ('01212345678', '+201212345678'),
      ('01512345678', '+201512345678'),
      ('+201012345678', '+201012345678'),
      ('00201012345678', '+201012345678'),
      ('  010 1234 5678  ', '+201012345678'),
      ('(010) 1234-5678', '+201012345678'),
      ('+20 10 1234-5678', '+201012345678'),
      ('0020 (10) 1234-5678', '+201012345678'),
      ('010-1234-5678', '+201012345678')
    ) as sample(input, expected)
  loop
    v_actual := private.normalize_egypt_mobile(v_input);
    if v_actual is distinct from v_expected then
      raise exception 'phone % normalized to % expected %', v_input, v_actual, v_expected;
    end if;
  end loop;

  for v_input in
    select sample.input
    from (values
      (null::text),
      (''),
      ('   '),
      ('123'),
      ('0101234567'),
      ('010123456789'),
      ('01312345678'),
      ('01612345678'),
      ('01712345678'),
      ('01812345678'),
      ('01912345678'),
      ('201012345678'),
      ('+2001012345678'),
      ('002001012345678'),
      ('+966501234567'),
      ('+201712345678'),
      ('+2011123456789'),
      ('0223456789'),
      ('010.1234.5678'),
      (E'010\t12345678'),
      (E'010\n12345678'),
      ('01012345678x'),
      ('+1 (201) 555-0123'),
      ('001012345678'),
      ('+2010123456780')
    ) as sample(input)
  loop
    if private.normalize_egypt_mobile(v_input) is not null then
      raise exception 'invalid phone was accepted: %', v_input;
    end if;
  end loop;

  if private.normalize_registration_email('  Owner@Example.Test ') <> 'owner@example.test' then
    raise exception 'email normalization mismatch';
  end if;
  if private.normalize_registration_email('not-an-email') is not null
    or private.normalize_registration_email('a@b') is not null
    or private.normalize_registration_email('a @b.com') is not null
    or private.normalize_registration_email('') is not null
    or private.normalize_registration_email(null) is not null then
    raise exception 'invalid email was accepted';
  end if;
  if not private.auth_phone_matches('201012345678', '+201012345678') then
    raise exception 'Auth digits without plus did not match';
  end if;
  if not private.auth_phone_matches('+20 101-234-5678', '+201012345678') then
    raise exception 'Auth punctuated phone did not match';
  end if;
  if private.auth_phone_matches('201112345678', '+201012345678')
    or private.auth_phone_matches(null, '+201012345678')
    or private.auth_phone_matches('', '+201012345678') then
    raise exception 'different Auth phone matched';
  end if;
end;
$test$;

do $test$
declare
  v_function oid;
begin
  select p.oid into v_function
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'begin_owner_registration';
  if (select oidvectortypes(proargtypes) from pg_proc where oid = v_function)
    is distinct from 'uuid, text, text, text, text, text' then
    raise exception 'begin_owner_registration arguments drifted';
  end if;
  if pg_get_function_arguments(v_function) is distinct from
    'p_request_key uuid, p_owner_display_name text, p_business_name text, p_email text, p_phone text, p_governorate_code text' then
    raise exception 'begin_owner_registration argument names drifted';
  end if;
  if pg_get_function_result(v_function) ilike '%password%' then
    raise exception 'registration result exposes a password field';
  end if;
  if not pg_get_function_result(v_function) like '%auth_phone text%' then
    raise exception 'begin_owner_registration does not return auth_phone';
  end if;
  if exists (
    select 1 from unnest(coalesce((
      select p.proargnames
      from pg_proc as p
      where p.oid = v_function
    ), array[]::text[])) as argument_name
    where argument_name ilike '%password%'
  ) then
    raise exception 'begin_owner_registration accepts a password';
  end if;

  select p.oid into v_function
  from pg_proc as p
  join pg_namespace as n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'complete_owner_registration';
  if pg_get_function_arguments(v_function) is distinct from 'p_request_key uuid'
    or pg_get_function_result(v_function) is distinct from 'uuid' then
    raise exception 'complete_owner_registration signature drifted';
  end if;

  if exists (
    select 1
    from pg_proc as p
    join pg_namespace as n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private')
      and p.proname in (
        'begin_owner_registration',
        'complete_owner_registration',
        'normalize_egypt_mobile',
        'owner_registration_result'
      )
      and (
        not exists (
          select 1 from unnest(coalesce(p.proconfig, array[]::text[])) as config
          where config = 'search_path=""'
        )
        or p.prosrc ilike '%password%'
        or p.prosrc ilike '%encrypted_password%'
      )
  ) then
    raise exception 'registration function search_path or body is unsafe';
  end if;

  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    raise exception 'service_role is missing';
  end if;
  if not has_function_privilege(
    'service_role',
    'public.begin_owner_registration(uuid,text,text,text,text,text)',
    'EXECUTE'
  ) or not has_function_privilege(
    'service_role',
    'public.complete_owner_registration(uuid)',
    'EXECUTE'
  ) then
    raise exception 'service_role cannot run registration';
  end if;
  if has_function_privilege('anon', 'public.begin_owner_registration(uuid,text,text,text,text,text)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.begin_owner_registration(uuid,text,text,text,text,text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.complete_owner_registration(uuid)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.complete_owner_registration(uuid)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.create_shop_account(text,text,text,text,uuid)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.create_shop_account(text,text,text,text,uuid)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.create_staff_invitation(uuid,text,text,uuid,uuid)', 'EXECUTE')
    or has_function_privilege('service_role', 'public.accept_staff_invitation(uuid)', 'EXECUTE') then
    raise exception 'registration or legacy RPC grant is too wide';
  end if;
  if not has_function_privilege('authenticated', 'public.set_staff_permission(uuid,uuid,text,boolean,uuid)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.revoke_staff_member(uuid,uuid,uuid)', 'EXECUTE') then
    raise exception 'staff grant or revoke execute changed';
  end if;

  if not (
    select c.relrowsecurity and c.relforcerowsecurity
    from pg_class as c
    join pg_namespace as n on n.oid = c.relnamespace
    where n.nspname = 'private' and c.relname = 'owner_registration_reservations'
  ) then
    raise exception 'reservation RLS is not forced';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'private' and tablename = 'owner_registration_reservations'
  ) then
    raise exception 'reservation table has a client policy';
  end if;
  if (
    select count(*) from pg_policies
    where schemaname = 'public'
      and tablename = 'egypt_governorates'
      and cmd = 'SELECT'
  ) <> 1 or exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'egypt_governorates'
      and cmd <> 'SELECT'
  ) then
    raise exception 'governorate policies are not read-only';
  end if;
  if has_table_privilege('authenticated', 'public.shops', 'UPDATE')
    or has_table_privilege('authenticated', 'public.shops', 'INSERT')
    or has_table_privilege('anon', 'public.egypt_governorates', 'INSERT')
    or has_table_privilege('authenticated', 'public.egypt_governorates', 'UPDATE')
    or has_table_privilege('authenticated', 'private.owner_registration_reservations', 'SELECT') then
    raise exception 'direct profile or governorate write was granted';
  end if;
  if not has_table_privilege('anon', 'public.egypt_governorates', 'SELECT')
    or not has_table_privilege('authenticated', 'public.egypt_governorates', 'SELECT') then
    raise exception 'governorate dropdown is not readable';
  end if;
end;
$test$;

set local role anon;
do $test$
begin
  if (select count(*) from public.egypt_governorates) <> 27 then
    raise exception 'anonymous governorate read failed';
  end if;
end;
$test$;
call pg_temp.expect_error(
  $sql$insert into public.egypt_governorates (code, name_ar, display_order)
    values ('EG-ZZ', 'اختبار', 28)$sql$,
  '42501',
  'permission denied'
);
reset role;

set local role authenticated;
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa',
    'مالك الاختبار',
    'متجر الاختبار',
    'owner@example.test',
    '01012345678',
    'EG-GZ'
  )$sql$,
  '42501',
  'permission denied'
);
call pg_temp.expect_error(
  $sql$update public.egypt_governorates set name_ar = 'تغيير' where code = 'EG-C'$sql$,
  '42501',
  'permission denied'
);
reset role;

set local role anon;
call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-0000000000aa')$sql$,
  '42501',
  'permission denied'
);
reset role;

call pg_temp.expect_error(
  $sql$insert into public.shops (name, owner_display_name, email, governorate_code, phone, time_zone)
    values ('متجر غير مكتمل', 'مالك الاختبار', 'incomplete@example.test', 'EG-C', null, 'Africa/Cairo')$sql$,
  '23514',
  'new row for relation "shops" violates check constraint "shops_registered_profile_check"'
);

call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    null, 'مالك الاختبار', 'متجر الاختبار', 'owner@example.test', '01012345678', 'EG-GZ'
  )$sql$,
  '22023',
  'invalid_registration'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', '   ', 'متجر الاختبار', 'owner@example.test', '01012345678', 'EG-GZ'
  )$sql$,
  '22023',
  'invalid_registration'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', null, 'owner@example.test', '01012345678', 'EG-GZ'
  )$sql$,
  '22023',
  'invalid_registration'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', 'متجر الاختبار', 'not-an-email', '01012345678', 'EG-GZ'
  )$sql$,
  '22023',
  'invalid_email'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', 'متجر الاختبار', 'owner@example.test', '01312345678', 'EG-GZ'
  )$sql$,
  '22023',
  'invalid_phone'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', 'متجر الاختبار', 'owner@example.test', '+966501234567', 'EG-GZ'
  )$sql$,
  '22023',
  'invalid_phone'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', 'متجر الاختبار', 'owner@example.test', '01012345678', 'الجيزة'
  )$sql$,
  '22023',
  'invalid_governorate'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', 'متجر الاختبار', 'owner@example.test', '01012345678', 'eg-gz'
  )$sql$,
  '22023',
  'invalid_governorate'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-0000000000aa', 'مالك الاختبار', 'متجر الاختبار', 'owner@example.test', '01012345678', 'EG-HU'
  )$sql$,
  '22023',
  'invalid_governorate'
);
call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-0000000000aa')$sql$,
  'P0002',
  'registration_not_found'
);

do $test$
begin
  if exists (select 1 from private.owner_registration_reservations)
    or exists (select 1 from public.shops where email is not null) then
    raise exception 'invalid registration persisted a profile';
  end if;
end;
$test$;

set local role service_role;
select
  set_config('test.reserved_user_id', reserved_user_id::text, true),
  set_config('test.request_key', request_key::text, true)
from public.begin_owner_registration(
  'c0c0c0c0-0000-4000-8000-000000000001',
  '  مالك الاختبار  ',
  'متجر الجيزة',
  '  Owner@Example.Test ',
  '(010) 1234-5678',
  ' EG-GZ '
);
reset role;

do $test$
declare
  v_reserved uuid := current_setting('test.reserved_user_id')::uuid;
  v_replay uuid;
  v_count integer;
begin
  if v_reserved::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'reserved user id is not UUID v4';
  end if;
  select reserved_user_id into v_replay
  from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000001',
    'مالك الاختبار',
    'متجر الجيزة',
    'owner@example.test',
    '+20 10 1234 5678',
    'EG-GZ'
  );
  if v_replay <> v_reserved then
    raise exception 'replay allocated a second Auth id';
  end if;
  select count(*) into v_count from private.owner_registration_reservations;
  if v_count <> 1 then
    raise exception 'replay created another reservation';
  end if;
  if exists (
    select 1
    from private.owner_registration_reservations
    where request_key = 'c0c0c0c0-0000-4000-8000-000000000001'
      and (
        email <> 'owner@example.test'
        or phone <> '+201012345678'
        or owner_display_name <> 'مالك الاختبار'
        or business_name <> 'متجر الجيزة'
        or governorate_code <> 'EG-GZ'
        or status <> 'reserved'
        or shop_id is not null
        or created_at is null
      )
  ) then
    raise exception 'reserved profile was not canonical';
  end if;
  if exists (select 1 from auth.users where id = v_reserved)
    or exists (select 1 from public.shop_memberships where user_id = v_reserved)
    or exists (select 1 from public.shop_entitlements) then
    raise exception 'reservation created an Auth user, membership, or entitlement';
  end if;
  if (
    select auth_phone from public.begin_owner_registration(
      'c0c0c0c0-0000-4000-8000-000000000001',
      'مالك الاختبار',
      'متجر الجيزة',
      'owner@example.test',
      '01012345678',
      'EG-GZ'
    )
  ) <> '201012345678' then
    raise exception 'auth_phone was not digits without a plus';
  end if;
end;
$test$;

call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000001',
    'مالك آخر',
    'متجر الجيزة',
    'owner@example.test',
    '01012345678',
    'EG-GZ'
  )$sql$,
  '23505',
  'request_key_reused'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000002',
    'مالك الاختبار',
    'متجر آخر',
    'other@example.test',
    '00201012345678',
    'EG-C'
  )$sql$,
  '23505',
  'identifier_already_registered'
);

insert into auth.users (
  id, instance_id, aud, role, email, phone, email_confirmed_at, phone_confirmed_at,
  raw_user_meta_data, created_at, updated_at
) values (
  'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0',
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'taken@example.test',
  '201111111111',
  null,
  null,
  '{"role":"owner","is_platform_admin":true}'::jsonb,
  now(),
  now()
);

call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000003',
    'مالك الاختبار',
    'متجر مكرر',
    'TAKEN@example.test',
    '01212345678',
    'EG-C'
  )$sql$,
  '23505',
  'identifier_already_registered'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000004',
    'مالك الاختبار',
    'متجر مكرر',
    'fresh@example.test',
    '011 1111 1111',
    'EG-C'
  )$sql$,
  '23505',
  'identifier_already_registered'
);

do $test$
begin
  if (select count(*) from private.owner_registration_reservations) <> 1 then
    raise exception 'duplicate identifier created a reservation';
  end if;
  if (select owner_display_name from private.owner_registration_reservations) <> 'مالك الاختبار' then
    raise exception 'rejected replay changed the reserved name';
  end if;
end;
$test$;

call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001')$sql$,
  'P0001',
  'auth_user_not_ready'
);

insert into auth.users (
  id, instance_id, aud, role, email, phone, email_confirmed_at, phone_confirmed_at,
  encrypted_password, raw_user_meta_data, created_at, updated_at
) values (
  current_setting('test.reserved_user_id')::uuid,
  '00000000-0000-0000-0000-000000000000',
  'authenticated',
  'authenticated',
  'Owner@example.test',
  '201599999999',
  null,
  null,
  null,
  '{"role":"owner"}'::jsonb,
  now(),
  now()
);

call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001')$sql$,
  '42501',
  'auth_contact_mismatch'
);

update auth.users
set phone = '201012345678'
where id = current_setting('test.reserved_user_id')::uuid;

update auth.users
set email = 'wrong@example.test'
where id = current_setting('test.reserved_user_id')::uuid;

call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001')$sql$,
  '42501',
  'auth_contact_mismatch'
);

update auth.users
set email = 'owner@example.test',
    is_anonymous = true
where id = current_setting('test.reserved_user_id')::uuid;

call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001')$sql$,
  'P0001',
  'auth_user_not_ready'
);

update auth.users
set is_anonymous = false,
    deleted_at = now()
where id = current_setting('test.reserved_user_id')::uuid;

call pg_temp.expect_error(
  $sql$select public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001')$sql$,
  'P0001',
  'auth_user_not_ready'
);

update auth.users
set deleted_at = null
where id = current_setting('test.reserved_user_id')::uuid;

do $test$
begin
  if exists (
    select 1 from public.shop_memberships
    where user_id = current_setting('test.reserved_user_id')::uuid
  ) or exists (
    select 1 from public.shops where email = 'owner@example.test'
  ) or (
    select status from private.owner_registration_reservations
    where request_key = 'c0c0c0c0-0000-4000-8000-000000000001'
  ) <> 'reserved' then
    raise exception 'failed completion left a profile or consumed the reservation';
  end if;
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('test.reserved_user_id'), true);
do $test$
begin
  if exists (select 1 from public.shops)
    or exists (select 1 from public.list_my_shop_accounts())
    or private.is_active_shop_member('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa') then
    raise exception 'Auth user gained shop access before completion';
  end if;
end;
$test$;
call pg_temp.expect_error(
  $sql$select count(*) from private.owner_registration_reservations$sql$,
  '42501',
  'permission denied'
);
reset role;

do $test$
begin
  begin
    create function public.egypt_registration_test_fail_shop()
    returns trigger
    language plpgsql
    security invoker
    set search_path = ''
    as $fn$
    begin
      raise exception 'forced_shop_failure' using errcode = 'P0001';
    end;
    $fn$;

    create trigger egypt_registration_test_fail_shop
    before insert on public.shops
    for each row
    execute function public.egypt_registration_test_fail_shop();

    perform public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001');
    raise exception 'completion_succeeded' using errcode = 'P0004';
  exception
    when others then
      if sqlerrm is distinct from 'forced_shop_failure' then
        raise;
      end if;
  end;
  if exists (select 1 from pg_trigger where tgname = 'egypt_registration_test_fail_shop') then
    raise exception 'forced failure trigger survived its subtransaction';
  end if;
  if exists (select 1 from public.shops where email = 'owner@example.test')
    or exists (
      select 1 from public.shop_memberships
      where user_id = current_setting('test.reserved_user_id')::uuid
    )
    or (
      select status from private.owner_registration_reservations
      where request_key = 'c0c0c0c0-0000-4000-8000-000000000001'
    ) <> 'reserved' then
    raise exception 'forced completion failure was not atomic';
  end if;
end;
$test$;

select set_config(
  'test.shop_id',
  public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001')::text,
  true
);

do $test$
declare
  v_shop uuid := current_setting('test.shop_id')::uuid;
  v_retry uuid;
begin
  v_retry := public.complete_owner_registration('c0c0c0c0-0000-4000-8000-000000000001');
  if v_retry <> v_shop then
    raise exception 'completion retry created another shop';
  end if;
  if (
    select count(*) from public.shops
    where id = v_shop
      and name = 'متجر الجيزة'
      and owner_display_name = 'مالك الاختبار'
      and email = 'owner@example.test'
      and phone = '+201012345678'
      and governorate_code = 'EG-GZ'
      and time_zone = 'Africa/Cairo'
      and created_by = current_setting('test.reserved_user_id')::uuid
      and setup_request_key = 'c0c0c0c0-0000-4000-8000-000000000001'
  ) <> 1 then
    raise exception 'completed shop profile mismatch';
  end if;
  if (select count(*) from public.shop_memberships
        where shop_id = v_shop
          and user_id = current_setting('test.reserved_user_id')::uuid
          and role = 'owner'
          and revoked_at is null) <> 1 then
    raise exception 'completed owner membership mismatch';
  end if;
  if exists (select 1 from public.shop_entitlements where shop_id = v_shop) then
    raise exception 'registration created an entitlement or trial';
  end if;
  if (select count(*) from public.identity_audit_events
        where shop_id = v_shop
          and action = 'owner_registered'
          and correlation_id = 'c0c0c0c0-0000-4000-8000-000000000001'
          and details = jsonb_build_object('governorate_code', 'EG-GZ')) <> 1 then
    raise exception 'registration audit mismatch';
  end if;
  if (
    select reserved_user_id = current_setting('test.reserved_user_id')::uuid
      and status = 'completed'
      and shop_id = v_shop
    from public.begin_owner_registration(
      'c0c0c0c0-0000-4000-8000-000000000001',
      'مالك الاختبار',
      'متجر الجيزة',
      'OWNER@example.test',
      '00201012345678',
      'EG-GZ'
    )
  ) is not true then
    raise exception 'completed replay did not return the original reservation';
  end if;
  if exists (
    select 1 from public.identity_audit_events
    where details::text ilike '%password%' or details::text ilike '%201012345678%'
  ) then
    raise exception 'audit stored a secret or phone';
  end if;
  if exists (
    select 1
    from information_schema.columns
    where table_schema in ('public', 'private')
      and column_name ilike '%password%'
  ) then
    raise exception 'a shop or reservation table stores a password';
  end if;
  if (select encrypted_password from auth.users
      where id = current_setting('test.reserved_user_id')::uuid) is not null then
    raise exception 'SQL fixture stored a password hash';
  end if;
  if (
    select status = 'completed' and shop_id = v_shop and completed_at is not null
    from private.owner_registration_reservations
    where request_key = 'c0c0c0c0-0000-4000-8000-000000000001'
  ) is not true then
    raise exception 'reservation was not marked completed';
  end if;
end;
$test$;

call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000001',
    'مالك الاختبار',
    'اسم مختلف',
    'owner@example.test',
    '01012345678',
    'EG-GZ'
  )$sql$,
  '23505',
  'request_key_reused'
);
call pg_temp.expect_error(
  $sql$select count(*) from public.begin_owner_registration(
    'c0c0c0c0-0000-4000-8000-000000000005',
    'مالك الاختبار',
    'متجر ثان',
    'owner@example.test',
    '01512345678',
    'EG-C'
  )$sql$,
  '23505',
  'identifier_already_registered'
);

do $test$
begin
  if (select count(*) from public.shops where created_by = current_setting('test.reserved_user_id')::uuid) <> 1
    or (select count(*) from private.owner_registration_reservations) <> 1 then
    raise exception 'retry after completion duplicated a shop or reservation';
  end if;
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub', current_setting('test.reserved_user_id'), true);
do $test$
declare
  v_shop uuid := current_setting('test.shop_id')::uuid;
begin
  if exists (select 1 from public.shops) then
    raise exception 'pending shop was visible through membership RLS';
  end if;
  if (select count(*) from public.list_my_shop_accounts()
        where shop_id = v_shop
          and shop_name = 'متجر الجيزة'
          and member_role = 'owner'
          and subscription_expires_at is null
          and entitlement_status = 'pending') <> 1 then
    raise exception 'pending registration missing from account list';
  end if;
  if private.can_write_shop(v_shop) or private.is_active_shop_member(v_shop) then
    raise exception 'pending shop can write or counts as an active entitlement';
  end if;
  if public.is_platform_admin() then
    raise exception 'user metadata was treated as platform admin';
  end if;
end;
$test$;
call pg_temp.expect_error(
  $sql$update public.shops
    set governorate_code = 'EG-C', email = 'changed@example.test', phone = '+201512345678'
    where id = current_setting('test.shop_id')::uuid$sql$,
  '42501',
  'permission denied'
);
reset role;

-- Isolation fixtures are separate from the registration above.
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at)
values
  ('10101010-1010-4010-8010-101010101010', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iso-owner@example.test', null, false, now(), now()),
  ('20202020-2020-4020-8020-202020202020', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iso-other@example.test', null, false, now(), now()),
  ('30303030-3030-4030-8030-303030303030', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iso-revoked@example.test', null, false, now(), now()),
  ('40404040-4040-4040-8040-404040404040', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iso-anon@example.test', null, true, now(), now()),
  ('50505050-5050-4050-8050-505050505050', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'iso-platform@example.test', null, false, now(), now());

insert into public.shops (id, name) values
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', 'متجر العزل'),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', 'متجر منته');
insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', '10101010-1010-4010-8010-101010101010', 'owner', null),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', '20202020-2020-4020-8020-202020202020', 'owner', null),
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', '30303030-3030-4030-8030-303030303030', 'employee', now()),
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', '40404040-4040-4040-8040-404040404040', 'employee', null);
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', now() - interval '1 day', now() + interval '1 day'),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', now() - interval '2 days', now() - interval '1 day');
insert into public.shop_member_grants (shop_id, user_id, permission)
values ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', '30303030-3030-4030-8030-303030303030', 'sale');
insert into public.platform_admins (user_id)
values ('50505050-5050-4050-8050-505050505050');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10101010-1010-4010-8010-101010101010', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1 then
    raise exception 'owner shop isolation failed';
  end if;
  if private.is_active_shop_member('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2') then
    raise exception 'cross-shop membership passed';
  end if;
end;
$test$;
call pg_temp.expect_error(
  $sql$select public.set_staff_permission(
    'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2',
    '30303030-3030-4030-8030-303030303030',
    'sale',
    true,
    'c3c3c3c3-0000-4000-8000-000000000003'
  )$sql$,
  '42501',
  'owner_required'
);

select set_config('request.jwt.claim.sub', '20202020-2020-4020-8020-202020202020', true);
do $test$
begin
  if (select count(*) from public.shops) <> 1 then
    raise exception 'expired shop read denied';
  end if;
  if private.can_write_shop('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2') then
    raise exception 'expired shop write passed';
  end if;
  if (select entitlement_status from public.list_my_shop_accounts()) <> 'expired' then
    raise exception 'expired account list status mismatch';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '30303030-3030-4030-8030-303030303030', true);
do $test$
begin
  if exists (select 1 from public.shops) or private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1') then
    raise exception 'revoked member retained access';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '40404040-4040-4040-8040-404040404040', true);
do $test$
begin
  if exists (select 1 from public.shops)
    or private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1')
    or public.is_platform_admin() then
    raise exception 'anonymous actor gained access';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '50505050-5050-4050-8050-505050505050', true);
do $test$
begin
  if not public.is_platform_admin() then
    raise exception 'unconfirmed platform admin was denied';
  end if;
  if exists (select 1 from public.shops) then
    raise exception 'platform admin inherited shop access';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', 'd0d0d0d0-d0d0-40d0-80d0-d0d0d0d0d0d0', true);
do $test$
begin
  if public.is_platform_admin() or exists (select 1 from public.shops) then
    raise exception 'metadata-only admin or shop claim was accepted';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '10101010-1010-4010-8010-101010101010', true);
select set_config('request.jwt.claim.session_id', 'not-a-uuid', true);
do $test$
begin
  if private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1')
    or exists (select 1 from public.list_my_shop_accounts()) then
    raise exception 'malformed session id was accepted';
  end if;
end;
$test$;
reset role;

insert into auth.sessions (id, user_id, created_at, updated_at, not_after)
values
  ('12121212-1212-4121-8121-121212121212', '10101010-1010-4010-8010-101010101010', now(), now(), now() + interval '1 day'),
  ('13131313-1313-4131-8131-131313131313', '20202020-2020-4020-8020-202020202020', now(), now(), null);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10101010-1010-4010-8010-101010101010', true);
select set_config('request.jwt.claim.session_id', '12121212-1212-4121-8121-121212121212', true);
do $test$
begin
  if not private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1') then
    raise exception 'live session was rejected';
  end if;
end;
$test$;
select set_config('request.jwt.claim.session_id', '13131313-1313-4131-8131-131313131313', true);
do $test$
begin
  if private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1') then
    raise exception 'another user session was accepted';
  end if;
end;
$test$;
reset role;

update auth.sessions
set not_after = now() - interval '1 minute'
where id = '12121212-1212-4121-8121-121212121212';

set local role authenticated;
select set_config('request.jwt.claim.sub', '10101010-1010-4010-8010-101010101010', true);
select set_config('request.jwt.claim.session_id', '12121212-1212-4121-8121-121212121212', true);
do $test$
begin
  if private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1') then
    raise exception 'expired session was accepted';
  end if;
end;
$test$;
select set_config('request.jwt.claim.session_id', '', true);
select set_config('request.jwt.claims', '{"session_id":"13131313-1313-4131-8131-131313131313"}', true);
do $test$
begin
  if private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1') then
    raise exception 'claims session for another user was accepted';
  end if;
end;
$test$;
select set_config('request.jwt.claims', '', true);
do $test$
begin
  if not private.is_active_shop_member('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1') then
    raise exception 'fixture without a session claim lost access';
  end if;
end;
$test$;
reset role;

select 'egypt_owner_registration_passed' as test_result;
rollback;

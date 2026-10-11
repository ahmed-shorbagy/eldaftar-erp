-- Synthetic local regression; every created row rolls back.
begin;
do $test$
declare v_registration record; v_shop uuid; v_replay uuid;
begin
  if has_function_privilege('anon', 'public.begin_owner_registration(uuid,text,text,text,text,text)', 'execute')
    or has_function_privilege('authenticated', 'public.complete_owner_registration(uuid)', 'execute') then
    raise exception 'registration_rpc_exposed';
  end if;
  if private.registration_phone('0501234567', 'SA:الرياض') <> '+966501234567'
    or private.registration_phone('+971501234567', 'SA:الرياض') is not null
    or private.registration_region_valid('SA:')
    or not private.registration_region_stored_valid('SA:')
    or private.registration_region_valid('ZZ:منطقة') then raise exception 'country_validation'; end if;
  select * into v_registration from public.begin_owner_registration(
    'feed0001-0000-4000-8000-000000000001', 'مالك تجريبي', 'محل تجريبي',
    'feedback-owner@example.test', '0501234567', 'SA:الرياض');
  insert into auth.users(id, email, phone, is_anonymous)
    values(v_registration.reserved_user_id, v_registration.email, v_registration.auth_phone, false);
  v_shop := public.complete_owner_registration(v_registration.request_key);
  v_replay := public.complete_owner_registration(v_registration.request_key);
  if v_shop <> v_replay then raise exception 'duplicate_shop'; end if;
  if not exists(select 1 from public.shops where id = v_shop and country_code = 'SA'
    and region_name = 'الرياض' and time_zone = 'Asia/Riyadh' and phone = '+966501234567') then
    raise exception 'international_profile_not_saved'; end if;
  if (select count(*) from public.shop_memberships where shop_id = v_shop) <> 1
    or (select count(*) from public.identity_audit_events where shop_id = v_shop and action = 'owner_registered') <> 1
    or exists(select 1 from public.shop_entitlements where shop_id = v_shop) then
    raise exception 'owner_boundary'; end if;
  begin
    perform public.begin_owner_registration(v_registration.request_key, 'مالك تجريبي', 'محل تجريبي',
      'feedback-owner@example.test', '0501234567', 'SA:جدة');
    raise exception 'changed_region_replayed';
  exception when unique_violation then null; end;
  begin
    perform public.begin_owner_registration('feed0001-0000-4000-8000-000000000002', 'مالك آخر', 'محل آخر',
      'feedback-other@example.test', '+966501234567', 'SA:الرياض');
    raise exception 'duplicate_identifier_reserved';
  exception when unique_violation then null; end;
  begin
    perform public.begin_owner_registration(
      'feed0001-0000-4000-8000-000000000003', 'مالك بدون منطقة', 'محل بدون منطقة',
      'feedback-optional@example.test', '0507654321', 'SA:');
    raise exception 'empty_region_accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'invalid_governorate' then raise; end if;
  end;
  insert into private.owner_registration_reservations (
    request_key, reserved_user_id, email, phone, owner_display_name, business_name,
    governorate_code, status, created_at
  ) values (
    'feed0001-0000-4000-8000-000000000003', gen_random_uuid(),
    'feedback-optional@example.test', '+966507654321', 'مالك بدون منطقة', 'محل بدون منطقة',
    'SA:', 'reserved', clock_timestamp()
  );
  select * into v_registration from public.begin_owner_registration(
    'feed0001-0000-4000-8000-000000000003', 'مالك بدون منطقة', 'محل بدون منطقة',
    'feedback-optional@example.test', '0507654321', 'SA:');
  insert into auth.users(id, email, phone, is_anonymous)
    values(v_registration.reserved_user_id, v_registration.email, v_registration.auth_phone, false);
  v_shop := public.complete_owner_registration(v_registration.request_key);
  if public.complete_owner_registration(v_registration.request_key) <> v_shop
    or not exists(select 1 from public.shops where id = v_shop and country_code = 'SA'
      and region_name = '' and time_zone = 'Asia/Riyadh' and phone = '+966507654321')
    or (select count(*) from public.shop_memberships where shop_id = v_shop) <> 1
    or (select count(*) from public.identity_audit_events where shop_id = v_shop and action = 'owner_registered') <> 1 then
    raise exception 'legacy_empty_region_replay';
  end if;
  begin
    perform public.begin_owner_registration(v_registration.request_key, 'مالك بدون منطقة', 'محل بدون منطقة',
      'feedback-optional@example.test', '0507654321', 'SA:الرياض');
    raise exception 'optional_region_replay_mutated';
  exception when unique_violation then null; end;
  if private.registration_region_valid('EG:')
    or not private.registration_region_stored_valid('EG:')
    or private.registration_phone('01012345678', 'EG:') <> '+201012345678'
    or private.registration_region_valid('EG:الجيزة')
    or not private.registration_region_stored_valid('EG:الجيزة')
    or private.registration_region_valid('SA: ')
    or private.registration_region_valid('ZZ:')
    or private.registration_region_valid('SA:' || repeat('أ',121)) then
    raise exception 'required_region_boundary';
  end if;
  begin
    perform public.begin_owner_registration(
      'feed0001-0000-4000-8000-000000000004', 'مالك جيزة قديم', 'محل جيزة قديم',
      'feedback-eg-text@example.test', '01076543210', 'EG:الجيزة');
    raise exception 'egypt_manual_region_accepted';
  exception when invalid_parameter_value then
    if sqlerrm <> 'invalid_governorate' then raise; end if;
  end;
  insert into private.owner_registration_reservations (
    request_key, reserved_user_id, email, phone, owner_display_name, business_name,
    governorate_code, status, created_at
  ) values (
    'feed0001-0000-4000-8000-000000000004', gen_random_uuid(),
    'feedback-eg-text@example.test', '+201076543210', 'مالك جيزة قديم', 'محل جيزة قديم',
    'EG:الجيزة', 'reserved', clock_timestamp()
  );
  select * into v_registration from public.begin_owner_registration(
    'feed0001-0000-4000-8000-000000000004', 'مالك جيزة قديم', 'محل جيزة قديم',
    'feedback-eg-text@example.test', '01076543210', 'EG:الجيزة');
  insert into auth.users(id, email, phone, is_anonymous)
    values(v_registration.reserved_user_id, v_registration.email, v_registration.auth_phone, false);
  v_shop := public.complete_owner_registration(v_registration.request_key);
  if public.complete_owner_registration(v_registration.request_key) <> v_shop
    or not exists(select 1 from public.shops where id = v_shop and governorate_code = 'EG:الجيزة'
      and phone = '+201076543210') then
    raise exception 'legacy_egypt_text_region_replay';
  end if;

end;
$test$;
rollback;

-- Automatic customer capture from sales and purchases (ADR 0043). Rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('d1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'capture-owner@example.test', false, now(), now()),
  ('d1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'capture-staff@example.test', false, now(), now()),
  ('d1100000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'capture-other@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('d2200000-0000-4000-8000-000000000001', 'متجر الالتقاط', 'مالك الالتقاط', 'Africa/Cairo'),
  ('d2200000-0000-4000-8000-000000000002', 'متجر الالتقاط الآخر', 'مالك آخر', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role) values
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000001', 'owner'),
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000002', 'employee'),
  ('d2200000-0000-4000-8000-000000000002', 'd1100000-0000-4000-8000-000000000003', 'owner');

insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000002', 'sale', 'd1100000-0000-4000-8000-000000000001');

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('d2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days'),
  ('d2200000-0000-4000-8000-000000000002', now() - interval '1 day', now() + interval '30 days');

create temp table capture_ops (name text primary key, operation_id uuid);
grant select, insert on capture_ops to authenticated;

create function pg_temp.trade(
  p_key uuid, p_kind text, p_name text, p_phone text
) returns uuid
language plpgsql
security invoker
set search_path = ''
as $fn$
declare
  v_item jsonb;
  v_payload jsonb;
  v_result jsonb;
begin
  if p_kind = 'purchase' then
    -- jsonb_build_object drops SQL nulls; count must stay present as JSON null.
    v_item := '{"category":"scrap","karat":21,"milligrams":"500","count":null,"item_name":"كسر","line_price_piastres":null}'::jsonb;
  else
    v_item := jsonb_build_object(
      'category', 'worked_jewelry', 'karat', 21, 'milligrams', '500',
      'count', '1', 'item_name', 'خاتم', 'line_price_piastres', null
    );
  end if;
  v_payload := jsonb_build_object(
    'version', 1, 'kind', p_kind, 'total_piastres', '1000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1000')),
    'items', jsonb_build_array(v_item),
    'description', '', 'customer_name', p_name, 'customer_phone', p_phone, 'note', ''
  );
  v_result := public.post_daily_ledger_trade(p_key, v_payload);
  if v_result ->> 'operation_id' is null then
    raise exception 'trade_failed %', v_result;
  end if;
  return (v_result ->> 'operation_id')::uuid;
end;
$fn$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'd3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"50000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"40000","count":"30"}],"scrap":[{"karat":21,"milligrams":"20000"}]}'::jsonb
);

do $capture$
declare
  v_shop uuid := 'd2200000-0000-4000-8000-000000000001';
  v_sale uuid;
  v_second uuid;
  v_purchase uuid;
  v_sara uuid;
  v_sara2 uuid;
  v_sara3 uuid;
  v_archived jsonb;
  v_latin uuid;
  v_invalid uuid;
  v_customer uuid;
  v_name text;
  v_links integer;
begin
  v_sale := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000011', 'sale', 'محمد أحمد', '01012345678'
  );
  insert into capture_ops values ('first', v_sale);
  select customer.id, customer.display_name into v_customer, v_name
  from public.customers as customer
  join public.customer_phones as phone
    on phone.shop_id = customer.shop_id and phone.customer_id = customer.id
  where customer.shop_id = v_shop and phone.normalized_number = '+201012345678';
  if v_name is distinct from 'محمد أحمد'
    or (select count(*) from public.customers where shop_id = v_shop) <> 1
    or (select is_primary from public.customer_phones where customer_id = v_customer) is not true
    or not exists (
      select 1 from public.customer_operation_links
      where shop_id = v_shop and customer_id = v_customer
        and operation_id = v_sale and status = 'active'
    ) then
    raise exception 'first_capture_wrong %', v_name;
  end if;

  v_second := pg_temp.trade(
    -- Trade payload rejects spaced phones; E.164 without spaces still differs from 010… and normalizes equal.
    'd3300000-0000-4000-8000-000000000012', 'sale', 'أبو أحمد', '+201012345678'
  );
  if (select display_name from public.customers where id = v_customer) is distinct from 'محمد أحمد'
    or (select count(*) from public.customers where shop_id = v_shop) <> 1
    or not exists (
      select 1 from public.customer_operation_links
      where customer_id = v_customer and operation_id = v_second and status = 'active'
    ) then
    raise exception 'phone_match_renamed_or_duplicated';
  end if;

  v_purchase := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000013', 'purchase', 'محمد', '01012345678'
  );
  if not exists (
    select 1 from public.customer_operation_links as link
    join public.financial_operations as operation on operation.id = link.operation_id
    where link.customer_id = v_customer and link.operation_id = v_purchase
      and link.status = 'active' and operation.kind = 'purchase'
  ) then
    raise exception 'purchase_not_linked';
  end if;

  v_sara := pg_temp.trade('d3300000-0000-4000-8000-000000000014', 'sale', 'سارة', '');
  v_sara2 := pg_temp.trade('d3300000-0000-4000-8000-000000000015', 'sale', 'سارة', '');
  if (select count(*) from public.customers
      where shop_id = v_shop and display_name = 'سارة') <> 1
    or exists (
      select 1 from public.customer_phones as phone
      join public.customers as customer on customer.id = phone.customer_id
      where customer.display_name = 'سارة' and customer.shop_id = v_shop
    )
    or (
      select count(*) from public.customer_operation_links as link
      join public.customers as customer on customer.id = link.customer_id
      where customer.display_name = 'سارة' and link.status = 'active'
        and link.operation_id in (v_sara, v_sara2)
    ) <> 2 then
    raise exception 'name_only_capture_wrong';
  end if;
  perform public.post_customer_create_v1(
    'd3300000-0000-4000-8000-000000000016',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_create', 'display_name', 'سارة',
      'phones', '[]'::jsonb, 'is_vip', false, 'has_open_request', false
    )
  );
  v_sara3 := pg_temp.trade('d3300000-0000-4000-8000-000000000017', 'sale', 'سارة', '');
  if exists (
    select 1 from public.customer_operation_links
    where operation_id = v_sara3 and status = 'active'
  ) then
    raise exception 'ambiguous_name_linked';
  end if;

  v_archived := (
    public.post_customer_create_v1(
      'd3300000-0000-4000-8000-000000000018',
      jsonb_build_object(
        'version', 1, 'kind', 'customer_create', 'display_name', 'عميل مؤرشف',
        'phones', jsonb_build_array(jsonb_build_object('number', '01055556677', 'is_primary', true)),
        'is_vip', false, 'has_open_request', false
      )
    )
  );
  perform public.post_customer_archive_v1(
    'd3300000-0000-4000-8000-000000000019',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_archive',
      'customer_id', v_archived ->> 'customer_id',
      'expected_version', v_archived ->> 'record_version'
    )
  );
  v_links := (select count(*) from public.customers where shop_id = v_shop);
  perform pg_temp.trade('d3300000-0000-4000-8000-000000000020', 'sale', 'جديد', '01055556677');
  if (select count(*) from public.customers where shop_id = v_shop) <> v_links
    or exists (
      select 1 from public.customer_operation_links as link
      join public.financial_operations as operation on operation.id = link.operation_id
      join public.financial_operation_details as detail
        on detail.operation_id = operation.id
      where detail.payload ->> 'customer_phone' = '01055556677'
        and link.status = 'active'
    ) then
    raise exception 'archived_phone_created_or_linked';
  end if;

  v_latin := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000021', 'sale', 'Ahmed', '01198765432'
  );
  if not exists (
    select 1 from public.customers as customer
    join public.customer_phones as phone on phone.customer_id = customer.id
    where customer.shop_id = v_shop
      and customer.display_name = 'عميل 01198765432'
      and phone.normalized_number = '+201198765432'
      and phone.raw_number = '01198765432'
  ) or not exists (
    select 1 from public.customer_operation_links
    where operation_id = v_latin and status = 'active'
  ) then
    raise exception 'latin_name_not_rewritten';
  end if;

  -- Trade accepts 7–15 digits; Egypt normalize rejects 1234567. Sale must still commit.
  v_invalid := pg_temp.trade('d3300000-0000-4000-8000-000000000022', 'sale', '', '1234567');
  if v_invalid is null or exists (
    select 1 from public.customer_operation_links where operation_id = v_invalid
  ) then
    raise exception 'invalid_phone_changed_the_sale';
  end if;

  perform public.post_daily_ledger_trade(
    'd3300000-0000-4000-8000-000000000011',
    '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"500","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"محمد أحمد","customer_phone":"01012345678","note":""}'::jsonb
  );
  if (select count(*) from public.customer_operation_links
      where operation_id = v_sale and status = 'active') <> 1 then
    raise exception 'replay_linked_twice';
  end if;
end;
$capture$;

reset role;
create function public.customer_capture_block_test()
returns trigger
language plpgsql
as $fn$
begin
  raise exception 'customer_blocked';
end;
$fn$;
create trigger customer_capture_block_test
  before insert on public.customers
  for each row execute function public.customer_capture_block_test();

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000001', true);
do $isolated$
declare
  v_before integer;
  v_op uuid;
begin
  v_before := (select count(*) from public.customers
    where shop_id = 'd2200000-0000-4000-8000-000000000001');
  v_op := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000023', 'sale', 'محمود', '01033334444'
  );
  if v_op is null
    or (select count(*) from public.customers
        where shop_id = 'd2200000-0000-4000-8000-000000000001') <> v_before
    or exists (
      select 1 from public.customer_operation_links where operation_id = v_op
    )
    or exists (
      select 1 from public.customer_phones where raw_number = '01033334444'
    ) then
    raise exception 'capture_failure_blocked_the_sale';
  end if;
end;
$isolated$;

reset role;
drop trigger customer_capture_block_test on public.customers;
drop function public.customer_capture_block_test();

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000001', true);
do $edit$
declare
  v_shop uuid := 'd2200000-0000-4000-8000-000000000001';
  v_sale uuid;
  v_customer uuid;
  v_review jsonb;
  v_posted jsonb;
  v_replacement jsonb;
  v_detail jsonb;
  v_deleted uuid;
  v_replacement_id uuid;
begin
  -- Dedicated one-sale customer so edit statistics are not mixed with earlier captures.
  v_sale := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000028', 'sale', 'نورة', '01099998888'
  );
  select customer.id into v_customer
  from public.customers as customer
  join public.customer_phones as phone on phone.customer_id = customer.id
  where customer.shop_id = v_shop and phone.normalized_number = '+201099998888';
  v_replacement := '{"version":1,"kind":"sale","total_piastres":"1500","tenders":[{"method":"cash","piastres":"1500"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"500","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"نورة","customer_phone":"01099998888","note":"تعديل"}'::jsonb;
  v_review := public.review_ledger_trade_change_v1(v_sale, 'edit', v_replacement);
  v_posted := public.post_ledger_trade_change_v1(
    'd3300000-0000-4000-8000-000000000024', v_sale, 'edit', v_replacement,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  v_replacement_id := coalesce(
    (v_posted ->> 'replacement_operation_id')::uuid,
    (v_posted ->> 'operation_id')::uuid
  );
  if v_replacement_id is null then
    raise exception 'edit_failed %', v_posted;
  end if;
  if not exists (
    select 1 from public.customer_operation_links
    where customer_id = v_customer
      and operation_id = v_replacement_id
      and status = 'active'
  ) then
    raise exception 'replacement_not_linked %', v_posted;
  end if;
  v_detail := public.get_customer_v3(v_customer, 20, null, 20, null, 20, null);
  if v_detail #>> '{statistics,bought_count}' is distinct from '1' then
    raise exception 'edited_sale_counted_twice %', v_detail -> 'statistics';
  end if;

  v_deleted := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000025', 'sale', 'ليلى', ''
  );
  v_review := public.review_ledger_trade_change_v1(v_deleted, 'delete', null);
  perform public.post_ledger_trade_change_v1(
    'd3300000-0000-4000-8000-000000000026', v_deleted, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  select customer.id into v_customer
  from public.customers as customer
  where customer.shop_id = v_shop and customer.display_name = 'ليلى' and customer.status = 'active';
  v_detail := public.get_customer_v3(v_customer, 20, null, 20, null, 20, null);
  if v_detail #>> '{statistics,bought_count}' is distinct from '0'
    or exists (
      select 1 from jsonb_array_elements(v_detail #> '{links,items}') as item
      where item ->> 'operation_id' = v_deleted::text
    ) then
    raise exception 'deleted_sale_still_visible %', v_detail -> 'statistics';
  end if;
end;
$edit$;

select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000002', true);
do $employee$
declare
  v_op uuid;
  v_customer uuid;
begin
  -- v1 trade wrapper reads the shop before setting a staff grant; allow sale first.
  perform private.allow_member_permission('sale');
  v_op := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000027', 'sale', 'موظف', '01200001111'
  );
  select customer.id into v_customer
  from public.customers as customer
  join public.customer_phones as phone on phone.customer_id = customer.id
  where phone.normalized_number = '+201200001111';
  if v_customer is null or (
    select created_by from public.customers where id = v_customer
  ) is distinct from 'd1100000-0000-4000-8000-000000000002' then
    raise exception 'employee_sale_did_not_create_customer';
  end if;
  -- Clear the sale grant GUC so customer reads stay owner-only.
  perform set_config('app.required_shop_permission', '', true);
  begin
    perform public.get_customer_list_v3('', 'name', 'active', 20, null);
    raise exception 'employee_list_allowed';
  exception
    when others then
      if sqlerrm is distinct from 'forbidden' then
        raise exception 'employee_list_got_%', sqlerrm;
      end if;
  end;
end;
$employee$;

select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000003', true);
select set_config('app.required_shop_permission', '', true);
select public.confirm_opening_balances(
  'd3300000-0000-4000-8000-000000000002',
  '{"version":1,"cash":{"cash":"5000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"4"}],"scrap":[{"karat":21,"milligrams":"2000"}]}'::jsonb
);
do $other$
declare
  v_op uuid;
  v_links integer;
  v_shop2_customer uuid;
begin
  perform set_config('app.required_shop_permission', '', true);
  v_op := pg_temp.trade(
    'd3300000-0000-4000-8000-000000000029', 'sale', 'محمد أحمد', '01012345678'
  );
  select customer.id into v_shop2_customer
  from public.customers as customer
  join public.customer_phones as phone
    on phone.shop_id = customer.shop_id and phone.customer_id = customer.id
  where customer.shop_id = 'd2200000-0000-4000-8000-000000000002'
    and phone.normalized_number = '+201012345678';
  select count(*) into v_links
  from public.customer_operation_links
  where operation_id = v_op and status = 'active' and customer_id = v_shop2_customer;
  if v_shop2_customer is null or v_links <> 1 then
    raise exception 'other_shop_capture_failed';
  end if;
end;
$other$;

reset role;
do $other_isolation$
begin
  if (select count(*) from public.customer_phones
      where normalized_number = '+201012345678') <> 2
    or (select count(distinct shop_id) from public.customer_phones
        where normalized_number = '+201012345678') <> 2 then
    raise exception 'other_shop_shared_the_customer';
  end if;
end;
$other_isolation$;

rollback;

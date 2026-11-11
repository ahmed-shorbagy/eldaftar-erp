-- An auto-captured customer reads back with its phone (20261111091000).
-- Before the fix, customer reads dropped a phone with no declaration row, and
-- auto-capture started none, so the customer showed «بدون رقم هاتف».
-- One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('17171717-1717-4171-8171-171717171717', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'auto-phone-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1717171-7171-4171-8171-171717171717', 'متجر هاتف العميل', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1717171-7171-4171-8171-171717171717', '17171717-1717-4171-8171-171717171717', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1717171-7171-4171-8171-171717171717', now() - interval '1 day', now() + interval '30 days');

do $priv$
begin
  if has_function_privilege(
    'authenticated', 'private.customer_phone_start_declaration()', 'execute'
  ) then
    raise exception 'trigger_function_granted';
  end if;
  if exists (
    select 1 from public.customer_phones as phone
    where not exists (
      select 1 from public.customer_number_declarations as d
      where d.shop_id = phone.shop_id and d.customer_id = phone.customer_id
        and d.normalized_number = phone.normalized_number and d.retired_at is null
    )
  ) then
    raise exception 'phone_without_declaration_after_backfill';
  end if;
end;
$priv$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '17171717-1717-4171-8171-171717171717', true);

do $test$
declare
  v_result jsonb;
  v_list jsonb;
  v_customer uuid;
  v_detail jsonb;
  v_declarations integer;
begin
  v_result := public.confirm_opening_balances(
    'a1717171-7171-4171-8171-171717171717',
    '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"50000","count":"5"}],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'opening failed %', v_result;
  end if;

  v_result := public.post_daily_ledger_trade(
    'c1717171-7171-4171-8171-171717171701',
    '{"version":1,"kind":"sale","total_piastres":"1000000","tenders":[{"method":"cash","piastres":"1000000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"1","item_name":"خواتم","line_price_piastres":null}],"description":"","customer_name":"Test Buyer","customer_phone":"+201001234567","note":""}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'sale failed %', v_result;
  end if;

  v_list := public.get_customer_list_v3('', 'name', 'active', 20, null);
  if jsonb_array_length(v_list -> 'items') <> 1 then
    raise exception 'auto-capture did not create one customer %', v_list;
  end if;
  v_customer := (v_list -> 'items' -> 0 ->> 'customer_id')::uuid;
  if jsonb_array_length(v_list -> 'items' -> 0 -> 'phones') <> 1
    or v_list -> 'items' -> 0 -> 'phones' -> 0 ->> 'normalized' is distinct from '+201001234567'
    or v_list -> 'items' -> 0 -> 'phones' -> 0 -> 'saved_number' ->> 'state' is distinct from 'unknown' then
    raise exception 'list phones %', v_list -> 'items' -> 0 -> 'phones';
  end if;

  v_detail := public.get_customer_v3(v_customer, 20, null, 20, null, 20, null);
  if coalesce(jsonb_array_length(
    coalesce(v_detail -> 'customer' -> 'phones', v_detail -> 'phones')
  ), 0) <> 1 then
    raise exception 'detail phones %', v_detail;
  end if;

  -- A second sale with the same phone links the customer and starts no
  -- second declaration.
  perform public.post_daily_ledger_trade(
    'c1717171-7171-4171-8171-171717171702',
    '{"version":1,"kind":"sale","total_piastres":"1000000","tenders":[{"method":"cash","piastres":"1000000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"1","item_name":"خواتم","line_price_piastres":null}],"description":"","customer_name":"Test Buyer","customer_phone":"+201001234567","note":""}'::jsonb
  );
  select count(*) into v_declarations
  from public.customer_number_declarations
  where customer_id = v_customer and retired_at is null;
  if v_declarations <> 1 then
    raise exception 'declarations after second sale %', v_declarations;
  end if;
end;
$test$;

select 'CUSTOMER_AUTO_CAPTURE_PHONE_PASSED' as result;
rollback;

-- Standalone customer return. One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('19191919-1919-4191-8191-191919191919', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'return-owner@example.test', false, now(), now()),
  ('19191919-1919-4191-8191-19191919191a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'return-staff@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1919191-9191-4191-8191-191919191919', 'متجر المرتجعات', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1919191-9191-4191-8191-191919191919', '19191919-1919-4191-8191-191919191919', 'owner'),
  ('b1919191-9191-4191-8191-191919191919', '19191919-1919-4191-8191-19191919191a', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('b1919191-9191-4191-8191-191919191919', '19191919-1919-4191-8191-19191919191a', 'sale', '19191919-1919-4191-8191-191919191919');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1919191-9191-4191-8191-191919191919', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', '19191919-1919-4191-8191-191919191919', true);

do $test$
declare
  v_shop uuid := 'b1919191-9191-4191-8191-191919191919';
  v_day uuid;
  v_result jsonb;
  v_op uuid;
  v_staff uuid;
  v_page jsonb;
  v_item jsonb;
  v_report jsonb;
  v_ops integer;
  v_payload jsonb;
begin
  v_result := public.confirm_opening_balances(
    'a1919191-9191-4191-8191-191919191919',
    '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'opening failed %', v_result;
  end if;
  v_day := (public.get_daily_ledger_day_state() ->> 'business_day_id')::uuid;
  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'customer_return', 'total_piastres', '6000000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '6000000')),
    'items', jsonb_build_array(jsonb_build_object(
      'category', 'worked_jewelry', 'karat', 21, 'milligrams', '10000',
      'count', '1', 'item_name', 'خاتم', 'line_price_piastres', null
    )),
    'customer_name', '', 'customer_phone', '', 'note', ''
  );
  v_result := public.post_customer_return_v1('c1919191-9191-4191-8191-191919191919', v_payload);
  v_op := (v_result ->> 'operation_id')::uuid;
  if v_result ->> 'replayed' is distinct from 'false' or v_op is null then
    raise exception 'return did not post %', v_result;
  end if;
  if (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash')
      is distinct from 4000000
    or (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_metal'
        and category_code = 'worked_jewelry' and karat = 21) is distinct from 10000
    or (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_count'
        and category_code = 'worked_jewelry' and karat = 21) is distinct from 1 then
    raise exception 'return did not move cash and stock';
  end if;
  execute 'reset role';
  if (select count(*) from public.inventory_lots
      where shop_id = v_shop and display_name = 'خاتم'
        and category_code = 'worked_jewelry' and karat = 21) <> 1 then
    raise exception 'the returned ring did not become a named lot';
  end if;
  execute 'set local role authenticated';

  v_result := public.post_customer_return_v1(
    'c1919191-9191-4191-8191-19191919191b',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_return', 'total_piastres', '1000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1000')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'coin', 'karat', 21, 'milligrams', '8000',
        'count', '1', 'item_name', 'جنيه', 'line_price_piastres', null
      )),
      'customer_name', '', 'customer_phone', '', 'note', ''
    )
  );
  if (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_metal'
        and category_code = 'coin' and karat = 21) is distinct from 8000 then
    raise exception 'a returned coin did not enter coin stock';
  end if;
  perform public.post_customer_return_v1(
    'c1919191-9191-4191-8191-19191919191c',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_return', 'total_piastres', '2000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '2000')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'bullion', 'karat', 24, 'milligrams', '10000',
        'count', '1', 'item_name', 'سبيكة', 'line_price_piastres', null
      )),
      'customer_name', '', 'customer_phone', '', 'note', ''
    )
  );
  if (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_metal'
        and category_code = 'bullion' and karat = 24) is distinct from 10000 then
    raise exception 'a returned bar did not enter bullion stock';
  end if;

  v_page := public.get_ledger_date_v1(
    (public.get_daily_ledger_day_state() ->> 'business_date')::date, null, 20
  );
  select item into v_item
  from jsonb_array_elements(v_page #> '{feed_page,items}') as item
  where item ->> 'operation_id' = v_op::text;
  if v_item ->> 'is_return' is distinct from 'true'
    or v_item ->> 'label_ar' is distinct from 'مرتجع'
    or v_item ->> 'kind' is distinct from 'customer_return' then
    raise exception 'the feed did not mark the return %', v_item;
  end if;
  if public.get_daily_ledger_home_v1() #>> '{journal_context,return_count}'
      is distinct from '3' then
    raise exception 'return_count ignored the standalone returns';
  end if;
  v_report := public.get_financial_day_report_v1(v_day);
  if (v_report #>> '{summary,net_sales}')::numeric <> -6003000
    or (v_report #>> '{summary,return_count}')::numeric <> 3 then
    raise exception 'the day report did not reduce net sales %', v_report -> 'summary';
  end if;
  -- Private helpers are closed to clients; read the label as the database owner.
  execute 'reset role';
  if private.audit_trail_action_label('customer_return_confirmed')
      is distinct from 'تسجيل مرتجع' then
    raise exception 'the audit label is wrong';
  end if;
  execute 'set local role authenticated';

  v_result := public.post_customer_return_v1('c1919191-9191-4191-8191-191919191919', v_payload);
  if v_result ->> 'replayed' is distinct from 'true'
    or (v_result ->> 'operation_id')::uuid is distinct from v_op then
    raise exception 'replay failed %', v_result;
  end if;
  v_ops := (select count(*) from public.financial_operations
    where shop_id = v_shop and kind = 'customer_return');
  begin
    perform public.post_customer_return_v1(
      'c1919191-9191-4191-8191-19191919191d',
      jsonb_set(v_payload, '{items,0,category}', '"scrap"')
    );
    raise exception 'scrap_succeeded';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then
      raise exception 'expected invalid_input for scrap got %', sqlerrm;
    end if;
  end;
  begin
    perform public.post_customer_return_v1(
      'c1919191-9191-4191-8191-19191919191e',
      jsonb_set(v_payload, '{tenders,0,piastres}', '"1"')
    );
    raise exception 'mismatch_succeeded';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then
      raise exception 'expected invalid_input for a tender mismatch got %', sqlerrm;
    end if;
  end;
  begin
    perform public.post_customer_return_v1(
      'c1919191-9191-4191-8191-19191919191f',
      jsonb_build_object(
        'version', 1, 'kind', 'customer_return', 'total_piastres', '9000000',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '9000000')),
        'items', jsonb_build_array(jsonb_build_object(
          'category', 'worked_jewelry', 'karat', 21, 'milligrams', '1000',
          'count', '1', 'item_name', 'خاتم', 'line_price_piastres', null
        )),
        'customer_name', '', 'customer_phone', '', 'note', ''
      )
    );
    -- The owned-balance trigger is deferred to commit, as for sales. Force it.
    execute 'set constraints all immediate';
    raise exception 'overdraft_succeeded';
  exception when others then
    if sqlerrm is distinct from 'negative_owned_balance' then
      raise exception 'expected negative_owned_balance got %', sqlerrm;
    end if;
  end;
  execute 'set constraints all deferred';
  if (select count(*) from public.financial_operations
      where shop_id = v_shop and kind = 'customer_return') <> v_ops then
    raise exception 'a rejected return left a row';
  end if;

  perform set_config('request.jwt.claim.sub', '19191919-1919-4191-8191-19191919191a', true);
  v_result := public.post_customer_return_v1(
    'c1919191-9191-4191-8191-191919191920',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_return', 'total_piastres', '100',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '100')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'coin', 'karat', 21, 'milligrams', '1000',
        'count', '1', 'item_name', 'جنيه الموظف', 'line_price_piastres', null
      )),
      'customer_name', '', 'customer_phone', '', 'note', ''
    )
  );
  v_staff := (v_result ->> 'operation_id')::uuid;
  v_page := public.get_daily_ledger_home_v1();
  if exists (
    select 1 from jsonb_array_elements(v_page -> 'feed') as item
    where item ->> 'operation_id' = v_op::text
  ) or not exists (
    select 1 from jsonb_array_elements(v_page -> 'feed') as item
    where item ->> 'operation_id' = v_staff::text
  ) then
    raise exception 'the employee feed is not limited to their own return';
  end if;

  execute 'reset role';
  delete from public.shop_member_grants
  where user_id = '19191919-1919-4191-8191-19191919191a';
  execute 'set local role authenticated';
  begin
    perform public.post_customer_return_v1(
      'c1919191-9191-4191-8191-191919191921', v_payload
    );
    raise exception 'grantless_succeeded';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then
      raise exception 'expected forbidden without the sale grant got %', sqlerrm;
    end if;
  end;

  perform set_config('request.jwt.claim.sub', '19191919-1919-4191-8191-191919191919', true);
  execute 'reset role';
  update public.business_days
    set status = 'closed', closed_at = clock_timestamp()
    where id = v_day;
  execute 'set local role authenticated';
  begin
    perform public.post_customer_return_v1(
      'c1919191-9191-4191-8191-191919191922', v_payload
    );
    raise exception 'closed_succeeded';
  exception when others then
    if sqlerrm is distinct from 'day_closed' then
      raise exception 'expected day_closed got %', sqlerrm;
    end if;
  end;
end;
$test$;

select 'CUSTOMER_RETURN_PASSED' as result;
rollback;

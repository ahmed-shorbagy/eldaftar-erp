-- Expense and customer_return edit/delete. One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('15151515-1515-4151-8151-151515151515', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'exp-ret-owner@example.test', false, now(), now()),
  ('15151515-1515-4151-8151-15151515151a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'exp-ret-staff@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1515151-5151-4151-8151-151515151515', 'متجر المصروف والمرتجع', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1515151-5151-4151-8151-151515151515', '15151515-1515-4151-8151-151515151515', 'owner'),
  ('b1515151-5151-4151-8151-151515151515', '15151515-1515-4151-8151-15151515151a', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('b1515151-5151-4151-8151-151515151515', '15151515-1515-4151-8151-15151515151a', 'sale', '15151515-1515-4151-8151-151515151515');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1515151-5151-4151-8151-151515151515', now() - interval '1 day', now() + interval '30 days');

do $priv$
begin
  if not has_function_privilege(
    'authenticated',
    'public.review_ledger_trade_change_v1(uuid,text,jsonb)',
    'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.post_ledger_trade_change_v1(uuid,uuid,text,jsonb,uuid,bigint,text,text)',
    'execute'
  ) then
    raise exception 'trade_change_execute_missing';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.review_ledger_trade_change_v1_before_expense_return_change(uuid,text,jsonb)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.post_ledger_trade_change_v1_before_expense_return_change(uuid,uuid,text,jsonb,uuid,bigint,text,text)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'private.post_mirror_reversal(uuid,uuid,uuid,text,uuid,uuid,timestamptz)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.review_ledger_trade_change_v1_before_owner_check(uuid,text,jsonb)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.post_ledger_trade_change_v1_before_owner_check(uuid,uuid,text,jsonb,uuid,bigint,text,text)',
    'execute'
  ) then
    raise exception 'before_or_private_still_granted';
  end if;
end;
$priv$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '15151515-1515-4151-8151-151515151515', true);

do $test$
declare
  v_shop uuid := 'b1515151-5151-4151-8151-151515151515';
  v_day uuid;
  v_version bigint;
  v_result jsonb;
  v_review jsonb;
  v_posted jsonb;
  v_expense uuid;
  v_expense2 uuid;
  v_return uuid;
  v_return_sold uuid;
  v_sale uuid;
  v_key uuid;
  v_cash bigint;
  v_page jsonb;
  v_payload jsonb;
  v_replacement jsonb;
  v_error text;
  v_expense_count integer;
  v_return_count integer;
begin
  v_result := public.confirm_opening_balances(
    'a1515151-5151-4151-8151-151515151515',
    '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"50000","count":"5"}],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'opening failed %', v_result;
  end if;
  v_day := (public.get_daily_ledger_day_state() ->> 'business_day_id')::uuid;

  -- Post an expense of 500,000 piastres (EGP 5,000).
  v_result := public.post_daily_ledger_trade(
    'c1515151-5151-4151-8151-151515151501',
    '{"version":1,"kind":"expense","total_piastres":"500000","tenders":[{"method":"cash","piastres":"500000"}],"items":[],"description":"إيجار","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  v_expense := (v_result ->> 'operation_id')::uuid;
  v_cash := (
    select amount from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash'
  );
  if v_cash is distinct from 9500000 then
    raise exception 'expense did not reduce cash %', v_cash;
  end if;

  -- Delete the expense: cash restored, feed hides it, expense_count drops.
  v_review := public.review_ledger_trade_change_v1(v_expense, 'delete', null);
  if (v_review -> 'effects' -> 'cash' -> 0 ->> 'delta_piastres') is distinct from '500000' then
    raise exception 'expense delete effect %', v_review -> 'effects';
  end if;
  v_key := 'c1515151-5151-4151-8151-151515151510';
  v_posted := public.post_ledger_trade_change_v1(
    v_key, v_expense, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token'
  );
  if v_posted ->> 'replayed' is distinct from 'false' then
    raise exception 'expense delete not fresh %', v_posted;
  end if;
  v_cash := (
    select amount from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash'
  );
  if v_cash is distinct from 10000000 then
    raise exception 'expense delete did not restore cash %', v_cash;
  end if;
  v_page := public.get_daily_ledger_home_v1();
  if exists (
    select 1 from jsonb_array_elements(v_page -> 'feed') as item
    where item ->> 'operation_id' = v_expense::text
  ) then
    raise exception 'deleted expense still in feed';
  end if;
  v_expense_count := coalesce((v_page -> 'journal_context' ->> 'expense_count')::integer, 0);
  if v_expense_count <> 0 then
    raise exception 'expense_count after delete %', v_expense_count;
  end if;
  if (public.post_ledger_trade_change_v1(
    v_key, v_expense, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token'
  ) ->> 'replayed') is distinct from 'true' then
    raise exception 'expense delete replay failed';
  end if;

  -- Edit expense 500k → 700k: net cash −200k, one active row.
  v_result := public.post_daily_ledger_trade(
    'c1515151-5151-4151-8151-151515151502',
    '{"version":1,"kind":"expense","total_piastres":"500000","tenders":[{"method":"cash","piastres":"500000"}],"items":[],"description":"كهرباء","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  v_expense2 := (v_result ->> 'operation_id')::uuid;
  v_replacement := '{"version":1,"kind":"expense","total_piastres":"700000","tenders":[{"method":"cash","piastres":"700000"}],"items":[],"description":"كهرباء معدّل","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_review := public.review_ledger_trade_change_v1(v_expense2, 'edit', v_replacement);
  if (v_review -> 'effects' -> 'cash' -> 0 ->> 'delta_piastres') is distinct from '-200000' then
    raise exception 'expense edit effect %', v_review -> 'effects';
  end if;
  v_posted := public.post_ledger_trade_change_v1(
    'c1515151-5151-4151-8151-151515151511', v_expense2, 'edit', v_replacement,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token'
  );
  v_cash := (
    select amount from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash'
  );
  -- After first delete restored 10M, second expense −500k → 9.5M, edit −200k → 9.3M.
  if v_cash is distinct from 9300000 then
    raise exception 'expense edit cash %', v_cash;
  end if;
  v_page := public.get_daily_ledger_home_v1();
  if exists (
    select 1 from jsonb_array_elements(v_page -> 'feed') as item
    where item ->> 'operation_id' = v_expense2::text
  ) or not exists (
    select 1 from jsonb_array_elements(v_page -> 'feed') as item
    where item ->> 'operation_id' = (v_posted ->> 'replacement_operation_id')
  ) then
    raise exception 'expense edit feed did not swap rows';
  end if;
  -- Reports count only the live expense: the deleted one and the replaced
  -- source are excluded, the 700,000 replacement is kept.
  v_page := public.get_financial_day_report_v1(v_day);
  if (v_page #>> '{summary,expenses}')::numeric is distinct from 700000
    or (v_page #>> '{summary,expense_count}')::numeric is distinct from 1 then
    raise exception 'day report kept deleted or replaced expenses %', v_page -> 'summary';
  end if;

  -- Standalone return, then delete: cash and stock reverse.
  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'customer_return', 'total_piastres', '1000000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1000000')),
    'items', jsonb_build_array(jsonb_build_object(
      'category', 'worked_jewelry', 'karat', 21, 'milligrams', '10000',
      'count', '1', 'item_name', 'خاتم', 'line_price_piastres', null
    )),
    'customer_name', '', 'customer_phone', '', 'note', ''
  );
  v_result := public.post_customer_return_v1(
    'c1515151-5151-4151-8151-151515151503', v_payload
  );
  v_return := (v_result ->> 'operation_id')::uuid;
  v_review := public.review_ledger_trade_change_v1(v_return, 'delete', null);
  if (v_review -> 'effects' -> 'cash' -> 0 ->> 'delta_piastres') is distinct from '1000000'
    or (v_review -> 'effects' -> 'stock' -> 0 ->> 'delta_milligrams') is distinct from '-10000' then
    raise exception 'return delete effects %', v_review -> 'effects';
  end if;
  perform public.post_ledger_trade_change_v1(
    'c1515151-5151-4151-8151-151515151512', v_return, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token'
  );
  if (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'saleable_metal'
        and category_code = 'worked_jewelry' and karat = 21)
      is distinct from 50000
    or (select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash')
      is distinct from 9300000 then
    raise exception 'return delete did not reverse cash and stock';
  end if;
  v_page := public.get_daily_ledger_home_v1();
  v_return_count := coalesce((v_page -> 'journal_context' ->> 'return_count')::integer, 0);
  if v_return_count <> 0 then
    raise exception 'return_count after delete %', v_return_count;
  end if;

  -- Return whose ring is later sold cannot be deleted.
  v_result := public.post_customer_return_v1(
    'c1515151-5151-4151-8151-151515151504',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_return', 'total_piastres', '500000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '500000')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'worked_jewelry', 'karat', 21, 'milligrams', '8000',
        'count', '1', 'item_name', 'خاتم مباع', 'line_price_piastres', null
      )),
      'customer_name', '', 'customer_phone', '', 'note', ''
    )
  );
  v_return_sold := (v_result ->> 'operation_id')::uuid;
  -- Sell all 21k jewelry so the returned lot is consumed (FIFO would
  -- otherwise leave the return lot untouched and skip the follow-up check).
  v_result := public.post_daily_ledger_trade(
    'c1515151-5151-4151-8151-151515151505',
    jsonb_build_object(
      'version', 1, 'kind', 'sale', 'total_piastres', '600000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '600000')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'worked_jewelry', 'karat', 21, 'milligrams', '58000',
        'count', '6', 'item_name', 'مشغولات', 'line_price_piastres', null
      )),
      'description', '', 'customer_name', '', 'customer_phone', '', 'note', ''
    )
  );
  v_sale := (v_result ->> 'operation_id')::uuid;
  if v_sale is null then raise exception 'sale after return failed'; end if;
  execute 'reset role';
  if not exists (
    select 1
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
      and lot.origin_operation_id = v_return_sold
      and movement.operation_id = v_sale
      and (movement.delta_milligrams < 0 or movement.delta_count < 0)
  ) then
    raise exception 'sale did not consume the returned lot';
  end if;
  execute 'set local role authenticated';
  begin
    perform public.review_ledger_trade_change_v1(v_return_sold, 'delete', null);
    raise exception 'sold_return_review_succeeded';
  exception when others then
    if sqlerrm is distinct from 'trade_has_followups' then
      raise exception 'expected trade_has_followups got %', sqlerrm;
    end if;
  end;

  -- Affordability: editing expense larger than cash is refused.
  v_result := public.post_daily_ledger_trade(
    'c1515151-5151-4151-8151-151515151506',
    '{"version":1,"kind":"expense","total_piastres":"100000","tenders":[{"method":"cash","piastres":"100000"}],"items":[],"description":"صغير","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  v_expense := (v_result ->> 'operation_id')::uuid;
  v_replacement := jsonb_build_object(
    'version', 1, 'kind', 'expense', 'total_piastres', '999999999',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '999999999')),
    'items', '[]'::jsonb, 'description', 'ضخم',
    'customer_name', '', 'customer_phone', '', 'note', ''
  );
  begin
    perform public.review_ledger_trade_change_v1(v_expense, 'edit', v_replacement);
    raise exception 'unaffordable_edit_succeeded';
  exception when others then
    if sqlerrm is distinct from 'negative_owned_balance' then
      raise exception 'expected negative_owned_balance got %', sqlerrm;
    end if;
  end;

  -- Stale review token.
  v_review := public.review_ledger_trade_change_v1(v_expense, 'delete', null);
  begin
    perform public.post_ledger_trade_change_v1(
      'c1515151-5151-4151-8151-151515151513', v_expense, 'delete', null,
      (v_review ->> 'expected_day_id')::uuid,
      (v_review ->> 'expected_day_version')::bigint,
      v_review ->> 'source_sha256',
      repeat('a', 64)
    );
    raise exception 'stale_succeeded';
  exception when others then
    if sqlerrm is distinct from 'stale_trade_review' then
      raise exception 'expected stale_trade_review got %', sqlerrm;
    end if;
  end;

  -- Staff without expense grant cannot change an expense.
  perform set_config('request.jwt.claim.sub', '15151515-1515-4151-8151-15151515151a', true);
  begin
    perform public.review_ledger_trade_change_v1(v_expense, 'delete', null);
    raise exception 'staff_expense_succeeded';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then
      raise exception 'expected forbidden for staff expense got %', sqlerrm;
    end if;
  end;

  -- Trade edit/delete is owner-only for every kind, like sale and purchase.
  -- Staff holding the sale grant still cannot review a return change.
  -- Use a fresh return that was not sold.
  perform set_config('request.jwt.claim.sub', '15151515-1515-4151-8151-151515151515', true);
  v_result := public.post_customer_return_v1(
    'c1515151-5151-4151-8151-151515151507',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_return', 'total_piastres', '100000',
      'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '100000')),
      'items', jsonb_build_array(jsonb_build_object(
        'category', 'coin', 'karat', 21, 'milligrams', '1000',
        'count', '1', 'item_name', 'جنيه', 'line_price_piastres', null
      )),
      'customer_name', '', 'customer_phone', '', 'note', ''
    )
  );
  v_return := (v_result ->> 'operation_id')::uuid;
  perform set_config('request.jwt.claim.sub', '15151515-1515-4151-8151-15151515151a', true);
  begin
    perform public.review_ledger_trade_change_v1(v_return, 'delete', null);
    raise exception 'staff_return_review_succeeded';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then
      raise exception 'expected forbidden for staff return change got %', sqlerrm;
    end if;
  end;
  begin
    perform public.post_ledger_trade_change_v1(
      'c1515151-5151-4151-8151-151515151599', v_return, 'delete', null,
      gen_random_uuid(), 1, repeat('a', 64), repeat('a', 64)
    );
    raise exception 'staff_return_change_succeeded';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then
      raise exception 'expected forbidden for staff return post got %', sqlerrm;
    end if;
  end;
  -- The owner can still review the same return delete.
  perform set_config('request.jwt.claim.sub', '15151515-1515-4151-8151-151515151515', true);
  v_review := public.review_ledger_trade_change_v1(v_return, 'delete', null);
  if v_review ->> 'action' is distinct from 'delete' then
    raise exception 'owner could not review the return delete';
  end if;

  -- Closed-day expense is not editable.
  perform set_config('request.jwt.claim.sub', '15151515-1515-4151-8151-151515151515', true);
  execute 'reset role';
  update public.business_days
    set status = 'closed', closed_at = clock_timestamp()
    where id = v_day;
  execute 'set local role authenticated';
  begin
    perform public.review_ledger_trade_change_v1(v_expense, 'delete', null);
    raise exception 'closed_day_succeeded';
  exception when others then
    if sqlerrm not in ('trade_not_editable', 'day_closed') then
      raise exception 'expected closed-day refusal got %', sqlerrm;
    end if;
  end;
end;
$test$;

select 'EXPENSE_RETURN_CHANGE_PASSED' as result;
rollback;

-- Compensating ledger. One connection, one transaction, ROLLBACK.
-- Lot sync runs immediately. Deferred journal checks are forced immediate.
begin;
set local time zone 'UTC';
do $collision$
begin
  if exists(select 1 from auth.users where id in ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1','a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2','a5a5a5a5-a5a5-45a5-85a5-a5a5a5a5a5a5'))
    or exists(select 1 from public.shops where id in ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1','b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2')) then
    raise exception 'synthetic_fixture_collision';
  end if;
end;
$collision$;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'comp-a@example.test', false, now(), now()),
  ('a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'comp-b@example.test', false, now(), now()),
  ('a5a5a5a5-a5a5-45a5-85a5-a5a5a5a5a5a5', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'comp-admin@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1', 'تعويض أ', 'المالك أ', 'Africa/Cairo'),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', 'تعويض ب', 'المالك ب', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', 'owner'),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1', now() - interval '1 day', now() + interval '30 days'),
  ('b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2', now() - interval '1 day', now() + interval '30 days');
insert into public.platform_admins (user_id) values ('a5a5a5a5-a5a5-45a5-85a5-a5a5a5a5a5a5');
insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('d1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', now(), now(), now() - interval '1 minute');

create function pg_temp.expect_comp(p_sql text, p_code text)
returns void language plpgsql as $fn$
begin
  begin
    execute p_sql;
    raise exception using message = 'call_succeeded';
  exception when others then
    if sqlerrm = 'call_succeeded' then
      raise exception 'expected_%', p_code;
    elsif sqlerrm is distinct from p_code then
      raise exception 'expected_%_got_%', p_code, sqlerrm;
    end if;
  end;
end;
$fn$;
grant execute on function pg_temp.expect_comp(text, text) to authenticated;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', true);
select set_config('request.jwt.claim.session_id', '', true);

select public.confirm_opening_balances(
  'c1000000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"500000","card":"1000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"10000","count":"4"}],"scrap":[]}'::jsonb
);


do $edges$
declare v_day uuid; v_version bigint; v_counts jsonb; v_initial jsonb; v_payload jsonb; v_sale uuid;
  v_result jsonb; v_purchase uuid; v_return jsonb; v_replacement jsonb; v_exchange jsonb;
  v_ops bigint; v_audits bigint; v_requests bigint; v_postings bigint; v_payable bigint; v_original_lot uuid; v_state jsonb;
begin
  v_result := public.get_daily_ledger_day_state(); v_day := (v_result ->> 'business_day_id')::uuid;
  v_version := (v_result ->> 'day_version')::bigint; v_initial := v_result -> 'counts';
  v_counts := jsonb_set(v_initial,'{stock,0,milligrams}','"9999"');
  v_counts := jsonb_set(v_counts,'{stock,0,count}','"5"');
  v_payload := jsonb_build_object('version',1,'kind','ledger_correction','expected_day_id',v_day,
    'expected_day_version',v_version::text,'reason','فرق الوزن والعدد','counted',v_counts);
  perform pg_temp.expect_comp(format('select public.post_ledger_correction_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000001',jsonb_set(v_payload,'{reason}','"english only"')),'invalid_input');
  perform public.post_ledger_correction_v1('c2000000-0000-4000-8000-000000000001',v_payload);
  if (public.get_daily_ledger_day_state() -> 'counts') is distinct from v_counts then raise exception 'mixed correction failed'; end if;
  perform pg_temp.expect_comp(format('select public.close_daily_ledger_day(%L::uuid,%L::uuid,%s,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000002',v_day,v_version,v_initial),'stale_day');
  v_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  if public.close_daily_ledger_day('c2000000-0000-4000-8000-000000000002',v_day,v_version,v_initial) ->> 'reason' is distinct from 'count_mismatch' then raise exception 'correction bypassed physical count'; end if;
  perform pg_temp.expect_comp(format('select public.post_ledger_correction_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000003',jsonb_set(jsonb_set(v_payload,'{expected_day_version}',to_jsonb(v_version::text)),
      '{counted,cash,cash}','"-1"')),'negative_amount');
  -- Real three-decimal return and a later zero-consideration full goods remainder.
  v_result := public.post_daily_ledger_trade('c2000000-0000-4000-8000-000000000004',
    '{"version":1,"kind":"sale","total_piastres":"3000","tenders":[{"method":"cash","piastres":"3000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"4001","count":"2","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}');
  v_sale := (v_result ->> 'operation_id')::uuid;
  v_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  v_return := jsonb_build_object('version',1,'kind','sale_return','expected_day_id',v_day,'expected_day_version',v_version::text,
    'original_operation_id',v_sale,'note','مرتجع مقاس','items',jsonb_build_array(jsonb_build_object('item_index','0','milligrams','1999','count','1')),
    'consideration_piastres','3000','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','3000')));
  perform pg_temp.expect_comp(format('select public.post_linked_return_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000005',jsonb_set(v_return,'{items,0,count}','"2"')),'stock_pair_mismatch');
  perform public.post_linked_return_v1('c2000000-0000-4000-8000-000000000005',v_return);
  if public.get_daily_ledger_operation(v_sale) ->> 'returned_by_operation_id' is not null then raise exception 'partial hidden as full'; end if;
  v_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  v_return := jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_return,'{expected_day_version}',to_jsonb(v_version::text)),
    '{items,0,milligrams}','"2002"'),'{consideration_piastres}','"0"'),'{tenders}','[]');
  perform public.post_linked_return_v1('c2000000-0000-4000-8000-000000000006',v_return);
  if public.get_return_remainder_v1(v_sale) ->> 'fully_returned' is distinct from 'true' then raise exception 'zero consideration remainder failed'; end if;
  -- Purchase exchange: return would cancel a payable, but failing replacement must
  -- roll back payable, original bounds, keys, operations, audit and all postings.
  v_result := public.post_daily_ledger_trade('c2000000-0000-4000-8000-000000000007',
    '{"version":1,"kind":"purchase","total_piastres":"10000","purchase_obligation_piastres":"8000","tenders":[{"method":"cash","piastres":"2000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"4000","count":"2","item_name":"سوار","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}');
  v_purchase := (v_result ->> 'operation_id')::uuid;
  v_return := jsonb_build_object('kind','purchase_return','original_operation_id',v_purchase,'note','استبدال',
    'items',jsonb_build_array(jsonb_build_object('item_index','0','milligrams','2000','count','1')),
    'consideration_piastres','5000','tenders','[]'::jsonb);
  v_replacement := '{"version":1,"kind":"purchase","total_piastres":"999999999","tenders":[{"method":"cash","piastres":"999999999"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"3000","count":"1","item_name":"بديل","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}';
  v_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  v_exchange := jsonb_build_object('version',1,'kind','exchange','expected_day_id',v_day,'expected_day_version',v_version::text,
    'note','استبدال','return',v_return,'replacement',v_replacement);
  select count(*) into v_ops from public.financial_operations;select count(*) into v_audits from public.financial_audit_events;
  select count(*) into v_postings from public.journal_postings;select count(*) into v_requests from public.financial_command_requests;
  perform pg_temp.expect_comp(format('select public.post_exchange_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000008',v_exchange),'negative_owned_balance');
  if (select remaining_piastres from public.purchase_cash_payables where operation_id=v_purchase) <> 8000
    or (select count(*) from public.financial_operations) <> v_ops or (select count(*) from public.financial_audit_events) <> v_audits
    or (select count(*) from public.journal_postings) <> v_postings or (select count(*) from public.financial_command_requests) <> v_requests
    or (public.get_return_remainder_v1(v_purchase) ->> 'returned_consideration_piastres') <> '0'
    or (public.get_daily_ledger_day_state() ->> 'day_version')::bigint <> v_version then raise exception 'failed exchange leaked effects'; end if;
  -- First-side over-return fails before any replacement is recorded.
  perform pg_temp.expect_comp(format('select public.post_exchange_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000008',jsonb_set(v_exchange,'{return,items,0,milligrams}','"4001"')),'return_exceeds_original');
  -- Valid replacement purchase can remain unpaid; its payable is independent.
  v_replacement := jsonb_set(jsonb_set(v_replacement,'{total_piastres}','"3000"'),'{tenders}','[]') || jsonb_build_object('purchase_obligation_piastres','3000');
  v_exchange := jsonb_set(v_exchange,'{replacement}',v_replacement);
  v_result := public.post_exchange_v1('c2000000-0000-4000-8000-000000000008',v_exchange);
  if v_result -> 'net_effects' ->> 'cash_piastres' <> '0'
    or (select remaining_piastres from public.purchase_cash_payables where operation_id=v_purchase) <> 3000
    or (select remaining_piastres from public.purchase_cash_payables where operation_id=(v_result ->> 'replacement_operation_id')::uuid) <> 3000 then raise exception 'purchase exchange payable failed'; end if;
  perform pg_temp.expect_comp(format('select public.post_exchange_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000008',jsonb_set(v_exchange,'{note}','"تغيير"')),'payload_mismatch');
  if public.post_exchange_v1('c2000000-0000-4000-8000-000000000008',v_exchange) ->> 'replayed' <> 'true' then raise exception 'exchange replay failed'; end if;
  select lot.id into v_original_lot from public.inventory_lots lot
    where lot.origin_operation_id=v_purchase and lot.display_name='سوار' limit 1;
  v_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  perform public.post_daily_ledger_trade_v2('c2000000-0000-4000-8000-000000000009',jsonb_build_object(
    'version',2,'kind','sale','expected_day_id',v_day,'expected_day_version',v_version::text,
    'total_piastres','1000','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','1000')),
    'items',jsonb_build_array(jsonb_build_object('category','worked_jewelry','karat',18,'milligrams','2000','count','1','item_name','سوار','line_price_piastres',null)),
    'description','','customer_name','','customer_phone','','note','',
    'lot_selections',jsonb_build_array(jsonb_build_object('lot_id',v_original_lot,'milligrams','2000','count','1'))));
  v_version := (public.get_daily_ledger_day_state() ->> 'day_version')::bigint;
  v_return := v_return || jsonb_build_object('version',1,'expected_day_id',v_day,'expected_day_version',v_version::text,
    'consideration_piastres','5000','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','2000')));
  perform pg_temp.expect_comp(format('select public.post_linked_return_v1(%L::uuid,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000010',v_return),'negative_owned_balance');
  if (select remaining_piastres from public.purchase_cash_payables where operation_id=v_purchase) <> 3000 then raise exception 'unavailable original lot changed payable'; end if;
  -- An explicitly chosen refund method may differ from original tenders.
  v_result := public.post_daily_ledger_trade('c2000000-0000-4000-8000-000000000020',
    '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"card","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"500","count":"1","item_name":"خاتم بطاقة","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}');
  v_sale := (v_result ->> 'operation_id')::uuid;
  v_state := public.get_daily_ledger_day_state();
  v_return := jsonb_build_object('version',1,'kind','sale_return','expected_day_id',v_day,'expected_day_version',v_state ->> 'day_version',
    'original_operation_id',v_sale,'note','رد نقدي متفق عليه','items',jsonb_build_array(jsonb_build_object('item_index','0','milligrams','500','count','1')),
    'consideration_piastres','1000','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','1000')));
  v_result := public.post_linked_return_v1('c2000000-0000-4000-8000-000000000021',v_return);
  if v_result ->> 'cash_refund_piastres' <> '1000' or public.get_return_remainder_v1(v_sale) ->> 'fully_returned' <> 'true' then raise exception 'explicit cross-method refund failed'; end if;
  -- Force deferred immutability, balance, and lot assertions before rollback.
  set constraints all immediate;
end;
$edges$;
select jsonb_build_object('ledger',public.get_daily_ledger_v2(),'page',public.get_ledger_operation_page(null,null,null,100),
  'operations',(select jsonb_agg(public.get_daily_ledger_operation(id) order by shop_sequence) from public.financial_operations)) as synthetic_contract;
set constraints all deferred;
do $day_edges$
declare v_day uuid; v_old_day uuid; v_version bigint; v_sale uuid; v_state jsonb; v_payload jsonb; v_result jsonb; v_original jsonb;
begin
  v_result := public.post_daily_ledger_trade('c2000000-0000-4000-8000-000000000011',
    '{"version":1,"kind":"sale","total_piastres":"100","tenders":[{"method":"cash","piastres":"100"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"500","count":"1","item_name":"خاتم يوم سابق","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}');
  v_sale := (v_result ->> 'operation_id')::uuid; v_old_day := (v_result ->> 'business_day_id')::uuid;
  v_original := public.get_daily_ledger_operation(v_sale) -> 'payload';
  v_state := public.get_daily_ledger_day_state();
  perform public.close_daily_ledger_day('c2000000-0000-4000-8000-000000000012',v_old_day,(v_state ->> 'day_version')::bigint,v_state -> 'counts');
  perform public.open_daily_ledger_day('c2000000-0000-4000-8000-000000000013');
  v_state := public.get_daily_ledger_day_state(); v_day := (v_state ->> 'business_day_id')::uuid;
  if v_day = v_old_day then raise exception 'old day reopened'; end if;
  v_version := (v_state ->> 'day_version')::bigint;
  v_payload := jsonb_build_object('version',1,'kind','sale_return','expected_day_id',v_day,'expected_day_version',v_version::text,
    'original_operation_id',v_sale,'note','مرتجع يوم سابق','items',jsonb_build_array(jsonb_build_object('item_index','0','milligrams','500','count','1')),
    'consideration_piastres','100','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','100')));
  v_result := public.post_linked_return_v1('c2000000-0000-4000-8000-000000000014',v_payload);
  if v_result ->> 'business_day_id' <> v_day::text or public.get_daily_ledger_operation(v_sale) -> 'payload' is distinct from v_original then
    raise exception 'historical return edited original day'; end if;
  -- Session time-zone changes cannot substitute a device clock or another day.
  perform set_config('TimeZone','Pacific/Honolulu',true);
  v_state := public.get_daily_ledger_day_state();
  v_payload := jsonb_build_object('version',1,'kind','ledger_correction','expected_day_id',v_day,
    'expected_day_version',v_state ->> 'day_version','reason','فرق نقد في اليوم الحالي',
    'counted',jsonb_set(v_state -> 'counts','{cash,cash}',to_jsonb(((v_state -> 'counts' -> 'cash' ->> 'cash')::bigint-1)::text)));
  v_result := public.post_ledger_correction_v1('c2000000-0000-4000-8000-000000000015',v_payload);
  if v_result ->> 'business_day_id' <> v_day::text or (select status from public.business_days where id=v_old_day) <> 'closed' then raise exception 'correction used wrong server day'; end if;
  perform pg_temp.expect_comp(format('select public.close_daily_ledger_day(%L::uuid,%L::uuid,%s,%L::jsonb)',
    'c2000000-0000-4000-8000-000000000016',v_day,(v_state ->> 'day_version')::bigint,v_state -> 'counts'),'stale_day');
  perform set_config('TimeZone','UTC',true);
  set constraints all immediate;
end;
$day_edges$;
reset role;
rollback;

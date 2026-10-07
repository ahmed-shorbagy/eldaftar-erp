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

do $test$
declare
  v_day uuid;
  v_version bigint;
  v_payload jsonb;
  v_result jsonb;
  v_sale uuid;
  v_original jsonb;
  v_partial uuid;
  v_purchase uuid;
  v_bounds jsonb;
  v_cash bigint;
  v_mg bigint;
  v_count bigint;
  v_ops integer;
  v_summary jsonb;
begin
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1' and day.status = 'open';
  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'ledger_correction',
    'expected_day_id', v_day, 'expected_day_version', v_version::text,
    'reason', 'نقص جرد',
    'counted', jsonb_build_object(
      'cash', jsonb_build_object('cash','500000','instant_transfer','0','wallet','0','card','1000'),
      'stock', jsonb_build_array(jsonb_build_object(
        'category','worked_jewelry','karat',18,'milligrams','9000','count','3')),
      'scrap', '[]'::jsonb));
  v_result := public.post_ledger_correction_v1('c1000000-0000-4000-8000-000000000002', v_payload);
  if v_result ->> 'ok' is distinct from 'true' or v_result ->> 'replayed' is distinct from 'false'
    or (v_result -> 'deltas' -> 'stock' -> 0 ->> 'milligrams') is distinct from '-1000'
    or (v_result -> 'deltas' -> 'stock' -> 0 ->> 'count') is distinct from '-1' then
    raise exception 'correction delta mismatch %', v_result;
  end if;
  if (select sum(movement.delta_milligrams) from public.inventory_lot_movements as movement
      where movement.operation_id = (v_result ->> 'operation_id')::uuid) is distinct from -1000
    or (select sum(movement.delta_count) from public.inventory_lot_movements as movement
      where movement.operation_id = (v_result ->> 'operation_id')::uuid) is distinct from -1 then
    raise exception 'correction lots did not follow the delta';
  end if;
  if not exists (
    select 1 from public.financial_audit_events
    where operation_id = (v_result ->> 'operation_id')::uuid
      and action = 'ledger_correction_confirmed'
  ) or not exists (
    select 1 from public.financial_outbox
    where operation_id = (v_result ->> 'operation_id')::uuid
      and event_type = 'ledger_correction_confirmed'
  ) then
    raise exception 'correction audit or outbox missing';
  end if;
  if (public.post_ledger_correction_v1('c1000000-0000-4000-8000-000000000002', v_payload) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'correction replay failed';
  end if;
  perform pg_temp.expect_comp(
    format('select public.post_ledger_correction_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000002',
      jsonb_set(v_payload, '{reason}', '"سبب آخر"')),
    'payload_mismatch');
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  perform pg_temp.expect_comp(
    format('select public.post_ledger_correction_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000004',
      jsonb_build_object(
        'version', 1, 'kind', 'ledger_correction',
        'expected_day_id', v_day, 'expected_day_version', v_version::text,
        'reason', 'لا فرق',
        'counted', jsonb_build_object(
          'cash', jsonb_build_object('cash','500000','instant_transfer','0','wallet','0','card','1000'),
          'stock', jsonb_build_array(jsonb_build_object(
            'category','worked_jewelry','karat',18,'milligrams','9000','count','3')),
          'scrap', '[]'::jsonb))),
    'invalid_input');
  if exists (select 1 from public.financial_command_requests
      where idempotency_key = 'c1000000-0000-4000-8000-000000000004') then
    raise exception 'zero correction consumed a key';
  end if;
  perform pg_temp.expect_comp(
    format('select public.post_ledger_correction_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000005',
      jsonb_set(v_payload, '{expected_day_version}', '"1"')),
    'stale_day');

  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  v_result := public.post_ledger_correction_v1(
    'c1000000-0000-4000-8000-000000000006',
    jsonb_build_object(
      'version', 1, 'kind', 'ledger_correction',
      'expected_day_id', v_day, 'expected_day_version', v_version::text,
      'reason', 'إعادة الجرد',
      'counted', jsonb_build_object(
        'cash', jsonb_build_object('cash','500000','instant_transfer','0','wallet','0','card','1000'),
        'stock', jsonb_build_array(jsonb_build_object(
          'category','worked_jewelry','karat',18,'milligrams','10000','count','4')),
        'scrap', '[]'::jsonb)));
  if (v_result -> 'deltas' -> 'stock' -> 0 ->> 'milligrams') is distinct from '1000' then
    raise exception 'positive correction mismatch %', v_result;
  end if;
  if not exists (
    select 1 from public.inventory_lots as lot
    where lot.origin_operation_id = (v_result ->> 'operation_id')::uuid
      and lot.original_milligrams = 1000 and lot.display_name = 'تسوية جرد'
  ) then
    raise exception 'positive correction did not create a lot';
  end if;

  v_result := public.post_daily_ledger_trade(
    'c1000000-0000-4000-8000-000000000010',
    '{"version":2,"kind":"sale","total_piastres":"8000","pricing":{"base_piastres":"7000","workmanship_piastres":"1000","other_charges_piastres":"0","other_charges_label":"","discount_piastres":"0"},"tenders":[{"method":"cash","piastres":"8000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"4000","count":"2","item_name":"خاتم","line_price_piastres":"7000"}],"description":"","customer_name":"عميل","customer_phone":"","note":"بيع"}'::jsonb);
  v_sale := (v_result ->> 'operation_id')::uuid;
  select detail.payload into v_original
  from public.financial_operation_details as detail where detail.operation_id = v_sale;
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'sale_return', 'original_operation_id', v_sale,
    'expected_day_id', v_day, 'expected_day_version', v_version::text,
    'note', 'مرتجع جزئي',
    'items', jsonb_build_array(jsonb_build_object(
      'item_index','0','milligrams','2000','count','1')),
    'consideration_piastres', '3000',
    'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','3000')),
    'pricing', jsonb_build_object(
      'base_piastres','2500','workmanship_piastres','500',
      'other_charges_piastres','0','other_charges_label','','discount_piastres','0'));
  v_result := public.post_linked_return_v1('c1000000-0000-4000-8000-000000000011', v_payload);
  v_partial := (v_result ->> 'operation_id')::uuid;
  if v_result ->> 'cash_refund_piastres' is distinct from '3000'
    or v_result ->> 'cancelled_payable_piastres' is distinct from '0' then
    raise exception 'partial sale cash mismatch %', v_result;
  end if;
  if (select sum(movement.delta_milligrams) from public.inventory_lot_movements as movement
      where movement.operation_id = v_partial) is distinct from 2000 then
    raise exception 'partial return mirrored the whole sale';
  end if;
  select detail.payload into v_bounds
  from public.financial_operation_details as detail where detail.operation_id = v_sale;
  if v_bounds is distinct from v_original then
    raise exception 'original sale payload changed';
  end if;
  v_bounds := public.get_return_remainder_v1(v_sale);
  if v_bounds ->> 'fully_returned' is distinct from 'false'
    or v_bounds ->> 'returned_consideration_piastres' is distinct from '3000'
    or v_bounds ->> 'remainder_consideration_piastres' is distinct from '5000'
    or v_bounds -> 'items' -> 0 ->> 'remainder_milligrams' is distinct from '2000'
    or v_bounds -> 'items' -> 0 ->> 'remainder_count' is distinct from '1'
    or v_bounds -> 'pricing' -> 'base_piastres' ->> 'returned' is distinct from '2500' then
    raise exception 'remainder contract mismatch %', v_bounds;
  end if;
  if (public.post_linked_return_v1('c1000000-0000-4000-8000-000000000011', v_payload) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'partial replay failed';
  end if;
  perform pg_temp.expect_comp(
    format('select public.post_linked_return_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000011',
      jsonb_set(v_payload, '{consideration_piastres}', '"3001"')),
    'payload_mismatch');
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  perform pg_temp.expect_comp(
    format('select public.post_linked_return_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000012',
      jsonb_set(jsonb_set(v_payload, '{expected_day_version}', to_jsonb(v_version::text)),
        '{items,0,milligrams}', '"2001"')),
    'return_exceeds_original');
  perform pg_temp.expect_comp(
    format('select public.post_linked_return_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000013',
      jsonb_set(jsonb_set(v_payload, '{expected_day_version}', to_jsonb(v_version::text)),
        '{pricing,base_piastres}', '"5000"')),
    'return_exceeds_original');
  perform pg_temp.expect_comp(
    format('select public.post_linked_return_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000014',
      jsonb_set(jsonb_set(v_payload, '{expected_day_version}', to_jsonb(v_version::text)),
        '{tenders}', '[{"method":"card","piastres":"3000"}]')),
    'negative_owned_balance');

  perform pg_temp.expect_comp(format('select public.post_daily_ledger_return(%L::uuid,%L::uuid,%L)',
    'c1000000-0000-4000-8000-000000000015',v_sale,'إتمام المرتجع'),'explicit_refund_required');
  select day.day_version into v_version from public.business_days day where day.id = v_day;
  v_payload := jsonb_build_object('version',1,'kind','sale_return','original_operation_id',v_sale,
    'expected_day_id',v_day,'expected_day_version',v_version::text,'note','إتمام المرتجع',
    'items',jsonb_build_array(jsonb_build_object('item_index','0','milligrams','2000','count','1')),
    'consideration_piastres','5000','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','5000')),
    'pricing',jsonb_build_object('base_piastres','4500','workmanship_piastres','500',
      'other_charges_piastres','0','other_charges_label','','discount_piastres','0'));
  v_result := public.post_linked_return_v1('c1000000-0000-4000-8000-000000000015',v_payload);
  if v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'remainder return did not post';
  end if;
  v_bounds := public.get_return_remainder_v1(v_sale);
  if v_bounds ->> 'fully_returned' is distinct from 'true'
    or v_bounds ->> 'remainder_consideration_piastres' is distinct from '0'
    or v_bounds -> 'items' -> 0 ->> 'remainder_milligrams' is distinct from '0' then
    raise exception 'full after partial left a remainder %', v_bounds;
  end if;
  select coalesce(sum(posting.amount), 0) into v_cash
  from public.journal_postings as posting
  join public.ledger_accounts as account on account.id = posting.account_id
  where posting.operation_id = (v_result ->> 'operation_id')::uuid
    and account.account_kind = 'cash_method';
  select coalesce(sum(posting.amount), 0) into v_mg
  from public.journal_postings as posting
  join public.ledger_accounts as account on account.id = posting.account_id
  where posting.operation_id = (v_result ->> 'operation_id')::uuid
    and account.account_kind = 'saleable_metal';
  if v_cash is distinct from -5000 or v_mg is distinct from 2000 then
    raise exception 'remainder return reversed the original, cash % gold %', v_cash, v_mg;
  end if;
  perform pg_temp.expect_comp(
    format('select public.post_daily_ledger_return(%L::uuid, %L::uuid, %L)',
      'c1000000-0000-4000-8000-000000000016', v_sale, 'مرة أخرى'),
    'already_returned');
  if (public.post_linked_return_v1(
      'c1000000-0000-4000-8000-000000000015', v_payload) ->> 'replayed')
      is distinct from 'true' then
    raise exception 'legacy remainder replay failed';
  end if;

  v_result := public.post_daily_ledger_trade(
    'c1000000-0000-4000-8000-000000000020',
    '{"version":1,"kind":"purchase","total_piastres":"10000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","item_name":"سوار","line_price_piastres":null}],"description":"","customer_name":"تاجر","customer_phone":"","note":"","purchase_obligation_piastres":"6000"}'::jsonb);
  v_purchase := (v_result ->> 'operation_id')::uuid;
  perform public.settle_purchase_cash_payable(
    'c1000000-0000-4000-8000-000000000021', v_purchase,
    '[{"method":"cash","piastres":"2000"}]'::jsonb);
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'purchase_return', 'original_operation_id', v_purchase,
    'expected_day_id', v_day, 'expected_day_version', v_version::text,
    'note', 'مرتجع شراء جزئي',
    'items', jsonb_build_array(jsonb_build_object(
      'item_index','0','milligrams','2000','count','1')),
    'consideration_piastres', '5000',
    'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','1000')));
  v_result := public.post_linked_return_v1('c1000000-0000-4000-8000-000000000022', v_payload);
  if v_result ->> 'cancelled_payable_piastres' is distinct from '4000'
    or v_result ->> 'cash_refund_piastres' is distinct from '1000' then
    raise exception 'purchase return split mismatch %', v_result;
  end if;
  if (select remaining_piastres from public.purchase_cash_payables where operation_id = v_purchase)
      is distinct from 0 then
    raise exception 'payable was not cancelled first';
  end if;
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  v_result := public.post_linked_return_v1(
    'c1000000-0000-4000-8000-000000000023',
    jsonb_build_object(
      'version', 1, 'kind', 'purchase_return', 'original_operation_id', v_purchase,
      'expected_day_id', v_day, 'expected_day_version', v_version::text,
      'note', 'باقي الثمن', 'items', '[]'::jsonb,
      'consideration_piastres', '5000',
      'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','5000'))));
  if v_result ->> 'cancelled_payable_piastres' is distinct from '0'
    or v_result ->> 'cash_refund_piastres' is distinct from '5000' then
    raise exception 'excess seller refund mismatch %', v_result;
  end if;
  if (public.get_return_remainder_v1(v_purchase) ->> 'fully_returned') is distinct from 'true' then
    raise exception 'purchase not fully returned';
  end if;

  v_result := public.post_daily_ledger_trade(
    'c1000000-0000-4000-8000-000000000029',
    '{"version":1,"kind":"sale","total_piastres":"2000","tenders":[{"method":"cash","piastres":"2000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"للرفض","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb);
  v_sale := (v_result ->> 'operation_id')::uuid;
  select count(*) into v_ops from public.financial_operations
  where shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1';
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  perform pg_temp.expect_comp(
    format('select public.post_exchange_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000030',
      jsonb_build_object(
        'version', 1, 'kind', 'exchange',
        'expected_day_id', v_day, 'expected_day_version', v_version::text,
        'note', 'استبدال فاشل',
        'return', jsonb_build_object(
          'kind','sale_return','original_operation_id', v_sale, 'note','',
          'items', jsonb_build_array(jsonb_build_object('item_index','0','milligrams','1000','count','1')),
          'consideration_piastres','1',
          'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','1'))),
        'replacement', '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"999999","count":"1","item_name":"زائد","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb)),
    'negative_owned_balance');
  if (select count(*) from public.financial_operations
      where shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1') is distinct from v_ops then
    raise exception 'failed exchange left a posting';
  end if;

  v_result := public.post_daily_ledger_trade(
    'c1000000-0000-4000-8000-000000000031',
    '{"version":1,"kind":"sale","total_piastres":"4000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb);
  v_sale := (v_result ->> 'operation_id')::uuid;
  select day.day_version into v_version from public.business_days as day where day.id = v_day;
  v_result := public.post_exchange_v1(
    'c1000000-0000-4000-8000-000000000032',
    jsonb_build_object(
      'version', 1, 'kind', 'exchange',
      'expected_day_id', v_day, 'expected_day_version', v_version::text,
      'note', 'استبدال',
      'return', jsonb_build_object(
        'kind','sale_return','original_operation_id', v_sale, 'note','مرتجع الاستبدال',
        'items', jsonb_build_array(jsonb_build_object('item_index','0','milligrams','2000','count','1')),
        'consideration_piastres','4000',
        'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','4000'))),
      'replacement', '{"version":1,"kind":"sale","total_piastres":"1500","tenders":[{"method":"cash","piastres":"1500"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","item_name":"بديل","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb));
  if v_result ->> 'replayed' is distinct from 'false'
    or v_result -> 'return_effects' ->> 'cash_piastres' is distinct from '-4000'
    or v_result -> 'replacement_effects' ->> 'cash_piastres' is distinct from '1500'
    or v_result -> 'net_effects' ->> 'cash_piastres' is distinct from '-2500'
    or (v_result -> 'net_effects' -> 'buckets' -> 0 ->> 'milligrams') is distinct from '0' then
    raise exception 'exchange effects mismatch %', v_result;
  end if;
  if (v_result ->> 'day_version')::bigint <> v_version + 1 then
    raise exception 'exchange version bump %', v_result -> 'day_version';
  end if;
  if (public.post_exchange_v1(
      'c1000000-0000-4000-8000-000000000032',
      jsonb_build_object(
        'version', 1, 'kind', 'exchange',
        'expected_day_id', v_day, 'expected_day_version', v_version::text,
        'note', 'استبدال',
        'return', jsonb_build_object(
          'kind','sale_return','original_operation_id', v_sale, 'note','مرتجع الاستبدال',
          'items', jsonb_build_array(jsonb_build_object('item_index','0','milligrams','2000','count','1')),
          'consideration_piastres','4000',
          'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','4000'))),
        'replacement', '{"version":1,"kind":"sale","total_piastres":"1500","tenders":[{"method":"cash","piastres":"1500"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","item_name":"بديل","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb)
    ) ->> 'replayed') is distinct from 'true' then
    raise exception 'exchange replay failed';
  end if;

  if exists (
    select 1 from public.journals as journal
    join public.journal_postings as posting on posting.journal_id = journal.id
    where journal.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1'
    group by journal.id
    having count(*) < 2 or sum(posting.amount) <> 0
  ) then
    raise exception 'journal conservation failed';
  end if;
  select coalesce(sum(account.amount), 0) into v_mg
  from public.ledger_account_balances as account
  where account.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1'
    and account.account_kind = 'saleable_metal';
  select coalesce(sum(account.amount), 0) into v_count
  from public.ledger_account_balances as account
  where account.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1'
    and account.account_kind = 'saleable_count';
  if v_mg <= 0 or v_count <= 0 or (v_mg = 0) <> (v_count = 0) then
    raise exception 'owned stock pair broken mg % count %', v_mg, v_count;
  end if;
  v_summary := public.get_ledger_compensation_summary_v1();
  if (v_summary ->> 'gross_sale_piastres')::numeric
      - (v_summary ->> 'sale_return_piastres')::numeric
      is distinct from (v_summary ->> 'net_sale_piastres')::numeric
    or (v_summary ->> 'correction_cash_delta_piastres') is distinct from '0' then
    raise exception 'summary contract mismatch %', v_summary;
  end if;
  execute 'set constraints all deferred';
  execute 'set constraints all immediate';
end;
$test$;

do $test$
declare
  v_day uuid;
  v_version bigint;
  v_purchase uuid;
  v_result jsonb;
begin
  execute 'set constraints all deferred';
  perform set_config('request.jwt.claim.sub', 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', true);
  perform public.confirm_opening_balances(
    'c2000000-0000-4000-8000-000000000001',
    '{"version":1,"cash":{"cash":"100000","card":"1000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"2"}],"scrap":[]}'::jsonb);
  perform public.post_daily_ledger_trade(
    'c2000000-0000-4000-8000-000000000002',
    '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"2","item_name":"كل الرصيد","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb);
  v_result := public.post_daily_ledger_trade(
    'c2000000-0000-4000-8000-000000000003',
    '{"version":1,"kind":"purchase","total_piastres":"4000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","item_name":"وارد","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb);
  v_purchase := (v_result ->> 'operation_id')::uuid;
  perform public.post_daily_ledger_trade(
    'c2000000-0000-4000-8000-000000000004',
    '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2000","count":"1","item_name":"بيع الوارد","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb);
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = 'b2b2b2b2-b2b2-42b2-82b2-b2b2b2b2b2b2' and day.status = 'open';
  perform pg_temp.expect_comp(
    format('select public.post_linked_return_v1(%L::uuid, %L::jsonb)',
      'c2000000-0000-4000-8000-000000000005',
      jsonb_build_object(
        'version', 1, 'kind', 'purchase_return', 'original_operation_id', v_purchase,
        'expected_day_id', v_day, 'expected_day_version', v_version::text,
        'note', 'لا يوجد مخزون',
        'items', jsonb_build_array(jsonb_build_object('item_index','0','milligrams','2000','count','1')),
        'consideration_piastres', '4000',
        'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','4000')))),
    'negative_owned_balance');
  execute 'set constraints all immediate';
end;
$test$;

reset role;
set local role anon;
do $test$
begin
  begin
    perform public.get_return_remainder_v1('b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1');
    raise exception 'anon read the remainder';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.post_ledger_correction_v1(
      'c1000000-0000-4000-8000-000000000099', '{}'::jsonb);
    raise exception 'anon posted a correction';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.post_linked_return_v1(
      'c1000000-0000-4000-8000-000000000098', '{}'::jsonb);
    raise exception 'anon posted a return';
  exception when insufficient_privilege then
    null;
  end;
  begin
    perform public.post_exchange_v1(
      'c1000000-0000-4000-8000-000000000097', '{}'::jsonb);
    raise exception 'anon posted an exchange';
  exception when insufficient_privilege then
    null;
  end;
end;
$test$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', true);
select set_config('request.jwt.claim.session_id', 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1', true);
select pg_temp.expect_comp(
  'select public.get_ledger_compensation_summary_v1()',
  'session_expired');

reset role;
update public.shop_memberships set revoked_at = now()
where user_id = 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', true);
select set_config('request.jwt.claim.session_id', '', true);
select pg_temp.expect_comp(
  'select public.get_ledger_compensation_summary_v1()',
  'forbidden');

reset role;
update public.shop_memberships set revoked_at = null
where user_id = 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1';
update public.shop_entitlements set expires_at = now() - interval '1 minute'
where shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', true);
select set_config('request.jwt.claim.session_id', '', true);
do $test$
declare v_sale uuid; v_day uuid; v_version bigint;
begin
  if public.get_ledger_compensation_summary_v1() ->> 'state' is null then
    raise exception 'expired owner could not read the summary';
  end if;
  select operation.id into v_sale from public.financial_operations as operation
  where operation.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1' and operation.kind = 'sale'
  limit 1;
  if public.get_return_remainder_v1(v_sale) ->> 'operation_id' is null then
    raise exception 'expired owner could not read the remainder';
  end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1';
  perform pg_temp.expect_comp(
    format('select public.post_ledger_correction_v1(%L::uuid, %L::jsonb)',
      'c1000000-0000-4000-8000-000000000040',
      jsonb_build_object(
        'version', 1, 'kind', 'ledger_correction',
        'expected_day_id', v_day, 'expected_day_version', v_version::text,
        'reason', 'منتهي',
        'counted', '{"cash":{"cash":"1","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb)),
    'shop_not_active');
end;
$test$;

select set_config('request.jwt.claim.sub', 'a5a5a5a5-a5a5-45a5-85a5-a5a5a5a5a5a5', true);
select pg_temp.expect_comp(
  'select public.get_ledger_compensation_summary_v1()',
  'forbidden');

reset role;
do $test$
declare v_sale uuid;
begin
  select operation.id into v_sale from public.financial_operations as operation
  where operation.shop_id = 'b1b1b1b1-b1b1-41b1-81b1-b1b1b1b1b1b1' and operation.kind = 'sale'
  limit 1;
  if v_sale is null then raise exception 'shop A sale missing'; end if;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', true);
  perform set_config('request.jwt.claim.session_id', '', true);
  perform pg_temp.expect_comp(
    format('select public.get_return_remainder_v1(%L::uuid)', v_sale),
    'not_found');
end;
$test$;

rollback;

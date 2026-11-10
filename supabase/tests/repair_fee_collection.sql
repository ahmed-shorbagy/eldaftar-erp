-- Later collection of an outstanding repair fee. The transaction rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('d1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'collect-owner@example.test', false, now(), now()),
  ('d1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'collect-partner@example.test', false, now(), now()),
  ('d1100000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'collect-staff@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('d2200000-0000-4000-8000-000000000001', 'متجر التحصيل', 'مالك التحصيل', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000001', 'owner'),
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000002', 'partner'),
  ('d2200000-0000-4000-8000-000000000001', 'd1100000-0000-4000-8000-000000000003', 'employee');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('d2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'd3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"1000000","instant_transfer":"0","wallet":"500000","card":"0"},"stock":[],"scrap":[]}'::jsonb
);

create function pg_temp.ready_repair(p_name text)
returns uuid
language plpgsql
as $fn$
declare
  v_repair uuid;
begin
  v_repair := (public.post_repair_intake_v1(
    pg_catalog.gen_random_uuid(),
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', p_name, 'customer_phone', '',
      'item_description', 'خاتم', 'measured_milligrams', '1255',
      'karat', 21, 'issue', 'مفصص', 'intake_notes', '',
      'estimated_fee_piastres', '15000'
    )
  ) ->> 'repair_id')::uuid;
  perform public.post_repair_status_v1(
    pg_catalog.gen_random_uuid(),
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'repair_status', 'repair_id', v_repair,
      'expected_version', '1', 'status', 'in_progress'
    )
  );
  perform public.post_repair_status_v1(
    pg_catalog.gen_random_uuid(),
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'repair_status', 'repair_id', v_repair,
      'expected_version', '2', 'status', 'ready'
    )
  );
  return v_repair;
end;
$fn$;

create function pg_temp.handover(
  p_repair uuid, p_version text, p_final text, p_collection text,
  p_collected text, p_tenders jsonb, p_day text, p_day_version text
) returns jsonb
language sql
as $fn$
  select pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'version', 1,
    'kind', 'repair_handover',
    'repair_id', p_repair,
    'expected_version', p_version,
    'final_fee_piastres', p_final,
    'collection', p_collection,
    'collected_piastres', p_collected,
    'tenders', p_tenders,
    'expected_day_id', p_day,
    'expected_day_version', p_day_version
  ));
$fn$;

create function pg_temp.expect_code(p_sql text, p_code text)
returns void language plpgsql as $fn$
begin
  begin
    execute p_sql;
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception using message = 'expected_' || p_code;
      elsif sqlerrm is distinct from p_code then
        raise exception using message = 'expected_' || p_code || '_got_' || sqlerrm;
      end if;
  end;
end;
$fn$;

do $collect$
declare
  v_state jsonb;
  v_unpaid uuid;
  v_paid uuid;
  v_later uuid;
  v_received uuid;
  v_result jsonb;
  v_replay jsonb;
  v_cash bigint;
  v_wallet bigint;
  v_summary jsonb;
  v_counts jsonb;
  v_key uuid := 'd4400000-0000-4000-8000-000000000099';
  v_payload jsonb;
begin
  v_state := public.get_daily_ledger_day_state();
  v_unpaid := pg_temp.ready_repair('غير محصل');
  perform public.post_repair_handover_v1(
    'd4400000-0000-4000-8000-000000000011',
    pg_temp.handover(v_unpaid, '3', '20000', 'none', '0', '[]'::jsonb, null, null)
  );
  v_summary := public.get_ledger_date_v2(null, null, 20) -> 'day_summary';
  if v_summary ->> 'repair_piastres' is distinct from '0'
    or v_summary ->> 'repair_count' is distinct from '0' then
    raise exception 'unpaid_repair_posted %', v_summary;
  end if;

  v_state := public.get_daily_ledger_day_state();
  v_paid := pg_temp.ready_repair('تحصيل كامل');
  perform public.post_repair_handover_v1(
    'd4400000-0000-4000-8000-000000000021',
    pg_temp.handover(
      v_paid, '3', '20000', 'all', '20000',
      jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '20000')),
      v_state ->> 'business_day_id', v_state ->> 'day_version'
    )
  );
  v_summary := public.get_ledger_date_v2(null, null, 20) -> 'day_summary';
  if v_summary ->> 'repair_piastres' is distinct from '20000'
    or v_summary ->> 'repair_count' is distinct from '1'
    or (public.get_financial_day_report_v2((v_state ->> 'business_day_id')::uuid)
      #>> '{summary,repair_piastres}') is distinct from '20000'
    or (public.get_financial_day_report_v2((v_state ->> 'business_day_id')::uuid)
      #>> '{summary,repair_count}') is distinct from '1' then
    raise exception 'paid_repair_revenue_wrong %', v_summary;
  end if;

  v_state := public.get_daily_ledger_day_state();
  v_later := pg_temp.ready_repair('تحصيل لاحق');
  perform public.post_repair_handover_v1(
    'd4400000-0000-4000-8000-000000000031',
    pg_temp.handover(
      v_later, '3', '20000', 'part', '8000',
      jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '8000')),
      v_state ->> 'business_day_id', v_state ->> 'day_version'
    )
  );
  select coalesce(sum(posting.amount), 0) into v_cash
  from public.journal_postings as posting
  join public.ledger_accounts as account
    on account.shop_id = posting.shop_id and account.id = posting.account_id
  where account.shop_id = 'd2200000-0000-4000-8000-000000000001'
    and account.method_code = 'cash';
  select coalesce(sum(posting.amount), 0) into v_wallet
  from public.journal_postings as posting
  join public.ledger_accounts as account
    on account.shop_id = posting.shop_id and account.id = posting.account_id
  where account.shop_id = 'd2200000-0000-4000-8000-000000000001'
    and account.method_code = 'wallet';

  v_state := public.get_daily_ledger_day_state();
  v_payload := jsonb_build_object(
    'version', 1,
    'repair_id', v_later,
    'expected_version', '4',
    'day_id', v_state ->> 'business_day_id',
    'day_version', v_state ->> 'day_version',
    'amount_piastres', '12000',
    'tenders', jsonb_build_array(
      jsonb_build_object('method', 'cash', 'piastres', '7000'),
      jsonb_build_object('method', 'wallet', 'piastres', '5000')
    )
  );
  v_result := public.post_repair_collect_v1(v_key, v_payload);
  if v_result ->> 'outstanding_piastres' is distinct from '0'
    or v_result ->> 'collected_piastres' is distinct from '20000'
    or v_result ->> 'collection_operation_id' is null
    or jsonb_array_length(public.get_repair_v1(v_later) -> 'collections') is distinct from 1
    or not exists (
      select 1 from public.financial_operations
      where shop_id = 'd2200000-0000-4000-8000-000000000001'
        and id = (v_result ->> 'collection_operation_id')::uuid
        and kind = 'repair_fee_collection'
    )
    or not exists (
      select 1 from public.financial_operations
      where shop_id = 'd2200000-0000-4000-8000-000000000001'
        and id = (public.get_repair_v1(v_later) ->> 'financial_operation_id')::uuid
        and kind = 'repair_fee'
    ) then
    raise exception 'collection_result_wrong %', v_result;
  end if;
  if (select coalesce(sum(posting.amount), 0)
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where account.shop_id = 'd2200000-0000-4000-8000-000000000001'
        and account.method_code = 'cash') <> v_cash + 7000
    or (select coalesce(sum(posting.amount), 0)
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where account.shop_id = 'd2200000-0000-4000-8000-000000000001'
        and account.method_code = 'wallet') <> v_wallet + 5000 then
    raise exception 'collection_cash_wrong';
  end if;
  if exists (
    select 1 from jsonb_array_elements(
      public.list_repairs_v1('', 'outstanding', 20, null) -> 'items'
    ) as item
    where item ->> 'repair_id' = v_later::text
  ) then
    raise exception 'settled_repair_still_outstanding';
  end if;

  v_replay := public.post_repair_collect_v1(v_key, v_payload);
  if v_replay ->> 'replayed' is distinct from 'true'
    or v_replay ->> 'collection_operation_id' is distinct from v_result ->> 'collection_operation_id' then
    raise exception 'collection_replay_wrong %', v_replay;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_repair_collect_v1(%L, %L)',
      v_key, (v_payload || '{"amount_piastres":"1000"}')::text
    ),
    'payload_mismatch'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_repair_collect_v1(%L, %L)',
      'd4400000-0000-4000-8000-000000000098',
      jsonb_build_object(
        'version', 1,
        'repair_id', v_later,
        'expected_version', '5',
        'day_id', v_payload ->> 'day_id',
        'day_version', v_result ->> 'day_version',
        'amount_piastres', '1',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1'))
      )::text
    ),
    'invalid_input'
  );

  v_received := (public.post_repair_intake_v1(
    'd4400000-0000-4000-8000-000000000040',
    jsonb_build_object(
      'version', 1, 'kind', 'repair_intake',
      'customer_name', 'لم يسلم', 'customer_phone', '',
      'item_description', 'خاتم', 'measured_milligrams', '1000',
      'karat', 21, 'issue', 'تلميع', 'intake_notes', '',
      'estimated_fee_piastres', '0'
    )
  ) ->> 'repair_id')::uuid;
  v_state := public.get_daily_ledger_day_state();
  perform pg_temp.expect_code(
    format(
      'select public.post_repair_collect_v1(%L, %L)',
      'd4400000-0000-4000-8000-000000000041',
      jsonb_build_object(
        'version', 1, 'repair_id', v_received, 'expected_version', '1',
        'day_id', v_state ->> 'business_day_id',
        'day_version', v_state ->> 'day_version',
        'amount_piastres', '1',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1'))
      )::text
    ),
    'repair_not_delivered'
  );

  v_state := public.get_daily_ledger_day_state();
  v_counts := jsonb_build_object(
    'version', 2,
    'cash', v_state #> '{counts,cash}',
    'scrap', v_state #> '{counts,scrap}',
    'stock', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_name', 'خاتم',
        'category', item ->> 'category',
        'karat', item -> 'karat',
        'count', item ->> 'count',
        'milligrams', 'null'::jsonb
      ))
      from jsonb_array_elements(v_state #> '{counts,stock}') as item
    ), '[]'::jsonb)
  );
  if (public.close_daily_ledger_day_v2(
    'd4400000-0000-4000-8000-000000000050',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    v_counts
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'close_failed';
  end if;
  if (public.get_daily_ledger_home_v2() #>> '{day_summary,repair_piastres}') is distinct from '0' then
    raise exception 'closed_home_kept_repair_revenue';
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_repair_collect_v1(%L, %L)',
      'd4400000-0000-4000-8000-000000000051',
      jsonb_build_object(
        'version', 1, 'repair_id', v_unpaid, 'expected_version', '4',
        'day_id', v_state ->> 'business_day_id',
        'day_version', v_state ->> 'day_version',
        'amount_piastres', '1000',
        'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1000'))
      )::text
    ),
    'day_closed'
  );

  perform set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000002', true);
  perform pg_temp.expect_code(
    format('select public.post_repair_collect_v1(%L, %L)', 'd4400000-0000-4000-8000-000000000060', v_payload::text),
    'forbidden'
  );
  perform set_config('request.jwt.claim.sub', 'd1100000-0000-4000-8000-000000000003', true);
  perform pg_temp.expect_code(
    format('select public.post_repair_collect_v1(%L, %L)', 'd4400000-0000-4000-8000-000000000061', v_payload::text),
    'forbidden'
  );
end;
$collect$;

reset role;
do $direct$
begin
  update public.repairs
    set collected_piastres = collected_piastres + 1,
        outstanding_piastres = outstanding_piastres - 1,
        record_version = record_version + 1
  where shop_id = 'd2200000-0000-4000-8000-000000000001'
    and status = 'delivered'
    and outstanding_piastres > 0;
  raise exception 'direct_collect_allowed';
exception
  when others then
    if sqlerrm is distinct from 'audit_append_only' then
      raise exception 'direct_collect_got_%', sqlerrm;
    end if;
end;
$direct$;

rollback;

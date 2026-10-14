-- Supplemental read-only export gates inside the existing debts.sql synthetic
-- transaction. Its final rollback retires every fixture, trigger and probe.
reset role;
select set_config('request.jwt.claim.sub','d7111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d7111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
do $expired_statement$
declare v_source uuid; s jsonb;
begin
  select id into v_source from public.shop_debts where shop_id='d7222222-2222-4222-8222-222222222222' limit 1;
  s:=public.get_debt_statement_v1('standalone',v_source);
  if s->>'remaining_amount'<>'700' or s->>'history_complete'<>'true' then raise exception 'expired_export_denied';end if;
end;
$expired_statement$;
select set_config('request.jwt.claim.sub','d1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);

do $statement$
declare b record; s jsonb; old jsonb; again jsonb; v_count integer := 0;
  v_before text; v_after text; v_source uuid; v_event uuid; v_operation uuid;
begin
  select md5(string_agg(x.row::text,'' order by x.row::text)) into v_before from (
    select to_jsonb(t) row from public.financial_operations t
    union all select to_jsonb(t) from public.financial_operation_details t
    union all select to_jsonb(t) from public.financial_audit_events t
    union all select to_jsonb(t) from public.debt_events t
    union all select to_jsonb(t) from public.shop_debts t
    union all select to_jsonb(t) from public.debt_command_requests t
    union all select to_jsonb(t) from public.invoice_dispatch_confirmations t
  ) x;
  for b in select * from private.debt_balances('d1222222-2222-4222-8222-222222222222') loop
    s:=public.get_debt_statement_v1(b.source_kind,b.source_id);
    old:=public.get_debt_v1(b.source_kind,b.source_id);
    again:=public.get_debt_statement_v1(b.source_kind,b.source_id);
    if s->>'original_amount' is distinct from old->>'original_amount'
      or s->>'settled_amount' is distinct from old->>'settled_amount'
      or s->>'cancelled_amount' is distinct from old->>'cancelled_amount'
      or s->>'remaining_amount' is distinct from old->>'remaining_amount'
      or s->>'history_complete' is distinct from 'true'
      or (s->>'history_count')::integer <> jsonb_array_length(s->'history')
      or s->>'freshness' is distinct from again->>'freshness'
      or (s->>'snapshot_at')::timestamptz > clock_timestamp()
      or exists(select 1 from jsonb_array_elements(s->'history') h(e) where e ? 'payload' or e ? 'kind')
      or (s->>'unit'='money' and exists(select 1 from jsonb_array_elements(s->'history') h(e) where e->>'gold_milligrams'<>'0'))
    then raise exception 'statement_contract_%',b.source_kind; end if;
    if b.source_kind <> 'standalone' and (s->>'source_sequence' is null
      or (select count(distinct e->>'operation_id') from jsonb_array_elements(s->'history') h(e)
        where e->>'event_type' in ('posted','linked_settlement','linked_return'))
        <> (select count(*) from jsonb_array_elements(s->'history') h(e)
        where e->>'event_type' in ('posted','linked_settlement','linked_return')))
    then raise exception 'statement_operation_dedup'; end if;
    v_count:=v_count+1;
  end loop;
  if v_count<5 then raise exception 'statement_fixture_coverage'; end if;

  -- Missing zero-amount archive event must never claim complete history.
  select source_id,id into v_source,v_event from public.debt_events where
    shop_id='d1222222-2222-4222-8222-222222222222' and source_kind='standalone' and event_type='archived' limit 1;
  if v_event is null then raise exception 'archive_fixture_missing'; end if;
  begin
    alter table public.debt_events disable trigger debt_events_append_only;
    delete from public.debt_events where id=v_event;
    perform public.get_debt_statement_v1('standalone',v_source);
    raise exception 'missing_archive_accepted';
  exception when others then
    if sqlerrm <> 'incomplete_debt_statement' then raise; end if;
  end;
  -- A moving standalone settlement requires immutable financial detail/audit.
  select source_id,(payload->>'operation_id')::uuid into v_source,v_operation
    from public.debt_events where shop_id='d1222222-2222-4222-8222-222222222222'
    and source_kind='standalone' and event_type='settled' and payload->>'ledger_effect'='move' limit 1;
  if v_operation is null then raise exception 'moving_fixture_missing'; end if;
  begin
    alter table public.financial_operation_details disable trigger user;
    delete from public.financial_operation_details where operation_id=v_operation;
    perform public.get_debt_statement_v1('standalone',v_source);
    raise exception 'missing_financial_detail_accepted';
  exception when others then
    if sqlerrm <> 'incomplete_debt_statement' then raise; end if;
  end;
  select md5(string_agg(x.row::text,'' order by x.row::text)) into v_after from (
    select to_jsonb(t) row from public.financial_operations t
    union all select to_jsonb(t) from public.financial_operation_details t
    union all select to_jsonb(t) from public.financial_audit_events t
    union all select to_jsonb(t) from public.debt_events t
    union all select to_jsonb(t) from public.shop_debts t
    union all select to_jsonb(t) from public.debt_command_requests t
    union all select to_jsonb(t) from public.invoice_dispatch_confirmations t
  ) x;
  if v_before is distinct from v_after then raise exception 'statement_financial_effect'; end if;
end;
$statement$;

set local role authenticated;
select pg_temp.expect_code('select private.debt_statement_content_v1(''d1222222-2222-4222-8222-222222222222'',''standalone'',''d3333333-3333-4333-8333-333333333333'')','permission denied for function debt_statement_content_v1');
select pg_temp.expect_code('select public.get_debt_statement_v1(null,null)','invalid_input');
select set_config('request.jwt.claim.sub','d2111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
select pg_temp.expect_code('select public.get_debt_statement_v1(''standalone'',''d3333333-3333-4333-8333-333333333333'')','not_found');
select set_config('request.jwt.claim.sub','d3111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d3111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
select pg_temp.expect_code('select public.get_debt_statement_v1(''standalone'',''d3333333-3333-4333-8333-333333333333'')','forbidden');
select set_config('request.jwt.claim.sub','d5111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d5111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
select pg_temp.expect_code('select public.get_debt_statement_v1(''standalone'',''d3333333-3333-4333-8333-333333333333'')','forbidden');
select set_config('request.jwt.claim.sub','d1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"d1818181-8181-4181-8181-818181818182","is_anonymous":false}',true);
select pg_temp.expect_code('select public.get_debt_statement_v1(''standalone'',''d3333333-3333-4333-8333-333333333333'')','session_expired');
reset role;

-- Supplemental to debts.sql in its rollback-only synthetic transaction.
reset role;
select set_config('request.jwt.claim.sub','d1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);

create function pg_temp.due_payload(k text,s uuid,d text) returns jsonb language sql as $f$
  select jsonb_build_object('version',1,'kind','debt_due','source_kind',k,'source_id',s,'due_date',d,
    'expected_due_version',j->>'due_version','expected_freshness',j->>'freshness') from (select public.get_debt_due_v1(k,s) j) r;
$f$;
create function pg_temp.due_assert_fail(q text,expected text) returns void language plpgsql as $f$
begin
  begin execute q; raise exception 'unexpected_success'; exception when others then
    if sqlerrm<>expected then raise exception 'expected %, got %',expected,sqlerrm; end if;
  end;
end;
$f$;
create function pg_temp.due_fail() returns trigger language plpgsql as $f$ begin raise exception 'due_test_failure'; end; $f$;

do $due$
declare v_id uuid; v_kind text; v_key uuid; v_payload jsonb; v_receipt jsonb; v_old jsonb; v_pdf jsonb;
  v_list jsonb; v_cursor text; v_seen text[]:=array[]::text[]; v_before text; v_after text; v_revision bigint;
  v_version bigint; v_day bigint; v_date text; v_count integer; k integer; direction text;
begin
  -- Add/change/clear across both standalone directions and all supported exact units.
  for direction in select unnest(array['shop_owes','owed_to_shop']) loop
    foreach k in array array[0,14,18,21,22,24] loop
      v_receipt:=public.post_debt_declare_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','debt_declare','direction',direction,
        'unit',case when k=0 then 'money' else 'gold' end,'karat',case when k=0 then null else k end,'amount','10005',
        'party_name','مواعيد اختبار '||direction||k,'contact_phone','','reason','رصيد اختبار','external_reference',null));
      v_id:=(v_receipt->>'source_id')::uuid;
      v_old:=public.get_debt_v1('standalone',v_id); v_pdf:=public.get_debt_statement_v1('standalone',v_id)-'snapshot_at'-'snapshot_at_shop';
      v_payload:=pg_temp.due_payload('standalone',v_id,'2024-02-29');v_key:=gen_random_uuid();
      v_receipt:=public.post_debt_due_v1(v_key,v_payload);
      if v_receipt->>'due_version'<>'1' or v_receipt->>'cash_piastres'<>'0' or v_receipt->>'gold_milligrams'<>'0' or v_receipt->>'actor_user_id'<>auth.uid()::text then raise exception 'due_receipt';end if;
      if public.post_debt_due_v1(v_key,v_payload)->>'replayed'<>'true' then raise exception 'due_replay';end if;
      if public.get_debt_due_status_v1(v_key,v_payload)->'result' is distinct from v_receipt then raise exception 'due_status';end if;
      perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',v_key,v_payload||jsonb_build_object('due_date','2024-03-01')),'payload_mismatch');
      perform pg_temp.due_assert_fail(format('select public.get_debt_due_status_v1(%L,%L::jsonb)',v_key,v_payload||jsonb_build_object('source_id',gen_random_uuid())),'payload_mismatch');
      perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',gen_random_uuid(),v_payload),'stale_due');
      v_payload:=pg_temp.due_payload('standalone',v_id,null);
      perform public.post_debt_due_v1(gen_random_uuid(),v_payload);
      if public.get_debt_due_v1('standalone',v_id)->>'due_date' is not null then raise exception 'due_clear';end if;
      v_payload:=pg_temp.due_payload('standalone',v_id,'9999-12-31');
      perform public.post_debt_due_v1(gen_random_uuid(),v_payload);
      if public.get_debt_v1('standalone',v_id) is distinct from v_old or public.get_debt_statement_v1('standalone',v_id)-'snapshot_at'-'snapshot_at_shop' is distinct from v_pdf then raise exception 'old_contract_modified';end if;
    end loop;
  end loop;
  -- Snapshot entire protected history after declarations, before metadata-only changes.
  select md5(string_agg(r::text,'' order by r::text)) into v_before from (
    select to_jsonb(t) r from public.financial_operations t union all select to_jsonb(t) from public.financial_operation_details t
    union all select to_jsonb(t) from public.financial_audit_events t union all select to_jsonb(t) from public.journal_postings t
    union all select to_jsonb(t) from public.business_days t union all select to_jsonb(t) from public.shop_debts t
    union all select to_jsonb(t) from public.debt_events t union all select to_jsonb(t) from public.debt_command_requests t
    union all select to_jsonb(t) from public.purchase_cash_payables t union all select to_jsonb(t) from public.gold_obligations t
    union all select to_jsonb(t) from public.inventory_lots t union all select to_jsonb(t) from public.inventory_receipts t
    union all select to_jsonb(t) from public.customers t union all select to_jsonb(t) from public.customer_number_declarations t
    union all select to_jsonb(t) from public.invoice_dispatch_confirmations t
  ) h;
  for v_kind,v_id in select source_kind,source_id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' and remaining_amount>0 loop
    v_payload:=pg_temp.due_payload(v_kind,v_id,public.get_debt_due_v1(v_kind,v_id)->>'local_date');
    select debt_revision into v_revision from public.shop_sync_signals where shop_id='d1222222-2222-4222-8222-222222222222';
    perform public.post_debt_due_v1(gen_random_uuid(),v_payload);
    if public.get_debt_due_v1(v_kind,v_id)->>'due_state'<>'today' or (select debt_revision from public.shop_sync_signals where shop_id='d1222222-2222-4222-8222-222222222222')<>v_revision+1 then raise exception 'due_revision_state';end if;
  end loop;
  select md5(string_agg(r::text,'' order by r::text)) into v_after from (
    select to_jsonb(t) r from public.financial_operations t union all select to_jsonb(t) from public.financial_operation_details t
    union all select to_jsonb(t) from public.financial_audit_events t union all select to_jsonb(t) from public.journal_postings t
    union all select to_jsonb(t) from public.business_days t union all select to_jsonb(t) from public.shop_debts t
    union all select to_jsonb(t) from public.debt_events t union all select to_jsonb(t) from public.debt_command_requests t
    union all select to_jsonb(t) from public.purchase_cash_payables t union all select to_jsonb(t) from public.gold_obligations t
    union all select to_jsonb(t) from public.inventory_lots t union all select to_jsonb(t) from public.inventory_receipts t
    union all select to_jsonb(t) from public.customers t union all select to_jsonb(t) from public.customer_number_declarations t
    union all select to_jsonb(t) from public.invoice_dispatch_confirmations t
  ) h;
  if v_before is distinct from v_after then raise exception 'metadata_financial_effect';end if;
  -- Complete deterministic pagination, query and filter binding, missing/null offsets.
  loop
    v_list:=public.get_debt_reminders_v1('','all',3,v_cursor);
    for v_old in select * from jsonb_array_elements(v_list->'items') loop
      if v_old->>'debt_key'=any(v_seen) then raise exception 'duplicate_page';end if;
      v_seen:=array_append(v_seen,v_old->>'debt_key');
    end loop;
    v_cursor:=v_list->>'next_cursor';exit when v_cursor is null;
  end loop;
  if array_length(v_seen,1)<>(v_list->>'total')::integer or array_length(v_seen,1)<12 then raise exception 'truncated_pages';end if;
  v_list:=public.get_debt_reminders_v1('','all',1,null);v_cursor:=v_list->>'next_cursor';
  perform pg_temp.due_assert_fail(format('select public.get_debt_reminders_v1(%L,%L,1,%L)','x','all',v_cursor),'stale_due_cursor');
  perform pg_temp.due_assert_fail(format('select public.get_debt_reminders_v1(%L,%L,1,%L)','','overdue',v_cursor),'stale_due_cursor');
  foreach v_old in array array[jsonb_build_object('freshness',v_list->>'freshness'),jsonb_build_object('freshness',v_list->>'freshness','offset',null),jsonb_build_object('freshness',v_list->>'freshness','offset','1')] loop
    perform pg_temp.due_assert_fail(format('select public.get_debt_reminders_v1(%L,%L,1,%L)','','all',v_old::text),'stale_due_cursor');
  end loop;
  -- Stale timezone/date/source reviews fail without touching financial state.
  select source_kind,source_id into v_kind,v_id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' limit 1;
  v_payload:=pg_temp.due_payload(v_kind,v_id,'2024-02-29');
  update public.shops set time_zone='America/New_York' where id='d1222222-2222-4222-8222-222222222222';
  perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',gen_random_uuid(),v_payload),'stale_due');
  perform pg_temp.due_assert_fail(format('select public.get_debt_reminders_v1(%L,%L,1,%L)','','all',v_cursor),'stale_due_cursor');
  update public.shops set time_zone='Africa/Cairo' where id='d1222222-2222-4222-8222-222222222222';
  foreach v_date in array array['2023-02-29','1900-02-29','2024-04-31','2024-13-01','2024-2-01','0000-01-01','today','2024-02-29T00:00:00Z'] loop
    perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',gen_random_uuid(),pg_temp.due_payload(v_kind,v_id,v_date)),'invalid_date');
  end loop;
  -- Atomic rollback after metadata, audit, sync, and request insertion.
  v_old:=public.get_debt_due_v1(v_kind,v_id);v_payload:=pg_temp.due_payload(v_kind,v_id,'2024-01-01');
  select count(*) into v_count from public.debt_due_events;
  create trigger due_test_failure after insert on public.debt_due_requests for each row execute function pg_temp.due_fail();
  perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',gen_random_uuid(),v_payload),'due_test_failure');
  drop trigger due_test_failure on public.debt_due_requests;
  if public.get_debt_due_v1(v_kind,v_id)-'snapshot_at'-'snapshot_at_shop' is distinct from v_old-'snapshot_at'-'snapshot_at_shop' or (select count(*) from public.debt_due_events)<>v_count then raise exception 'partial_due_commit';end if;
  -- Date metadata works with no open day; partial standalone settlement retains date.
  v_receipt:=public.post_debt_declare_v1(gen_random_uuid(),'{"version":1,"kind":"debt_declare","direction":"owed_to_shop","unit":"money","karat":null,"amount":"1000","party_name":"دورة موعد","contact_phone":"","reason":"اختبار","external_reference":null}');v_id:=(v_receipt->>'source_id')::uuid;v_kind:='standalone';
  perform public.post_debt_due_v1(gen_random_uuid(),pg_temp.due_payload(v_kind,v_id,'2024-01-01'));
  v_payload:=jsonb_build_object('version',1,'kind','debt_settle','source_kind',v_kind,'source_id',v_id,'direction','owed_to_shop','unit','money','karat',null,
    'amount','300','expected_remaining','1000','expected_version','1','ledger_effect','none','reason','سداد جزئي','settlement_reference',gen_random_uuid(),
    'expected_day_id',null,'expected_day_version',null,'tenders',null,'deliveries',null,'receipt',null);
  perform public.post_debt_settle_v1(gen_random_uuid(),v_payload);
  if public.get_debt_due_v1(v_kind,v_id)->>'remaining_amount'<>'700' or public.get_debt_due_v1(v_kind,v_id)->>'due_date'<>'2024-01-01' then raise exception 'partial_cleared_date';end if;
  v_payload:=v_payload||jsonb_build_object('amount','700','expected_remaining','700','expected_version','2','settlement_reference',gen_random_uuid());perform public.post_debt_settle_v1(gen_random_uuid(),v_payload);
  if public.get_debt_due_v1(v_kind,v_id)->>'due_state'<>'inactive' or public.get_debt_due_v1(v_kind,v_id)->>'due_date'<>'2024-01-01' then raise exception 'closed_lifecycle';end if;
  perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',gen_random_uuid(),pg_temp.due_payload(v_kind,v_id,null)),'due_not_active');
  -- Archive and cancellation keep date and its separate audit readable.
  for v_kind,v_id in select source_kind,source_id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' and remaining_amount>0 limit 3 loop
    v_old:=public.get_debt_due_v1(v_kind,v_id);
    perform public.post_debt_archive_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','debt_archive','source_kind',v_kind,'source_id',v_id,'expected_remaining',v_old->>'remaining_amount','expected_version',v_old->>'record_version','reason','أرشفة اختبار'));
    if public.get_debt_due_v1(v_kind,v_id)->>'due_state'<>'inactive' or public.get_debt_due_v1(v_kind,v_id)->>'remaining_amount' is distinct from v_old->>'remaining_amount' then raise exception 'archive_forgave_debt';end if;
  end loop;
end;
$due$;

do $clock$
begin
  if private.debt_due_state_v1('2026-10-14',1,'open','2026-10-14T20:59:59Z','Africa/Cairo')<>'today'
    or private.debt_due_state_v1('2026-10-14',1,'open','2026-10-14T21:00:00Z','Africa/Cairo')<>'overdue'
    or private.debt_due_state_v1('2026-03-08',1,'open','2026-03-08T06:59:59Z','America/New_York')<>'today'
    or private.debt_due_state_v1('2026-03-08',1,'open','2026-03-08T07:00:00Z','America/New_York')<>'today'
    or private.debt_due_state_v1('2026-11-01',1,'open','2026-11-01T05:30:00Z','America/New_York')<>'today'
    or private.debt_due_state_v1('2026-11-01',1,'open','2026-11-01T06:30:00Z','America/New_York')<>'today'
    or private.debt_due_state_v1('2026-10-15',1,'open','2026-10-14T12:00:00Z','Africa/Cairo')<>'upcoming'
    or private.debt_due_state_v1('2026-10-14',0,'open','2026-10-14T12:00:00Z','Africa/Cairo')<>'inactive'
  then raise exception 'server_calendar_clock';end if;
end;
$clock$;

-- Real-role isolation, append-only/direct write denial and expired read/replay.
set local role authenticated;
do $rls$
declare v_id uuid; p jsonb; key uuid:=gen_random_uuid(); r jsonb;
begin
  select source_id into v_id from public.debt_due_dates where shop_id='d1222222-2222-4222-8222-222222222222' limit 1;
  if v_id is null then raise exception 'owner_due_read';end if;
  perform pg_temp.due_assert_fail('update public.debt_due_dates set due_date=null','permission denied for table debt_due_dates');
  perform pg_temp.due_assert_fail('update public.debt_due_events set old_date=null','permission denied for table debt_due_events');
  perform pg_temp.due_assert_fail('select private.debt_due_rows_v1(''d1222222-2222-4222-8222-222222222222'',now())','permission denied for function debt_due_rows_v1');
end;
$rls$;
reset role;
do $expired$
declare v_id uuid; p jsonb; k uuid:=gen_random_uuid(); r jsonb;
begin
  select source_id into v_id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' limit 1;
  p:=pg_temp.due_payload('standalone',v_id,'2024-01-01');r:=public.post_debt_due_v1(k,p);
  update public.shop_entitlements set expires_at=now()-interval '1 second' where shop_id='d1222222-2222-4222-8222-222222222222';
  if public.post_debt_due_v1(k,p)->>'replayed'<>'true' or public.get_debt_due_status_v1(k,p)->>'status'<>'completed' or public.get_debt_due_v1('standalone',v_id)->>'can_schedule'<>'false' then raise exception 'expired_read_replay';end if;
  perform pg_temp.due_assert_fail(format('select public.post_debt_due_v1(%L,%L::jsonb)',gen_random_uuid(),pg_temp.due_payload('standalone',v_id,null)),'shop_not_active');
end;
$expired$;
select set_config('request.jwt.claim.sub','d2111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
do $cross$ begin
  if exists(select 1 from public.debt_due_dates) or exists(select 1 from public.debt_due_events) or exists(select 1 from public.debt_due_requests) then raise exception 'cross_shop_due';end if;
end; $cross$;
reset role;
do $denied$
declare u text;
begin
  foreach u in array array['d3111111-1111-4111-8111-111111111111','d4111111-1111-4111-8111-111111111111','d5111111-1111-4111-8111-111111111111'] loop
    perform set_config('request.jwt.claim.sub',u,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',u='d4111111-1111-4111-8111-111111111111')::text,true);
    begin perform public.get_debt_reminders_v1();raise exception 'unauthorized_due';exception when others then if sqlerrm not in ('forbidden','unauthenticated') then raise;end if;end;
  end loop;
end;
$denied$;

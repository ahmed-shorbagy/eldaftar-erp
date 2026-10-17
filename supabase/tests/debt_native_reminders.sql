-- Supplemental to debts.sql inside its rollback-only synthetic transaction.
reset role;
select set_config('request.jwt.claim.sub','d1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
update public.shop_entitlements set expires_at=now()+interval '1 day' where shop_id='d1222222-2222-4222-8222-222222222222';
create function pg_temp.native_payload(k text,s uuid,t text) returns jsonb language sql as $f$
  select jsonb_build_object('version',1,'kind','debt_native','source_kind',k,'source_id',s,'reminder_time',t,
    'expected_native_version',j->>'native_version','expected_freshness',j->>'native_freshness')
    from (select public.get_debt_native_v1(k,s) j) r;
$f$;
create function pg_temp.native_date(k text,s uuid,d text) returns void language sql as $f$
  select public.post_debt_due_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','debt_due','source_kind',k,'source_id',s,'due_date',d,
    'expected_due_version',j->>'due_version','expected_freshness',j->>'freshness')) from (select public.get_debt_due_v1(k,s) j) r;
$f$;
create function pg_temp.native_assert_fail(q text,expected text) returns void language plpgsql as $f$
begin
  begin execute q; raise exception 'unexpected_success'; exception when others then
    if sqlerrm<>expected then raise exception 'expected %, got %',expected,sqlerrm; end if;
  end;
end;
$f$;
create function pg_temp.native_fail() returns trigger language plpgsql as $f$ begin raise exception 'native_test_failure';end;$f$;

do $native$
declare id uuid; kind text; direction text; k integer; payload jsonb; receipt jsonb; key uuid; old jsonb;
  before_hash text; after_hash text; list jsonb; cursor text; seen text[]:=array[]::text[]; row jsonb; rev bigint; n bigint;
begin
  for direction in select unnest(array['shop_owes','owed_to_shop']) loop
    foreach k in array array[0,14,18,21,22,24] loop
      receipt:=public.post_debt_declare_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','debt_declare','direction',direction,
        'unit',case when k=0 then 'money' else 'gold' end,'karat',case when k=0 then null else k end,'amount','10005',
        'party_name','تذكير اختبار '||direction||k,'contact_phone','','reason','اختبار تذكير','external_reference',null));
      id:=(receipt->>'source_id')::uuid;
      perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',gen_random_uuid(),pg_temp.native_payload('standalone',id,'16:00')),'due_date_required');
      perform pg_temp.native_date('standalone',id,'2026-10-14');
    end loop;
  end loop;
  -- All authoritative source types participate without importing their balances.
  for kind,id in select source_kind,source_id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' and remaining_amount>0 loop
    perform pg_temp.native_date(kind,id,'2026-10-14');
  end loop;
  select md5(string_agg(r::text,'' order by r::text)) into before_hash from (
    select to_jsonb(t) r from public.financial_operations t union all select to_jsonb(t) from public.financial_operation_details t
    union all select to_jsonb(t) from public.financial_audit_events t union all select to_jsonb(t) from public.journal_postings t
    union all select to_jsonb(t) from public.business_days t union all select to_jsonb(t) from public.shop_debts t
    union all select to_jsonb(t) from public.debt_events t union all select to_jsonb(t) from public.debt_command_requests t
    union all select to_jsonb(t) from public.purchase_cash_payables t union all select to_jsonb(t) from public.gold_obligations t
    union all select to_jsonb(t) from public.inventory_lots t union all select to_jsonb(t) from public.inventory_receipts t
    union all select to_jsonb(t) from public.customers t union all select to_jsonb(t) from public.customer_number_declarations t
    union all select to_jsonb(t) from public.invoice_dispatch_confirmations t union all select to_jsonb(t) from public.debt_due_dates t
    union all select to_jsonb(t) from public.debt_due_events t union all select to_jsonb(t) from public.debt_due_requests t
  ) h;
  for kind,id in select source_kind,source_id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' and remaining_amount>0 loop
    old:=public.get_debt_due_v1(kind,id)-'snapshot_at'-'snapshot_at_shop';
    if public.review_debt_native_v1(kind,id,'16:00')->>'proposed_trigger_at'<>'2026-10-14T13:00:00.000000Z' then raise exception 'cairo_utc_review';end if;
    payload:=pg_temp.native_payload(kind,id,'16:00');key:=gen_random_uuid();
    select debt_revision into rev from public.shop_sync_signals where shop_id='d1222222-2222-4222-8222-222222222222';
    receipt:=public.post_debt_native_v1(key,payload);
    if receipt->>'native_version'<>'1' or receipt->>'cash_piastres'<>'0' or receipt->>'gold_milligrams'<>'0'
      or receipt->>'stock_milligrams'<>'0' or receipt->>'custody_milligrams'<>'0' or receipt->>'invoice_effect'<>'false'
      or receipt->>'actor_user_id'<>auth.uid()::text or (select debt_revision from public.shop_sync_signals where shop_id='d1222222-2222-4222-8222-222222222222')<>rev+1 then raise exception 'native_atomic_receipt';end if;
    if public.post_debt_native_v1(key,payload)->>'replayed'<>'true' or public.get_debt_native_status_v1(key,payload)->'result' is distinct from receipt then raise exception 'native_replay';end if;
    perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',key,payload||'{"reminder_time":"17:00"}'),'payload_mismatch');
    perform pg_temp.native_assert_fail(format('select public.get_debt_native_status_v1(%L,%L::jsonb)',key,payload||'{"reminder_time":null}'),'payload_mismatch');
    perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',gen_random_uuid(),payload),'stale_native');
    perform public.post_debt_native_v1(gen_random_uuid(),pg_temp.native_payload(kind,id,null));
    if public.get_debt_native_v1(kind,id)->>'reminder_time' is not null then raise exception 'native_clear';end if;
    perform public.post_debt_native_v1(gen_random_uuid(),pg_temp.native_payload(kind,id,'00:00'));
    if public.get_debt_due_v1(kind,id)-'snapshot_at'-'snapshot_at_shop' is distinct from old then raise exception 'old_due_contract_changed';end if;
  end loop;
  select md5(string_agg(r::text,'' order by r::text)) into after_hash from (
    select to_jsonb(t) r from public.financial_operations t union all select to_jsonb(t) from public.financial_operation_details t
    union all select to_jsonb(t) from public.financial_audit_events t union all select to_jsonb(t) from public.journal_postings t
    union all select to_jsonb(t) from public.business_days t union all select to_jsonb(t) from public.shop_debts t
    union all select to_jsonb(t) from public.debt_events t union all select to_jsonb(t) from public.debt_command_requests t
    union all select to_jsonb(t) from public.purchase_cash_payables t union all select to_jsonb(t) from public.gold_obligations t
    union all select to_jsonb(t) from public.inventory_lots t union all select to_jsonb(t) from public.inventory_receipts t
    union all select to_jsonb(t) from public.customers t union all select to_jsonb(t) from public.customer_number_declarations t
    union all select to_jsonb(t) from public.invoice_dispatch_confirmations t union all select to_jsonb(t) from public.debt_due_dates t
    union all select to_jsonb(t) from public.debt_due_events t union all select to_jsonb(t) from public.debt_due_requests t
  ) h;
  if before_hash is distinct from after_hash then raise exception 'native_financial_or_date_effect';end if;
  loop
    list:=public.get_debt_native_queue_v1(3,cursor);
    for row in select * from jsonb_array_elements(list->'items') loop
      if (row->>'source_kind')||':'||(row->>'source_id')=any(seen) then raise exception 'native_duplicate_page';end if;
      seen:=array_append(seen,(row->>'source_kind')||':'||(row->>'source_id'));
      if row ?| array['party_name','contact_phone','remaining_amount','unit','karat','due_date'] then raise exception 'scheduler_private_data';end if;
    end loop;
    cursor:=list->>'next_cursor';exit when cursor is null;
  end loop;
  if array_length(seen,1)<>(list->>'total')::integer or array_length(seen,1)<12 then raise exception 'native_truncated_page';end if;
  list:=public.get_debt_native_queue_v1(1,null);cursor:=list->>'next_cursor';
  row:=list->'items'->0;kind:=row->>'source_kind';id:=(row->>'source_id')::uuid;
  payload:=pg_temp.native_payload(kind,id,'17:00');
  perform pg_temp.native_date(kind,id,'2026-10-15');
  perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',gen_random_uuid(),payload),'stale_native');
  perform pg_temp.native_assert_fail(format('select public.get_debt_native_queue_v1(1,%L)',cursor),'stale_native_cursor');
  payload:=pg_temp.native_payload(kind,id,'17:00');
  update public.shops s set time_zone='America/New_York' where s.id='d1222222-2222-4222-8222-222222222222';
  perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',gen_random_uuid(),payload),'stale_native');
  update public.shops s set time_zone='Africa/Cairo' where s.id='d1222222-2222-4222-8222-222222222222';
  -- Immutable audit/request rollback even after all state + sync effects.
  old:=public.get_debt_native_v1(kind,id)-'snapshot_at';payload:=pg_temp.native_payload(kind,id,'17:00');
  select count(*) into n from public.debt_native_events;
  create trigger native_test_failure after insert on public.debt_native_requests for each row execute function pg_temp.native_fail();
  perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',gen_random_uuid(),payload),'native_test_failure');
  drop trigger native_test_failure on public.debt_native_requests;
  if public.get_debt_native_v1(kind,id)-'snapshot_at' is distinct from old or (select count(*) from public.debt_native_events)<>n then raise exception 'native_partial_commit';end if;
  perform pg_temp.native_assert_fail('update public.debt_native_events set old_time=null','audit_append_only');
end;
$native$;

do $dst$
begin
  if private.debt_native_instant_v1('2026-10-14','00:00','Africa/Cairo')<>'2026-10-13T21:00:00Z'::timestamptz
    or private.debt_native_instant_v1('2026-01-01','00:00','Africa/Cairo')<>'2025-12-31T22:00:00Z'::timestamptz then raise exception 'utc_midnight';end if;
  perform pg_temp.native_assert_fail('select private.debt_native_instant_v1(''2026-03-08'',''02:30'',''America/New_York'')','unresolved_wall_time');
  perform pg_temp.native_assert_fail('select private.debt_native_instant_v1(''2026-11-01'',''01:30'',''America/New_York'')','unresolved_wall_time');
  perform pg_temp.native_assert_fail('select private.debt_native_instant_v1(''2026-04-24'',''00:30'',''Africa/Cairo'')','unresolved_wall_time');
  perform pg_temp.native_assert_fail('select private.debt_native_instant_v1(''2026-10-29'',''23:30'',''Africa/Cairo'')','unresolved_wall_time');
end;$dst$;
set local role authenticated;
do $rls$
begin
  if not exists(select 1 from public.debt_native_intents) then raise exception 'native_owner_read';end if;
  perform pg_temp.native_assert_fail('update public.debt_native_intents set reminder_time=null','permission denied for table debt_native_intents');
  perform pg_temp.native_assert_fail('delete from public.debt_native_events','permission denied for table debt_native_events');
  perform pg_temp.native_assert_fail('update public.debt_native_requests set result=''{}''','permission denied for table debt_native_requests');
  perform pg_temp.native_assert_fail('select private.debt_native_rows_v1(''d1222222-2222-4222-8222-222222222222'',now())','permission denied for function debt_native_rows_v1');
end;$rls$;
reset role;
do $expired$
declare id uuid;kind text;p jsonb;k uuid:=gen_random_uuid();
begin
  select source_kind,source_id into kind,id from private.debt_balances('d1222222-2222-4222-8222-222222222222') where display_status='open' limit 1;
  p:=pg_temp.native_payload(kind,id,'17:00');perform public.post_debt_native_v1(k,p);
  update public.shop_entitlements set expires_at=now()-interval '1 second' where shop_id='d1222222-2222-4222-8222-222222222222';
  if public.post_debt_native_v1(k,p)->>'replayed'<>'true' or public.get_debt_native_status_v1(k,p)->>'status'<>'completed'
    or public.get_debt_native_v1(kind,id)->>'can_write'<>'false' or (public.get_debt_native_queue_v1()->>'total')::integer<1 then raise exception 'native_expired_read_replay';end if;
  perform pg_temp.native_assert_fail(format('select public.post_debt_native_v1(%L,%L::jsonb)',gen_random_uuid(),pg_temp.native_payload(kind,id,null)),'shop_not_active');
end;$expired$;
select set_config('request.jwt.claim.sub','d2111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"d2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}',true);
set local role authenticated;
do $cross$ begin
  if exists(select 1 from public.debt_native_intents) or exists(select 1 from public.debt_native_events) or exists(select 1 from public.debt_native_requests)
    or public.get_debt_native_queue_v1()->>'total'<>'0' then raise exception 'cross_shop_native';end if;
end;$cross$;
reset role;
do $denied$
declare u text;
begin
  foreach u in array array['d3111111-1111-4111-8111-111111111111','d4111111-1111-4111-8111-111111111111','d5111111-1111-4111-8111-111111111111'] loop
    perform set_config('request.jwt.claim.sub',u,true);perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated','is_anonymous',u='d4111111-1111-4111-8111-111111111111')::text,true);
    begin perform public.get_debt_native_queue_v1();raise exception 'unauthorized_native';exception when others then if sqlerrm not in ('forbidden','unauthenticated') then raise;end if;end;
  end loop;
end;$denied$;

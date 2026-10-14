-- CRM-01 / CRM-03. Synthetic rows roll back. Customer commands must not post
-- cash, stock, debt, or business-day changes, and must not rewrite invoices.
begin;

create function pg_temp.customer_fail_after_write() returns trigger
language plpgsql as $failure$
begin
  if current_setting('eldafttar.customer_fail_after_write', true) = '1' then
    raise exception 'customer_test_failure';
  end if;
  return new;
end;
$failure$;
create trigger customer_test_failure after insert on public.customer_command_requests
for each row execute function pg_temp.customer_fail_after_write();

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, deleted_at, created_at, updated_at
) values
  ('c1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-owner@example.test', false, null, now(), now()),
  ('c2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-other@example.test', false, null, now(), now()),
  ('c3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-revoked@example.test', false, null, now(), now()),
  ('c4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-anon@example.test', true, null, now(), now()),
  ('c5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-admin@example.test', false, null, now(), now()),
  ('c6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-pending@example.test', false, null, now(), now()),
  ('c7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-expired@example.test', false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('c1222222-2222-4222-8222-222222222222', 'متجر العملاء', 'مالك العملاء', 'Africa/Cairo'),
  ('c2222222-2222-4222-8222-222222222222', 'متجر عملاء آخر', 'مالك آخر', 'Africa/Cairo'),
  ('c3222222-2222-4222-8222-222222222222', 'متجر عملاء موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('c4222222-2222-4222-8222-222222222222', 'متجر عملاء مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('c6222222-2222-4222-8222-222222222222', 'متجر عملاء معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('c7222222-2222-4222-8222-222222222222', 'متجر عملاء منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('c1222222-2222-4222-8222-222222222222', 'c1111111-1111-4111-8111-111111111111', 'owner', null),
  ('c2222222-2222-4222-8222-222222222222', 'c2111111-1111-4111-8111-111111111111', 'owner', null),
  ('c3222222-2222-4222-8222-222222222222', 'c3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('c4222222-2222-4222-8222-222222222222', 'c4111111-1111-4111-8111-111111111111', 'owner', null),
  ('c6222222-2222-4222-8222-222222222222', 'c6111111-1111-4111-8111-111111111111', 'owner', null),
  ('c7222222-2222-4222-8222-222222222222', 'c7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('c1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c4222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c7222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

insert into public.platform_admins (user_id)
values ('c5111111-1111-4111-8111-111111111111');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('c1818181-8181-4181-8181-818181818181', 'c1111111-1111-4111-8111-111111111111', now(), now(), now() + interval '1 day'),
  ('c1818181-8181-4181-8181-818181818182', 'c1111111-1111-4111-8111-111111111111', now(), now(), now() - interval '1 minute');

create function pg_temp.crm_entitlement(p_expired boolean) returns void language sql security definer set search_path='' as $f$
 update public.shop_entitlements set expires_at=case when p_expired then now()-interval '1 minute' else now()+interval '30 days' end where shop_id='c1222222-2222-4222-8222-222222222222';
$f$;
create temp table customer_ops (
  name text primary key,
  operation_id uuid,
  payload jsonb
);

grant select, insert on customer_ops to authenticated;

create function pg_temp.expect_code(p_sql text, p_code text)
returns void language plpgsql security invoker set search_path = '' as $fn$
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

create function pg_temp.create_payload(
  p_name text, p_phones jsonb, p_vip boolean, p_open boolean
) returns jsonb language sql immutable as $fn$
  select pg_catalog.jsonb_build_object(
    'version', 1, 'kind', 'customer_create', 'display_name', p_name,
    'phones', p_phones, 'is_vip', p_vip, 'has_open_request', p_open
  );
$fn$;

create function pg_temp.phone(p_number text, p_primary boolean)
returns jsonb language sql immutable as $fn$
  select pg_catalog.jsonb_build_object('number', p_number, 'is_primary', p_primary);
$fn$;


create function pg_temp.saved_snapshot() returns jsonb language plpgsql security definer set search_path='' as $f$
declare t text; result jsonb:='{}'; value text;
begin
 foreach t in array array['financial_operations','financial_audit_events','journals','journal_postings','inventory_lots','inventory_lot_movements','inventory_receipts','repairs','repair_events','shop_debts','debt_events','purchase_cash_payables','gold_obligations','financial_operation_details','invoice_dispatch_confirmations','business_days','customer_notes','customer_operation_links'] loop
 execute format('select md5(coalesce(string_agg(to_jsonb(r)::text,E''\n'' order by to_jsonb(r)::text),'''')) from public.%I r',t) into value;
 result:=result||jsonb_build_object(t,value);
 end loop; return result;
end;$f$;
create temp table crm05_baseline as select pg_temp.saved_snapshot() digest;
grant select on crm05_baseline to authenticated;
create function pg_temp.assert_true(p_value boolean,p_label text) returns void language plpgsql as $f$
begin if p_value is distinct from true then raise exception 'crm05_%',p_label; end if;end;$f$;
create function pg_temp.saved_payload(p_customer uuid,p_version text,p_number uuid,p_norm text,p_state text) returns jsonb language sql as $f$
select jsonb_build_object('version',1,'kind','customer_saved_number','customer_id',p_customer,'expected_version',p_version,'number_id',p_number,'normalized_number',p_norm,'state',p_state);$f$;
set local role authenticated;
select set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false,"session_id":"c1818181-8181-4181-8181-818181818181"}',true);
do $test$
declare c uuid; empty_c uuid; number_id uuid; other_number uuid; old_id uuid; phone_row uuid;
 r jsonb; read3 jsonb; payload jsonb; original_receipt jsonb; v text; key uuid; create_key uuid; count_before bigint; sync_before jsonb;
begin
 create_key:=gen_random_uuid();
 r:=public.post_customer_create_v1(create_key,pg_temp.create_payload('عميل إقرار','[{"number":"٠١٠١١١١١١١١","is_primary":true},{"number":"+33123456789","is_primary":false}]',false,false));
 c:=(r->>'customer_id')::uuid; original_receipt:=r;
 empty_c:=(public.post_customer_create_v1(gen_random_uuid(),pg_temp.create_payload('عميل بدون هاتف','[]',false,false))->>'customer_id')::uuid;
 read3:=public.get_customer_v3(c,20,null,20,null,20,null);
 number_id:=(read3#>>'{phones,0,saved_number,number_id}')::uuid;
 other_number:=(read3#>>'{phones,1,saved_number,number_id}')::uuid;
 phone_row:=(read3#>>'{phones,0,phone_id}')::uuid;
 perform pg_temp.assert_true(read3#>>'{phones,0,saved_number,state}'='unknown' and read3#>>'{phones,0,saved_number,actor_user_id}' is null,'initial_unknown');
 perform pg_temp.assert_true(jsonb_array_length(public.get_customer_v3(empty_c,20,null,20,null,20,null)->'phones')=0,'optional_phone');
 sync_before:=(select to_jsonb(s) from public.shop_sync_signals s where s.shop_id='c1222222-2222-4222-8222-222222222222');
 payload:=pg_temp.saved_payload(c,'1',number_id,'+201011111111','saved'); key:=gen_random_uuid();
 r:=public.post_customer_saved_number_v1(key,payload);
 perform pg_temp.assert_true(r#>>'{phones,0,saved_number,state}'='saved' and r#>>'{phones,0,saved_number,actor_user_id}'='c1111111-1111-4111-8111-111111111111' and r#>>'{phones,0,saved_number,declared_at}'=r->>'updated_at','saved_provenance');
 perform pg_temp.assert_true(r->>'declaration_event_id' is not null and (select count(*)=1 from public.customer_number_events where customer_id=c),'single_audit');
 perform pg_temp.assert_true((select (s.ledger_revision::text=sync_before->>'ledger_revision') and (s.customer_revision>(sync_before->>'customer_revision')::bigint) from public.shop_sync_signals s where s.shop_id='c1222222-2222-4222-8222-222222222222'),'customer_only_sync');
 perform pg_temp.assert_true(public.post_customer_saved_number_v1(key,payload)=r||'{"replayed":true}'::jsonb,'exact_replay');
 perform pg_temp.assert_true(public.get_customer_command_status_v2(key,'customer_saved_number',c,payload)->'result'=r,'exact_status');
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(%L::uuid,%L::jsonb)',key,payload||'{"state":"not_saved"}'),'payload_mismatch');
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',payload),'stale_customer');
 perform pg_temp.assert_true(not (public.get_customer_v2(c,20,null,20,null,20,null)#>'{phones,0}' ? 'saved_number'),'v2_unchanged');
 perform pg_temp.assert_true(not exists(select 1 from jsonb_array_elements(public.get_customer_v2(c,20,null,20,null,20,null)#>'{history,items}') e where e->>'event_type'='saved_number_changed'),'v2_history_unchanged');
 perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.get_customer_v3(c,20,null,20,null,20,null)#>'{history,items}') e where e->>'event_type'='saved_number_changed'),'v3_audit');
 -- Old-client name, raw-format and primary edit preserves both active incarnations.
 r:=public.post_customer_edit_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_edit','customer_id',c,'expected_version','2','display_name','عميل باسم جديد','phones','[{"number":"00201011111111","is_primary":false},{"number":"+33 123456789","is_primary":true}]'::jsonb));
 read3:=public.get_customer_v3(c,20,null,20,null,20,null);
 perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(read3->'phones') p where p->>'normalized'='+201011111111' and p#>>'{saved_number,number_id}'=number_id::text and p#>>'{saved_number,state}'='saved' and (p->>'phone_id')::uuid<>phone_row),'old_edit_retains');
 perform pg_temp.assert_true(read3#>>'{phones,0,saved_number,number_id}'=other_number::text and read3#>>'{phones,0,saved_number,state}'='unknown','primary_badge_identity');
 perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(public.get_customer_list_v3('+33123456789','name','all',1,null)->'items') item where item->>'customer_id'=c::text and item#>>'{phones,0,saved_number,number_id}'=other_number::text),'search_primary_status');
 payload:=pg_temp.saved_payload(c,'3',number_id,'+201011111111','not_saved');
 r:=public.post_customer_saved_number_v1(gen_random_uuid(),payload);
 perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(r->'phones') p where p#>>'{saved_number,state}'='not_saved'),'not_saved_distinct');
 payload:=pg_temp.saved_payload(c,'4',number_id,'+201011111111','unknown');
 r:=public.post_customer_saved_number_v1(gen_random_uuid(),payload);
 perform pg_temp.assert_true(exists(select 1 from jsonb_array_elements(r->'phones') p where p#>>'{saved_number,number_id}'=number_id::text and p#>>'{saved_number,state}'='unknown' and p#>>'{saved_number,actor_user_id}' is not null),'clear_audited');
 r:=public.post_customer_archive_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_archive','customer_id',c,'expected_version','5'));
 r:=public.post_customer_saved_number_v1(gen_random_uuid(),pg_temp.saved_payload(c,'6',number_id,'+201011111111','saved'));
 r:=public.post_customer_restore_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_restore','customer_id',c,'expected_version','7'));
 perform pg_temp.assert_true(public.get_customer_v3(c,20,null,20,null,20,null)#>>'{phones,1,saved_number,state}'='saved','archive_restore');
 -- Removal retains the audit and permanently retires this incarnation.
 r:=public.post_customer_edit_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_edit','customer_id',c,'expected_version','8','display_name','عميل جديد','phones','[]'::jsonb));
 perform pg_temp.assert_true((select retired_at is not null and state='saved' from public.customer_number_declarations where id=number_id),'retired_preserved');
 perform pg_temp.assert_true((select count(*)=4 from public.customer_number_events e where e.customer_id=c),'retired_audit');
 -- The same normalized number assigned to a different customer is unknown.
 r:=public.post_customer_edit_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_edit','customer_id',empty_c,'expected_version','1','display_name','عميل آخر','phones','[{"number":"01011111111","is_primary":true}]'::jsonb));
 read3:=public.get_customer_v3(empty_c,20,null,20,null,20,null);
 perform pg_temp.assert_true(read3#>>'{phones,0,saved_number,state}'='unknown' and read3#>>'{phones,0,saved_number,number_id}'<>number_id::text,'cross_customer_no_transfer');
 r:=public.post_customer_edit_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_edit','customer_id',empty_c,'expected_version','2','display_name','عميل آخر','phones','[{"number":"+441234567890","is_primary":true}]'::jsonb));
 perform pg_temp.assert_true(public.get_customer_v3(empty_c,20,null,20,null,20,null)#>>'{phones,0,saved_number,state}'='unknown','replacement_unknown');
 r:=public.post_customer_edit_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_edit','customer_id',c,'expected_version','9','display_name','عميل جديد','phones','[{"number":"01011111111","is_primary":true}]'::jsonb));
 read3:=public.get_customer_v3(c,20,null,20,null,20,null);
 old_id:=number_id;number_id:=(read3#>>'{phones,0,saved_number,number_id}')::uuid;
 perform pg_temp.assert_true(number_id<>old_id and read3#>>'{phones,0,saved_number,state}'='unknown','readd_new_unknown');
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',pg_temp.saved_payload(c,'10',old_id,'+201011111111','saved')),'stale_number');
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',pg_temp.saved_payload(empty_c,'3',number_id,'+201011111111','saved')),'stale_number');
 -- Failure after every write must undo declaration, version, audit, sync and request.
 count_before:=(select count(*) from public.customer_number_events);
 perform set_config('eldafttar.customer_fail_after_write','1',true);
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',pg_temp.saved_payload(c,'10',number_id,'+201011111111','saved')),'customer_test_failure');
 perform set_config('eldafttar.customer_fail_after_write','0',true);
 perform pg_temp.assert_true((select count(*)=count_before from public.customer_number_events) and public.get_customer_v3(c,20,null,20,null,20,null)->>'record_version'='10' and public.get_customer_v3(c,20,null,20,null,20,null)#>>'{phones,0,saved_number,state}'='unknown','atomic_failure');
 perform pg_temp.crm_entitlement(true);
 perform pg_temp.assert_true(public.get_customer_v3(c,20,null,20,null,20,null)->>'customer_id'=c::text,'expired_read');
 perform pg_temp.assert_true(public.get_customer_command_status_v2(key,'customer_saved_number',c,pg_temp.saved_payload(c,'1',old_id,'+201011111111','saved'))->'result'->>'ok'='true','expired_reconcile');
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',pg_temp.saved_payload(c,'10',number_id,'+201011111111','saved')),'shop_not_active');
 perform pg_temp.crm_entitlement(false);
 perform pg_temp.assert_true(public.get_customer_command_status_v1(create_key,'customer_create',null,pg_temp.create_payload('عميل إقرار','[{"number":"٠١٠١١١١١١١١","is_primary":true},{"number":"+33123456789","is_primary":false}]',false,false))->'result'=original_receipt,'frozen_v1_receipt');
 insert into customer_ops(name,operation_id,payload) values('saved',c,pg_temp.saved_payload(c,'10',number_id,'+201011111111','saved'));
 perform pg_temp.assert_true(pg_temp.saved_snapshot()=(select digest from crm05_baseline),'financial_history_preserved');
end;$test$;
-- Direct writes have no privileges; private helpers are not callable.
do $acl$ begin
 perform pg_temp.assert_true(not has_table_privilege('authenticated','public.customer_number_declarations','INSERT,UPDATE,DELETE') and not has_table_privilege('authenticated','public.customer_number_events','INSERT,UPDATE,DELETE'),'direct_writes_denied');
 perform pg_temp.assert_true(not has_function_privilege('authenticated','private.customer_saved_number(uuid,jsonb)','EXECUTE'),'private_denied');
end;$acl$;
reset role;
do $append$ begin
 perform pg_temp.expect_code('delete from public.customer_number_events','audit_append_only');
 perform pg_temp.expect_code('update public.customer_number_events set actor_display_name=''مزور''','audit_append_only');
end;$append$;
set local role authenticated;
select set_config('request.jwt.claims','{"role":"authenticated","is_anonymous":false}',true);
select set_config('request.jwt.claim.sub','c2111111-1111-4111-8111-111111111111',true);
do $other$ begin
 perform pg_temp.assert_true((select count(*)=0 from public.customer_number_declarations),'cross_shop_rls');
 perform pg_temp.assert_true(jsonb_array_length(public.get_customer_list_v3('','name','all',20,null)->'items')=0,'cross_shop_list');
 perform pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',(select payload from customer_ops where name='saved')),'not_found');
 perform pg_temp.assert_true(public.get_customer_command_status_v2(gen_random_uuid(),'customer_saved_number',(select operation_id from customer_ops where name='saved'),(select payload from customer_ops where name='saved'))->>'status'='absent','foreign_status_no_leak');
end;$other$;
select set_config('request.jwt.claim.sub','c3111111-1111-4111-8111-111111111111',true);
select pg_temp.expect_code($$select public.get_customer_list_v3('','name','all',20,null)$$,'forbidden');
select pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',(select payload from customer_ops where name='saved')),'forbidden');
select set_config('request.jwt.claim.sub','c5111111-1111-4111-8111-111111111111',true);
select pg_temp.expect_code($$select public.get_customer_list_v3('','name','all',20,null)$$,'forbidden');
select pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',(select payload from customer_ops where name='saved')),'forbidden');
select set_config('request.jwt.claim.sub','c4111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"role":"authenticated","is_anonymous":true}',true);
select pg_temp.expect_code($$select public.get_customer_list_v3('','name','all',20,null)$$,'forbidden');
select set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"role":"authenticated","is_anonymous":false,"session_id":"c1818181-8181-4181-8181-818181818182"}',true);
select pg_temp.expect_code($$select public.get_customer_list_v3('','name','all',20,null)$$,'session_expired');
select pg_temp.expect_code(format('select public.post_customer_saved_number_v1(gen_random_uuid(),%L::jsonb)',(select payload from customer_ops where name='saved')),'session_expired');
set local role anon;
select pg_temp.expect_code($$select public.get_customer_list_v3('','name','all',20,null)$$,'permission denied for function get_customer_list_v3');
select pg_temp.expect_code($$select public.post_customer_saved_number_v1(gen_random_uuid(),'{}'::jsonb)$$,'permission denied for function post_customer_saved_number_v1');
rollback;

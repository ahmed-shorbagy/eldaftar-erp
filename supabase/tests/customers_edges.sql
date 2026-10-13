-- Independent Codex CRM regressions. Every synthetic row and fault trigger rolls back.
begin;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,deleted_at,created_at,updated_at)
values('c8111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','customer-edges@example.test',false,null,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone)
values('c8222222-2222-4222-8222-222222222222','محل تحقق العملاء الاصطناعي','مالك تحقق اصطناعي','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role)
values('c8222222-2222-4222-8222-222222222222','c8111111-1111-4111-8111-111111111111','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
values('c8222222-2222-4222-8222-222222222222',now()-interval '1 day',now()+interval '1 day');
insert into auth.sessions(id,user_id,created_at,updated_at,not_after)
values('c8888888-8888-4888-8888-888888888888','c8111111-1111-4111-8111-111111111111',now(),now(),now()+interval '1 day');
create function pg_temp.crm_fault() returns trigger language plpgsql as $f$
begin
 if current_setting('eldafttar.crm_review_fault',true)='1' then raise exception 'crm_review_fault'; end if;
 return new;
end;$f$;
create trigger crm_review_fault after insert on public.customer_command_requests for each row execute function pg_temp.crm_fault();
create function pg_temp.crm_state(p_shop uuid) returns jsonb language sql security invoker as $f$
select jsonb_build_object(
 'customers',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.customers t where shop_id=p_shop),
 'phones',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.customer_phones t where shop_id=p_shop),
 'notes',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.customer_notes t where shop_id=p_shop),
 'events',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.customer_events t where shop_id=p_shop),
 'links',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.customer_operation_links t where shop_id=p_shop),
 'requests',(select coalesce(jsonb_agg(to_jsonb(t) order by idempotency_key),'[]') from public.customer_command_requests t where shop_id=p_shop),
 'sync',(select to_jsonb(t) from public.shop_sync_signals t where shop_id=p_shop),
 'operations',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.financial_operations t where shop_id=p_shop),
 'details',(select coalesce(jsonb_agg(to_jsonb(t) order by operation_id),'[]') from public.financial_operation_details t where shop_id=p_shop),
 'postings',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.journal_postings t where shop_id=p_shop),
 'day',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from public.business_days t where shop_id=p_shop)
);$f$;
create function pg_temp.expect_error(p_sql text,p_error text) returns void language plpgsql as $f$
begin
 begin execute p_sql; exception when others then
  if sqlerrm=p_error then return; end if;
  raise exception 'expected %, got %',p_error,sqlerrm;
 end;
 raise exception 'expected %, call succeeded',p_error;
end;$f$;
set local role authenticated;
select set_config('request.jwt.claim.sub','c8111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"c8111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"c8888888-8888-4888-8888-888888888888","is_anonymous":false}',true);
do $checks$
declare
 shop uuid:='c8222222-2222-4222-8222-222222222222';
 customer jsonb; second jsonb; purchase jsonb; payload jsonb; old_state jsonb; kind text;
 id uuid; other uuid; operation uuid; cursor_value text;
begin
 perform public.confirm_opening_balances(gen_random_uuid(),'{"version":1,"cash":{"cash":"50000"},"stock":[],"scrap":[]}'::jsonb);
 purchase:=public.post_daily_ledger_trade(gen_random_uuid(),'{"version":1,"kind":"purchase","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"scrap","karat":21,"milligrams":"1255","count":null,"item_name":"كسر اصطناعي","line_price_piastres":null}],"description":"","customer_name":"لقطة الطرف الاصطناعي","customer_phone":"","note":""}'::jsonb);
 operation:=(purchase->>'operation_id')::uuid;
 customer:=public.post_customer_create_v1(gen_random_uuid(),'{"version":1,"kind":"customer_create","display_name":"عميل تحقق أول","phones":[{"number":"01088888888","is_primary":true}],"is_vip":false,"has_open_request":false}');
 id:=(customer->>'customer_id')::uuid;
 second:=public.post_customer_create_v1(gen_random_uuid(),'{"version":1,"kind":"customer_create","display_name":"عميل تحقق ثان","phones":[],"is_vip":false,"has_open_request":false}');
 other:=(second->>'customer_id')::uuid;
 foreach kind in array array['customer_create','customer_edit','customer_note','customer_status','customer_link','customer_archive'] loop
  payload:=jsonb_build_object('version',1,'kind',kind,'customer_id',id,'expected_version',customer->>'record_version');
  case kind
  when 'customer_create' then payload:='{"version":1,"kind":"customer_create","display_name":"عميل فشل اصطناعي","phones":[{"number":"01077777777","is_primary":true}],"is_vip":false,"has_open_request":false}';
  when 'customer_edit' then payload:=payload||'{"display_name":"عميل بعد التعديل","phones":[{"number":"01066666666","is_primary":true}]}'::jsonb;
  when 'customer_note' then payload:=payload||jsonb_build_object('body',E'ملاحظة اصطناعية\nسطر ثان');
  when 'customer_status' then payload:=payload||'{"is_vip":true,"has_open_request":true}'::jsonb;
  when 'customer_link' then payload:=payload||jsonb_build_object('operation_id',operation);
  when 'customer_archive' then null;
  end case;
  old_state:=pg_temp.crm_state(shop);
  perform set_config('eldafttar.crm_review_fault','1',true);
  perform pg_temp.expect_error(format('select public.post_%s_v1(%L::uuid,%L::jsonb)',kind,gen_random_uuid(),payload),'crm_review_fault');
  perform set_config('eldafttar.crm_review_fault','0',true);
  if pg_temp.crm_state(shop) is distinct from old_state then raise exception 'partial rollback for %',kind; end if;
 end loop;
 customer:=public.post_customer_note_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_note','customer_id',id,'expected_version',customer->>'record_version','body',E'ملاحظة اصطناعية\nسطر ثان'));
 if public.get_customer_v1(id,20,null,20,null,20,null)->'notes'->'items'->0->>'body' is distinct from E'ملاحظة اصطناعية\nسطر ثان' then raise exception 'multiline note lost'; end if;
 customer:=public.post_customer_link_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_link','customer_id',id,'expected_version',customer->>'record_version','operation_id',operation));
 old_state:=pg_temp.crm_state(shop);
 perform set_config('eldafttar.crm_review_fault','1',true);
 perform pg_temp.expect_error(format('select public.post_customer_unlink_v1(%L::uuid,%L::jsonb)',gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_unlink','customer_id',id,'expected_version',customer->>'record_version','operation_id',operation)),'crm_review_fault');
 perform set_config('eldafttar.crm_review_fault','0',true);
 if pg_temp.crm_state(shop) is distinct from old_state then raise exception 'partial unlink rollback'; end if;
 customer:=public.post_customer_archive_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_archive','customer_id',id,'expected_version',customer->>'record_version'));
 old_state:=pg_temp.crm_state(shop);
 perform set_config('eldafttar.crm_review_fault','1',true);
 perform pg_temp.expect_error(format('select public.post_customer_restore_v1(%L::uuid,%L::jsonb)',gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_restore','customer_id',id,'expected_version',customer->>'record_version')),'crm_review_fault');
 perform set_config('eldafttar.crm_review_fault','0',true);
 if pg_temp.crm_state(shop) is distinct from old_state then raise exception 'partial restore rollback'; end if;
 -- Rejected cursors must not look like fresh first pages to an app appending older results.
 perform pg_temp.expect_error($sql$select public.get_customer_list_v1('','name','all',20,'bad')$sql$,'invalid_cursor');
 perform pg_temp.expect_error(format('select public.get_customer_v1(%L::uuid,20,%L,20,null,20,null)',id,'bad'),'invalid_cursor');
 perform pg_temp.expect_error($sql$select public.get_customer_link_candidates_v1('',20,'bad')$sql$,'invalid_cursor');
 cursor_value:=public.get_customer_list_v1('','name','all',1,null)->>'next_cursor';
 if cursor_value is null then raise exception 'pagination fixture has no cursor'; end if;
 perform pg_temp.expect_error(format('select public.get_customer_list_v1(%L,%L,%L,20,%L)','different','name','all',cursor_value),'invalid_cursor');
end;$checks$;
reset role;
-- Persisted event instants stay UTC. Display handles midnight, DST and changed shop zones.
do $dates$
begin
 if private.customer_utc('2026-10-13 21:30:00+00') <> '2026-10-13T21:30:00.000000Z'
  or private.customer_local('2026-10-13 21:30:00+00','Africa/Cairo') <> '2026-10-14T00:30:00'
  or private.customer_local('2026-10-13 21:30:00+00','Asia/Dubai') <> '2026-10-14T01:30:00'
  or private.customer_local('2026-01-13 21:30:00+00','Africa/Cairo') <> '2026-01-13T23:30:00' then raise exception 'CRM UTC/timezone/day-boundary mismatch'; end if;
end;$dates$;
rollback;

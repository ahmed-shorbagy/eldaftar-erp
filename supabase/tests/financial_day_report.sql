-- Synthetic report fixture; every mutation rolls back, including R2 metadata.
begin;
set local time zone 'UTC';
create function pg_temp.report_error(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlerrm; end; $$;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at) values
 ('b1111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','report-owner@example.test',false,now(),now()),
 ('b1111111-1111-4111-8111-111111111112','00000000-0000-0000-0000-000000000000','authenticated','authenticated','report-other@example.test',false,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone) values
 ('b2222222-2222-4222-8222-222222222222','متجر التقرير التجريبي','مالك تجريبي','Africa/Cairo'),
 ('b2222222-2222-4222-8222-222222222223','متجر آخر','مالك آخر','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values
 ('b2222222-2222-4222-8222-222222222222','b1111111-1111-4111-8111-111111111111','owner'),
 ('b2222222-2222-4222-8222-222222222223','b1111111-1111-4111-8111-111111111112','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at) values
 ('b2222222-2222-4222-8222-222222222222',now()-interval '1 day',now()+interval '30 days'),
 ('b2222222-2222-4222-8222-222222222223',now()-interval '1 day',now()+interval '30 days');
create temp table report_fixture(day_id uuid, report jsonb);
grant all on report_fixture to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
do $test$
declare
 d uuid; sale uuid; purchase uuid; review jsonb; report jsonb; again jsonb; snapshot text;
 s jsonb := '{"version":1,"kind":"sale","total_piastres":"10001","tenders":[{"method":"cash","piastres":"10001"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}';
 p jsonb := '{"version":1,"kind":"purchase","total_piastres":"50001","tenders":[{"method":"cash","piastres":"20001"}],"purchase_obligation_piastres":"30000","items":[{"category":"scrap","karat":14,"milligrams":"1230","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}';
begin
 if public.list_financial_report_days_v1()->'days' <> '[]'::jsonb then raise exception 'empty_days'; end if;
 perform public.confirm_opening_balances(gen_random_uuid(),'{"version":1,"cash":{"cash":"9007199254740993"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"20000","count":"10"}],"scrap":[]}');
 select id into d from public.business_days where shop_id='b2222222-2222-4222-8222-222222222222' and status='open';
 sale := (public.post_daily_ledger_trade(gen_random_uuid(),s)->>'operation_id')::uuid;
 purchase := (public.post_daily_ledger_trade(gen_random_uuid(),p)->>'operation_id')::uuid;
 perform public.post_daily_ledger_trade(gen_random_uuid(),'{"version":1,"kind":"expense","total_piastres":"123","tenders":[{"method":"cash","piastres":"123"}],"items":[],"description":"مصروف","customer_name":"طرف تجريبي","customer_phone":"","note":""}');
 report := public.get_financial_day_report_v1(d);
 if report#>>'{summary,sales}'<>'10001' or report#>>'{summary,purchases}'<>'50001'
   or report#>>'{summary,net_cash}'<>'-10123' or report#>>'{summary,opening_cash}'<>'9007199254740993'
   or report#>>'{summary,operation_count}'<>'3' or report#>>'{gold,0,bought}'<>'1230'
   or report#>>'{gold,2,sold}'<>'2000' then raise exception 'exact_initial_totals %',report->'summary'; end if;
 -- Delete sale: both original and reversal remain in cash ledger, neither contributes to trade metrics.
 review := public.review_ledger_trade_change_v1(sale,'delete',null);
 perform public.post_ledger_trade_change_v1(gen_random_uuid(),sale,'delete',null,
   (review->>'expected_day_id')::uuid,(review->>'expected_day_version')::bigint,review->>'source_sha256',review->>'review_token');
 report := public.get_financial_day_report_v1(d);
 if report#>>'{summary,sales}'<>'0' or report#>>'{summary,net_cash}'<>'-20124'
   or report#>>'{gold,2,sold}'<>'0' or report#>>'{summary,audit_row_count}'<>'5'
   or not exists(select 1 from jsonb_array_elements(report->'transactions') r where r->>'state'='delete')
   or not exists(select 1 from jsonb_array_elements(report->'transactions') r where r->>'state'='internal_reversal')
   then raise exception 'delete_report %',report->'summary'; end if;
 -- Edit partial purchase to unpaid 18k scrap. Cash must cancel only actual tender.
 p := p || '{"total_piastres":"60001","tenders":[],"purchase_obligation_piastres":"60001","items":[{"category":"scrap","karat":18,"milligrams":"2340","count":null,"item_name":"كسر جديد","line_price_piastres":null}]}'::jsonb;
 review := public.review_ledger_trade_change_v1(purchase,'edit',p);
 perform public.post_ledger_trade_change_v1(gen_random_uuid(),purchase,'edit',p,
   (review->>'expected_day_id')::uuid,(review->>'expected_day_version')::bigint,review->>'source_sha256',review->>'review_token');
 report := public.get_financial_day_report_v1(d);
 if report#>>'{summary,purchases}'<>'60001' or report#>>'{summary,net_cash}'<>'-123'
   or report#>>'{gold,0,bought}'<>'0' or report#>>'{gold,1,bought}'<>'2340'
   or report#>>'{summary,purchase_count}'<>'1' then raise exception 'edit_report %',report->'summary'; end if;
 again := public.get_financial_day_report_v1(d);
 if report->>'fingerprint'<>again->>'fingerprint' then raise exception 'unstable_fingerprint'; end if;
 if pg_temp.report_error(format('select public.confirm_financial_day_pdf_v1(%L,%L,%L)',d,report->>'fingerprint','report-pdf/missing'))<>'media_rejected' then raise exception 'unverified_pdf'; end if;
 if has_function_privilege('authenticated','public.record_report_pdf_object_v1(uuid,uuid,text,bigint,text)','execute')
   or has_function_privilege('anon','public.get_financial_day_report_v1(uuid)','execute') then raise exception 'report_grants'; end if;
 insert into report_fixture values(d,report);
end;
$test$;
reset role;
do $registry$
declare r jsonb; d uuid; key text := 'report-pdf/b2222222-2222-4222-8222-222222222222/'||repeat('a',64)||'.pdf';
begin
 r := public.record_report_pdf_object_v1('b1111111-1111-4111-8111-111111111111','b2222222-2222-4222-8222-222222222222',key,100,repeat('a',64));
 if r->>'replayed'<>'false' then raise exception 'first_pdf'; end if;
 r := public.record_report_pdf_object_v1('b1111111-1111-4111-8111-111111111111','b2222222-2222-4222-8222-222222222222',key,100,repeat('a',64));
 if r->>'replayed'<>'true' then raise exception 'pdf_retry'; end if;
end;
$registry$;
set local role authenticated;
do $confirm$
declare d uuid; r jsonb; key text := 'report-pdf/b2222222-2222-4222-8222-222222222222/'||repeat('a',64)||'.pdf';
begin
 select day_id,report into d,r from report_fixture;
 perform public.confirm_financial_day_pdf_v1(d,r->>'fingerprint',key);
 if pg_temp.report_error(format('select public.confirm_financial_day_pdf_v1(%L,%L,%L)',d,repeat('f',64),key))<>'stale_report' then raise exception 'stale_pdf'; end if;
 perform set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111112',true);
 if pg_temp.report_error(format('select public.get_financial_day_report_v1(%L)',d))<>'not_found' then raise exception 'cross_shop'; end if;
end;
$confirm$;
reset role;
-- Legacy return permission is restored only inside this rolled-back fixture.
grant execute on function public.post_linked_return_v1(uuid,jsonb) to authenticated;
alter table report_fixture add column sale_id uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
update report_fixture set sale_id=(public.post_daily_ledger_trade(gen_random_uuid(),
 '{"version":1,"kind":"sale","total_piastres":"10001","tenders":[{"method":"cash","piastres":"10001"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"2000","count":"2","item_name":"بيع تاريخي","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}')->>'operation_id')::uuid;
reset role;
update public.business_days set business_date=business_date-2,opened_at=opened_at-interval '2 days',status='closed',closed_at=now()-interval '1 day'
 where id=(select day_id from report_fixture);
insert into public.business_days(id,shop_id,business_date,opened_at,status,day_version)
 values('b3333333-3333-4333-8333-333333333335','b2222222-2222-4222-8222-222222222222',(now() at time zone 'Africa/Cairo')::date,now(),'open',1);
set local role authenticated;
do $historical$
declare r jsonb; old jsonb; src uuid; d uuid; i integer; p jsonb; key uuid := gen_random_uuid();
begin
 select day_id,sale_id into d,src from report_fixture;
 old:=public.get_financial_day_report_v1(d);
 if old->>'status'<>'closed' or old->>'date'=((now() at time zone 'Africa/Cairo')::date)::text then raise exception 'historical_day'; end if;
 p:=jsonb_build_object('version',1,'kind','sale_return','original_operation_id',src,
   'expected_day_id','b3333333-3333-4333-8333-333333333335','expected_day_version','1',
   'note','مرتجع في يوم لاحق','items',jsonb_build_array(jsonb_build_object('item_index','0','milligrams','1000','count','1')),
   'consideration_piastres','4001','tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres','4001')));
 perform public.post_linked_return_v1(key,p);
 if public.post_linked_return_v1(key,p)->>'replayed'<>'true' then raise exception 'return_replay'; end if;
 for i in 1..105 loop
   perform public.post_daily_ledger_trade(gen_random_uuid(),'{"version":1,"kind":"expense","total_piastres":"1","tenders":[{"method":"cash","piastres":"1"}],"items":[],"description":"مصروف تجريبي","customer_name":"","customer_phone":"","note":""}');
 end loop;
 r:=public.get_financial_day_report_v1('b3333333-3333-4333-8333-333333333335');
 if jsonb_array_length(r->'transactions')<>106 or r#>>'{summary,expense_count}'<>'105'
   or r#>>'{summary,sales}'<>'0' or r#>>'{summary,sale_returns}'<>'4001'
   or r#>>'{summary,net_sales}'<>'-4001' or r#>>'{summary,net_cash}'<>'-4106'
   or r#>>'{gold,2,sold}'<>'-1000' then raise exception 'historical_return_or_truncation %',r->'summary'; end if;
 -- Physical-count compensation changes actual cash/stock, never sales or purchases.
 select jsonb_build_object('version',1,'kind','ledger_correction',
   'expected_day_id','b3333333-3333-4333-8333-333333333335','expected_day_version',day_version::text,
   'reason','تسوية تجريبية','counted',jsonb_build_object(
     'cash',jsonb_build_object('cash',(select (amount+50)::text from public.ledger_account_balances
       where shop_id='b2222222-2222-4222-8222-222222222222' and account_kind='cash_method' and method_code='cash'),
       'instant_transfer','0','wallet','0','card','0'),
     'stock',jsonb_build_array(jsonb_build_object('category','worked_jewelry','karat',21,'milligrams','19000','count','9')),
     'scrap',(select jsonb_agg(jsonb_build_object('karat',karat,'milligrams',
       (amount+case when karat=18 then 123 else 0 end)::text) order by karat)
       from public.ledger_account_balances where shop_id='b2222222-2222-4222-8222-222222222222' and account_kind='scrap_metal')))
 into p from public.business_days where id='b3333333-3333-4333-8333-333333333335';
 perform public.post_ledger_correction_v1(gen_random_uuid(),p);
 r:=public.get_financial_day_report_v1('b3333333-3333-4333-8333-333333333335');
 if r#>>'{summary,net_cash}'<>'-4056' or r#>>'{summary,net_sales}'<>'-4001'
   or r#>>'{summary,purchases}'<>'0' or r#>>'{gold,1,bought}'<>'0'
   or not exists(select 1 from jsonb_array_elements(r->'transactions') t,
     jsonb_array_elements(t->'inventory') g where t->>'kind'='ledger_correction' and g->>'karat'='18' and g->>'milligrams'='123')
   then raise exception 'compensation_report %',r->'summary'; end if;
 if public.get_financial_day_report_v1(d)->>'fingerprint'<>old->>'fingerprint' then raise exception 'rewrote_historical_day'; end if;
 if jsonb_array_length(public.list_financial_report_days_v1()->'days')<>2 then raise exception 'day_list'; end if;
end;
$historical$;
reset role;
-- A real count-only identity has no owner membership and must never read reports.
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)
 values('b1111111-1111-4111-8111-111111111113','00000000-0000-0000-0000-000000000000','authenticated','authenticated','report-staff@example.test',false,now(),now());
insert into public.closing_staff_accounts(shop_id,user_id,display_name,phone,created_by)
 values('b2222222-2222-4222-8222-222222222222','b1111111-1111-4111-8111-111111111113','عد تجريبي','+201099999999','b1111111-1111-4111-8111-111111111111');
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111113',true);
do $staff$
begin
 if pg_temp.report_error('select public.list_financial_report_days_v1()')<>'forbidden'
 or pg_temp.report_error($q$select public.get_financial_day_report_v1('b3333333-3333-4333-8333-333333333335')$q$)<>'forbidden'
 then raise exception 'staff_report_leak'; end if;
end;
$staff$;
reset role;
update public.shop_entitlements set expires_at=now()-interval '1 second' where shop_id='b2222222-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
select public.get_financial_day_report_v1(day_id)->>'fingerprint' from report_fixture;
reset role;
update public.shop_memberships set revoked_at=now() where user_id='b1111111-1111-4111-8111-111111111111';
set local role authenticated;
do $deny$
begin
 if pg_temp.report_error('select public.list_financial_report_days_v1()')<>'forbidden' then raise exception 'revoked_report'; end if;
end;
$deny$;
rollback;
do $$ begin raise notice 'FINANCIAL_DAY_REPORT_SQL_PASSED'; end; $$;


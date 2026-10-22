-- Synthetic weekly report fixture. Every mutation, grant and registry row rolls back.
begin;
set local time zone 'UTC';
create function pg_temp.week_error(q text) returns text language plpgsql as $$
begin execute q; return 'ok'; exception when others then return sqlerrm; end; $$;
create function pg_temp.gold_of(r jsonb, k integer, f text) returns text language sql as $$
  select g->>f from jsonb_array_elements(r->'gold') g where (g->>'karat')::integer=k $$;
create function pg_temp.group_of(r jsonb, c text, k integer, f text) returns text language sql as $$
  select g->>f from jsonb_array_elements(r->'groups') g
  where g->>'category'=c and (g->>'karat')::integer=k $$;
create temp table week_state(
  day1 uuid, day2 uuid, offset_sale uuid, server_date date,
  phase1 text, historical text, combined text, content jsonb
);
insert into week_state(server_date)
select (now() at time zone 'Africa/Cairo')::date;
create temp table week_guard(
  label text primary key, ops bigint, audits bigint, posts bigint, invoices bigint, media bigint
);
create function pg_temp.mark(p_label text) returns void
language plpgsql security definer set search_path = pg_temp as $$
begin
  insert into week_guard values (
    p_label,
    (select count(*) from public.financial_operations),
    (select count(*) from public.financial_audit_events),
    (select count(*) from public.journal_postings),
    (select count(*) from public.invoice_dispatch_confirmations),
    (select count(*) from public.r2_media_objects))
  on conflict (label) do update set
    ops=excluded.ops, audits=excluded.audits, posts=excluded.posts,
    invoices=excluded.invoices, media=excluded.media;
end $$;
create function pg_temp.same(p_label text, p_media bigint default 0) returns void
language plpgsql security definer set search_path = pg_temp as $$
declare g week_guard%rowtype; ops bigint; audits bigint; posts bigint; invoices bigint; media bigint;
begin
  select * into g from week_guard where label=p_label;
  select count(*) into ops from public.financial_operations;
  select count(*) into audits from public.financial_audit_events;
  select count(*) into posts from public.journal_postings;
  select count(*) into invoices from public.invoice_dispatch_confirmations;
  select count(*) into media from public.r2_media_objects;
  if ops<>g.ops or audits<>g.audits or posts<>g.posts or invoices<>g.invoices
    or media<>g.media+p_media then
    raise exception 'report_mutated % ops %/% audits %/% posts %/% invoices %/% media %/%',
      p_label, ops, g.ops, audits, g.audits, posts, g.posts, invoices, g.invoices, media, g.media+p_media;
  end if;
end $$;
grant all on week_state, week_guard to authenticated;
grant execute on function public.post_linked_return_v1(uuid, jsonb) to authenticated;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at) values
 ('b1111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','week-owner@example.test',false,now(),now()),
 ('b1111111-1111-4111-8111-111111111112','00000000-0000-0000-0000-000000000000','authenticated','authenticated','week-other@example.test',false,now(),now()),
 ('b1111111-1111-4111-8111-111111111113','00000000-0000-0000-0000-000000000000','authenticated','authenticated','week-staff@example.test',false,now(),now()),
 ('b1111111-1111-4111-8111-111111111114','00000000-0000-0000-0000-000000000000','authenticated','authenticated','week-admin@example.test',false,now(),now());
update auth.users set email_confirmed_at=now() where id='b1111111-1111-4111-8111-111111111114';
insert into public.shops(id,name,owner_display_name,time_zone) values
 ('b2222222-2222-4222-8222-222222222222','متجر الأسبوع التجريبي','مالك تجريبي','Africa/Cairo'),
 ('b2222222-2222-4222-8222-222222222223','متجر أسبوع آخر','مالك آخر','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values
 ('b2222222-2222-4222-8222-222222222222','b1111111-1111-4111-8111-111111111111','owner'),
 ('b2222222-2222-4222-8222-222222222223','b1111111-1111-4111-8111-111111111112','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at) values
 ('b2222222-2222-4222-8222-222222222222',now()-interval '1 day',now()+interval '30 days'),
 ('b2222222-2222-4222-8222-222222222223',now()-interval '1 day',now()+interval '30 days');
insert into public.platform_admins(user_id) values ('b1111111-1111-4111-8111-111111111114');
insert into public.closing_staff_accounts(shop_id,user_id,display_name,phone,created_by)
 values ('b2222222-2222-4222-8222-222222222222','b1111111-1111-4111-8111-111111111113','عد تجريبي','+201099999998','b1111111-1111-4111-8111-111111111111');

set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
do $phase1$
declare
  d uuid; report jsonb; again jsonb; stripped jsonb; review jsonb; posted jsonb;
  multi uuid; v_offset uuid; scrap_sale uuid; small_sale uuid; partial uuid; unpaid uuid; replacement uuid;
  sale jsonb; purchase jsonb;
begin
  if public.get_financial_week_report_v1(null)->'days' <> '[]'::jsonb then
    raise exception 'empty_week';
  end if;
  perform public.confirm_opening_balances(gen_random_uuid(),'{
    "version":1,
    "cash":{"cash":"9007199254740993"},
    "stock":[
      {"category":"worked_jewelry","karat":14,"milligrams":"20000","count":"10"},
      {"category":"worked_jewelry","karat":18,"milligrams":"20000","count":"10"},
      {"category":"worked_jewelry","karat":21,"milligrams":"20000","count":"10"},
      {"category":"worked_jewelry","karat":22,"milligrams":"20000","count":"10"},
      {"category":"bullion","karat":24,"milligrams":"20000","count":"5"},
      {"category":"coin","karat":21,"milligrams":"20000","count":"2"}
    ],
    "scrap":[
      {"karat":14,"milligrams":"5000"},{"karat":18,"milligrams":"5000"},
      {"karat":21,"milligrams":"5000"},{"karat":22,"milligrams":"5000"},
      {"karat":24,"milligrams":"5000"}
    ]
  }'::jsonb);
  select id into d from public.business_days
    where shop_id='b2222222-2222-4222-8222-222222222222' and status='open';
  sale := '{"version":1,"kind":"sale","total_piastres":"100001","tenders":[{"method":"cash","piastres":"100001"}],"items":[
    {"category":"worked_jewelry","karat":14,"milligrams":"500","count":"1","item_name":"مشغول أول","line_price_piastres":null},
    {"category":"worked_jewelry","karat":14,"milligrams":"500","count":"1","item_name":"مشغول ثان","line_price_piastres":null},
    {"category":"worked_jewelry","karat":21,"milligrams":"2001","count":"1","item_name":"خاتم","line_price_piastres":null},
    {"category":"worked_jewelry","karat":22,"milligrams":"1000","count":"1","item_name":"سلسلة","line_price_piastres":null},
    {"category":"coin","karat":21,"milligrams":"8000","count":"1","item_name":"جنيه","line_price_piastres":null},
    {"category":"bullion","karat":24,"milligrams":"1000","count":"1","item_name":"سبيكة","line_price_piastres":null}
  ],"description":"بيع متعدد الأصناف","customer_name":"طرف تجريبي","customer_phone":"","note":""}'::jsonb;
  multi := (public.post_daily_ledger_trade(gen_random_uuid(), sale)->>'operation_id')::uuid;
  v_offset := (public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"sale","total_piastres":"15001","tenders":[{"method":"cash","piastres":"15001"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1500","count":"1","item_name":"سوار","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}')->>'operation_id')::uuid;
  scrap_sale := (public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"scrap_sale","total_piastres":"20001","tenders":[{"method":"cash","piastres":"20001"}],"items":[{"category":"scrap","karat":22,"milligrams":"300","count":null,"item_name":"كسر مباع","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}')->>'operation_id')::uuid;
  small_sale := (public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"sale","total_piastres":"10001","tenders":[{"method":"cash","piastres":"10001"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"بيع يُحذف","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}')->>'operation_id')::uuid;
  partial := (public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"purchase","total_piastres":"50001","tenders":[{"method":"cash","piastres":"20001"}],"purchase_obligation_piastres":"30000","items":[{"category":"scrap","karat":14,"milligrams":"1000","count":null,"item_name":"كسر","line_price_piastres":null},{"category":"scrap","karat":14,"milligrams":"230","count":null,"item_name":"كسر إضافي","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}')->>'operation_id')::uuid;
  purchase := '{"version":1,"kind":"purchase","total_piastres":"60001","tenders":[],"purchase_obligation_piastres":"60001","items":[{"category":"scrap","karat":18,"milligrams":"2340","count":null,"item_name":"كسر غير مدفوع","line_price_piastres":null}],"description":"","customer_name":"طرف تجريبي","customer_phone":"","note":""}'::jsonb;
  unpaid := (public.post_daily_ledger_trade(gen_random_uuid(), purchase)->>'operation_id')::uuid;
  perform public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"expense","total_piastres":"123","tenders":[{"method":"cash","piastres":"123"}],"items":[],"description":"مصروف","customer_name":"طرف تجريبي","customer_phone":"","note":""}');
  review := public.review_ledger_trade_change_v1(small_sale,'delete',null);
  perform public.post_ledger_trade_change_v1(gen_random_uuid(), small_sale, 'delete', null,
    (review->>'expected_day_id')::uuid, (review->>'expected_day_version')::bigint,
    review->>'source_sha256', review->>'review_token');
  purchase := purchase || '{"total_piastres":"70001","purchase_obligation_piastres":"70001","items":[{"category":"scrap","karat":18,"milligrams":"3000","count":null,"item_name":"كسر معدل","line_price_piastres":null}]}'::jsonb;
  review := public.review_ledger_trade_change_v1(unpaid,'edit',purchase);
  posted := public.post_ledger_trade_change_v1(gen_random_uuid(), unpaid, 'edit', purchase,
    (review->>'expected_day_id')::uuid, (review->>'expected_day_version')::bigint,
    review->>'source_sha256', review->>'review_token');
  replacement := (posted->>'replacement_operation_id')::uuid;
  purchase := purchase || '{"total_piastres":"80001","purchase_obligation_piastres":"80001","items":[{"category":"scrap","karat":24,"milligrams":"1111","count":null,"item_name":"كسر نهائي","line_price_piastres":null}]}'::jsonb;
  review := public.review_ledger_trade_change_v1(replacement,'edit',purchase);
  perform public.post_ledger_trade_change_v1(gen_random_uuid(), replacement, 'edit', purchase,
    (review->>'expected_day_id')::uuid, (review->>'expected_day_version')::bigint,
    review->>'source_sha256', review->>'review_token');
  perform public.post_daily_ledger_cash_transfer(gen_random_uuid(), '{"version":1,"kind":"cash_transfer","from_method":"cash","to_method":"card","amount_piastres":"300","note":"تحويل تجريبي"}'::jsonb);
  perform public.settle_purchase_cash_payable(gen_random_uuid(), partial, '[{"method":"cash","piastres":"10000"}]'::jsonb);

  report := public.get_financial_week_report_v1(null);
  again := public.get_financial_week_report_v1((report->>'end_date')::date);
  stripped := report - 'fingerprint' - 'generated_at_utc' - 'generated_at_shop'
    - 'server_date' - 'first_business_date' - 'last_selectable_date';
  if report->>'fingerprint' is distinct from again->>'fingerprint'
    or report->>'end_date' is distinct from (select server_date::text from week_state)
    or (report->>'end_date')::date - (report->>'start_date')::date <> 6
    or jsonb_array_length(report->'days') <> 1
    or jsonb_array_length(report->'days'->0->'transactions') < 10
  then raise exception 'phase1_identity %', report->'summary'; end if;
  if report#>>'{summary,sales}' is distinct from '135003'
    or report#>>'{summary,sale_returns}' is distinct from '0'
    or report#>>'{summary,net_sales}' is distinct from '135003'
    or report#>>'{summary,purchases}' is distinct from '130002'
    or report#>>'{summary,net_purchases}' is distinct from '130002'
    or report#>>'{summary,expenses}' is distinct from '123'
    or report#>>'{summary,net_cash}' is distinct from '104879'
    or report#>>'{summary,opening_cash}' is distinct from '9007199254740993'
    or report#>>'{summary,sale_count}' is distinct from '3'
    or report#>>'{summary,purchase_count}' is distinct from '2'
    or report#>>'{summary,expense_count}' is distinct from '1'
    or report#>>'{summary,return_count}' is distinct from '0'
    or report#>>'{summary,operation_count}' is distinct from '8'
    or (report#>>'{summary,net_sales}')::numeric
      - (report#>>'{summary,net_purchases}')::numeric
      - (report#>>'{summary,expenses}')::numeric
      = (report#>>'{summary,net_cash}')::numeric
  then raise exception 'phase1_totals %', report->'summary'; end if;
  if pg_temp.gold_of(report,14,'sold') is distinct from '1000'
    or pg_temp.gold_of(report,18,'sold') is distinct from '1500'
    or pg_temp.gold_of(report,21,'sold') is distinct from '10001'
    or pg_temp.gold_of(report,22,'sold') is distinct from '1300'
    or pg_temp.gold_of(report,24,'sold') is distinct from '1000'
    or pg_temp.gold_of(report,14,'bought') is distinct from '1230'
    or pg_temp.gold_of(report,18,'bought') is distinct from '0'
    or pg_temp.gold_of(report,24,'bought') is distinct from '1111'
    or pg_temp.group_of(report,'worked_jewelry',14,'sold') is distinct from '1000'
    or pg_temp.group_of(report,'worked_jewelry',14,'sale_movements') is distinct from '1'
    or pg_temp.group_of(report,'scrap',14,'bought') is distinct from '1230'
    or pg_temp.group_of(report,'scrap',14,'purchase_movements') is distinct from '1'
    or pg_temp.group_of(report,'worked_jewelry',18,'sale_movements') is distinct from '1'
    or (select coalesce(sum((g->>'sale_movements')::numeric),0) from jsonb_array_elements(report->'groups') g)
      <= (report#>>'{summary,sale_count}')::numeric
  then raise exception 'phase1_groups % gold %', report->'groups', report->'gold'; end if;
  if not exists(select 1 from jsonb_array_elements(report->'days'->0->'transactions') t where t->>'state'='delete')
    or not exists(select 1 from jsonb_array_elements(report->'days'->0->'transactions') t where t->>'state'='internal_reversal')
    or not exists(select 1 from jsonb_array_elements(report->'days'->0->'transactions') t where t->>'state'='edit')
  then raise exception 'phase1_states'; end if;
  if pg_temp.week_error(format('select public.confirm_financial_week_pdf_v1(%L,%L,%L)', report->>'end_date', report->>'fingerprint', 'report-pdf/missing')) <> 'media_rejected'
    or pg_temp.week_error('select public.confirm_financial_week_pdf_v1(null,repeat(''a'',64),''report-pdf/missing'')') <> 'invalid_date'
    or pg_temp.week_error('select public.get_financial_week_report_v1(''0001-01-06'')') <> 'invalid_date'
    or has_function_privilege('anon','public.get_financial_week_report_v1(date)','execute')
    or has_function_privilege('anon','public.confirm_financial_week_pdf_v1(date,text,text)','execute')
    or has_function_privilege('authenticated','public.record_report_pdf_object_v1(uuid,uuid,text,bigint,text)','execute')
  then raise exception 'phase1_grants'; end if;
  update week_state set day1=d, offset_sale=v_offset, phase1=report->>'fingerprint', content=stripped;
end;
$phase1$;
reset role;
do $hash$
declare s jsonb; fp text;
begin
  select content, phase1 into s, fp from week_state;
  if encode(extensions.digest(convert_to(s::text,'UTF8'),'sha256'),'hex') is distinct from fp then
    raise exception 'fingerprint_mismatch';
  end if;
end;
$hash$;
do $registry$
declare r jsonb; key text := 'report-pdf/b2222222-2222-4222-8222-222222222222/'||repeat('a',64)||'.pdf';
  other text := 'report-pdf/b2222222-2222-4222-8222-222222222223/'||repeat('b',64)||'.pdf';
begin
  perform pg_temp.mark('registry');
  r := public.record_report_pdf_object_v1('b1111111-1111-4111-8111-111111111111','b2222222-2222-4222-8222-222222222222',key,100,repeat('a',64));
  if r->>'replayed' is distinct from 'false' then raise exception 'pdf_insert'; end if;
  r := public.record_report_pdf_object_v1('b1111111-1111-4111-8111-111111111111','b2222222-2222-4222-8222-222222222222',key,100,repeat('a',64));
  if r->>'replayed' is distinct from 'true' then raise exception 'pdf_replay'; end if;
  perform public.record_report_pdf_object_v1('b1111111-1111-4111-8111-111111111112','b2222222-2222-4222-8222-222222222223',other,80,repeat('b',64));
  perform pg_temp.same('registry', 2);
end;
$registry$;
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
do $confirm$
declare key text := 'report-pdf/b2222222-2222-4222-8222-222222222222/'||repeat('a',64)||'.pdf';
  other text := 'report-pdf/b2222222-2222-4222-8222-222222222223/'||repeat('b',64)||'.pdf';
  fingerprint text; empty jsonb;
begin
  select phase1 into fingerprint from week_state;
  perform pg_temp.mark('confirm');
  perform public.confirm_financial_week_pdf_v1((select server_date from week_state), fingerprint, key);
  perform public.confirm_financial_week_pdf_v1((select server_date from week_state), fingerprint, key);
  if pg_temp.week_error(format('select public.confirm_financial_week_pdf_v1(%L,%L,%L)', (select server_date from week_state), repeat('f',64), key)) <> 'stale_report'
    or pg_temp.week_error(format('select public.confirm_financial_week_pdf_v1(%L,%L,%L)', (select server_date from week_state), fingerprint, other)) <> 'media_rejected'
  then raise exception 'confirm_boundaries'; end if;
  perform pg_temp.same('confirm');
  empty := public.get_financial_week_report_v1('2020-01-08');
  if empty->'days' <> '[]'::jsonb or empty#>>'{summary,net_sales}' is distinct from '0'
    or empty->>'start_date' is distinct from '2020-01-02' or empty->>'fingerprint' is distinct from public.get_financial_week_report_v1('2020-01-08')->>'fingerprint'
  then raise exception 'empty_historical %', empty->'summary'; end if;
  if pg_temp.week_error(format('select public.get_financial_week_report_v1(%L)', (select server_date+1 from week_state))) <> 'invalid_date'
  then raise exception 'future_date'; end if;
end;
$confirm$;
reset role;
update public.business_days set status='closed', closed_at=now(),
  business_date=(select server_date-3 from week_state),
  opened_at=(((select server_date-3 from week_state)::timestamp + time '09:00') at time zone 'Africa/Cairo')
 where id=(select day1 from week_state);
insert into public.business_days(id,shop_id,business_date,opened_at,status,day_version)
values ('b3333333-3333-4333-8333-333333333335','b2222222-2222-4222-8222-222222222222',
  (select server_date from week_state), now(), 'open', 1);
update week_state set day2='b3333333-3333-4333-8333-333333333335';
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
do $cross$
declare v_week jsonb; day2 uuid; src uuid; version bigint; i integer; p jsonb; report jsonb; before_ops bigint;
begin
  select ws.day2, ws.offset_sale into day2, src from week_state ws;
  v_week := public.get_financial_week_report_v1((select server_date-3 from week_state));
  update week_state set historical=v_week->>'fingerprint';
  select day_version into version from public.business_days where id=day2;
  perform public.post_linked_return_v1(gen_random_uuid(), jsonb_build_object(
    'version',1,'kind','sale_return','original_operation_id',src,'expected_day_id',day2,
    'expected_day_version',version::text,'note','مرتجع في يوم لاحق',
    'items', jsonb_build_array(jsonb_build_object('item_index','0','milligrams','1500','count','1')),
    'consideration_piastres','15001',
    'tenders', jsonb_build_array(jsonb_build_object('method','cash','piastres','15001'))));
  for i in 1..105 loop
    perform public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"expense","total_piastres":"1","tenders":[{"method":"cash","piastres":"1"}],"items":[],"description":"مصروف تجريبي","customer_name":"طرف تجريبي","customer_phone":"","note":""}');
  end loop;
  select jsonb_build_object('version',1,'kind','ledger_correction','expected_day_id',day2,
    'expected_day_version', day_version::text, 'reason','تسوية تجريبية',
    'counted', jsonb_build_object(
      'cash', jsonb_build_object('cash', (select (amount+50)::text from public.ledger_account_balances
        where shop_id='b2222222-2222-4222-8222-222222222222' and account_kind='cash_method' and method_code='cash'),
        'instant_transfer','0','wallet','0','card',
        (select amount::text from public.ledger_account_balances
          where shop_id='b2222222-2222-4222-8222-222222222222' and account_kind='cash_method' and method_code='card')),
      'stock', (select jsonb_agg(jsonb_build_object(
        'category', metal.category_code, 'karat', metal.karat,
        'milligrams', (metal.amount + case when metal.category_code='worked_jewelry' and metal.karat=21 then 1001 else 0 end)::text,
        'count', coalesce(piece.amount, 0)::text
      ) order by metal.category_code, metal.karat)
      from public.ledger_account_balances metal
      left join public.ledger_account_balances piece
        on piece.shop_id=metal.shop_id and piece.account_kind='saleable_count'
        and piece.category_code=metal.category_code and piece.karat=metal.karat
      where metal.shop_id='b2222222-2222-4222-8222-222222222222'
        and metal.account_kind='saleable_metal'),
      'scrap', (select jsonb_agg(jsonb_build_object('karat',karat,'milligrams',
        (amount + case when karat=18 then 123 else 0 end)::text) order by karat)
        from public.ledger_account_balances
        where shop_id='b2222222-2222-4222-8222-222222222222' and account_kind='scrap_metal')))
  into p from public.business_days where id=day2;
  perform public.post_ledger_correction_v1(gen_random_uuid(), p);
  if public.get_financial_week_report_v1((select server_date-3 from week_state))->>'fingerprint'
    is distinct from (select ws.historical from week_state ws)
    or public.get_financial_week_report_v1((select server_date-3 from week_state))#>>'{summary,sales}' is distinct from '135003'
    or pg_temp.gold_of(public.get_financial_week_report_v1((select server_date-3 from week_state)),18,'sold') is distinct from '1500'
  then raise exception 'out_of_range_changed_historical_week'; end if;
  report := public.get_financial_week_report_v1((select server_date from week_state));
  if report#>>'{summary,net_sales}' is distinct from '120002'
    or report#>>'{summary,sale_returns}' is distinct from '15001'
    or report#>>'{summary,purchases}' is distinct from '130002'
    or report#>>'{summary,expenses}' is distinct from '228'
    or report#>>'{summary,net_cash}' is distinct from '89823'
    or report#>>'{summary,operation_count}' is distinct from '115'
    or report#>>'{summary,return_count}' is distinct from '1'
    or report#>>'{summary,expense_count}' is distinct from '106'
    or pg_temp.gold_of(report,18,'sold') is distinct from '0'
    or pg_temp.gold_of(report,18,'bought') is distinct from '0'
    or pg_temp.group_of(report,'worked_jewelry',18,'sold') is distinct from '0'
    or pg_temp.group_of(report,'worked_jewelry',18,'sale_movements') is distinct from '2'
    or jsonb_array_length(report->'days') <> 2
    or (select sum(jsonb_array_length(d->'transactions')) from jsonb_array_elements(report->'days') d) <= 100
    or (select sum(jsonb_array_length(d->'transactions')) from jsonb_array_elements(report->'days') d)::text
      is distinct from report#>>'{summary,audit_row_count}'
  then raise exception 'combined_week %', report->'summary'; end if;
  if public.get_financial_week_report_v1((select server_date-4 from week_state))#>>'{summary,sales}' is distinct from '0'
    or public.get_financial_week_report_v1((select server_date-2 from week_state))#>>'{summary,expense_count}' is distinct from '1'
  then raise exception 'range_boundaries'; end if;
  update week_state set combined=report->>'fingerprint';
  select count(*) into before_ops from public.financial_operations;
  perform public.post_daily_ledger_trade(gen_random_uuid(), '{"version":1,"kind":"expense","total_piastres":"7","tenders":[{"method":"cash","piastres":"7"}],"items":[],"description":"مصروف داخل الفترة","customer_name":"طرف تجريبي","customer_phone":"","note":""}');
  report := public.get_financial_week_report_v1((select server_date from week_state));
  if report->>'fingerprint' = (select combined from week_state)
    or report#>>'{summary,expenses}' is distinct from '235'
    or report#>>'{summary,net_cash}' is distinct from '89816'
    or public.get_financial_week_report_v1((select server_date-3 from week_state))->>'fingerprint'
      is distinct from (select ws.historical from week_state ws)
    or pg_temp.week_error(format('select public.confirm_financial_week_pdf_v1(%L,%L,%L)', (select server_date from week_state), (select combined from week_state), 'report-pdf/b2222222-2222-4222-8222-222222222222/'||repeat('a',64)||'.pdf')) <> 'stale_report'
  then raise exception 'in_range_stale %', report->'summary'; end if;
  perform pg_temp.mark('after_posts');
  perform public.get_financial_week_report_v1((select server_date from week_state));
  perform public.confirm_financial_week_pdf_v1((select server_date from week_state), report->>'fingerprint', 'report-pdf/b2222222-2222-4222-8222-222222222222/'||repeat('a',64)||'.pdf');
  perform pg_temp.same('after_posts');
  if (select count(*) from public.financial_operations) <> before_ops+1 then raise exception 'extra_financial_write'; end if;
end;
$cross$;
reset role;
update public.business_days set business_date=(select server_date-1 from week_state),
  opened_at=(((select server_date-1 from week_state)::timestamp + time '23:30') at time zone 'Africa/Cairo')
 where id=(select day2 from week_state);
set local role authenticated;
do $midnight$
declare report jsonb; day jsonb;
begin
  report := public.get_financial_week_report_v1((select server_date-1 from week_state));
  select d into day from jsonb_array_elements(report->'days') d
    where d->>'day_id'=(select day2::text from week_state);
  if day is null
    or exists(select 1 from jsonb_array_elements(report->'days') d where d->>'day_id'=(select day2::text from week_state) and d->>'date' <> (select (server_date-1)::text from week_state))
    or not exists(select 1 from jsonb_array_elements(day->'transactions') t where left(t->>'at_shop',10) > day->>'date')
    or public.get_financial_week_report_v1((select server_date-2 from week_state))#>>'{summary,expense_count}' is distinct from '1'
  then raise exception 'midnight_open_day %', day->>'date'; end if;
end;
$midnight$;
reset role;
update public.business_days set business_date=(select server_date-1 from week_state),
  opened_at=(((select server_date-1 from week_state)::timestamp + time '09:00') at time zone 'Africa/Cairo')
 where id=(select day1 from week_state);
set local role authenticated;
do $duplicate$
declare report jsonb;
begin
  report := public.get_financial_week_report_v1((select server_date-1 from week_state));
  if jsonb_array_length(report->'days') <> 2
    or (select count(distinct d->>'date') from jsonb_array_elements(report->'days') d) <> 1
    or (select count(distinct d->>'day_id') from jsonb_array_elements(report->'days') d) <> 2
    or report->>'contains_open_day' is distinct from 'true'
  then raise exception 'duplicate_date %', report->'days'; end if;
end;
$duplicate$;
reset role;
update public.shops set time_zone='America/New_York' where id='b2222222-2222-4222-8222-222222222222';
update public.business_days set business_date=date '2026-03-08', opened_at='2026-03-08 07:30:00+00'
 where id=(select day2 from week_state);
set local role authenticated;
do $dst$
declare report jsonb; day jsonb;
begin
  report := public.get_financial_week_report_v1(date '2026-03-08');
  select d into day from jsonb_array_elements(report->'days') d
    where d->>'day_id'=(select day2::text from week_state);
  if day->>'date' is distinct from '2026-03-08'
    or day->>'opened_at_shop' is distinct from '2026-03-08 03:30:00'
    or not exists(select 1 from jsonb_array_elements(day->'transactions') t where left(t->>'at_shop',10) <> '2026-03-08')
    or exists(select 1 from jsonb_array_elements(public.get_financial_week_report_v1(date '2026-03-07')->'days') d where d->>'day_id'=(select day2::text from week_state))
  then raise exception 'dst_boundary %', day->>'opened_at_shop'; end if;
end;
$dst$;
reset role;
update public.shops set time_zone='Pacific/Honolulu' where id='b2222222-2222-4222-8222-222222222222';
update public.business_days set
  business_date=((now() at time zone 'Pacific/Honolulu')::date + 3),
  opened_at=((((now() at time zone 'Pacific/Honolulu')::date + 3)::timestamp + time '15:00') at time zone 'Africa/Cairo')
 where shop_id='b2222222-2222-4222-8222-222222222222' and id=(select day1 from week_state);
update public.business_days set
  business_date=((now() at time zone 'Pacific/Honolulu')::date + 3),
  opened_at=((((now() at time zone 'Pacific/Honolulu')::date + 3)::timestamp + time '18:00') at time zone 'Africa/Cairo')
 where shop_id='b2222222-2222-4222-8222-222222222222' and id=(select day2 from week_state);
set local role authenticated;
do $zone$
declare server date := (now() at time zone 'Pacific/Honolulu')::date; report jsonb;
begin
  report := public.get_financial_week_report_v1(server+3);
  if report->>'server_date' is distinct from server::text
    or report->>'last_selectable_date' is distinct from (server+3)::text
    or report->>'end_date' is distinct from (server+3)::text
    or jsonb_array_length(report->'days') <> 2
    or (server+3) <= server
  then raise exception 'zone_ahead %', report; end if;
  if pg_temp.week_error(format('select public.get_financial_week_report_v1(%L)', server+4)) <> 'invalid_date'
  then raise exception 'zone_upper_bound'; end if;
end;
$zone$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111112',true);
do $other$
declare report jsonb;
begin
  report := public.get_financial_week_report_v1(null);
  if report->>'shop_id' is distinct from 'b2222222-2222-4222-8222-222222222223'
    or report->'days' <> '[]'::jsonb
  then raise exception 'other_shop_leak'; end if;
end;
$other$;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111113',true);
do $staff$
begin
  if pg_temp.week_error('select public.get_financial_week_report_v1(null)') <> 'forbidden'
    or pg_temp.week_error('select public.confirm_financial_week_pdf_v1(current_date,repeat(''a'',64),''report-pdf/missing'')') <> 'forbidden'
  then raise exception 'staff_leak'; end if;
end;
$staff$;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111114',true);
do $admin$
begin
  if public.is_platform_admin() is not true
    or pg_temp.week_error('select public.get_financial_week_report_v1(null)') <> 'forbidden'
  then raise exception 'platform_admin_leak'; end if;
end;
$admin$;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claim.session_id','b9999999-9999-4999-8999-999999999999',true);
do $session$
begin
  if pg_temp.week_error('select public.get_financial_week_report_v1(null)') <> 'session_expired'
  then raise exception 'session_loss'; end if;
end;
$session$;
select set_config('request.jwt.claim.session_id','',true);
reset role;
update public.shop_entitlements set expires_at=now()-interval '1 second'
 where shop_id='b2222222-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub','b1111111-1111-4111-8111-111111111111',true);
do $expired$
begin
  perform public.get_financial_week_report_v1(null);
end;
$expired$;
reset role;
update public.shop_memberships set revoked_at=now() where user_id='b1111111-1111-4111-8111-111111111111';
set local role authenticated;
do $revoked$
begin
  if pg_temp.week_error('select public.get_financial_week_report_v1(null)') <> 'forbidden'
  then raise exception 'revoked_owner'; end if;
end;
$revoked$;
reset role;
set local role anon;
do $anon$
begin
  if pg_temp.week_error('select public.get_financial_week_report_v1(null)') = 'ok'
    or pg_temp.week_error('select public.confirm_financial_week_pdf_v1(current_date,repeat(''a'',64),''k'')') = 'ok'
  then raise exception 'anon_grant'; end if;
end;
$anon$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','',true);
do $unsigned$
begin
  if pg_temp.week_error('select public.get_financial_week_report_v1(null)') <> 'unauthenticated'
  then raise exception 'missing_session'; end if;
end;
$unsigned$;
reset role;
rollback;
do $$ begin raise notice 'FINANCIAL_WEEK_REPORT_SQL_PASSED'; end; $$;

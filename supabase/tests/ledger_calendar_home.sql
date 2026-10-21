-- Synthetic read regressions. All fixtures roll back; never run against hosted data.
begin;
do $guard$ begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_owner_meeting_[a-z0-9_]+$' then
    raise exception 'dedicated loopback test database required';
  end if;
  if has_function_privilege('anon','public.get_daily_ledger_home_v1()','execute')
    or has_function_privilege('anon','public.list_daily_notes_date_v1(date,text,integer,text)','execute') then
    raise exception 'anonymous function privilege';
  end if;
end; $guard$;
insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('c1900000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cache-a@example.test',false,now(),now()),
  ('c1900000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cache-b@example.test',false,now(),now());
insert into public.shops (id,name,owner_display_name,time_zone) values
  ('c2900000-0000-4000-8000-000000000001','متجر تجريبي','مالك تجريبي','Africa/Cairo'),
  ('c2900000-0000-4000-8000-000000000002','متجر مستقل','مالك مستقل','Africa/Cairo');
insert into public.shop_memberships (shop_id,user_id,role) values
  ('c2900000-0000-4000-8000-000000000001','c1900000-0000-4000-8000-000000000001','owner'),
  ('c2900000-0000-4000-8000-000000000002','c1900000-0000-4000-8000-000000000002','owner');
insert into public.shop_entitlements (shop_id,starts_at,expires_at) values
  ('c2900000-0000-4000-8000-000000000001',now()-interval '1 day',now()+interval '10 days'),
  ('c2900000-0000-4000-8000-000000000002',now()-interval '1 day',now()+interval '10 days');
set local role authenticated;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','',true);
do $test$
declare
  v_before jsonb;
  v_after jsonb;
  v_day uuid;
  v_date date;
  v_notes jsonb;
  v_i integer;
begin
  perform public.confirm_opening_balances('c3900000-0000-4000-8000-000000000001',
    '{"version":1,"cash":{"cash":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"5"}],"scrap":[]}'::jsonb);
  v_before := public.get_daily_ledger_v2();
  v_day := (v_before #>> '{business_day,id}')::uuid;
  v_date := (v_before #>> '{business_day,business_date}')::date;
  v_after := public.get_daily_ledger_home_v1();
  if v_after ->> 'read_model_version' <> '3'
    or v_after #>> '{journal_context,business_date}' <> v_date::text
    or v_after -> 'cash' <> v_before -> 'cash'
    or v_after -> 'stock' <> v_before -> 'stock'
    or v_after -> 'business_day' <> v_before -> 'business_day'
    or (v_after #>> '{journal_context,next_midnight_at}')::timestamptz <= now()
    or (v_after #>> '{journal_context,next_midnight_at}')::timestamptz <> ((v_date + 1)::timestamp at time zone 'Africa/Cairo') then
    raise exception 'home contract or read changed balances %', v_after;
  end if;
end;
$test$;
reset role;
-- Move the still-open financial session to yesterday: the home journal stays on
-- that open day until explicit close. Cash/stock remain intact. Calendar-date
-- notes for today stay empty when no session exists on the calendar date.
update public.business_days set business_date = business_date - 1, opened_at = opened_at - interval '1 day'
where shop_id = 'c2900000-0000-4000-8000-000000000001';
set local role authenticated;
do $empty$
declare v_home jsonb; v_old jsonb; v_notes jsonb; v_open_date text; v_day text;
begin
  v_old := public.get_daily_ledger_v2();
  v_home := public.get_daily_ledger_home_v1();
  v_notes := public.list_daily_notes_date_v1((now() at time zone 'Africa/Cairo')::date, null, 30, null);
  v_open_date := v_old #>> '{business_day,business_date}';
  v_day := v_old #>> '{business_day,id}';
  if v_home -> 'cash' <> v_old -> 'cash' or v_home -> 'stock' <> v_old -> 'stock'
    or v_home -> 'business_day' <> v_old -> 'business_day'
    or v_home #>> '{journal_context,business_date}' is distinct from v_open_date
    or v_home #> '{journal_context,day_ids}' <> jsonb_build_array(v_day)
    or v_notes #> '{page,items}' <> '[]'::jsonb then
    raise exception 'open-day home journal drifted %',v_home;
  end if;
end;
$empty$;
reset role;
-- Two closed/open sessions for today's date, with more notes than one feed page.
update public.business_days set business_date = (now() at time zone 'Africa/Cairo')::date, opened_at = opened_at + interval '1 day'
where shop_id = 'c2900000-0000-4000-8000-000000000001';
insert into public.business_days(id, shop_id, business_date, status, opened_at, closed_at, day_version)
values ('d3900000-0000-4000-8000-000000000001', 'c2900000-0000-4000-8000-000000000001',
  (now() at time zone 'Africa/Cairo')::date, 'closed', ((now() at time zone 'Africa/Cairo')::date::timestamp at time zone 'Africa/Cairo'), now(), 1);
insert into public.financial_operations(id,shop_id,shop_sequence,kind,business_day_id,actor_user_id,created_at)
select gen_random_uuid(),'c2900000-0000-4000-8000-000000000001',1000+i,'daily_note',
  case when i%2=0 then 'd3900000-0000-4000-8000-000000000001'::uuid else
  (select id from public.business_days where shop_id='c2900000-0000-4000-8000-000000000001' and status='open') end,
  'c1900000-0000-4000-8000-000000000001',now()
from generate_series(1,105) as n(i);
insert into public.financial_operation_details(operation_id,shop_id,payload,created_at)
select id,shop_id,'{"version":1,"text":"ملاحظة اختبار التاريخ","attachment":null}'::jsonb,created_at
from public.financial_operations where shop_id='c2900000-0000-4000-8000-000000000001' and kind='daily_note';
set local role authenticated;
do $many$
declare v_home jsonb; v_page jsonb; v_next jsonb;
begin
  v_home := public.get_daily_ledger_home_v1();
  v_page := public.list_daily_notes_date_v1((now() at time zone 'Africa/Cairo')::date,null,50,null);
  v_next := public.list_daily_notes_date_v1((now() at time zone 'Africa/Cairo')::date,v_page #>> '{page,next_before_sequence}',50,null);
  if v_home #>> '{journal_context,note_count}' <> '105'
    or jsonb_array_length(v_home #> '{journal_context,day_ids}') <> 2
    or jsonb_array_length(v_home -> 'feed') <> 100
    or v_home #>> '{feed_page,has_more}' <> 'true'
    or jsonb_array_length(v_page #> '{page,items}') <> 50
    or jsonb_array_length(v_next #> '{page,items}') <> 50
    or v_page #>> '{page,has_more}' <> 'true'
    or v_page #>> '{page,items,49,note_id}' = v_next #>> '{page,items,0,note_id}' then
    raise exception 'counts/pagination across sessions % %',v_home,v_page;
  end if;
  begin
    perform public.list_daily_notes_date_v1((now() at time zone 'Africa/Cairo')::date+1,null,30,null);
    raise exception 'future date accepted';
  exception when others then if sqlerrm <> 'invalid_input' then raise; end if; end;
end;
$many$;
do $closing$
declare v_state jsonb; v_counts jsonb; v_result jsonb; v_again jsonb; v_bad jsonb; v_audit jsonb;
begin
  if has_function_privilege('anon','public.close_daily_ledger_day_v2(uuid,uuid,bigint,jsonb)','execute')
    or has_function_privilege('authenticated','private.closing_counts_match_v2(jsonb,jsonb)','execute') then
    raise exception 'closing privileges';
  end if;
  v_state := public.get_daily_ledger_day_state();
  v_counts := jsonb_build_object('version',2,'cash',v_state #> '{counts,cash}',
    'scrap',v_state #> '{counts,scrap}', 'stock',
    '[{"category":"worked_jewelry","karat":21,"item_name":"خاتم","count":"3","milligrams":null},{"category":"worked_jewelry","karat":21,"item_name":"حلق","count":"2","milligrams":"1000"}]'::jsonb);
  v_bad := jsonb_set(v_counts,'{stock,0,count}','"4"'::jsonb);
  v_result := public.close_daily_ledger_day_v2('c3900000-0000-4000-8000-000000000090',
    (v_state->>'business_day_id')::uuid,(v_state->>'day_version')::bigint,v_bad);
  if v_result->>'reason' <> 'count_mismatch' or (public.get_daily_ledger_day_state())->>'state' <> 'open' then
    raise exception 'mismatched count closed day %',v_result;
  end if;
  v_result := public.close_daily_ledger_day_v2('c3900000-0000-4000-8000-000000000091',
    (v_state->>'business_day_id')::uuid,(v_state->>'day_version')::bigint,v_counts);
  v_again := public.close_daily_ledger_day_v2('c3900000-0000-4000-8000-000000000091',
    (v_state->>'business_day_id')::uuid,(v_state->>'day_version')::bigint,v_counts);
  if v_result->>'ok' <> 'true' or v_again->>'replayed' <> 'true'
    or v_again->>'operation_id' <> v_result->>'operation_id' then raise exception 'close/replay % %',v_result,v_again; end if;
end; $closing$;
reset role;
do $observation_audit$ declare v_audit jsonb; begin
  select details into v_audit from public.financial_audit_events
  where shop_id='c2900000-0000-4000-8000-000000000001' and action='business_day_closed';
  if v_audit #> '{count_observations,stock,0,milligrams}' is distinct from 'null'::jsonb
    or v_audit #>> '{book_counts,stock,0,milligrams}' <> '5000'
    or (select count(*) from public.financial_operations where shop_id='c2900000-0000-4000-8000-000000000001' and kind='close_day') <> 1 then
    raise exception 'unmeasured weight fabricated or duplicate close %',v_audit;
  end if;
end; $observation_audit$;
set local role authenticated;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000002',true);
-- A local calendar midnight may be 23 or 25 hours after the prior midnight.
do $dst$ begin
  if (timestamp '2026-04-25 00:00' at time zone 'Africa/Cairo') - (timestamp '2026-04-24 00:00' at time zone 'Africa/Cairo') <> interval '23 hours'
    or (timestamp '2026-10-30 00:00' at time zone 'Africa/Cairo') - (timestamp '2026-10-29 00:00' at time zone 'Africa/Cairo') <> interval '25 hours'
    then raise exception 'Cairo daylight saving boundary'; end if;
end; $dst$;
reset role;
update public.shops set time_zone='Asia/Riyadh' where id='c2900000-0000-4000-8000-000000000002';
set local role authenticated;
do $changed_zone$ declare v_home jsonb; v_date date; begin
  v_home := public.get_daily_ledger_home_v1();
  v_date := (now() at time zone 'Asia/Riyadh')::date;
  if v_home #>> '{journal_context,business_date}' <> v_date::text
    or (v_home #>> '{journal_context,next_midnight_at}')::timestamptz <> ((v_date+1)::timestamp at time zone 'Asia/Riyadh')
    then raise exception 'changed shop timezone ignored'; end if;
end; $changed_zone$;

do $isolation$ declare v_page jsonb; begin
  v_page := public.list_daily_notes_date_v1(null,null,30,null);
  if v_page #> '{page,items}' <> '[]'::jsonb or v_page #>> '{page,shop_id}' <> 'c2900000-0000-4000-8000-000000000002' then
    raise exception 'cross shop notes leak';
  end if;
end; $isolation$;
select set_config('request.jwt.claim.sub','',true);
do $denied$ begin
  begin perform public.get_daily_ledger_home_v1(); raise exception 'anonymous read allowed';
  exception when others then if sqlerrm <> 'unauthenticated' then raise; end if; end;
end; $denied$;
rollback;

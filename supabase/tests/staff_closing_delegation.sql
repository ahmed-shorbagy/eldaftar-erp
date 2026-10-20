-- Synthetic Auth identities emulate the server-admin boundary; no messages are sent.
begin;
do $guard$ begin if inet_server_addr() is distinct from '127.0.0.1'::inet or current_database() !~ '^eldaftar_owner_meeting_[a-z0-9_]+$' then raise exception 'dedicated local database required'; end if; end; $guard$;
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
select public.confirm_opening_balances('c3900000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"5"}],"scrap":[{"karat":21,"milligrams":"1000"}]}'::jsonb);
select public.begin_closing_staff_creation_v1('a4100000-0000-4000-8000-000000000001','موظف تجريبي','201000000001',repeat('a',64));
do $denied_finalization$ begin
  begin perform public.complete_closing_staff_creation_v1('c1900000-0000-4000-8000-000000000001','a4100000-0000-4000-8000-000000000001');
    raise exception 'owner finalized identity without server admin';
  exception when insufficient_privilege then null; end;
end; $denied_finalization$;
reset role;
insert into auth.users(id,instance_id,aud,role,phone,is_anonymous,phone_confirmed_at,created_at,updated_at)
select reserved_user_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',phone,false,now(),now(),now()
from private.closing_staff_creation_requests where key='a4100000-0000-4000-8000-000000000001';
set local role service_role;
select public.complete_closing_staff_creation_v1('c1900000-0000-4000-8000-000000000001','a4100000-0000-4000-8000-000000000001');
select public.complete_closing_staff_creation_v1('c1900000-0000-4000-8000-000000000001','a4100000-0000-4000-8000-000000000001');
reset role;
create temporary table staff_test_ids(user_id uuid,staff_id uuid,day_id uuid,task_id uuid,second_task uuid,revoked_task uuid,expired_task uuid);
insert into staff_test_ids(user_id,staff_id,day_id)
select staff.user_id,staff.id,day.id from public.closing_staff_accounts staff
join public.business_days day on day.shop_id=staff.shop_id and day.status='open';
grant select,update on staff_test_ids to authenticated;
set local role authenticated;
do $assignment$ declare v_id uuid; v_day uuid; v_first jsonb; v_again jsonb;
begin
  select staff_id,day_id into v_id,v_day from staff_test_ids;
  v_first := public.mutate_closing_delegation_v1('a4100000-0000-4000-8000-000000000002','assign',v_id,v_day,1);
  v_again := public.mutate_closing_delegation_v1('a4100000-0000-4000-8000-000000000002','assign',v_id,v_day,1);
  if v_first->>'ok'<>'true' or v_again->>'replayed'<>'true' or v_first->>'task_id'<>v_again->>'task_id' then raise exception 'assignment replay'; end if;
  update staff_test_ids set revoked_task=(v_first->>'task_id')::uuid;
  v_first := public.mutate_closing_delegation_v1('a4100000-0000-4000-8000-000000000100','assign',v_id,v_day,1);
  update staff_test_ids set task_id=(v_first->>'task_id')::uuid;
end; $assignment$;
reset role;
update public.closing_count_tasks set assigned_at=clock_timestamp()-interval '5 hours',expires_at=clock_timestamp()-interval '1 hour'
where id=(select task_id from staff_test_ids);
set local role authenticated;
select set_config('request.jwt.claim.sub',(select user_id::text from staff_test_ids),true);
do $revoked_expired$ declare v_task uuid; begin
  if (public.get_my_closing_task_v1())->>'state'<>'unassigned' then raise exception 'expired form remained available'; end if;
  for v_task in select revoked_task from staff_test_ids union all select task_id from staff_test_ids loop
    begin perform public.submit_closing_count_v1(gen_random_uuid(),v_task,
      '{"stock":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"count":"5","milligrams":null}],"scrap":[{"karat":21,"milligrams":"1000"}]}'::jsonb);
      raise exception 'revoked or expired count accepted';
    exception when others then if sqlerrm<>'task_unavailable' then raise; end if; end;
  end loop;
end; $revoked_expired$;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000001',true);
do $fresh$ declare v_result jsonb; begin
  v_result := public.mutate_closing_delegation_v1('a4100000-0000-4000-8000-000000000103','assign',(select staff_id from staff_test_ids),(select day_id from staff_test_ids),1);
  update staff_test_ids set expired_task=task_id,task_id=(v_result->>'task_id')::uuid;
end; $fresh$;
reset role;
update public.business_days set day_version=day_version+1 where id=(select day_id from staff_test_ids);
set local role authenticated;
select set_config('request.jwt.claim.sub',(select user_id::text from staff_test_ids),true);
do $stale$ begin
  if (public.get_my_closing_task_v1())->>'state'<>'unassigned' then raise exception 'stale day count form exposed'; end if;
  begin perform public.submit_closing_count_v1('a4100000-0000-4000-8000-000000000104',(select task_id from staff_test_ids),
    '{"stock":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"count":"5","milligrams":null}],"scrap":[{"karat":21,"milligrams":"1000"}]}'::jsonb);
    raise exception 'stale day submitted';
  exception when others then if sqlerrm<>'stale_day' then raise; end if; end;
end; $stale$;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000001',true);
do $reassign$ declare v_result jsonb; begin
  v_result := public.mutate_closing_delegation_v1('a4100000-0000-4000-8000-000000000105','assign',(select staff_id from staff_test_ids),(select day_id from staff_test_ids),2);
  update staff_test_ids set task_id=(v_result->>'task_id')::uuid;
end; $reassign$;
select set_config('request.jwt.claim.sub',(select user_id::text from staff_test_ids),true);
do $staff_boundary$ declare v_task jsonb; v_result jsonb; v_replay jsonb; v_id uuid;
begin
  select task_id into v_id from staff_test_ids;
  v_task := public.get_my_closing_task_v1();
  if v_task->>'state'<>'assigned' or v_task->>'task_id'<>v_id::text or
    v_task ?| array['cash','counts','balances','day_summary','stock_weights'] or
    v_task::text like '%"count"%' or v_task::text like '%"milligrams"%' then raise exception 'staff task leaked book values %',v_task; end if;
  begin perform public.get_daily_ledger_home_v1(); raise exception 'staff read financial ledger';
  exception when others then if sqlerrm not in ('forbidden','shop_unavailable') then raise; end if; end;
  begin perform public.list_closing_staff_v1(); raise exception 'staff read staff directory';
  exception when others then if sqlerrm not in ('forbidden','shop_unavailable') then raise; end if; end;
  begin if exists(select 1 from public.financial_operations) then raise exception 'staff direct financial read'; end if;
  exception when insufficient_privilege then null; end;
  begin perform public.close_daily_ledger_day_v2('a4100000-0000-4000-8000-000000000009',(select day_id from staff_test_ids),1,'{}'::jsonb);
    raise exception 'staff closed financial day';
  exception when others then if sqlerrm not in ('forbidden','shop_unavailable') then raise; end if; end;
  -- A discrepant physical count is accepted as an observation, never as a close.
  v_result := public.submit_closing_count_v1('a4100000-0000-4000-8000-000000000003',v_id,
    '{"stock":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"count":"4","milligrams":null}],"scrap":[{"karat":21,"milligrams":"1000"}]}'::jsonb);
  v_replay := public.submit_closing_count_v1('a4100000-0000-4000-8000-000000000003',v_id,
    '{"stock":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"count":"4","milligrams":null}],"scrap":[{"karat":21,"milligrams":"1000"}]}'::jsonb);
  if v_result->>'ok'<>'true' or v_replay->>'replayed'<>'true' or (public.get_my_closing_task_v1())->>'state'<>'unassigned' then raise exception 'submission did not revoke form or replay'; end if;
  if (public.get_closing_delegation_status_v1('a4100000-0000-4000-8000-000000000003'))->>'status'<>'confirmed' then raise exception 'staff reconciliation missing'; end if;
  begin perform public.submit_closing_count_v1('a4100000-0000-4000-8000-000000000004',v_id,
    '{"stock":[],"scrap":[]}'::jsonb); raise exception 'submitted form remained writable';
  exception when others then if sqlerrm<>'task_unavailable' then raise; end if; end;
end; $staff_boundary$;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000002',true);
do $other_owner$ declare v_result jsonb; begin
  v_result := public.list_closing_staff_v1();
  if v_result->'staff'<>'[]'::jsonb or v_result->'tasks'<>'[]'::jsonb then raise exception 'cross shop staff data leak'; end if;
  begin perform public.close_daily_ledger_from_staff_v1('a4100000-0000-4000-8000-000000000010',(select task_id from staff_test_ids),'{}'::jsonb);
    raise exception 'other owner closed assigned day';
  exception when others then if sqlerrm<>'task_unavailable' then raise; end if; end;
end; $other_owner$;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000001',true);
do $owner_review$ declare v_result jsonb; v_next jsonb; v_version bigint;
begin
  v_result := public.close_daily_ledger_from_staff_v1('a4100000-0000-4000-8000-000000000011',(select task_id from staff_test_ids),
    '{"cash":"100000","instant_transfer":"0","wallet":"0","card":"0"}'::jsonb);
  if v_result->>'reason'<>'count_mismatch' or (public.get_daily_ledger_day_state())->>'state'<>'open' then raise exception 'owner discrepant count closed day'; end if;
  v_next := public.mutate_closing_delegation_v1('a4100000-0000-4000-8000-000000000012','assign',(select staff_id from staff_test_ids),(select day_id from staff_test_ids),2);
  update staff_test_ids set second_task=(v_next->>'task_id')::uuid;
end; $owner_review$;
select set_config('request.jwt.claim.sub',(select user_id::text from staff_test_ids),true);
select public.submit_closing_count_v1('a4100000-0000-4000-8000-000000000013',(select second_task from staff_test_ids),
  '{"stock":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"count":"5","milligrams":null}],"scrap":[{"karat":21,"milligrams":"1000"}]}'::jsonb);
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000001',true);
do $owner_close$ declare v_result jsonb; v_replay jsonb; begin
  v_result := public.close_daily_ledger_from_staff_v1('a4100000-0000-4000-8000-000000000014',(select second_task from staff_test_ids),
    '{"cash":"100000","instant_transfer":"0","wallet":"0","card":"0"}'::jsonb);
  v_replay := public.close_daily_ledger_from_staff_v1('a4100000-0000-4000-8000-000000000014',(select second_task from staff_test_ids),
    '{"cash":"100000","instant_transfer":"0","wallet":"0","card":"0"}'::jsonb);
  if v_result->>'ok'<>'true' or v_replay->>'replayed'<>'true' then raise exception 'owner reviewed close or retry failed %',v_result; end if;
end; $owner_close$;
reset role;
do $audit$ begin
  if exists(select 1 from public.shop_memberships where user_id=(select user_id from staff_test_ids))
    or (select count(*) from public.closing_staff_accounts)<>1
    or (select count(*) from public.financial_operations where kind='close_day' and shop_id='c2900000-0000-4000-8000-000000000001')<>1
    or not exists(select 1 from public.closing_delegation_audit where action='count_submitted' and actor_user_id=(select user_id from staff_test_ids))
    or not exists(select 1 from public.closing_delegation_audit where action='owner_closed' and actor_user_id='c1900000-0000-4000-8000-000000000001') then raise exception 'staff/owner audit or membership boundary'; end if;
end; $audit$;
rollback;

-- U18 (device pass 2026-11-11): the report day list carries closed_at_shop,
-- null for the open day and the server close time once closed. Rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('f5000000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'report-days-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('f5000000-0000-4000-8000-0000000000a1', 'متجر الدفاتر', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('f5000000-0000-4000-8000-0000000000a1', 'f5000000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('f5000000-0000-4000-8000-0000000000a1', now() - interval '1 day', now() + interval '30 days');

do $priv$
begin
  if has_function_privilege('authenticated', 'public.list_financial_report_days_v1_before_staff()', 'execute') then
    raise exception 'inner_report_days_granted';
  end if;
end;
$priv$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f5000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'f5000000-0000-4000-8000-000000000100',
  '{"version":1,"cash":{"cash":"100000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
);

do $days$
declare
  v_day jsonb;
begin
  select item into v_day
  from jsonb_array_elements(public.list_financial_report_days_v1() -> 'days') as item
  limit 1;
  if v_day ->> 'status' is distinct from 'open'
    or not (v_day ? 'closed_at_shop')
    or jsonb_typeof(v_day -> 'closed_at_shop') is distinct from 'null' then
    raise exception 'open_day_closed_at %', v_day;
  end if;
end;
$days$;

reset role;
update public.business_days set status = 'closed', closed_at = '2026-11-08 19:45:00+00'
where shop_id = 'f5000000-0000-4000-8000-0000000000a1';
set local role authenticated;

do $closed$
declare
  v_day jsonb;
begin
  select item into v_day
  from jsonb_array_elements(public.list_financial_report_days_v1() -> 'days') as item
  limit 1;
  -- Cairo is UTC+2 in November.
  if v_day ->> 'closed_at_shop' is distinct from '2026-11-08 21:45:00' then
    raise exception 'closed_day_closed_at %', v_day;
  end if;
end;
$closed$;

rollback;

-- Dedicated disposable local database only. Committed synthetic rows enable
-- a real two-connection race; the runner never connects this to a hosted DB.
do $guard$ begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet or current_database() !~ '^eldaftar_owner_meeting_[a-z0-9_]+$'
    then raise exception 'dedicated local database required'; end if;
end; $guard$;
begin;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)
values ('e1900000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','race@example.test',false,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone)
values ('e2900000-0000-4000-8000-000000000001','اختبار التزامن','مالك تجريبي','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role)
values ('e2900000-0000-4000-8000-000000000001','e1900000-0000-4000-8000-000000000001','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
values ('e2900000-0000-4000-8000-000000000001',now()-interval '1 day',now()+interval '10 days');
set local role authenticated;
select set_config('request.jwt.claim.sub','e1900000-0000-4000-8000-000000000001',true);
select public.confirm_opening_balances('e3900000-0000-4000-8000-000000000001','{"version":1,"cash":{"cash":"10000"},"stock":[],"scrap":[]}'::jsonb);
commit;

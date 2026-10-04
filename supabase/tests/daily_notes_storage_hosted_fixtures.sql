-- Reviewed synthetic HTTP setup; use only after explicit approval.
-- Replace these UUID tokens from the HTTP runner manifest; reject non-UUID values.
-- Never use existing account/shop IDs. No financial RPC or journal is created.
begin;
set local lock_timeout='3s';
do $target$
begin
  if current_database()<>'postgres'
    or (select system_identifier::text from pg_control_system())<>'7678071634733212629' then
    raise exception 'wrong project for synthetic Storage fixtures';
  end if;
  if exists(select 1 from public.shops where id in ('__SHOP__'::uuid,'__OTHER_SHOP__'::uuid)) then
    raise exception 'synthetic shop collision';
  end if;
  if (select count(*) from auth.users where id in ('__OWNER__'::uuid,'__OTHER_OWNER__'::uuid)
    and email like 'notes-storage-%@example.test')<>2 then
    raise exception 'synthetic Auth owners required';
  end if;
end;
$target$;
insert into public.shops(id,name,owner_display_name,time_zone) values
  ('__SHOP__','متجر اختبار التخزين المؤقت','مالك الاختبار','Africa/Cairo'),
  ('__OTHER_SHOP__','متجر اختبار العزل المؤقت','مالك الاختبار الآخر','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values
  ('__SHOP__','__OWNER__','owner'),('__OTHER_SHOP__','__OTHER_OWNER__','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at) values
  ('__SHOP__',now()-interval '1 day',now()+interval '1 day'),
  ('__OTHER_SHOP__',now()-interval '1 day',now()+interval '1 day');
insert into public.business_days(id,shop_id,business_date,opened_at,status,day_version)
values('__DAY__','__SHOP__',(now() at time zone 'Africa/Cairo')::date,now(),'open',1);
commit;

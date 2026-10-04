-- Run ONLY after exact-path Storage API cleanup. Auth users are then deleted
-- through Auth admin API, after global sign-out. Never delete Storage metadata.
begin;
set local lock_timeout='3s';
do $target$
begin
  if current_database()<>'postgres'
    or (select system_identifier::text from pg_control_system())<>'7678071634733212629' then
    raise exception 'wrong project for synthetic Storage cleanup';
  end if;
  if (select count(*) from public.shops where id in ('__SHOP__'::uuid,'__OTHER_SHOP__'::uuid)
    and name in ('متجر اختبار التخزين المؤقت','متجر اختبار العزل المؤقت'))<>2 then
    raise exception 'synthetic shop identity mismatch';
  end if;
  if exists(select 1 from storage.objects where bucket_id='eldafttar-private-notes'
    and name like '__SHOP__/%') then
    raise exception 'Storage API cleanup required first';
  end if;
  if exists(select 1 from public.financial_operations where shop_id in ('__SHOP__'::uuid,'__OTHER_SHOP__'::uuid)) then
    raise exception 'refusing cleanup of shop with financial operations';
  end if;
end;
$target$;
delete from public.business_days where id='__DAY__' and shop_id='__SHOP__';
delete from public.shop_entitlements where shop_id in ('__SHOP__','__OTHER_SHOP__');
delete from public.shop_memberships where (shop_id='__SHOP__' and user_id='__OWNER__')
  or (shop_id='__OTHER_SHOP__' and user_id='__OTHER_OWNER__');
delete from public.shops where id in ('__SHOP__','__OTHER_SHOP__');
commit;

-- CRM-02 fixtures. Synthetic rows roll back. Customer commands must not post
-- cash, stock, debt, or business-day changes, and must not rewrite invoices.
begin;

-- Trade edit/delete revokes authenticated EXECUTE on return and exchange
-- writers. This fixture restores that privilege only inside this rolled-back
-- transaction so historic return math still runs. It is not a production grant.
grant execute on function public.post_daily_ledger_return(uuid, uuid, text) to authenticated;
grant execute on function public.post_linked_return_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_exchange_v1(uuid, jsonb) to authenticated;

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

-- Synthetic CRM-02 behavior, preservation and access checks; all rolled back.
create function pg_temp.financial_fingerprint() returns text language sql security definer set search_path='' as $f$
 select md5(jsonb_build_array(
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.financial_operations t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.financial_operation_details t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.financial_audit_events t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.journal_postings t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.journals t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.inventory_lots t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.inventory_lot_movements t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.inventory_receipts t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.purchase_cash_payables t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.gold_obligations t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.repairs t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.repair_events t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.shop_debts t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.debt_events t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.invoice_dispatch_confirmations t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.business_days t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.shop_sync_signals t)
 )::text);
$f$;
create function pg_temp.stats(p_id uuid) returns jsonb language plpgsql as $f$
declare before text; result jsonb;
begin
 before:=pg_temp.financial_fingerprint();
 result:=public.get_customer_v2(p_id,20,null,20,null,20,null)->'statistics';
 if pg_temp.financial_fingerprint() is distinct from before then raise exception 'statistics_mutated_financial_history';end if;
 return result;
end;
$f$;
create function pg_temp.weight(s jsonb,k integer,d text) returns text language sql as $f$
 select w->>d from jsonb_array_elements(s->'weights') w where (w->>'karat')::integer=k;
$f$;
create function pg_temp.line(k integer,m text,c text,category text default 'worked_jewelry') returns jsonb language sql as $f$
 select jsonb_build_object('category',category,'karat',k,'milligrams',m,'count',c,'item_name','صنف اصطناعي','line_price_piastres',null);
$f$;
create function pg_temp.trade(kind text,items jsonb,total text) returns jsonb language sql as $f$
 select jsonb_build_object('version',1,'kind',kind,'total_piastres',total,'tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres',total)),
 'items',items,'description','','customer_name','طرف اصطناعي متطابق','customer_phone','','note','');
$f$;
create function pg_temp.link(c jsonb,op uuid,kind text default 'customer_link') returns jsonb language plpgsql as $f$
declare payload jsonb:=jsonb_build_object('version',1,'kind',kind,'customer_id',c->>'customer_id','expected_version',c->>'record_version','operation_id',op);
begin
 if kind='customer_link' then return public.post_customer_link_v1(gen_random_uuid(),payload);end if;
 return public.post_customer_unlink_v1(gen_random_uuid(),payload);
end;$f$;
create function pg_temp.returned(op uuid,kind text,items jsonb,total text) returns jsonb language plpgsql as $f$
declare day uuid; version bigint;
begin
 select d.id,d.day_version into day,version from public.business_days d where d.shop_id='c1222222-2222-4222-8222-222222222222' and d.status='open';
 return public.post_linked_return_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind',kind,'original_operation_id',op,'expected_day_id',day,'expected_day_version',version::text,'note','مرتجع اصطناعي','items',items,'consideration_piastres',total,'tenders',jsonb_build_array(jsonb_build_object('method','cash','piastres',total))));
end;$f$;
set local role authenticated;
select set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
select set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"c1818181-8181-4181-8181-818181818181","is_anonymous":false}',true);
do $behavior$
declare c jsonb; c2 jsonb; c3 jsonb; id uuid; second uuid; s jsonb; sale uuid; purchase uuid; r jsonb;
 day uuid; version bigint; replacement uuid; returned uuid; ledger bigint; crm bigint; cursor_value text;
begin
 perform public.confirm_opening_balances(gen_random_uuid(),'{"version":1,"cash":{"cash":"500000"},"stock":[{"category":"worked_jewelry","karat":14,"milligrams":"5000","count":"4"},{"category":"worked_jewelry","karat":18,"milligrams":"30000","count":"20"},{"category":"worked_jewelry","karat":21,"milligrams":"30000","count":"10"},{"category":"worked_jewelry","karat":22,"milligrams":"10000","count":"5"},{"category":"bullion","karat":24,"milligrams":"20000","count":"5"}],"scrap":[]}'::jsonb);
 c:=public.post_customer_create_v1(gen_random_uuid(),pg_temp.create_payload('عميل إحصائيات أول','[]',false,false));id:=(c->>'customer_id')::uuid;
 c2:=public.post_customer_create_v1(gen_random_uuid(),pg_temp.create_payload('عميل إحصائيات ثان','[]',false,false));second:=(c2->>'customer_id')::uuid;
 c3:=public.post_customer_create_v1(gen_random_uuid(),pg_temp.create_payload('عميل مرتجع كامل','[]',false,false));
 s:=pg_temp.stats(id);
 if s->>'bought_count'<>'0' or s->>'sold_count'<>'0' or s->'last_operation'<>'null'::jsonb or jsonb_array_length(s->'weights')<>5 then raise exception 'zero_history';end if;
 sale:=(public.post_daily_ledger_trade(gen_random_uuid(),pg_temp.trade('sale',jsonb_build_array(pg_temp.line(14,'1111','1'),pg_temp.line(18,'1001','1'),pg_temp.line(18,'2000','1'),pg_temp.line(21,'10000','3'),pg_temp.line(22,'2222','1'),pg_temp.line(24,'4004','2','bullion')),'10000'))->>'operation_id')::uuid;
 purchase:=(public.post_daily_ledger_trade(gen_random_uuid(),pg_temp.trade('purchase',jsonb_build_array(pg_temp.line(21,'1001',null,'scrap'),pg_temp.line(21,'254',null,'scrap'),pg_temp.line(24,'1',null,'scrap')),'1000'))->>'operation_id')::uuid;
 if pg_temp.stats(id)->>'bought_count'<>'0' then raise exception 'implicit_attribution';end if;
 c:=pg_temp.link(c,sale);c:=pg_temp.link(c,purchase);s:=pg_temp.stats(id);
 if s->>'bought_count'<>'1' or s->>'sold_count'<>'1'
  or pg_temp.weight(s,14,'bought_milligrams')<>'1111' or pg_temp.weight(s,18,'bought_milligrams')<>'3001'
  or pg_temp.weight(s,21,'bought_milligrams')<>'10000' or pg_temp.weight(s,22,'bought_milligrams')<>'2222'
  or pg_temp.weight(s,24,'bought_milligrams')<>'4004' or pg_temp.weight(s,21,'sold_milligrams')<>'1255'
  or pg_temp.weight(s,24,'sold_milligrams')<>'1' then raise exception 'mixed_precision_or_counts';end if;
 select ledger_revision,customer_revision into ledger,crm from public.shop_sync_signals where shop_id='c1222222-2222-4222-8222-222222222222';
 r:=pg_temp.returned(sale,'sale_return','[{"item_index":"3","milligrams":"4000","count":"1"}]','4000');s:=pg_temp.stats(id);
 if pg_temp.weight(s,21,'bought_milligrams')<>'6000' or s->>'bought_count'<>'1' or s->'last_operation'->>'operation_id'<>r->>'operation_id' then raise exception 'partial_return_or_last_activity';end if;
 if (select ledger_revision<=ledger or customer_revision<>crm from public.shop_sync_signals where shop_id='c1222222-2222-4222-8222-222222222222') then raise exception 'financial_refresh_scope';end if;
 select d.id,d.day_version into day,version from public.business_days d where d.shop_id='c1222222-2222-4222-8222-222222222222' and d.status='open';
 r:=public.post_exchange_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','exchange','expected_day_id',day,'expected_day_version',version::text,'note','استبدال اصطناعي',
 'return',jsonb_build_object('kind','sale_return','original_operation_id',sale,'note','','items','[{"item_index":"3","milligrams":"6000","count":"2"}]'::jsonb,'consideration_piastres','6000','tenders','[{"method":"cash","piastres":"6000"}]'::jsonb),
 'replacement',pg_temp.trade('sale',jsonb_build_array(pg_temp.line(18,'3000','1')),'2000')));
 replacement:=(r->>'replacement_operation_id')::uuid;returned:=(r->>'return_operation_id')::uuid;
 if replacement is null or returned is null then raise exception 'exchange_fixture_contract';end if;
 s:=pg_temp.stats(id);
 if pg_temp.weight(s,21,'bought_milligrams')<>'0' or pg_temp.weight(s,18,'bought_milligrams')<>'3001' or s->>'bought_count'<>'1' or s->'last_operation'->>'operation_id'<>returned::text then raise exception 'implicit_exchange_replacement';end if;
 c2:=pg_temp.link(c2,replacement);
 if pg_temp.weight(pg_temp.stats(second),18,'bought_milligrams')<>'3000' or pg_temp.stats(second)->>'bought_count'<>'1' then raise exception 'separate_replacement_link';end if;
 perform pg_temp.returned(purchase,'purchase_return','[{"item_index":"0","milligrams":"501"}]','400');
 if pg_temp.weight(pg_temp.stats(id),21,'sold_milligrams')<>'754' then raise exception 'purchase_partial';end if;
 r:=pg_temp.returned(purchase,'purchase_return','[{"item_index":"0","milligrams":"500"},{"item_index":"1","milligrams":"254"},{"item_index":"2","milligrams":"1"}]','600');s:=pg_temp.stats(id);
 if pg_temp.weight(s,21,'sold_milligrams')<>'0' or pg_temp.weight(s,24,'sold_milligrams')<>'0' or s->>'sold_count'<>'1' then raise exception 'purchase_full_count';end if;
 c:=pg_temp.link(c,purchase,'customer_unlink');
 if pg_temp.stats(id)->>'sold_count'<>'0' then raise exception 'unlink_retained_return';end if;
 c2:=pg_temp.link(c2,purchase);
 if pg_temp.stats(second)->>'sold_count'<>'1' or pg_temp.weight(pg_temp.stats(second),21,'sold_milligrams')<>'0' or pg_temp.stats(second)->'last_operation'->>'operation_id'<>r->>'operation_id' then raise exception 'relink_return_attribution';end if;
 c2:=public.post_customer_archive_v1(gen_random_uuid(),jsonb_build_object('version',1,'kind','customer_archive','customer_id',second,'expected_version',c2->>'record_version'));
 if pg_temp.stats(second)->>'bought_count'<>'1' then raise exception 'archived_summary';end if;
 if public.get_customer_v1(id,20,null,20,null,20,null) ? 'statistics' or c ? 'statistics' then raise exception 'v1_shape_changed';end if;
 cursor_value:=public.get_customer_list_v2('','last_operation','all',1,null)->>'next_cursor';
 if cursor_value is null or jsonb_array_length(public.get_customer_list_v2('','last_operation','all',1,cursor_value)->'items')<>1 then raise exception 'v2_pagination';end if;
 perform pg_temp.expect_code(format('select public.get_customer_list_v1(%L,%L,%L,20,%L)','','last_operation','all',cursor_value),'invalid_cursor');
 perform pg_temp.expect_code(format('select public.get_customer_list_v2(%L,%L,%L,20,%L)','different','last_operation','all',cursor_value),'invalid_cursor');
 sale:=(public.post_daily_ledger_trade(gen_random_uuid(),pg_temp.trade('sale',jsonb_build_array(pg_temp.line(18,'1000','1')),'1000'))->>'operation_id')::uuid;
 c3:=pg_temp.link(c3,sale);
 perform public.post_daily_ledger_return(gen_random_uuid(),sale,'مرتجع كامل');s:=pg_temp.stats((c3->>'customer_id')::uuid);
 if pg_temp.weight(s,18,'bought_milligrams')<>'0' or s->>'bought_count'<>'1' then raise exception 'legacy_full_return';end if;
 perform pg_temp.crm_entitlement(true);
 if pg_temp.stats(id)->>'bought_count'<>'1' then raise exception 'expired_read_denied';end if;
 perform pg_temp.crm_entitlement(false);
end;$behavior$;
reset role;
do $evidence$
declare v_customer uuid; shop uuid:='c1222222-2222-4222-8222-222222222222'; actor uuid:='c1111111-1111-4111-8111-111111111111';
 day uuid; op uuid; before jsonb; kind text; last_at text;
begin
 select c.id into v_customer from public.customers c where c.shop_id=shop and c.display_name='عميل إحصائيات أول';
 select d.id into day from public.business_days d where d.shop_id=shop and d.status='open';
 before:=private.customer_statistics(shop,v_customer,'Africa/Cairo');
 foreach kind in array array['sale','expense','sale_return'] loop
  op:=private.insert_operation(shop,kind,day,actor,clock_timestamp(),jsonb_build_object('version',1,'kind',kind,
    'items',jsonb_build_array(pg_temp.line(18,'1','1')),'original_operation_id',
    (select l.operation_id from public.customer_operation_links l where l.customer_id=v_customer and l.status='active' limit 1)));
  if kind='expense' then
   insert into public.financial_audit_events(shop_id,actor_user_id,action,operation_id,created_at,details)
   values(shop,actor,'expense_confirmed',op,clock_timestamp(),'{}');
  end if;
  if kind<>'sale_return' then
   insert into public.customer_operation_links(shop_id,customer_id,operation_id,status,linked_at,linked_by)
   values(shop,v_customer,op,'active',clock_timestamp(),actor);
  end if;
 end loop;
 if private.customer_statistics(shop,v_customer,'Africa/Cairo') is distinct from before then raise exception 'nonconfirmed_or_wrong_kind_included';end if;
 -- Check changed zones/day boundaries against the actual relevant operation instant.
 last_at:=before->'last_operation'->>'operation_created_at';
 if private.customer_statistics(shop,v_customer,'Asia/Dubai')->'last_operation'->>'operation_created_at_shop'
  is distinct from private.customer_local(last_at::timestamptz,'Asia/Dubai') then raise exception 'statistics_zone_change';end if;
 if private.customer_local('2026-10-13 21:30:00+00','Africa/Cairo')<>'2026-10-14T00:30:00'
  or private.customer_local('2026-01-13 21:30:00+00','Africa/Cairo')<>'2026-01-13T23:30:00' then raise exception 'statistics_day_boundary';end if;
end;$evidence$;
do $boundaries$
declare id uuid; sql text; actor text;
begin
 select c.id into id from public.customers c where c.shop_id='c1222222-2222-4222-8222-222222222222' and c.display_name='عميل إحصائيات أول';
 sql:=format('select public.get_customer_v2(%L::uuid,20,null,20,null,20,null)',id);
 execute 'set local role authenticated';
 foreach actor in array array['c2111111-1111-4111-8111-111111111111','c3111111-1111-4111-8111-111111111111','c4111111-1111-4111-8111-111111111111','c5111111-1111-4111-8111-111111111111'] loop
  perform set_config('request.jwt.claim.sub',actor,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated','is_anonymous',actor='c4111111-1111-4111-8111-111111111111')::text,true);
  perform pg_temp.expect_code(sql,case when actor='c2111111-1111-4111-8111-111111111111' then 'not_found' else 'forbidden' end);
  if actor='c2111111-1111-4111-8111-111111111111' then
   if jsonb_array_length(public.get_customer_list_v2('','name','all',20,null)->'items')<>0 then raise exception 'cross_shop_list';end if;
  else
   perform pg_temp.expect_code($sql$select public.get_customer_list_v2('','name','all',20,null)$sql$,'forbidden');
  end if;
 end loop;
 perform set_config('request.jwt.claim.sub','c1111111-1111-4111-8111-111111111111',true);
 perform set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"c1818181-8181-4181-8181-818181818182","is_anonymous":false}',true);
 perform pg_temp.expect_code(sql,'session_expired');
 perform set_config('request.jwt.claims','{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"cf818181-8181-4181-8181-818181818182","is_anonymous":false}',true);
 perform pg_temp.expect_code(sql,'session_expired');
 perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claims','{}',true);
 perform pg_temp.expect_code(sql,'unauthenticated');
 perform pg_temp.expect_code($sql$select public.get_customer_list_v2('','name','all',20,null)$sql$,'unauthenticated');
 execute 'reset role';
 if has_function_privilege('anon','public.get_customer_list_v2(text,text,text,integer,text)','execute') or has_function_privilege('authenticated','private.customer_statistics(uuid,uuid,text)','execute') then raise exception 'statistics_privilege_leak';end if;
end;$boundaries$;
set constraints all immediate;
rollback;

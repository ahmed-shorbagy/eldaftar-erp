begin;
select pg_catalog.set_config('request.jwt.claims','{}',true);
do $check$
declare r record;
begin
  for r in select c.relname,c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('ledger_trade_changes','ledger_trade_change_audits')
  loop
    if not r.relrowsecurity then raise exception 'rls_missing'; end if;
    if (select count(*) from pg_policies where schemaname='public' and tablename=r.relname and cmd='SELECT' and roles=array['authenticated']::name[]) <> 1 then raise exception 'owner_policy_missing'; end if;
  end loop;
  if (select provolatile from pg_proc where oid='public.get_ledger_date_v1(date,text,integer)'::regprocedure) <> 's' then raise exception 'date_snapshot_not_stable'; end if;
end $check$;
set local role authenticated;
do $check$
declare t text; q text;
begin
  foreach t in array array['ledger_trade_changes','ledger_trade_change_audits'] loop
    if not has_table_privilege(current_user,'public.'||t,'select')
       or has_table_privilege(current_user,'public.'||t,'insert')
       or has_table_privilege(current_user,'public.'||t,'update')
       or has_table_privilege(current_user,'public.'||t,'delete') then raise exception 'bad_table_privilege'; end if;
  end loop;
  if exists(select 1 from public.ledger_trade_changes) or exists(select 1 from public.ledger_trade_change_audits) then raise exception 'unscoped_rows_visible'; end if;
  foreach t in array array[
    'public.post_daily_ledger_return(uuid,uuid,text)',
    'public.post_linked_return_v1(uuid,jsonb)','public.post_exchange_v1(uuid,jsonb)',
    'public.get_daily_ledger_v2_before_trade_cache()',
    'public.get_daily_ledger_v2_before_trade_change()',
    'public.get_daily_ledger_operation_before_trade_change(uuid)',
    'public.get_invoice_brand_source_v1_before_trade_change(uuid)',
    'public.get_invoice_message_source_v1_before_trade_change(uuid)',
    'public.get_invoice_dispatch_state_before_trade_change(uuid)'
  ] loop
    if has_function_privilege(current_user,t,'execute') then raise exception 'legacy_or_wrapper_execute_allowed: %',t; end if;
  end loop;
  foreach q in array array[
    'select public.get_ledger_date_v1()',
    'select public.get_daily_ledger_v2()',
    'select public.review_ledger_trade_change_v1(null,''delete'',null)',
    'select public.post_ledger_trade_change_v1(null,null,''delete'',null,null,null,null,null)'
  ] loop
    begin execute q; raise exception 'accepted_without_identity'; exception when others then
      if sqlerrm <> 'unauthenticated' then raise; end if;
    end;
  end loop;
end $check$;
set local role anon;
do $check$
declare t text;
begin
  foreach t in array array['public.get_ledger_date_v1(date,text,integer)',
    'public.review_ledger_trade_change_v1(uuid,text,jsonb)',
    'public.post_ledger_trade_change_v1(uuid,uuid,text,jsonb,uuid,bigint,text,text)'] loop
    if has_function_privilege(current_user,t,'execute') then raise exception 'anonymous_execute_allowed'; end if;
  end loop;
end $check$;
reset role;
rollback;
select 'HOSTED_LEDGER_AUTHORIZATION_GATES_PASSED' as gate;

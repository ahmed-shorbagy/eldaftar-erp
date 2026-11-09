-- Owner overview figures for «بيانات العملاء» (ADR 0043).
-- Counts are text. Partners and employees stay forbidden: this read uses the
-- same shop check as get_customer_list_v3 and does not set a staff permission.

begin;

create function public.get_customer_overview_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_active text;
  v_vip text;
  v_recent text;
  v_open text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  v_shop := private.opening_require_reader_shop();
  select count(*)::text into v_active
  from public.customers as customer
  where customer.shop_id = v_shop and customer.status = 'active';
  select count(*)::text into v_vip
  from public.customers as customer
  where customer.shop_id = v_shop
    and customer.status = 'active'
    and customer.is_vip;
  select count(*)::text into v_open
  from public.customers as customer
  where customer.shop_id = v_shop
    and customer.status = 'active'
    and customer.has_open_request;
  select count(*)::text into v_recent
  from public.customers as customer
  where customer.shop_id = v_shop
    and customer.status = 'active'
    and exists (
      select 1
      from public.customer_operation_links as link
      join public.financial_operations as operation
        on operation.shop_id = link.shop_id
       and operation.id = link.operation_id
      where link.shop_id = customer.shop_id
        and link.customer_id = customer.id
        and link.status = 'active'
        and not private.ledger_trade_hidden(link.shop_id, link.operation_id)
        and operation.created_at >= pg_catalog.now() - interval '30 days'
    );
  return pg_catalog.jsonb_build_object(
    'active_count', v_active,
    'vip_count', v_vip,
    'active_30_days', v_recent,
    'open_request_count', v_open
  );
end;
$fn$;

revoke all on function public.get_customer_overview_v1() from public, anon;
grant execute on function public.get_customer_overview_v1() to authenticated;

notify pgrst, 'reload schema';
commit;

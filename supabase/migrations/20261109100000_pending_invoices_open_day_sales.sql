-- Pending invoices are unsent sales of the open day only (ADR 0042, A-D3).
begin;

create or replace function public.get_pending_invoice_sends(
  p_before_sequence bigint default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_items jsonb;
  v_next bigint;
  v_more boolean;
begin
  v_shop := private.opening_require_reader_shop();
  if p_before_sequence is not null and p_before_sequence < 1 then
    raise exception 'invalid_input';
  end if;
  with page as (
    select
      operation.id, operation.kind, operation.shop_sequence,
      operation.created_at, detail.payload ->> 'customer_name' as customer_name
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    left join public.invoice_dispatch_confirmations as dispatch
      on dispatch.shop_id = operation.shop_id and dispatch.operation_id = operation.id
    where operation.shop_id = v_shop
      and operation.kind = 'sale'
      and operation.business_day_id in (
        select day.id
        from public.business_days as day
        where day.shop_id = v_shop and day.status = 'open'
      )
      and dispatch.operation_id is null
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      and (p_before_sequence is null or operation.shop_sequence < p_before_sequence)
    order by operation.shop_sequence desc
    limit 51
  ), numbered as (
    select page.*, pg_catalog.row_number() over (order by page.shop_sequence desc) as row_no
    from page
  )
  select
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'operation_id', numbered.id,
      'kind', numbered.kind,
      'shop_sequence', numbered.shop_sequence::text,
      'occurred_at_cairo', pg_catalog.to_char(
        numbered.created_at at time zone 'Africa/Cairo',
        'YYYY-MM-DD"T"HH24:MI:SS'
      ),
      'customer_name', coalesce(numbered.customer_name, '')
    ) order by numbered.shop_sequence desc)
      filter (where numbered.row_no <= 50), '[]'::jsonb),
    min(numbered.shop_sequence) filter (where numbered.row_no <= 50),
    coalesce(bool_or(numbered.row_no = 51), false)
  into v_items, v_next, v_more
  from numbered;
  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'next_before_sequence', case when v_more then v_next else null end
  );
end;
$fn$;

revoke all on function public.get_pending_invoice_sends(bigint) from public, anon;
grant execute on function public.get_pending_invoice_sends(bigint) to authenticated;

comment on function public.get_pending_invoice_sends(bigint) is
  'Unsent sales of the open day only. Purchases and closed days stay out (ADR 0042).';

notify pgrst, 'reload schema';
commit;

-- Allow staff into grant-covered RPCs via app.required_shop_permission GUC.
-- Employee ledger reads filter to own operations and omit shop balances.

begin;

-- Trade v2
alter function public.post_daily_ledger_trade_v2(uuid, jsonb)
  rename to post_daily_ledger_trade_v2_before_staff;
revoke all on function public.post_daily_ledger_trade_v2_before_staff(uuid, jsonb)
  from public, anon, authenticated;

create function public.post_daily_ledger_trade_v2(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_kind text;
  v_perm text;
begin
  v_kind := p_payload ->> 'kind';
  v_perm := case
    when v_kind in ('sale', 'scrap_sale') then 'sale'
    when v_kind = 'purchase' then 'purchase'
    when v_kind = 'expense' then 'expense'
    else null
  end;
  if v_perm is null then raise exception 'invalid_input'; end if;
  perform private.allow_member_permission(v_perm);
  return public.post_daily_ledger_trade_v2_before_staff(p_idempotency_key, p_payload);
end;
$fn$;

revoke all on function public.post_daily_ledger_trade_v2(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_trade_v2(uuid, jsonb) to authenticated;

-- Cash transfer / scrap-to-stock / return → expense or inventory / sale-purchase
alter function public.post_daily_ledger_cash_transfer(uuid, jsonb)
  rename to post_daily_ledger_cash_transfer_before_staff;
revoke all on function public.post_daily_ledger_cash_transfer_before_staff(uuid, jsonb)
  from public, anon, authenticated;

create function public.post_daily_ledger_cash_transfer(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('expense');
  return public.post_daily_ledger_cash_transfer_before_staff(p_idempotency_key, p_payload);
end;
$fn$;
revoke all on function public.post_daily_ledger_cash_transfer(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_cash_transfer(uuid, jsonb) to authenticated;

alter function public.post_daily_ledger_scrap_to_stock(uuid, jsonb)
  rename to post_daily_ledger_scrap_to_stock_before_staff;
revoke all on function public.post_daily_ledger_scrap_to_stock_before_staff(uuid, jsonb)
  from public, anon, authenticated;

create function public.post_daily_ledger_scrap_to_stock(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('inventory');
  return public.post_daily_ledger_scrap_to_stock_before_staff(p_idempotency_key, p_payload);
end;
$fn$;
revoke all on function public.post_daily_ledger_scrap_to_stock(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_scrap_to_stock(uuid, jsonb) to authenticated;

alter function public.post_daily_ledger_return(uuid, uuid, text)
  rename to post_daily_ledger_return_before_staff;
revoke all on function public.post_daily_ledger_return_before_staff(uuid, uuid, text)
  from public, anon, authenticated;

create function public.post_daily_ledger_return(
  p_idempotency_key uuid, p_original_operation_id uuid, p_note text
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_shop uuid;
begin
  -- Peek original kind as owner/member: temporarily allow ledger_read then map grant.
  perform private.allow_member_permission('ledger_read');
  v_shop := private.opening_require_reader_shop();
  select operation.kind into v_kind
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_original_operation_id;
  if v_kind = 'purchase' then
    perform private.allow_member_permission('purchase');
  elsif v_kind in ('sale', 'scrap_sale') then
    perform private.allow_member_permission('sale');
  else
    raise exception 'forbidden';
  end if;
  return public.post_daily_ledger_return_before_staff(
    p_idempotency_key, p_original_operation_id, p_note
  );
end;
$fn$;
revoke all on function public.post_daily_ledger_return(uuid, uuid, text) from public, anon;
grant execute on function public.post_daily_ledger_return(uuid, uuid, text) to authenticated;

-- Inventory command wrappers
create or replace function public.post_inventory_addition_v1(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_addition' then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission('inventory');
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create or replace function public.post_inventory_removal_v1(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_removal' then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission('inventory');
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create or replace function public.post_inventory_correction_v1(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_correction' then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission('inventory');
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create or replace function public.post_inventory_conversion_v1(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_conversion' then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission('inventory');
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

-- Invoice send
alter function public.confirm_invoice_whatsapp_send(uuid, uuid)
  rename to confirm_invoice_whatsapp_send_before_staff;
revoke all on function public.confirm_invoice_whatsapp_send_before_staff(uuid, uuid)
  from public, anon, authenticated;

create function public.confirm_invoice_whatsapp_send(
  p_operation_id uuid, p_idempotency_key uuid
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('invoice_send');
  return public.confirm_invoice_whatsapp_send_before_staff(
    p_operation_id, p_idempotency_key
  );
end;
$fn$;
revoke all on function public.confirm_invoice_whatsapp_send(uuid, uuid) from public, anon;
grant execute on function public.confirm_invoice_whatsapp_send(uuid, uuid) to authenticated;

-- Reports
alter function public.list_financial_report_days_v1()
  rename to list_financial_report_days_v1_before_staff;
revoke all on function public.list_financial_report_days_v1_before_staff()
  from public, anon, authenticated;

create function public.list_financial_report_days_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('reports');
  return public.list_financial_report_days_v1_before_staff();
end;
$fn$;
revoke all on function public.list_financial_report_days_v1() from public, anon;
grant execute on function public.list_financial_report_days_v1() to authenticated;

alter function public.get_financial_day_report_v1(uuid)
  rename to get_financial_day_report_v1_before_staff;
revoke all on function public.get_financial_day_report_v1_before_staff(uuid)
  from public, anon, authenticated;

create function public.get_financial_day_report_v1(p_day_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
begin
  perform private.allow_member_permission('reports');
  v_result := public.get_financial_day_report_v1_before_staff(p_day_id);
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_role = 'employee' and v_result ? 'transactions' then
    v_result := jsonb_set(
      v_result,
      '{transactions}',
      coalesce((
        select jsonb_agg(item)
        from jsonb_array_elements(v_result -> 'transactions') as item
        where item ->> 'actor_user_id' = auth.uid()::text
      ), '[]'::jsonb)
    );
  end if;
  return v_result;
end;
$fn$;
revoke all on function public.get_financial_day_report_v1(uuid) from public, anon;
grant execute on function public.get_financial_day_report_v1(uuid) to authenticated;

alter function public.get_financial_week_report_v1(date)
  rename to get_financial_week_report_v1_before_staff;
revoke all on function public.get_financial_week_report_v1_before_staff(date)
  from public, anon, authenticated;

create function public.get_financial_week_report_v1(p_end_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('reports');
  return public.get_financial_week_report_v1_before_staff(p_end_date);
end;
$fn$;
revoke all on function public.get_financial_week_report_v1(date) from public, anon;
grant execute on function public.get_financial_week_report_v1(date) to authenticated;

-- Ledger reads
alter function public.get_daily_ledger_v2()
  rename to get_daily_ledger_v2_before_staff;
revoke all on function public.get_daily_ledger_v2_before_staff()
  from public, anon, authenticated;

create function public.get_daily_ledger_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
begin
  perform private.allow_member_permission('ledger_read');
  v_result := public.get_daily_ledger_v2_before_staff();
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_role = 'employee' then
    if v_result ->> 'state' is distinct from 'confirmed' then
      return v_result;
    end if;
    -- Employees may not see shop cash/gold totals.
    return jsonb_build_object(
      'state', 'confirmed',
      'employee_ledger', true,
      'shop_id', v_shop,
      'balances_hidden', true
    );
  end if;
  return v_result;
end;
$fn$;
revoke all on function public.get_daily_ledger_v2() from public, anon;
grant execute on function public.get_daily_ledger_v2() to authenticated;

alter function public.get_daily_ledger_home_v1()
  rename to get_daily_ledger_home_v1_before_staff;
revoke all on function public.get_daily_ledger_home_v1_before_staff()
  from public, anon, authenticated;

create function public.get_daily_ledger_home_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
  v_feed jsonb;
begin
  perform private.allow_member_permission('ledger_read');
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_role = 'employee' then
    -- Build a feed of the employee's own operations without shop balances.
    select coalesce(jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc), '[]'::jsonb)
      into v_feed
    from (
      select jsonb_build_object(
        'operation_id', operation.id,
        'shop_sequence', operation.shop_sequence::text,
        'kind', operation.kind,
        'created_at', operation.created_at,
        'actor_user_id', operation.actor_user_id
      ) as item
      from public.financial_operations as operation
      where operation.shop_id = v_shop
        and operation.actor_user_id = auth.uid()
        and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      order by operation.shop_sequence desc
      limit 100
    ) as rows;
    return jsonb_build_object(
      'state', 'confirmed',
      'employee_ledger', true,
      'balances_hidden', true,
      'shop_id', v_shop,
      'feed', v_feed,
      'feed_page', jsonb_build_object(
        'limit', 100,
        'has_more', false,
        'direction', 'desc'
      )
    );
  end if;
  v_result := public.get_daily_ledger_home_v1_before_staff();
  return v_result;
end;
$fn$;
revoke all on function public.get_daily_ledger_home_v1() from public, anon;
grant execute on function public.get_daily_ledger_home_v1() to authenticated;

alter function public.get_ledger_date_v1(date, text, integer)
  rename to get_ledger_date_v1_before_staff;
revoke all on function public.get_ledger_date_v1_before_staff(date, text, integer)
  from public, anon, authenticated;

create function public.get_ledger_date_v1(
  p_business_date date, p_before_sequence text, p_limit integer
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
begin
  perform private.allow_member_permission('ledger_read');
  v_result := public.get_ledger_date_v1_before_staff(
    p_business_date, p_before_sequence, p_limit
  );
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_role = 'employee' and v_result ? 'feed_page' then
    v_result := jsonb_set(
      v_result,
      '{feed_page,items}',
      coalesce((
        select jsonb_agg(item)
        from jsonb_array_elements(v_result #> '{feed_page,items}') as item
        where item ->> 'actor_user_id' = auth.uid()::text
           or item ->> 'actor_id' = auth.uid()::text
      ), '[]'::jsonb)
    );
    v_result := v_result - 'day_summary';
  end if;
  return v_result;
end;
$fn$;
revoke all on function public.get_ledger_date_v1(date, text, integer) from public, anon;
grant execute on function public.get_ledger_date_v1(date, text, integer) to authenticated;

alter function public.get_daily_ledger_operation(uuid)
  rename to get_daily_ledger_operation_before_staff;
revoke all on function public.get_daily_ledger_operation_before_staff(uuid)
  from public, anon, authenticated;

create function public.get_daily_ledger_operation(p_operation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
  v_actor uuid;
begin
  perform private.allow_member_permission('ledger_read');
  v_result := public.get_daily_ledger_operation_before_staff(p_operation_id);
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_role = 'employee' then
    select operation.actor_user_id into v_actor
    from public.financial_operations as operation
    where operation.shop_id = v_shop and operation.id = p_operation_id;
    if v_actor is distinct from auth.uid() then
      raise exception 'forbidden';
    end if;
  end if;
  return v_result;
end;
$fn$;
revoke all on function public.get_daily_ledger_operation(uuid) from public, anon;
grant execute on function public.get_daily_ledger_operation(uuid) to authenticated;

alter function public.get_daily_ledger_day_state()
  rename to get_daily_ledger_day_state_before_staff;
revoke all on function public.get_daily_ledger_day_state_before_staff()
  from public, anon, authenticated;

create function public.get_daily_ledger_day_state()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('ledger_read');
  return public.get_daily_ledger_day_state_before_staff();
end;
$fn$;
revoke all on function public.get_daily_ledger_day_state() from public, anon;
grant execute on function public.get_daily_ledger_day_state() to authenticated;

-- Close day stays owner-only (no allow_member_permission → staff denied by default).

alter function public.get_inventory_totals_v1(text, smallint)
  rename to get_inventory_totals_v1_before_staff;
revoke all on function public.get_inventory_totals_v1_before_staff(text, smallint)
  from public, anon, authenticated;

create function public.get_inventory_totals_v1(
  p_category text default null, p_karat smallint default null
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('inventory');
  return public.get_inventory_totals_v1_before_staff(p_category, p_karat);
end;
$fn$;
revoke all on function public.get_inventory_totals_v1(text, smallint) from public, anon;
grant execute on function public.get_inventory_totals_v1(text, smallint) to authenticated;

alter function public.list_inventory_lots_v1(text, smallint, text, text, integer, text)
  rename to list_inventory_lots_v1_before_staff;
revoke all on function public.list_inventory_lots_v1_before_staff(
  text, smallint, text, text, integer, text
) from public, anon, authenticated;

create function public.list_inventory_lots_v1(
  p_category text default null,
  p_karat smallint default null,
  p_stock_class text default null,
  p_query text default null,
  p_limit integer default 50,
  p_cursor text default null
)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  perform private.allow_member_permission('inventory');
  return public.list_inventory_lots_v1_before_staff(
    p_category, p_karat, p_stock_class, p_query, p_limit, p_cursor
  );
end;
$fn$;
revoke all on function public.list_inventory_lots_v1(
  text, smallint, text, text, integer, text
) from public, anon;
grant execute on function public.list_inventory_lots_v1(
  text, smallint, text, text, integer, text
) to authenticated;

notify pgrst, 'reload schema';
commit;

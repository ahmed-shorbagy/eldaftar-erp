-- U5 (device pass 2026-11-11): expense cards in the ledger feed showed only
-- «مصروف» and the amount. The current-app reads (home, date, operation page)
-- now carry the expense description in the existing `item_summary` key, so
-- no client build meets an unknown key. Legacy 361ad2e reads are unchanged.
begin;

create function private.feed_expense_descriptions(p_rows jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(pg_catalog.jsonb_agg(
    case
      when row_item.value ->> 'kind' = 'expense'
        and pg_catalog.jsonb_typeof(row_item.value -> 'item_summary') is distinct from 'string'
        and described.text is not null
        then row_item.value
          || pg_catalog.jsonb_build_object('item_summary', described.text)
      else row_item.value
    end
    order by row_item.ordinality
  ), '[]'::jsonb)
  from pg_catalog.jsonb_array_elements(
    case when pg_catalog.jsonb_typeof(p_rows) = 'array' then p_rows else '[]'::jsonb end
  ) with ordinality as row_item(value, ordinality)
  left join lateral (
    select nullif(pg_catalog.left(pg_catalog.btrim(pg_catalog.regexp_replace(
      detail.payload ->> 'description', '[[:cntrl:][:space:]]+', ' ', 'g'
    )), 200), '') as text
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where row_item.value ->> 'kind' = 'expense'
      and operation.id::text = row_item.value ->> 'operation_id'
      and operation.kind = 'expense'
    limit 1
  ) as described on true;
$fn$;

revoke all on function private.feed_expense_descriptions(jsonb)
  from public, anon, authenticated;

comment on function private.feed_expense_descriptions(jsonb) is
  'Fills item_summary of expense feed rows with the expense description (U5). Only rows already returned by an authorized read are enriched.';

create or replace function public.get_daily_ledger_home_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  v_result := public.get_daily_ledger_home_v1_full();
  if pg_catalog.jsonb_typeof(v_result -> 'feed') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{feed}', private.feed_expense_descriptions(v_result -> 'feed')
    );
  end if;
  return v_result;
end;
$fn$;

create or replace function public.get_ledger_date_v2(
  p_business_date date default null,
  p_before_sequence text default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  v_result := public.get_ledger_date_v1_full(
    p_business_date, p_before_sequence, p_limit
  );
  if pg_catalog.jsonb_typeof(v_result #> '{feed_page,items}') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{feed_page,items}',
      private.feed_expense_descriptions(v_result #> '{feed_page,items}')
    );
  end if;
  return v_result;
end;
$fn$;

create or replace function public.get_ledger_operation_page_v2(
  p_day_id uuid,
  p_before_sequence text,
  p_after_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  v_result := public.get_ledger_operation_page_full(
    p_day_id, p_before_sequence, p_after_sequence, p_limit
  );
  if pg_catalog.jsonb_typeof(v_result -> 'items') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{items}', private.feed_expense_descriptions(v_result -> 'items')
    );
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_daily_ledger_home_v2() from public, anon;
grant execute on function public.get_daily_ledger_home_v2() to authenticated;
revoke all on function public.get_ledger_date_v2(date, text, integer) from public, anon;
grant execute on function public.get_ledger_date_v2(date, text, integer) to authenticated;
revoke all on function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  from public, anon;
grant execute on function public.get_ledger_operation_page_v2(uuid, text, text, integer)
  to authenticated;

notify pgrst, 'reload schema';
commit;

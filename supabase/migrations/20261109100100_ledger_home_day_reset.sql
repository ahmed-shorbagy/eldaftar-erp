-- After close, home daily flows are zero and balances stay (ADR 0042, A-D1, A-D4).
begin;

create function private.ledger_zero_flows(p_value jsonb) returns jsonb
language sql
immutable
set search_path = ''
as $fn$
  select case pg_catalog.jsonb_typeof(p_value)
    when 'object' then coalesce((
      select pg_catalog.jsonb_object_agg(entry.key, private.ledger_zero_flows(entry.value))
      from pg_catalog.jsonb_each(p_value) as entry), '{}'::jsonb)
    when 'array' then '[]'::jsonb
    when 'number' then '0'::jsonb
    when 'string' then case
      when p_value #>> '{}' ~ '^-?[0-9]+$' then '"0"'::jsonb
      else p_value
    end
    else p_value
  end;
$fn$;

revoke all on function private.ledger_zero_flows(jsonb) from public, anon, authenticated;

alter function public.get_daily_ledger_home_v1()
  rename to get_daily_ledger_home_v1_before_day_reset;
revoke all on function public.get_daily_ledger_home_v1_before_day_reset()
  from public, anon, authenticated;

create function public.get_daily_ledger_home_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_open_days uuid[];
  v_last_closed date;
  v_feed jsonb;
  v_summary jsonb;
  v_open_count bigint;
begin
  v_result := public.get_daily_ledger_home_v1_before_day_reset();
  if v_result ->> 'state' is distinct from 'confirmed' then
    return v_result;
  end if;
  v_shop := private.opening_require_reader_shop();
  select pg_catalog.array_agg(day.id) into v_open_days
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open';
  select day.business_date into v_last_closed
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'closed'
  order by day.opened_at desc, day.id desc
  limit 1;

  if coalesce(v_result ->> 'employee_ledger', 'false') = 'true' then
    v_result := pg_catalog.jsonb_set(v_result, '{feed}', coalesce((
      select pg_catalog.jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
      from pg_catalog.jsonb_array_elements(v_result -> 'feed') as item
      join public.financial_operations as operation
        on operation.shop_id = v_shop
       and operation.id = (item ->> 'operation_id')::uuid
      where operation.business_day_id = any (coalesce(v_open_days, '{}'))
    ), '[]'::jsonb));
    return v_result || pg_catalog.jsonb_build_object(
      'day_reset', v_open_days is null,
      'last_closed_business_date', v_last_closed
    );
  end if;

  if v_open_days is not null then
    -- get_ledger_date_v1 reads every session of the calendar date. A new
    -- day opened on that date must not show the closed session (A-D1).
    v_feed := coalesce((
      select pg_catalog.jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
      from pg_catalog.jsonb_array_elements(v_result -> 'feed') as item
      join public.financial_operations as operation
        on operation.shop_id = v_shop
       and operation.id = (item ->> 'operation_id')::uuid
      where operation.business_day_id = any (v_open_days)
    ), '[]'::jsonb);
    select count(*) into v_open_count
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_open_days)
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      and not private.daily_note_deleted(operation.shop_id, operation.id);
    select pg_catalog.jsonb_build_object(
      'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
        filter (where operation.kind in ('sale', 'scrap_sale')), 0)::text,
      'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
        filter (where operation.kind = 'purchase'), 0)::text,
      'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
        filter (where operation.kind = 'expense'), 0)::text,
      'sale_count', count(*) filter (where operation.kind in ('sale', 'scrap_sale')),
      'purchase_count', count(*) filter (where operation.kind = 'purchase'),
      'expense_count', count(*) filter (where operation.kind = 'expense')
    ) into v_summary
    from public.financial_operations as operation
    left join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_open_days)
      and not private.ledger_trade_hidden(operation.shop_id, operation.id);
    v_summary := v_summary || (
      select pg_catalog.jsonb_build_object(
        'repair_piastres', coalesce(sum(posting.amount) filter (
          where account.account_kind = 'cash_method'), 0)::text,
        'repair_count', count(distinct operation.id)
      )
      from public.financial_operations as operation
      left join public.journal_postings as posting
        on posting.shop_id = operation.shop_id and posting.operation_id = operation.id
      left join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where operation.shop_id = v_shop
        and operation.business_day_id = any (v_open_days)
        and operation.kind in ('repair_fee', 'repair_fee_collection')
        and not private.ledger_trade_hidden(operation.shop_id, operation.id)
    );
    v_summary := v_summary || pg_catalog.jsonb_build_object(
      'gold_by_bucket', coalesce((
        select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'kind', bucket.kind,
          'category', bucket.category,
          'karat', bucket.karat,
          'milligrams', bucket.milligrams::text,
          'count', bucket.pieces::text
        ) order by bucket.kind, bucket.category, bucket.karat)
        from (
          select case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end as kind,
            item.value ->> 'category' as category,
            (item.value ->> 'karat')::smallint as karat,
            sum((item.value ->> 'milligrams')::numeric) as milligrams,
            sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
          from public.financial_operations as operation
          join public.financial_operation_details as detail
            on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
          cross join lateral pg_catalog.jsonb_array_elements(
            case
              when pg_catalog.jsonb_typeof(detail.payload -> 'items') = 'array'
                then detail.payload -> 'items'
              else '[]'::jsonb
            end
          ) as item(value)
          where operation.shop_id = v_shop
            and operation.business_day_id = any (v_open_days)
            and not private.ledger_trade_hidden(operation.shop_id, operation.id)
            and operation.kind in ('sale', 'purchase', 'scrap_sale')
          group by 1, 2, 3
        ) as bucket
      ), '[]'::jsonb)
    );
    return v_result || pg_catalog.jsonb_build_object(
      'feed', v_feed,
      'feed_page', (v_result -> 'feed_page') || pg_catalog.jsonb_build_object(
        'has_more', v_open_count > coalesce(pg_catalog.jsonb_array_length(v_feed), 0),
        'next_before_sequence', null
      ),
      'day_summary', v_summary,
      'journal_context', (v_result -> 'journal_context') || pg_catalog.jsonb_build_object(
        'day_ids', to_jsonb(v_open_days),
        'return_count', (
          select count(*) from public.financial_operations as operation
          where operation.shop_id = v_shop
            and operation.business_day_id = any (v_open_days)
            and operation.kind in ('sale_return', 'purchase_return', 'customer_return')
            and not private.ledger_trade_hidden(operation.shop_id, operation.id)
        ),
        'note_count', (
          select count(*) from public.financial_operations as operation
          where operation.shop_id = v_shop
            and operation.business_day_id = any (v_open_days)
            and operation.kind = 'daily_note'
            and not private.daily_note_deleted(operation.shop_id, operation.id)
        )
      ),
      'day_reset', false,
      'last_closed_business_date', v_last_closed
    );
  end if;

  return v_result || pg_catalog.jsonb_build_object(
    'feed', '[]'::jsonb,
    'feed_page', (v_result -> 'feed_page') || pg_catalog.jsonb_build_object(
      'has_more', false,
      'next_before_sequence', null
    ),
    'day_summary', private.ledger_zero_flows(v_result -> 'day_summary'),
    'journal_context', private.ledger_zero_flows(v_result -> 'journal_context')
      || pg_catalog.jsonb_build_object(
        'business_date', v_last_closed,
        'day_ids', '[]'::jsonb
      ),
    'day_reset', true,
    'last_closed_business_date', v_last_closed
  );
end;
$fn$;

revoke all on function public.get_daily_ledger_home_v1() from public, anon;
grant execute on function public.get_daily_ledger_home_v1() to authenticated;

comment on function public.get_daily_ledger_home_v1() is
  'Open day: only that open day''s flows. No open day: zero daily flows, keep balances (ADR 0042).';

notify pgrst, 'reload schema';
commit;

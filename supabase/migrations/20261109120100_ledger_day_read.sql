-- One financial day's ledger, read by day id (ADR 0042, A-D2 amended).
-- get_ledger_date_v1 reads every session of a calendar date. When a day is
-- closed and a new one is opened on the same date, «الدفاتر» must show only
-- the closed session and home must page only the open session.
-- The home read also returns the cursor for older open-day rows, so a day
-- with more than 100 operations can be paged.

begin;

create function private.ledger_days_summary(p_shop uuid, p_days uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_summary jsonb;
begin
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
  where operation.shop_id = p_shop
    and operation.business_day_id = any (p_days)
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
    where operation.shop_id = p_shop
      and operation.business_day_id = any (p_days)
      and operation.kind in ('repair_fee', 'repair_fee_collection')
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
  );
  return v_summary || pg_catalog.jsonb_build_object(
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
        where operation.shop_id = p_shop
          and operation.business_day_id = any (p_days)
          and not private.ledger_trade_hidden(operation.shop_id, operation.id)
          and operation.kind in ('sale', 'purchase', 'scrap_sale')
        group by 1, 2, 3
      ) as bucket
    ), '[]'::jsonb)
  );
end;
$fn$;

revoke all on function private.ledger_days_summary(uuid, uuid[])
  from public, anon, authenticated;

-- Same contract as get_ledger_date_v1, limited to one business day. Reads
-- through get_ledger_date_v1, so the staff and permission rules stay there.
create function public.get_ledger_day_v1(
  p_day_id uuid, p_before_sequence text, p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_date date;
  v_page jsonb;
  v_first jsonb;
  v_items jsonb := '[]'::jsonb;
  v_cursor text := p_before_sequence;
  v_guard integer := 0;
  v_more boolean := false;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_day_id is null or p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select day.business_date into v_date
  from public.business_days as day
  where day.shop_id = v_shop and day.id = p_day_id;
  if v_date is null then
    raise exception 'not_found';
  end if;

  loop
    v_guard := v_guard + 1;
    v_page := public.get_ledger_date_v1(v_date, v_cursor, 100);
    if v_first is null then
      v_first := v_page;
    end if;
    v_items := v_items || coalesce((
      select pg_catalog.jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
      from pg_catalog.jsonb_array_elements(v_page #> '{feed_page,items}') as item
      join public.financial_operations as operation
        on operation.shop_id = v_shop
       and operation.id = (item ->> 'operation_id')::uuid
      where operation.business_day_id = p_day_id
    ), '[]'::jsonb);
    exit when pg_catalog.jsonb_array_length(v_items) > p_limit;
    exit when coalesce((v_page #>> '{feed_page,has_more}')::boolean, false) is false;
    v_cursor := v_page #>> '{feed_page,next_before_sequence}';
    exit when v_cursor is null or v_guard >= 50;
  end loop;

  v_more := pg_catalog.jsonb_array_length(v_items) > p_limit;
  v_items := coalesce((
    select pg_catalog.jsonb_agg(item.value order by item.ordinality)
    from pg_catalog.jsonb_array_elements(v_items) with ordinality as item(value, ordinality)
    where item.ordinality <= p_limit
  ), '[]'::jsonb);

  v_first := pg_catalog.jsonb_set(v_first, '{feed_page,items}', v_items);
  v_first := pg_catalog.jsonb_set(v_first, '{feed_page,has_more}', to_jsonb(v_more));
  v_first := pg_catalog.jsonb_set(v_first, '{feed_page,limit}', to_jsonb(p_limit));
  v_first := pg_catalog.jsonb_set(
    v_first,
    '{feed_page,next_before_sequence}',
    case
      when v_more then to_jsonb((
        select min((item ->> 'shop_sequence')::bigint)::text
        from pg_catalog.jsonb_array_elements(v_items) as item
      ))
      else 'null'::jsonb
    end
  );
  v_first := v_first || pg_catalog.jsonb_build_object(
    'day_ids', pg_catalog.jsonb_build_array(p_day_id)
  );
  if v_first ? 'day_summary' then
    v_first := v_first || pg_catalog.jsonb_build_object(
      'day_summary', private.ledger_days_summary(v_shop, array[p_day_id])
    );
  end if;
  return v_first;
end;
$fn$;

revoke all on function public.get_ledger_day_v1(uuid, text, integer) from public, anon;
grant execute on function public.get_ledger_day_v1(uuid, text, integer) to authenticated;

comment on function public.get_ledger_day_v1(uuid, text, integer) is
  'One business day of get_ledger_date_v1: rows and figures of that day only (ADR 0042).';

-- Home: send the cursor for older open-day rows instead of a null cursor.
do $patch_home_cursor$
declare
  v_def text;
  v_old text := $old$        'has_more', v_open_count > coalesce(pg_catalog.jsonb_array_length(v_feed), 0),
        'next_before_sequence', null$old$;
  v_new text := $new$        'has_more', v_open_count > coalesce(pg_catalog.jsonb_array_length(v_feed), 0),
        'next_before_sequence', case
          when v_open_count > coalesce(pg_catalog.jsonb_array_length(v_feed), 0) then (
            select min((item ->> 'shop_sequence')::bigint)::text
            from pg_catalog.jsonb_array_elements(v_feed) as item
          )
          else null
        end$new$;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef('public.get_daily_ledger_home_v1()'::regprocedure),
    E'\r\n',
    E'\n'
  );
  if (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
      / pg_catalog.length(v_old) <> 1 then
    raise exception 'home_cursor_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_home_cursor$;

notify pgrst, 'reload schema';
commit;

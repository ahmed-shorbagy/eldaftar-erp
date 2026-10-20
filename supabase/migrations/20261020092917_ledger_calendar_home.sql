-- Calendar-date home read. Financial business-day state and balances are not
-- changed by this endpoint. The old v2 contract remains available to old clients.
begin;

create function public.get_daily_ledger_home_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_base jsonb;
  v_date jsonb;
  v_shop uuid;
  v_zone text;
  v_days uuid[];
  v_at timestamptz := pg_catalog.now();
  v_next timestamptz;
  v_returns bigint;
  v_notes bigint;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  v_base := public.get_daily_ledger_v2();
  if v_base ->> 'state' is distinct from 'confirmed' then return v_base; end if;
  select private.shop_display_zone(shop.time_zone) into v_zone
  from public.shops as shop where shop.id = v_shop;
  v_date := public.get_ledger_date_v1(null, null, 100);
  select coalesce(array_agg(item.value::uuid), '{}'::uuid[]) into v_days
  from pg_catalog.jsonb_array_elements_text(v_date -> 'day_ids') as item(value);
  v_next := (((v_at at time zone v_zone)::date + 1)::timestamp at time zone v_zone);
  select count(*) filter (where operation.kind in ('sale_return', 'purchase_return')),
    count(*) filter (where operation.kind = 'daily_note')
    into v_returns, v_notes
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = any(v_days)
    and not private.ledger_trade_hidden(operation.shop_id, operation.id);
  return v_base || pg_catalog.jsonb_build_object(
    'read_model_version', 3,
    'day_summary', v_date -> 'day_summary',
    'feed', v_date #> '{feed_page,items}',
    'feed_page', pg_catalog.jsonb_build_object(
      'limit', v_date #> '{feed_page,limit}',
      'has_more', v_date #> '{feed_page,has_more}',
      'direction', 'desc',
      'next_before_sequence', v_date #> '{feed_page,next_before_sequence}',
      'server_sequence', v_date #> '{feed_page,server_sequence}',
      'snapshot_sequence', v_date #> '{feed_page,snapshot_sequence}'
    ),
    'journal_context', pg_catalog.jsonb_build_object(
      'business_date', v_date ->> 'business_date',
      'day_ids', v_date -> 'day_ids',
      'server_now', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'next_midnight_at', pg_catalog.to_char(v_next at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'return_count', v_returns,
      'note_count', v_notes
    )
  );
end;
$fn$;

comment on function public.get_daily_ledger_home_v1() is
  'Owner-only calendar-date home summary/feed with exact return/note counts and server UTC rollover timing. Read only; financial day closure remains explicit.';
revoke all on function public.get_daily_ledger_home_v1() from public, anon;
grant execute on function public.get_daily_ledger_home_v1() to authenticated;
create function public.list_daily_notes_date_v1(
  p_business_date date, p_before_sequence text, p_limit integer, p_query text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_name text;
  v_date date;
  v_days uuid[];
  v_before bigint;
  v_query text;
  v_server bigint;
  v_items jsonb;
  v_more boolean;
  v_next text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 50
    or char_length(p_query) > 80 then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  select private.shop_display_zone(shop.time_zone), shop.owner_display_name
    into v_zone, v_name from public.shops as shop where shop.id = v_shop;
  v_date := coalesce(p_business_date, (pg_catalog.now() at time zone v_zone)::date);
  if v_date > (pg_catalog.now() at time zone v_zone)::date then
    raise exception 'invalid_input';
  end if;
  v_before := private.parse_optional_sequence(p_before_sequence);
  v_query := nullif(btrim(coalesce(p_query, '')), '');
  select coalesce(array_agg(day.id), '{}'::uuid[]) into v_days
  from public.business_days as day
  where day.shop_id = v_shop and day.business_date = v_date;
  select coalesce(max(operation.shop_sequence), 0) into v_server
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.business_day_id = any(v_days)
    and operation.kind = 'daily_note';
  with matched as materialized (
    select operation.id, operation.shop_sequence
    from public.financial_operations as operation
    where operation.shop_id = v_shop and operation.business_day_id = any(v_days)
      and operation.kind = 'daily_note'
      and (v_before is null or operation.shop_sequence < v_before)
      and (v_query is null or exists (
        select 1 from public.financial_operation_details as detail
        where detail.shop_id = operation.shop_id and detail.operation_id = operation.id
          and strpos(lower(coalesce(detail.payload ->> 'text', '')), lower(v_query)) > 0
      ))
    order by operation.shop_sequence desc limit (p_limit + 1)
  ), picked as (
    select * from matched order by shop_sequence desc limit p_limit
  )
  select coalesce((select jsonb_agg(private.daily_note_json(
      picked.id, v_shop, v_zone, v_name
    ) order by picked.shop_sequence desc) from picked), '[]'::jsonb),
    (select count(*) > p_limit from matched),
    (select min(picked.shop_sequence)::text from picked)
  into v_items, v_more, v_next;
  return jsonb_build_object('business_date', v_date::text,
    'page', jsonb_build_object('shop_id', v_shop, 'day_id', null,
      'limit', p_limit, 'has_more', v_more, 'server_sequence', v_server::text,
      'snapshot_sequence', v_server::text,
      'next_before_sequence', case when v_more then v_next else null end,
      'items', v_items));
end;
$fn$;
revoke all on function public.list_daily_notes_date_v1(date, text, integer, text) from public, anon;
grant execute on function public.list_daily_notes_date_v1(date, text, integer, text) to authenticated;
notify pgrst, 'reload schema';
commit;

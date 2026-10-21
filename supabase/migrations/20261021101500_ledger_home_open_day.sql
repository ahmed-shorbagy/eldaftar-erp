-- Home journal follows the open financial day until the owner closes it.
-- Calendar midnight no longer empties the main ledger or forces a new day.
begin;

create or replace function public.get_daily_ledger_home_v1()
returns jsonb
language plpgsql
volatile
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
  v_open_date date;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  v_base := public.get_daily_ledger_v2();
  if v_base ->> 'state' is distinct from 'confirmed' then return v_base; end if;
  select private.shop_display_zone(shop.time_zone) into v_zone
  from public.shops as shop where shop.id = v_shop;
  select day.business_date into v_open_date
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  order by day.opened_at desc, day.id desc
  limit 1;
  v_date := public.get_ledger_date_v1(v_open_date, null, 100);
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
  'Owner-only home summary/feed for the open financial day until explicit close; otherwise the shop calendar date. Volatile so PostgREST allows the shared shop lock used by get_daily_ledger_v2.';

notify pgrst, 'reload schema';

commit;

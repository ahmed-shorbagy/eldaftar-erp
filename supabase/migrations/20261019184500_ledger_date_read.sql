-- Owner read of one business date across every session that shares it.
-- Null date means the server date in the shop display zone. No balances,
-- no mutations, and no client shop argument. Item JSON matches
-- get_ledger_operation_page, including JSON-null optional arrays.
begin;

-- Day lookup is by shop and business date. Sequence paging stays on
-- financial_operations_shop_day_sequence_idx; this index does not repeat it.
create index business_days_shop_business_date_idx
  on public.business_days (shop_id, business_date, opened_at, id);

comment on index public.business_days_shop_business_date_idx is
  'Resolves every business day that shares a shop date for historical ledger reads.';

create function public.get_ledger_date_v1(
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
  v_shop uuid;
  v_zone text;
  v_name text;
  v_server_date date;
  v_date date;
  v_before bigint;
  v_day_ids uuid[];
  v_summary jsonb;
  v_gold jsonb;
  v_server bigint;
  v_rows jsonb;
  v_has_more boolean;
  v_next text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid_input';
  end if;
  v_before := private.parse_optional_sequence(p_before_sequence);
  v_shop := private.opening_require_reader_shop();
  select private.shop_display_zone(shop.time_zone), shop.owner_display_name
    into v_zone, v_name
  from public.shops as shop
  where shop.id = v_shop;
  v_server_date := (pg_catalog.now() at time zone v_zone)::date;
  if p_business_date is null then
    v_date := v_server_date;
  else
    v_date := p_business_date;
  end if;
  if v_date > v_server_date then
    raise exception 'invalid_date';
  end if;
  select coalesce(
    array_agg(day.id order by day.opened_at asc, day.id asc),
    '{}'::uuid[]
  )
    into v_day_ids
  from public.business_days as day
  where day.shop_id = v_shop
    and day.business_date = v_date;

  select jsonb_build_object(
    'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind in ('sale', 'scrap_sale')), 0)::text,
    'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'purchase'), 0)::text,
    'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'expense'), 0)::text,
    'sale_count', count(*) filter (where operation.kind in ('sale', 'scrap_sale')),
    'purchase_count', count(*) filter (where operation.kind = 'purchase'),
    'expense_count', count(*) filter (where operation.kind = 'expense')
  )
    into v_summary
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  where operation.shop_id = v_shop
    and operation.business_day_id = any (v_day_ids);

  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', bucket.kind,
    'category', bucket.category,
    'karat', bucket.karat,
    'milligrams', bucket.milligrams::text,
    'count', bucket.pieces::text
  ) order by bucket.kind, bucket.category, bucket.karat), '[]'::jsonb)
    into v_gold
  from (
    select case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end as kind,
      item.value ->> 'category' as category,
      (item.value ->> 'karat')::smallint as karat,
      sum((item.value ->> 'milligrams')::numeric) as milligrams,
      sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id
     and detail.operation_id = operation.id
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(detail.payload -> 'items') = 'array'
          then detail.payload -> 'items'
        else '[]'::jsonb
      end
    ) as item(value)
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and operation.kind in ('sale', 'purchase', 'scrap_sale')
    group by case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end,
      item.value ->> 'category',
      (item.value ->> 'karat')::smallint
  ) as bucket;
  v_summary := v_summary || jsonb_build_object('gold_by_bucket', coalesce(v_gold, '[]'::jsonb));

  select coalesce(max(operation.shop_sequence), 0)
    into v_server
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = any (v_day_ids);

  with fetched as materialized (
    select
      operation.id,
      operation.shop_id,
      operation.kind,
      operation.shop_sequence,
      operation.created_at
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and (v_before is null or operation.shop_sequence < v_before)
    order by operation.shop_sequence desc
    limit (p_limit + 1)
  ),
  shaped as (
    select
      fetched.id,
      fetched.kind,
      fetched.shop_sequence,
      fetched.created_at,
      detail.payload as summary_payload,
      (
        coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
        or (
          fetched.kind = 'daily_note'
          and coalesce(length(btrim(detail.payload ->> 'text')) > 0, false)
        )
        or exists (
          select 1
          from public.daily_note_attachments as attachment
          where attachment.shop_id = fetched.shop_id
            and attachment.operation_id = fetched.id
        )
      ) as has_note
    from fetched
    left join public.financial_operation_details as detail
      on detail.shop_id = fetched.shop_id
     and detail.operation_id = fetched.id
  ),
  kept as (
    select shaped.*
    from shaped
    order by shaped.shop_sequence desc
    limit p_limit
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'kind', kept.kind,
      'label_ar', private.ledger_operation_label(kept.kind),
      'operation_id', kept.id,
      'actor_display_name', coalesce(v_name, ''),
      'occurred_at', pg_catalog.to_jsonb(kept.created_at),
      'occurred_at_cairo', to_char(
        kept.created_at at time zone 'Africa/Cairo',
        'YYYY-MM-DD"T"HH24:MI:SS'
      ),
      'occurred_at_shop', to_char(
        kept.created_at at time zone v_zone,
        'YYYY-MM-DD"T"HH24:MI:SS'
      ),
      'has_note', kept.has_note,
      'is_daily_note', kept.kind = 'daily_note',
      'is_return', kept.kind in ('sale_return', 'purchase_return'),
      'shop_sequence', kept.shop_sequence::text,
      'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),
      'item_summary', (select left(string_agg(nullif(item ->> 'item_name', ''), '، ' order by ord), 200)
        from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) with ordinality as items(item, ord)),
      'piece_count', (select sum((item ->> 'count')::numeric)::text
        from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item
        where item ->> 'count' ~ '^[0-9]+$'),
      'total_pounds', case when kept.summary_payload ->> 'total_piastres' ~ '^[0-9]+$'
        then trunc((kept.summary_payload ->> 'total_piastres')::numeric / 100)::text || '.' ||
          lpad(mod((kept.summary_payload ->> 'total_piastres')::numeric, 100)::text, 2, '0') else null end,
      'weight_grams', (select case when sum((item ->> 'milligrams')::numeric) is null then null
        else trunc(sum((item ->> 'milligrams')::numeric) / 1000)::text || '.' ||
          lpad(mod(sum((item ->> 'milligrams')::numeric), 1000)::text, 3, '0') end
        from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item),
      'karat', (select case when count(distinct item ->> 'karat') = 1
        then min((item ->> 'karat')::integer) else null end
        from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item),
      'payment_label', (select string_agg(case tender ->> 'method'
        when 'cash' then 'كاش' when 'instant_transfer' then 'إنستا باي'
        when 'wallet' then 'محفظة' when 'card' then 'فيزا' end, ' + ' order by tender ->> 'method')
        from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'tenders', 'null'::jsonb), '[]'::jsonb)) tender)
    ) order by kept.shop_sequence desc), '[]'::jsonb),
    (select count(*) from fetched) > p_limit,
    (select min(edge.shop_sequence)::text from kept as edge)
    into v_rows, v_has_more, v_next
  from kept;
  if not found then
    v_rows := '[]'::jsonb;
    v_has_more := false;
    v_next := null;
  elsif not coalesce(v_has_more, false) then
    v_next := null;
  end if;

  return jsonb_build_object(
    'read_model_version', 1,
    'shop_id', v_shop,
    'business_date', pg_catalog.to_char(v_date, 'YYYY-MM-DD'),
    'server_date', pg_catalog.to_char(v_server_date, 'YYYY-MM-DD'),
    'day_ids', to_jsonb(v_day_ids),
    'day_summary', v_summary,
    'feed_page', jsonb_build_object(
      'shop_id', v_shop,
      'day_id', null,
      'direction', 'desc',
      'limit', p_limit,
      'has_more', coalesce(v_has_more, false),
      'server_sequence', v_server::text,
      'snapshot_sequence', v_server::text,
      'next_before_sequence', case when coalesce(v_has_more, false) then v_next else null end,
      'next_after_sequence', null,
      'items', coalesce(v_rows, '[]'::jsonb)
    )
  );
end;
$fn$;

comment on function public.get_ledger_date_v1(date, text, integer) is
  'Authenticated owner read of one shop business date. Sequences are the date maximum, not shop-wide balances.';

revoke all on function public.get_ledger_date_v1(date, text, integer) from public, anon;
grant execute on function public.get_ledger_date_v1(date, text, integer) to authenticated;

notify pgrst, 'reload schema';
commit;

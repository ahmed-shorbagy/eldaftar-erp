-- Instant inventory and trader (abouniyat) page summaries for Word PAGES gaps:
-- shop-wide original trader holding, bullion/coin denomination rows, and
-- pending receipt counts on trader search.

create or replace function public.get_inventory_totals_v1(
  p_category text default null, p_karat smallint default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_buckets jsonb;
  v_original_held bigint;
  v_denominations jsonb;
  v_coins jsonb;
begin
  perform private.assert_read_filters(p_category, p_karat, null, null);
  v_shop := private.opening_require_reader_shop();
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', bucket.category_code,
    'karat', bucket.karat,
    'available_milligrams', bucket.available_mg::text,
    'available_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
      else to_jsonb(bucket.available_count::text) end,
    'pending_milligrams', bucket.pending_mg::text,
    'pending_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
      else to_jsonb(bucket.pending_count::text) end,
    'held_milligrams', bucket.held_mg::text,
    'held_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
      else to_jsonb(bucket.held_count::text) end
  ) order by bucket.category_code, bucket.karat), '[]'::jsonb)
  into v_buckets
  from (
    select lot.category_code, lot.karat,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'owned_available'), 0)::bigint as available_mg,
      coalesce(sum(movement.delta_count) filter (
        where lot.stock_class = 'owned_available' and lot.tracks_count), 0)::bigint as available_count,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'owned_pending'), 0)::bigint as pending_mg,
      coalesce(sum(movement.delta_count) filter (
        where lot.stock_class = 'owned_pending' and lot.tracks_count), 0)::bigint as pending_count,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'trader_custody'), 0)::bigint as held_mg,
      coalesce(sum(movement.delta_count) filter (
        where lot.stock_class = 'trader_custody' and lot.tracks_count), 0)::bigint as held_count
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
      and (p_category is null or lot.category_code = p_category)
      and (p_karat is null or lot.karat = p_karat)
    group by lot.category_code, lot.karat
  ) as bucket;

  select coalesce(sum(receipt.milligrams), 0)::bigint
  into v_original_held
  from public.inventory_receipts as receipt
  where receipt.shop_id = v_shop
    and receipt.trader_id is not null
    and (p_category is null or receipt.category_code = p_category)
    and (p_karat is null or receipt.karat = p_karat);

  select coalesce(jsonb_agg(jsonb_build_object(
    'denomination_id', row.denomination_id,
    'label', row.label,
    'nominal_milligrams', row.nominal_milligrams::text,
    'milligrams', row.milligrams::text,
    'count', row.piece_count::text
  ) order by row.nominal_milligrams, row.label), '[]'::jsonb)
  into v_denominations
  from (
    select lot.denomination_id,
      coalesce(denomination.label, 'سبيكة بلا فئة') as label,
      coalesce(denomination.nominal_milligrams, 0)::bigint as nominal_milligrams,
      coalesce(sum(movement.delta_milligrams), 0)::bigint as milligrams,
      coalesce(sum(movement.delta_count), 0)::bigint as piece_count
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    left join public.bullion_denominations as denomination
      on denomination.shop_id = lot.shop_id and denomination.id = lot.denomination_id
    where lot.shop_id = v_shop
      and lot.category_code = 'bullion'
      and lot.stock_class = 'owned_available'
      and (p_karat is null or lot.karat = p_karat)
      and (p_category is null or p_category = 'bullion')
    group by lot.denomination_id, denomination.label, denomination.nominal_milligrams
    having coalesce(sum(movement.delta_milligrams), 0) > 0
       or coalesce(sum(movement.delta_count), 0) > 0
  ) as row;

  select coalesce(jsonb_agg(jsonb_build_object(
    'coin_type_id', row.coin_type_id,
    'label', row.label,
    'nominal_milligrams', case when row.nominal_milligrams is null then 'null'::jsonb
      else to_jsonb(row.nominal_milligrams::text) end,
    'milligrams', row.milligrams::text,
    'count', row.piece_count::text
  ) order by coalesce(row.nominal_milligrams, 0), row.label), '[]'::jsonb)
  into v_coins
  from (
    select lot.coin_type_id,
      coalesce(coin.label, 'عملة بلا نوع') as label,
      coin.nominal_milligrams as nominal_milligrams,
      coalesce(sum(movement.delta_milligrams), 0)::bigint as milligrams,
      coalesce(sum(movement.delta_count), 0)::bigint as piece_count
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    left join public.coin_types as coin
      on coin.shop_id = lot.shop_id and coin.id = lot.coin_type_id
    where lot.shop_id = v_shop
      and lot.category_code = 'coin'
      and lot.stock_class = 'owned_available'
      and (p_karat is null or lot.karat = p_karat)
      and (p_category is null or p_category = 'coin')
    group by lot.coin_type_id, coin.label, coin.nominal_milligrams
    having coalesce(sum(movement.delta_milligrams), 0) > 0
       or coalesce(sum(movement.delta_count), 0) > 0
  ) as row;

  return jsonb_build_object(
    'ok', true,
    'buckets', v_buckets,
    'original_held_milligrams', v_original_held::text,
    'denomination_rows', coalesce(v_denominations, '[]'::jsonb),
    'coin_rows', coalesce(v_coins, '[]'::jsonb)
  );
end;
$fn$;

create or replace function public.search_traders_v1(
  p_query text default null, p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  if p_query is not null and char_length(p_query) > 120 then
    raise exception 'invalid_input';
  end if;
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  for v_row in
    select trader.id, trader.display_name, trader.phone, trader.active,
      trader.created_at,
      coalesce((
        select count(*)::bigint
        from public.inventory_receipts as receipt
        left join (
          select allocation.receipt_id,
            sum(allocation.milligrams)::bigint as milligrams
          from public.receipt_quantity_allocations as allocation
          where allocation.shop_id = v_shop
          group by allocation.receipt_id
        ) as allocated on allocated.receipt_id = receipt.id
        where receipt.shop_id = v_shop
          and receipt.trader_id = trader.id
          and receipt.milligrams > coalesce(allocated.milligrams, 0)
      ), 0)::bigint as pending_receipt_count
    from public.traders as trader
    where trader.shop_id = v_shop
      and (p_query is null or btrim(p_query) = ''
        or strpos(lower(trader.display_name), lower(p_query)) > 0)
      and (v_at is null or (trader.created_at, trader.id) < (v_at, v_id))
    order by trader.created_at desc, trader.id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.created_at, v_row.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'trader_id', v_row.id,
      'display_name', v_row.display_name,
      'phone', v_row.phone,
      'active', v_row.active,
      'created_at', v_row.created_at,
      'pending_receipt_count', v_row.pending_receipt_count::text,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

revoke all on function public.get_inventory_totals_v1(text, smallint) from public;
revoke all on function public.search_traders_v1(text, integer, text) from public;
grant execute on function public.get_inventory_totals_v1(text, smallint) to authenticated;
grant execute on function public.search_traders_v1(text, integer, text) to authenticated;

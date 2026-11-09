-- Item-by-karat aggregate for «الجرد الفوري» (ADR 0043).
-- Worked jewelry that is owned and available, plus scrap from the same
-- available balance get_inventory_totals_v1 reports.

begin;

create function public.get_inventory_item_grid_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_rows jsonb;
  v_scrap jsonb;
  v_karats jsonb;
begin
  perform private.allow_member_permission('inventory');
  v_shop := private.opening_require_reader_shop();
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'item_name', grouped.item_name,
    'karat', grouped.karat,
    'count', grouped.piece_count::text,
    'count_known', grouped.count_known,
    'milligrams', grouped.milligrams::text
  ) order by grouped.item_name, grouped.karat), '[]'::jsonb)
  into v_rows
  from (
    select product.name as item_name,
      lot.karat,
      coalesce(sum(movement.delta_milligrams), 0)::bigint as milligrams,
      coalesce(sum(movement.delta_count) filter (
        where lot.original_count is not null
      ), 0)::bigint as piece_count,
      not coalesce(bool_or(lot.original_count is null), false) as count_known
    from public.inventory_lots as lot
    join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    left join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
      and lot.stock_class = 'owned_available'
      and lot.category_code = 'worked_jewelry'
    group by product.name, lot.karat
    having coalesce(sum(movement.delta_milligrams), 0) > 0
    order by product.name, lot.karat
    limit 500
  ) as grouped;

  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'karat', scrap.karat,
    'milligrams', scrap.available_mg::text
  ) order by scrap.karat), '[]'::jsonb)
  into v_scrap
  from (
    select lot.karat,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'owned_available'
      ), 0)::bigint as available_mg
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
      and lot.category_code = 'scrap'
    group by lot.karat
  ) as scrap
  where scrap.available_mg > 0;

  select coalesce(pg_catalog.jsonb_agg(present.karat order by present.karat), '[]'::jsonb)
  into v_karats
  from (
    select distinct (item ->> 'karat')::integer as karat
    from pg_catalog.jsonb_array_elements(v_rows) as item
  ) as present;

  return pg_catalog.jsonb_build_object(
    'rows', v_rows,
    'scrap', v_scrap,
    'karats', v_karats
  );
end;
$fn$;

revoke all on function public.get_inventory_item_grid_v1() from public, anon;
grant execute on function public.get_inventory_item_grid_v1() to authenticated;

notify pgrst, 'reload schema';
commit;

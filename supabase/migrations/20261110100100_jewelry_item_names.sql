-- Canonical jewelry names and coin row in the item grid (ADR 0044 C-D2..C-D4).

begin;

create function private.canonical_jewelry_name(p_name text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case pg_catalog.btrim(coalesce(p_name, ''))
    when 'خاتم' then 'خواتم'
    when 'حلق' then 'حلقان'
    when 'سلسلة' then 'سلاسل'
    when 'تعليقة' then 'تعاليق'
    when 'دبلة' then 'دبل'
    when 'محبس' then 'محابس'
    when 'غويشة' then 'غوايش'
    when 'إسورة' then 'اساور'
    when 'اسورة' then 'اساور'
    when 'انسيال' then 'انسيالات'
    when 'كوليه' then 'كوليهات'
    else pg_catalog.btrim(coalesce(p_name, ''))
  end;
$fn$;

revoke all on function private.canonical_jewelry_name(text)
  from public, anon, authenticated;

comment on function private.canonical_jewelry_name(text) is
  'Maps legacy singular jewelry names to the 2026-11-10 plural built-ins (ADR 0044).';

create or replace function private.consume_fifo_named(
  p_shop uuid, p_operation uuid, p_category text, p_karat smallint,
  p_mg bigint, p_count bigint, p_kind text, p_name text
) returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_lot record;
  v_need_mg bigint := p_mg;
  v_need_count bigint := p_count;
  v_rem_mg bigint;
  v_rem_count bigint;
  v_take_mg bigint;
  v_take_count bigint;
  v_new_mg bigint;
  v_new_count bigint;
  v_name text := nullif(private.canonical_jewelry_name(p_name), '');
begin
  if p_mg < 0 or p_count < 0 or (p_mg = 0 and p_count = 0) then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.inventory_lots as lot
  where lot.shop_id = p_shop and lot.category_code = p_category and lot.karat = p_karat
    and lot.stock_class = 'owned_available'
  order by lot.id for update;
  for v_lot in
    select lot.id, lot.tracks_count
    from public.inventory_lots as lot
    left join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    where lot.shop_id = p_shop and lot.category_code = p_category
      and lot.karat = p_karat and lot.stock_class = 'owned_available'
    order by
      case
        when v_name is not null
          and private.canonical_jewelry_name(product.name) = v_name then 0
        when product.name = 'رصيد افتتاحي مجمّع' then 1
        else 2
      end,
      lot.created_at, lot.id
  loop
    exit when v_need_mg = 0 and v_need_count = 0;
    select remaining.milligrams, remaining.piece_count into v_rem_mg, v_rem_count
    from private.lot_remaining(v_lot.id) as remaining;
    if v_rem_mg <= 0 then continue; end if;
    if v_lot.tracks_count then
      if v_rem_count <= 0 then continue; end if;
      v_take_mg := least(v_rem_mg, v_need_mg);
      v_take_count := least(v_rem_count, v_need_count);
      v_new_mg := v_rem_mg - v_take_mg;
      v_new_count := v_rem_count - v_take_count;
      if (v_new_mg = 0) <> (v_new_count = 0) then
        if v_new_mg = 0 and v_new_count > 0 and v_need_count >= v_rem_count then
          v_take_count := v_rem_count;
        elsif v_new_count = 0 and v_new_mg > 0 and v_need_mg >= v_rem_mg then
          v_take_mg := v_rem_mg;
        elsif v_new_mg = 0 and v_new_count > 0 and v_rem_mg > 1 then
          v_take_mg := least(v_take_mg, v_rem_mg - 1);
          if v_rem_count - v_take_count = 0 then
            v_take_count := case when v_rem_count > 1 then least(v_take_count, v_rem_count - 1) else 0 end;
          end if;
        elsif v_new_count = 0 and v_new_mg > 0 and v_rem_count > 1 then
          v_take_count := least(v_take_count, v_rem_count - 1);
          if v_rem_mg - v_take_mg = 0 then
            v_take_mg := case when v_rem_mg > 1 then least(v_take_mg, v_rem_mg - 1) else 0 end;
          end if;
        else
          v_take_mg := 0;
          v_take_count := 0;
        end if;
        v_new_mg := v_rem_mg - v_take_mg;
        v_new_count := v_rem_count - v_take_count;
        if v_take_mg < 0 or v_take_count < 0
          or (v_new_mg = 0) <> (v_new_count = 0) then
          v_take_mg := 0;
          v_take_count := 0;
        end if;
      end if;
    else
      v_take_mg := least(v_rem_mg, v_need_mg);
      v_take_count := 0;
    end if;
    if v_take_mg = 0 and v_take_count = 0 then continue; end if;
    perform private.add_lot_movement(
      p_shop, v_lot.id, p_operation, -v_take_mg, -v_take_count, p_kind, 'deterministic_fifo'
    );
    v_need_mg := v_need_mg - v_take_mg;
    v_need_count := v_need_count - v_take_count;
  end loop;
  if v_need_mg <> 0 or v_need_count <> 0 then
    raise exception 'negative_owned_balance';
  end if;
end;
$fn$;

revoke all on function private.consume_fifo_named(
  uuid, uuid, text, smallint, bigint, bigint, text, text
) from public, anon, authenticated;

create or replace function public.get_inventory_item_grid_v1()
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
    'milligrams', grouped.milligrams::text,
    'category', grouped.category
  ) order by grouped.item_name, grouped.karat), '[]'::jsonb)
  into v_rows
  from (
    select private.canonical_jewelry_name(product.name) as item_name,
      lot.karat,
      'worked_jewelry'::text as category,
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
    group by private.canonical_jewelry_name(product.name), lot.karat
    having coalesce(sum(movement.delta_milligrams), 0) > 0
    union all
    select 'جنيهات'::text as item_name,
      lot.karat,
      'coin'::text as category,
      coalesce(sum(movement.delta_milligrams), 0)::bigint as milligrams,
      coalesce(sum(movement.delta_count) filter (
        where lot.original_count is not null
      ), 0)::bigint as piece_count,
      not coalesce(bool_or(lot.original_count is null), false) as count_known
    from public.inventory_lots as lot
    left join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
      and lot.stock_class = 'owned_available'
      and lot.category_code = 'coin'
    group by lot.karat
    having coalesce(sum(movement.delta_milligrams), 0) > 0
      or coalesce(sum(movement.delta_count) filter (
        where lot.original_count is not null
      ), 0) > 0
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

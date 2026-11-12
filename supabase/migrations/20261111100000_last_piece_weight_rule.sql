-- O1 (device pass 2026-11-11, owner answer 2026-11-11, ADR 0047 D1):
-- selling the last pieces of a named item takes its whole recorded weight;
-- the weight difference is a correction movement on the sale. An edit or
-- delete of that sale (trade-change reversal) puts the correction back on the
-- returned lot, so the item returns exactly as it was recorded.
begin;

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
  v_named_mg bigint;
  v_named_count bigint;
  v_adjust_lot uuid;
  v_adjust_mg bigint;
begin
  if p_mg < 0 or p_count < 0 or (p_mg = 0 and p_count = 0) then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.inventory_lots as lot
  where lot.shop_id = p_shop and lot.category_code = p_category and lot.karat = p_karat
    and lot.stock_class = 'owned_available'
  order by lot.id for update;
  -- O1 (owner answer 2026-11-11): selling every remaining piece of a named
  -- item takes that item's whole recorded weight. The difference between the
  -- recorded and the sold weight is a 'correction' movement on the sale, so
  -- no other item's stock pays for it and the item leaves no residue.
  if v_name is not null and p_count > 0 and not exists (
    select 1
    from public.inventory_lots as lot
    join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    where lot.shop_id = p_shop and lot.category_code = p_category
      and lot.karat = p_karat and lot.stock_class = 'owned_available'
      and not lot.tracks_count
      and private.canonical_jewelry_name(product.name) = v_name
  ) then
    select coalesce(sum(remaining.milligrams), 0)::bigint,
           coalesce(sum(remaining.piece_count), 0)::bigint
    into v_named_mg, v_named_count
    from public.inventory_lots as lot
    join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    cross join lateral private.lot_remaining(lot.id) as remaining
    where lot.shop_id = p_shop and lot.category_code = p_category
      and lot.karat = p_karat and lot.stock_class = 'owned_available'
      and private.canonical_jewelry_name(product.name) = v_name
      and remaining.milligrams > 0 and remaining.piece_count > 0;
    if v_named_count = p_count and v_named_mg > 0 and v_named_mg <> p_mg then
      select lot.id, remaining.milligrams into v_adjust_lot, v_adjust_mg
      from public.inventory_lots as lot
      join public.inventory_products as product
        on product.shop_id = lot.shop_id and product.id = lot.product_id
      cross join lateral private.lot_remaining(lot.id) as remaining
      where lot.shop_id = p_shop and lot.category_code = p_category
        and lot.karat = p_karat and lot.stock_class = 'owned_available'
        and private.canonical_jewelry_name(product.name) = v_name
        and remaining.milligrams > 0 and remaining.piece_count > 0
      order by remaining.milligrams desc, lot.created_at, lot.id
      limit 1;
      if v_adjust_mg + (p_mg - v_named_mg) > 0 then
        perform private.add_lot_movement(
          p_shop, v_adjust_lot, p_operation, p_mg - v_named_mg, 0,
          'correction', 'explicit'
        );
        -- Keep the gold journal equal to the lots (assert_operation_lots).
        perform private.post_account_delta(
          p_shop, p_operation, 'saleable_metal', 'gold_mg', p_category,
          p_karat, null, p_mg - v_named_mg, 'adjustment_gold_clearing', false
        );
      end if;
    end if;
  end if;
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

alter function private.apply_operation_lots(uuid, uuid)
  rename to apply_operation_lots_before_weight_rule;

revoke all on function private.apply_operation_lots_before_weight_rule(uuid, uuid)
  from public, anon, authenticated;

create function private.apply_operation_lots(p_shop uuid, p_operation uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_original uuid;
  v_fix record;
  v_target uuid;
begin
  if exists (
    select 1 from public.inventory_lot_movements as movement
    where movement.operation_id = p_operation
  ) then
    return;
  end if;
  perform private.apply_operation_lots_before_weight_rule(p_shop, p_operation);
  -- Only the trade-change reversal (edit/delete) restores the recorded
  -- weight; a customer's real return keeps the weight actually sold.
  if coalesce(pg_catalog.current_setting('eldaftar.trade_change_net', true), '')
    is distinct from 'on' then
    return;
  end if;
  select operation.kind, (detail.payload ->> 'original_operation_id')::uuid
  into v_kind, v_original
  from public.financial_operations as operation
  join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = p_shop and operation.id = p_operation;
  if v_kind is distinct from 'sale_return' or v_original is null then
    return;
  end if;
  for v_fix in
    select movement.delta_milligrams, lot.category_code, lot.karat,
      private.canonical_jewelry_name(product.name) as item_name
    from public.inventory_lot_movements as movement
    join public.inventory_lots as lot
      on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
    join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    where movement.shop_id = p_shop and movement.operation_id = v_original
      and movement.movement_kind = 'correction'
      and movement.allocation_mode = 'explicit'
    order by movement.created_at, movement.id
  loop
    v_target := null;
    select lot.id into v_target
    from public.inventory_lot_movements as movement
    join public.inventory_lots as lot
      on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
    join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    cross join lateral private.lot_remaining(lot.id) as remaining
    where movement.shop_id = p_shop and movement.operation_id = p_operation
      and movement.delta_milligrams > 0
      and lot.category_code = v_fix.category_code and lot.karat = v_fix.karat
      and private.canonical_jewelry_name(product.name) = v_fix.item_name
      and remaining.milligrams - v_fix.delta_milligrams > 0
    order by remaining.milligrams desc, lot.id
    limit 1;
    if v_target is not null then
      perform private.add_lot_movement(
        p_shop, v_target, p_operation, -v_fix.delta_milligrams, 0,
        'correction', 'explicit'
      );
      perform private.post_account_delta(
        p_shop, p_operation, 'saleable_metal', 'gold_mg', v_fix.category_code,
        v_fix.karat, null, -v_fix.delta_milligrams, 'adjustment_gold_clearing',
        false
      );
    end if;
  end loop;
end;
$fn$;

revoke all on function private.apply_operation_lots(uuid, uuid)
  from public, anon, authenticated;

comment on function private.apply_operation_lots(uuid, uuid) is
  'Applies stock movements; a trade-change sale reversal also undoes the sale''s last-piece weight correction (ADR 0047 D1).';

commit;

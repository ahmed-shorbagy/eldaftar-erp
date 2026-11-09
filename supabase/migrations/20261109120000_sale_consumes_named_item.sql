-- A sale line takes stock from lots of the same item name first, then from
-- pooled opening stock, then from the oldest lot of the same category and
-- karat (ADR 0043, B-D14). Before this, every sale took the oldest lot, so
-- selling «خاتم» could reduce «سلسلة» in the item-by-karat table.
-- Category and karat balances are unchanged: only the choice of lot moves.

begin;

create function private.consume_fifo_named(
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
  v_name text := nullif(pg_catalog.btrim(coalesce(p_name, '')), '');
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
        when v_name is not null and product.name = v_name then 0
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

do $patch_sale_lots$
declare
  v_def text;
  v_old text := $old$        perform private.consume_fifo(
          p_shop, p_operation, v_category, v_karat, v_mg, v_count, v_kind
        );$old$;
  v_new text := $new$        perform private.consume_fifo_named(
          p_shop, p_operation, v_category, v_karat, v_mg, v_count, v_kind,
          v_line ->> 'item_name'
        );$new$;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'private.apply_operation_lots_before_compensation(uuid, uuid)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
      / pg_catalog.length(v_old) <> 1 then
    raise exception 'sale_lot_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_sale_lots$;

notify pgrst, 'reload schema';
commit;

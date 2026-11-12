-- O2 (device pass 2026-11-11): older backfills named the pooled opening lots
-- «رصيد سابق مجمّع» (legacy_aggregate) instead of «رصيد افتتاحي مجمّع».
-- Treat both as the pooled opening stock: the item grid groups them into the
-- one «رصيد افتتاحي» row, and a named sale takes pooled stock second (after
-- the named item, before other items' lots), as ADR 0043 B-D14 requires.
begin;

create or replace function private.canonical_jewelry_name(p_name text)
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
    when 'رصيد سابق مجمّع' then 'رصيد افتتاحي مجمّع'
    else pg_catalog.btrim(coalesce(p_name, ''))
  end;
$fn$;

revoke all on function private.canonical_jewelry_name(text)
  from public, anon, authenticated;

comment on function private.canonical_jewelry_name(text) is
  'Maps legacy singular jewelry names to the 2026-11-10 plural built-ins (ADR 0044) and the legacy pooled lot name to «رصيد افتتاحي مجمّع» (O2).';

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
        when lot.legacy_aggregate
          or private.canonical_jewelry_name(product.name) = 'رصيد افتتاحي مجمّع' then 1
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

notify pgrst, 'reload schema';
commit;

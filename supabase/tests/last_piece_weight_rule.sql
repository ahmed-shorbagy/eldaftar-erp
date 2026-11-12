-- O1 / ADR 0047 D1: selling the last pieces of a named item takes its whole
-- recorded weight; the difference is a correction on the sale, never another
-- item's stock. Deleting or editing that sale restores the recorded weight.
-- One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('f4700000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'last-piece-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('f4700000-0000-4000-8000-0000000000a1', 'متجر آخر قطعة', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('f4700000-0000-4000-8000-0000000000a1', 'f4700000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('f4700000-0000-4000-8000-0000000000a1', now() - interval '1 day', now() + interval '30 days');

do $priv$
begin
  if has_function_privilege('authenticated', 'private.apply_operation_lots(uuid,uuid)', 'execute')
    or has_function_privilege('authenticated', 'private.apply_operation_lots_before_weight_rule(uuid,uuid)', 'execute')
    or has_function_privilege('authenticated', 'private.consume_fifo_named(uuid,uuid,text,smallint,bigint,bigint,text,text)', 'execute') then
    raise exception 'private_function_granted';
  end if;
end;
$priv$;

create function pg_temp.with_day(p_payload jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $fn$
declare v_state jsonb;
begin
  v_state := public.get_daily_ledger_day_state();
  return p_payload || jsonb_build_object(
    'expected_day_id', v_state ->> 'business_day_id',
    'expected_day_version', v_state ->> 'day_version'
  );
end;
$fn$;

create function pg_temp.grid_cell(p_name text, p_karat int)
returns jsonb language sql security invoker set search_path = '' as $fn$
  select item from pg_catalog.jsonb_array_elements(public.get_inventory_item_grid_v1() -> 'rows') as item
  where item ->> 'item_name' = p_name and (item ->> 'karat')::int = p_karat;
$fn$;

create function pg_temp.add_item(p_key uuid, p_name text, p_mg text, p_count text)
returns void language plpgsql security invoker set search_path = '' as $fn$
begin
  perform public.post_inventory_addition_v1(
    p_key,
    pg_temp.with_day(jsonb_build_object(
      'version', 1, 'kind', 'inventory_addition', 'reason', p_name,
      'lines', jsonb_build_array(jsonb_build_object(
        'item_name', p_name, 'category', 'worked_jewelry', 'karat', 21,
        'milligrams', p_mg, 'count', p_count,
        'denomination_id', null, 'coin_type_id', null)))));
end;
$fn$;

create function pg_temp.sale(p_name text, p_mg text, p_count text)
returns jsonb language sql immutable as $fn$
  select jsonb_build_object(
    'version', 1, 'kind', 'sale', 'total_piastres', '1000',
    'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '1000')),
    'items', jsonb_build_array(jsonb_build_object(
      'category', 'worked_jewelry', 'karat', 21, 'milligrams', p_mg,
      'count', p_count, 'item_name', p_name, 'line_price_piastres', null)),
    'description', '', 'customer_name', '', 'customer_phone', '', 'note', '');
$fn$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f4700000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'f4700000-0000-4000-8000-000000000100',
  '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
);

do $rule$
declare
  v_result jsonb;
  v_sale uuid;
  v_review jsonb;
  v_posted jsonb;
  v_cell jsonb;
  v_correction bigint;
begin
  perform pg_temp.add_item('f4700000-0000-4000-8000-000000000101', 'سلسلة', '10500', '1');
  perform pg_temp.add_item('f4700000-0000-4000-8000-000000000102', 'خاتم', '4000', '2');
  perform pg_temp.add_item('f4700000-0000-4000-8000-000000000103', 'حلق', '6000', '2');
  perform pg_temp.add_item('f4700000-0000-4000-8000-000000000104', 'دبلة', '3000', '1');

  -- 1. Lighter than recorded: the chain leaves completely, rings untouched.
  v_result := public.post_daily_ledger_trade(
    'f4700000-0000-4000-8000-000000000201', pg_temp.sale('سلاسل', '10000', '1'));
  v_sale := (v_result ->> 'operation_id')::uuid;
  if pg_temp.grid_cell('سلاسل', 21) is not null then
    raise exception 'chain_residue_left %', pg_temp.grid_cell('سلاسل', 21);
  end if;
  v_cell := pg_temp.grid_cell('خواتم', 21);
  if v_cell ->> 'count' is distinct from '2' or v_cell ->> 'milligrams' is distinct from '4000' then
    raise exception 'rings_paid_for_chain %', v_cell;
  end if;
  select sum(movement.delta_milligrams) into v_correction
  from public.inventory_lot_movements as movement
  where movement.operation_id = v_sale and movement.movement_kind = 'correction';
  if v_correction is distinct from -500 then
    raise exception 'correction_movement %', v_correction;
  end if;

  -- 2. Deleting that sale restores the chain exactly as recorded.
  v_review := public.review_ledger_trade_change_v1(v_sale, 'delete', null);
  v_posted := public.post_ledger_trade_change_v1(
    'f4700000-0000-4000-8000-000000000202', v_sale, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token');
  if v_posted ->> 'ok' is distinct from 'true' then
    raise exception 'delete_failed %', v_posted;
  end if;
  v_cell := pg_temp.grid_cell('سلاسل', 21);
  if v_cell ->> 'count' is distinct from '1' or v_cell ->> 'milligrams' is distinct from '10500' then
    raise exception 'chain_not_restored %', v_cell;
  end if;

  -- 3. Heavier than recorded: the band leaves, the extra is a correction.
  v_result := public.post_daily_ledger_trade(
    'f4700000-0000-4000-8000-000000000203', pg_temp.sale('دبل', '3200', '1'));
  if pg_temp.grid_cell('دبل', 21) is not null then
    raise exception 'band_left %', pg_temp.grid_cell('دبل', 21);
  end if;
  v_cell := pg_temp.grid_cell('خواتم', 21);
  if v_cell ->> 'milligrams' is distinct from '4000' then
    raise exception 'rings_paid_for_band %', v_cell;
  end if;

  -- 4. Not the last piece: ordinary consumption, no correction.
  v_result := public.post_daily_ledger_trade(
    'f4700000-0000-4000-8000-000000000204', pg_temp.sale('حلقان', '2500', '1'));
  v_cell := pg_temp.grid_cell('حلقان', 21);
  if v_cell ->> 'count' is distinct from '1' or v_cell ->> 'milligrams' is distinct from '3500' then
    raise exception 'partial_wrong %', v_cell;
  end if;
  if exists (
    select 1 from public.inventory_lot_movements as movement
    where movement.operation_id = (v_result ->> 'operation_id')::uuid
      and movement.movement_kind = 'correction'
  ) then
    raise exception 'partial_has_correction';
  end if;

  -- 5. Edit of a last-piece sale: reversal restores, the replacement applies
  -- the rule again at the new weight.
  v_result := public.post_daily_ledger_trade(
    'f4700000-0000-4000-8000-000000000205', pg_temp.sale('سلاسل', '10000', '1'));
  v_sale := (v_result ->> 'operation_id')::uuid;
  -- Build a replacement with a different weight from the stored payload.
  v_review := public.review_ledger_trade_change_v1(
    v_sale, 'edit',
    jsonb_set(
      public.review_ledger_trade_change_v1(v_sale, 'delete', null) -> 'source' -> 'payload',
      '{items,0,milligrams}', '"9800"'));
  v_posted := public.post_ledger_trade_change_v1(
    'f4700000-0000-4000-8000-000000000206', v_sale, 'edit',
    jsonb_set(
      public.review_ledger_trade_change_v1(v_sale, 'delete', null) -> 'source' -> 'payload',
      '{items,0,milligrams}', '"9800"'),
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token');
  if v_posted ->> 'ok' is distinct from 'true' then
    raise exception 'edit_failed %', v_posted;
  end if;
  if pg_temp.grid_cell('سلاسل', 21) is not null then
    raise exception 'edit_left_chain_residue %', pg_temp.grid_cell('سلاسل', 21);
  end if;
  v_cell := pg_temp.grid_cell('خواتم', 21);
  if v_cell ->> 'count' is distinct from '2' or v_cell ->> 'milligrams' is distinct from '4000' then
    raise exception 'edit_took_rings %', v_cell;
  end if;
end;
$rule$;

select 'LAST_PIECE_WEIGHT_RULE_PASSED' as result;
rollback;

-- Closing a day must not change customer data or the instant-inventory table.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values (
  'f1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'close-keep@example.test', false, now(), now()
);
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('f2200000-0000-4000-8000-000000000001', 'متجر ثبات التقفيل', 'مالك الثبات', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('f2200000-0000-4000-8000-000000000001', 'f1100000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('f2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

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

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'f3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"8000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"9000","count":"4"}],"scrap":[{"karat":18,"milligrams":"3000"}]}'::jsonb
);

do $keep$
declare
  v_shop uuid := 'f2200000-0000-4000-8000-000000000001';
  v_customers jsonb;
  v_phones jsonb;
  v_links jsonb;
  v_events jsonb;
  v_notes jsonb;
  v_lots jsonb;
  v_grid jsonb;
  v_state jsonb;
  v_counts jsonb;
begin
  if (public.post_inventory_addition_v1(
    'f3300000-0000-4000-8000-000000000011',
    pg_temp.with_day('{"version":1,"kind":"inventory_addition","reason":"خاتم ثابت","lines":[{"item_name":"خاتم","category":"worked_jewelry","karat":21,"milligrams":"2500","count":"2","denomination_id":null,"coin_type_id":null}]}'::jsonb)
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'inventory_seed_failed';
  end if;
  perform public.post_daily_ledger_trade(
    'f3300000-0000-4000-8000-000000000012',
    '{"version":1,"kind":"sale","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"هبة","customer_phone":"01012121212","note":""}'::jsonb
  );
  perform public.post_customer_note_v1(
    'f3300000-0000-4000-8000-000000000013',
    jsonb_build_object(
      'version', 1, 'kind', 'customer_note',
      'customer_id', (
        select customer.id::text from public.customers as customer
        where customer.shop_id = v_shop and customer.display_name = 'هبة'
      ),
      'expected_version', (
        select customer.record_version::text from public.customers as customer
        where customer.shop_id = v_shop and customer.display_name = 'هبة'
      ),
      'body', 'ملاحظة تبقى بعد التقفيل'
    )
  );

  select coalesce(jsonb_agg(to_jsonb(customer) order by customer.id), '[]'::jsonb)
    into v_customers from public.customers as customer where customer.shop_id = v_shop;
  select coalesce(jsonb_agg(to_jsonb(phone) order by phone.id), '[]'::jsonb)
    into v_phones from public.customer_phones as phone where phone.shop_id = v_shop;
  select coalesce(jsonb_agg(to_jsonb(link) order by link.id), '[]'::jsonb)
    into v_links from public.customer_operation_links as link where link.shop_id = v_shop;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', event.id, 'type', event.event_type, 'customer_id', event.customer_id
    ) order by event.id), '[]'::jsonb)
    into v_events from public.customer_events as event where event.shop_id = v_shop;
  select coalesce(jsonb_agg(to_jsonb(note) order by note.id), '[]'::jsonb)
    into v_notes from public.customer_notes as note where note.shop_id = v_shop;
  select coalesce(jsonb_agg(row_to_json(lot_row)::jsonb order by lot_row.lot_id), '[]'::jsonb)
    into v_lots
  from (
    select lot.id as lot_id,
      coalesce(sum(movement.delta_milligrams), 0) as milligrams,
      coalesce(sum(movement.delta_count), 0) as pieces
    from public.inventory_lots as lot
    left join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
    group by lot.id
  ) as lot_row;
  v_grid := public.get_inventory_item_grid_v1();

  v_state := public.get_daily_ledger_day_state();
  v_counts := jsonb_build_object(
    'version', 2,
    'cash', v_state #> '{counts,cash}',
    'scrap', v_state #> '{counts,scrap}',
    'stock', coalesce((
      select jsonb_agg(jsonb_build_object(
        'item_name', 'خاتم',
        'category', item ->> 'category',
        'karat', item -> 'karat',
        'count', item ->> 'count',
        'milligrams', 'null'::jsonb
      ))
      from jsonb_array_elements(v_state #> '{counts,stock}') as item
    ), '[]'::jsonb)
  );
  if (public.close_daily_ledger_day_v2(
    'f3300000-0000-4000-8000-000000000014',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    v_counts
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'close_failed %', v_counts;
  end if;

  if (select coalesce(jsonb_agg(to_jsonb(customer) order by customer.id), '[]'::jsonb)
      from public.customers as customer where customer.shop_id = v_shop) is distinct from v_customers
    or (select coalesce(jsonb_agg(to_jsonb(phone) order by phone.id), '[]'::jsonb)
        from public.customer_phones as phone where phone.shop_id = v_shop) is distinct from v_phones
    or (select coalesce(jsonb_agg(to_jsonb(link) order by link.id), '[]'::jsonb)
        from public.customer_operation_links as link where link.shop_id = v_shop) is distinct from v_links
    or (select coalesce(jsonb_agg(jsonb_build_object(
          'id', event.id, 'type', event.event_type, 'customer_id', event.customer_id
        ) order by event.id), '[]'::jsonb)
        from public.customer_events as event where event.shop_id = v_shop) is distinct from v_events
    or (select coalesce(jsonb_agg(to_jsonb(note) order by note.id), '[]'::jsonb)
        from public.customer_notes as note where note.shop_id = v_shop) is distinct from v_notes then
    raise exception 'close_changed_customer_data';
  end if;
  if (select coalesce(jsonb_agg(row_to_json(lot_row)::jsonb order by lot_row.lot_id), '[]'::jsonb)
      from (
        select lot.id as lot_id,
          coalesce(sum(movement.delta_milligrams), 0) as milligrams,
          coalesce(sum(movement.delta_count), 0) as pieces
        from public.inventory_lots as lot
        left join public.inventory_lot_movements as movement
          on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
        where lot.shop_id = v_shop
        group by lot.id
      ) as lot_row) is distinct from v_lots
    or public.get_inventory_item_grid_v1() is distinct from v_grid then
    raise exception 'close_changed_inventory_table';
  end if;
end;
$keep$;

rollback;

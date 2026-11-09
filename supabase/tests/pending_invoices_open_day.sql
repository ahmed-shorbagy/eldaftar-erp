-- Pending invoices: open-day sales only. The transaction rolls back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('a1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pending-a@example.test', false, now(), now()),
  ('a1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pending-b@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('a2200000-0000-4000-8000-000000000001', 'متجر المعلق', 'مالك المعلق', 'Africa/Cairo'),
  ('a2200000-0000-4000-8000-000000000002', 'متجر الآخر', 'مالك الآخر', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('a2200000-0000-4000-8000-000000000001', 'a1100000-0000-4000-8000-000000000001', 'owner'),
  ('a2200000-0000-4000-8000-000000000002', 'a1100000-0000-4000-8000-000000000002', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days'),
  ('a2200000-0000-4000-8000-000000000002', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);

select public.confirm_opening_balances(
  'a3300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"2000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"8000","count":"4"}],"scrap":[{"karat":21,"milligrams":"5000"}]}'::jsonb
);

do $pending$
declare
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"10000","tenders":[{"method":"cash","piastres":"10000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"عميل","customer_phone":"","note":""}'::jsonb;
  v_sent jsonb := '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"سلسلة","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_hidden jsonb := '{"version":1,"kind":"sale","total_piastres":"4000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"حلق","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_purchase jsonb := '{"version":1,"kind":"purchase","total_piastres":"3000","tenders":[{"method":"cash","piastres":"3000"}],"items":[{"category":"scrap","karat":21,"milligrams":"500","count":null,"item_name":"كسر","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_sale_id uuid;
  v_hidden_id uuid;
  v_page jsonb;
  v_review jsonb;
  v_state jsonb;
  v_counts jsonb;
  v_closed date;
begin
  v_sale_id := (public.post_daily_ledger_trade('a3300000-0000-4000-8000-000000000011', v_sale) ->> 'operation_id')::uuid;
  perform public.post_daily_ledger_trade('a3300000-0000-4000-8000-000000000012', v_purchase);
  perform public.confirm_invoice_whatsapp_send(
    (public.post_daily_ledger_trade('a3300000-0000-4000-8000-000000000013', v_sent) ->> 'operation_id')::uuid,
    'a3300000-0000-4000-8000-000000000014'
  );
  v_hidden_id := (public.post_daily_ledger_trade('a3300000-0000-4000-8000-000000000015', v_hidden) ->> 'operation_id')::uuid;

  v_page := public.get_pending_invoice_sends(null);
  if jsonb_array_length(v_page -> 'items') <> 2
    or not exists (
      select 1 from jsonb_array_elements(v_page -> 'items') as item
      where item ->> 'operation_id' = v_sale_id::text and item ->> 'kind' = 'sale'
    )
    or exists (
      select 1 from jsonb_array_elements(v_page -> 'items') as item
      where item ->> 'kind' = 'purchase'
    ) then
    raise exception 'open_day_sales_wrong %', v_page;
  end if;

  v_review := public.review_ledger_trade_change_v1(v_hidden_id, 'delete', null);
  perform public.post_ledger_trade_change_v1(
    'a3300000-0000-4000-8000-000000000016', v_hidden_id, 'delete', null,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256', v_review ->> 'review_token'
  );
  v_page := public.get_pending_invoice_sends(null);
  if exists (
    select 1 from jsonb_array_elements(v_page -> 'items') as item
    where item ->> 'operation_id' = v_hidden_id::text
  ) or jsonb_array_length(v_page -> 'items') <> 1 then
    raise exception 'hidden_sale_still_listed %', v_page;
  end if;

  v_state := public.get_daily_ledger_day_state();
  v_closed := (v_state ->> 'business_date')::date;
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
    'a3300000-0000-4000-8000-000000000017',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    v_counts
  ) ->> 'ok') is distinct from 'true' then
    raise exception 'close_failed';
  end if;
  if jsonb_array_length(public.get_pending_invoice_sends(null) -> 'items') <> 0 then
    raise exception 'closed_day_still_lists_sales';
  end if;

  perform public.open_daily_ledger_day('a3300000-0000-4000-8000-000000000018');
  if jsonb_array_length(public.get_pending_invoice_sends(null) -> 'items') <> 0 then
    raise exception 'old_sale_carried_forward';
  end if;
  perform public.post_daily_ledger_trade('a3300000-0000-4000-8000-000000000019', v_sale);
  v_page := public.get_pending_invoice_sends(null);
  if jsonb_array_length(v_page -> 'items') <> 1
    or (v_page #>> '{items,0,operation_id}') = v_sale_id::text then
    raise exception 'new_day_sale_wrong %', v_page;
  end if;

  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000002', true);
  perform public.confirm_opening_balances(
    'a3300000-0000-4000-8000-000000000021',
    '{"version":1,"cash":{"cash":"1000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"8000","count":"4"}],"scrap":[]}'::jsonb
  );
  perform public.post_daily_ledger_trade('a3300000-0000-4000-8000-000000000022', v_sale);
  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000001', true);
  if exists (
    select 1 from jsonb_array_elements(public.get_pending_invoice_sends(null) -> 'items') as item
    where item ->> 'operation_id' in (
      select operation.id::text from public.financial_operations as operation
      where operation.shop_id = 'a2200000-0000-4000-8000-000000000002'
    )
  ) then
    raise exception 'other_shop_sale_leaked';
  end if;
  if v_closed is null then
    raise exception 'closed_date_missing';
  end if;
end;
$pending$;

rollback;

-- ADR 0033 staff grants on the entry points the app calls (2026-11-15 regression).
-- Rolled back. Each call starts like a fresh PostgREST request: the declared
-- grant from an earlier call is cleared first, so no call inherits another's.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('a5500000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'staff-entry-owner@example.test', false, now(), now()),
  ('a5500000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'staff-entry-partner@example.test', false, now(), now()),
  ('a5500000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'staff-entry-seller@example.test', false, now(), now()),
  ('a5500000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'staff-entry-limited@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('a5500000-0000-4000-8000-000000000010', 'متجر صلاحيات الموظفين', 'مالك الصلاحيات', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('a5500000-0000-4000-8000-000000000010', 'a5500000-0000-4000-8000-000000000001', 'owner'),
  ('a5500000-0000-4000-8000-000000000010', 'a5500000-0000-4000-8000-000000000002', 'partner'),
  ('a5500000-0000-4000-8000-000000000010', 'a5500000-0000-4000-8000-000000000003', 'employee'),
  ('a5500000-0000-4000-8000-000000000010', 'a5500000-0000-4000-8000-000000000004', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by)
select 'a5500000-0000-4000-8000-000000000010', member.user_id, member.permission,
  'a5500000-0000-4000-8000-000000000001'
from (values
  ('a5500000-0000-4000-8000-000000000002'::uuid, 'sale'),
  ('a5500000-0000-4000-8000-000000000002'::uuid, 'purchase'),
  ('a5500000-0000-4000-8000-000000000002'::uuid, 'inventory'),
  ('a5500000-0000-4000-8000-000000000002'::uuid, 'expense'),
  ('a5500000-0000-4000-8000-000000000002'::uuid, 'reports'),
  ('a5500000-0000-4000-8000-000000000002'::uuid, 'invoice_send'),
  ('a5500000-0000-4000-8000-000000000003'::uuid, 'sale'),
  ('a5500000-0000-4000-8000-000000000003'::uuid, 'invoice_send'),
  ('a5500000-0000-4000-8000-000000000003'::uuid, 'reports'),
  ('a5500000-0000-4000-8000-000000000004'::uuid, 'sale')
) as member(user_id, permission);
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a5500000-0000-4000-8000-000000000010', now() - interval '1 day', now() + interval '30 days');

-- Runs one statement as a user, like a new request; returns its result or 'ERROR <message>'.
create function pg_temp.call_as(p_user uuid, p_sql text)
returns text language plpgsql security invoker set search_path = '' as $fn$
declare
  v_result text;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user::text, true);
  perform pg_catalog.set_config('request.jwt.claim.session_id', '', true);
  perform pg_catalog.set_config('app.required_shop_permission', '', true);
  execute p_sql into v_result;
  return coalesce(v_result, 'null');
exception when others then
  return 'ERROR ' || sqlerrm;
end;
$fn$;

create function pg_temp.trade(p_kind text, p_karat int, p_category text, p_mg text, p_count text, p_name text, p_piastres text)
returns text language sql immutable as $fn$
  select 'select public.post_daily_ledger_trade(gen_random_uuid(), '
    || pg_catalog.quote_literal(pg_catalog.jsonb_build_object(
      'version', 1, 'kind', p_kind, 'total_piastres', p_piastres,
      'tenders', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('method', 'cash', 'piastres', p_piastres)),
      'items', case when p_kind = 'expense' then '[]'::jsonb else pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'category', p_category, 'karat', p_karat, 'milligrams', p_mg,
        'count', case when p_count is null then 'null'::jsonb else pg_catalog.to_jsonb(p_count) end,
        'item_name', p_name, 'line_price_piastres', null)) end,
      'description', case when p_kind = 'expense' then 'مصروف اختبار' else '' end,
      'customer_name', '', 'customer_phone', '', 'note', ''
    )::text) || '::jsonb)::text';
$fn$;

set local role authenticated;

do $suite$
declare
  v_owner uuid := 'a5500000-0000-4000-8000-000000000001';
  v_partner uuid := 'a5500000-0000-4000-8000-000000000002';
  v_seller uuid := 'a5500000-0000-4000-8000-000000000003';
  v_limited uuid := 'a5500000-0000-4000-8000-000000000004';
  v_r text;
  v_owner_sale uuid;
  v_seller_sale uuid;
  v_day uuid;
  v_feed jsonb;
begin
  v_r := pg_temp.call_as(v_owner, 'select public.confirm_opening_balances(gen_random_uuid(), '
    || quote_literal('{"version":1,"cash":{"cash":"5000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"40000","count":"8"},{"category":"worked_jewelry","karat":18,"milligrams":"20000","count":"5"}],"scrap":[{"karat":18,"milligrams":"6000"}]}')
    || '::jsonb)::text');
  if v_r like 'ERROR%' then raise exception 'opening_failed %', v_r; end if;
  v_day := (v_r::jsonb ->> 'business_day_id')::uuid;

  -- Owner is unaffected.
  v_r := pg_temp.call_as(v_owner, pg_temp.trade('sale', 21, 'worked_jewelry', '5000', '1', 'خاتم', '2000000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'owner_sale %', v_r; end if;
  v_owner_sale := (v_r::jsonb ->> 'operation_id')::uuid;

  -- Employee with the sale grant records a sale (the 2026-11-15 defect).
  v_r := pg_temp.call_as(v_seller, pg_temp.trade('sale', 18, 'worked_jewelry', '4000', '1', 'خاتم', '1000000'));
  if v_r like 'ERROR%' or (v_r::jsonb ->> 'ok') is distinct from 'true' then
    raise exception 'employee_sale_with_grant %', v_r;
  end if;
  v_seller_sale := (v_r::jsonb ->> 'operation_id')::uuid;
  if (select operation.actor_user_id from public.financial_operations as operation
      where operation.id = v_seller_sale) is distinct from v_seller then
    raise exception 'employee_sale_actor';
  end if;

  -- The declared grant does not outlive the wrapper: an owner-only read later in
  -- the same transaction, without clearing anything in between, is refused.
  perform pg_catalog.set_config('app.required_shop_permission', '', true);
  v_r := pg_temp.call_as(v_seller, pg_temp.trade('sale', 18, 'worked_jewelry', '1000', '1', 'خاتم', '100000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'employee_second_sale %', v_r; end if;
  if coalesce(current_setting('app.required_shop_permission', true), '') <> '' then
    raise exception 'grant_leaked_after_trade %', current_setting('app.required_shop_permission', true);
  end if;
  begin
    perform public.get_customer_overview_v1();
    raise exception 'customer_overview_allowed_after_sale';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then raise exception 'customer_overview_after_sale %', sqlerrm; end if;
  end;

  -- Grants are still enforced per kind.
  v_r := pg_temp.call_as(v_limited, pg_temp.trade('purchase', 18, 'scrap', '1000', null, 'كسر', '300000'));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'limited_purchase %', v_r; end if;
  v_r := pg_temp.call_as(v_limited, pg_temp.trade('expense', null, null, null, null, null, '1000'));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'limited_expense %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, 'select public.post_daily_ledger_trade(gen_random_uuid(), '
    || quote_literal('{"version":1,"kind":"customer_return","total_piastres":"1","tenders":[],"items":[],"customer_name":"","customer_phone":"","note":""}')
    || '::jsonb)::text');
  if v_r is distinct from 'ERROR forbidden' then raise exception 'unknown_kind_stays_owner_only %', v_r; end if;

  -- A full partner records purchase, expense and scrap sale.
  v_r := pg_temp.call_as(v_partner, pg_temp.trade('purchase', 18, 'scrap', '1000', null, 'كسر', '300000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'partner_purchase %', v_r; end if;
  v_r := pg_temp.call_as(v_partner, pg_temp.trade('expense', null, null, null, null, null, '1000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'partner_expense %', v_r; end if;
  v_r := pg_temp.call_as(v_partner, pg_temp.trade('scrap_sale', 18, 'scrap', '1000', null, 'كسر', '300000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'partner_scrap_sale %', v_r; end if;

  -- Employee home: own operations only, no shop balances (zero cash amounts,
  -- no stock or scrap; see employee_ledger_reads.sql for the full read model).
  v_r := pg_temp.call_as(v_seller, 'select public.get_daily_ledger_home_v2()::text');
  if v_r like 'ERROR%' then raise exception 'employee_home %', v_r; end if;
  v_feed := v_r::jsonb -> 'feed';
  if exists (
      select 1 from jsonb_array_elements(coalesce(v_r::jsonb -> 'cash', '[]'::jsonb)) as line
      where line ->> 'piastres' is distinct from '0'
    )
    or coalesce(v_r::jsonb -> 'stock', '[]'::jsonb) <> '[]'::jsonb
    or coalesce(v_r::jsonb -> 'scrap', '[]'::jsonb) <> '[]'::jsonb
    or jsonb_array_length(v_feed) <> 2
    or exists (
      select 1 from jsonb_array_elements(v_feed) as item
      join public.financial_operations as operation on operation.id = (item ->> 'operation_id')::uuid
      where operation.actor_user_id is distinct from v_seller
    ) then
    raise exception 'employee_home_scope %', v_r;
  end if;

  -- Inventory totals follow the inventory grant again.
  v_r := pg_temp.call_as(v_partner, 'select public.get_inventory_totals_v1(null, null)::text');
  if v_r like 'ERROR%' then raise exception 'partner_inventory_totals %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, 'select public.get_inventory_totals_v1(null, null)::text');
  if v_r is distinct from 'ERROR forbidden' then raise exception 'employee_inventory_totals %', v_r; end if;

  -- Day reads: partner sees the shop day; an employee sees only their own
  -- operations and their own totals, never shop totals.
  v_r := pg_temp.call_as(v_partner, format('select public.get_ledger_day_v1(%L::uuid, null, 100)::text', v_day));
  if v_r like 'ERROR%' or jsonb_array_length(v_r::jsonb #> '{feed_page,items}') < 5 then
    raise exception 'partner_ledger_day %', left(v_r, 300);
  end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_ledger_day_v1(%L::uuid, null, 100)::text', v_day));
  if v_r like 'ERROR%' then raise exception 'employee_ledger_day %', v_r; end if;
  if exists (
    select 1 from jsonb_array_elements(v_r::jsonb #> '{feed_page,items}') as item
    left join public.financial_operations as operation on operation.id = (item ->> 'operation_id')::uuid
    where operation.actor_user_id is distinct from v_seller
  ) or (v_r::jsonb #>> '{day_summary,sale_piastres}') is distinct from '1100000'
    or v_r::jsonb ? 'cash' then
    raise exception 'employee_ledger_day_scope %', left(v_r, 400);
  end if;
  v_r := pg_temp.call_as(v_partner, format('select public.get_ledger_operation_page_v2(%L::uuid, null, null, 100)::text', v_day));
  if v_r like 'ERROR%' then raise exception 'partner_operation_page %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_ledger_operation_page_v2(%L::uuid, null, null, 100)::text', v_day));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'employee_operation_page %', left(v_r, 200); end if;

  -- Invoices: invoice_send grant, employee limited to own sales.
  v_r := pg_temp.call_as(v_seller, format('select public.get_invoice_dispatch_state(%L::uuid)::text', v_seller_sale));
  if v_r like 'ERROR%' then raise exception 'employee_own_dispatch %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_invoice_brand_source_v1(%L::uuid)::text', v_seller_sale));
  if v_r like 'ERROR%' then raise exception 'employee_own_brand_source %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_invoice_presentations_v1(%L::uuid)::text', v_seller_sale));
  if v_r like 'ERROR%' then raise exception 'employee_own_presentations %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, 'select public.get_invoice_appearance_v1()::text');
  if v_r like 'ERROR%' then raise exception 'employee_appearance %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_invoice_dispatch_state(%L::uuid)::text', v_owner_sale));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'employee_other_dispatch %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_invoice_message_source_v1(%L::uuid)::text', v_owner_sale));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'employee_other_message_source %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, format('select public.confirm_invoice_whatsapp_send(%L::uuid, gen_random_uuid())::text', v_owner_sale));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'employee_other_confirm %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, 'select public.post_invoice_presentation_v2(gen_random_uuid(), '
    || quote_literal(jsonb_build_object('operation_id', v_owner_sale)::text) || '::jsonb)::text');
  if v_r is distinct from 'ERROR forbidden' then raise exception 'employee_other_presentation %', v_r; end if;
  v_r := pg_temp.call_as(v_limited, format('select public.get_invoice_dispatch_state(%L::uuid)::text', v_owner_sale));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'no_grant_dispatch %', v_r; end if;
  v_r := pg_temp.call_as(v_partner, format('select public.get_invoice_presentations_v1(%L::uuid)::text', v_owner_sale));
  if v_r like 'ERROR%' then raise exception 'partner_presentations %', v_r; end if;

  v_r := pg_temp.call_as(v_seller, 'select public.get_pending_invoice_sends(null)::text');
  if v_r like 'ERROR%'
    or jsonb_array_length(v_r::jsonb -> 'items') <> 2
    or exists (
      select 1 from jsonb_array_elements(v_r::jsonb -> 'items') as item
      join public.financial_operations as operation on operation.id = (item ->> 'operation_id')::uuid
      where operation.actor_user_id is distinct from v_seller
    ) then
    raise exception 'employee_pending_scope %', v_r;
  end if;
  v_r := pg_temp.call_as(v_owner, 'select public.get_pending_invoice_sends(null)::text');
  if v_r like 'ERROR%' or jsonb_array_length(v_r::jsonb -> 'items') <> 3 then
    raise exception 'owner_pending %', v_r;
  end if;
  v_r := pg_temp.call_as(v_seller, format('select public.confirm_invoice_whatsapp_send(%L::uuid, gen_random_uuid())::text', v_seller_sale));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'employee_own_confirm %', v_r; end if;

  -- Owner-only stays owner-only.
  v_r := pg_temp.call_as(v_partner, 'select public.list_shop_payment_methods_v1()::text');
  if v_r is distinct from 'ERROR forbidden' then raise exception 'partner_payment_methods %', v_r; end if;
  v_r := pg_temp.call_as(v_partner, format(
    'select public.close_daily_ledger_day_v2(gen_random_uuid(), %L::uuid, 1, ''{"version":2,"cash":{},"scrap":[],"stock":[]}''::jsonb)::text', v_day));
  if v_r is distinct from 'ERROR forbidden' then raise exception 'partner_close %', v_r; end if;

  raise notice 'STAFF_GRANT_ENTRY_POINTS_PASSED';
end;
$suite$;

rollback;

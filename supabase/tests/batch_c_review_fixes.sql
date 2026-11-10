-- Batch C review fixes (ADR 0044): legacy feed vocabulary, WhatsApp-group flag
-- for current and 361ad2e payloads, the whatsapp_group filter, and «مرمة»
-- audit labels. Synthetic rows roll back.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('cb100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'review-owner@example.test', false, now(), now()),
  ('cb100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'review-staff@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('cb200000-0000-4000-8000-000000000001', 'متجر المراجعة', 'مالك المراجعة', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('cb200000-0000-4000-8000-000000000001', 'cb100000-0000-4000-8000-000000000001', 'owner'),
  ('cb200000-0000-4000-8000-000000000001', 'cb100000-0000-4000-8000-000000000002', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by) values
  ('cb200000-0000-4000-8000-000000000001', 'cb100000-0000-4000-8000-000000000002', 'sale', 'cb100000-0000-4000-8000-000000000001');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('cb200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

-- Legacy feed normalizer: known kinds only, 361ad2e labels and keys.
do $feed$
declare
  v_rows jsonb := pg_catalog.jsonb_build_array(
    pg_catalog.jsonb_build_object('kind', 'sale', 'label_ar', 'بيع', 'operation_id', 'a'),
    pg_catalog.jsonb_build_object('kind', 'repair_fee', 'label_ar', 'أجرة مرمة', 'operation_id', 'b'),
    pg_catalog.jsonb_build_object('kind', 'repair_fee_collection', 'label_ar', 'تحصيل متبقي مرمة', 'operation_id', 'c'),
    pg_catalog.jsonb_build_object('kind', 'debt_settlement', 'label_ar', 'سداد دين', 'operation_id', 'd'),
    pg_catalog.jsonb_build_object('kind', 'expense', 'label_ar', 'مصروف', 'operation_id', 'e', 'future_key', 1)
  );
  v_out jsonb;
begin
  v_out := private.legacy_361ad2e_feed(v_rows);
  if pg_catalog.jsonb_array_length(v_out) <> 4
    or v_out -> 0 ->> 'operation_id' <> 'a'
    or v_out -> 1 ->> 'kind' <> 'repair_fee'
    or v_out -> 1 ->> 'label_ar' <> 'أجرة إصلاح'
    or v_out -> 2 ->> 'kind' <> 'repair_fee'
    or v_out -> 2 ->> 'label_ar' <> 'أجرة إصلاح'
    or v_out -> 2 ->> 'operation_id' <> 'c'
    or v_out -> 3 ->> 'operation_id' <> 'e'
    or v_out -> 3 ? 'future_key' then
    raise exception 'legacy_feed_normalizer %', v_out;
  end if;
  if private.legacy_361ad2e_feed('[]'::jsonb) <> '[]'::jsonb
    or private.legacy_361ad2e_feed(null) <> '[]'::jsonb then
    raise exception 'legacy_feed_empty';
  end if;
  if private.audit_trail_action_label('repair_fee_confirmed') <> 'أجرة مرمة'
    or private.audit_trail_action_label('repair_fee_collection_confirmed') <> 'تحصيل متبقي مرمة' then
    raise exception 'audit_repair_label';
  end if;
  if private.ledger_operation_label('repair_fee') <> 'أجرة مرمة' then
    raise exception 'ledger_repair_label';
  end if;
end;
$feed$;

do $grants$
begin
  if not has_function_privilege('authenticated', 'public.get_ledger_operation_page_v2(uuid, text, text, integer)', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.get_ledger_operation_page(uuid, text, text, integer)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_ledger_operation_page_v2(uuid, text, text, integer)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_ledger_operation_page(uuid, text, text, integer)', 'EXECUTE')
    or has_function_privilege('authenticated', 'public.get_ledger_operation_page_full(uuid, text, text, integer)', 'EXECUTE')
    or has_function_privilege('authenticated', 'private.legacy_361ad2e_feed(jsonb)', 'EXECUTE') then
    raise exception 'operation_page_grants';
  end if;
  -- Internal chains of the current reads never go through a legacy wrapper.
  if pg_catalog.pg_get_functiondef('public.get_daily_ledger_home_v1_before_staff()'::regprocedure)
      ~ 'public\.get_ledger_date_v1\('
    or pg_catalog.pg_get_functiondef('public.get_financial_week_report_v1_before_staff(date)'::regprocedure)
      ~ 'public\.get_financial_day_report_v1\('
    or pg_catalog.pg_get_functiondef('public.get_ledger_day_v1(uuid, text, integer)'::regprocedure)
      ~ 'public\.get_ledger_date_v1\('
    or pg_catalog.pg_get_functiondef('public.get_daily_ledger_home_v1_full()'::regprocedure)
      ~ 'public\.get_daily_ledger_home_v1\(' then
    raise exception 'internal_chain_uses_legacy_read';
  end if;
end;
$grants$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'cb100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'cb300000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"1000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"2"}],"scrap":[]}'::jsonb
);

-- Legacy home, date, and page reads expose only 361ad2e kinds and labels.
do $legacy_reads$
declare
  v_home jsonb;
  v_day uuid;
  v_page jsonb;
  v_page2 jsonb;
  v_date jsonb;
  v_bad jsonb;
begin
  v_home := public.get_daily_ledger_home_v1();
  v_day := (v_home #>> '{business_day,id}')::uuid;
  v_page := public.get_ledger_operation_page(v_day, null, null, 50);
  v_page2 := public.get_ledger_operation_page_v2(v_day, null, null, 50);
  v_date := public.get_ledger_date_v1(null, null, 100);
  select pg_catalog.jsonb_agg(item) into v_bad
  from pg_catalog.jsonb_array_elements(
    (v_home -> 'feed') || (v_page -> 'items') || (v_date #> '{feed_page,items}')
  ) as item
  where item ->> 'kind' not in (
      'opening_balances_confirmed', 'opening_balances', 'sale', 'purchase',
      'expense', 'purchase_settlement', 'cash_transfer', 'scrap_sale',
      'scrap_to_stock', 'sale_return', 'purchase_return', 'customer_return',
      'ledger_correction', 'exchange', 'close_day', 'open_day', 'daily_note',
      'repair_fee')
    or (item ->> 'kind' = 'repair_fee' and item ->> 'label_ar' <> 'أجرة إصلاح');
  if v_bad is not null then
    raise exception 'legacy_read_vocabulary %', v_bad;
  end if;
  if pg_catalog.jsonb_array_length(v_page2 -> 'items') <> pg_catalog.jsonb_array_length(v_page -> 'items')
    or v_page2 ->> 'shop_id' is distinct from v_page ->> 'shop_id' then
    raise exception 'operation_page_v2 %', v_page2;
  end if;
end;
$legacy_reads$;

-- WhatsApp group: current payload sets it, the 361ad2e payload keeps it.
do $group$
declare
  v_created jsonb;
  v_id uuid;
  v_status jsonb;
  v_list jsonb;
begin
  v_created := public.post_customer_create_v1(
    'cb300000-0000-4000-8000-000000000101',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_create', 'display_name', 'سارة',
      'phones', '[]'::jsonb, 'is_vip', false, 'has_open_request', false
    )
  );
  v_id := (v_created ->> 'customer_id')::uuid;
  if v_created ->> 'in_whatsapp_group' is distinct from 'false' then
    raise exception 'group_default %', v_created;
  end if;
  perform public.post_customer_create_v1(
    'cb300000-0000-4000-8000-000000000102',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_create', 'display_name', 'منى',
      'phones', '[]'::jsonb, 'is_vip', false, 'has_open_request', false
    )
  );

  v_status := public.post_customer_status_v1(
    'cb300000-0000-4000-8000-000000000103',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_status', 'customer_id', v_id,
      'expected_version', v_created ->> 'record_version',
      'is_vip', false, 'has_open_request', false, 'in_whatsapp_group', true
    )
  );
  if v_status ->> 'in_whatsapp_group' is distinct from 'true' then
    raise exception 'group_set %', v_status;
  end if;
  if not exists (
    select 1 from public.customer_events as event
    where event.customer_id = v_id and event.event_type = 'status_changed'
      and event.payload ->> 'in_whatsapp_group' = 'true'
  ) then
    raise exception 'group_event_missing';
  end if;

  -- 361ad2e payload: no in_whatsapp_group key. VIP changes, the flag stays.
  v_status := public.post_customer_status_v1(
    'cb300000-0000-4000-8000-000000000104',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_status', 'customer_id', v_id,
      'expected_version', v_status ->> 'record_version',
      'is_vip', true, 'has_open_request', false
    )
  );
  if v_status ->> 'is_vip' is distinct from 'true'
    or v_status ->> 'in_whatsapp_group' is distinct from 'true' then
    raise exception 'legacy_status_payload %', v_status;
  end if;

  v_list := public.get_customer_list_v3(null, null, 'whatsapp_group', 20, null);
  if pg_catalog.jsonb_array_length(v_list -> 'items') <> 1
    or v_list -> 'items' -> 0 ->> 'customer_id' <> v_id::text
    or v_list ->> 'filter' <> 'whatsapp_group' then
    raise exception 'group_filter %', v_list;
  end if;
  if public.get_customer_overview_v1() ->> 'whatsapp_group_count' <> '1' then
    raise exception 'group_overview';
  end if;

  v_status := public.post_customer_status_v1(
    'cb300000-0000-4000-8000-000000000105',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_status', 'customer_id', v_id,
      'expected_version', v_status ->> 'record_version',
      'is_vip', true, 'has_open_request', false, 'in_whatsapp_group', false
    )
  );
  if v_status ->> 'in_whatsapp_group' is distinct from 'false'
    or pg_catalog.jsonb_array_length(
      public.get_customer_list_v3(null, null, 'whatsapp_group', 20, null) -> 'items'
    ) <> 0 then
    raise exception 'group_clear %', v_status;
  end if;

  begin
    perform public.post_customer_status_v1(
      'cb300000-0000-4000-8000-000000000106',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_status', 'customer_id', v_id,
        'expected_version', v_status ->> 'record_version',
        'is_vip', true, 'has_open_request', false, 'in_whatsapp_group', 'yes'
      )
    );
    raise exception 'group_string_accepted';
  exception when others then
    if sqlerrm <> 'invalid_input' then raise; end if;
  end;
end;
$group$;

-- Employees stay out of customers. Earlier owner calls in this transaction set
-- app.required_shop_permission; one PostgREST request never inherits it.
select set_config('request.jwt.claim.sub', 'cb100000-0000-4000-8000-000000000002', true);
select set_config('app.required_shop_permission', '', true);
do $staff$
begin
  perform public.get_customer_list_v3(null, null, 'whatsapp_group', 20, null);
  raise exception 'staff_group_filter_allowed';
exception when others then
  if sqlerrm <> 'forbidden' then
    raise exception 'staff_group_filter_got_%', sqlerrm;
  end if;
end;
$staff$;

rollback;

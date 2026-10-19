-- Synthetic, rolled-back regression: removing any cached page must be detectable.
begin;
do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_trade_change[a-z0-9_]*$' then
    raise exception 'refusing non-disposable cache revision test';
  end if;
  if has_function_privilege('authenticated', 'public.get_daily_ledger_v2_before_trade_cache()', 'execute')
    or has_function_privilege('anon', 'public.get_daily_ledger_v2()', 'execute') then
    raise exception 'cache_reader_privileges';
  end if;
end;
$guard$;
insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('c1900000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cache-a@example.test',false,now(),now()),
  ('c1900000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','cache-b@example.test',false,now(),now());
insert into public.shops (id,name,owner_display_name,time_zone) values
  ('c2900000-0000-4000-8000-000000000001','متجر تجريبي','مالك تجريبي','Africa/Cairo'),
  ('c2900000-0000-4000-8000-000000000002','متجر مستقل','مالك مستقل','Africa/Cairo');
insert into public.shop_memberships (shop_id,user_id,role) values
  ('c2900000-0000-4000-8000-000000000001','c1900000-0000-4000-8000-000000000001','owner'),
  ('c2900000-0000-4000-8000-000000000002','c1900000-0000-4000-8000-000000000002','owner');
insert into public.shop_entitlements (shop_id,starts_at,expires_at) values
  ('c2900000-0000-4000-8000-000000000001',now()-interval '1 day',now()+interval '10 days'),
  ('c2900000-0000-4000-8000-000000000002',now()-interval '1 day',now()+interval '10 days');
set local role authenticated;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claim.session_id','',true);
do $main$
declare
  v_sale jsonb := '{"version":1,"kind":"sale","total_piastres":"10000","items":[{"category":"worked_jewelry","karat":21,"milligrams":"1255","count":"1","item_name":"خاتم","line_price_piastres":null}],"tenders":[{"method":"cash","piastres":"10000"}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb;
  v_review jsonb;
  v_post jsonb;
  v_read jsonb;
  v_id uuid;
  v_first bigint;
  v_second bigint;
  v_key uuid;
  v_iteration integer;
  v_date date;
  v_history jsonb;
  v_source uuid;
  v_replacement uuid;
  v_state jsonb;
  v_page jsonb;
  v_walk jsonb := '[]'::jsonb;
  v_cursor text;
  v_steps integer := 0;
begin
  perform public.confirm_opening_balances('c3900000-0000-4000-8000-000000000001',
    '{"version":1,"cash":{"cash":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"5"}],"scrap":[]}'::jsonb);
  v_read := public.get_daily_ledger_v2();
  if v_read->'trade_change_sequence' is distinct from '"0"'::jsonb then
    raise exception 'initial_cache_revision %',v_read;
  end if;
  for v_iteration in 1..2 loop
    v_key := case when v_iteration=1 then 'c3900000-0000-4000-8000-000000000002'::uuid else 'c3900000-0000-4000-8000-000000000004'::uuid end;
    v_id := (public.post_daily_ledger_trade(v_key,v_sale)->>'operation_id')::uuid;
    v_read := public.get_daily_ledger_v2();
    if v_iteration=1 and v_read->>'trade_change_sequence' <> '0' then
      raise exception 'ordinary_post_changed_revision';
    end if;
    v_review := public.review_ledger_trade_change_v1(v_id,'delete',null);
    v_key := case when v_iteration=1 then 'c3900000-0000-4000-8000-000000000003'::uuid else 'c3900000-0000-4000-8000-000000000005'::uuid end;
    v_post := public.post_ledger_trade_change_v1(v_key,v_id,'delete',null,
      (v_review->>'expected_day_id')::uuid,(v_review->>'expected_day_version')::bigint,
      v_review->>'source_sha256',v_review->>'review_token');
    v_read := public.get_daily_ledger_v2();
    v_second := (v_read->>'trade_change_sequence')::bigint;
    if v_second<=0 or (v_iteration=2 and v_second<=v_first)
      or v_read->'day_summary'->>'sale_piastres' <> '0'
      or exists(select 1 from jsonb_array_elements(v_read->'feed') as entry(value) where entry.value->>'operation_id' in (v_id::text,v_post->>'operation_id')) then
      raise exception 'cache_revision_or_active_feed %',v_read;
    end if;
    v_first := v_second;
    v_history := public.get_ledger_date_v1(null);
    v_date := (v_history->>'business_date')::date;
    if v_history->'day_summary'->>'sale_piastres' <> '0'
      or exists(select 1 from jsonb_array_elements(v_history->'feed_page'->'items') as entry(value)
        where entry.value->>'operation_id' in (v_id::text,v_post->>'operation_id')) then
      raise exception 'historical_deleted_row_visible %',v_history;
    end if;
  end loop;
  -- A replacement contributes once, and a deleted purchase contributes zero.
  v_source := (public.post_daily_ledger_trade('c3900000-0000-4000-8000-000000000007',v_sale)->>'operation_id')::uuid;
  v_review := public.review_ledger_trade_change_v1(v_source,'edit',v_sale || '{"note":"تعديل تجريبي"}'::jsonb);
  v_post := public.post_ledger_trade_change_v1('c3900000-0000-4000-8000-000000000008',v_source,'edit',v_sale || '{"note":"تعديل تجريبي"}'::jsonb,
    (v_review->>'expected_day_id')::uuid,(v_review->>'expected_day_version')::bigint,
    v_review->>'source_sha256',v_review->>'review_token');
  v_replacement := (v_post->>'replacement_operation_id')::uuid;
  v_history := public.get_ledger_date_v1(v_date);
  if v_history->'day_summary'->>'sale_count' <> '1'
    or v_history->'day_summary'->>'sale_piastres' <> '10000'
    or v_history->'day_summary'->'gold_by_bucket'->0->>'milligrams' <> '1255'
    or not exists(select 1 from jsonb_array_elements(v_history->'feed_page'->'items') as entry(value) where entry.value->>'operation_id'=v_replacement::text)
    or exists(select 1 from jsonb_array_elements(v_history->'feed_page'->'items') as entry(value) where entry.value->>'operation_id' in (v_source::text,v_post->>'operation_id')) then
    raise exception 'historical_edit_double_counted %',v_history;
  end if;
  v_source := (public.post_daily_ledger_trade('c3900000-0000-4000-8000-000000000009',v_sale || '{"kind":"purchase"}'::jsonb)->>'operation_id')::uuid;
  v_review := public.review_ledger_trade_change_v1(v_source,'delete',null);
  v_post := public.post_ledger_trade_change_v1('c3900000-0000-4000-8000-000000000010',v_source,'delete',null,
    (v_review->>'expected_day_id')::uuid,(v_review->>'expected_day_version')::bigint,
    v_review->>'source_sha256',v_review->>'review_token');
  v_history := public.get_ledger_date_v1(v_date);
  if v_history->'day_summary'->>'purchase_piastres' <> '0'
    or v_history->'day_summary'->>'sale_piastres' <> '10000' then
    raise exception 'historical_purchase_delete_summary %',v_history;
  end if;
  -- Reopening on the same date must retain the first session's active sale.
  v_state := public.get_daily_ledger_day_state();
  perform public.close_daily_ledger_day('c3900000-0000-4000-8000-000000000011',
    (v_state->>'business_day_id')::uuid,(v_state->>'day_version')::bigint,v_state->'counts');
  perform public.open_daily_ledger_day('c3900000-0000-4000-8000-000000000012');
  v_source := (public.post_daily_ledger_trade('c3900000-0000-4000-8000-000000000013',v_sale)->>'operation_id')::uuid;
  v_history := public.get_ledger_date_v1(v_date);
  if jsonb_array_length(v_history->'day_ids') <> 2
    or v_history->'day_summary'->>'sale_piastres' <> '20000'
    or v_history->'day_summary'->>'sale_count' <> '2' then
    raise exception 'reopened_date_summary %',v_history;
  end if;
  begin
    perform public.review_ledger_trade_change_v1(v_replacement,'delete',null);
    raise exception 'closed_day_change_allowed';
  exception when others then
    if sqlerrm <> 'trade_not_editable' then raise; end if;
  end;
  -- Hide a head row in the second session, leaving hidden rows between and
  -- behind visible rows from the earlier session.
  v_review := public.review_ledger_trade_change_v1(v_source,'delete',null);
  perform public.post_ledger_trade_change_v1('c3900000-0000-4000-8000-000000000014',v_source,'delete',null,
    (v_review->>'expected_day_id')::uuid,(v_review->>'expected_day_version')::bigint,
    v_review->>'source_sha256',v_review->>'review_token');
  v_history := public.get_ledger_date_v1(v_date);
  loop
    v_page := public.get_ledger_date_v1(v_date,v_cursor,1)->'feed_page';
    v_walk := v_walk || (v_page->'items');
    v_steps := v_steps+1;
    exit when not (v_page->>'has_more')::boolean;
    v_cursor := v_page->>'next_before_sequence';
    if v_steps>20 then raise exception 'historical_cursor_loop'; end if;
  end loop;
  if v_walk is distinct from v_history->'feed_page'->'items'
    or exists(select 1 from jsonb_array_elements(v_walk) as entry(value)
      join public.ledger_trade_changes as change on change.shop_id='c2900000-0000-4000-8000-000000000001'
        and entry.value->>'operation_id' in (change.source_operation_id::text,change.reversal_operation_id::text)) then
    raise exception 'historical_hidden_cursor_gap %',v_walk;
  end if;
  raise notice 'HISTORICAL_CHANGE_REOPENING_PAGINATION_PASSED %',v_steps;
  raise notice 'CACHE_REVISION_MONOTONIC_PASSED %',v_second;
end;
$main$;
select set_config('request.jwt.claim.sub','c1900000-0000-4000-8000-000000000002',true);
do $other_shop$
declare v_read jsonb;
begin
  perform public.confirm_opening_balances('c3900000-0000-4000-8000-000000000006',
    '{"version":1,"cash":{"cash":"0"},"stock":[],"scrap":[]}'::jsonb);
  v_read := public.get_daily_ledger_v2();
  if v_read->>'trade_change_sequence' <> '0' then raise exception 'cache_revision_cross_shop'; end if;
end;
$other_shop$;
reset role;
rollback;
\echo CACHE_REVISION_SQL_PASSED

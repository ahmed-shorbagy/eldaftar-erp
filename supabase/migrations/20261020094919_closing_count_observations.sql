begin;

-- Physical observations are preserved verbatim. Null stock weight means it was
-- not measured; book weights are recorded separately and never substituted.
create function private.closing_counts_match_v2(p_counts jsonb, p_book jsonb)
returns boolean language plpgsql immutable set search_path = '' as $fn$
declare
  v_row jsonb;
  v_book jsonb;
  v_count numeric;
  v_weight numeric;
  v_measured boolean;
  v_keys integer;
begin
  if jsonb_typeof(p_counts) is distinct from 'object'
    or (select count(*) from jsonb_object_keys(p_counts)) <> 4
    or p_counts -> 'version' is distinct from '2'::jsonb
    or not p_counts ?& array['version','cash','stock','scrap']
    or jsonb_typeof(p_counts -> 'cash') is distinct from 'object'
    or jsonb_typeof(p_counts -> 'stock') is distinct from 'array'
    or jsonb_typeof(p_counts -> 'scrap') is distinct from 'array' then
    raise exception 'invalid_input';
  end if;
  if jsonb_array_length(p_counts -> 'stock') > 200 then raise exception 'invalid_input'; end if;
  for v_row in select value from jsonb_array_elements(p_counts -> 'stock') loop
    if jsonb_typeof(v_row) is distinct from 'object'
      or (select count(*) from jsonb_object_keys(v_row)) <> 5
      or not v_row ?& array['item_name','category','karat','count','milligrams']
      or jsonb_typeof(v_row -> 'item_name') is distinct from 'string'
      or length(btrim(v_row ->> 'item_name')) not between 1 and 120
      or (v_row ->> 'item_name') ~ '[[:cntrl:]]'
      or (v_row ->> 'category') not in ('worked_jewelry','bullion','coin')
      or jsonb_typeof(v_row -> 'category') is distinct from 'string'
      or jsonb_typeof(v_row -> 'karat') is distinct from 'number'
      or (v_row ->> 'karat') not in ('14','18','21','22','24')
      or not exists (select 1 from jsonb_array_elements(p_book -> 'stock') as book(value)
        where book.value -> 'category' = v_row -> 'category' and book.value -> 'karat' = v_row -> 'karat')
      or jsonb_typeof(v_row -> 'count') is distinct from 'string'
      or (v_row ->> 'count') !~ '^(0|[1-9][0-9]{0,18})$'
      or (v_row ->> 'count')::numeric > 9223372036854775807
      or (v_row -> 'milligrams' <> 'null'::jsonb and (
        jsonb_typeof(v_row -> 'milligrams') is distinct from 'string'
        or (v_row ->> 'milligrams') !~ '^(0|[1-9][0-9]{0,18})$'
        or (v_row ->> 'milligrams')::numeric > 9223372036854775807
        or ((v_row ->> 'count') = '0') <> ((v_row ->> 'milligrams') = '0')
      )) then raise exception 'invalid_input'; end if;
  end loop;
  if exists (select 1 from jsonb_array_elements(p_counts -> 'stock') as item(value)
    group by item.value -> 'category', item.value -> 'karat', btrim(item.value ->> 'item_name')
    having count(*) > 1) then raise exception 'invalid_input'; end if;
  if p_counts -> 'cash' is distinct from p_book -> 'cash'
    or p_counts -> 'scrap' is distinct from p_book -> 'scrap' then return false; end if;
  for v_book in select value from jsonb_array_elements(p_book -> 'stock') loop
    select count(*), coalesce(sum((item.value ->> 'count')::numeric),0),
      coalesce(sum((item.value ->> 'milligrams')::numeric),0),
      coalesce(bool_and(item.value -> 'milligrams' <> 'null'::jsonb),false)
      into v_keys, v_count, v_weight, v_measured
    from jsonb_array_elements(p_counts -> 'stock') as item(value)
    where item.value -> 'category' = v_book -> 'category' and item.value -> 'karat' = v_book -> 'karat';
    if v_keys = 0 or v_count <> (v_book ->> 'count')::numeric
      or v_weight > (v_book ->> 'milligrams')::numeric
      or (v_measured and v_weight <> (v_book ->> 'milligrams')::numeric) then return false; end if;
  end loop;
  return true;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception 'invalid_input';
end;
$fn$;
revoke all on function private.closing_counts_match_v2(jsonb,jsonb) from public, anon, authenticated;

create function public.close_daily_ledger_day_v2(
  p_idempotency_key uuid, p_day_id uuid,
  p_expected_version bigint, p_counts jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_day public.business_days%rowtype;
  v_request public.financial_command_requests%rowtype;
  v_payload jsonb;
  v_hash bytea;
  v_actual jsonb;
  v_actor uuid;
  v_at timestamptz;
  v_sequence bigint;
  v_op uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_day_id is null
    or p_expected_version is null or p_counts is null
    or jsonb_typeof(p_counts) <> 'object' then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_payload := jsonb_build_object('version', 2, 'kind', 'close_day',
    'day_id', p_day_id, 'expected_version', p_expected_version,
    'counts', p_counts);
  v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = v_payload and v_request.payload_sha256 = v_hash then
      return jsonb_build_object('ok', true,
        'operation_id', v_request.operation_id, 'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select day.* into v_day from public.business_days as day
  where day.shop_id = v_shop and day.id = p_day_id for update;
  if v_day.id is null or v_day.status <> 'open' then
    raise exception 'day_closed';
  end if;
  if v_day.day_version <> p_expected_version then
    raise exception 'stale_day';
  end if;
  v_actual := private.daily_ledger_count_snapshot(v_shop);
  if not private.closing_counts_match_v2(p_counts, v_actual) then
    return jsonb_build_object('ok', false, 'reason', 'count_mismatch',
      'day_version', v_day.day_version, 'expected_counts', v_actual);
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, 'close_day', p_day_id, v_actor, v_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, v_shop, v_payload, v_at);
  update public.business_days set status = 'closed', closed_at = v_at,
    day_version = day_version + 1 where id = p_day_id;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, 'business_day_closed', v_op, v_at,
    jsonb_build_object('business_day_id', p_day_id, 'count_observations', p_counts, 'book_counts', v_actual));
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_op, 'business_day_closed', v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, v_payload, v_hash, v_op, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_op,
    'day_version', v_day.day_version + 1, 'replayed', false);
end;
$fn$;

revoke all on function public.close_daily_ledger_day_v2(uuid,uuid,bigint,jsonb) from public, anon;
grant execute on function public.close_daily_ledger_day_v2(uuid,uuid,bigint,jsonb) to authenticated;
notify pgrst, 'reload schema';
commit;

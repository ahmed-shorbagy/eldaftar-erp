-- Compensating ledger: audited count corrections, partial linked returns,
-- and one-envelope exchanges. Inventory and notes migrations are not edited.
-- Kind checks keep every value already allowed, including inventory and notes.
begin;

create function private.compensation_extend_in_check(
  p_table regclass, p_constraint name, p_column text, p_added text[]
) returns void language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_def text;
  v_values text[] := '{}';
  v_token text;
  v_list text;
begin
  select pg_catalog.pg_get_constraintdef(constraint_.oid) into v_def
  from pg_catalog.pg_constraint as constraint_
  where constraint_.conrelid = p_table and constraint_.conname = p_constraint;
  if v_def is null then raise exception 'invalid_input'; end if;
  for v_token in
    select (pg_catalog.regexp_matches(v_def, '''([^'']+)''', 'g'))[1]
  loop
    if v_token <> p_column and not v_token = any(v_values) then
      v_values := pg_catalog.array_append(v_values, v_token);
    end if;
  end loop;
  foreach v_token in array p_added loop
    if not v_token = any(v_values) then
      v_values := pg_catalog.array_append(v_values, v_token);
    end if;
  end loop;
  if coalesce(pg_catalog.array_length(v_values, 1), 0) < 8 then
    raise exception 'invalid_input';
  end if;
  select pg_catalog.string_agg(pg_catalog.quote_literal(value), ', ' order by value)
    into v_list
  from pg_catalog.unnest(v_values) as value;
  execute pg_catalog.format('alter table %s drop constraint %I', p_table::text, p_constraint);
  execute pg_catalog.format(
    'alter table %s add constraint %I check (%I in (%s))',
    p_table::text, p_constraint, p_column, v_list);
end;
$fn$;

select private.compensation_extend_in_check(
  'public.financial_operations'::regclass, 'financial_operations_kind_check', 'kind',
  array['ledger_correction', 'exchange']);
select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass, 'financial_audit_events_action_check', 'action',
  array['ledger_correction_confirmed', 'exchange_confirmed']);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass, 'financial_outbox_event_check', 'event_type',
  array['ledger_correction_confirmed', 'exchange_confirmed']);

create function private.canonical_signed(p_value numeric)
returns text language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  return private.checked_signed_bigint(p_value)::text;
end;
$fn$;

create function private.return_consideration(p_payload jsonb)
returns numeric language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if p_payload ? 'consideration_piastres' then
    return private.opening_parse_amount(p_payload ->> 'consideration_piastres');
  end if;
  return private.opening_parse_amount(p_payload ->> 'total_piastres');
end;
$fn$;

create function private.return_movement_lines(p_shop uuid, p_payload jsonb)
returns table (
  item_index integer, category text, karat smallint,
  milligrams bigint, piece_count bigint, item_name text
) language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_original jsonb;
  v_item jsonb;
  v_source jsonb;
  v_position integer := 0;
  v_index integer;
  v_category text;
begin
  select detail.payload into v_original
  from public.financial_operation_details as detail
  where detail.shop_id = p_shop
    and detail.operation_id = (p_payload ->> 'original_operation_id')::uuid;
  if v_original is null then raise exception 'not_found'; end if;
  for v_item in
    select value from pg_catalog.jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb))
  loop
    if v_item ? 'item_index' then
      v_index := private.opening_checked_bigint(
        private.opening_parse_amount(v_item ->> 'item_index'))::integer;
      v_source := v_original -> 'items' -> v_index;
      if v_source is null or pg_catalog.jsonb_typeof(v_source) <> 'object' then
        raise exception 'invalid_input';
      end if;
    else
      v_index := v_position;
      v_source := v_item;
    end if;
    v_category := v_source ->> 'category';
    item_index := v_index;
    category := v_category;
    karat := (v_source ->> 'karat')::smallint;
    item_name := coalesce(v_source ->> 'item_name', 'مرتجع');
    if v_item ? 'item_index' then
      milligrams := private.opening_checked_bigint(
        private.opening_parse_amount(v_item ->> 'milligrams'));
      if v_category = 'scrap' then
        piece_count := 0;
      else
        piece_count := private.opening_checked_bigint(
          private.opening_parse_amount(v_item ->> 'count'));
      end if;
    else
      milligrams := private.line_milligrams(v_source);
      piece_count := private.line_count(v_source, v_category);
    end if;
    return next;
    v_position := v_position + 1;
  end loop;
end;
$fn$;

create function private.json_add_method(p_map jsonb, p_method text, p_amount numeric)
returns jsonb language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_current numeric;
begin
  v_current := coalesce((p_map ->> p_method)::numeric, 0) + p_amount;
  return pg_catalog.jsonb_set(p_map, array[p_method], pg_catalog.to_jsonb(v_current::text));
end;
$fn$;

create function private.return_bounds(p_shop uuid, p_operation uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_original public.financial_operations%rowtype;
  v_payload jsonb;
  v_acc jsonb := '{}'::jsonb;
  v_prior record;
  v_line record;
  v_key text;
  v_mg numeric;
  v_count numeric;
  v_returned_consideration numeric := 0;
  v_items jsonb := '[]'::jsonb;
  v_index integer := 0;
  v_source jsonb;
  v_category text;
  v_orig_mg bigint;
  v_orig_count bigint;
  v_ret_mg bigint;
  v_ret_count bigint;
  v_paid jsonb := '{"cash":"0","instant_transfer":"0","wallet":"0","card":"0"}'::jsonb;
  v_refunded jsonb := '{"cash":"0","instant_transfer":"0","wallet":"0","card":"0"}'::jsonb;
  v_refundable jsonb := '{}'::jsonb;
  v_tender jsonb;
  v_method text;
  v_has_pricing boolean;
  v_component text;
  v_components text[] := array[
    'base_piastres', 'workmanship_piastres', 'other_charges_piastres', 'discount_piastres'];
  v_orig_component numeric;
  v_ret_component numeric;
  v_pricing jsonb := '{}'::jsonb;
  v_total numeric;
  v_payable bigint := 0;
  v_fully boolean := true;
begin
  select operation.* into v_original
  from public.financial_operations as operation
  where operation.shop_id = p_shop and operation.id = p_operation;
  if v_original.id is null or v_original.kind not in ('sale', 'purchase') then
    raise exception 'not_found';
  end if;
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = p_shop and detail.operation_id = p_operation;
  if v_payload is null then raise exception 'not_found'; end if;
  for v_prior in
    select detail.payload
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = p_shop
      and operation.kind = v_original.kind || '_return'
      and detail.payload ->> 'original_operation_id' = p_operation::text
  loop
    v_returned_consideration := v_returned_consideration
      + private.return_consideration(v_prior.payload);
    for v_line in
      select * from private.return_movement_lines(p_shop, v_prior.payload)
    loop
      v_key := v_line.item_index::text;
      v_mg := coalesce((v_acc -> v_key ->> 'mg')::numeric, 0) + v_line.milligrams;
      v_count := coalesce((v_acc -> v_key ->> 'count')::numeric, 0) + v_line.piece_count;
      v_acc := pg_catalog.jsonb_set(v_acc, array[v_key], pg_catalog.jsonb_build_object(
        'mg', v_mg::text, 'count', v_count::text));
    end loop;
    for v_tender in
      select jsonb_build_object('method', account.method_code,
        'piastres', abs(sum(posting.amount))::text)
      from public.financial_operations operation
      join public.financial_operation_details detail on detail.operation_id = operation.id
      join public.journal_postings posting on posting.operation_id = operation.id
      join public.ledger_accounts account on account.id = posting.account_id
      where operation.shop_id = p_shop and operation.kind = v_original.kind || '_return'
        and detail.payload = v_prior.payload and account.account_kind = 'cash_method'
      group by account.method_code
    loop
      v_refunded := private.json_add_method(v_refunded, v_tender ->> 'method',
        private.opening_parse_amount(v_tender ->> 'piastres'));
    end loop;
  end loop;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(coalesce(v_payload -> 'tenders', '[]'::jsonb))
  loop
    v_paid := private.json_add_method(
      v_paid, v_tender ->> 'method',
      private.opening_parse_amount(v_tender ->> 'piastres'));
  end loop;
  if v_original.kind = 'purchase' then
    for v_prior in
      select detail.payload
      from public.financial_operations as operation
      join public.financial_operation_details as detail
        on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
      where operation.shop_id = p_shop and operation.kind = 'purchase_settlement'
        and detail.payload ->> 'purchase_operation_id' = p_operation::text
    loop
      for v_tender in
        select value from pg_catalog.jsonb_array_elements(coalesce(v_prior.payload -> 'tenders', '[]'::jsonb))
      loop
        v_paid := private.json_add_method(
          v_paid, v_tender ->> 'method',
          private.opening_parse_amount(v_tender ->> 'piastres'));
      end loop;
    end loop;
    select payable.remaining_piastres into v_payable
    from public.purchase_cash_payables as payable
    where payable.shop_id = p_shop and payable.operation_id = p_operation;
    v_payable := coalesce(v_payable, 0);
  end if;
  foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
    v_refundable := pg_catalog.jsonb_set(v_refundable, array[v_method], pg_catalog.to_jsonb(
      private.canonical_signed(
        (v_paid ->> v_method)::numeric - (v_refunded ->> v_method)::numeric)));
  end loop;
  for v_source in
    select value from pg_catalog.jsonb_array_elements(coalesce(v_payload -> 'items', '[]'::jsonb))
  loop
    v_category := v_source ->> 'category';
    v_orig_mg := private.line_milligrams(v_source);
    v_ret_mg := coalesce((v_acc -> v_index::text ->> 'mg')::bigint, 0);
    if v_category = 'scrap' then
      v_orig_count := 0;
      v_ret_count := 0;
      v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'item_index', v_index::text,
        'category', v_category,
        'karat', (v_source ->> 'karat')::integer,
        'item_name', coalesce(v_source ->> 'item_name', ''),
        'original_milligrams', v_orig_mg::text,
        'original_count', null,
        'returned_milligrams', v_ret_mg::text,
        'returned_count', null,
        'remainder_milligrams', (v_orig_mg - v_ret_mg)::text,
        'remainder_count', null));
      if v_orig_mg - v_ret_mg <> 0 then v_fully := false; end if;
    else
      v_orig_count := private.line_count(v_source, v_category);
      v_ret_count := coalesce((v_acc -> v_index::text ->> 'count')::bigint, 0);
      v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'item_index', v_index::text,
        'category', v_category,
        'karat', (v_source ->> 'karat')::integer,
        'item_name', coalesce(v_source ->> 'item_name', ''),
        'original_milligrams', v_orig_mg::text,
        'original_count', v_orig_count::text,
        'returned_milligrams', v_ret_mg::text,
        'returned_count', v_ret_count::text,
        'remainder_milligrams', (v_orig_mg - v_ret_mg)::text,
        'remainder_count', (v_orig_count - v_ret_count)::text));
      if v_orig_mg - v_ret_mg <> 0 or v_orig_count - v_ret_count <> 0 then
        v_fully := false;
      end if;
    end if;
    v_index := v_index + 1;
  end loop;
  v_total := private.opening_parse_amount(v_payload ->> 'total_piastres');
  if v_total - v_returned_consideration <> 0 then v_fully := false; end if;
  v_has_pricing := v_payload ? 'pricing';
  if v_has_pricing then
    foreach v_component in array v_components loop
      v_orig_component := private.opening_parse_amount(v_payload -> 'pricing' ->> v_component);
      select coalesce(sum(
        case when prior.payload ? 'pricing'
          then private.opening_parse_amount(prior.payload -> 'pricing' ->> v_component)
          else 0 end), 0) into v_ret_component
      from (
        select detail.payload
        from public.financial_operations as operation
        join public.financial_operation_details as detail
          on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
        where operation.shop_id = p_shop
          and operation.kind = v_original.kind || '_return'
          and detail.payload ->> 'original_operation_id' = p_operation::text
      ) as prior;
      v_pricing := pg_catalog.jsonb_set(v_pricing, array[v_component], pg_catalog.jsonb_build_object(
        'original', private.canonical_signed(v_orig_component),
        'returned', private.canonical_signed(v_ret_component),
        'remainder', private.canonical_signed(v_orig_component - v_ret_component)));
    end loop;
    v_pricing := pg_catalog.jsonb_set(
      v_pricing, '{other_charges_label}',
      pg_catalog.to_jsonb(coalesce(v_payload -> 'pricing' ->> 'other_charges_label', '')));
  end if;
  return pg_catalog.jsonb_build_object(
    'operation_id', p_operation,
    'kind', v_original.kind,
    'original_immutable', true,
    'fully_returned', v_fully,
    'items', v_items,
    'original_total_piastres', private.canonical_signed(v_total),
    'returned_consideration_piastres', private.canonical_signed(v_returned_consideration),
    'remainder_consideration_piastres', private.canonical_signed(v_total - v_returned_consideration),
    'has_pricing', v_has_pricing,
    'pricing', v_pricing,
    'payable_remaining_piastres', v_payable::text,
    'paid_by_method', v_paid,
    'refunded_by_method', v_refunded,
    'refundable_by_method', v_refundable);
end;
$fn$;


create function private.compensation_child_key(p_parent uuid, p_salt text)
returns uuid language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_md5 text := pg_catalog.md5(p_parent::text || p_salt);
begin
  return (
    substr(v_md5, 1, 8) || '-' || substr(v_md5, 9, 4) || '-' ||
    '4' || substr(v_md5, 14, 3) || '-' ||
    '8' || substr(v_md5, 18, 3) || '-' || substr(v_md5, 21, 12)
  )::uuid;
end;
$fn$;

create function private.json_keys_allowed(
  p_value jsonb, p_required text[], p_optional text[]
) returns void language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_key text;
begin
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  foreach v_key in array p_required loop
    if not (p_value ? v_key) then raise exception 'invalid_input'; end if;
  end loop;
  for v_key in select pg_catalog.jsonb_object_keys(p_value) loop
    if not v_key = any(p_required) and not v_key = any(p_optional) then
      raise exception 'invalid_input';
    end if;
  end loop;
end;
$fn$;

create function private.method_balance(p_shop uuid, p_method text, p_exclude uuid)
returns bigint language sql stable security definer set search_path = '' as $fn$
  select coalesce(sum(posting.amount), 0)::bigint
  from public.ledger_accounts as account
  join public.journal_postings as posting
    on posting.shop_id = account.shop_id and posting.account_id = account.id
  where account.shop_id = p_shop and account.account_kind = 'cash_method'
    and account.method_code = p_method
    and posting.operation_id is distinct from p_exclude;
$fn$;

create function private.metal_balance(
  p_shop uuid, p_category text, p_karat smallint, p_exclude uuid
) returns table (milligrams bigint, piece_count bigint)
language sql stable security definer set search_path = '' as $fn$
  select
    coalesce(sum(posting.amount) filter (
      where account.account_kind in ('saleable_metal', 'scrap_metal')), 0)::bigint,
    coalesce(sum(posting.amount) filter (
      where account.account_kind = 'saleable_count'), 0)::bigint
  from public.ledger_accounts as account
  left join public.journal_postings as posting
    on posting.shop_id = account.shop_id and posting.account_id = account.id
   and posting.operation_id is distinct from p_exclude
  where account.shop_id = p_shop
    and account.category_code = p_category and account.karat = p_karat
    and account.account_kind in ('saleable_metal', 'scrap_metal', 'saleable_count');
$fn$;

create function private.signed_journal_effects(p_shop uuid, p_operation uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_cash numeric := 0; v_buckets jsonb := '[]'::jsonb;
begin
  select coalesce(sum(posting.amount), 0) into v_cash
  from public.journal_postings as posting
  join public.ledger_accounts as account
    on account.shop_id = posting.shop_id and account.id = posting.account_id
  where posting.shop_id = p_shop and posting.operation_id = p_operation
    and account.account_kind = 'cash_method';
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'category', bucket.category_code,
    'karat', bucket.karat,
    'milligrams', private.canonical_signed(bucket.milligrams),
    'count', case when bucket.category_code = 'scrap' then null
      else private.canonical_signed(bucket.pieces) end
  ) order by bucket.category_code, bucket.karat), '[]'::jsonb)
  into v_buckets
  from (
    select account.category_code, account.karat,
      coalesce(sum(posting.amount) filter (
        where account.account_kind in ('saleable_metal', 'scrap_metal')), 0) as milligrams,
      coalesce(sum(posting.amount) filter (
        where account.account_kind = 'saleable_count'), 0) as pieces
    from public.journal_postings as posting
    join public.ledger_accounts as account
      on account.shop_id = posting.shop_id and account.id = posting.account_id
    where posting.shop_id = p_shop and posting.operation_id = p_operation
      and account.account_kind in ('saleable_metal', 'scrap_metal', 'saleable_count')
    group by account.category_code, account.karat
  ) as bucket;
  return pg_catalog.jsonb_build_object(
    'cash_piastres', private.canonical_signed(v_cash),
    'buckets', v_buckets);
end;
$fn$;

create function private.correction_counted_deltas(
  p_shop uuid, p_payload jsonb, p_exclude uuid
) returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_counted jsonb := p_payload -> 'counted';
  v_cash jsonb := v_counted -> 'cash';
  v_method text;
  v_seen text[] := '{}';
  v_line jsonb;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_book_mg bigint;
  v_book_count bigint;
  v_delta_cash jsonb := '{}'::jsonb;
  v_delta_stock jsonb := '[]'::jsonb;
  v_delta_scrap jsonb := '[]'::jsonb;
  v_nonzero boolean := false;
  v_expected integer;
  v_matched integer := 0;
begin
  perform private.json_keys_allowed(v_counted, array['cash', 'stock', 'scrap'], array[]::text[]);
  perform private.json_keys_allowed(
    v_cash, array['cash', 'instant_transfer', 'wallet', 'card'], array[]::text[]);
  if pg_catalog.jsonb_typeof(v_counted -> 'stock') is distinct from 'array'
    or pg_catalog.jsonb_typeof(v_counted -> 'scrap') is distinct from 'array' then
    raise exception 'invalid_input';
  end if;
  foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
    if pg_catalog.jsonb_typeof(v_cash -> v_method) is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_mg := private.opening_checked_bigint(
      private.opening_parse_amount(v_cash ->> v_method));
    v_book_mg := private.method_balance(p_shop, v_method, p_exclude);
    v_delta_cash := pg_catalog.jsonb_set(v_delta_cash, array[v_method],
      pg_catalog.to_jsonb(private.canonical_signed(v_mg - v_book_mg)));
    if v_mg - v_book_mg <> 0 then v_nonzero := true; end if;
  end loop;
  select count(*) into v_expected from public.ledger_accounts as account
  where account.shop_id = p_shop and account.account_kind = 'saleable_metal';
  if pg_catalog.jsonb_array_length(v_counted -> 'stock') is distinct from v_expected then
    raise exception 'invalid_input';
  end if;
  for v_line in select value from pg_catalog.jsonb_array_elements(v_counted -> 'stock') loop
    perform private.json_keys_allowed(
      v_line, array['category', 'karat', 'milligrams', 'count'], array[]::text[]);
    v_category := v_line ->> 'category';
    if pg_catalog.jsonb_typeof(v_line -> 'karat') is distinct from 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$'
      or pg_catalog.jsonb_typeof(v_line -> 'milligrams') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'count') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_karat := (v_line ->> 'karat')::smallint;
    if not private.opening_pair_allowed(v_category, v_karat) or v_category = 'scrap' then
      raise exception 'invalid_input';
    end if;
    if (v_category || ':' || v_karat::text) = any(v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_category || ':' || v_karat::text);
    if not exists (
      select 1 from public.ledger_accounts as account
      where account.shop_id = p_shop and account.account_kind = 'saleable_metal'
        and account.category_code = v_category and account.karat = v_karat
    ) then raise exception 'invalid_input'; end if;
    v_mg := private.opening_checked_bigint(private.opening_parse_amount(v_line ->> 'milligrams'));
    v_count := private.opening_checked_bigint(private.opening_parse_amount(v_line ->> 'count'));
    if (v_mg = 0) <> (v_count = 0) then raise exception 'stock_pair_mismatch'; end if;
    select balance.milligrams, balance.piece_count into v_book_mg, v_book_count
    from private.metal_balance(p_shop, v_category, v_karat, p_exclude) as balance;
    v_delta_stock := v_delta_stock || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'category', v_category, 'karat', v_karat,
      'milligrams', private.canonical_signed(v_mg - v_book_mg),
      'count', private.canonical_signed(v_count - v_book_count)));
    if v_mg - v_book_mg <> 0 or v_count - v_book_count <> 0 then v_nonzero := true; end if;
    v_matched := v_matched + 1;
  end loop;
  if v_matched <> v_expected then raise exception 'invalid_input'; end if;
  select count(*) into v_expected from public.ledger_accounts as account
  where account.shop_id = p_shop and account.account_kind = 'scrap_metal';
  if pg_catalog.jsonb_array_length(v_counted -> 'scrap') is distinct from v_expected then
    raise exception 'invalid_input';
  end if;
  v_seen := '{}';
  v_matched := 0;
  for v_line in select value from pg_catalog.jsonb_array_elements(v_counted -> 'scrap') loop
    perform private.json_keys_allowed(v_line, array['karat', 'milligrams'], array[]::text[]);
    if pg_catalog.jsonb_typeof(v_line -> 'karat') is distinct from 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$'
      or pg_catalog.jsonb_typeof(v_line -> 'milligrams') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_karat := (v_line ->> 'karat')::smallint;
    if not private.opening_pair_allowed('scrap', v_karat) then raise exception 'invalid_input'; end if;
    if v_karat::text = any(v_seen) then raise exception 'invalid_input'; end if;
    v_seen := pg_catalog.array_append(v_seen, v_karat::text);
    if not exists (
      select 1 from public.ledger_accounts as account
      where account.shop_id = p_shop and account.account_kind = 'scrap_metal'
        and account.karat = v_karat
    ) then raise exception 'invalid_input'; end if;
    v_mg := private.opening_checked_bigint(private.opening_parse_amount(v_line ->> 'milligrams'));
    select balance.milligrams into v_book_mg
    from private.metal_balance(p_shop, 'scrap', v_karat, p_exclude) as balance;
    v_delta_scrap := v_delta_scrap || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'karat', v_karat, 'milligrams', private.canonical_signed(v_mg - v_book_mg)));
    if v_mg - v_book_mg <> 0 then v_nonzero := true; end if;
    v_matched := v_matched + 1;
  end loop;
  if v_matched <> v_expected then raise exception 'invalid_input'; end if;
  if not v_nonzero then raise exception 'invalid_input'; end if;
  return pg_catalog.jsonb_build_object(
    'cash', v_delta_cash, 'stock', v_delta_stock, 'scrap', v_delta_scrap);
end;
$fn$;

create function private.apply_correction_lots(
  p_shop uuid, p_operation uuid, p_payload jsonb
) returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_deltas jsonb;
  v_line jsonb;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_available record;
  v_need_mg bigint;
  v_need_count bigint;
  v_add_mg bigint;
  v_add_count bigint;
begin
  v_deltas := private.correction_counted_deltas(p_shop, p_payload, p_operation);
  for v_line in select value from pg_catalog.jsonb_array_elements(v_deltas -> 'stock') loop
    v_category := v_line ->> 'category';
    v_karat := (v_line ->> 'karat')::smallint;
    v_mg := private.checked_signed_bigint(private.parse_signed_amount(v_line ->> 'milligrams'));
    v_count := private.checked_signed_bigint(private.parse_signed_amount(v_line ->> 'count'));
    if v_mg = 0 and v_count = 0 then continue; end if;
    if v_mg > 0 and v_count > 0 then
      perform private.create_stock_lot(p_shop, p_operation, 'تسوية جرد',
        v_category, v_karat, v_mg, v_count, 'owned_available',
        null, false, null, null, 'correction', 'manual');
    elsif v_mg < 0 and v_count < 0 then
      perform private.consume_fifo(p_shop,p_operation,v_category,v_karat,-v_mg,-v_count,'correction');
    else
      v_need_mg := v_mg; v_need_count := v_count;
      for v_available in
        select lot.id, remaining.milligrams, remaining.piece_count
        from public.inventory_lots lot
        cross join lateral private.lot_remaining(lot.id) remaining
        where lot.shop_id = p_shop and lot.category_code = v_category
          and lot.karat = v_karat and lot.stock_class = 'owned_available'
          and remaining.milligrams > 0 and remaining.piece_count > 0
        order by lot.created_at, lot.id
      loop
        exit when v_need_mg = 0 and v_need_count = 0;
        v_add_mg := case when v_need_mg < 0 then greatest(v_need_mg,1-v_available.milligrams) else v_need_mg end;
        v_add_count := case when v_need_count < 0 then greatest(v_need_count,1-v_available.piece_count) else v_need_count end;
        if v_add_mg <> 0 or v_add_count <> 0 then
          perform private.add_lot_movement(p_shop,v_available.id,p_operation,v_add_mg,v_add_count,'correction','manual');
          v_need_mg := v_need_mg - v_add_mg; v_need_count := v_need_count - v_add_count;
        end if;
      end loop;
      -- Never merge products or silently transfer quantities between known lots.
      if v_need_mg <> 0 or v_need_count <> 0 then raise exception 'stock_pair_mismatch'; end if;
    end if;
  end loop;
  for v_line in select value from pg_catalog.jsonb_array_elements(v_deltas -> 'scrap') loop
    v_karat := (v_line ->> 'karat')::smallint;
    v_mg := private.checked_signed_bigint(private.parse_signed_amount(v_line ->> 'milligrams'));
    if v_mg > 0 then
      perform private.create_stock_lot(
        p_shop, p_operation, 'تسوية جرد', 'scrap', v_karat, v_mg, null,
        'owned_available', null, false, null, null, 'correction', 'manual');
    elsif v_mg < 0 then
      perform private.consume_fifo(
        p_shop, p_operation, 'scrap', v_karat, -v_mg, 0, 'correction');
    end if;
  end loop;
end;
$fn$;

create function private.consume_purchase_return(
  p_shop uuid, p_operation uuid, p_category text, p_karat smallint,
  p_mg bigint, p_count bigint, p_kind text, p_original uuid, p_name text
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
begin
  if p_mg < 0 or p_count < 0 or (p_mg = 0 and p_count = 0) then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.inventory_lots as lot
  where lot.shop_id = p_shop and lot.category_code = p_category and lot.karat = p_karat
    and lot.stock_class = 'owned_available' and lot.origin_operation_id = p_original and lot.display_name = btrim(p_name)
  order by lot.id for update;
  for v_lot in
    select lot.id, lot.tracks_count
    from public.inventory_lots as lot
    where lot.shop_id = p_shop and lot.category_code = p_category
      and lot.karat = p_karat and lot.stock_class = 'owned_available' and lot.origin_operation_id = p_original and lot.display_name = btrim(p_name)
    order by lot.created_at, lot.id
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

revoke all on function private.consume_purchase_return(uuid,uuid,text,smallint,bigint,bigint,text,uuid,text) from public, anon, authenticated;

alter function private.apply_operation_lots(uuid, uuid)
  rename to apply_operation_lots_before_compensation;

create function private.apply_operation_lots(p_shop uuid, p_operation uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_payload jsonb;
  v_line record;
begin
  if exists (
    select 1 from public.inventory_lot_movements as movement
    where movement.operation_id = p_operation
  ) then
    return;
  end if;
  select operation.kind into v_kind
  from public.financial_operations as operation
  where operation.shop_id = p_shop and operation.id = p_operation;
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = p_shop and detail.operation_id = p_operation;
  if v_kind = 'ledger_correction' then
    perform private.apply_correction_lots(p_shop, p_operation, v_payload);
    return;
  elsif v_kind = 'exchange' then
    return;
  elsif v_kind in ('sale_return', 'purchase_return') then
    for v_line in select * from private.return_movement_lines(p_shop, v_payload) loop
      if v_line.milligrams = 0 and v_line.piece_count = 0 then continue; end if;
      if v_kind = 'sale_return' then
        perform private.create_stock_lot(
          p_shop, p_operation, coalesce(nullif(btrim(v_line.item_name), ''), 'مرتجع'),
          v_line.category, v_line.karat, v_line.milligrams,
          case when v_line.category = 'scrap' then null else v_line.piece_count end,
          'owned_available', null, false, null, null, 'return', 'return_mirror');
      else
        perform private.consume_purchase_return(
          p_shop, p_operation, v_line.category, v_line.karat,
          v_line.milligrams, v_line.piece_count, 'return', (v_payload ->> 'original_operation_id')::uuid, v_line.item_name);
      end if;
    end loop;
    return;
  end if;
  perform private.apply_operation_lots_before_compensation(p_shop, p_operation);
end;
$fn$;

create function private.post_linked_return_core(
  p_shop uuid, p_key uuid, p_payload jsonb, p_day uuid,
  p_actor uuid, p_at timestamptz, p_bump boolean, p_allow_zero boolean
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_original uuid;
  v_original_payload jsonb;
  v_bounds jsonb;
  v_item jsonb;
  v_source record;
  v_seen integer[] := '{}';
  v_index integer;
  v_mg bigint;
  v_count bigint;
  v_rem_mg bigint;
  v_rem_count bigint;
  v_consideration bigint;
  v_remainder bigint;
  v_tender_sum numeric;
  v_tender jsonb;
  v_method text;
  v_amount bigint;
  v_refundable bigint;
  v_payable bigint;
  v_cancel bigint;
  v_cash bigint;
  v_operation uuid;
  v_component text;
  v_components text[] := array[
    'base_piastres', 'workmanship_piastres', 'other_charges_piastres', 'discount_piastres'];
  v_price_sum numeric;
  v_book_mg bigint;
  v_book_count bigint;
  v_version bigint;
  v_hash bytea;
  v_qty_left boolean := false;
  v_line_count integer := 0;
  v_detail jsonb;
  v_detail_items jsonb;
begin
  perform private.json_keys_allowed(p_payload, array[
    'version', 'kind', 'original_operation_id', 'note', 'items',
    'consideration_piastres', 'tenders'
  ], array['pricing', 'expected_day_id', 'expected_day_version']);
  if p_payload -> 'version' is distinct from '1'::jsonb then raise exception 'invalid_input'; end if;
  v_kind := p_payload ->> 'kind';
  if v_kind not in ('sale_return', 'purchase_return')
    or pg_catalog.jsonb_typeof(p_payload -> 'original_operation_id') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'note') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'consideration_piastres') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or pg_catalog.jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or char_length(p_payload ->> 'note') > 1000 then
    raise exception 'invalid_input';
  end if;
  begin
    v_original := (p_payload ->> 'original_operation_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_input';
  end;
  perform 1 from public.financial_operations as operation
  where operation.shop_id = p_shop and operation.id = v_original
    and operation.kind = case when v_kind = 'sale_return' then 'sale' else 'purchase' end
  for update;
  if not found then raise exception 'not_found'; end if;
  select detail.payload into v_original_payload
  from public.financial_operation_details as detail
  where detail.shop_id = p_shop and detail.operation_id = v_original;
  v_bounds := private.return_bounds(p_shop, v_original);
  if (v_bounds ->> 'fully_returned')::boolean then raise exception 'already_returned'; end if;
  v_consideration := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'consideration_piastres'));
  v_remainder := private.checked_signed_bigint(
    private.parse_signed_amount(v_bounds ->> 'remainder_consideration_piastres'));
  if v_consideration < 0 or v_consideration > v_remainder then
    raise exception 'return_exceeds_original';
  end if;

  for v_item in select value from pg_catalog.jsonb_array_elements(v_bounds -> 'items') loop
    if coalesce((v_item ->> 'remainder_milligrams')::bigint, 0) <> 0
      or coalesce((v_item ->> 'remainder_count')::bigint, 0) <> 0 then
      v_qty_left := true;
    end if;
  end loop;
  v_line_count := pg_catalog.jsonb_array_length(p_payload -> 'items');
  if v_line_count = 0 and (v_qty_left or v_consideration = 0) then
    raise exception 'invalid_input';
  end if;
  if v_line_count > 50 then raise exception 'invalid_input'; end if;
  for v_item in select value from pg_catalog.jsonb_array_elements(p_payload -> 'items') loop
    if v_kind = 'sale_return' then
      perform private.json_keys_allowed(
        v_item, array['item_index', 'milligrams'], array['count']);
    else
      perform private.json_keys_allowed(
        v_item, array['item_index', 'milligrams'], array['count']);
    end if;
    if pg_catalog.jsonb_typeof(v_item -> 'item_index') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_item -> 'milligrams') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_index := private.opening_checked_bigint(
      private.opening_parse_amount(v_item ->> 'item_index'))::integer;
    if v_index = any(v_seen) then raise exception 'invalid_input'; end if;
    v_seen := pg_catalog.array_append(v_seen, v_index);
    select * into v_source from private.return_movement_lines(p_shop, p_payload) as line
    where line.item_index = v_index limit 1;
    if v_source.item_index is null then raise exception 'invalid_input'; end if;
    select (item.value ->> 'remainder_milligrams')::bigint,
      case when item.value ->> 'remainder_count' is null then 0
        else (item.value ->> 'remainder_count')::bigint end
      into v_rem_mg, v_rem_count
    from pg_catalog.jsonb_array_elements(v_bounds -> 'items') as item(value)
    where (item.value ->> 'item_index') = v_index::text;
    v_mg := v_source.milligrams;
    v_count := v_source.piece_count;
    if v_mg <= 0 or v_mg > v_rem_mg or v_count < 0 or v_count > v_rem_count then
      raise exception 'return_exceeds_original';
    end if;
    if v_source.category = 'scrap' then
      if v_item ? 'count' and v_item -> 'count' <> 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    else
      if v_count <= 0 or (v_mg = 0) <> (v_count = 0) then
        raise exception 'stock_pair_mismatch';
      end if;
      if (v_rem_mg - v_mg = 0) <> (v_rem_count - v_count = 0) then
        raise exception 'stock_pair_mismatch';
      end if;
      select balance.milligrams, balance.piece_count into v_book_mg, v_book_count
      from private.metal_balance(p_shop, v_source.category, v_source.karat, null) as balance;
      if v_kind = 'purchase_return' then
        if v_book_mg < v_mg or v_book_count < v_count then
          raise exception 'negative_owned_balance';
        end if;
        if (v_book_mg - v_mg = 0) <> (v_book_count - v_count = 0) then
          raise exception 'stock_pair_mismatch';
        end if;
      end if;
    end if;
    if v_kind = 'purchase_return' and v_source.category = 'scrap' then
      select balance.milligrams into v_book_mg
      from private.metal_balance(p_shop, 'scrap', v_source.karat, null) as balance;
      if v_book_mg < v_mg then raise exception 'negative_owned_balance'; end if;
    end if;
  end loop;
  if (v_bounds ->> 'has_pricing')::boolean then
    if pg_catalog.jsonb_typeof(p_payload -> 'pricing') is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
    perform private.json_keys_allowed(p_payload -> 'pricing', v_components,
      array['other_charges_label']);
    v_price_sum := 0;
    foreach v_component in array v_components loop
      if pg_catalog.jsonb_typeof(p_payload -> 'pricing' -> v_component) is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(p_payload -> 'pricing' ->> v_component));
      v_rem_mg := private.checked_signed_bigint(private.parse_signed_amount(
        v_bounds -> 'pricing' -> v_component ->> 'remainder'));
      if v_rem_mg < 0 or v_amount > v_rem_mg then raise exception 'return_exceeds_original'; end if;
      if v_component = 'discount_piastres' then v_price_sum := v_price_sum - v_amount;
      else v_price_sum := v_price_sum + v_amount; end if;
    end loop;
    if pg_catalog.jsonb_typeof(p_payload -> 'pricing' -> 'other_charges_label') is distinct from 'string'
      or char_length(p_payload -> 'pricing' ->> 'other_charges_label') > 120 then
      raise exception 'invalid_input';
    end if;
    if private.opening_parse_amount(p_payload -> 'pricing' ->> 'other_charges_piastres') > 0
      and nullif(btrim(p_payload -> 'pricing' ->> 'other_charges_label'), '') is null then
      raise exception 'invalid_input';
    end if;
    if v_price_sum <> v_consideration then raise exception 'pricing_mismatch'; end if;
  elsif p_payload ? 'pricing' then
    raise exception 'invalid_input';
  end if;
  v_payable := (v_bounds ->> 'payable_remaining_piastres')::bigint;
  if v_kind = 'purchase_return' then
    v_cancel := least(v_consideration, v_payable);
    v_cash := v_consideration - v_cancel;
  else
    v_cancel := 0;
    v_cash := v_consideration;
  end if;
  v_tender_sum := private.validated_tender_sum(p_payload -> 'tenders');
  if v_tender_sum <> v_cash then raise exception 'tender_mismatch'; end if;
  for v_tender in select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') loop
    v_method := v_tender ->> 'method';
    v_amount := private.opening_checked_bigint(private.opening_parse_amount(v_tender ->> 'piastres'));
    v_refundable := private.checked_signed_bigint(
      private.parse_signed_amount(v_bounds -> 'refundable_by_method' ->> v_method));
    if v_amount > v_refundable then raise exception 'return_exceeds_original'; end if;
    if v_kind = 'sale_return'
      and private.method_balance(p_shop, v_method, null) < v_amount then
      raise exception 'negative_owned_balance';
    end if;
  end loop;
  if v_kind = 'purchase_return' then
    v_refundable := 0;
    foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
      v_refundable := v_refundable + private.checked_signed_bigint(
        private.parse_signed_amount(v_bounds -> 'refundable_by_method' ->> v_method));
    end loop;
    if v_cash > v_refundable then raise exception 'return_exceeds_original'; end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'item_index', line.item_index::text, 'category', line.category,
    'karat', line.karat, 'item_name', line.item_name,
    'milligrams', line.milligrams::text,
    'count', case when line.category = 'scrap' then null else line.piece_count::text end
  ) order by line.item_index), '[]'::jsonb) into v_detail_items
  from private.return_movement_lines(p_shop, p_payload) line;
  v_detail := p_payload || jsonb_build_object(
    'items', v_detail_items, 'total_piastres', v_consideration::text,
    'original_sequence', (select shop_sequence::text from public.financial_operations where id = v_original and shop_id = p_shop),
    'original_kind', v_bounds ->> 'kind',
    'customer_name', coalesce(v_original_payload ->> 'customer_name', ''),
    'cash_returned_piastres', v_cash::text, 'cancelled_payable_piastres', v_cancel::text);
  v_operation := private.insert_operation(
    p_shop, v_kind, p_day, p_actor, p_at, v_detail);
  for v_source in select * from private.return_movement_lines(p_shop, p_payload) loop
    perform private.post_account_delta(
      p_shop, v_operation,
      case when v_source.category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
      'gold_mg', v_source.category, v_source.karat, null,
      case when v_kind = 'sale_return' then v_source.milligrams else -v_source.milligrams end,
      'movement_gold_clearing', v_kind = 'sale_return');
    if v_source.category <> 'scrap' then
      perform private.post_account_delta(
        p_shop, v_operation, 'saleable_count', 'count',
        v_source.category, v_source.karat, null,
        case when v_kind = 'sale_return' then v_source.piece_count else -v_source.piece_count end,
        'movement_count_clearing', v_kind = 'sale_return');
    end if;
  end loop;
  for v_tender in select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') loop
    v_amount := private.opening_checked_bigint(private.opening_parse_amount(v_tender ->> 'piastres'));
    perform private.post_account_delta(
      p_shop, v_operation, 'cash_method', 'money', null, null, v_tender ->> 'method',
      case when v_kind = 'sale_return' then -v_amount else v_amount end,
      'movement_money_clearing', v_kind = 'purchase_return');
  end loop;
  if v_cancel > 0 then
    update public.purchase_cash_payables
    set remaining_piastres = remaining_piastres - v_cancel, updated_at = p_at
    where shop_id = p_shop and operation_id = v_original;
  end if;
  if p_bump then
    return private.finish_financial_command(
      p_shop, v_operation, p_actor, p_at, p_day, v_kind || '_confirmed',
      p_key, p_payload,
      pg_catalog.jsonb_build_object(
        'business_day_id', p_day, 'operation_id', v_operation,
        'original_operation_id', v_original,
        'cancelled_payable_piastres', v_cancel::text,
        'cash_refund_piastres', v_cash::text))
      || pg_catalog.jsonb_build_object(
        'cancelled_payable_piastres', v_cancel::text,
        'cash_refund_piastres', v_cash::text);
  end if;
  select day.day_version into v_version
  from public.business_days as day where day.id = p_day and day.shop_id = p_shop;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    p_shop, p_actor, v_kind || '_confirmed', v_operation, p_at,
    pg_catalog.jsonb_build_object('business_day_id', p_day, 'operation_id', v_operation,
      'original_operation_id', v_original));
  insert into public.financial_outbox (shop_id, operation_id, event_type, created_at)
  values (p_shop, v_operation, v_kind || '_confirmed', p_at);
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (p_shop, p_key, p_payload, v_hash, v_operation, p_at);
  perform private.sync_operation_lots(p_shop, v_operation, true);
  return pg_catalog.jsonb_build_object(
    'ok', true, 'operation_id', v_operation, 'business_day_id', p_day,
    'day_version', v_version, 'replayed', false,
    'cancelled_payable_piastres', v_cancel::text,
    'cash_refund_piastres', v_cash::text,
    'effects', private.operation_effects(p_shop, v_operation));
end;
$fn$;


create function private.net_signed_effects(p_left jsonb, p_right jsonb)
returns jsonb language plpgsql immutable security invoker set search_path = '' as $fn$
declare
  v_cash numeric;
  v_buckets jsonb := '[]'::jsonb;
  v_row record;
begin
  v_cash := private.parse_signed_amount(p_left ->> 'cash_piastres')
    + private.parse_signed_amount(p_right ->> 'cash_piastres');
  for v_row in
    select bucket.category, bucket.karat,
      sum(bucket.milligrams) as milligrams,
      sum(bucket.pieces) as pieces,
      bool_or(bucket.scrap) as scrap
    from (
      select item.value ->> 'category' as category,
        (item.value ->> 'karat')::smallint as karat,
        private.parse_signed_amount(item.value ->> 'milligrams') as milligrams,
        case when item.value ->> 'count' is null then 0
          else private.parse_signed_amount(item.value ->> 'count') end as pieces,
        (item.value ->> 'count') is null as scrap
      from pg_catalog.jsonb_array_elements(coalesce(p_left -> 'buckets', '[]'::jsonb)) as item(value)
      union all
      select item.value ->> 'category',
        (item.value ->> 'karat')::smallint,
        private.parse_signed_amount(item.value ->> 'milligrams'),
        case when item.value ->> 'count' is null then 0
          else private.parse_signed_amount(item.value ->> 'count') end,
        (item.value ->> 'count') is null
      from pg_catalog.jsonb_array_elements(coalesce(p_right -> 'buckets', '[]'::jsonb)) as item(value)
    ) as bucket
    group by bucket.category, bucket.karat
  loop
    v_buckets := v_buckets || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'category', v_row.category,
      'karat', v_row.karat,
      'milligrams', private.canonical_signed(v_row.milligrams),
      'count', case when v_row.scrap then null else private.canonical_signed(v_row.pieces) end));
  end loop;
  return pg_catalog.jsonb_build_object(
    'cash_piastres', private.canonical_signed(v_cash),
    'buckets', v_buckets);
end;
$fn$;

create or replace function public.post_daily_ledger_return(
  p_idempotency_key uuid, p_original_operation_id uuid, p_note text
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_original public.financial_operations%rowtype;
  v_original_payload jsonb;
  v_kind text;
  v_payload jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_day uuid;
  v_day_version bigint;
  v_actor uuid;
  v_at timestamptz;
  v_sequence bigint;
  v_operation uuid;
  v_source_journal record;
  v_new_journal uuid;
  v_action text;
  v_remaining bigint := 0;
  v_original_paid numeric := 0;
  v_settled numeric := 0;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_original_operation_id is null
    or p_note is null or length(p_note) > 1000 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select operation.* into v_original
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_original_operation_id
  for update;
  if v_original.id is null then raise exception 'not_found'; end if;
  if v_original.kind not in ('sale', 'purchase') then
    raise exception 'invalid_input';
  end if;
  select detail.payload into v_original_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop and detail.operation_id = v_original.id;
  if v_original_payload is null then raise exception 'not_found'; end if;
  v_kind := v_original.kind || '_return';
  v_payload := pg_catalog.jsonb_build_object(
    'version', 1,
    'kind', v_kind,
    'original_operation_id', v_original.id,
    'original_sequence', v_original.shop_sequence::text,
    'original_kind', v_original.kind,
    'total_piastres', v_original_payload ->> 'total_piastres',
    'tenders', coalesce(v_original_payload -> 'tenders', '[]'::jsonb),
    'items', coalesce(v_original_payload -> 'items', '[]'::jsonb),
    'customer_name', coalesce(v_original_payload ->> 'customer_name', ''),
    'note', p_note
  );
  v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key for update;
  if found then
    if v_request.payload_canonical ->> 'kind' = v_kind
      and v_request.payload_canonical ->> 'original_operation_id' = v_original.id::text
      and v_request.payload_canonical ->> 'note' = p_note then
      return pg_catalog.jsonb_build_object('ok', true,
        'operation_id', v_request.operation_id, 'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if exists (
    select 1 from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = v_shop
      and operation.kind in ('sale_return', 'purchase_return')
      and detail.payload ->> 'original_operation_id' = v_original.id::text
  ) then
    if (private.return_bounds(v_shop, v_original.id) ->> 'fully_returned')::boolean then
      raise exception 'already_returned';
    end if;
    raise exception 'explicit_refund_required';
  end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if v_original.kind = 'purchase' then
    select payable.remaining_piastres into v_remaining
    from public.purchase_cash_payables as payable
    where payable.shop_id = v_shop and payable.operation_id = v_original.id
    for update;
    v_remaining := coalesce(v_remaining, 0);
    select coalesce(sum((tender.value ->> 'piastres')::numeric), 0)
      into v_original_paid
    from pg_catalog.jsonb_array_elements(coalesce(v_original_payload -> 'tenders', '[]'::jsonb))
      as tender(value);
    select coalesce(sum((tender.value ->> 'piastres')::numeric), 0)
      into v_settled
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral pg_catalog.jsonb_array_elements(detail.payload -> 'tenders') as tender(value)
    where operation.shop_id = v_shop and operation.kind = 'purchase_settlement'
      and detail.payload ->> 'purchase_operation_id' = v_original.id::text;
    v_payload := pg_catalog.jsonb_set(v_payload, '{cash_returned_piastres}',
      pg_catalog.to_jsonb((v_original_paid + v_settled)::bigint::text));
    v_payload := pg_catalog.jsonb_set(v_payload, '{cancelled_payable_piastres}',
      pg_catalog.to_jsonb(v_remaining::text));
    v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  else
    v_payload := pg_catalog.jsonb_set(v_payload, '{cash_returned_piastres}',
      pg_catalog.to_jsonb((v_original_payload ->> 'total_piastres')));
    v_payload := pg_catalog.jsonb_set(v_payload, '{cancelled_payable_piastres}', '"0"'::jsonb);
    v_hash := extensions.digest(convert_to(v_payload::text, 'UTF8'), 'sha256');
  end if;
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key for update;
  if found then
    if v_request.payload_canonical = v_payload
      and v_request.payload_sha256 = v_hash then
      return pg_catalog.jsonb_build_object('ok', true,
        'operation_id', v_request.operation_id, 'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, v_kind, v_day, v_actor, v_at)
  returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_operation, v_shop, v_payload, v_at);
  for v_source_journal in
    select journal.* from public.journals as journal
    where journal.shop_id = v_shop and (
      journal.operation_id = v_original.id or (
        v_original.kind = 'purchase' and journal.operation_id in (
          select operation.id from public.financial_operations as operation
          join public.financial_operation_details as detail
            on detail.shop_id = operation.shop_id
           and detail.operation_id = operation.id
          where operation.shop_id = v_shop
            and operation.kind = 'purchase_settlement'
            and detail.payload ->> 'purchase_operation_id' = v_original.id::text
        )
      )
    ) order by journal.id
  loop
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_operation, v_source_journal.unit_kind,
      v_source_journal.currency_code, v_source_journal.karat,
      v_source_journal.bucket_key
    ) returning id into v_new_journal;
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) select v_shop, v_new_journal, posting.account_id, v_operation,
        -posting.amount
      from public.journal_postings as posting
      where posting.shop_id = v_shop
        and posting.journal_id = v_source_journal.id;
  end loop;
  if v_original.kind = 'purchase' then
    update public.purchase_cash_payables
    set remaining_piastres = 0, updated_at = v_at
    where shop_id = v_shop and operation_id = v_original.id;
  end if;
  update public.business_days set day_version = day_version + 1 where id = v_day;
  v_action := v_kind || '_confirmed';
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, v_action, v_operation, v_at,
    pg_catalog.jsonb_build_object('business_day_id', v_day,
      'original_operation_id', v_original.id,
      'operation_id', v_operation));
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_operation, v_action, v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, v_payload, v_hash, v_operation, v_at);
  return pg_catalog.jsonb_build_object('ok', true, 'operation_id', v_operation,
    'business_day_id', v_day, 'day_version', v_day_version + 1,
    'replayed', false);
end;
$fn$;

create function public.post_linked_return_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_gate jsonb;
begin
  v_gate := private.replay_or_gate(p_idempotency_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  if p_payload ->> 'kind' not in ('sale_return', 'purchase_return') then
    raise exception 'invalid_input';
  end if;
  return private.post_linked_return_core(
    (v_gate ->> 'shop_id')::uuid, p_idempotency_key, p_payload,
    (v_gate ->> 'day_id')::uuid, (v_gate ->> 'actor')::uuid,
    (v_gate ->> 'at')::timestamptz, true, false);
end;
$fn$;

create function public.post_ledger_correction_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_gate jsonb;
  v_shop uuid;
  v_deltas jsonb;
  v_operation uuid;
  v_line jsonb;
  v_method text;
  v_amount bigint;
  v_mg bigint;
  v_count bigint;
begin
  perform private.json_keys_allowed(p_payload, array[
    'version', 'kind', 'expected_day_id', 'expected_day_version', 'reason', 'counted'
  ], array[]::text[]);
  if p_payload ->> 'kind' is distinct from 'ledger_correction' then
    raise exception 'invalid_input';
  end if;
  perform private.require_reason(p_payload);
  if (p_payload ->> 'reason') !~ '[ء-ي]' then raise exception 'invalid_input'; end if;
  v_gate := private.replay_or_gate(p_idempotency_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_deltas := private.correction_counted_deltas(v_shop, p_payload, null);
  v_operation := private.insert_operation(
    v_shop, 'ledger_correction', (v_gate ->> 'day_id')::uuid,
    (v_gate ->> 'actor')::uuid, (v_gate ->> 'at')::timestamptz, p_payload);
  foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
    v_amount := private.checked_signed_bigint(
      private.parse_signed_amount(v_deltas -> 'cash' ->> v_method));
    perform private.post_account_delta(
      v_shop, v_operation, 'cash_method', 'money', null, null, v_method,
      v_amount, 'adjustment_money_clearing', v_amount > 0);
  end loop;
  for v_line in select value from pg_catalog.jsonb_array_elements(v_deltas -> 'stock') loop
    v_mg := private.checked_signed_bigint(private.parse_signed_amount(v_line ->> 'milligrams'));
    v_count := private.checked_signed_bigint(private.parse_signed_amount(v_line ->> 'count'));
    perform private.post_account_delta(
      v_shop, v_operation, 'saleable_metal', 'gold_mg',
      v_line ->> 'category', (v_line ->> 'karat')::smallint, null,
      v_mg, 'adjustment_gold_clearing', v_mg > 0);
    perform private.post_account_delta(
      v_shop, v_operation, 'saleable_count', 'count',
      v_line ->> 'category', (v_line ->> 'karat')::smallint, null,
      v_count, 'adjustment_count_clearing', v_count > 0);
  end loop;
  for v_line in select value from pg_catalog.jsonb_array_elements(v_deltas -> 'scrap') loop
    v_mg := private.checked_signed_bigint(private.parse_signed_amount(v_line ->> 'milligrams'));
    perform private.post_account_delta(
      v_shop, v_operation, 'scrap_metal', 'gold_mg', 'scrap',
      (v_line ->> 'karat')::smallint, null, v_mg, 'adjustment_gold_clearing', v_mg > 0);
  end loop;
  return private.finish_financial_command(
    v_shop, v_operation, (v_gate ->> 'actor')::uuid, (v_gate ->> 'at')::timestamptz,
    (v_gate ->> 'day_id')::uuid, 'ledger_correction_confirmed',
    p_idempotency_key, p_payload,
    pg_catalog.jsonb_build_object(
      'business_day_id', v_gate ->> 'day_id', 'operation_id', v_operation, 'deltas', v_deltas))
    || pg_catalog.jsonb_build_object('deltas', v_deltas);
end;
$fn$;

create function private.exchange_result(
  p_shop uuid, p_parent uuid, p_return uuid, p_replacement uuid,
  p_day uuid, p_version bigint, p_replayed boolean
) returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_return jsonb; v_replacement jsonb;
begin
  v_return := private.signed_journal_effects(p_shop, p_return);
  v_replacement := private.signed_journal_effects(p_shop, p_replacement);
  return pg_catalog.jsonb_build_object(
    'ok', true,
    'operation_id', p_parent,
    'return_operation_id', p_return,
    'replacement_operation_id', p_replacement,
    'business_day_id', p_day,
    'day_version', p_version,
    'replayed', p_replayed,
    'return_effects', v_return,
    'replacement_effects', v_replacement,
    'net_effects', private.net_signed_effects(v_return, v_replacement));
end;
$fn$;

create function private.compensation_assert_cash(p_shop uuid)
returns void language plpgsql stable security definer set search_path = '' as $fn$
begin
  if exists(select 1 from public.ledger_accounts account
    join public.journal_postings posting on posting.account_id = account.id and posting.shop_id = account.shop_id
    where account.shop_id = p_shop and account.account_kind = 'cash_method'
    group by account.id having sum(posting.amount::numeric) < 0) then
    raise exception 'negative_owned_balance';
  end if;
end;
$fn$;
revoke all on function private.compensation_assert_cash(uuid) from public, anon, authenticated;

create function public.post_exchange_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_gate jsonb;
  v_shop uuid;
  v_day uuid;
  v_actor uuid;
  v_at timestamptz;
  v_return jsonb;
  v_replacement jsonb;
  v_child jsonb;
  v_return_key uuid;
  v_trade_key uuid;
  v_return_id uuid;
  v_trade jsonb;
  v_trade_id uuid;
  v_parent uuid;
  v_version bigint;
  v_hash bytea;
begin
  perform private.json_keys_allowed(p_payload, array[
    'version', 'kind', 'expected_day_id', 'expected_day_version', 'note',
    'return', 'replacement'
  ], array[]::text[]);
  if p_payload ->> 'kind' is distinct from 'exchange'
    or pg_catalog.jsonb_typeof(p_payload -> 'note') is distinct from 'string'
    or char_length(p_payload ->> 'note') > 1000
    or pg_catalog.jsonb_typeof(p_payload -> 'return') is distinct from 'object'
    or pg_catalog.jsonb_typeof(p_payload -> 'replacement') is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  v_return := p_payload -> 'return';
  v_replacement := p_payload -> 'replacement';
  perform private.json_keys_allowed(v_return, array[
    'kind', 'original_operation_id', 'note', 'items', 'consideration_piastres', 'tenders'
  ], array['pricing']);
  if v_return ->> 'kind' = 'sale_return' then
    if v_replacement ->> 'kind' is distinct from 'sale' then raise exception 'invalid_input'; end if;
  elsif v_return ->> 'kind' = 'purchase_return' then
    if v_replacement ->> 'kind' is distinct from 'purchase' then raise exception 'invalid_input'; end if;
  else
    raise exception 'invalid_input';
  end if;
  v_gate := private.replay_or_gate(p_idempotency_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then
    v_shop := private.opening_require_reader_shop();
    v_return_key := private.compensation_child_key(p_idempotency_key, ':return');
    v_trade_key := private.compensation_child_key(p_idempotency_key, ':replacement');
    select request.operation_id into v_return_id
    from public.financial_command_requests as request
    where request.shop_id = v_shop and request.idempotency_key = v_return_key;
    select request.operation_id into v_trade_id
    from public.financial_command_requests as request
    where request.shop_id = v_shop and request.idempotency_key = v_trade_key;
    select operation.business_day_id, day.day_version into v_day, v_version
    from public.financial_operations as operation
    join public.business_days as day on day.id = operation.business_day_id
    where operation.shop_id = v_shop and operation.id = (v_gate ->> 'operation_id')::uuid;
    return private.exchange_result(
      v_shop, (v_gate ->> 'operation_id')::uuid, v_return_id, v_trade_id,
      v_day, v_version, true);
  end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  v_return_key := private.compensation_child_key(p_idempotency_key, ':return');
  v_trade_key := private.compensation_child_key(p_idempotency_key, ':replacement');
  if exists (
    select 1 from public.financial_command_requests as request
    where request.shop_id = v_shop
      and request.idempotency_key in (v_return_key, v_trade_key)
  ) then
    raise exception 'payload_mismatch';
  end if;
  v_child := v_return || pg_catalog.jsonb_build_object(
    'version', 1,
    'expected_day_id', p_payload ->> 'expected_day_id',
    'expected_day_version', p_payload ->> 'expected_day_version');
  perform private.post_linked_return_core(
    v_shop, v_return_key, v_child, v_day, v_actor, v_at, false, false);
  v_trade := public.post_daily_ledger_trade(v_trade_key, v_replacement);
  perform private.compensation_assert_cash(v_shop);
  v_return_id := (
    select request.operation_id from public.financial_command_requests as request
    where request.shop_id = v_shop and request.idempotency_key = v_return_key);
  v_trade_id := (v_trade ->> 'operation_id')::uuid;
  v_version := (v_trade ->> 'day_version')::bigint;
  v_parent := private.insert_operation(v_shop, 'exchange', v_day, v_actor, v_at, p_payload);
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, 'exchange_confirmed', v_parent, v_at,
    pg_catalog.jsonb_build_object(
      'business_day_id', v_day, 'operation_id', v_parent,
      'return_operation_id', v_return_id, 'replacement_operation_id', v_trade_id));
  insert into public.financial_outbox (shop_id, operation_id, event_type, created_at)
  values (v_shop, v_parent, 'exchange_confirmed', v_at);
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (v_shop, p_idempotency_key, p_payload, v_hash, v_parent, v_at);
  perform private.sync_operation_lots(v_shop, v_parent, true);
  return private.exchange_result(
    v_shop, v_parent, v_return_id, v_trade_id, v_day, v_version, false);
end;
$fn$;

create function public.get_return_remainder_v1(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_operation_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  return private.return_bounds(v_shop, p_operation_id);
end;
$fn$;

create function public.get_ledger_compensation_summary_v1()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_day public.business_days%rowtype;
  v_gross_sale numeric := 0;
  v_gross_purchase numeric := 0;
  v_sale_return numeric := 0;
  v_purchase_return numeric := 0;
  v_correction_cash numeric := 0;
  v_sale_gold jsonb;
  v_purchase_gold jsonb;
  v_correction_gold jsonb;
  v_correction_cash_methods jsonb;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  select day.* into v_day from public.business_days as day
  where day.shop_id = v_shop order by day.opened_at desc, day.id desc limit 1;
  if v_day.id is null then
    return pg_catalog.jsonb_build_object('state', 'uninitialized');
  end if;
  select coalesce(sum(private.opening_parse_amount(detail.payload ->> 'total_piastres'))
    filter (where operation.kind in ('sale', 'scrap_sale')), 0),
    coalesce(sum(private.opening_parse_amount(detail.payload ->> 'total_piastres'))
    filter (where operation.kind = 'purchase'), 0),
    coalesce(sum(private.return_consideration(detail.payload))
    filter (where operation.kind = 'sale_return'), 0),
    coalesce(sum(private.return_consideration(detail.payload))
    filter (where operation.kind = 'purchase_return'), 0)
  into v_gross_sale, v_gross_purchase, v_sale_return, v_purchase_return
  from public.financial_operations as operation
  join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop and operation.business_day_id = v_day.id;
  select coalesce(sum(posting.amount), 0) into v_correction_cash
  from public.journal_postings as posting
  join public.ledger_accounts as account
    on account.shop_id = posting.shop_id and account.id = posting.account_id
  join public.financial_operations as operation
    on operation.shop_id = posting.shop_id and operation.id = posting.operation_id
  where posting.shop_id = v_shop and operation.business_day_id = v_day.id
    and operation.kind = 'ledger_correction' and account.account_kind = 'cash_method';
  select coalesce(pg_catalog.jsonb_object_agg(method.method_code, method.amount), '{}'::jsonb)
  into v_correction_cash_methods
  from (
    select account.method_code,
      private.canonical_signed(coalesce(sum(posting.amount), 0)) as amount
    from public.ledger_accounts as account
    left join public.journal_postings as posting
      on posting.shop_id = account.shop_id and posting.account_id = account.id
     and posting.operation_id in (
       select operation.id from public.financial_operations as operation
       where operation.shop_id = v_shop and operation.business_day_id = v_day.id
         and operation.kind = 'ledger_correction')
    where account.shop_id = v_shop and account.account_kind = 'cash_method'
    group by account.method_code
  ) as method;
  with lines as (
    select operation.kind, line.category, line.karat, line.milligrams, line.piece_count
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral private.return_movement_lines(v_shop, detail.payload) as line
    where operation.shop_id = v_shop and operation.business_day_id = v_day.id
      and operation.kind in ('sale_return', 'purchase_return')
    union all
    select operation.kind, item.value ->> 'category', (item.value ->> 'karat')::smallint,
      private.line_milligrams(item.value), private.line_count(item.value, item.value ->> 'category')
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral pg_catalog.jsonb_array_elements(coalesce(detail.payload -> 'items', '[]'::jsonb))
      as item(value)
    where operation.shop_id = v_shop and operation.business_day_id = v_day.id
      and operation.kind in ('sale', 'scrap_sale', 'purchase')
  )
  select
    coalesce((select pg_catalog.jsonb_agg(row_to_json(bucket)::jsonb) from (
      select category, karat,
        private.canonical_signed(coalesce(sum(milligrams) filter (where kind in ('sale', 'scrap_sale')), 0)) as gross_milligrams,
        private.canonical_signed(coalesce(sum(milligrams) filter (where kind = 'sale_return'), 0)) as returned_milligrams,
        private.canonical_signed(
          coalesce(sum(milligrams) filter (where kind in ('sale', 'scrap_sale')), 0)
          - coalesce(sum(milligrams) filter (where kind = 'sale_return'), 0)) as net_milligrams
      from lines where kind in ('sale', 'scrap_sale', 'sale_return')
      group by category, karat
    ) as bucket), '[]'::jsonb),
    coalesce((select pg_catalog.jsonb_agg(row_to_json(bucket)::jsonb) from (
      select category, karat,
        private.canonical_signed(coalesce(sum(milligrams) filter (where kind = 'purchase'), 0)) as gross_milligrams,
        private.canonical_signed(coalesce(sum(milligrams) filter (where kind = 'purchase_return'), 0)) as returned_milligrams,
        private.canonical_signed(
          coalesce(sum(milligrams) filter (where kind = 'purchase'), 0)
          - coalesce(sum(milligrams) filter (where kind = 'purchase_return'), 0)) as net_milligrams
      from lines where kind in ('purchase', 'purchase_return')
      group by category, karat
    ) as bucket), '[]'::jsonb)
  into v_sale_gold, v_purchase_gold;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'category', bucket.category_code, 'karat', bucket.karat,
    'milligrams', private.canonical_signed(bucket.milligrams),
    'count', case when bucket.category_code = 'scrap' then null
      else private.canonical_signed(bucket.pieces) end
  ) order by bucket.category_code, bucket.karat), '[]'::jsonb)
  into v_correction_gold
  from (
    select account.category_code, account.karat,
      coalesce(sum(posting.amount) filter (
        where account.account_kind in ('saleable_metal', 'scrap_metal')), 0) as milligrams,
      coalesce(sum(posting.amount) filter (
        where account.account_kind = 'saleable_count'), 0) as pieces
    from public.journal_postings as posting
    join public.ledger_accounts as account
      on account.shop_id = posting.shop_id and account.id = posting.account_id
    join public.financial_operations as operation
      on operation.shop_id = posting.shop_id and operation.id = posting.operation_id
    where posting.shop_id = v_shop and operation.business_day_id = v_day.id
      and operation.kind = 'ledger_correction'
      and account.account_kind in ('saleable_metal', 'scrap_metal', 'saleable_count')
    group by account.category_code, account.karat
  ) as bucket;
  return pg_catalog.jsonb_build_object(
    'state', v_day.status,
    'business_day_id', v_day.id,
    'day_version', v_day.day_version::text,
    'gross_sale_piastres', private.canonical_signed(v_gross_sale),
    'gross_purchase_piastres', private.canonical_signed(v_gross_purchase),
    'sale_return_piastres', private.canonical_signed(v_sale_return),
    'purchase_return_piastres', private.canonical_signed(v_purchase_return),
    'net_sale_piastres', private.canonical_signed(v_gross_sale - v_sale_return),
    'net_purchase_piastres', private.canonical_signed(v_gross_purchase - v_purchase_return),
    'correction_cash_delta_piastres', private.canonical_signed(v_correction_cash),
    'correction_cash_by_method', coalesce(v_correction_cash_methods, '{}'::jsonb),
    'sale_gold', coalesce(v_sale_gold, '[]'::jsonb),
    'purchase_gold', coalesce(v_purchase_gold, '[]'::jsonb),
    'correction_gold', coalesce(v_correction_gold, '[]'::jsonb));
end;
$fn$;

revoke all on function private.compensation_extend_in_check(regclass, name, text, text[]) from public, anon, authenticated;
revoke all on function private.canonical_signed(numeric) from public, anon, authenticated;
revoke all on function private.return_consideration(jsonb) from public, anon, authenticated;
revoke all on function private.return_movement_lines(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.json_add_method(jsonb, text, numeric) from public, anon, authenticated;
revoke all on function private.return_bounds(uuid, uuid) from public, anon, authenticated;
revoke all on function private.compensation_child_key(uuid, text) from public, anon, authenticated;
revoke all on function private.json_keys_allowed(jsonb, text[], text[]) from public, anon, authenticated;
revoke all on function private.method_balance(uuid, text, uuid) from public, anon, authenticated;
revoke all on function private.metal_balance(uuid, text, smallint, uuid) from public, anon, authenticated;
revoke all on function private.signed_journal_effects(uuid, uuid) from public, anon, authenticated;
revoke all on function private.correction_counted_deltas(uuid, jsonb, uuid) from public, anon, authenticated;
revoke all on function private.apply_correction_lots(uuid, uuid, jsonb) from public, anon, authenticated;
revoke all on function private.apply_operation_lots(uuid, uuid) from public, anon, authenticated;
revoke all on function private.post_linked_return_core(uuid, uuid, jsonb, uuid, uuid, timestamptz, boolean, boolean) from public, anon, authenticated;
revoke all on function private.net_signed_effects(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.exchange_result(uuid, uuid, uuid, uuid, uuid, bigint, boolean) from public, anon, authenticated;
revoke all on function public.post_linked_return_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_ledger_correction_v1(uuid, jsonb) from public, anon;
revoke all on function public.post_exchange_v1(uuid, jsonb) from public, anon;
revoke all on function public.get_return_remainder_v1(uuid) from public, anon;
revoke all on function public.get_ledger_compensation_summary_v1() from public, anon;
grant execute on function public.post_linked_return_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_ledger_correction_v1(uuid, jsonb) to authenticated;
grant execute on function public.post_exchange_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_return_remainder_v1(uuid) to authenticated;
grant execute on function public.get_ledger_compensation_summary_v1() to authenticated;

alter function public.get_daily_ledger_operation(uuid) rename to get_daily_ledger_operation_before_compensation;
revoke all on function public.get_daily_ledger_operation_before_compensation(uuid) from public, anon, authenticated;
create function public.get_daily_ledger_operation(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_result jsonb; v_bounds jsonb; v_shop uuid; v_links jsonb; v_day uuid; v_version bigint;
begin
  v_result := public.get_daily_ledger_operation_before_compensation(p_operation_id);
  v_shop := private.opening_require_reader_shop();
  if v_result ->> 'kind' in ('sale', 'purchase') then
    v_bounds := private.return_bounds(v_shop, p_operation_id);
    v_result := jsonb_set(v_result, '{return_remainder}', v_bounds);
    if not (v_bounds ->> 'fully_returned')::boolean then
      v_result := jsonb_set(v_result, '{returned_by_operation_id}', 'null'::jsonb);
    end if;
  elsif v_result ->> 'kind' = 'exchange' then
    select audit.details into v_links from public.financial_audit_events audit
      where audit.shop_id = v_shop and audit.operation_id = p_operation_id and audit.action = 'exchange_confirmed';
    select operation.business_day_id, day.day_version into v_day, v_version
      from public.financial_operations operation join public.business_days day on day.id = operation.business_day_id
      where operation.shop_id = v_shop and operation.id = p_operation_id;
    v_result := v_result || jsonb_build_object('exchange_effects', private.exchange_result(v_shop,p_operation_id,
      (v_links ->> 'return_operation_id')::uuid,(v_links ->> 'replacement_operation_id')::uuid,v_day,v_version,true));
  elsif v_result ->> 'kind' = 'ledger_correction' then
    v_result := v_result || jsonb_build_object('correction_effects', private.signed_journal_effects(v_shop,p_operation_id));
  end if;
  return v_result;
end;
$fn$;
revoke all on function public.get_daily_ledger_operation(uuid) from public, anon;
grant execute on function public.get_daily_ledger_operation(uuid) to authenticated;

create or replace function private.ledger_operation_label(p_kind text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case p_kind
    when 'opening_balances' then 'رصيد افتتاحي'
    when 'sale' then 'بيع'
    when 'purchase' then 'شراء'
    when 'expense' then 'مصروف'
    when 'purchase_settlement' then 'سداد شراء'
    when 'cash_transfer' then 'تحويل نقدية'
    when 'scrap_sale' then 'بيع كسر'
    when 'scrap_to_stock' then 'تحويل كسر إلى مخزون'
    when 'sale_return' then 'مرتجع بيع'
    when 'purchase_return' then 'مرتجع شراء'
    when 'close_day' then 'تقفيل اليومية'
    when 'open_day' then 'فتح اليومية'
    when 'ledger_correction' then 'تسوية فرق الجرد'
    when 'exchange' then 'استبدال'
    when 'daily_note' then 'ملاحظة يومية'
    else null
  end;
$fn$;
commit;

-- Current-day sale and purchase edit/delete.
-- One owner transaction reverses the source through the linked-return core,
-- then posts an optional replacement trade. Active feeds hide the source and
-- the internal reversal. Journal, audit, and the original payload stay.
begin;

select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  array['trade_edited', 'trade_deleted']
);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  array['trade_edited', 'trade_deleted']
);

create table public.ledger_trade_changes (
  shop_id uuid not null,
  source_operation_id uuid not null,
  action text not null,
  reversal_operation_id uuid not null,
  replacement_operation_id uuid,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  source_sha256 text not null,
  review_token text not null,
  command_key uuid not null,
  primary key (shop_id, source_operation_id),
  constraint ledger_trade_changes_action_check check (action in ('edit', 'delete')),
  constraint ledger_trade_changes_shape_check check (
    reversal_operation_id is distinct from source_operation_id
    and (
      (action = 'delete' and replacement_operation_id is null)
      or (
        action = 'edit'
        and replacement_operation_id is not null
        and replacement_operation_id is distinct from source_operation_id
        and replacement_operation_id is distinct from reversal_operation_id
      )
    )
  ),
  constraint ledger_trade_changes_source_sha_check check (source_sha256 ~ '^[0-9a-f]{64}$'),
  constraint ledger_trade_changes_token_check check (review_token ~ '^[0-9a-f]{64}$'),
  constraint ledger_trade_changes_source_fkey
    foreign key (shop_id, source_operation_id)
    references public.financial_operations (shop_id, id),
  constraint ledger_trade_changes_reversal_fkey
    foreign key (shop_id, reversal_operation_id)
    references public.financial_operations (shop_id, id),
  constraint ledger_trade_changes_replacement_fkey
    foreign key (shop_id, replacement_operation_id)
    references public.financial_operations (shop_id, id),
  constraint ledger_trade_changes_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint ledger_trade_changes_shop_fkey
    foreign key (shop_id) references public.shops (id)
);

create unique index ledger_trade_changes_reversal_uidx
  on public.ledger_trade_changes (shop_id, reversal_operation_id);
create unique index ledger_trade_changes_replacement_uidx
  on public.ledger_trade_changes (shop_id, replacement_operation_id);
create unique index ledger_trade_changes_command_uidx
  on public.ledger_trade_changes (shop_id, command_key);
create index ledger_trade_changes_actor_idx
  on public.ledger_trade_changes (shop_id, actor_user_id);

create table public.ledger_trade_change_audits (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  source_operation_id uuid not null,
  actor_user_id uuid not null,
  action text not null,
  created_at timestamptz not null,
  details jsonb not null,
  constraint ledger_trade_change_audits_action_check
    check (action in ('trade_edited', 'trade_deleted')),
  constraint ledger_trade_change_audits_details_check
    check (pg_catalog.jsonb_typeof(details) = 'object'),
  constraint ledger_trade_change_audits_source_fkey
    foreign key (shop_id, source_operation_id)
    references public.financial_operations (shop_id, id),
  constraint ledger_trade_change_audits_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint ledger_trade_change_audits_shop_fkey
    foreign key (shop_id) references public.shops (id)
);

create index ledger_trade_change_audits_source_idx
  on public.ledger_trade_change_audits (shop_id, source_operation_id);
create index ledger_trade_change_audits_actor_idx
  on public.ledger_trade_change_audits (shop_id, actor_user_id);

alter table public.ledger_trade_changes enable row level security;
alter table public.ledger_trade_change_audits enable row level security;

create policy ledger_trade_changes_owner_read
  on public.ledger_trade_changes for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy ledger_trade_change_audits_owner_read
  on public.ledger_trade_change_audits for select to authenticated
  using (private.opening_financial_visible(shop_id));

revoke all on table public.ledger_trade_changes from public, anon, authenticated;
revoke all on table public.ledger_trade_change_audits from public, anon, authenticated;
grant select on table public.ledger_trade_changes to authenticated;
grant select on table public.ledger_trade_change_audits to authenticated;

create trigger ledger_trade_changes_append_only
  before update or delete on public.ledger_trade_changes
  for each row execute function private.financial_audit_events_append_only();
create trigger ledger_trade_change_audits_append_only
  before update or delete on public.ledger_trade_change_audits
  for each row execute function private.financial_audit_events_append_only();

do $service_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke insert, update, delete on table public.ledger_trade_changes from service_role';
    execute 'revoke insert, update, delete on table public.ledger_trade_change_audits from service_role';
  end if;
end;
$service_revoke$;

create function private.ledger_trade_hidden(p_shop uuid, p_operation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.ledger_trade_changes as change
    where change.shop_id = p_shop
      and (
        change.source_operation_id = p_operation
        or change.reversal_operation_id = p_operation
      )
  );
$fn$;

create function private.trade_payload_sha256(p_payload jsonb)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(p_payload::text, 'UTF8'), 'sha256'),
    'hex'
  );
$fn$;

-- JSON null is the stored no-payment array. It is not rewritten on the source.
create function private.trade_payment_array(p_payload jsonb)
returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case
    when pg_catalog.jsonb_typeof(p_payload -> 'tenders') = 'array' then p_payload -> 'tenders'
    when p_payload is null
      or p_payload -> 'tenders' is null
      or p_payload -> 'tenders' = 'null'::jsonb then '[]'::jsonb
    else p_payload -> 'tenders'
  end;
$fn$;

create function private.trade_method_amount(p_payload jsonb, p_method text)
returns numeric
language sql
stable
security invoker
set search_path = ''
as $fn$
  select coalesce(sum(private.opening_parse_amount(tender.value ->> 'piastres')), 0)
  from pg_catalog.jsonb_array_elements(private.trade_payment_array(p_payload)) as tender(value)
  where tender.value ->> 'method' = p_method;
$fn$;

create function private.trade_line_amounts(p_payload jsonb)
returns table (category text, karat integer, milligrams numeric, pieces numeric)
language sql
stable
security invoker
set search_path = ''
as $fn$
  select
    item.value ->> 'category',
    (item.value ->> 'karat')::integer,
    private.opening_parse_amount(item.value ->> 'milligrams'),
    case
      when item.value ->> 'category' = 'scrap' then 0::numeric
      else private.opening_parse_amount(item.value ->> 'count')
    end
  from pg_catalog.jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb)) as item(value);
$fn$;

create function private.trade_change_assert_draft(p_payload jsonb, p_expected_kind text)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_kind text;
  v_total bigint;
  v_tender_sum numeric := 0;
  v_payable bigint := 0;
  v_line_sum numeric := 0;
  v_priced integer := 0;
  v_tender jsonb;
  v_line jsonb;
  v_method text;
  v_seen text[] := '{}';
  v_amount bigint;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
begin
  if pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  if p_payload -> 'version' is null
    or p_payload -> 'version' not in ('1'::jsonb, '2'::jsonb) then
    raise exception 'invalid_input';
  end if;
  v_kind := p_payload ->> 'kind';
  if v_kind is null or v_kind not in ('sale', 'purchase')
    or (p_expected_kind is not null and v_kind is distinct from p_expected_kind)
    or not (p_payload ?& array[
      'version', 'kind', 'total_piastres', 'tenders', 'items',
      'description', 'customer_name', 'customer_phone', 'note'
    ])
    or p_payload - 'version' - 'kind' - 'total_piastres' - 'tenders'
      - 'items' - 'description' - 'customer_name' - 'customer_phone' - 'note'
      - 'purchase_obligation_piastres' - 'pricing'
      <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  if pg_catalog.jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_payload -> 'tenders') not between
      (case when v_kind = 'purchase' then 0 else 1 end) and 4
    or pg_catalog.jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_payload -> 'items') not between 1 and 50 then
    raise exception 'invalid_input';
  end if;
  if pg_catalog.jsonb_typeof(p_payload -> 'total_piastres') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'description') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'customer_name') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'customer_phone') is distinct from 'string'
    or pg_catalog.jsonb_typeof(p_payload -> 'note') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  if coalesce(pg_catalog.length(p_payload ->> 'note'), 0) > 1000
    or coalesce(pg_catalog.length(p_payload ->> 'customer_name'), 0) > 200
    or coalesce(pg_catalog.length(p_payload ->> 'customer_phone'), 0) > 20
    or coalesce(pg_catalog.length(p_payload ->> 'description'), 0) > 300 then
    raise exception 'invalid_input';
  end if;
  if coalesce(p_payload ->> 'customer_phone', '') <> ''
    and (p_payload ->> 'customer_phone') !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  v_total := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'total_piastres'));
  if v_total <= 0 then raise exception 'invalid_input'; end if;
  perform private.validate_trade_pricing(p_payload);
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') as tender(value)
  loop
    if pg_catalog.jsonb_typeof(v_tender) is distinct from 'object'
      or not (v_tender ?& array['method', 'piastres'])
      or v_tender - 'method' - 'piastres' <> '{}'::jsonb
      or pg_catalog.jsonb_typeof(v_tender -> 'method') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any (v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_amount <= 0 then raise exception 'invalid_input'; end if;
    v_tender_sum := v_tender_sum + v_amount;
  end loop;
  if v_kind = 'purchase' then
    if v_tender_sum > v_total then raise exception 'tender_mismatch'; end if;
    v_payable := private.opening_checked_bigint(v_total - v_tender_sum);
    if v_payable > 0 then
      if pg_catalog.jsonb_typeof(p_payload -> 'purchase_obligation_piastres')
          is distinct from 'string'
        or private.opening_checked_bigint(private.opening_parse_amount(
          p_payload ->> 'purchase_obligation_piastres')) <> v_payable then
        raise exception 'invalid_input';
      end if;
    elsif p_payload ? 'purchase_obligation_piastres' then
      raise exception 'invalid_input';
    end if;
  else
    if p_payload ? 'purchase_obligation_piastres' then
      raise exception 'invalid_input';
    end if;
    if v_tender_sum <> v_total then raise exception 'tender_mismatch'; end if;
  end if;
  for v_line in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'items') as line(value)
  loop
    if pg_catalog.jsonb_typeof(v_line) is distinct from 'object'
      or not (v_line ?& array[
        'category', 'karat', 'milligrams', 'count',
        'item_name', 'line_price_piastres'
      ])
      or v_line - 'category' - 'karat' - 'milligrams' - 'count'
        - 'item_name' - 'line_price_piastres' <> '{}'::jsonb
      or pg_catalog.jsonb_typeof(v_line -> 'category') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'milligrams') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'item_name') is distinct from 'string'
      or pg_catalog.jsonb_typeof(v_line -> 'line_price_piastres')
        not in ('string', 'null') then
      raise exception 'invalid_input';
    end if;
    v_category := v_line ->> 'category';
    if pg_catalog.jsonb_typeof(v_line -> 'karat') <> 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$' then
      raise exception 'invalid_input';
    end if;
    v_karat := (v_line ->> 'karat')::smallint;
    if not private.opening_pair_allowed(v_category, v_karat)
      or (v_kind = 'sale' and v_category = 'scrap')
      or nullif(pg_catalog.btrim(v_line ->> 'item_name'), '') is null
      or pg_catalog.length(v_line ->> 'item_name') > 120 then
      raise exception 'invalid_input';
    end if;
    v_mg := private.opening_checked_bigint(
      private.opening_parse_amount(v_line ->> 'milligrams'));
    if v_mg <= 0 then raise exception 'invalid_input'; end if;
    if v_category = 'scrap' then
      if v_line ? 'count' and v_line -> 'count' <> 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
    else
      if pg_catalog.jsonb_typeof(v_line -> 'count') is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_count := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'count'));
      if v_count <= 0 then raise exception 'invalid_input'; end if;
    end if;
    if v_line ? 'line_price_piastres'
      and v_line -> 'line_price_piastres' <> 'null'::jsonb then
      v_priced := v_priced + 1;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'line_price_piastres'));
      if v_amount <= 0 then raise exception 'invalid_input'; end if;
      v_line_sum := v_line_sum + v_amount;
    end if;
  end loop;
  if v_priced <> 0 and (
    v_priced <> pg_catalog.jsonb_array_length(p_payload -> 'items')
    or v_line_sum <> case
      when p_payload -> 'version' = '2'::jsonb
        then private.opening_parse_amount(p_payload -> 'pricing' ->> 'base_piastres')
      else v_total
    end
  ) then
    raise exception 'line_price_mismatch';
  end if;
end;
$fn$;

create function private.trade_change_effects(
  p_kind text, p_source jsonb, p_action text, p_replacement jsonb
) returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_new jsonb := case when p_action = 'delete' then null else p_replacement end;
  v_cash jsonb;
  v_stock jsonb;
  v_scrap jsonb;
  v_old_total numeric;
  v_new_total numeric;
  v_old_paid numeric;
  v_new_paid numeric;
  v_payable numeric;
begin
  v_old_total := private.opening_parse_amount(p_source ->> 'total_piastres');
  v_old_paid := private.validated_tender_sum(private.trade_payment_array(p_source));
  if p_action = 'delete' then
    v_new_total := 0;
    v_new_paid := 0;
  else
    v_new_total := private.opening_parse_amount(p_replacement ->> 'total_piastres');
    v_new_paid := private.validated_tender_sum(private.trade_payment_array(p_replacement));
  end if;
  if p_kind = 'purchase' then
    v_payable := (v_new_total - v_new_paid) - (v_old_total - v_old_paid);
  else
    v_payable := 0;
  end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'method', method.method,
    'delta_piastres', private.canonical_signed(method.delta)
  ) order by method.ord), '[]'::jsonb)
  into v_cash
  from (
    select
      candidate.method,
      candidate.ord,
      case
        when p_kind = 'sale' then
          private.trade_method_amount(v_new, candidate.method)
          - private.trade_method_amount(p_source, candidate.method)
        else
          private.trade_method_amount(p_source, candidate.method)
          - private.trade_method_amount(v_new, candidate.method)
      end as delta
    from (
      values ('cash', 1), ('instant_transfer', 2), ('wallet', 3), ('card', 4)
    ) as candidate(method, ord)
  ) as method
  where method.delta <> 0;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'category', bucket.category,
    'karat', bucket.karat,
    'delta_milligrams', private.canonical_signed(bucket.delta_mg),
    'delta_count', private.canonical_signed(bucket.delta_count)
  ) order by bucket.category, bucket.karat), '[]'::jsonb)
  into v_stock
  from (
    select
      lines.category,
      lines.karat,
      case
        when p_kind = 'sale' then lines.old_mg - lines.new_mg
        else lines.new_mg - lines.old_mg
      end as delta_mg,
      case
        when p_kind = 'sale' then lines.old_count - lines.new_count
        else lines.new_count - lines.old_count
      end as delta_count
    from (
      select
        raw.category,
        raw.karat,
        coalesce(sum(raw.milligrams) filter (where raw.side = 'old'), 0) as old_mg,
        coalesce(sum(raw.pieces) filter (where raw.side = 'old'), 0) as old_count,
        coalesce(sum(raw.milligrams) filter (where raw.side = 'new'), 0) as new_mg,
        coalesce(sum(raw.pieces) filter (where raw.side = 'new'), 0) as new_count
      from (
        select 'old' as side, line.category, line.karat, line.milligrams, line.pieces
        from private.trade_line_amounts(p_source) as line
        union all
        select 'new', line.category, line.karat, line.milligrams, line.pieces
        from private.trade_line_amounts(v_new) as line
      ) as raw
      where raw.category is distinct from 'scrap'
      group by raw.category, raw.karat
    ) as lines
  ) as bucket
  where bucket.delta_mg <> 0 or bucket.delta_count <> 0;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'karat', bucket.karat,
    'delta_milligrams', private.canonical_signed(bucket.delta_mg)
  ) order by bucket.karat), '[]'::jsonb)
  into v_scrap
  from (
    select
      lines.karat,
      case
        when p_kind = 'sale' then lines.old_mg - lines.new_mg
        else lines.new_mg - lines.old_mg
      end as delta_mg
    from (
      select
        raw.karat,
        coalesce(sum(raw.milligrams) filter (where raw.side = 'old'), 0) as old_mg,
        coalesce(sum(raw.milligrams) filter (where raw.side = 'new'), 0) as new_mg
      from (
        select 'old' as side, line.karat, line.milligrams
        from private.trade_line_amounts(p_source) as line
        where line.category = 'scrap'
        union all
        select 'new', line.karat, line.milligrams
        from private.trade_line_amounts(v_new) as line
        where line.category = 'scrap'
      ) as raw
      group by raw.karat
    ) as lines
  ) as bucket
  where bucket.delta_mg <> 0;
  return pg_catalog.jsonb_build_object(
    'cash', coalesce(v_cash, '[]'::jsonb),
    'stock', coalesce(v_stock, '[]'::jsonb),
    'scrap', coalesce(v_scrap, '[]'::jsonb),
    'payable_delta_piastres', private.canonical_signed(v_payable)
  );
end;
$fn$;

create function private.trade_change_token(
  p_shop uuid,
  p_operation uuid,
  p_action text,
  p_source_sha text,
  p_replacement_sha text,
  p_day uuid,
  p_day_version bigint,
  p_effects jsonb
) returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select pg_catalog.encode(extensions.digest(pg_catalog.convert_to((
    pg_catalog.jsonb_build_object(
      'action', p_action,
      'day_id', p_day,
      'day_version', p_day_version::text,
      'effects', p_effects,
      'operation_id', p_operation,
      'replacement_sha256', p_replacement_sha,
      'shop_id', p_shop,
      'source_sha256', p_source_sha
    )
  )::text, 'UTF8'), 'sha256'), 'hex');
$fn$;

create function private.trade_change_command_payload(
  p_action text,
  p_operation uuid,
  p_replacement jsonb,
  p_day uuid,
  p_day_version bigint,
  p_source_sha text,
  p_token text
) returns jsonb
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'kind', 'ledger_trade_change',
    'action', p_action,
    'operation_id', p_operation,
    'replacement', p_replacement,
    'expected_day_id', p_day,
    'expected_day_version', p_day_version::text,
    'source_sha256', p_source_sha,
    'review_token', p_token
  );
$fn$;

create function private.trade_change_reversal_payload(p_source jsonb, p_operation uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_items jsonb;
  v_payload jsonb;
begin
  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'item_index', (item.ordinality - 1)::text,
      'milligrams', item.value ->> 'milligrams',
      'count', case
        when item.value ->> 'category' = 'scrap' then null
        else item.value ->> 'count'
      end
    ))
    order by item.ordinality
  ), '[]'::jsonb)
  into v_items
  from pg_catalog.jsonb_array_elements(p_source -> 'items')
    with ordinality as item(value, ordinality);
  v_payload := pg_catalog.jsonb_build_object(
    'version', 1,
    'kind', case
      when p_source ->> 'kind' = 'sale' then 'sale_return'
      else 'purchase_return'
    end,
    'original_operation_id', p_operation,
    'note', 'عكس عملية اليوم',
    'items', v_items,
    'consideration_piastres', p_source ->> 'total_piastres',
    'tenders', private.trade_payment_array(p_source)
  );
  if p_source ? 'pricing' then
    v_payload := v_payload || pg_catalog.jsonb_build_object('pricing', p_source -> 'pricing');
  end if;
  return v_payload;
end;
$fn$;

create function private.trade_change_assert_followups(
  p_shop uuid, p_operation uuid, p_kind text
) returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_initial bigint;
  v_remaining bigint;
begin
  if exists (
    select 1
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = p_shop
      and operation.kind in ('sale_return', 'purchase_return')
      and detail.payload ->> 'original_operation_id' = p_operation::text
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    where operation.shop_id = p_shop
      and operation.kind = 'purchase_settlement'
      and detail.payload ->> 'purchase_operation_id' = p_operation::text
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1 from public.invoice_dispatch_confirmations as dispatch
    where dispatch.shop_id = p_shop and dispatch.operation_id = p_operation
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1 from public.debt_source_archives as archive
    where archive.shop_id = p_shop and archive.source_id = p_operation
  ) then
    raise exception 'trade_has_followups';
  end if;
  if exists (
    select 1 from public.gold_obligations as gold
    where gold.shop_id = p_shop and gold.operation_id = p_operation
  ) then
    raise exception 'trade_has_followups';
  end if;
  select payable.initial_piastres, payable.remaining_piastres
    into v_initial, v_remaining
  from public.purchase_cash_payables as payable
  where payable.shop_id = p_shop and payable.operation_id = p_operation;
  if found and v_remaining is distinct from v_initial then
    raise exception 'trade_has_followups';
  end if;
  if p_kind = 'purchase' and exists (
    select 1
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = p_shop
      and lot.origin_operation_id = p_operation
      and movement.operation_id is distinct from p_operation
      and (movement.delta_milligrams < 0 or movement.delta_count < 0)
  ) then
    raise exception 'trade_has_followups';
  end if;
end;
$fn$;

create function private.trade_change_assert_affordable(p_shop uuid, p_effects jsonb)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_row jsonb;
  v_delta bigint;
  v_count bigint;
  v_balance bigint;
  v_pieces bigint;
  v_category text;
  v_karat smallint;
  v_method text;
  v_exists boolean;
begin
  for v_row in
    select value from pg_catalog.jsonb_array_elements(coalesce(p_effects -> 'cash', '[]'::jsonb))
  loop
    v_method := v_row ->> 'method';
    v_delta := private.checked_signed_bigint(
      private.parse_signed_amount(v_row ->> 'delta_piastres'));
    if v_delta = 0 then continue; end if;
    select exists (
      select 1 from public.ledger_accounts as account
      where account.shop_id = p_shop
        and account.account_kind = 'cash_method'
        and account.method_code = v_method
    ) into v_exists;
    if not v_exists and v_delta > 0 then
      raise exception 'invalid_input';
    end if;
    if not v_exists and v_delta < 0 then
      raise exception 'negative_owned_balance';
    end if;
    if v_delta < 0 and private.method_balance(p_shop, v_method, null) < -v_delta then
      raise exception 'negative_owned_balance';
    end if;
  end loop;
  for v_row in
    select value from pg_catalog.jsonb_array_elements(coalesce(p_effects -> 'stock', '[]'::jsonb))
  loop
    v_category := v_row ->> 'category';
    v_karat := (v_row ->> 'karat')::smallint;
    v_delta := private.checked_signed_bigint(
      private.parse_signed_amount(v_row ->> 'delta_milligrams'));
    v_count := private.checked_signed_bigint(
      private.parse_signed_amount(v_row ->> 'delta_count'));
    select balance.milligrams, balance.piece_count
      into v_balance, v_pieces
    from private.metal_balance(p_shop, v_category, v_karat, null) as balance;
    v_balance := coalesce(v_balance, 0) + v_delta;
    v_pieces := coalesce(v_pieces, 0) + v_count;
    if v_balance < 0 or v_pieces < 0 then
      raise exception 'negative_owned_balance';
    end if;
    if (v_balance = 0) <> (v_pieces = 0) then
      raise exception 'stock_pair_mismatch';
    end if;
  end loop;
  for v_row in
    select value from pg_catalog.jsonb_array_elements(coalesce(p_effects -> 'scrap', '[]'::jsonb))
  loop
    v_karat := (v_row ->> 'karat')::smallint;
    v_delta := private.checked_signed_bigint(
      private.parse_signed_amount(v_row ->> 'delta_milligrams'));
    select balance.milligrams into v_balance
    from private.metal_balance(p_shop, 'scrap', v_karat, null) as balance;
    if coalesce(v_balance, 0) + v_delta < 0 then
      raise exception 'negative_owned_balance';
    end if;
  end loop;
end;
$fn$;

create function private.trade_change_assert_final(p_shop uuid)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if exists (
    select 1
    from public.ledger_accounts as account
    join public.journal_postings as posting
      on posting.shop_id = account.shop_id and posting.account_id = account.id
    where account.shop_id = p_shop
      and account.account_kind in (
        'cash_method', 'saleable_metal', 'scrap_metal', 'saleable_count'
      )
    group by account.id
    having sum(posting.amount) < 0
  ) then
    raise exception 'negative_owned_balance';
  end if;
  if exists (
    select 1
    from public.ledger_account_balances as metal
    left join public.ledger_account_balances as piece
      on piece.shop_id = metal.shop_id
     and piece.account_kind = 'saleable_count'
     and piece.category_code = metal.category_code
     and piece.karat = metal.karat
    where metal.shop_id = p_shop
      and metal.account_kind = 'saleable_metal'
      and (metal.amount = 0) <> (coalesce(piece.amount, 0) = 0)
  ) then
    raise exception 'stock_pair_mismatch';
  end if;
  perform private.assert_shop_lots(p_shop);
end;
$fn$;

-- Net edit can refund part of a tender after the shop has spent some of it.
-- The return core's immediate balance precheck would reject that even when the
-- replacement restores enough cash in the same transaction. The deferred
-- owned-balance trigger, plus trade_change_assert_final, still rejects a
-- negative end state. The setting is transaction-local and ignored unless on.
do $patch_core$
declare
  v_def text;
  v_sale text := $sale$
    if v_kind = 'sale_return'
      and private.method_balance(p_shop, v_method, null) < v_amount then
      raise exception 'negative_owned_balance';
    end if;$sale$;
  v_sale_next text := $sale$
    if v_kind = 'sale_return'
      and pg_catalog.current_setting('eldaftar.trade_change_net', true) is distinct from 'on'
      and private.method_balance(p_shop, v_method, null) < v_amount then
      raise exception 'negative_owned_balance';
    end if;$sale$;
  v_purchase text := $purchase$
      if v_kind = 'purchase_return' then
        if v_book_mg < v_mg or v_book_count < v_count then$purchase$;
  v_purchase_next text := $purchase$
      if v_kind = 'purchase_return'
        and pg_catalog.current_setting('eldaftar.trade_change_net', true) is distinct from 'on' then
        if v_book_mg < v_mg or v_book_count < v_count then$purchase$;
  v_scrap text := 'if v_book_mg < v_mg then raise exception ''negative_owned_balance''; end if;';
  v_scrap_next text := 'if pg_catalog.current_setting(''eldaftar.trade_change_net'', true) is distinct from ''on'' and v_book_mg < v_mg then raise exception ''negative_owned_balance''; end if;';
begin
  v_def := pg_catalog.replace(pg_catalog.pg_get_functiondef(
    'private.post_linked_return_core(uuid,uuid,jsonb,uuid,uuid,timestamptz,boolean,boolean)'::regprocedure
  ), E'\r\n', E'\n');
  v_sale := pg_catalog.replace(v_sale, E'\r\n', E'\n');
  v_sale_next := pg_catalog.replace(v_sale_next, E'\r\n', E'\n');
  v_purchase := pg_catalog.replace(v_purchase, E'\r\n', E'\n');
  v_purchase_next := pg_catalog.replace(v_purchase_next, E'\r\n', E'\n');
  if v_def is null
    or pg_catalog.strpos(v_def, v_sale) = 0
    or pg_catalog.strpos(v_def, v_purchase) = 0
    or pg_catalog.strpos(v_def, v_scrap) = 0 then
    raise exception 'trade_change_patch_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_sale, v_sale_next);
  v_def := pg_catalog.replace(v_def, v_purchase, v_purchase_next);
  v_def := pg_catalog.replace(v_def, v_scrap, v_scrap_next);
  if pg_catalog.strpos(v_def, 'eldaftar.trade_change_net') = 0 then
    raise exception 'trade_change_patch_anchor';
  end if;
  execute v_def;
end;
$patch_core$;

create function public.review_ledger_trade_change_v1(
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_kind text;
  v_source_day uuid;
  v_payload jsonb;
  v_day uuid;
  v_version bigint;
  v_source_sha text;
  v_replacement_sha text;
  v_effects jsonb;
  v_token text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_operation_id is null or p_action is null then
    raise exception 'invalid_input';
  end if;
  if p_replacement = 'null'::jsonb then
    p_replacement := null;
  end if;
  if p_action = 'delete' then
    if p_replacement is not null then raise exception 'invalid_input'; end if;
  elsif p_action = 'edit' then
    if pg_catalog.jsonb_typeof(p_replacement) is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select operation.kind, operation.business_day_id
    into v_kind, v_source_day
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if not found then raise exception 'not_found'; end if;
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = v_shop and change.source_operation_id = p_operation_id
  ) then
    raise exception 'trade_inactive';
  end if;
  if v_kind not in ('sale', 'purchase') then
    raise exception 'trade_not_editable';
  end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  order by day.opened_at desc
  limit 1;
  if v_day is null then raise exception 'day_closed'; end if;
  if v_source_day is distinct from v_day then
    raise exception 'trade_not_editable';
  end if;
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop and detail.operation_id = p_operation_id;
  if v_payload is null then raise exception 'not_found'; end if;
  if p_action = 'edit' then
    perform private.trade_change_assert_draft(p_replacement, v_kind);
  end if;
  perform private.trade_change_assert_followups(v_shop, p_operation_id, v_kind);
  v_effects := private.trade_change_effects(v_kind, v_payload, p_action, p_replacement);
  perform private.trade_change_assert_affordable(v_shop, v_effects);
  v_source_sha := private.trade_payload_sha256(v_payload);
  v_replacement_sha := case
    when p_action = 'delete' then ''
    else private.trade_payload_sha256(p_replacement)
  end;
  v_token := private.trade_change_token(
    v_shop, p_operation_id, p_action, v_source_sha, v_replacement_sha,
    v_day, v_version, v_effects
  );
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'operation_id', p_operation_id,
    'action', p_action,
    'expected_day_id', v_day,
    'expected_day_version', v_version,
    'source_sha256', v_source_sha,
    'review_token', v_token,
    'source', pg_catalog.jsonb_build_object('kind', v_kind, 'payload', v_payload),
    'effects', v_effects
  );
end;
$fn$;

create function public.post_ledger_trade_change_v1(
  p_idempotency_key uuid,
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb,
  p_expected_day_id uuid,
  p_expected_day_version bigint,
  p_source_sha256 text,
  p_review_token text
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_actor uuid;
  v_at timestamptz;
  v_command jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_change public.ledger_trade_changes%rowtype;
  v_kind text;
  v_source_day uuid;
  v_payload jsonb;
  v_day uuid;
  v_version bigint;
  v_source_sha text;
  v_replacement_sha text;
  v_effects jsonb;
  v_token text;
  v_reversal_key uuid;
  v_replacement_key uuid;
  v_reversal jsonb;
  v_reversal_id uuid;
  v_trade jsonb;
  v_replacement_id uuid;
  v_audit_action text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_operation_id is null or p_action is null
    or p_expected_day_id is null or p_expected_day_version is null
    or p_source_sha256 is null or p_review_token is null
    or p_source_sha256 !~ '^[0-9a-f]{64}$'
    or p_review_token !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_input';
  end if;
  if p_replacement = 'null'::jsonb then
    p_replacement := null;
  end if;
  if p_action = 'delete' then
    if p_replacement is not null then raise exception 'invalid_input'; end if;
  elsif p_action = 'edit' then
    if pg_catalog.jsonb_typeof(p_replacement) is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_command := private.trade_change_command_payload(
    p_action, p_operation_id, p_replacement, p_expected_day_id,
    p_expected_day_version, p_source_sha256, p_review_token
  );
  v_hash := extensions.digest(pg_catalog.convert_to(v_command::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = v_command and v_request.payload_sha256 = v_hash then
      select change.* into v_change
      from public.ledger_trade_changes as change
      where change.shop_id = v_shop and change.command_key = p_idempotency_key;
      if v_change.source_operation_id is null then
        raise exception 'invalid_input';
      end if;
      return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'ok', true,
        'operation_id', v_change.reversal_operation_id,
        'replayed', true,
        'replacement_operation_id', v_change.replacement_operation_id
      ));
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select operation.kind, operation.business_day_id
    into v_kind, v_source_day
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id
  for update;
  if not found then raise exception 'not_found'; end if;
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = v_shop and change.source_operation_id = p_operation_id
  ) then
    raise exception 'operation_replaced';
  end if;
  if v_kind not in ('sale', 'purchase') then
    raise exception 'trade_not_editable';
  end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  order by day.opened_at desc
  limit 1
  for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if v_source_day is distinct from v_day then
    raise exception 'trade_not_editable';
  end if;
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop and detail.operation_id = p_operation_id;
  if v_payload is null then raise exception 'not_found'; end if;
  v_source_sha := private.trade_payload_sha256(v_payload);
  if v_source_sha is distinct from p_source_sha256
    or p_expected_day_id is distinct from v_day
    or p_expected_day_version is distinct from v_version then
    raise exception 'stale_trade_review';
  end if;
  perform private.trade_change_assert_followups(v_shop, p_operation_id, v_kind);
  if p_action = 'edit' then
    perform private.trade_change_assert_draft(p_replacement, v_kind);
    v_replacement_sha := private.trade_payload_sha256(p_replacement);
  else
    v_replacement_sha := '';
  end if;
  v_effects := private.trade_change_effects(v_kind, v_payload, p_action, p_replacement);
  v_token := private.trade_change_token(
    v_shop, p_operation_id, p_action, v_source_sha, v_replacement_sha,
    v_day, v_version, v_effects
  );
  if v_token is distinct from p_review_token then
    raise exception 'stale_trade_review';
  end if;
  perform private.trade_change_assert_affordable(v_shop, v_effects);
  v_reversal_key := private.compensation_child_key(p_idempotency_key, ':trade-reversal');
  v_replacement_key := private.compensation_child_key(p_idempotency_key, ':trade-replacement');
  if exists (
    select 1 from public.financial_command_requests as request
    where request.shop_id = v_shop
      and request.idempotency_key in (v_reversal_key, v_replacement_key)
  ) then
    raise exception 'payload_mismatch';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  perform pg_catalog.set_config('eldaftar.trade_change_net', 'on', true);
  v_reversal := private.post_linked_return_core(
    v_shop,
    v_reversal_key,
    private.trade_change_reversal_payload(v_payload, p_operation_id),
    v_day,
    v_actor,
    v_at,
    false,
    false
  );
  perform pg_catalog.set_config('eldaftar.trade_change_net', 'off', true);
  v_reversal_id := (v_reversal ->> 'operation_id')::uuid;
  if p_action = 'edit' then
    v_trade := public.post_daily_ledger_trade(v_replacement_key, p_replacement);
    v_replacement_id := (v_trade ->> 'operation_id')::uuid;
    insert into public.customer_operation_links (
      shop_id, customer_id, operation_id, status, linked_at, linked_by
    )
    select
      link.shop_id, link.customer_id, v_replacement_id, 'active', v_at, v_actor
    from public.customer_operation_links as link
    where link.shop_id = v_shop
      and link.operation_id = p_operation_id
      and link.status = 'active';
  else
    update public.business_days
    set day_version = day_version + 1
    where id = v_day and shop_id = v_shop;
  end if;
  perform private.trade_change_assert_final(v_shop);
  insert into public.ledger_trade_changes (
    shop_id, source_operation_id, action, reversal_operation_id,
    replacement_operation_id, actor_user_id, created_at, source_sha256,
    review_token, command_key
  ) values (
    v_shop, p_operation_id, p_action, v_reversal_id, v_replacement_id,
    v_actor, v_at, v_source_sha, v_token, p_idempotency_key
  );
  v_audit_action := case when p_action = 'edit' then 'trade_edited' else 'trade_deleted' end;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, v_audit_action, p_operation_id, v_at,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'business_day_id', v_day,
      'operation_id', p_operation_id,
      'reversal_operation_id', v_reversal_id,
      'replacement_operation_id', v_replacement_id,
      'action', p_action
    ))
  );
  insert into public.financial_outbox (shop_id, operation_id, event_type, created_at)
  values (v_shop, p_operation_id, v_audit_action, v_at);
  insert into public.ledger_trade_change_audits (
    shop_id, source_operation_id, actor_user_id, action, created_at, details
  ) values (
    v_shop, p_operation_id, v_actor, v_audit_action, v_at,
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'reversal_operation_id', v_reversal_id,
      'replacement_operation_id', v_replacement_id,
      'command_key', p_idempotency_key,
      'source_sha256', v_source_sha
    ))
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (
    v_shop, p_idempotency_key, v_command, v_hash, v_reversal_id, v_at
  );
  perform private.bump_shop_sync(v_shop, 'invoice');
  perform private.bump_shop_sync(v_shop, 'debt');
  perform private.bump_shop_sync(v_shop, 'customer');
  return pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
    'ok', true,
    'operation_id', v_reversal_id,
    'replayed', false,
    'replacement_operation_id', v_replacement_id
  ));
end;
$fn$;

do $patch_page$
declare
  v_def text;
  v_before text := 'and (v_before is null or operation.shop_sequence < v_before)';
  v_after text := 'and operation.shop_sequence > v_after';
begin
  v_def := pg_catalog.replace(pg_catalog.pg_get_functiondef(
    'public.get_ledger_operation_page(uuid,text,text,integer)'::regprocedure
  ), E'\r\n', E'\n');
  if v_def is null
    or pg_catalog.strpos(v_def, v_before) = 0
    or pg_catalog.strpos(v_def, v_after) = 0 then
    raise exception 'trade_change_patch_anchor';
  end if;
  v_def := pg_catalog.replace(
    v_def, v_before,
    v_before || E'\n        and not private.ledger_trade_hidden(operation.shop_id, operation.id)'
  );
  v_def := pg_catalog.replace(
    v_def, v_after,
    v_after || E'\n        and not private.ledger_trade_hidden(operation.shop_id, operation.id)'
  );
  if (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, 'ledger_trade_hidden', '')))
    / pg_catalog.length('ledger_trade_hidden') < 2 then
    raise exception 'trade_change_patch_anchor';
  end if;
  execute v_def;
end;
$patch_page$;

-- Historical date reads ship before this helper exists. Patch them here so
-- the date migration stays runnable on its own. Summary and feed skip the
-- source and the internal reversal. The date maximum sequence stays
-- unfiltered so a hidden head still invalidates a live snapshot.
do $patch_date$
declare
  v_def text;
  v_summary text := $summary$
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  where operation.shop_id = v_shop
    and operation.business_day_id = any (v_day_ids);$summary$;
  v_summary_next text := $summary$
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  where operation.shop_id = v_shop
    and operation.business_day_id = any (v_day_ids)
    and not private.ledger_trade_hidden(operation.shop_id, operation.id);$summary$;
  v_gold text := $gold$
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and operation.kind in ('sale', 'purchase', 'scrap_sale')$gold$;
  v_gold_next text := $gold$
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      and operation.kind in ('sale', 'purchase', 'scrap_sale')$gold$;
  v_feed text := $feed$
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and (v_before is null or operation.shop_sequence < v_before)$feed$;
  v_feed_next text := $feed$
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      and (v_before is null or operation.shop_sequence < v_before)$feed$;
  v_mark integer;
  v_feed_at integer;
begin
  v_def := pg_catalog.replace(pg_catalog.pg_get_functiondef(
    'public.get_ledger_date_v1(date,text,integer)'::regprocedure
  ), E'\r\n', E'\n');
  v_summary := pg_catalog.replace(v_summary, E'\r\n', E'\n');
  v_summary_next := pg_catalog.replace(v_summary_next, E'\r\n', E'\n');
  v_gold := pg_catalog.replace(v_gold, E'\r\n', E'\n');
  v_gold_next := pg_catalog.replace(v_gold_next, E'\r\n', E'\n');
  v_feed := pg_catalog.replace(v_feed, E'\r\n', E'\n');
  v_feed_next := pg_catalog.replace(v_feed_next, E'\r\n', E'\n');
  if v_def is null
    or pg_catalog.strpos(v_def, v_summary) = 0
    or pg_catalog.strpos(v_def, v_gold) = 0
    or pg_catalog.strpos(v_def, v_feed) = 0 then
    raise exception 'trade_change_patch_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_summary, v_summary_next);
  v_def := pg_catalog.replace(v_def, v_gold, v_gold_next);
  v_def := pg_catalog.replace(v_def, v_feed, v_feed_next);
  v_mark := pg_catalog.strpos(v_def, 'coalesce(max(operation.shop_sequence), 0)');
  v_feed_at := pg_catalog.strpos(v_def, 'with fetched as materialized');
  if v_mark = 0 or v_feed_at <= v_mark
    or pg_catalog.strpos(pg_catalog.substr(v_def, v_mark, v_feed_at - v_mark), 'ledger_trade_hidden') <> 0
    or (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, 'ledger_trade_hidden', '')))
      / pg_catalog.length('ledger_trade_hidden') <> 3 then
    raise exception 'trade_change_patch_anchor';
  end if;
  execute v_def;
end;
$patch_date$;

comment on function public.get_ledger_date_v1(date, text, integer) is
  'Authenticated owner read of one shop business date. Summary and feed skip trade-change sources and internal reversals. Sequence watermarks stay the date maximum, including hidden rows.';

alter function public.get_daily_ledger_v2()
  rename to get_daily_ledger_v2_before_trade_change;
revoke all on function public.get_daily_ledger_v2_before_trade_change()
  from public, anon, authenticated;

create function public.get_daily_ledger_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_base jsonb;
  v_shop uuid;
  v_day uuid;
  v_summary jsonb;
  v_gold jsonb;
begin
  v_base := public.get_daily_ledger_v2_before_trade_change();
  if v_base ->> 'state' is distinct from 'confirmed' then
    return v_base;
  end if;
  v_shop := private.opening_require_reader_shop();
  select day.id into v_day
  from public.business_days as day
  where day.shop_id = v_shop
  order by day.opened_at desc, day.id desc
  limit 1;
  select pg_catalog.jsonb_build_object(
    'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind in ('sale', 'scrap_sale')), 0)::text,
    'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'purchase'), 0)::text,
    'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'expense'), 0)::text,
    'sale_count', count(*) filter (where operation.kind in ('sale', 'scrap_sale')),
    'purchase_count', count(*) filter (where operation.kind = 'purchase'),
    'expense_count', count(*) filter (where operation.kind = 'expense')
  )
  into v_summary
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop
    and operation.business_day_id = v_day
    and not private.ledger_trade_hidden(operation.shop_id, operation.id);
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'kind', bucket.kind,
    'category', bucket.category,
    'karat', bucket.karat,
    'milligrams', bucket.milligrams::text,
    'count', bucket.pieces::text
  ) order by bucket.kind, bucket.category, bucket.karat), '[]'::jsonb)
  into v_gold
  from (
    select
      case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end as kind,
      item.value ->> 'category' as category,
      (item.value ->> 'karat')::smallint as karat,
      sum((item.value ->> 'milligrams')::numeric) as milligrams,
      sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    cross join lateral pg_catalog.jsonb_array_elements(detail.payload -> 'items') as item(value)
    where operation.shop_id = v_shop
      and operation.business_day_id = v_day
      and operation.kind in ('sale', 'purchase', 'scrap_sale')
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
    group by
      case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end,
      item.value ->> 'category',
      (item.value ->> 'karat')::smallint
  ) as bucket;
  v_summary := v_summary || pg_catalog.jsonb_build_object('gold_by_bucket', v_gold);
  return pg_catalog.jsonb_set(v_base, '{day_summary}', v_summary);
end;
$fn$;

alter function public.get_daily_ledger_operation(uuid)
  rename to get_daily_ledger_operation_before_trade_change;
revoke all on function public.get_daily_ledger_operation_before_trade_change(uuid)
  from public, anon, authenticated;

create function public.get_daily_ledger_operation(p_operation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_change public.ledger_trade_changes%rowtype;
begin
  v_result := public.get_daily_ledger_operation_before_trade_change(p_operation_id);
  v_shop := private.opening_require_reader_shop();
  select change.* into v_change
  from public.ledger_trade_changes as change
  where change.shop_id = v_shop and change.source_operation_id = p_operation_id;
  if found then
    return v_result || pg_catalog.jsonb_build_object(
      'trade_change', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'action', v_change.action,
        'replacement_operation_id', v_change.replacement_operation_id
      ))
    );
  end if;
  select change.* into v_change
  from public.ledger_trade_changes as change
  where change.shop_id = v_shop and change.reversal_operation_id = p_operation_id;
  if found then
    return v_result || pg_catalog.jsonb_build_object(
      'trade_change', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'action', v_change.action,
        'role', 'reversal',
        'source_operation_id', v_change.source_operation_id,
        'replacement_operation_id', v_change.replacement_operation_id
      ))
    );
  end if;
  return v_result;
end;
$fn$;

create or replace function public.get_pending_invoice_sends(
  p_before_sequence bigint default null
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_items jsonb;
  v_next bigint;
  v_more boolean;
begin
  v_shop := private.opening_require_reader_shop();
  if p_before_sequence is not null and p_before_sequence < 1 then
    raise exception 'invalid_input';
  end if;
  with page as (
    select
      operation.id, operation.kind, operation.shop_sequence,
      operation.created_at, detail.payload ->> 'customer_name' as customer_name
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    left join public.invoice_dispatch_confirmations as dispatch
      on dispatch.shop_id = operation.shop_id and dispatch.operation_id = operation.id
    where operation.shop_id = v_shop
      and operation.kind in ('sale', 'purchase')
      and dispatch.operation_id is null
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      and (p_before_sequence is null or operation.shop_sequence < p_before_sequence)
    order by operation.shop_sequence desc
    limit 51
  ), numbered as (
    select page.*, pg_catalog.row_number() over (order by page.shop_sequence desc) as row_no
    from page
  )
  select
    coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'operation_id', numbered.id,
      'kind', numbered.kind,
      'shop_sequence', numbered.shop_sequence::text,
      'occurred_at_cairo', pg_catalog.to_char(
        numbered.created_at at time zone 'Africa/Cairo',
        'YYYY-MM-DD"T"HH24:MI:SS'
      ),
      'customer_name', coalesce(numbered.customer_name, '')
    ) order by numbered.shop_sequence desc)
      filter (where numbered.row_no <= 50), '[]'::jsonb),
    min(numbered.shop_sequence) filter (where numbered.row_no <= 50),
    coalesce(bool_or(numbered.row_no = 51), false)
  into v_items, v_next, v_more
  from numbered;
  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'next_before_sequence', case when v_more then v_next else null end
  );
end;
$fn$;

do $patch_summary$
declare
  v_def text;
  v_where text := 'where operation.shop_id = v_shop and operation.business_day_id = v_day.id';
  v_count integer;
begin
  v_def := pg_catalog.replace(pg_catalog.pg_get_functiondef(
    'public.get_ledger_compensation_summary_v1()'::regprocedure
  ), E'\r\n', E'\n');
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_where, ''))
  ) / pg_catalog.length(v_where);
  if v_def is null or v_count <> 4 then
    raise exception 'trade_change_patch_anchor';
  end if;
  v_def := pg_catalog.replace(
    v_def, v_where,
    v_where || ' and not private.ledger_trade_hidden(operation.shop_id, operation.id)'
  );
  execute v_def;
end;
$patch_summary$;

create or replace function private.customer_statistics_activity(
  p_shop uuid, p_customer uuid
) returns setof public.financial_operations
language sql
stable
security definer
set search_path = ''
as $fn$
  with originals as materialized (
    select operation.*
    from public.customer_operation_links as link
    join public.financial_operations as operation
      on operation.shop_id = link.shop_id and operation.id = link.operation_id
    where link.shop_id = p_shop
      and link.customer_id = p_customer
      and link.status = 'active'
      and operation.kind in ('sale', 'purchase')
      and not exists (
        select 1 from public.ledger_trade_changes as change
        where change.shop_id = link.shop_id
          and change.source_operation_id = operation.id
      )
      and exists (
        select 1 from public.financial_operation_details as detail
        where detail.shop_id = p_shop and detail.operation_id = operation.id
      )
      and exists (
        select 1 from public.financial_audit_events as audit
        where audit.shop_id = p_shop
          and audit.operation_id = operation.id
          and audit.action = operation.kind || '_confirmed'
      )
  )
  select * from originals
  union all
  select operation.*
  from originals as original
  join public.financial_operation_details as detail
    on detail.shop_id = p_shop
   and detail.payload ? 'original_operation_id'
   and detail.payload ->> 'original_operation_id' = original.id::text
  join public.financial_operations as operation
    on operation.shop_id = p_shop
   and operation.id = detail.operation_id
   and operation.kind = original.kind || '_return'
  where exists (
    select 1 from public.financial_audit_events as audit
    where audit.shop_id = p_shop
      and audit.operation_id = operation.id
      and audit.action = operation.kind || '_confirmed'
  );
$fn$;

create function private.ledger_trade_reject_inactive_source()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = new.shop_id
      and change.source_operation_id = new.operation_id
  ) then
    raise exception 'trade_inactive';
  end if;
  return new;
end;
$fn$;

create trigger invoice_dispatch_confirmations_reject_inactive_trade
  before insert on public.invoice_dispatch_confirmations
  for each row execute function private.ledger_trade_reject_inactive_source();
create trigger invoice_presentation_revisions_reject_inactive_trade
  before insert on public.invoice_presentation_revisions
  for each row execute function private.ledger_trade_reject_inactive_source();

alter function public.get_invoice_brand_source_v1(uuid)
  rename to get_invoice_brand_source_v1_before_trade_change;
revoke all on function public.get_invoice_brand_source_v1_before_trade_change(uuid)
  from public, anon, authenticated;

create function public.get_invoice_brand_source_v1(p_operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  if p_operation_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = v_shop and change.source_operation_id = p_operation_id
  ) then
    raise exception 'trade_inactive';
  end if;
  return public.get_invoice_brand_source_v1_before_trade_change(p_operation_id);
end;
$fn$;

alter function public.get_invoice_message_source_v1(uuid)
  rename to get_invoice_message_source_v1_before_trade_change;
revoke all on function public.get_invoice_message_source_v1_before_trade_change(uuid)
  from public, anon, authenticated;

create function public.get_invoice_message_source_v1(p_operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  if p_operation_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  if exists (
    select 1 from public.ledger_trade_changes as change
    where change.shop_id = v_shop and change.source_operation_id = p_operation_id
  ) then
    raise exception 'trade_inactive';
  end if;
  return public.get_invoice_message_source_v1_before_trade_change(p_operation_id);
end;
$fn$;

alter function public.get_invoice_dispatch_state(uuid)
  rename to get_invoice_dispatch_state_before_trade_change;
revoke all on function public.get_invoice_dispatch_state_before_trade_change(uuid)
  from public, anon, authenticated;

create function public.get_invoice_dispatch_state(p_operation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_change public.ledger_trade_changes%rowtype;
begin
  v_result := public.get_invoice_dispatch_state_before_trade_change(p_operation_id);
  v_shop := private.opening_require_reader_shop();
  select change.* into v_change
  from public.ledger_trade_changes as change
  where change.shop_id = v_shop and change.source_operation_id = p_operation_id;
  if found then
    v_result := v_result || pg_catalog.jsonb_build_object(
      'trade_change', pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'action', v_change.action,
        'replacement_operation_id', v_change.replacement_operation_id
      )),
      'sendable', false
    );
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.post_daily_ledger_return(uuid, uuid, text)
  from public, anon, authenticated;
revoke all on function public.post_linked_return_v1(uuid, jsonb)
  from public, anon, authenticated;
revoke all on function public.post_exchange_v1(uuid, jsonb)
  from public, anon, authenticated;

revoke all on function private.ledger_trade_hidden(uuid, uuid) from public, anon, authenticated;
revoke all on function private.trade_payment_array(jsonb) from public, anon, authenticated;
revoke all on function private.trade_payload_sha256(jsonb) from public, anon, authenticated;
revoke all on function private.trade_method_amount(jsonb, text) from public, anon, authenticated;
revoke all on function private.trade_line_amounts(jsonb) from public, anon, authenticated;
revoke all on function private.trade_change_assert_draft(jsonb, text) from public, anon, authenticated;
revoke all on function private.trade_change_effects(text, jsonb, text, jsonb) from public, anon, authenticated;
revoke all on function private.trade_change_token(uuid, uuid, text, text, text, uuid, bigint, jsonb)
  from public, anon, authenticated;
revoke all on function private.trade_change_command_payload(text, uuid, jsonb, uuid, bigint, text, text)
  from public, anon, authenticated;
revoke all on function private.trade_change_reversal_payload(jsonb, uuid) from public, anon, authenticated;
revoke all on function private.trade_change_assert_followups(uuid, uuid, text) from public, anon, authenticated;
revoke all on function private.trade_change_assert_affordable(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.trade_change_assert_final(uuid) from public, anon, authenticated;
revoke all on function private.ledger_trade_reject_inactive_source() from public, anon, authenticated;
revoke all on function private.post_linked_return_core(uuid, uuid, jsonb, uuid, uuid, timestamptz, boolean, boolean)
  from public, anon, authenticated;

revoke all on function public.review_ledger_trade_change_v1(uuid, text, jsonb) from public, anon;
revoke all on function public.post_ledger_trade_change_v1(uuid, uuid, text, jsonb, uuid, bigint, text, text)
  from public, anon;
revoke all on function public.get_daily_ledger_v2() from public, anon;
revoke all on function public.get_daily_ledger_operation(uuid) from public, anon;
revoke all on function public.get_pending_invoice_sends(bigint) from public, anon;
revoke all on function public.get_invoice_brand_source_v1(uuid) from public, anon;
revoke all on function public.get_invoice_message_source_v1(uuid) from public, anon;
revoke all on function public.get_invoice_dispatch_state(uuid) from public, anon;

grant execute on function public.review_ledger_trade_change_v1(uuid, text, jsonb) to authenticated;
grant execute on function public.post_ledger_trade_change_v1(uuid, uuid, text, jsonb, uuid, bigint, text, text)
  to authenticated;
grant execute on function public.get_daily_ledger_v2() to authenticated;
grant execute on function public.get_daily_ledger_operation(uuid) to authenticated;
grant execute on function public.get_pending_invoice_sends(bigint) to authenticated;
grant execute on function public.get_invoice_brand_source_v1(uuid) to authenticated;
grant execute on function public.get_invoice_message_source_v1(uuid) to authenticated;
grant execute on function public.get_invoice_dispatch_state(uuid) to authenticated;

notify pgrst, 'reload schema';

commit;

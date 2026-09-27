-- Opening balances (ADR 0004 working defaults, 2026-09-26).
-- One additive migration. confirm_opening_balances is the only writer.
-- Lock order: shops row FOR UPDATE; financial_command_requests row by primary
-- key when that key exists; opening financial_operations row by id when it
-- exists; existing ledger_accounts for the shop ORDER BY id; then inserts.
-- Quantities are canonical integer strings. Interim sums use numeric and are
-- range-checked before any bigint cast. No cached balance columns.
-- Gold clearing is shared by karat and is the bucket exception. A money journal
-- may mix the four cash methods. Count journals stay on one category and karat.
-- The explicit zero opening inserts no journals and no postings.

create schema if not exists extensions;

create extension if not exists pgcrypto with schema extensions;

create function private.opening_pair_allowed(p_category text, p_karat smallint)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select coalesce(case p_category
    when 'worked_jewelry' then p_karat in (14, 18, 21, 22)
    when 'bullion' then p_karat = 24
    when 'coin' then p_karat = 21
    when 'scrap' then p_karat in (14, 18, 21, 22, 24)
    else false
  end, false);
$fn$;

create function private.opening_parse_amount(p_value text)
returns numeric
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_num numeric;
  v_max constant numeric := 9223372036854775807;
begin
  if p_value is null then
    raise exception 'invalid_input';
  end if;
  if left(p_value, 1) = '-' then
    if p_value ~ '^-?(0|[1-9][0-9]*)$' then
      raise exception 'negative_amount';
    end if;
    raise exception 'invalid_input';
  end if;
  if p_value !~ '^(0|[1-9][0-9]*)$' then
    raise exception 'invalid_input';
  end if;
  -- bigint max is 19 digits. Longer canonical strings overflow numeric itself.
  if char_length(p_value) > 19 then
    raise exception 'overflow';
  end if;
  v_num := p_value::numeric;
  if v_num > v_max then
    raise exception 'overflow';
  end if;
  return v_num;
end;
$fn$;

create function private.opening_checked_bigint(p_value numeric)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  if p_value is null
    or p_value <> trunc(p_value)
    or p_value < 0
    or p_value > 9223372036854775807 then
    raise exception 'overflow';
  end if;
  return p_value::bigint;
end;
$fn$;

create function private.cairo_business_date(p_opened_at timestamptz)
returns date
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select (p_opened_at at time zone 'Africa/Cairo')::date;
$fn$;

create function private.opening_canonical_payload(p_payload jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_max constant numeric := 9223372036854775807;
  v_methods constant text[] := array['cash', 'instant_transfer', 'wallet', 'card'];
  v_cash jsonb;
  v_method text;
  v_text text;
  v_num numeric;
  v_cash_sum numeric := 0;
  v_cash_out jsonb := '{}'::jsonb;
  v_elem jsonb;
  v_category text;
  v_karat_text text;
  v_karat smallint;
  v_mg numeric;
  v_count numeric;
  v_mg_text text;
  v_count_text text;
  v_bucket text;
  v_seen text[] := array[]::text[];
  v_scrap_seen text[] := array[]::text[];
  v_karats smallint[] := array[]::smallint[];
  v_karat_sums numeric[] := array[]::numeric[];
  v_idx integer;
  v_count_sum numeric := 0;
  v_stock jsonb := '[]'::jsonb;
  v_scrap jsonb := '[]'::jsonb;
  v_sorted jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(p_payload) as object_key
    where object_key not in ('version', 'cash', 'stock', 'scrap')
  ) or not (
    p_payload ? 'version' and p_payload ? 'cash' and p_payload ? 'stock' and p_payload ? 'scrap'
  ) then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'version') <> 'number'
    or (p_payload -> 'version')::text ~ '[^0-9]'
    or (p_payload -> 'version') <> '1'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_cash := p_payload -> 'cash';
  if v_cash is null or jsonb_typeof(v_cash) <> 'object' then
    raise exception 'invalid_input';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(v_cash) as object_key
    where object_key <> all (v_methods)
  ) then
    raise exception 'invalid_input';
  end if;
  foreach v_method in array v_methods loop
    if v_cash ? v_method then
      if jsonb_typeof(v_cash -> v_method) is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_text := v_cash ->> v_method;
      v_num := private.opening_parse_amount(v_text);
    else
      v_text := '0';
      v_num := 0;
    end if;
    v_cash_sum := v_cash_sum + v_num;
    if v_cash_sum > v_max then
      raise exception 'overflow';
    end if;
    v_cash_out := v_cash_out || jsonb_build_object(v_method, v_text);
  end loop;

  if jsonb_typeof(p_payload -> 'stock') <> 'array'
    or jsonb_typeof(p_payload -> 'scrap') <> 'array' then
    raise exception 'invalid_input';
  end if;

  for v_elem in
    select value from jsonb_array_elements(p_payload -> 'stock') as element(value)
  loop
    if jsonb_typeof(v_elem) is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
    if exists (
        select 1 from jsonb_object_keys(v_elem) as object_key
        where object_key not in ('category', 'karat', 'milligrams', 'count')
      )
      or not (
        v_elem ? 'category' and v_elem ? 'karat' and v_elem ? 'milligrams' and v_elem ? 'count'
      ) then
      raise exception 'invalid_input';
    end if;
    if jsonb_typeof(v_elem -> 'category') <> 'string'
      or jsonb_typeof(v_elem -> 'milligrams') <> 'string'
      or jsonb_typeof(v_elem -> 'count') <> 'string'
      or jsonb_typeof(v_elem -> 'karat') <> 'number' then
      raise exception 'invalid_input';
    end if;
    v_karat_text := (v_elem -> 'karat')::text;
    if v_karat_text ~ '[^0-9]' then
      raise exception 'invalid_input';
    end if;
    v_num := v_karat_text::numeric;
    if v_num > 32767 then
      raise exception 'invalid_input';
    end if;
    v_karat := v_num::smallint;
    v_category := v_elem ->> 'category';
    if v_category = 'scrap' or not private.opening_pair_allowed(v_category, v_karat) then
      raise exception 'unsupported_category_karat';
    end if;
    v_mg_text := v_elem ->> 'milligrams';
    v_count_text := v_elem ->> 'count';
    v_mg := private.opening_parse_amount(v_mg_text);
    v_count := private.opening_parse_amount(v_count_text);
    if v_mg = 0 or v_count = 0 then
      raise exception 'invalid_input';
    end if;
    v_bucket := v_category || ':' || v_karat::text;
    if v_bucket = any (v_seen) then
      raise exception 'duplicate_bucket';
    end if;
    v_seen := v_seen || v_bucket;
    v_idx := array_position(v_karats, v_karat);
    if v_idx is null then
      v_karats := v_karats || v_karat;
      v_karat_sums := v_karat_sums || v_mg;
    else
      v_karat_sums[v_idx] := v_karat_sums[v_idx] + v_mg;
      if v_karat_sums[v_idx] > v_max then
        raise exception 'overflow';
      end if;
    end if;
    v_count_sum := v_count_sum + v_count;
    if v_count_sum > v_max then
      raise exception 'overflow';
    end if;
    v_stock := v_stock || jsonb_build_array(jsonb_build_object(
      'category', v_category,
      'karat', v_karat,
      'milligrams', v_mg_text,
      'count', v_count_text
    ));
  end loop;

  for v_elem in
    select value from jsonb_array_elements(p_payload -> 'scrap') as element(value)
  loop
    if jsonb_typeof(v_elem) is distinct from 'object' then
      raise exception 'invalid_input';
    end if;
    if exists (
        select 1 from jsonb_object_keys(v_elem) as object_key
        where object_key not in ('karat', 'milligrams')
      )
      or not (v_elem ? 'karat' and v_elem ? 'milligrams') then
      raise exception 'invalid_input';
    end if;
    if jsonb_typeof(v_elem -> 'milligrams') <> 'string'
      or jsonb_typeof(v_elem -> 'karat') <> 'number' then
      raise exception 'invalid_input';
    end if;
    v_karat_text := (v_elem -> 'karat')::text;
    if v_karat_text ~ '[^0-9]' then
      raise exception 'invalid_input';
    end if;
    v_num := v_karat_text::numeric;
    if v_num > 32767 then
      raise exception 'invalid_input';
    end if;
    v_karat := v_num::smallint;
    if not private.opening_pair_allowed('scrap', v_karat) then
      raise exception 'unsupported_category_karat';
    end if;
    v_mg_text := v_elem ->> 'milligrams';
    v_mg := private.opening_parse_amount(v_mg_text);
    if v_mg = 0 then
      raise exception 'invalid_input';
    end if;
    v_bucket := v_karat::text;
    if v_bucket = any (v_scrap_seen) then
      raise exception 'duplicate_bucket';
    end if;
    v_scrap_seen := v_scrap_seen || v_bucket;
    v_idx := array_position(v_karats, v_karat);
    if v_idx is null then
      v_karats := v_karats || v_karat;
      v_karat_sums := v_karat_sums || v_mg;
    else
      v_karat_sums[v_idx] := v_karat_sums[v_idx] + v_mg;
      if v_karat_sums[v_idx] > v_max then
        raise exception 'overflow';
      end if;
    end if;
    v_scrap := v_scrap || jsonb_build_array(jsonb_build_object(
      'karat', v_karat,
      'milligrams', v_mg_text
    ));
  end loop;

  select coalesce(jsonb_agg(element.value order by element.value ->> 'category', (element.value ->> 'karat')::integer), '[]'::jsonb)
    into v_sorted
  from jsonb_array_elements(v_stock) as element(value);
  v_stock := v_sorted;

  select coalesce(jsonb_agg(element.value order by (element.value ->> 'karat')::integer), '[]'::jsonb)
    into v_sorted
  from jsonb_array_elements(v_scrap) as element(value);
  v_scrap := v_sorted;

  return jsonb_build_object(
    'version', 1,
    'cash', v_cash_out,
    'stock', v_stock,
    'scrap', v_scrap
  );
end;
$fn$;

create table public.business_days (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  business_date date not null,
  opened_at timestamptz not null,
  status text not null,
  constraint business_days_shop_id_id_key unique (shop_id, id),
  constraint business_days_status_check check (status = 'open'),
  constraint business_days_date_check check (
    business_date = (opened_at at time zone 'Africa/Cairo')::date
  )
);

create unique index business_days_one_open_idx
  on public.business_days (shop_id)
  where status = 'open';

create table public.financial_operations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  shop_sequence bigint not null,
  kind text not null,
  business_day_id uuid not null,
  actor_user_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint financial_operations_shop_id_id_key unique (shop_id, id),
  constraint financial_operations_sequence_positive check (shop_sequence > 0),
  constraint financial_operations_kind_check check (kind = 'opening_balances'),
  constraint financial_operations_shop_sequence_key unique (shop_id, shop_sequence),
  constraint financial_operations_business_day_fkey
    foreign key (shop_id, business_day_id)
    references public.business_days (shop_id, id),
  constraint financial_operations_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create unique index financial_operations_one_opening_idx
  on public.financial_operations (shop_id)
  where kind = 'opening_balances';

create table public.ledger_accounts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  account_kind text not null,
  unit_kind text not null,
  currency_code text,
  karat smallint,
  category_code text,
  method_code text,
  constraint ledger_accounts_shop_id_id_key unique (shop_id, id),
  constraint ledger_accounts_shape_check check ((
    case account_kind
      when 'cash_method' then
        unit_kind = 'money'
        and currency_code = 'EGP'
        and karat is null
        and category_code is null
        and method_code in ('cash', 'instant_transfer', 'wallet', 'card')
      when 'saleable_metal' then
        unit_kind = 'gold_mg'
        and currency_code is null
        and method_code is null
        and category_code in ('worked_jewelry', 'bullion', 'coin')
        and private.opening_pair_allowed(category_code, karat)
      when 'saleable_count' then
        unit_kind = 'count'
        and currency_code is null
        and method_code is null
        and category_code in ('worked_jewelry', 'bullion', 'coin')
        and private.opening_pair_allowed(category_code, karat)
      when 'scrap_metal' then
        unit_kind = 'gold_mg'
        and currency_code is null
        and method_code is null
        and category_code = 'scrap'
        and private.opening_pair_allowed('scrap', karat)
      when 'opening_money_clearing' then
        unit_kind = 'money'
        and currency_code = 'EGP'
        and karat is null
        and category_code is null
        and method_code is null
      when 'opening_gold_clearing' then
        unit_kind = 'gold_mg'
        and currency_code is null
        and method_code is null
        and category_code is null
        and karat in (14, 18, 21, 22, 24)
      when 'opening_count_clearing' then
        unit_kind = 'count'
        and currency_code is null
        and method_code is null
        and category_code in ('worked_jewelry', 'bullion', 'coin')
        and private.opening_pair_allowed(category_code, karat)
      else false
    end
  ) is true)
);

create unique index ledger_accounts_cash_method_key
  on public.ledger_accounts (shop_id, method_code)
  where account_kind = 'cash_method';

create unique index ledger_accounts_saleable_metal_key
  on public.ledger_accounts (shop_id, category_code, karat)
  where account_kind = 'saleable_metal';

create unique index ledger_accounts_saleable_count_key
  on public.ledger_accounts (shop_id, category_code, karat)
  where account_kind = 'saleable_count';

create unique index ledger_accounts_scrap_key
  on public.ledger_accounts (shop_id, karat)
  where account_kind = 'scrap_metal';

create unique index ledger_accounts_money_clearing_key
  on public.ledger_accounts (shop_id)
  where account_kind = 'opening_money_clearing';

create unique index ledger_accounts_gold_clearing_key
  on public.ledger_accounts (shop_id, karat)
  where account_kind = 'opening_gold_clearing';

create unique index ledger_accounts_count_clearing_key
  on public.ledger_accounts (shop_id, category_code, karat)
  where account_kind = 'opening_count_clearing';

create table public.journals (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  operation_id uuid not null,
  unit_kind text not null,
  currency_code text,
  karat smallint,
  bucket_key text not null,
  constraint journals_shop_id_id_key unique (shop_id, id),
  constraint journals_shop_id_id_operation_id_key unique (shop_id, id, operation_id),
  constraint journals_shape_check check ((
    (
      unit_kind = 'money'
      and currency_code = 'EGP'
      and karat is null
      and bucket_key = 'money'
    )
    or (
      unit_kind = 'gold_mg'
      and currency_code is null
      and karat in (14, 18, 21, 22, 24)
      and private.opening_pair_allowed(split_part(bucket_key, ':', 2), karat)
      and bucket_key = 'gold:' || split_part(bucket_key, ':', 2) || ':' || karat::text
    )
    or (
      unit_kind = 'count'
      and currency_code is null
      and karat in (14, 18, 21, 22, 24)
      and split_part(bucket_key, ':', 2) in ('worked_jewelry', 'bullion', 'coin')
      and private.opening_pair_allowed(split_part(bucket_key, ':', 2), karat)
      and bucket_key = 'count:' || split_part(bucket_key, ':', 2) || ':' || karat::text
    )
  ) is true),
  constraint journals_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);

create table public.journal_postings (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  journal_id uuid not null,
  account_id uuid not null,
  operation_id uuid not null,
  amount bigint not null,
  constraint journal_postings_amount_nonzero check (amount <> 0),
  constraint journal_postings_journal_fkey
    foreign key (shop_id, journal_id)
    references public.journals (shop_id, id),
  constraint journal_postings_account_fkey
    foreign key (shop_id, account_id)
    references public.ledger_accounts (shop_id, id),
  constraint journal_postings_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  -- Durable guarantee that a posting belongs to its journal's operation.
  constraint journal_postings_journal_operation_fkey
    foreign key (shop_id, journal_id, operation_id)
    references public.journals (shop_id, id, operation_id)
);

create table public.financial_command_requests (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  idempotency_key uuid not null,
  payload_canonical jsonb not null,
  payload_sha256 bytea not null,
  operation_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  constraint financial_command_requests_shop_key unique (shop_id, idempotency_key),
  constraint financial_command_requests_hash_len check (octet_length(payload_sha256) = 32),
  constraint financial_command_requests_payload_object check (jsonb_typeof(payload_canonical) = 'object'),
  constraint financial_command_requests_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);

create table public.financial_audit_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  actor_user_id uuid not null,
  action text not null,
  operation_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  details jsonb not null,
  constraint financial_audit_events_action_check check (action = 'opening_balances_confirmed'),
  constraint financial_audit_events_details_object check (jsonb_typeof(details) = 'object'),
  constraint financial_audit_events_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint financial_audit_events_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create table public.financial_outbox (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  operation_id uuid not null,
  event_type text not null,
  created_at timestamptz not null default clock_timestamp(),
  delivered_at timestamptz,
  constraint financial_outbox_event_check check (event_type = 'opening_balances_confirmed'),
  constraint financial_outbox_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);

create view public.ledger_account_balances
with (security_invoker = true) as
select
  account.shop_id,
  account.id as account_id,
  account.account_kind,
  account.unit_kind,
  account.currency_code,
  account.karat,
  account.category_code,
  account.method_code,
  coalesce(sum(posting.amount), 0)::bigint as amount
from public.ledger_accounts as account
left join public.journal_postings as posting
  on posting.shop_id = account.shop_id
 and posting.account_id = account.id
group by
  account.shop_id,
  account.id,
  account.account_kind,
  account.unit_kind,
  account.currency_code,
  account.karat,
  account.category_code,
  account.method_code;

comment on view public.ledger_account_balances is
  'Synchronous security_invoker sum of journal postings. No cached balance column.';

create function private.enforce_journal_conservation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_journal uuid;
  v_shop uuid;
  v_unit text;
  v_currency text;
  v_karat smallint;
  v_bucket text;
  v_count integer;
  v_sum numeric;
  v_account public.ledger_accounts%rowtype;
  v_posting record;
begin
  if tg_table_name = 'journals' then
    v_journal := coalesce(new.id, old.id);
  else
    v_journal := coalesce(new.journal_id, old.journal_id);
  end if;
  select journal.shop_id, journal.unit_kind, journal.currency_code, journal.karat, journal.bucket_key
    into v_shop, v_unit, v_currency, v_karat, v_bucket
  from public.journals as journal
  where journal.id = v_journal;
  if not found then
    return null;
  end if;
  select count(*)::integer, coalesce(sum(posting.amount), 0)
    into v_count, v_sum
  from public.journal_postings as posting
  where posting.journal_id = v_journal;
  if v_count < 2 or v_sum <> 0 then
    raise exception 'journal_imbalance';
  end if;
  for v_posting in
    select posting.account_id, posting.shop_id
    from public.journal_postings as posting
    where posting.journal_id = v_journal
  loop
    if v_posting.shop_id is distinct from v_shop then
      raise exception 'journal_imbalance';
    end if;
    select * into v_account
    from public.ledger_accounts as account
    where account.id = v_posting.account_id;
    if v_account.unit_kind is distinct from v_unit
      or v_account.currency_code is distinct from v_currency
      or v_account.karat is distinct from v_karat
      or v_account.shop_id is distinct from v_shop then
      raise exception 'journal_imbalance';
    end if;
    if v_unit = 'money' then
      if v_bucket <> 'money'
        or v_account.account_kind not in ('cash_method', 'opening_money_clearing') then
        raise exception 'journal_imbalance';
      end if;
    elsif v_unit = 'gold_mg' then
      if v_account.account_kind = 'opening_gold_clearing' then
        null;
      elsif v_account.account_kind in ('saleable_metal', 'scrap_metal') then
        if v_bucket is distinct from ('gold:' || v_account.category_code || ':' || v_account.karat::text) then
          raise exception 'journal_imbalance';
        end if;
      else
        raise exception 'journal_imbalance';
      end if;
    elsif v_unit = 'count' then
      if v_account.account_kind in ('saleable_count', 'opening_count_clearing') then
        if v_bucket is distinct from ('count:' || v_account.category_code || ':' || v_account.karat::text) then
          raise exception 'journal_imbalance';
        end if;
      else
        raise exception 'journal_imbalance';
      end if;
    else
      raise exception 'journal_imbalance';
    end if;
  end loop;
  return null;
end;
$fn$;

create constraint trigger journal_postings_conservation_trg
after insert or update or delete on public.journal_postings
deferrable initially deferred
for each row
execute function private.enforce_journal_conservation();

create constraint trigger journals_conservation_trg
after insert or update on public.journals
deferrable initially deferred
for each row
execute function private.enforce_journal_conservation();

create function private.enforce_nonnegative_owned_balances()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := coalesce(new.shop_id, old.shop_id);
begin
  if exists (
    select 1
    from public.ledger_accounts as account
    join public.journal_postings as posting
      on posting.shop_id = account.shop_id
     and posting.account_id = account.id
    where account.shop_id = v_shop
      and account.account_kind in ('cash_method', 'saleable_metal', 'saleable_count', 'scrap_metal')
    group by account.id
    having sum(posting.amount) < 0
  ) then
    raise exception 'negative_owned_balance';
  end if;
  return null;
end;
$fn$;

create constraint trigger journal_postings_nonnegative_trg
after insert or update or delete on public.journal_postings
deferrable initially deferred
for each row
execute function private.enforce_nonnegative_owned_balances();

create function private.financial_audit_events_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  raise exception 'audit_append_only';
end;
$fn$;

create trigger financial_audit_events_append_only
before update or delete on public.financial_audit_events
for each row
execute function private.financial_audit_events_append_only();

alter table public.business_days enable row level security;
alter table public.financial_operations enable row level security;
alter table public.ledger_accounts enable row level security;
alter table public.journals enable row level security;
alter table public.journal_postings enable row level security;
alter table public.financial_command_requests enable row level security;
alter table public.financial_audit_events enable row level security;
alter table public.financial_outbox enable row level security;

revoke all on table public.business_days from public, anon, authenticated;
revoke all on table public.financial_operations from public, anon, authenticated;
revoke all on table public.ledger_accounts from public, anon, authenticated;
revoke all on table public.journals from public, anon, authenticated;
revoke all on table public.journal_postings from public, anon, authenticated;
revoke all on table public.financial_command_requests from public, anon, authenticated;
revoke all on table public.financial_audit_events from public, anon, authenticated;
revoke all on table public.financial_outbox from public, anon, authenticated;
revoke all on table public.ledger_account_balances from public, anon, authenticated;

grant select on table public.business_days to authenticated;
grant select on table public.financial_operations to authenticated;
grant select on table public.ledger_accounts to authenticated;
grant select on table public.journals to authenticated;
grant select on table public.journal_postings to authenticated;
grant select on table public.financial_command_requests to authenticated;
grant select on table public.financial_audit_events to authenticated;
grant select on table public.financial_outbox to authenticated;
grant select on table public.ledger_account_balances to authenticated;

do $audit_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.financial_audit_events from service_role';
  end if;
end;
$audit_revoke$;

create function private.opening_financial_visible(p_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select private.is_active_shop_member(p_shop_id)
    and exists (
      select 1
      from public.shop_entitlements as entitlement
      where entitlement.shop_id = p_shop_id
        and entitlement.starts_at <= pg_catalog.now()
    );
$fn$;

create function private.opening_require_reader_shop()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_user uuid := auth.uid();
  v_shop uuid;
begin
  if v_user is null then
    raise exception 'unauthenticated';
  end if;
  if not private.caller_session_accepted() then
    raise exception 'session_expired';
  end if;
  if not exists (
    select 1
    from auth.users as identity
    where identity.id = v_user
      and coalesce(identity.is_anonymous, false) = false
      and identity.deleted_at is null
  ) then
    raise exception 'forbidden';
  end if;
  select ownership.shop_id
    into v_shop
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop is null then
    raise exception 'forbidden';
  end if;
  if not private.is_active_shop_member(v_shop)
    or not exists (
      select 1
      from public.shop_entitlements as entitlement
      where entitlement.shop_id = v_shop
        and entitlement.starts_at <= pg_catalog.now()
    ) then
    raise exception 'shop_unavailable';
  end if;
  return v_shop;
end;
$fn$;

create policy business_days_select_opening
on public.business_days
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy financial_operations_select_opening
on public.financial_operations
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy ledger_accounts_select_opening
on public.ledger_accounts
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy journals_select_opening
on public.journals
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy journal_postings_select_opening
on public.journal_postings
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy financial_command_requests_select_opening
on public.financial_command_requests
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy financial_audit_events_select_opening
on public.financial_audit_events
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create policy financial_outbox_select_opening
on public.financial_outbox
for select
to authenticated
using (private.opening_financial_visible(shop_id));

create function public.confirm_opening_balances(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_recheck uuid;
  v_zone text;
  v_canonical jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_existing_op uuid;
  v_at timestamptz;
  v_date date;
  v_day uuid;
  v_op uuid;
  v_actor uuid;
  v_elem jsonb;
  v_method text;
  v_num numeric;
  v_cash_sum numeric := 0;
  v_amount bigint;
  v_journal uuid;
  v_account uuid;
  v_clear uuid;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_bucket text;
  v_replay_day uuid;
  v_replay_date date;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  -- Lock the shop before any command, account, or payload comparison that writes.
  perform 1
  from public.shops as shop
  where shop.id = v_shop
  for update;
  v_recheck := private.opening_require_reader_shop();
  if v_recheck is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select shop.time_zone
    into v_zone
  from public.shops as shop
  where shop.id = v_shop;
  if v_zone is distinct from 'Africa/Cairo' then
    raise exception 'invalid_input';
  end if;
  v_canonical := private.opening_canonical_payload(p_payload);
  v_hash := extensions.digest(convert_to(v_canonical::text, 'UTF8'), 'sha256');
  select request.*
    into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = v_canonical
      and v_request.payload_sha256 = v_hash then
      select operation.business_day_id
        into v_replay_day
      from public.financial_operations as operation
      where operation.id = v_request.operation_id
        and operation.shop_id = v_shop;
      select day.business_date
        into v_replay_date
      from public.business_days as day
      where day.id = v_replay_day
        and day.shop_id = v_shop;
      return jsonb_build_object(
        'ok', true,
        'operation_id', v_request.operation_id,
        'business_day_id', v_replay_day,
        'business_date', to_char(v_replay_date, 'YYYY-MM-DD'),
        'replayed', true
      );
    end if;
    raise exception 'payload_mismatch';
  end if;
  select operation.id
    into v_existing_op
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.kind = 'opening_balances'
  order by operation.id
  for update;
  if v_existing_op is not null then
    raise exception 'opening_already_confirmed';
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  perform 1
  from public.ledger_accounts as account
  where account.shop_id = v_shop
  order by account.id
  for update;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  v_date := private.cairo_business_date(v_at);
  insert into public.business_days (shop_id, business_date, opened_at, status)
  values (v_shop, v_date, v_at, 'open')
  returning id into v_day;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    v_shop, 1, 'opening_balances', v_day, v_actor, v_at
  ) returning id into v_op;

  foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code, method_code
    ) values (
      v_shop, 'cash_method', 'money', 'EGP', v_method
    );
    v_num := private.opening_parse_amount(v_canonical #>> array['cash', v_method]);
    v_cash_sum := v_cash_sum + v_num;
  end loop;
  if v_cash_sum > 0 then
    perform private.opening_checked_bigint(v_cash_sum);
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code
    ) values (
      v_shop, 'opening_money_clearing', 'money', 'EGP'
    ) returning id into v_clear;
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'money', 'EGP', null, 'money'
    ) returning id into v_journal;
    foreach v_method in array array['cash', 'instant_transfer', 'wallet', 'card'] loop
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_canonical #>> array['cash', v_method])
      );
      if v_amount > 0 then
        select account.id into v_account
        from public.ledger_accounts as account
        where account.shop_id = v_shop
          and account.account_kind = 'cash_method'
          and account.method_code = v_method;
        insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
        values (v_shop, v_journal, v_account, v_op, v_amount);
      end if;
    end loop;
    insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
    values (v_shop, v_journal, v_clear, v_op, -private.opening_checked_bigint(v_cash_sum));
  end if;

  for v_elem in
    select value from jsonb_array_elements(v_canonical -> 'stock') as element(value)
  loop
    v_category := v_elem ->> 'category';
    v_karat := (v_elem ->> 'karat')::smallint;
    v_mg := private.opening_checked_bigint(private.opening_parse_amount(v_elem ->> 'milligrams'));
    v_count := private.opening_checked_bigint(private.opening_parse_amount(v_elem ->> 'count'));
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, karat, category_code
    ) values (
      v_shop, 'saleable_metal', 'gold_mg', v_karat, v_category
    ) returning id into v_account;
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, karat, category_code
    ) values (
      v_shop, 'saleable_count', 'count', v_karat, v_category
    );
    v_clear := null;
    select account.id into v_clear
    from public.ledger_accounts as account
    where account.shop_id = v_shop
      and account.account_kind = 'opening_gold_clearing'
      and account.karat = v_karat;
    if v_clear is null then
      insert into public.ledger_accounts (
        shop_id, account_kind, unit_kind, karat
      ) values (
        v_shop, 'opening_gold_clearing', 'gold_mg', v_karat
      ) returning id into v_clear;
    end if;
    v_bucket := 'gold:' || v_category || ':' || v_karat::text;
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'gold_mg', null, v_karat, v_bucket
    ) returning id into v_journal;
    insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
    values
      (v_shop, v_journal, v_account, v_op, v_mg),
      (v_shop, v_journal, v_clear, v_op, -v_mg);
    select account.id into v_account
    from public.ledger_accounts as account
    where account.shop_id = v_shop
      and account.account_kind = 'saleable_count'
      and account.category_code = v_category
      and account.karat = v_karat;
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, karat, category_code
    ) values (
      v_shop, 'opening_count_clearing', 'count', v_karat, v_category
    ) returning id into v_clear;
    v_bucket := 'count:' || v_category || ':' || v_karat::text;
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'count', null, v_karat, v_bucket
    ) returning id into v_journal;
    insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
    values
      (v_shop, v_journal, v_account, v_op, v_count),
      (v_shop, v_journal, v_clear, v_op, -v_count);
  end loop;

  for v_elem in
    select value from jsonb_array_elements(v_canonical -> 'scrap') as element(value)
  loop
    v_karat := (v_elem ->> 'karat')::smallint;
    v_mg := private.opening_checked_bigint(private.opening_parse_amount(v_elem ->> 'milligrams'));
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, karat, category_code
    ) values (
      v_shop, 'scrap_metal', 'gold_mg', v_karat, 'scrap'
    ) returning id into v_account;
    v_clear := null;
    select account.id into v_clear
    from public.ledger_accounts as account
    where account.shop_id = v_shop
      and account.account_kind = 'opening_gold_clearing'
      and account.karat = v_karat;
    if v_clear is null then
      insert into public.ledger_accounts (
        shop_id, account_kind, unit_kind, karat
      ) values (
        v_shop, 'opening_gold_clearing', 'gold_mg', v_karat
      ) returning id into v_clear;
    end if;
    v_bucket := 'gold:scrap:' || v_karat::text;
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'gold_mg', null, v_karat, v_bucket
    ) returning id into v_journal;
    insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
    values
      (v_shop, v_journal, v_account, v_op, v_mg),
      (v_shop, v_journal, v_clear, v_op, -v_mg);
  end loop;

  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop,
    v_actor,
    'opening_balances_confirmed',
    v_op,
    v_at,
    jsonb_build_object(
      'business_date', to_char(v_date, 'YYYY-MM-DD'),
      'operation_id', v_op
    )
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at, delivered_at
  ) values (
    v_shop, v_op, 'opening_balances_confirmed', v_at, null
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (
    v_shop, p_idempotency_key, v_canonical, v_hash, v_op, v_at
  );
  return jsonb_build_object(
    'ok', true,
    'operation_id', v_op,
    'business_day_id', v_day,
    'business_date', to_char(v_date, 'YYYY-MM-DD'),
    'replayed', false
  );
end;
$fn$;

create function public.get_opening_status(p_idempotency_key uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_operation uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select request.operation_id
    into v_operation
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key;
  if v_operation is null then
    return jsonb_build_object('status', 'absent');
  end if;
  return jsonb_build_object('status', 'completed', 'operation_id', v_operation);
end;
$fn$;

create function public.get_daily_ledger()
returns jsonb
language plpgsql
volatile
security invoker
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_status text;
  v_operation uuid;
  v_can_confirm boolean;
  v_name text;
  v_day jsonb;
  v_cash jsonb;
  v_stock jsonb;
  v_scrap jsonb;
  v_feed jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  v_shop := private.opening_require_reader_shop();
  select case
    when entitlement.starts_at <= pg_catalog.now()
      and pg_catalog.now() < entitlement.expires_at then 'active'
    else 'expired'
  end
    into v_status
  from public.shop_entitlements as entitlement
  where entitlement.shop_id = v_shop;
  select operation.id
    into v_operation
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.kind = 'opening_balances';
  v_can_confirm := private.can_write_shop(v_shop) and v_operation is null;
  if v_operation is null then
    return jsonb_build_object(
      'read_model_version', 1,
      'state', 'uninitialized',
      'entitlement_status', v_status,
      'can_confirm', v_can_confirm,
      'business_day', null,
      'cash', '[]'::jsonb,
      'stock', '[]'::jsonb,
      'scrap', '[]'::jsonb,
      'feed', '[]'::jsonb
    );
  end if;
  select shop.owner_display_name
    into v_name
  from public.shops as shop
  where shop.id = v_shop;
  select jsonb_build_object(
    'id', day.id,
    'business_date', to_char(day.business_date, 'YYYY-MM-DD'),
    'opened_at', pg_catalog.to_jsonb(day.opened_at)
  )
    into v_day
  from public.business_days as day
  join public.financial_operations as operation
    on operation.shop_id = day.shop_id
   and operation.business_day_id = day.id
  where operation.id = v_operation;
  select coalesce(jsonb_agg(row_value order by row_ord), '[]'::jsonb)
    into v_cash
  from (
    select jsonb_build_object(
      'method', method.method_code,
      'label_ar', method.label_ar,
      'piastres', coalesce(balance.amount, 0)::text,
      'pounds',
        ((coalesce(balance.amount, 0) / 100)::text || '.'
          || lpad((coalesce(balance.amount, 0) % 100)::text, 2, '0'))
    ) as row_value,
    method.row_ord
    from (
      values
        ('cash', 'نقدي', 1),
        ('instant_transfer', 'انستا', 2),
        ('wallet', 'محفظة', 3),
        ('card', 'فيزا', 4)
    ) as method(method_code, label_ar, row_ord)
    left join public.ledger_account_balances as balance
      on balance.shop_id = v_shop
     and balance.account_kind = 'cash_method'
     and balance.method_code = method.method_code
  ) as cash_rows;
  select coalesce(jsonb_agg(row_value order by category_code, karat), '[]'::jsonb)
    into v_stock
  from (
    select jsonb_build_object(
      'category', metal.category_code,
      'label_ar', case metal.category_code
        when 'worked_jewelry' then 'مشغولات'
        when 'bullion' then 'سبائك'
        when 'coin' then 'جنيهات'
      end,
      'karat', metal.karat,
      'milligrams', metal.amount::text,
      'grams',
        ((metal.amount / 1000)::text || '.'
          || lpad((metal.amount % 1000)::text, 3, '0')),
      'count', coalesce(piece.amount, 0)::text
    ) as row_value,
    metal.category_code,
    metal.karat
    from public.ledger_account_balances as metal
    left join public.ledger_account_balances as piece
      on piece.shop_id = metal.shop_id
     and piece.account_kind = 'saleable_count'
     and piece.category_code = metal.category_code
     and piece.karat = metal.karat
    where metal.shop_id = v_shop
      and metal.account_kind = 'saleable_metal'
  ) as stock_rows;
  select coalesce(jsonb_agg(row_value order by karat), '[]'::jsonb)
    into v_scrap
  from (
    select jsonb_build_object(
      'karat', scrap.karat,
      'label_ar', 'كسر',
      'milligrams', scrap.amount::text,
      'grams',
        ((scrap.amount / 1000)::text || '.'
          || lpad((scrap.amount % 1000)::text, 3, '0'))
    ) as row_value,
    scrap.karat
    from public.ledger_account_balances as scrap
    where scrap.shop_id = v_shop
      and scrap.account_kind = 'scrap_metal'
  ) as scrap_rows;
  select coalesce(jsonb_agg(row_value), '[]'::jsonb)
    into v_feed
  from (
    select jsonb_build_object(
      'kind', 'opening_balances_confirmed',
      'label_ar', 'رصيد افتتاحي',
      'operation_id', audit_event.operation_id,
      'actor_display_name', coalesce(v_name, ''),
      'occurred_at', pg_catalog.to_jsonb(audit_event.created_at),
      'occurred_at_cairo', to_char(
        audit_event.created_at at time zone 'Africa/Cairo',
        'YYYY-MM-DD"T"HH24:MI:SS'
      )
    ) as row_value
    from public.financial_audit_events as audit_event
    where audit_event.shop_id = v_shop
      and audit_event.action = 'opening_balances_confirmed'
    order by audit_event.created_at
    limit 1
  ) as feed_rows;
  return jsonb_build_object(
    'read_model_version', 1,
    'state', 'confirmed',
    'entitlement_status', v_status,
    'can_confirm', false,
    'business_day', v_day,
    'cash', v_cash,
    'stock', v_stock,
    'scrap', v_scrap,
    'feed', v_feed
  );
end;
$fn$;

revoke all on function private.opening_pair_allowed(text, smallint) from public, anon, authenticated;
revoke all on function private.opening_parse_amount(text) from public, anon, authenticated;
revoke all on function private.opening_checked_bigint(numeric) from public, anon, authenticated;
revoke all on function private.cairo_business_date(timestamptz) from public, anon, authenticated;
revoke all on function private.opening_canonical_payload(jsonb) from public, anon, authenticated;
revoke all on function private.enforce_journal_conservation() from public, anon, authenticated;
revoke all on function private.enforce_nonnegative_owned_balances() from public, anon, authenticated;
revoke all on function private.financial_audit_events_append_only() from public, anon, authenticated;
revoke all on function private.opening_financial_visible(uuid) from public, anon;
revoke all on function private.opening_require_reader_shop() from public, anon;
revoke all on function public.confirm_opening_balances(uuid, jsonb) from public, anon;
revoke all on function public.get_opening_status(uuid) from public, anon;
revoke all on function public.get_daily_ledger() from public, anon;

grant execute on function private.opening_financial_visible(uuid) to authenticated;
grant execute on function private.opening_require_reader_shop() to authenticated;
grant execute on function public.confirm_opening_balances(uuid, jsonb) to authenticated;
grant execute on function public.get_opening_status(uuid) to authenticated;
grant execute on function public.get_daily_ledger() to authenticated;

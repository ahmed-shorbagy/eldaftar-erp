-- Applied to the connected project on 2026-09-29 through the Supabase connector.
begin;

alter table public.business_days drop constraint business_days_status_check;
alter table public.business_days add column closed_at timestamptz;
alter table public.business_days add column day_version bigint not null default 1;
alter table public.business_days add constraint business_days_status_check
  check ((status = 'open' and closed_at is null)
    or (status = 'closed' and closed_at is not null));
alter table public.business_days add constraint business_days_version_positive
  check (day_version > 0);

alter table public.financial_operations drop constraint financial_operations_kind_check;
alter table public.financial_operations add constraint financial_operations_kind_check
  check (kind in ('opening_balances', 'sale', 'purchase', 'expense',
    'close_day', 'open_day'));

alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened'));

alter table public.financial_outbox drop constraint financial_outbox_event_check;
alter table public.financial_outbox add constraint financial_outbox_event_check
  check (event_type in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened'));

alter table public.ledger_accounts drop constraint ledger_accounts_shape_check;
alter table public.ledger_accounts add constraint ledger_accounts_shape_check check ((
  case account_kind
    when 'cash_method' then unit_kind = 'money' and currency_code = 'EGP'
      and karat is null and category_code is null
      and method_code in ('cash', 'instant_transfer', 'wallet', 'card')
    when 'saleable_metal' then unit_kind = 'gold_mg' and currency_code is null
      and method_code is null and private.opening_pair_allowed(category_code, karat)
      and category_code in ('worked_jewelry', 'bullion', 'coin')
    when 'saleable_count' then unit_kind = 'count' and currency_code is null
      and method_code is null and private.opening_pair_allowed(category_code, karat)
      and category_code in ('worked_jewelry', 'bullion', 'coin')
    when 'scrap_metal' then unit_kind = 'gold_mg' and currency_code is null
      and method_code is null and category_code = 'scrap'
      and private.opening_pair_allowed('scrap', karat)
    when 'opening_money_clearing' then unit_kind = 'money'
      and currency_code = 'EGP' and karat is null
      and category_code is null and method_code is null
    when 'movement_money_clearing' then unit_kind = 'money'
      and currency_code = 'EGP' and karat is null
      and category_code is null and method_code is null
    when 'opening_gold_clearing' then unit_kind = 'gold_mg'
      and currency_code is null and category_code is null
      and method_code is null and karat in (14, 18, 21, 22, 24)
    when 'movement_gold_clearing' then unit_kind = 'gold_mg'
      and currency_code is null and category_code is null
      and method_code is null and karat in (14, 18, 21, 22, 24)
    when 'opening_count_clearing' then unit_kind = 'count'
      and currency_code is null and method_code is null
      and category_code in ('worked_jewelry', 'bullion', 'coin')
      and private.opening_pair_allowed(category_code, karat)
    when 'movement_count_clearing' then unit_kind = 'count'
      and currency_code is null and method_code is null
      and category_code in ('worked_jewelry', 'bullion', 'coin')
      and private.opening_pair_allowed(category_code, karat)
    else false
  end
) is true);

create unique index ledger_accounts_movement_money_key
  on public.ledger_accounts (shop_id)
  where account_kind = 'movement_money_clearing';
create unique index ledger_accounts_movement_gold_key
  on public.ledger_accounts (shop_id, karat)
  where account_kind = 'movement_gold_clearing';
create unique index ledger_accounts_movement_count_key
  on public.ledger_accounts (shop_id, category_code, karat)
  where account_kind = 'movement_count_clearing';

create table public.financial_operation_details (
  operation_id uuid primary key,
  shop_id uuid not null,
  payload jsonb not null,
  created_at timestamptz not null,
  constraint financial_operation_details_payload_object
    check (jsonb_typeof(payload) = 'object'),
  constraint financial_operation_details_operation_fk
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);
create index financial_operation_details_shop_idx
  on public.financial_operation_details (shop_id, created_at desc);
alter table public.financial_operation_details enable row level security;
create policy financial_operation_details_owner_read
  on public.financial_operation_details for select to authenticated
  using (private.opening_financial_visible(shop_id));
revoke all on public.financial_operation_details from public, anon, authenticated;
grant select on public.financial_operation_details to authenticated;
create trigger financial_operation_details_append_only
before update or delete on public.financial_operation_details
for each row execute function private.financial_audit_events_append_only();
do $details_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.financial_operation_details from service_role';
  end if;
end;
$details_revoke$;

create table public.purchase_cash_payables (
  operation_id uuid primary key,
  shop_id uuid not null,
  seller_name text not null,
  initial_piastres bigint not null check (initial_piastres > 0),
  remaining_piastres bigint not null check (
    remaining_piastres >= 0 and remaining_piastres <= initial_piastres
  ),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  constraint purchase_cash_payables_seller_nonblank
    check (nullif(btrim(seller_name), '') is not null),
  constraint purchase_cash_payables_operation_fk
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);
create index purchase_cash_payables_shop_idx
  on public.purchase_cash_payables (shop_id, updated_at desc);
alter table public.purchase_cash_payables enable row level security;
create policy purchase_cash_payables_owner_read
  on public.purchase_cash_payables for select to authenticated
  using (private.opening_financial_visible(shop_id));
revoke all on public.purchase_cash_payables from public, anon, authenticated;
grant select on public.purchase_cash_payables to authenticated;

create or replace function private.enforce_journal_conservation()
returns trigger language plpgsql security definer set search_path = '' as $fn$
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
  select journal.shop_id, journal.unit_kind, journal.currency_code,
    journal.karat, journal.bucket_key
    into v_shop, v_unit, v_currency, v_karat, v_bucket
  from public.journals as journal where journal.id = v_journal;
  if not found then return null; end if;
  select count(*)::integer, coalesce(sum(posting.amount), 0)
    into v_count, v_sum
  from public.journal_postings as posting where posting.journal_id = v_journal;
  if v_count < 2 or v_sum <> 0 then raise exception 'journal_imbalance'; end if;
  for v_posting in
    select posting.account_id, posting.shop_id
    from public.journal_postings as posting where posting.journal_id = v_journal
  loop
    if v_posting.shop_id is distinct from v_shop then
      raise exception 'journal_imbalance';
    end if;
    select * into v_account from public.ledger_accounts as account
    where account.id = v_posting.account_id;
    if v_account.unit_kind is distinct from v_unit
      or v_account.currency_code is distinct from v_currency
      or v_account.karat is distinct from v_karat
      or v_account.shop_id is distinct from v_shop then
      raise exception 'journal_imbalance';
    end if;
    if v_unit = 'money' then
      if v_bucket <> 'money' or v_account.account_kind not in
        ('cash_method', 'opening_money_clearing', 'movement_money_clearing') then
        raise exception 'journal_imbalance';
      end if;
    elsif v_unit = 'gold_mg' then
      if v_account.account_kind in ('opening_gold_clearing', 'movement_gold_clearing') then
        null;
      elsif v_account.account_kind in ('saleable_metal', 'scrap_metal') then
        if v_bucket is distinct from
          ('gold:' || v_account.category_code || ':' || v_account.karat::text) then
          raise exception 'journal_imbalance';
        end if;
      else
        raise exception 'journal_imbalance';
      end if;
    elsif v_unit = 'count' then
      if v_account.account_kind in
        ('saleable_count', 'opening_count_clearing', 'movement_count_clearing') then
        if v_bucket is distinct from
          ('count:' || v_account.category_code || ':' || v_account.karat::text) then
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

create or replace function private.enforce_nonnegative_owned_balances()
returns trigger language plpgsql security definer set search_path = '' as $fn$
declare v_shop uuid := coalesce(new.shop_id, old.shop_id);
begin
  if exists (
    select 1 from public.ledger_accounts as account
    join public.journal_postings as posting
      on posting.shop_id = account.shop_id and posting.account_id = account.id
    where account.shop_id = v_shop
    group by account.id
    having sum(posting.amount) not between
      -9223372036854775808::numeric and 9223372036854775807::numeric
  ) then
    raise exception 'overflow';
  end if;
  if exists (
    select 1 from public.ledger_accounts as account
    join public.journal_postings as posting
      on posting.shop_id = account.shop_id and posting.account_id = account.id
    where account.shop_id = v_shop and account.account_kind in
      ('cash_method', 'saleable_metal', 'saleable_count', 'scrap_metal')
    group by account.id having sum(posting.amount) < 0
  ) then
    raise exception 'negative_owned_balance';
  end if;
  if exists (
    select 1 from (
      select account.category_code, account.karat,
        coalesce(sum(posting.amount) filter
          (where account.account_kind = 'saleable_metal'), 0) as milligrams,
        coalesce(sum(posting.amount) filter
          (where account.account_kind = 'saleable_count'), 0) as pieces
      from public.ledger_accounts as account
      left join public.journal_postings as posting
        on posting.shop_id = account.shop_id and posting.account_id = account.id
      where account.shop_id = v_shop and account.account_kind in
        ('saleable_metal', 'saleable_count')
      group by account.category_code, account.karat
    ) as pair
    where (pair.milligrams = 0) <> (pair.pieces = 0)
  ) then
    raise exception 'stock_pair_mismatch';
  end if;
  return null;
end;
$fn$;

create function private.financial_account(
  p_shop uuid, p_kind text, p_unit text, p_category text,
  p_karat smallint, p_method text, p_create boolean
)
returns uuid language plpgsql security definer set search_path = '' as $fn$
declare v_id uuid;
begin
  select account.id into v_id from public.ledger_accounts as account
  where account.shop_id = p_shop and account.account_kind = p_kind
    and account.unit_kind = p_unit
    and account.category_code is not distinct from p_category
    and account.karat is not distinct from p_karat
    and account.method_code is not distinct from p_method;
  if v_id is null and p_create then
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code,
      category_code, karat, method_code
    ) values (
      p_shop, p_kind, p_unit,
      case when p_unit = 'money' then 'EGP' else null end,
      p_category, p_karat, p_method
    ) returning id into v_id;
  end if;
  return v_id;
end;
$fn$;

create function public.post_daily_ledger_trade(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_day uuid;
  v_day_version bigint;
  v_kind text;
  v_actor uuid;
  v_at timestamptz;
  v_sequence bigint;
  v_op uuid;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
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
  v_money_journal uuid;
  v_clear uuid;
  v_account uuid;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_gold_journal uuid;
  v_count_journal uuid;
  v_sign integer;
  v_action text;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_payload is null
    or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical = p_payload and v_request.payload_sha256 = v_hash then
      return jsonb_build_object('ok', true, 'operation_id', v_request.operation_id,
        'replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if p_payload -> 'version' is distinct from '1'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_kind := p_payload ->> 'kind';
  if v_kind is null or v_kind not in ('sale', 'purchase', 'expense')
    or not (p_payload ?& array[
      'version', 'kind', 'total_piastres', 'tenders', 'items',
      'description', 'customer_name', 'customer_phone', 'note'
    ])
    or p_payload - 'version' - 'kind' - 'total_piastres' - 'tenders'
      - 'items' - 'description' - 'customer_name' - 'customer_phone' - 'note'
      - 'purchase_obligation_piastres'
      <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'tenders') not between
      (case when v_kind = 'purchase' then 0 else 1 end) and 4
    or jsonb_typeof(p_payload -> 'items') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'items') > 50 then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'total_piastres') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'description') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'customer_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'customer_phone') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'note') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  if coalesce(length(p_payload ->> 'note'), 0) > 1000
    or coalesce(length(p_payload ->> 'customer_name'), 0) > 200
    or coalesce(length(p_payload ->> 'customer_phone'), 0) > 20
    or coalesce(length(p_payload ->> 'description'), 0) > 300 then
    raise exception 'invalid_input';
  end if;
  if coalesce(p_payload ->> 'customer_phone', '') <> ''
    and (p_payload ->> 'customer_phone') !~ '^\+?[0-9]{7,15}$' then
    raise exception 'invalid_input';
  end if;
  if v_kind = 'expense' then
    if jsonb_array_length(p_payload -> 'items') <> 0
      or nullif(btrim(p_payload ->> 'description'), '') is null then
      raise exception 'invalid_input';
    end if;
  elsif jsonb_array_length(p_payload -> 'items') = 0 then
    raise exception 'invalid_input';
  end if;
  v_total := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'total_piastres'));
  if v_total <= 0 then raise exception 'invalid_input'; end if;
  for v_tender in select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
  loop
    if jsonb_typeof(v_tender) is distinct from 'object'
      or not (v_tender ?& array['method', 'piastres'])
      or v_tender - 'method' - 'piastres' <> '{}'::jsonb
      or jsonb_typeof(v_tender -> 'method') is distinct from 'string'
      or jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any(v_seen) then raise exception 'invalid_input'; end if;
    v_seen := array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_amount <= 0 then raise exception 'invalid_input'; end if;
    v_tender_sum := v_tender_sum + v_amount;
  end loop;
  if v_kind = 'purchase' then
    if v_tender_sum > v_total then raise exception 'tender_mismatch'; end if;
    v_payable := private.opening_checked_bigint(v_total - v_tender_sum);
    if v_payable > 0 then
      if jsonb_typeof(p_payload -> 'purchase_obligation_piastres')
          is distinct from 'string'
        or private.opening_checked_bigint(private.opening_parse_amount(
          p_payload ->> 'purchase_obligation_piastres')) <> v_payable
        or nullif(btrim(p_payload ->> 'customer_name'), '') is null then
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
  for v_line in select value from jsonb_array_elements(p_payload -> 'items') as l(value)
  loop
    if jsonb_typeof(v_line) is distinct from 'object'
      or not (v_line ?& array[
        'category', 'karat', 'milligrams', 'count',
        'item_name', 'line_price_piastres'
      ])
      or v_line - 'category' - 'karat' - 'milligrams' - 'count'
        - 'item_name' - 'line_price_piastres' <> '{}'::jsonb
      or jsonb_typeof(v_line -> 'category') is distinct from 'string'
      or jsonb_typeof(v_line -> 'milligrams') is distinct from 'string'
      or jsonb_typeof(v_line -> 'item_name') is distinct from 'string'
      or jsonb_typeof(v_line -> 'line_price_piastres')
        not in ('string', 'null') then
      raise exception 'invalid_input';
    end if;
    v_category := v_line ->> 'category';
    if jsonb_typeof(v_line -> 'karat') <> 'number'
      or (v_line ->> 'karat') !~ '^[0-9]{2}$' then
      raise exception 'invalid_input';
    end if;
    v_karat := (v_line ->> 'karat')::smallint;
    if not private.opening_pair_allowed(v_category, v_karat)
      or (v_kind = 'sale' and v_category = 'scrap')
      or nullif(btrim(v_line ->> 'item_name'), '') is null
      or length(v_line ->> 'item_name') > 120 then
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
      if jsonb_typeof(v_line -> 'count') is distinct from 'string' then
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
  if v_priced <> 0 and
    (v_priced <> jsonb_array_length(p_payload -> 'items') or v_line_sum <> v_total) then
    raise exception 'line_price_mismatch';
  end if;
  select day.id, day.day_version into v_day, v_day_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open' for update;
  if v_day is null then raise exception 'day_closed'; end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, v_kind, v_day, v_actor, v_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, v_shop, p_payload, v_at);
  if v_payable > 0 then
    insert into public.purchase_cash_payables (
      operation_id, shop_id, seller_name, initial_piastres,
      remaining_piastres, created_at, updated_at
    ) values (v_op, v_shop, btrim(p_payload ->> 'customer_name'),
      v_payable, v_payable, v_at, v_at);
  end if;
  update public.business_days set day_version = day_version + 1 where id = v_day;

  v_sign := case when v_kind = 'sale' then 1 else -1 end;
  if v_tender_sum > 0 then
    v_clear := private.financial_account(v_shop, 'movement_money_clearing',
      'money', null, null, null, true);
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, bucket_key
    ) values (v_shop, v_op, 'money', 'EGP', 'money') returning id into v_money_journal;
    for v_tender in select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
    loop
      v_account := private.financial_account(v_shop, 'cash_method', 'money',
        null, null, v_tender ->> 'method', false);
      if v_account is null then raise exception 'invalid_input'; end if;
      v_amount := private.opening_checked_bigint(
        private.opening_parse_amount(v_tender ->> 'piastres'));
      insert into public.journal_postings (
        shop_id, journal_id, account_id, operation_id, amount
      ) values (v_shop, v_money_journal, v_account, v_op, v_sign * v_amount);
    end loop;
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values (v_shop, v_money_journal, v_clear, v_op, -v_sign * v_tender_sum);
  end if;

  if v_kind <> 'expense' then
    for v_line in select value from jsonb_array_elements(p_payload -> 'items') as l(value)
    loop
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      v_mg := private.opening_checked_bigint(
        private.opening_parse_amount(v_line ->> 'milligrams'));
      v_account := private.financial_account(v_shop,
        case when v_category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
        'gold_mg', v_category, v_karat, null, v_kind = 'purchase');
      if v_account is null then raise exception 'insufficient_stock'; end if;
      v_clear := private.financial_account(v_shop, 'movement_gold_clearing',
        'gold_mg', null, v_karat, null, true);
      insert into public.journals (
        shop_id, operation_id, unit_kind, karat, bucket_key
      ) values (
        v_shop, v_op, 'gold_mg', v_karat,
        'gold:' || v_category || ':' || v_karat::text
      ) returning id into v_gold_journal;
      insert into public.journal_postings (
        shop_id, journal_id, account_id, operation_id, amount
      ) values
        (v_shop, v_gold_journal, v_account, v_op, -v_sign * v_mg),
        (v_shop, v_gold_journal, v_clear, v_op, v_sign * v_mg);
      if v_category <> 'scrap' then
        v_count := private.opening_checked_bigint(
          private.opening_parse_amount(v_line ->> 'count'));
        v_account := private.financial_account(v_shop, 'saleable_count',
          'count', v_category, v_karat, null, v_kind = 'purchase');
        if v_account is null then raise exception 'insufficient_stock'; end if;
        v_clear := private.financial_account(v_shop, 'movement_count_clearing',
          'count', v_category, v_karat, null, true);
        insert into public.journals (
          shop_id, operation_id, unit_kind, karat, bucket_key
        ) values (
          v_shop, v_op, 'count', v_karat,
          'count:' || v_category || ':' || v_karat::text
        ) returning id into v_count_journal;
        insert into public.journal_postings (
          shop_id, journal_id, account_id, operation_id, amount
        ) values
          (v_shop, v_count_journal, v_account, v_op, -v_sign * v_count),
          (v_shop, v_count_journal, v_clear, v_op, v_sign * v_count);
      end if;
    end loop;
  end if;
  v_action := v_kind || '_confirmed';
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, v_action, v_op, v_at,
    jsonb_build_object('business_day_id', v_day, 'operation_id', v_op)
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_op, v_action, v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, p_payload, v_hash, v_op, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_op,
    'business_day_id', v_day, 'day_version', v_day_version + 1,
    'replayed', false);
end;
$fn$;

revoke all on function private.financial_account(
  uuid, text, text, text, smallint, text, boolean
) from public, anon, authenticated;
revoke all on function public.post_daily_ledger_trade(uuid, jsonb)
  from public, anon;
grant execute on function public.post_daily_ledger_trade(uuid, jsonb)
  to authenticated;

create function private.daily_ledger_count_snapshot(p_shop uuid)
returns jsonb language sql stable security definer set search_path = '' as $fn$
  select jsonb_build_object(
    'cash', (
      select jsonb_build_object(
        'cash', coalesce(max(amount) filter (where method_code = 'cash'), 0)::text,
        'instant_transfer', coalesce(max(amount) filter (where method_code = 'instant_transfer'), 0)::text,
        'wallet', coalesce(max(amount) filter (where method_code = 'wallet'), 0)::text,
        'card', coalesce(max(amount) filter (where method_code = 'card'), 0)::text
      )
      from public.ledger_account_balances
      where shop_id = p_shop and account_kind = 'cash_method'
    ),
    'stock', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'category', metal.category_code, 'karat', metal.karat,
        'milligrams', metal.amount::text,
        'count', coalesce(piece.amount, 0)::text
      ) order by metal.category_code, metal.karat), '[]'::jsonb)
      from public.ledger_account_balances as metal
      left join public.ledger_account_balances as piece
        on piece.shop_id = metal.shop_id
        and piece.account_kind = 'saleable_count'
        and piece.category_code = metal.category_code
        and piece.karat = metal.karat
      where metal.shop_id = p_shop and metal.account_kind = 'saleable_metal'
    ),
    'scrap', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'karat', scrap.karat, 'milligrams', scrap.amount::text
      ) order by scrap.karat), '[]'::jsonb)
      from public.ledger_account_balances as scrap
      where scrap.shop_id = p_shop and scrap.account_kind = 'scrap_metal'
    )
  );
$fn$;

create function public.get_daily_ledger_day_state()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_day public.business_days%rowtype;
begin
  v_shop := private.opening_require_reader_shop();
  select day.* into v_day from public.business_days as day
  where day.shop_id = v_shop order by day.opened_at desc, day.id desc limit 1;
  if v_day.id is null then
    return jsonb_build_object('state', 'uninitialized');
  end if;
  return jsonb_build_object(
    'state', v_day.status,
    'business_day_id', v_day.id,
    'business_date', to_char(v_day.business_date, 'YYYY-MM-DD'),
    'day_version', v_day.day_version,
    'counts', private.daily_ledger_count_snapshot(v_shop)
  );
end;
$fn$;

create function public.close_daily_ledger_day(
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
  v_payload := jsonb_build_object('version', 1, 'kind', 'close_day',
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
  if p_counts <> v_actual then
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
    jsonb_build_object('business_day_id', p_day_id));
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

create function public.open_daily_ledger_day(p_idempotency_key uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_request public.financial_command_requests%rowtype;
  v_payload jsonb := '{"version":1,"kind":"open_day"}'::jsonb;
  v_hash bytea;
  v_last public.business_days%rowtype;
  v_at timestamptz;
  v_day uuid;
  v_actor uuid;
  v_sequence bigint;
  v_op uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
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
  select day.* into v_last from public.business_days as day
  where day.shop_id = v_shop order by day.opened_at desc, day.id desc limit 1
  for update;
  if v_last.id is null or v_last.status <> 'closed' then
    raise exception 'day_not_closed';
  end if;
  v_at := pg_catalog.clock_timestamp();
  v_actor := auth.uid();
  insert into public.business_days (shop_id, business_date, opened_at, status)
  values (v_shop, private.cairo_business_date(v_at), v_at, 'open')
  returning id into v_day;
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (v_shop, v_sequence, 'open_day', v_day, v_actor, v_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, v_shop, v_payload, v_at);
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, 'business_day_opened', v_op, v_at,
    jsonb_build_object('business_day_id', v_day));
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (v_shop, v_op, 'business_day_opened', v_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (v_shop, p_idempotency_key, v_payload, v_hash, v_op, v_at);
  return jsonb_build_object('ok', true, 'operation_id', v_op,
    'business_day_id', v_day, 'replayed', false);
end;
$fn$;

revoke all on function private.daily_ledger_count_snapshot(uuid)
  from public, anon, authenticated;
revoke all on function public.get_daily_ledger_day_state()
  from public, anon;
revoke all on function public.close_daily_ledger_day(uuid, uuid, bigint, jsonb)
  from public, anon;
revoke all on function public.open_daily_ledger_day(uuid)
  from public, anon;
grant execute on function public.get_daily_ledger_day_state()
  to authenticated;
grant execute on function public.close_daily_ledger_day(uuid, uuid, bigint, jsonb)
  to authenticated;
grant execute on function public.open_daily_ledger_day(uuid)
  to authenticated;

create function public.get_daily_ledger_v2()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_base jsonb;
  v_day public.business_days%rowtype;
  v_feed jsonb;
  v_summary jsonb;
  v_gold jsonb;
  v_name text;
begin
  v_shop := private.opening_require_reader_shop();
  v_base := public.get_daily_ledger();
  if v_base ->> 'state' <> 'confirmed' then return v_base; end if;
  select day.* into v_day from public.business_days as day
  where day.shop_id = v_shop order by day.opened_at desc, day.id desc limit 1;
  select shop.owner_display_name into v_name from public.shops as shop
  where shop.id = v_shop;
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', operation.kind,
    'label_ar', case operation.kind
      when 'opening_balances' then 'رصيد افتتاحي'
      when 'sale' then 'بيع'
      when 'purchase' then 'شراء'
      when 'expense' then 'مصروف'
      when 'purchase_settlement' then 'سداد شراء'
      when 'close_day' then 'تقفيل اليومية'
      when 'open_day' then 'فتح اليومية'
    end,
    'operation_id', operation.id,
    'actor_display_name', coalesce(v_name, ''),
    'occurred_at', pg_catalog.to_jsonb(operation.created_at),
    'occurred_at_cairo', to_char(
      operation.created_at at time zone 'Africa/Cairo',
      'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'has_note', coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
  ) order by operation.shop_sequence desc), '[]'::jsonb) into v_feed
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop and operation.business_day_id = v_day.id;
  select jsonb_build_object(
    'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'sale'), 0)::text,
    'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'purchase'), 0)::text,
    'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'expense'), 0)::text,
    'sale_count', count(*) filter (where operation.kind = 'sale'),
    'purchase_count', count(*) filter (where operation.kind = 'purchase'),
    'expense_count', count(*) filter (where operation.kind = 'expense')
  ) into v_summary
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
  where operation.shop_id = v_shop and operation.business_day_id = v_day.id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', bucket.kind,
    'category', bucket.category,
    'karat', bucket.karat,
    'milligrams', bucket.milligrams::text,
    'count', bucket.pieces::text
  ) order by bucket.kind, bucket.category, bucket.karat), '[]'::jsonb)
    into v_gold
  from (
    select operation.kind,
      item.value ->> 'category' as category,
      (item.value ->> 'karat')::smallint as karat,
      sum((item.value ->> 'milligrams')::numeric) as milligrams,
      sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id
     and detail.operation_id = operation.id
    cross join lateral jsonb_array_elements(detail.payload -> 'items') as item(value)
    where operation.shop_id = v_shop and operation.business_day_id = v_day.id
      and operation.kind in ('sale', 'purchase')
    group by operation.kind, item.value ->> 'category',
      (item.value ->> 'karat')::smallint
  ) as bucket;
  v_summary := v_summary || jsonb_build_object('gold_by_bucket', v_gold);
  return jsonb_set(jsonb_set(jsonb_set(jsonb_set(v_base,
    '{read_model_version}', '2'::jsonb),
    '{business_day}', jsonb_build_object(
      'id', v_day.id,
      'business_date', to_char(v_day.business_date, 'YYYY-MM-DD'),
      'opened_at', pg_catalog.to_jsonb(v_day.opened_at)
    )), '{feed}', v_feed), '{day_summary}', v_summary);
end;
$fn$;

revoke all on function public.get_daily_ledger_v2() from public, anon;
grant execute on function public.get_daily_ledger_v2() to authenticated;

create function public.get_daily_ledger_operation(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_result jsonb;
begin
  if p_operation_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  select jsonb_build_object(
    'operation_id', operation.id,
    'shop_id', operation.shop_id,
    'kind', operation.kind,
    'business_day_id', operation.business_day_id,
    'shop_sequence', operation.shop_sequence::text,
    'shop_name', shop.name,
    'actor_display_name', shop.owner_display_name,
    'occurred_at', pg_catalog.to_jsonb(operation.created_at),
    'occurred_at_cairo', to_char(
      operation.created_at at time zone 'Africa/Cairo',
      'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'purchase_payable_initial_piastres', payable.initial_piastres::text,
    'purchase_payable_remaining_piastres', payable.remaining_piastres::text,
    'payload', coalesce(detail.payload, request.payload_canonical)
  ) into v_result
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  left join public.financial_command_requests as request
    on request.shop_id = operation.shop_id
   and request.operation_id = operation.id
  left join public.purchase_cash_payables as payable
    on payable.shop_id = operation.shop_id
   and payable.operation_id = operation.id
  join public.shops as shop on shop.id = operation.shop_id
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if v_result is null then raise exception 'not_found'; end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_daily_ledger_operation(uuid)
  from public, anon;
grant execute on function public.get_daily_ledger_operation(uuid)
  to authenticated;

commit;

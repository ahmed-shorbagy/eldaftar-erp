-- Milestone 3 inventory, custody, and one-unit obligations (ADR 0007 and ADR 0009).
-- Additive only. Old journal kinds and commands stay valid.
-- Lot sync is a deferrable initially-immediate constraint trigger on
-- financial_command_requests, which every existing command inserts last.
-- When a transaction defers constraints, earlier journal checks still run
-- first because their events were queued on the postings.
--
-- Old bucket commands (opening, sale, purchase, scrap sale, scrap-to-stock,
-- full return) that do not name lots use deterministic FIFO: shop-owned
-- available lots of that category and karat, oldest created_at then id.
-- Piece lots stay pair-safe: remaining milligrams and count are both zero
-- or both positive. Nominal bullion/coin identity is never a stock weight.
-- Legacy reconciliation labels pre-existing owned balances and posts no journal.
-- This is a bookkeeping model, not a legal title or tax determination.

begin;

alter table public.financial_operations drop constraint financial_operations_kind_check;
alter table public.financial_operations add constraint financial_operations_kind_check
  check (kind in ('opening_balances', 'sale', 'purchase', 'expense',
    'close_day', 'open_day', 'purchase_settlement', 'cash_transfer',
    'scrap_sale', 'scrap_to_stock', 'sale_return', 'purchase_return',
    'inventory_addition', 'inventory_removal', 'inventory_correction',
    'inventory_conversion', 'inventory_receipt', 'inventory_recognition',
    'ownership_transfer', 'gold_obligation_acquisition',
    'gold_obligation_settlement', 'receipt_manual_allocation'));

alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled', 'invoice_send_confirmed',
    'cash_transfer_confirmed', 'scrap_sale_confirmed',
    'scrap_to_stock_confirmed', 'sale_return_confirmed',
    'purchase_return_confirmed', 'inventory_addition_confirmed',
    'inventory_removal_confirmed', 'inventory_correction_confirmed',
    'inventory_conversion_confirmed', 'inventory_receipt_confirmed',
    'inventory_recognition_confirmed', 'ownership_transfer_confirmed',
    'gold_obligation_acquisition_confirmed', 'gold_obligation_settled',
    'receipt_manual_allocation_confirmed'));

alter table public.financial_outbox drop constraint financial_outbox_event_check;
alter table public.financial_outbox add constraint financial_outbox_event_check
  check (event_type in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'purchase_settled', 'cash_transfer_confirmed',
    'scrap_sale_confirmed', 'scrap_to_stock_confirmed',
    'sale_return_confirmed', 'purchase_return_confirmed',
    'inventory_addition_confirmed', 'inventory_removal_confirmed',
    'inventory_correction_confirmed', 'inventory_conversion_confirmed',
    'inventory_receipt_confirmed', 'inventory_recognition_confirmed',
    'ownership_transfer_confirmed', 'gold_obligation_acquisition_confirmed',
    'gold_obligation_settled', 'receipt_manual_allocation_confirmed'));

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
    when 'adjustment_money_clearing' then unit_kind = 'money'
      and currency_code = 'EGP' and karat is null
      and category_code is null and method_code is null
    when 'opening_gold_clearing' then unit_kind = 'gold_mg'
      and currency_code is null and category_code is null
      and method_code is null and karat in (14, 18, 21, 22, 24)
    when 'movement_gold_clearing' then unit_kind = 'gold_mg'
      and currency_code is null and category_code is null
      and method_code is null and karat in (14, 18, 21, 22, 24)
    when 'adjustment_gold_clearing' then unit_kind = 'gold_mg'
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
    when 'adjustment_count_clearing' then unit_kind = 'count'
      and currency_code is null and method_code is null
      and category_code in ('worked_jewelry', 'bullion', 'coin')
      and private.opening_pair_allowed(category_code, karat)
    else false
  end
) is true);

create unique index ledger_accounts_adjustment_money_key
  on public.ledger_accounts (shop_id)
  where account_kind = 'adjustment_money_clearing';
create unique index ledger_accounts_adjustment_gold_key
  on public.ledger_accounts (shop_id, karat)
  where account_kind = 'adjustment_gold_clearing';
create unique index ledger_accounts_adjustment_count_key
  on public.ledger_accounts (shop_id, category_code, karat)
  where account_kind = 'adjustment_count_clearing';

create index if not exists financial_command_requests_operation_idx
  on public.financial_command_requests (shop_id, operation_id);

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
        ('cash_method', 'opening_money_clearing', 'movement_money_clearing',
         'adjustment_money_clearing') then
        raise exception 'journal_imbalance';
      end if;
    elsif v_unit = 'gold_mg' then
      if v_account.account_kind in
        ('opening_gold_clearing', 'movement_gold_clearing', 'adjustment_gold_clearing') then
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
        ('saleable_count', 'opening_count_clearing', 'movement_count_clearing',
         'adjustment_count_clearing') then
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

create function private.parse_signed_amount(p_value text)
returns numeric language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_text text := p_value;
begin
  if p_value is null then raise exception 'invalid_input'; end if;
  if left(p_value, 1) = '-' then
    v_text := substr(p_value, 2);
    if v_text is null or v_text = '' then raise exception 'invalid_input'; end if;
    return -private.opening_parse_amount(v_text);
  end if;
  return private.opening_parse_amount(p_value);
end;
$fn$;

create function private.checked_signed_bigint(p_value numeric)
returns bigint language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if p_value is null or p_value <> trunc(p_value)
    or p_value < -9223372036854775808
    or p_value > 9223372036854775807 then
    raise exception 'overflow';
  end if;
  return p_value::bigint;
end;
$fn$;

create table public.inventory_products (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  name text not null,
  category_code text not null,
  karat smallint not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint inventory_products_shop_id_id_key unique (shop_id, id),
  constraint inventory_products_name_key unique (shop_id, category_code, karat, name),
  constraint inventory_products_name_check check (
    nullif(btrim(name), '') is not null and char_length(name) <= 120
    and name = btrim(name)
  ),
  constraint inventory_products_pair_check check (
    private.opening_pair_allowed(category_code, karat)
  )
);

create table public.bullion_denominations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  label text not null,
  nominal_milligrams bigint not null,
  active boolean not null default true,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint bullion_denominations_shop_id_id_key unique (shop_id, id),
  constraint bullion_denominations_label_key unique (shop_id, label),
  constraint bullion_denominations_label_check check (
    nullif(btrim(label), '') is not null and char_length(label) <= 120
    and label = btrim(label)
  ),
  constraint bullion_denominations_nominal_check check (nominal_milligrams > 0)
);

create table public.coin_types (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  label text not null,
  nominal_milligrams bigint,
  active boolean not null default true,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint coin_types_shop_id_id_key unique (shop_id, id),
  constraint coin_types_label_key unique (shop_id, label),
  constraint coin_types_label_check check (
    nullif(btrim(label), '') is not null and char_length(label) <= 120
    and label = btrim(label)
  ),
  constraint coin_types_nominal_check check (
    nominal_milligrams is null or nominal_milligrams > 0
  )
);

create table public.traders (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  display_name text not null,
  phone text not null default '',
  note text not null default '',
  active boolean not null default true,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint traders_shop_id_id_key unique (shop_id, id),
  constraint traders_name_key unique (shop_id, display_name),
  constraint traders_name_check check (
    nullif(btrim(display_name), '') is not null
    and char_length(display_name) <= 200 and display_name = btrim(display_name)
  ),
  constraint traders_phone_check check (char_length(phone) <= 20),
  constraint traders_note_check check (char_length(note) <= 1000)
);

create table public.inventory_lots (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  product_id uuid not null,
  category_code text not null,
  karat smallint not null,
  display_name text not null,
  original_milligrams bigint not null,
  original_count bigint,
  tracks_count boolean not null,
  stock_class text not null,
  trader_id uuid,
  legacy_aggregate boolean not null default false,
  denomination_id uuid,
  coin_type_id uuid,
  origin_operation_id uuid,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint inventory_lots_shop_id_id_key unique (shop_id, id),
  constraint inventory_lots_product_fkey
    foreign key (shop_id, product_id)
    references public.inventory_products (shop_id, id),
  constraint inventory_lots_trader_fkey
    foreign key (shop_id, trader_id)
    references public.traders (shop_id, id),
  constraint inventory_lots_denomination_fkey
    foreign key (shop_id, denomination_id)
    references public.bullion_denominations (shop_id, id),
  constraint inventory_lots_coin_type_fkey
    foreign key (shop_id, coin_type_id)
    references public.coin_types (shop_id, id),
  constraint inventory_lots_operation_fkey
    foreign key (shop_id, origin_operation_id)
    references public.financial_operations (shop_id, id),
  constraint inventory_lots_pair_check check (
    private.opening_pair_allowed(category_code, karat)
  ),
  constraint inventory_lots_weight_check check (original_milligrams > 0),
  constraint inventory_lots_class_check check (stock_class in (
    'owned_available', 'owned_pending', 'trader_custody'
  )),
  constraint inventory_lots_trader_check check (
    (stock_class = 'trader_custody') = (trader_id is not null)
  ),
  constraint inventory_lots_count_check check (
    (category_code = 'scrap' and not tracks_count and original_count is null)
    or (category_code <> 'scrap' and tracks_count and original_count > 0)
  ),
  constraint inventory_lots_legacy_check check (
    (legacy_aggregate and origin_operation_id is null)
    or not legacy_aggregate
  ),
  constraint inventory_lots_denomination_check check (
    denomination_id is null or category_code = 'bullion'
  ),
  constraint inventory_lots_coin_check check (
    coin_type_id is null or category_code = 'coin'
  ),
  constraint inventory_lots_name_check check (
    nullif(btrim(display_name), '') is not null and char_length(display_name) <= 120
  )
);

create table public.inventory_lot_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  lot_id uuid not null,
  operation_id uuid,
  delta_milligrams bigint not null,
  delta_count bigint not null,
  movement_kind text not null,
  allocation_mode text not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint inventory_lot_movements_shop_id_id_key unique (shop_id, id),
  constraint inventory_lot_movements_lot_fkey
    foreign key (shop_id, lot_id) references public.inventory_lots (shop_id, id),
  constraint inventory_lot_movements_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint inventory_lot_movements_nonzero_check check (
    delta_milligrams <> 0 or delta_count <> 0
  ),
  constraint inventory_lot_movements_mode_check check (
    (allocation_mode = 'legacy_reconciliation' and operation_id is null)
    or (allocation_mode <> 'legacy_reconciliation' and operation_id is not null)
  ),
  constraint inventory_lot_movements_kind_check check (
    movement_kind in ('opening', 'purchase', 'sale', 'scrap_sale',
      'conversion_out', 'conversion_in', 'return', 'legacy_reconciliation',
      'addition', 'removal', 'correction', 'receipt', 'recognition_out',
      'recognition_in', 'transfer_out', 'transfer_in', 'gold_acquisition',
      'gold_settlement', 'manual_link')
    and allocation_mode in ('deterministic_fifo', 'explicit', 'opening_line',
      'purchase_line', 'return_mirror', 'legacy_reconciliation', 'manual',
      'recognition', 'ownership_transfer', 'custody_receipt', 'gold_settlement',
      'manual_link')
  )
);

create table public.inventory_receipts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  owner_kind text not null,
  trader_id uuid,
  custodian_kind text not null default 'shop',
  counterparty_name text not null,
  product_id uuid not null,
  lot_id uuid not null,
  category_code text not null,
  karat smallint not null,
  milligrams bigint not null,
  piece_count bigint,
  received_at timestamptz not null default pg_catalog.clock_timestamp(),
  operation_id uuid not null,
  recognition_policy text not null,
  constraint inventory_receipts_shop_id_id_key unique (shop_id, id),
  constraint inventory_receipts_owner_check check (owner_kind in ('shop', 'trader')),
  constraint inventory_receipts_custodian_check check (custodian_kind = 'shop'),
  constraint inventory_receipts_policy_check check (
    recognition_policy in ('immediate', 'deferred', 'custody')
    and (owner_kind = 'trader') = (recognition_policy = 'custody')
    and (owner_kind = 'trader') = (trader_id is not null)
  ),
  constraint inventory_receipts_weight_check check (milligrams > 0),
  constraint inventory_receipts_count_check check (
    (category_code = 'scrap' and piece_count is null)
    or (category_code <> 'scrap' and piece_count > 0)
  ),
  constraint inventory_receipts_pair_check check (
    private.opening_pair_allowed(category_code, karat)
  ),
  constraint inventory_receipts_name_check check (
    nullif(btrim(counterparty_name), '') is not null
    and char_length(counterparty_name) <= 200
  ),
  constraint inventory_receipts_product_fkey
    foreign key (shop_id, product_id)
    references public.inventory_products (shop_id, id),
  constraint inventory_receipts_lot_fkey
    foreign key (shop_id, lot_id) references public.inventory_lots (shop_id, id),
  constraint inventory_receipts_trader_fkey
    foreign key (shop_id, trader_id) references public.traders (shop_id, id),
  constraint inventory_receipts_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);

create table public.receipt_quantity_allocations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  receipt_id uuid not null,
  operation_id uuid not null,
  allocation_kind text not null,
  milligrams bigint not null,
  piece_count bigint,
  linked_lot_id uuid,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint receipt_quantity_allocations_shop_id_id_key unique (shop_id, id),
  constraint receipt_quantity_allocations_kind_check check (
    allocation_kind in ('recognize', 'manual_link', 'ownership_transfer')
  ),
  constraint receipt_quantity_allocations_weight_check check (milligrams > 0),
  constraint receipt_quantity_allocations_count_check check (
    piece_count is null or piece_count > 0
  ),
  constraint receipt_quantity_allocations_receipt_fkey
    foreign key (shop_id, receipt_id)
    references public.inventory_receipts (shop_id, id),
  constraint receipt_quantity_allocations_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint receipt_quantity_allocations_lot_fkey
    foreign key (shop_id, linked_lot_id)
    references public.inventory_lots (shop_id, id)
);

create table public.gold_obligations (
  operation_id uuid primary key,
  shop_id uuid not null,
  trader_id uuid,
  counterparty_name text not null,
  karat smallint not null,
  initial_milligrams bigint not null,
  remaining_milligrams bigint not null,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  constraint gold_obligations_shop_operation_key unique (shop_id, operation_id),
  constraint gold_obligations_karat_check check (karat in (14, 18, 21, 22, 24)),
  constraint gold_obligations_amount_check check (
    initial_milligrams > 0
    and remaining_milligrams >= 0
    and remaining_milligrams <= initial_milligrams
  ),
  constraint gold_obligations_name_check check (
    nullif(btrim(counterparty_name), '') is not null
    and char_length(counterparty_name) <= 200
  ),
  constraint gold_obligations_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint gold_obligations_trader_fkey
    foreign key (shop_id, trader_id) references public.traders (shop_id, id)
);

alter table public.purchase_cash_payables
  add column trader_id uuid,
  add constraint purchase_cash_payables_trader_fkey
    foreign key (shop_id, trader_id) references public.traders (shop_id, id);

create table public.inventory_explicit_plans (
  shop_id uuid not null,
  idempotency_key uuid not null,
  plan jsonb not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (shop_id, idempotency_key),
  constraint inventory_explicit_plans_object_check check (jsonb_typeof(plan) = 'object')
);

create table public.inventory_command_envelopes (
  shop_id uuid not null,
  idempotency_key uuid not null,
  payload jsonb not null,
  payload_sha256 bytea not null,
  operation_id uuid not null,
  result jsonb not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (shop_id, idempotency_key),
  constraint inventory_command_envelopes_hash_check check (octet_length(payload_sha256) = 32),
  constraint inventory_command_envelopes_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);

create table public.inventory_catalog_requests (
  shop_id uuid not null,
  idempotency_key uuid not null,
  payload jsonb not null,
  payload_sha256 bytea not null,
  result jsonb not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  primary key (shop_id, idempotency_key),
  constraint inventory_catalog_requests_hash_check check (octet_length(payload_sha256) = 32)
);

create table public.inventory_catalog_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  actor_user_id uuid not null,
  action text not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  details jsonb not null,
  constraint inventory_catalog_events_action_check check (action in (
    'product_saved', 'bullion_denomination_saved', 'coin_type_saved', 'trader_saved'
  )),
  constraint inventory_catalog_events_details_check check (jsonb_typeof(details) = 'object'),
  constraint inventory_catalog_events_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create table public.inventory_lot_sync (
  operation_id uuid primary key,
  shop_id uuid not null,
  synced_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint inventory_lot_sync_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id)
);

create index inventory_products_shop_idx
  on public.inventory_products (shop_id, category_code, karat, name);
create index bullion_denominations_shop_idx
  on public.bullion_denominations (shop_id, created_at desc);
create index coin_types_shop_idx on public.coin_types (shop_id, created_at desc);
create index traders_shop_name_idx on public.traders (shop_id, display_name);
create index traders_shop_time_idx on public.traders (shop_id, created_at desc, id desc);
create index inventory_lots_bucket_idx
  on public.inventory_lots (shop_id, stock_class, category_code, karat, created_at, id);
create index inventory_lots_product_idx on public.inventory_lots (shop_id, product_id);
create index inventory_lots_trader_idx on public.inventory_lots (shop_id, trader_id);
create index inventory_lots_origin_idx on public.inventory_lots (shop_id, origin_operation_id);
create index inventory_lots_denomination_idx
  on public.inventory_lots (shop_id, denomination_id)
  where denomination_id is not null;
create index inventory_lots_coin_type_idx
  on public.inventory_lots (shop_id, coin_type_id)
  where coin_type_id is not null;
create index inventory_lot_movements_lot_idx
  on public.inventory_lot_movements (shop_id, lot_id, created_at, id);
create index inventory_lot_movements_operation_idx
  on public.inventory_lot_movements (shop_id, operation_id, created_at, id);
create index inventory_receipts_shop_time_idx
  on public.inventory_receipts (shop_id, received_at desc, id desc);
create index inventory_receipts_trader_idx
  on public.inventory_receipts (shop_id, trader_id, received_at desc, id desc);
create index inventory_receipts_lot_idx on public.inventory_receipts (shop_id, lot_id);
create index inventory_receipts_product_idx
  on public.inventory_receipts (shop_id, product_id);
create index inventory_receipts_operation_idx
  on public.inventory_receipts (shop_id, operation_id);
create index receipt_quantity_allocations_receipt_idx
  on public.receipt_quantity_allocations (shop_id, receipt_id);
create index receipt_quantity_allocations_lot_idx
  on public.receipt_quantity_allocations (shop_id, linked_lot_id);
create index receipt_quantity_allocations_operation_idx
  on public.receipt_quantity_allocations (shop_id, operation_id);
create index gold_obligations_shop_idx
  on public.gold_obligations (shop_id, updated_at desc);
create index gold_obligations_trader_idx
  on public.gold_obligations (shop_id, trader_id, created_at desc, operation_id desc)
  where trader_id is not null;
create index purchase_cash_payables_trader_idx
  on public.purchase_cash_payables (shop_id, trader_id, created_at desc, operation_id desc)
  where trader_id is not null;
create index inventory_catalog_events_shop_idx
  on public.inventory_catalog_events (shop_id, created_at desc);
create index inventory_catalog_events_actor_idx
  on public.inventory_catalog_events (shop_id, actor_user_id);
create index inventory_command_envelopes_operation_idx
  on public.inventory_command_envelopes (shop_id, operation_id);
create index inventory_lot_sync_shop_idx on public.inventory_lot_sync (shop_id);

comment on table public.inventory_lots is
  'Immutable lot identity. Remaining quantity is the sum of movements. legacy_aggregate labels stock already recognized before lot tracking and is not a new financial posting. denomination_id and coin_type_id are nominal catalog identity; original_milligrams is the measured weight.';
comment on table public.gold_obligations is
  'One gold obligation unit: milligrams at exactly one karat. Optional trader_id is an immutable shop-scoped link assigned at insert; historical rows without it stay unlinked. Not an EGP payable and not a custody return duty.';
comment on table public.inventory_receipts is
  'Immutable physical receipt. Trader-owned custody is excluded from shop-owned stock. Recognition and ownership transfer allocate the remaining quantity once.';

create function private.inventory_reject_mutation()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  raise exception 'audit_append_only';
end;
$fn$;

create trigger inventory_products_append_only
before update or delete on public.inventory_products
for each row execute function private.inventory_reject_mutation();
create trigger bullion_denominations_append_only
before update or delete on public.bullion_denominations
for each row execute function private.inventory_reject_mutation();
create trigger coin_types_append_only
before update or delete on public.coin_types
for each row execute function private.inventory_reject_mutation();
create trigger traders_append_only
before update or delete on public.traders
for each row execute function private.inventory_reject_mutation();
create trigger inventory_lots_append_only
before update or delete on public.inventory_lots
for each row execute function private.inventory_reject_mutation();
create trigger inventory_lot_movements_append_only
before update or delete on public.inventory_lot_movements
for each row execute function private.inventory_reject_mutation();
create trigger inventory_receipts_append_only
before update or delete on public.inventory_receipts
for each row execute function private.inventory_reject_mutation();
create trigger receipt_quantity_allocations_append_only
before update or delete on public.receipt_quantity_allocations
for each row execute function private.inventory_reject_mutation();
create trigger inventory_explicit_plans_append_only
before update or delete on public.inventory_explicit_plans
for each row execute function private.inventory_reject_mutation();
create trigger inventory_command_envelopes_append_only
before update or delete on public.inventory_command_envelopes
for each row execute function private.inventory_reject_mutation();
create trigger inventory_catalog_requests_append_only
before update or delete on public.inventory_catalog_requests
for each row execute function private.inventory_reject_mutation();
create trigger inventory_catalog_events_append_only
before update or delete on public.inventory_catalog_events
for each row execute function private.inventory_reject_mutation();
create trigger inventory_lot_sync_append_only
before update or delete on public.inventory_lot_sync
for each row execute function private.inventory_reject_mutation();

create function private.gold_obligations_remaining_only()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if tg_op = 'DELETE' then raise exception 'audit_append_only'; end if;
  if new.operation_id is distinct from old.operation_id
    or new.shop_id is distinct from old.shop_id
    or new.trader_id is distinct from old.trader_id
    or new.counterparty_name is distinct from old.counterparty_name
    or new.karat is distinct from old.karat
    or new.initial_milligrams is distinct from old.initial_milligrams
    or new.created_at is distinct from old.created_at
    or new.remaining_milligrams > old.remaining_milligrams then
    raise exception 'audit_append_only';
  end if;
  return new;
end;
$fn$;

create trigger gold_obligations_remaining_only
before update or delete on public.gold_obligations
for each row execute function private.gold_obligations_remaining_only();

create function private.purchase_cash_payables_remaining_only()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  if tg_op = 'DELETE' then raise exception 'audit_append_only'; end if;
  if new.operation_id is distinct from old.operation_id
    or new.shop_id is distinct from old.shop_id
    or new.trader_id is distinct from old.trader_id
    or new.seller_name is distinct from old.seller_name
    or new.initial_piastres is distinct from old.initial_piastres
    or new.created_at is distinct from old.created_at
    or new.remaining_piastres > old.remaining_piastres then
    raise exception 'audit_append_only';
  end if;
  return new;
end;
$fn$;

create trigger purchase_cash_payables_remaining_only
before update or delete on public.purchase_cash_payables
for each row execute function private.purchase_cash_payables_remaining_only();

create function private.enforce_one_obligation_unit()
returns trigger language plpgsql security definer set search_path = '' as $fn$
declare v_op uuid := coalesce(new.operation_id, old.operation_id);
begin
  if exists (
    select 1 from public.purchase_cash_payables as cash
    where cash.operation_id = v_op
  ) and exists (
    select 1 from public.gold_obligations as gold
    where gold.operation_id = v_op
  ) then
    raise exception 'mixed_obligation_unit';
  end if;
  return null;
end;
$fn$;

create constraint trigger purchase_cash_one_unit
after insert or update on public.purchase_cash_payables
deferrable initially immediate
for each row execute function private.enforce_one_obligation_unit();
create constraint trigger gold_obligation_one_unit
after insert or update on public.gold_obligations
deferrable initially immediate
for each row execute function private.enforce_one_obligation_unit();

create function private.inventory_product_id(
  p_shop uuid, p_name text, p_category text, p_karat smallint
) returns uuid language plpgsql security definer set search_path = '' as $fn$
declare v_name text := btrim(p_name); v_id uuid;
begin
  if v_name is null or v_name = '' or char_length(v_name) > 120
    or not private.opening_pair_allowed(p_category, p_karat) then
    raise exception 'invalid_input';
  end if;
  select product.id into v_id from public.inventory_products as product
  where product.shop_id = p_shop and product.category_code = p_category
    and product.karat = p_karat and product.name = v_name;
  if v_id is null then
    insert into public.inventory_products (shop_id, name, category_code, karat)
    values (p_shop, v_name, p_category, p_karat) returning id into v_id;
  end if;
  return v_id;
end;
$fn$;

create function private.lot_remaining(p_lot uuid)
returns table (milligrams bigint, piece_count bigint)
language sql stable security definer set search_path = '' as $fn$
  select coalesce(sum(movement.delta_milligrams), 0)::bigint,
         coalesce(sum(movement.delta_count), 0)::bigint
  from public.inventory_lot_movements as movement
  where movement.lot_id = p_lot;
$fn$;

create function private.add_lot_movement(
  p_shop uuid, p_lot uuid, p_operation uuid,
  p_mg bigint, p_count bigint, p_kind text, p_mode text
) returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_lot public.inventory_lots%rowtype;
  v_mg bigint;
  v_count bigint;
begin
  select * into v_lot from public.inventory_lots where id = p_lot and shop_id = p_shop;
  if v_lot.id is null then raise exception 'not_found'; end if;
  if not v_lot.tracks_count and p_count <> 0 then raise exception 'invalid_input'; end if;
  insert into public.inventory_lot_movements (
    shop_id, lot_id, operation_id, delta_milligrams, delta_count,
    movement_kind, allocation_mode
  ) values (p_shop, p_lot, p_operation, p_mg, p_count, p_kind, p_mode);
  select remaining.milligrams, remaining.piece_count into v_mg, v_count
  from private.lot_remaining(p_lot) as remaining;
  if v_mg < 0 or v_count < 0 then raise exception 'negative_owned_balance'; end if;
  if v_lot.tracks_count and (v_mg = 0) <> (v_count = 0) then
    raise exception 'stock_pair_mismatch';
  end if;
end;
$fn$;

create function private.create_stock_lot(
  p_shop uuid, p_operation uuid, p_name text, p_category text, p_karat smallint,
  p_mg bigint, p_count bigint, p_class text, p_trader uuid, p_legacy boolean,
  p_denom uuid, p_coin uuid, p_kind text, p_mode text
) returns uuid language plpgsql security definer set search_path = '' as $fn$
declare v_product uuid; v_lot uuid; v_count bigint := case when p_category = 'scrap' then 0 else p_count end;
begin
  if p_mg is null or p_mg <= 0 then raise exception 'invalid_input'; end if;
  if p_category = 'scrap' then
    if p_count is not null then raise exception 'invalid_input'; end if;
  elsif p_count is null or p_count <= 0 then
    raise exception 'invalid_input';
  end if;
  if p_denom is not null and (
    p_category <> 'bullion' or not exists (
      select 1 from public.bullion_denominations as denomination
      where denomination.id = p_denom and denomination.shop_id = p_shop
        and denomination.active
    )
  ) then raise exception 'invalid_input'; end if;
  if p_coin is not null and (
    p_category <> 'coin' or not exists (
      select 1 from public.coin_types as coin
      where coin.id = p_coin and coin.shop_id = p_shop and coin.active
    )
  ) then raise exception 'invalid_input'; end if;
  if p_trader is not null and not exists (
    select 1 from public.traders as trader
    where trader.id = p_trader and trader.shop_id = p_shop
  ) then raise exception 'not_found'; end if;
  v_product := private.inventory_product_id(p_shop, p_name, p_category, p_karat);
  insert into public.inventory_lots (
    shop_id, product_id, category_code, karat, display_name,
    original_milligrams, original_count, tracks_count, stock_class, trader_id,
    legacy_aggregate, denomination_id, coin_type_id, origin_operation_id
  ) values (
    p_shop, v_product, p_category, p_karat, btrim(p_name),
    p_mg, p_count, p_category <> 'scrap', p_class, p_trader,
    p_legacy, p_denom, p_coin, case when p_legacy then null else p_operation end
  ) returning id into v_lot;
  perform private.add_lot_movement(
    p_shop, v_lot, case when p_legacy then null else p_operation end,
    p_mg, coalesce(v_count, 0), p_kind, p_mode
  );
  return v_lot;
end;
$fn$;

create function private.consume_named_lot(
  p_shop uuid, p_operation uuid, p_lot uuid, p_mg bigint, p_count bigint,
  p_kind text, p_mode text
) returns void language plpgsql security definer set search_path = '' as $fn$
declare v_lot public.inventory_lots%rowtype;
begin
  perform 1 from public.inventory_lots as lot
  where lot.shop_id = p_shop and lot.id = p_lot for update;
  select * into v_lot from public.inventory_lots where id = p_lot and shop_id = p_shop;
  if v_lot.id is null then raise exception 'not_found'; end if;
  if v_lot.stock_class <> 'owned_available' then raise exception 'insufficient_lot'; end if;
  if p_mg < 0 or p_count < 0 or (p_mg = 0 and p_count = 0) then
    raise exception 'invalid_input';
  end if;
  if not v_lot.tracks_count and p_count <> 0 then raise exception 'invalid_input'; end if;
  perform private.add_lot_movement(
    p_shop, p_lot, p_operation, -p_mg, -p_count, p_kind, p_mode
  );
end;
$fn$;

create function private.consume_fifo(
  p_shop uuid, p_operation uuid, p_category text, p_karat smallint,
  p_mg bigint, p_count bigint, p_kind text
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
    and lot.stock_class = 'owned_available'
  order by lot.id for update;
  for v_lot in
    select lot.id, lot.tracks_count
    from public.inventory_lots as lot
    where lot.shop_id = p_shop and lot.category_code = p_category
      and lot.karat = p_karat and lot.stock_class = 'owned_available'
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

create function private.post_account_delta(
  p_shop uuid, p_operation uuid, p_kind text, p_unit text, p_category text,
  p_karat smallint, p_method text, p_amount bigint, p_clear_kind text,
  p_create boolean
) returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_account uuid;
  v_clear uuid;
  v_journal uuid;
  v_bucket text;
begin
  if p_amount = 0 then return; end if;
  v_account := private.financial_account(
    p_shop, p_kind, p_unit, p_category, p_karat, p_method, p_create or p_amount > 0
  );
  if v_account is null then raise exception 'insufficient_stock'; end if;
  if p_unit = 'money' then
    v_clear := private.financial_account(
      p_shop, p_clear_kind, 'money', null, null, null, true
    );
    v_bucket := 'money';
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, bucket_key
    ) values (p_shop, p_operation, 'money', 'EGP', 'money') returning id into v_journal;
  elsif p_unit = 'gold_mg' then
    v_clear := private.financial_account(
      p_shop, p_clear_kind, 'gold_mg', null, p_karat, null, true
    );
    v_bucket := 'gold:' || p_category || ':' || p_karat::text;
    insert into public.journals (
      shop_id, operation_id, unit_kind, karat, bucket_key
    ) values (p_shop, p_operation, 'gold_mg', p_karat, v_bucket)
    returning id into v_journal;
  else
    v_clear := private.financial_account(
      p_shop, p_clear_kind, 'count', p_category, p_karat, null, true
    );
    v_bucket := 'count:' || p_category || ':' || p_karat::text;
    insert into public.journals (
      shop_id, operation_id, unit_kind, karat, bucket_key
    ) values (p_shop, p_operation, 'count', p_karat, v_bucket)
    returning id into v_journal;
  end if;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values
    (p_shop, v_journal, v_account, p_operation, p_amount),
    (p_shop, v_journal, v_clear, p_operation, -p_amount);
end;
$fn$;

create function private.assert_operation_lots(p_shop uuid, p_operation uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  if exists (
    select 1 from (
      select account.category_code, account.karat, sum(posting.amount) as qty
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where posting.shop_id = p_shop and posting.operation_id = p_operation
        and account.account_kind in ('saleable_metal', 'scrap_metal')
      group by account.category_code, account.karat
    ) as journal
    full join (
      select lot.category_code, lot.karat, sum(movement.delta_milligrams) as qty
      from public.inventory_lot_movements as movement
      join public.inventory_lots as lot
        on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
      where movement.shop_id = p_shop and movement.operation_id = p_operation
        and lot.stock_class = 'owned_available'
      group by lot.category_code, lot.karat
    ) as lots
      on lots.category_code = journal.category_code and lots.karat = journal.karat
    where coalesce(journal.qty, 0) <> coalesce(lots.qty, 0)
  ) or exists (
    select 1 from (
      select account.category_code, account.karat, sum(posting.amount) as qty
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where posting.shop_id = p_shop and posting.operation_id = p_operation
        and account.account_kind = 'saleable_count'
      group by account.category_code, account.karat
    ) as journal
    full join (
      select lot.category_code, lot.karat, sum(movement.delta_count) as qty
      from public.inventory_lot_movements as movement
      join public.inventory_lots as lot
        on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
      where movement.shop_id = p_shop and movement.operation_id = p_operation
        and lot.stock_class = 'owned_available' and lot.tracks_count
      group by lot.category_code, lot.karat
    ) as lots
      on lots.category_code = journal.category_code and lots.karat = journal.karat
    where coalesce(journal.qty, 0) <> coalesce(lots.qty, 0)
  ) then
    raise exception 'lot_journal_mismatch';
  end if;
end;
$fn$;

create function private.assert_shop_lots(p_shop uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  if exists (
    select 1 from (
      select account.category_code, account.karat, sum(posting.amount) as qty
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where posting.shop_id = p_shop
        and account.account_kind in ('saleable_metal', 'scrap_metal')
        and posting.operation_id in (
          select synced.operation_id from public.inventory_lot_sync as synced
          where synced.shop_id = p_shop
        )
      group by account.category_code, account.karat
    ) as journal
    full join (
      select lot.category_code, lot.karat, sum(movement.delta_milligrams) as qty
      from public.inventory_lot_movements as movement
      join public.inventory_lots as lot
        on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
      where lot.shop_id = p_shop and lot.stock_class = 'owned_available'
        and (
          movement.operation_id is null
          or movement.operation_id in (
            select synced.operation_id from public.inventory_lot_sync as synced
            where synced.shop_id = p_shop
          )
        )
      group by lot.category_code, lot.karat
    ) as lots
      on lots.category_code = journal.category_code and lots.karat = journal.karat
    where coalesce(journal.qty, 0) <> coalesce(lots.qty, 0)
  ) or exists (
    select 1 from (
      select account.category_code, account.karat, sum(posting.amount) as qty
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where posting.shop_id = p_shop and account.account_kind = 'saleable_count'
        and posting.operation_id in (
          select synced.operation_id from public.inventory_lot_sync as synced
          where synced.shop_id = p_shop
        )
      group by account.category_code, account.karat
    ) as journal
    full join (
      select lot.category_code, lot.karat, sum(movement.delta_count) as qty
      from public.inventory_lot_movements as movement
      join public.inventory_lots as lot
        on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
      where lot.shop_id = p_shop and lot.stock_class = 'owned_available'
        and lot.tracks_count
        and (
          movement.operation_id is null
          or movement.operation_id in (
            select synced.operation_id from public.inventory_lot_sync as synced
            where synced.shop_id = p_shop
          )
        )
      group by lot.category_code, lot.karat
    ) as lots
      on lots.category_code = journal.category_code and lots.karat = journal.karat
    where coalesce(journal.qty, 0) <> coalesce(lots.qty, 0)
  ) then
    raise exception 'lot_journal_mismatch';
  end if;
end;
$fn$;

create function private.line_milligrams(p_line jsonb)
returns bigint language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_mg bigint;
begin
  v_mg := private.opening_checked_bigint(
    private.opening_parse_amount(p_line ->> 'milligrams'));
  if v_mg <= 0 then raise exception 'invalid_input'; end if;
  return v_mg;
end;
$fn$;

create function private.line_count(p_line jsonb, p_category text)
returns bigint language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if p_category = 'scrap' then return 0; end if;
  if jsonb_typeof(p_line -> 'count') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  return private.opening_checked_bigint(private.opening_parse_amount(p_line ->> 'count'));
end;
$fn$;

create function private.sync_operation_lots(
  p_shop uuid, p_operation uuid, p_assert boolean
) returns void language plpgsql security definer set search_path = '' as $fn$
begin
  if exists (
    select 1 from public.inventory_lot_sync as synced
    where synced.operation_id = p_operation
  ) then
    return;
  end if;
  perform private.apply_operation_lots(p_shop, p_operation);
  perform private.assert_operation_lots(p_shop, p_operation);
  insert into public.inventory_lot_sync (operation_id, shop_id)
  values (p_operation, p_shop);
  if p_assert then
    perform private.assert_shop_lots(p_shop);
  end if;
end;
$fn$;

create function private.apply_operation_lots(p_shop uuid, p_operation uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_payload jsonb;
  v_plan jsonb;
  v_line jsonb;
  v_index integer := 0;
  v_category text;
  v_karat smallint;
  v_mg bigint;
  v_count bigint;
  v_name text;
  v_denom uuid;
  v_coin uuid;
  v_selection jsonb;
  v_lot public.inventory_lots%rowtype;
  v_original uuid;
  v_movement record;
  v_plan_mg bigint;
  v_plan_count bigint;
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
  if v_payload is null then
    select request.payload_canonical into v_payload
    from public.financial_command_requests as request
    where request.shop_id = p_shop and request.operation_id = p_operation;
  end if;
  select plan.plan into v_plan
  from public.financial_command_requests as request
  join public.inventory_explicit_plans as plan
    on plan.shop_id = request.shop_id
   and plan.idempotency_key = request.idempotency_key
  where request.shop_id = p_shop and request.operation_id = p_operation;
  if v_plan is not null and v_kind in ('sale', 'scrap_sale') then
    perform private.lock_lots_ordered(p_shop, (
      select coalesce(array_agg((item.value ->> 'lot_id')::uuid order by (item.value ->> 'lot_id')::uuid), '{}')
      from jsonb_array_elements(coalesce(v_plan -> 'lines', '[]'::jsonb)) as item(value)
      where jsonb_typeof(item.value -> 'lot_id') = 'string'
    ));
  end if;

  if v_kind = 'opening_balances' then
    for v_line in
      select value from jsonb_array_elements(coalesce(v_payload -> 'stock', '[]'::jsonb))
    loop
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      perform private.create_stock_lot(
        p_shop, p_operation, 'رصيد افتتاحي مجمّع', v_category, v_karat,
        private.line_milligrams(v_line), private.line_count(v_line, v_category),
        'owned_available', null, false, null, null, 'opening', 'opening_line'
      );
    end loop;
    for v_line in
      select value from jsonb_array_elements(coalesce(v_payload -> 'scrap', '[]'::jsonb))
    loop
      perform private.create_stock_lot(
        p_shop, p_operation, 'رصيد افتتاحي مجمّع', 'scrap',
        (v_line ->> 'karat')::smallint, private.line_milligrams(v_line), null,
        'owned_available', null, false, null, null, 'opening', 'opening_line'
      );
    end loop;
  elsif v_kind in ('sale', 'scrap_sale') then
    for v_line in
      select value from jsonb_array_elements(coalesce(v_payload -> 'items', '[]'::jsonb))
    loop
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      v_mg := private.line_milligrams(v_line);
      v_count := private.line_count(v_line, v_category);
      if v_plan is not null then
        select item.value into v_selection
        from jsonb_array_elements(v_plan -> 'lines') as item(value)
        where (item.value ->> 'item_index')::integer = v_index;
        if v_selection is null then raise exception 'invalid_input'; end if;
        v_plan_mg := private.opening_checked_bigint(
          private.opening_parse_amount(v_selection ->> 'milligrams'));
        v_plan_count := case when v_category = 'scrap' then 0
          else private.opening_checked_bigint(
            private.opening_parse_amount(v_selection ->> 'count')) end;
        if v_plan_mg <> v_mg or v_plan_count <> v_count then
          raise exception 'invalid_input';
        end if;
        select * into v_lot from public.inventory_lots as lot
        where lot.shop_id = p_shop and lot.id = (v_selection ->> 'lot_id')::uuid;
        if v_lot.id is null or v_lot.category_code <> v_category or v_lot.karat <> v_karat then
          raise exception 'invalid_input';
        end if;
        perform private.consume_named_lot(
          p_shop, p_operation, v_lot.id, v_mg, v_count, v_kind, 'explicit'
        );
      else
        perform private.consume_fifo(
          p_shop, p_operation, v_category, v_karat, v_mg, v_count, v_kind
        );
      end if;
      v_index := v_index + 1;
    end loop;
  elsif v_kind = 'purchase' then
    for v_line in
      select value from jsonb_array_elements(coalesce(v_payload -> 'items', '[]'::jsonb))
    loop
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      v_mg := private.line_milligrams(v_line);
      v_count := private.line_count(v_line, v_category);
      v_name := v_line ->> 'item_name';
      v_denom := null;
      v_coin := null;
      if v_plan is not null then
        select item.value into v_selection
        from jsonb_array_elements(v_plan -> 'lines') as item(value)
        where (item.value ->> 'item_index')::integer = v_index;
        if v_selection is not null and jsonb_typeof(v_selection -> 'denomination_id') = 'string' then
          v_denom := (v_selection ->> 'denomination_id')::uuid;
        end if;
        if v_selection is not null and jsonb_typeof(v_selection -> 'coin_type_id') = 'string' then
          v_coin := (v_selection ->> 'coin_type_id')::uuid;
        end if;
      end if;
      perform private.create_stock_lot(
        p_shop, p_operation, v_name, v_category, v_karat, v_mg,
        case when v_category = 'scrap' then null else v_count end,
        'owned_available', null, false, v_denom, v_coin, 'purchase', 'purchase_line'
      );
      v_index := v_index + 1;
    end loop;
  elsif v_kind = 'scrap_to_stock' then
    v_category := v_payload ->> 'category';
    v_karat := (v_payload ->> 'karat')::smallint;
    v_mg := private.line_milligrams(v_payload);
    v_count := private.opening_checked_bigint(
      private.opening_parse_amount(v_payload ->> 'count'));
    perform private.consume_fifo(
      p_shop, p_operation, 'scrap', v_karat, v_mg, 0, 'conversion_out'
    );
    perform private.create_stock_lot(
      p_shop, p_operation, v_payload ->> 'item_name', v_category, v_karat,
      v_mg, v_count, 'owned_available', null, false, null, null,
      'conversion_in', 'manual'
    );
  elsif v_kind in ('sale_return', 'purchase_return') then
    v_original := (v_payload ->> 'original_operation_id')::uuid;
    if not exists (
      select 1 from public.inventory_lot_movements as movement
      where movement.operation_id = v_original
    ) and not exists (
      select 1 from public.inventory_lot_sync as synced
      where synced.operation_id = v_original
    ) then
      perform private.sync_operation_lots(p_shop, v_original, false);
    end if;
    if exists (
      select 1 from public.inventory_lot_movements as movement
      where movement.operation_id = v_original
    ) then
      for v_movement in
        select movement.lot_id, movement.delta_milligrams, movement.delta_count
        from public.inventory_lot_movements as movement
        where movement.shop_id = p_shop and movement.operation_id = v_original
        order by movement.created_at, movement.id
      loop
        perform private.add_lot_movement(
          p_shop, v_movement.lot_id, p_operation,
          -v_movement.delta_milligrams, -v_movement.delta_count,
          'return', 'return_mirror'
        );
      end loop;
    else
      for v_line in
        select value from jsonb_array_elements(coalesce(v_payload -> 'items', '[]'::jsonb))
      loop
        v_category := v_line ->> 'category';
        v_karat := (v_line ->> 'karat')::smallint;
        v_mg := private.line_milligrams(v_line);
        v_count := private.line_count(v_line, v_category);
        if v_kind = 'sale_return' then
          perform private.create_stock_lot(
            p_shop, p_operation, coalesce(v_line ->> 'item_name', 'مرتجع'),
            v_category, v_karat, v_mg,
            case when v_category = 'scrap' then null else v_count end,
            'owned_available', null, false, null, null, 'return', 'return_mirror'
          );
        else
          perform private.consume_fifo(
            p_shop, p_operation, v_category, v_karat, v_mg, v_count, 'return'
          );
        end if;
      end loop;
    end if;
  end if;
end;
$fn$;

create function private.sync_operation_lots_trigger()
returns trigger language plpgsql security definer set search_path = '' as $fn$
begin
  perform private.sync_operation_lots(new.shop_id, new.operation_id, true);
  return null;
end;
$fn$;

create constraint trigger inventory_sync_request
after insert on public.financial_command_requests
deferrable initially immediate
for each row execute function private.sync_operation_lots_trigger();

create function private.operation_effects(p_shop uuid, p_operation uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_movements jsonb; v_receipt uuid; v_cash bigint; v_gold bigint;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'lot_id', movement.lot_id,
    'delta_milligrams', movement.delta_milligrams::text,
    'delta_count', movement.delta_count::text,
    'movement_kind', movement.movement_kind,
    'allocation_mode', movement.allocation_mode,
    'category', lot.category_code,
    'karat', lot.karat,
    'stock_class', lot.stock_class,
    'legacy_aggregate', lot.legacy_aggregate
  ) order by movement.created_at, movement.id), '[]'::jsonb)
  into v_movements
  from public.inventory_lot_movements as movement
  join public.inventory_lots as lot
    on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
  where movement.shop_id = p_shop and movement.operation_id = p_operation;
  select receipt.id into v_receipt from public.inventory_receipts as receipt
  where receipt.shop_id = p_shop and receipt.operation_id = p_operation;
  select payable.remaining_piastres into v_cash
  from public.purchase_cash_payables as payable
  where payable.shop_id = p_shop and payable.operation_id = p_operation;
  select obligation.remaining_milligrams into v_gold
  from public.gold_obligations as obligation
  where obligation.shop_id = p_shop and obligation.operation_id = p_operation;
  return jsonb_build_object(
    'movements', coalesce(v_movements, '[]'::jsonb),
    'receipt_id', v_receipt,
    'cash_payable_remaining_piastres', v_cash::text,
    'gold_obligation_remaining_milligrams', v_gold::text
  );
end;
$fn$;

create function private.begin_financial_command(
  p_key uuid, p_payload jsonb, p_expected_day uuid, p_expected_version bigint
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_day uuid;
  v_version bigint;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_key is null or p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_key
  for update;
  if found then
    if v_request.payload_canonical = p_payload and v_request.payload_sha256 = v_hash then
      return jsonb_build_object(
        'replay', true, 'operation_id', v_request.operation_id, 'shop_id', v_shop
      );
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if p_expected_day is null or p_expected_version is null
    or v_day is distinct from p_expected_day
    or v_version is distinct from p_expected_version then
    raise exception 'stale_day';
  end if;
  return jsonb_build_object(
    'replay', false,
    'shop_id', v_shop,
    'day_id', v_day,
    'day_version', v_version,
    'actor', auth.uid(),
    'at', pg_catalog.clock_timestamp()
  );
end;
$fn$;

create function private.insert_operation(
  p_shop uuid, p_kind text, p_day uuid, p_actor uuid, p_at timestamptz, p_payload jsonb
) returns uuid language plpgsql security definer set search_path = '' as $fn$
declare v_sequence bigint; v_operation uuid;
begin
  select coalesce(max(operation.shop_sequence), 0) + 1 into v_sequence
  from public.financial_operations as operation where operation.shop_id = p_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (p_shop, v_sequence, p_kind, p_day, p_actor, p_at)
  returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_operation, p_shop, p_payload, p_at);
  return v_operation;
end;
$fn$;

create function private.finish_financial_command(
  p_shop uuid, p_operation uuid, p_actor uuid, p_at timestamptz, p_day uuid,
  p_action text, p_key uuid, p_payload jsonb, p_audit jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_hash bytea; v_version bigint;
begin
  update public.business_days set day_version = day_version + 1
  where id = p_day and shop_id = p_shop
  returning day_version into v_version;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (p_shop, p_actor, p_action, p_operation, p_at, p_audit);
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (p_shop, p_operation, p_action, p_at);
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (p_shop, p_key, p_payload, v_hash, p_operation, p_at);
  perform private.sync_operation_lots(p_shop, p_operation, true);
  return jsonb_build_object(
    'ok', true,
    'operation_id', p_operation,
    'business_day_id', p_day,
    'day_version', v_version,
    'replayed', false,
    'effects', private.operation_effects(p_shop, p_operation)
  );
end;
$fn$;

create function private.parse_expected_day(p_payload jsonb)
returns uuid language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_day uuid;
begin
  if jsonb_typeof(p_payload -> 'expected_day_id') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  begin
    v_day := (p_payload ->> 'expected_day_id')::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_input';
  end;
  return v_day;
end;
$fn$;

create function private.parse_expected_version(p_payload jsonb)
returns bigint language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if jsonb_typeof(p_payload -> 'expected_day_version') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  return private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'expected_day_version'));
end;
$fn$;

create function private.require_reason(p_payload jsonb)
returns text language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_reason text;
begin
  if jsonb_typeof(p_payload -> 'reason') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_reason := btrim(p_payload ->> 'reason');
  if v_reason is null or v_reason = '' or char_length(p_payload ->> 'reason') > 1000 then
    raise exception 'invalid_input';
  end if;
  return v_reason;
end;
$fn$;

create function private.replay_or_gate(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_gate jsonb;
begin
  if p_payload -> 'version' is distinct from '1'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_gate := private.begin_financial_command(
    p_key, p_payload,
    private.parse_expected_day(p_payload),
    private.parse_expected_version(p_payload)
  );
  if v_gate ->> 'replay' = 'true' then
    return jsonb_build_object(
      'ok', true,
      'operation_id', v_gate ->> 'operation_id',
      'replayed', true,
      'effects', private.operation_effects(
        (v_gate ->> 'shop_id')::uuid, (v_gate ->> 'operation_id')::uuid)
    );
  end if;
  return v_gate;
end;
$fn$;

create function private.uuid_or_null(p_value jsonb)
returns uuid language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_id uuid;
begin
  if p_value is null or p_value = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p_value) <> 'string' then raise exception 'invalid_input'; end if;
  begin
    v_id := (p_value #>> '{}')::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_input';
  end;
  return v_id;
end;
$fn$;

create function private.require_shop_trader(p_shop uuid, p_trader uuid)
returns uuid language plpgsql security definer set search_path = '' as $fn$
begin
  if p_trader is null then return null; end if;
  if not exists (
    select 1 from public.traders as trader
    where trader.shop_id = p_shop and trader.id = p_trader and trader.active
  ) then
    raise exception 'not_found';
  end if;
  return p_trader;
end;
$fn$;

create function private.post_inventory_command(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_kind text;
  v_gate jsonb;
  v_shop uuid;
  v_day uuid;
  v_actor uuid;
  v_at timestamptz;
  v_operation uuid;
  v_line jsonb;
  v_lot public.inventory_lots%rowtype;
  v_mg bigint;
  v_count bigint;
  v_signed_mg bigint;
  v_signed_count bigint;
  v_method text;
  v_seen text[] := '{}';
  v_amount bigint;
  v_category text;
  v_karat smallint;
  v_source public.inventory_lots%rowtype;
  v_dest_count bigint;
  v_source_count bigint;
  v_effects integer := 0;
  v_ids uuid[] := '{}';
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
  v_kind := p_payload ->> 'kind';
  if v_kind = 'inventory_addition' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'reason' - 'lines' <> '{}'::jsonb
      or jsonb_typeof(p_payload -> 'lines') <> 'array'
      or jsonb_array_length(p_payload -> 'lines') not between 1 and 50 then
      raise exception 'invalid_input';
    end if;
  elsif v_kind = 'inventory_removal' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'reason' - 'lines' <> '{}'::jsonb
      or jsonb_typeof(p_payload -> 'lines') <> 'array'
      or jsonb_array_length(p_payload -> 'lines') not between 1 and 50 then
      raise exception 'invalid_input';
    end if;
  elsif v_kind = 'inventory_correction' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'reason' - 'cash_deltas' - 'metal_deltas' <> '{}'::jsonb
      or jsonb_typeof(p_payload -> 'cash_deltas') <> 'array'
      or jsonb_typeof(p_payload -> 'metal_deltas') <> 'array'
      or jsonb_array_length(p_payload -> 'cash_deltas') > 4
      or jsonb_array_length(p_payload -> 'metal_deltas') > 50 then
      raise exception 'invalid_input';
    end if;
  elsif v_kind = 'inventory_conversion' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'reason' - 'karat' - 'milligrams' - 'source_category' - 'source_lot_id'
      - 'source_count' - 'destination_category' - 'destination_count' - 'item_name'
      <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  perform private.require_reason(p_payload);
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  v_operation := private.insert_operation(
    v_shop, v_kind, v_day, v_actor, v_at, p_payload
  );

  if v_kind in ('inventory_removal', 'inventory_correction') then
    for v_line in select value from jsonb_array_elements(
      case when v_kind = 'inventory_removal' then p_payload -> 'lines'
        else p_payload -> 'metal_deltas' end
    ) loop
      if jsonb_typeof(v_line) = 'object' and v_line ? 'lot_id' then
        v_ids := array_append(v_ids, private.uuid_or_null(v_line -> 'lot_id'));
      end if;
    end loop;
    if cardinality(v_ids) > 0 then
      perform private.lock_lots_ordered(v_shop, v_ids);
    end if;
  elsif v_kind = 'inventory_conversion' then
    perform private.lock_lots_ordered(
      v_shop, array[private.uuid_or_null(p_payload -> 'source_lot_id')]
    );
  end if;

  if v_kind = 'inventory_addition' then
    for v_line in select value from jsonb_array_elements(p_payload -> 'lines')
    loop
      if jsonb_typeof(v_line) <> 'object'
        or v_line - 'item_name' - 'category' - 'karat' - 'milligrams' - 'count'
          - 'denomination_id' - 'coin_type_id' <> '{}'::jsonb
        or jsonb_typeof(v_line -> 'item_name') <> 'string'
        or jsonb_typeof(v_line -> 'category') <> 'string'
        or jsonb_typeof(v_line -> 'karat') <> 'number'
        or jsonb_typeof(v_line -> 'milligrams') <> 'string' then
        raise exception 'invalid_input';
      end if;
      v_category := v_line ->> 'category';
      v_karat := (v_line ->> 'karat')::smallint;
      if not private.opening_pair_allowed(v_category, v_karat) then
        raise exception 'unsupported_category_karat';
      end if;
      v_mg := private.line_milligrams(v_line);
      if v_category = 'scrap' then
        if v_line -> 'count' <> 'null'::jsonb then raise exception 'invalid_input'; end if;
        v_count := null;
      else
        v_count := private.line_count(v_line, v_category);
        if v_count <= 0 then raise exception 'invalid_input'; end if;
      end if;
      perform private.create_stock_lot(
        v_shop, v_operation, v_line ->> 'item_name', v_category, v_karat, v_mg, v_count,
        'owned_available', null, false,
        private.uuid_or_null(v_line -> 'denomination_id'),
        private.uuid_or_null(v_line -> 'coin_type_id'),
        'addition', 'manual'
      );
      perform private.post_account_delta(
        v_shop, v_operation,
        case when v_category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
        'gold_mg', v_category, v_karat, null, v_mg, 'adjustment_gold_clearing', true
      );
      if v_category <> 'scrap' then
        perform private.post_account_delta(
          v_shop, v_operation, 'saleable_count', 'count', v_category, v_karat, null,
          v_count, 'adjustment_count_clearing', true
        );
      end if;
    end loop;
  elsif v_kind = 'inventory_removal' then
    for v_line in select value from jsonb_array_elements(p_payload -> 'lines')
    loop
      if jsonb_typeof(v_line) <> 'object'
        or v_line - 'lot_id' - 'milligrams' - 'count' <> '{}'::jsonb then
        raise exception 'invalid_input';
      end if;
      select * into v_lot from public.inventory_lots as lot
      where lot.shop_id = v_shop and lot.id = private.uuid_or_null(v_line -> 'lot_id')
      for update;
      if v_lot.id is null then raise exception 'not_found'; end if;
      v_mg := private.line_milligrams(v_line);
      if v_lot.category_code = 'scrap' then
        if v_line -> 'count' <> 'null'::jsonb then raise exception 'invalid_input'; end if;
        v_count := 0;
      else
        v_count := private.line_count(v_line, v_lot.category_code);
      end if;
      perform private.consume_named_lot(
        v_shop, v_operation, v_lot.id, v_mg, v_count, 'removal', 'explicit'
      );
      perform private.post_account_delta(
        v_shop, v_operation,
        case when v_lot.category_code = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
        'gold_mg', v_lot.category_code, v_lot.karat, null, -v_mg,
        'adjustment_gold_clearing', false
      );
      if v_lot.tracks_count then
        perform private.post_account_delta(
          v_shop, v_operation, 'saleable_count', 'count', v_lot.category_code,
          v_lot.karat, null, -v_count, 'adjustment_count_clearing', false
        );
      end if;
    end loop;
  elsif v_kind = 'inventory_correction' then
    for v_line in select value from jsonb_array_elements(p_payload -> 'cash_deltas')
    loop
      if jsonb_typeof(v_line) <> 'object'
        or v_line - 'method' - 'piastres' <> '{}'::jsonb
        or jsonb_typeof(v_line -> 'method') <> 'string'
        or jsonb_typeof(v_line -> 'piastres') <> 'string' then
        raise exception 'invalid_input';
      end if;
      v_method := v_line ->> 'method';
      if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
        or v_method = any (v_seen) then
        raise exception 'invalid_input';
      end if;
      v_seen := array_append(v_seen, v_method);
      v_amount := private.checked_signed_bigint(
        private.parse_signed_amount(v_line ->> 'piastres'));
      if v_amount = 0 then raise exception 'invalid_input'; end if;
      perform private.post_account_delta(
        v_shop, v_operation, 'cash_method', 'money', null, null, v_method,
        v_amount, 'adjustment_money_clearing', false
      );
      v_effects := v_effects + 1;
    end loop;
    for v_line in select value from jsonb_array_elements(p_payload -> 'metal_deltas')
    loop
      if jsonb_typeof(v_line) <> 'object' then raise exception 'invalid_input'; end if;
      if v_line ? 'lot_id' then
        if v_line - 'lot_id' - 'milligrams' - 'count' <> '{}'::jsonb
          or jsonb_typeof(v_line -> 'milligrams') <> 'string' then
          raise exception 'invalid_input';
        end if;
        select * into v_lot from public.inventory_lots as lot
        where lot.shop_id = v_shop and lot.id = private.uuid_or_null(v_line -> 'lot_id')
        for update;
        if v_lot.id is null or v_lot.stock_class <> 'owned_available' then
          raise exception 'not_found';
        end if;
        v_signed_mg := private.checked_signed_bigint(
          private.parse_signed_amount(v_line ->> 'milligrams'));
        if v_lot.tracks_count then
          if jsonb_typeof(v_line -> 'count') <> 'string' then
            raise exception 'invalid_input';
          end if;
          v_signed_count := private.checked_signed_bigint(
            private.parse_signed_amount(v_line ->> 'count'));
        else
          if v_line -> 'count' <> 'null'::jsonb then raise exception 'invalid_input'; end if;
          v_signed_count := 0;
        end if;
        -- Named lots only decrease. An increase is a new lot on its own line.
        -- Piece corrections move milligrams and count in the same direction.
        if v_signed_mg > 0 or v_signed_count > 0
          or (v_signed_mg = 0 and v_signed_count = 0)
          or (v_lot.tracks_count and (v_signed_mg = 0 or v_signed_count = 0)) then
          raise exception 'invalid_input';
        end if;
        perform private.consume_named_lot(
          v_shop, v_operation, v_lot.id,
          -v_signed_mg, -v_signed_count, 'correction', 'explicit'
        );
        perform private.post_account_delta(
          v_shop, v_operation,
          case when v_lot.category_code = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
          'gold_mg', v_lot.category_code, v_lot.karat, null, v_signed_mg,
          'adjustment_gold_clearing', v_signed_mg > 0
        );
        if v_lot.tracks_count then
          perform private.post_account_delta(
            v_shop, v_operation, 'saleable_count', 'count', v_lot.category_code,
            v_lot.karat, null, v_signed_count, 'adjustment_count_clearing',
            v_signed_count > 0
          );
        end if;
      else
        if v_line - 'item_name' - 'category' - 'karat' - 'milligrams' - 'count'
          <> '{}'::jsonb then
          raise exception 'invalid_input';
        end if;
        v_category := v_line ->> 'category';
        v_karat := (v_line ->> 'karat')::smallint;
        if not private.opening_pair_allowed(v_category, v_karat) then
          raise exception 'unsupported_category_karat';
        end if;
        v_mg := private.line_milligrams(v_line);
        v_count := case when v_category = 'scrap' then null
          else private.line_count(v_line, v_category) end;
        perform private.create_stock_lot(
          v_shop, v_operation, v_line ->> 'item_name', v_category, v_karat,
          v_mg, v_count, 'owned_available', null, false, null, null,
          'correction', 'manual'
        );
        perform private.post_account_delta(
          v_shop, v_operation,
          case when v_category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
          'gold_mg', v_category, v_karat, null, v_mg, 'adjustment_gold_clearing', true
        );
        if v_category <> 'scrap' then
          perform private.post_account_delta(
            v_shop, v_operation, 'saleable_count', 'count', v_category, v_karat,
            null, v_count, 'adjustment_count_clearing', true
          );
        end if;
      end if;
      v_effects := v_effects + 1;
    end loop;
    if v_effects = 0 then raise exception 'invalid_input'; end if;
  else
    if jsonb_typeof(p_payload -> 'karat') <> 'number'
      or jsonb_typeof(p_payload -> 'milligrams') <> 'string'
      or jsonb_typeof(p_payload -> 'source_category') <> 'string'
      or jsonb_typeof(p_payload -> 'destination_category') <> 'string'
      or jsonb_typeof(p_payload -> 'item_name') <> 'string'
      or nullif(btrim(p_payload ->> 'item_name'), '') is null
      or char_length(p_payload ->> 'item_name') > 120 then
      raise exception 'invalid_input';
    end if;
    v_karat := (p_payload ->> 'karat')::smallint;
    v_mg := private.line_milligrams(p_payload);
    v_category := p_payload ->> 'destination_category';
    if p_payload ->> 'source_category' = v_category
      or not private.opening_pair_allowed(p_payload ->> 'source_category', v_karat)
      or not private.opening_pair_allowed(v_category, v_karat) then
      raise exception 'unsupported_category_karat';
    end if;
    select * into v_source from public.inventory_lots as lot
    where lot.shop_id = v_shop
      and lot.id = private.uuid_or_null(p_payload -> 'source_lot_id')
    for update;
    if v_source.id is null or v_source.stock_class <> 'owned_available'
      or v_source.category_code <> p_payload ->> 'source_category'
      or v_source.karat <> v_karat then
      raise exception 'not_found';
    end if;
    if v_source.category_code = 'scrap' then
      if p_payload -> 'source_count' <> 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
      v_source_count := 0;
    else
      if jsonb_typeof(p_payload -> 'source_count') is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_source_count := private.opening_checked_bigint(
        private.opening_parse_amount(p_payload ->> 'source_count'));
      if v_source_count <= 0 then raise exception 'invalid_input'; end if;
    end if;
    if v_category = 'scrap' then
      if p_payload -> 'destination_count' <> 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
      v_dest_count := null;
    else
      if jsonb_typeof(p_payload -> 'destination_count') is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      v_dest_count := private.opening_checked_bigint(
        private.opening_parse_amount(p_payload ->> 'destination_count'));
      if v_dest_count <= 0 then raise exception 'invalid_input'; end if;
    end if;
    perform private.consume_named_lot(
      v_shop, v_operation, v_source.id, v_mg, v_source_count, 'conversion_out', 'explicit'
    );
    perform private.create_stock_lot(
      v_shop, v_operation, p_payload ->> 'item_name', v_category, v_karat, v_mg,
      v_dest_count, 'owned_available', null, false, null, null,
      'conversion_in', 'manual'
    );
    perform private.post_account_delta(
      v_shop, v_operation,
      case when v_source.category_code = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
      'gold_mg', v_source.category_code, v_karat, null, -v_mg,
      'adjustment_gold_clearing', false
    );
    perform private.post_account_delta(
      v_shop, v_operation,
      case when v_category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
      'gold_mg', v_category, v_karat, null, v_mg, 'adjustment_gold_clearing', true
    );
    if v_source.tracks_count then
      perform private.post_account_delta(
        v_shop, v_operation, 'saleable_count', 'count', v_source.category_code,
        v_karat, null, -v_source_count, 'adjustment_count_clearing', false
      );
    end if;
    if v_category <> 'scrap' then
      perform private.post_account_delta(
        v_shop, v_operation, 'saleable_count', 'count', v_category, v_karat, null,
        v_dest_count, 'adjustment_count_clearing', true
      );
    end if;
  end if;

  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, v_kind || '_confirmed',
    p_key, p_payload,
    jsonb_build_object('operation_id', v_operation, 'business_day_id', v_day, 'kind', v_kind)
  );
end;
$fn$;

create function private.receipt_remaining(p_receipt uuid)
returns table (milligrams bigint, piece_count bigint)
language sql stable security definer set search_path = '' as $fn$
  select receipt.milligrams - coalesce(sum(allocation.milligrams), 0)::bigint,
         case when receipt.piece_count is null then null
           else receipt.piece_count - coalesce(sum(allocation.piece_count), 0)::bigint end
  from public.inventory_receipts as receipt
  left join public.receipt_quantity_allocations as allocation
    on allocation.receipt_id = receipt.id
  where receipt.id = p_receipt
  group by receipt.milligrams, receipt.piece_count;
$fn$;

create function private.assert_receipt_bounds(p_receipt uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
declare v_mg bigint; v_count bigint;
begin
  select remaining.milligrams, remaining.piece_count into v_mg, v_count
  from private.receipt_remaining(p_receipt) as remaining;
  if v_mg < 0 or coalesce(v_count, 0) < 0 then
    raise exception 'already_allocated';
  end if;
end;
$fn$;

create function public.post_inventory_addition_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_addition' then
    raise exception 'invalid_input';
  end if;
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_inventory_removal_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_removal' then
    raise exception 'invalid_input';
  end if;
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_inventory_correction_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_correction' then
    raise exception 'invalid_input';
  end if;
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_inventory_conversion_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'inventory_conversion' then
    raise exception 'invalid_input';
  end if;
  return private.post_inventory_command(p_idempotency_key, p_payload);
end;
$fn$;

create function private.category_quantity(
  p_object jsonb, p_category text, p_mg_key text, p_count_key text
) returns table (milligrams bigint, piece_count bigint)
language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_mg bigint; v_count bigint;
begin
  if jsonb_typeof(p_object -> p_mg_key) is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_mg := private.opening_checked_bigint(
    private.opening_parse_amount(p_object ->> p_mg_key));
  if v_mg <= 0 then raise exception 'invalid_input'; end if;
  if p_category = 'scrap' then
    if p_object -> p_count_key is distinct from 'null'::jsonb then
      raise exception 'invalid_input';
    end if;
    v_count := null;
  else
    if jsonb_typeof(p_object -> p_count_key) is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_count := private.opening_checked_bigint(
      private.opening_parse_amount(p_object ->> p_count_key));
    if v_count <= 0 then raise exception 'invalid_input'; end if;
  end if;
  return query select v_mg, v_count;
end;
$fn$;

create function private.validated_tender_sum(p_tenders jsonb)
returns numeric language plpgsql stable security invoker set search_path = '' as $fn$
declare
  v_tender jsonb;
  v_seen text[] := '{}';
  v_method text;
  v_amount bigint;
  v_sum numeric := 0;
begin
  if jsonb_typeof(p_tenders) is distinct from 'array'
    or jsonb_array_length(p_tenders) > 4 then
    raise exception 'invalid_input';
  end if;
  for v_tender in select value from jsonb_array_elements(p_tenders) loop
    if jsonb_typeof(v_tender) is distinct from 'object'
      or v_tender - 'method' - 'piastres' <> '{}'::jsonb
      or jsonb_typeof(v_tender -> 'method') is distinct from 'string'
      or jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any (v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_amount <= 0 then raise exception 'invalid_input'; end if;
    v_sum := v_sum + v_amount;
  end loop;
  return v_sum;
end;
$fn$;

create function private.lock_receipt(p_shop uuid, p_receipt uuid)
returns public.inventory_receipts
language plpgsql security definer set search_path = '' as $fn$
declare v_row public.inventory_receipts%rowtype;
begin
  select * into v_row from public.inventory_receipts as receipt
  where receipt.shop_id = p_shop and receipt.id = p_receipt
  for update;
  if v_row.id is null then raise exception 'not_found'; end if;
  return v_row;
end;
$fn$;

create function private.lock_lots_ordered(p_shop uuid, p_ids uuid[])
returns void language plpgsql security definer set search_path = '' as $fn$
begin
  perform 1 from public.inventory_lots as lot
  where lot.shop_id = p_shop and lot.id = any (p_ids)
  order by lot.id
  for update;
end;
$fn$;

create function private.take_receipt_quantity(
  p_receipt uuid, p_category text, p_mg bigint, p_count bigint
) returns void language plpgsql security definer set search_path = '' as $fn$
declare v_rem_mg bigint; v_rem_count bigint; v_left_mg bigint; v_left_count bigint;
begin
  select remaining.milligrams, remaining.piece_count into v_rem_mg, v_rem_count
  from private.receipt_remaining(p_receipt) as remaining;
  if p_category = 'scrap' then
    if p_mg > v_rem_mg then raise exception 'already_allocated'; end if;
  else
    if p_count is null or v_rem_count is null then raise exception 'invalid_input'; end if;
    v_left_mg := v_rem_mg - p_mg;
    v_left_count := v_rem_count - p_count;
    if v_left_mg < 0 or v_left_count < 0 then raise exception 'already_allocated'; end if;
    if (v_left_mg = 0) <> (v_left_count = 0) then
      raise exception 'stock_pair_mismatch';
    end if;
  end if;
end;
$fn$;

create function private.insert_receipt_allocation(
  p_shop uuid, p_receipt uuid, p_operation uuid, p_kind text,
  p_mg bigint, p_count bigint, p_linked uuid
) returns void language plpgsql security definer set search_path = '' as $fn$
begin
  insert into public.receipt_quantity_allocations (
    shop_id, receipt_id, operation_id, allocation_kind,
    milligrams, piece_count, linked_lot_id
  ) values (
    p_shop, p_receipt, p_operation, p_kind, p_mg, p_count, p_linked
  );
  perform private.assert_receipt_bounds(p_receipt);
end;
$fn$;

create function private.post_owned_increase(
  p_shop uuid, p_operation uuid, p_category text, p_karat smallint,
  p_mg bigint, p_count bigint, p_clear text
) returns void language plpgsql security definer set search_path = '' as $fn$
begin
  perform private.post_account_delta(
    p_shop, p_operation,
    case when p_category = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
    'gold_mg', p_category, p_karat, null, p_mg, p_clear || '_gold_clearing', true
  );
  if p_category <> 'scrap' then
    perform private.post_account_delta(
      p_shop, p_operation, 'saleable_count', 'count', p_category, p_karat, null,
      p_count, p_clear || '_count_clearing', true
    );
  end if;
end;
$fn$;

create function private.post_cash_payment(
  p_shop uuid, p_operation uuid, p_tenders jsonb
) returns void language plpgsql security definer set search_path = '' as $fn$
declare v_tender jsonb; v_amount bigint; v_account uuid;
begin
  for v_tender in select value from jsonb_array_elements(p_tenders) loop
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    v_account := private.financial_account(
      p_shop, 'cash_method', 'money', null, null, v_tender ->> 'method', false
    );
    if v_account is null then raise exception 'invalid_input'; end if;
    perform private.post_account_delta(
      p_shop, p_operation, 'cash_method', 'money', null, null,
      v_tender ->> 'method', -v_amount, 'movement_money_clearing', false
    );
  end loop;
end;
$fn$;

create function private.post_inventory_receipt(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_day uuid; v_actor uuid; v_at timestamptz;
  v_operation uuid; v_owner text; v_policy text; v_trader uuid;
  v_category text; v_karat smallint; v_mg bigint; v_count bigint;
  v_class text; v_mode text; v_lot uuid; v_product uuid; v_receipt uuid;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'kind' is distinct from 'inventory_receipt'
    or p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'owner_kind' - 'trader_id' - 'counterparty_name' - 'product_name'
      - 'category' - 'karat' - 'milligrams' - 'count' - 'recognition'
      - 'denomination_id' - 'coin_type_id' - 'note' <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'owner_kind') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'counterparty_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'product_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'category') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'karat') is distinct from 'number'
    or jsonb_typeof(p_payload -> 'recognition') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'note') is distinct from 'string'
    or char_length(p_payload ->> 'note') > 1000
    or nullif(btrim(p_payload ->> 'counterparty_name'), '') is null
    or char_length(p_payload ->> 'counterparty_name') > 200
    or p_payload ->> 'counterparty_name' is distinct from btrim(p_payload ->> 'counterparty_name')
    or nullif(btrim(p_payload ->> 'product_name'), '') is null
    or char_length(p_payload ->> 'product_name') > 120
    or p_payload ->> 'product_name' is distinct from btrim(p_payload ->> 'product_name') then
    raise exception 'invalid_input';
  end if;
  v_owner := p_payload ->> 'owner_kind';
  v_policy := p_payload ->> 'recognition';
  v_category := p_payload ->> 'category';
  v_karat := (p_payload ->> 'karat')::smallint;
  if not private.opening_pair_allowed(v_category, v_karat) then
    raise exception 'unsupported_category_karat';
  end if;
  if v_owner not in ('shop', 'trader')
    or v_policy not in ('immediate', 'deferred', 'custody')
    or (v_owner = 'trader') <> (v_policy = 'custody') then
    raise exception 'invalid_input';
  end if;
  if v_owner = 'trader' then
    v_trader := private.uuid_or_null(p_payload -> 'trader_id');
    if v_trader is null then raise exception 'invalid_input'; end if;
  elsif p_payload ? 'trader_id' and p_payload -> 'trader_id' is distinct from 'null'::jsonb then
    raise exception 'invalid_input';
  end if;
  select quantity.milligrams, quantity.piece_count into v_mg, v_count
  from private.category_quantity(p_payload, v_category, 'milligrams', 'count') as quantity;
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  if v_trader is not null and not exists (
    select 1 from public.traders as trader
    where trader.id = v_trader and trader.shop_id = v_shop and trader.active
  ) then
    raise exception 'not_found';
  end if;
  v_operation := private.insert_operation(
    v_shop, 'inventory_receipt', v_day, v_actor, v_at, p_payload
  );
  v_class := case v_policy
    when 'immediate' then 'owned_available'
    when 'deferred' then 'owned_pending'
    else 'trader_custody' end;
  v_mode := case when v_policy = 'custody' then 'custody_receipt' else 'manual' end;
  v_lot := private.create_stock_lot(
    v_shop, v_operation, p_payload ->> 'product_name', v_category, v_karat,
    v_mg, v_count, v_class, v_trader, false,
    private.uuid_or_null(p_payload -> 'denomination_id'),
    private.uuid_or_null(p_payload -> 'coin_type_id'),
    'receipt', v_mode
  );
  select lot.product_id into v_product from public.inventory_lots as lot
  where lot.id = v_lot;
  insert into public.inventory_receipts (
    shop_id, owner_kind, trader_id, custodian_kind, counterparty_name,
    product_id, lot_id, category_code, karat, milligrams, piece_count,
    received_at, operation_id, recognition_policy
  ) values (
    v_shop, v_owner, v_trader, 'shop', p_payload ->> 'counterparty_name',
    v_product, v_lot, v_category, v_karat, v_mg, v_count,
    v_at, v_operation, v_policy
  ) returning id into v_receipt;
  if v_policy = 'immediate' then
    perform private.post_owned_increase(
      v_shop, v_operation, v_category, v_karat, v_mg, v_count, 'movement'
    );
    perform private.insert_receipt_allocation(
      v_shop, v_receipt, v_operation, 'recognize', v_mg, v_count, v_lot
    );
  end if;
  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, 'inventory_receipt_confirmed',
    p_key, p_payload,
    jsonb_build_object('operation_id', v_operation, 'receipt_id', v_receipt)
  );
end;
$fn$;

create function private.spawn_owned_from_source(
  p_shop uuid, p_operation uuid, p_source public.inventory_lots,
  p_mg bigint, p_count bigint, p_kind text, p_mode text
) returns uuid language plpgsql security definer set search_path = '' as $fn$
declare v_name text;
begin
  select product.name into v_name from public.inventory_products as product
  where product.shop_id = p_shop and product.id = p_source.product_id;
  return private.create_stock_lot(
    p_shop, p_operation, v_name, p_source.category_code, p_source.karat,
    p_mg, p_count, 'owned_available', null, false,
    p_source.denomination_id, p_source.coin_type_id, p_kind, p_mode
  );
end;
$fn$;

create function private.post_inventory_recognition(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_day uuid; v_actor uuid; v_at timestamptz;
  v_operation uuid; v_receipt public.inventory_receipts%rowtype;
  v_source public.inventory_lots%rowtype; v_mg bigint; v_count bigint;
  v_move_count bigint; v_new uuid;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'kind' is distinct from 'inventory_recognition'
    or p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'receipt_id' - 'milligrams' - 'count' - 'reason' <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  perform private.require_reason(p_payload);
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  v_receipt := private.lock_receipt(v_shop, private.uuid_or_null(p_payload -> 'receipt_id'));
  if v_receipt.recognition_policy = 'custody' then
    raise exception 'custody_requires_transfer';
  end if;
  if v_receipt.recognition_policy is distinct from 'deferred'
    or v_receipt.owner_kind is distinct from 'shop' then
    raise exception 'invalid_input';
  end if;
  select quantity.milligrams, quantity.piece_count into v_mg, v_count
  from private.category_quantity(
    p_payload, v_receipt.category_code, 'milligrams', 'count'
  ) as quantity;
  perform private.take_receipt_quantity(
    v_receipt.id, v_receipt.category_code, v_mg, v_count
  );
  perform private.lock_lots_ordered(v_shop, array[v_receipt.lot_id]);
  select * into v_source from public.inventory_lots as lot
  where lot.shop_id = v_shop and lot.id = v_receipt.lot_id;
  if v_source.stock_class is distinct from 'owned_pending' then
    raise exception 'invalid_input';
  end if;
  v_operation := private.insert_operation(
    v_shop, 'inventory_recognition', v_day, v_actor, v_at, p_payload
  );
  v_move_count := case when v_receipt.category_code = 'scrap' then 0 else v_count end;
  perform private.add_lot_movement(
    v_shop, v_source.id, v_operation, -v_mg, -v_move_count,
    'recognition_out', 'recognition'
  );
  v_new := private.spawn_owned_from_source(
    v_shop, v_operation, v_source, v_mg, v_count, 'recognition_in', 'recognition'
  );
  perform private.post_owned_increase(
    v_shop, v_operation, v_source.category_code, v_source.karat, v_mg, v_count, 'movement'
  );
  perform private.insert_receipt_allocation(
    v_shop, v_receipt.id, v_operation, 'recognize', v_mg, v_count, v_new
  );
  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, 'inventory_recognition_confirmed',
    p_key, p_payload,
    jsonb_build_object('operation_id', v_operation, 'receipt_id', v_receipt.id)
  );
end;
$fn$;

create function private.post_ownership_transfer(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_day uuid; v_actor uuid; v_at timestamptz;
  v_operation uuid; v_receipt public.inventory_receipts%rowtype;
  v_source public.inventory_lots%rowtype; v_mg bigint; v_count bigint;
  v_move_count bigint; v_new uuid; v_has_cash boolean; v_has_gold boolean;
  v_price bigint; v_tender_sum numeric; v_payable bigint; v_gold_mg bigint;
  v_gold_karat smallint;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'kind' is distinct from 'ownership_transfer'
    or p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'receipt_id' - 'milligrams' - 'count' - 'reason' - 'price_piastres'
      - 'tenders' - 'purchase_obligation_piastres' - 'obligation_karat'
      - 'obligation_milligrams' <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  perform private.require_reason(p_payload);
  v_has_cash := p_payload ? 'price_piastres' or p_payload ? 'tenders'
    or p_payload ? 'purchase_obligation_piastres';
  v_has_gold := p_payload ? 'obligation_milligrams' or p_payload ? 'obligation_karat';
  if v_has_cash = v_has_gold then raise exception 'invalid_input'; end if;
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  v_receipt := private.lock_receipt(v_shop, private.uuid_or_null(p_payload -> 'receipt_id'));
  if v_receipt.recognition_policy is distinct from 'custody'
    or v_receipt.owner_kind is distinct from 'trader' then
    raise exception 'invalid_input';
  end if;
  select quantity.milligrams, quantity.piece_count into v_mg, v_count
  from private.category_quantity(
    p_payload, v_receipt.category_code, 'milligrams', 'count'
  ) as quantity;
  perform private.take_receipt_quantity(
    v_receipt.id, v_receipt.category_code, v_mg, v_count
  );
  if v_has_cash then
    if jsonb_typeof(p_payload -> 'price_piastres') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'tenders') is distinct from 'array' then
      raise exception 'invalid_input';
    end if;
    v_price := private.opening_checked_bigint(
      private.opening_parse_amount(p_payload ->> 'price_piastres'));
    if v_price <= 0 then raise exception 'invalid_input'; end if;
    v_tender_sum := private.validated_tender_sum(p_payload -> 'tenders');
    if v_tender_sum > v_price then raise exception 'tender_mismatch'; end if;
    v_payable := private.opening_checked_bigint(v_price - v_tender_sum);
    if v_payable > 0 then
      if jsonb_typeof(p_payload -> 'purchase_obligation_piastres') is distinct from 'string'
        or private.opening_checked_bigint(private.opening_parse_amount(
          p_payload ->> 'purchase_obligation_piastres')) <> v_payable then
        raise exception 'invalid_input';
      end if;
    elsif p_payload ? 'purchase_obligation_piastres' then
      raise exception 'invalid_input';
    end if;
  else
    if jsonb_typeof(p_payload -> 'obligation_milligrams') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'obligation_karat') is distinct from 'number' then
      raise exception 'invalid_input';
    end if;
    v_gold_karat := (p_payload ->> 'obligation_karat')::smallint;
    if v_gold_karat not in (14, 18, 21, 22, 24) then
      raise exception 'invalid_input';
    end if;
    v_gold_mg := private.opening_checked_bigint(
      private.opening_parse_amount(p_payload ->> 'obligation_milligrams'));
    if v_gold_mg <= 0 then raise exception 'invalid_input'; end if;
  end if;
  perform private.lock_lots_ordered(v_shop, array[v_receipt.lot_id]);
  select * into v_source from public.inventory_lots as lot
  where lot.shop_id = v_shop and lot.id = v_receipt.lot_id;
  if v_source.stock_class is distinct from 'trader_custody' then
    raise exception 'invalid_input';
  end if;
  v_operation := private.insert_operation(
    v_shop, 'ownership_transfer', v_day, v_actor, v_at, p_payload
  );
  v_move_count := case when v_receipt.category_code = 'scrap' then 0 else v_count end;
  perform private.add_lot_movement(
    v_shop, v_source.id, v_operation, -v_mg, -v_move_count,
    'transfer_out', 'ownership_transfer'
  );
  v_new := private.spawn_owned_from_source(
    v_shop, v_operation, v_source, v_mg, v_count, 'transfer_in', 'ownership_transfer'
  );
  perform private.post_owned_increase(
    v_shop, v_operation, v_source.category_code, v_source.karat, v_mg, v_count, 'movement'
  );
  if v_has_cash then
    if v_tender_sum > 0 then
      perform private.post_cash_payment(v_shop, v_operation, p_payload -> 'tenders');
    end if;
    if v_payable > 0 then
      insert into public.purchase_cash_payables (
        operation_id, shop_id, trader_id, seller_name, initial_piastres,
        remaining_piastres, created_at, updated_at
      ) values (
        v_operation, v_shop, v_receipt.trader_id, v_receipt.counterparty_name,
        v_payable, v_payable, v_at, v_at
      );
    end if;
  else
    insert into public.gold_obligations (
      operation_id, shop_id, trader_id, counterparty_name, karat,
      initial_milligrams, remaining_milligrams, created_at, updated_at
    ) values (
      v_operation, v_shop, v_receipt.trader_id, v_receipt.counterparty_name,
      v_gold_karat, v_gold_mg, v_gold_mg, v_at, v_at
    );
  end if;
  perform private.insert_receipt_allocation(
    v_shop, v_receipt.id, v_operation, 'ownership_transfer', v_mg, v_count, v_new
  );
  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, 'ownership_transfer_confirmed',
    p_key, p_payload,
    jsonb_build_object(
      'operation_id', v_operation, 'receipt_id', v_receipt.id,
      'trader_id', v_receipt.trader_id
    )
  );
end;
$fn$;

create function private.post_receipt_manual_allocation(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_day uuid; v_actor uuid; v_at timestamptz;
  v_operation uuid; v_receipt public.inventory_receipts%rowtype;
  v_lot public.inventory_lots%rowtype; v_manual uuid; v_mg bigint; v_count bigint;
  v_rem_mg bigint; v_rem_count bigint; v_move_count bigint;
  v_addition public.financial_operations%rowtype;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'kind' is distinct from 'receipt_manual_allocation'
    or p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'receipt_id' - 'manual_operation_id' - 'lot_id' - 'milligrams' - 'count'
      - 'reason' <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  perform private.require_reason(p_payload);
  v_manual := private.uuid_or_null(p_payload -> 'manual_operation_id');
  if v_manual is null or private.uuid_or_null(p_payload -> 'lot_id') is null then
    raise exception 'invalid_input';
  end if;
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  v_receipt := private.lock_receipt(v_shop, private.uuid_or_null(p_payload -> 'receipt_id'));
  if v_receipt.recognition_policy = 'custody' then
    raise exception 'custody_requires_transfer';
  end if;
  if v_receipt.recognition_policy is distinct from 'deferred'
    or v_receipt.owner_kind is distinct from 'shop' then
    raise exception 'invalid_input';
  end if;
  select * into v_addition from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = v_manual;
  if v_addition.id is null or v_addition.kind is distinct from 'inventory_addition' then
    raise exception 'invalid_input';
  end if;
  perform private.lock_lots_ordered(
    v_shop, array[v_receipt.lot_id, private.uuid_or_null(p_payload -> 'lot_id')]
  );
  select * into v_lot from public.inventory_lots as lot
  where lot.shop_id = v_shop and lot.id = private.uuid_or_null(p_payload -> 'lot_id');
  if v_lot.id is null or v_lot.origin_operation_id is distinct from v_manual
    or v_lot.stock_class is distinct from 'owned_available'
    or v_lot.product_id is distinct from v_receipt.product_id
    or v_lot.category_code is distinct from v_receipt.category_code
    or v_lot.karat is distinct from v_receipt.karat then
    raise exception 'invalid_input';
  end if;
  select quantity.milligrams, quantity.piece_count into v_mg, v_count
  from private.category_quantity(
    p_payload, v_lot.category_code, 'milligrams', 'count'
  ) as quantity;
  if v_mg <> v_lot.original_milligrams
    or (v_lot.tracks_count and v_count is distinct from v_lot.original_count) then
    raise exception 'invalid_input';
  end if;
  select remaining.milligrams, remaining.piece_count into v_rem_mg, v_rem_count
  from private.lot_remaining(v_lot.id) as remaining;
  if v_rem_mg <> v_lot.original_milligrams
    or (v_lot.tracks_count and v_rem_count is distinct from v_lot.original_count) then
    raise exception 'invalid_input';
  end if;
  if exists (
    select 1 from public.receipt_quantity_allocations as allocation
    where allocation.shop_id = v_shop and allocation.linked_lot_id = v_lot.id
  ) then
    raise exception 'already_allocated';
  end if;
  perform private.take_receipt_quantity(
    v_receipt.id, v_receipt.category_code, v_mg, v_count
  );
  v_operation := private.insert_operation(
    v_shop, 'receipt_manual_allocation', v_day, v_actor, v_at, p_payload
  );
  v_move_count := case when v_lot.tracks_count then v_count else 0 end;
  perform private.add_lot_movement(
    v_shop, v_receipt.lot_id, v_operation, -v_mg, -v_move_count,
    'manual_link', 'manual_link'
  );
  perform private.insert_receipt_allocation(
    v_shop, v_receipt.id, v_operation, 'manual_link', v_mg, v_count, v_lot.id
  );
  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, 'receipt_manual_allocation_confirmed',
    p_key, p_payload,
    jsonb_build_object('operation_id', v_operation, 'receipt_id', v_receipt.id)
  );
end;
$fn$;

create function private.post_gold_acquisition(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_day uuid; v_actor uuid; v_at timestamptz;
  v_operation uuid; v_category text; v_karat smallint; v_mg bigint; v_count bigint;
  v_gold_karat smallint; v_gold_mg bigint; v_name text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'kind' is distinct from 'gold_obligation_acquisition'
    or p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'category' - 'karat' - 'milligrams' - 'count' - 'item_name'
      - 'obligation_karat' - 'obligation_milligrams' - 'counterparty_name'
      - 'note' - 'denomination_id' - 'coin_type_id' - 'trader_id' <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'category') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'karat') is distinct from 'number'
    or jsonb_typeof(p_payload -> 'item_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'obligation_karat') is distinct from 'number'
    or jsonb_typeof(p_payload -> 'obligation_milligrams') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'counterparty_name') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'note') is distinct from 'string'
    or char_length(p_payload ->> 'note') > 1000
    or nullif(btrim(p_payload ->> 'item_name'), '') is null
    or char_length(p_payload ->> 'item_name') > 120
    or p_payload ->> 'item_name' is distinct from btrim(p_payload ->> 'item_name')
    or nullif(btrim(p_payload ->> 'counterparty_name'), '') is null
    or char_length(p_payload ->> 'counterparty_name') > 200
    or p_payload ->> 'counterparty_name' is distinct from btrim(p_payload ->> 'counterparty_name') then
    raise exception 'invalid_input';
  end if;
  v_category := p_payload ->> 'category';
  v_karat := (p_payload ->> 'karat')::smallint;
  v_gold_karat := (p_payload ->> 'obligation_karat')::smallint;
  if not private.opening_pair_allowed(v_category, v_karat) then
    raise exception 'unsupported_category_karat';
  end if;
  if v_gold_karat not in (14, 18, 21, 22, 24) then raise exception 'invalid_input'; end if;
  select quantity.milligrams, quantity.piece_count into v_mg, v_count
  from private.category_quantity(p_payload, v_category, 'milligrams', 'count') as quantity;
  v_gold_mg := private.opening_checked_bigint(
    private.opening_parse_amount(p_payload ->> 'obligation_milligrams'));
  if v_gold_mg <= 0 then raise exception 'invalid_input'; end if;
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  v_name := p_payload ->> 'item_name';
  perform private.require_shop_trader(
    v_shop, private.uuid_or_null(p_payload -> 'trader_id'));
  v_operation := private.insert_operation(
    v_shop, 'gold_obligation_acquisition', v_day, v_actor, v_at, p_payload
  );
  perform private.create_stock_lot(
    v_shop, v_operation, v_name, v_category, v_karat, v_mg, v_count,
    'owned_available', null, false,
    private.uuid_or_null(p_payload -> 'denomination_id'),
    private.uuid_or_null(p_payload -> 'coin_type_id'),
    'gold_acquisition', 'manual'
  );
  perform private.post_owned_increase(
    v_shop, v_operation, v_category, v_karat, v_mg, v_count, 'movement'
  );
  insert into public.gold_obligations (
    operation_id, shop_id, trader_id, counterparty_name, karat,
    initial_milligrams, remaining_milligrams, created_at, updated_at
  ) values (
    v_operation, v_shop, private.uuid_or_null(p_payload -> 'trader_id'),
    p_payload ->> 'counterparty_name', v_gold_karat,
    v_gold_mg, v_gold_mg, v_at, v_at
  );
  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, 'gold_obligation_acquisition_confirmed',
    p_key, p_payload, jsonb_build_object('operation_id', v_operation)
  );
end;
$fn$;

create function private.post_gold_settlement(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_day uuid; v_actor uuid; v_at timestamptz;
  v_operation uuid; v_obligation public.gold_obligations%rowtype;
  v_line jsonb; v_lot public.inventory_lots%rowtype; v_ids uuid[] := '{}';
  v_id uuid; v_mg bigint; v_count bigint; v_move_count bigint; v_sum numeric := 0;
  v_seen uuid[] := '{}';
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload ->> 'kind' is distinct from 'gold_obligation_settlement'
    or p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'obligation_operation_id' - 'deliveries' - 'reason' <> '{}'::jsonb
    or jsonb_typeof(p_payload -> 'deliveries') is distinct from 'array'
    or jsonb_array_length(p_payload -> 'deliveries') not between 1 and 20 then
    raise exception 'invalid_input';
  end if;
  perform private.require_reason(p_payload);
  for v_line in select value from jsonb_array_elements(p_payload -> 'deliveries') loop
    if jsonb_typeof(v_line) is distinct from 'object'
      or v_line - 'lot_id' - 'milligrams' - 'count' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
    v_id := private.uuid_or_null(v_line -> 'lot_id');
    if v_id is null or v_id = any (v_seen) then raise exception 'invalid_input'; end if;
    v_seen := array_append(v_seen, v_id);
    v_ids := array_append(v_ids, v_id);
    v_sum := v_sum + private.opening_parse_amount(v_line ->> 'milligrams');
  end loop;
  v_gate := private.replay_or_gate(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_day := (v_gate ->> 'day_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  v_at := (v_gate ->> 'at')::timestamptz;
  select * into v_obligation from public.gold_obligations as obligation
  where obligation.shop_id = v_shop
    and obligation.operation_id = private.uuid_or_null(p_payload -> 'obligation_operation_id')
  for update;
  if v_obligation.operation_id is null then raise exception 'not_found'; end if;
  if v_sum > v_obligation.remaining_milligrams then
    raise exception 'settlement_exceeds_obligation';
  end if;
  perform private.lock_lots_ordered(v_shop, v_ids);
  v_operation := private.insert_operation(
    v_shop, 'gold_obligation_settlement', v_day, v_actor, v_at, p_payload
  );
  for v_line in select value from jsonb_array_elements(p_payload -> 'deliveries') loop
    select * into v_lot from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.id = (v_line ->> 'lot_id')::uuid;
    if v_lot.id is null or v_lot.stock_class is distinct from 'owned_available'
      or v_lot.karat is distinct from v_obligation.karat then
      raise exception 'invalid_input';
    end if;
    select quantity.milligrams, quantity.piece_count into v_mg, v_count
    from private.category_quantity(
      v_line, v_lot.category_code, 'milligrams', 'count'
    ) as quantity;
    v_move_count := case when v_lot.tracks_count then v_count else 0 end;
    perform private.consume_named_lot(
      v_shop, v_operation, v_lot.id, v_mg, v_move_count, 'gold_settlement', 'gold_settlement'
    );
    perform private.post_account_delta(
      v_shop, v_operation,
      case when v_lot.category_code = 'scrap' then 'scrap_metal' else 'saleable_metal' end,
      'gold_mg', v_lot.category_code, v_lot.karat, null, -v_mg,
      'movement_gold_clearing', false
    );
    if v_lot.tracks_count then
      perform private.post_account_delta(
        v_shop, v_operation, 'saleable_count', 'count', v_lot.category_code,
        v_lot.karat, null, -v_count, 'movement_count_clearing', false
      );
    end if;
  end loop;
  update public.gold_obligations
  set remaining_milligrams = remaining_milligrams - private.opening_checked_bigint(v_sum),
      updated_at = v_at
  where operation_id = v_obligation.operation_id and shop_id = v_shop;
  return private.finish_financial_command(
    v_shop, v_operation, v_actor, v_at, v_day, 'gold_obligation_settled',
    p_key, p_payload,
    jsonb_build_object('operation_id', v_operation,
      'obligation_operation_id', v_obligation.operation_id)
  );
end;
$fn$;

create function public.post_inventory_receipt_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.post_inventory_receipt(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_inventory_recognition_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.post_inventory_recognition(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_ownership_transfer_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.post_ownership_transfer(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_receipt_manual_allocation_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.post_receipt_manual_allocation(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_gold_obligation_acquisition_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.post_gold_acquisition(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_gold_obligation_settlement_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  return private.post_gold_settlement(p_idempotency_key, p_payload);
end;
$fn$;

create function private.begin_catalog_command(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_hash bytea; v_row public.inventory_catalog_requests%rowtype;
  v_day uuid; v_version bigint;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_key is null or p_payload is null or jsonb_typeof(p_payload) <> 'object'
    or p_payload -> 'version' is distinct from '1'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select request.* into v_row from public.inventory_catalog_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_key
  for update;
  if found then
    if v_row.payload = p_payload and v_row.payload_sha256 = v_hash then
      return v_row.result || jsonb_build_object('replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if private.parse_expected_day(p_payload) is distinct from v_day
    or private.parse_expected_version(p_payload) is distinct from v_version then
    raise exception 'stale_day';
  end if;
  return jsonb_build_object(
    'replayed', false, 'shop_id', v_shop, 'actor', auth.uid(), 'hash', encode(v_hash, 'hex')
  );
end;
$fn$;

create function private.finish_catalog_command(
  p_shop uuid, p_key uuid, p_payload jsonb, p_actor uuid, p_action text,
  p_id uuid, p_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_result jsonb;
begin
  v_result := jsonb_build_object('ok', true, 'id', p_id, 'replayed', false);
  insert into public.inventory_catalog_events (
    shop_id, actor_user_id, action, details
  ) values (
    p_shop, p_actor, p_action, jsonb_build_object('id', p_id)
  );
  insert into public.inventory_catalog_requests (
    shop_id, idempotency_key, payload, payload_sha256, result
  ) values (
    p_shop, p_key, p_payload, decode(p_hash, 'hex'), v_result
  );
  return v_result;
end;
$fn$;

create function private.save_catalog(p_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_gate jsonb; v_shop uuid; v_actor uuid; v_kind text; v_id uuid;
  v_name text; v_category text; v_karat smallint; v_label text;
  v_nominal bigint; v_active boolean; v_phone text; v_note text;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'invalid_input';
  end if;
  v_kind := p_payload ->> 'kind';
  if v_kind = 'product' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'name' - 'category' - 'karat' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
  elsif v_kind = 'bullion_denomination' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'label' - 'nominal_milligrams' - 'active' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
  elsif v_kind = 'coin_type' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'label' - 'nominal_milligrams' - 'active' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
  elsif v_kind = 'trader' then
    if p_payload - 'version' - 'kind' - 'expected_day_id' - 'expected_day_version'
      - 'display_name' - 'phone' - 'note' - 'active' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  v_gate := private.begin_catalog_command(p_key, p_payload);
  if v_gate ->> 'replayed' = 'true' then return v_gate; end if;
  v_shop := (v_gate ->> 'shop_id')::uuid;
  v_actor := (v_gate ->> 'actor')::uuid;
  if v_kind = 'product' then
    if jsonb_typeof(p_payload -> 'name') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'category') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'karat') is distinct from 'number' then
      raise exception 'invalid_input';
    end if;
    v_name := p_payload ->> 'name';
    v_category := p_payload ->> 'category';
    v_karat := (p_payload ->> 'karat')::smallint;
    if v_name is distinct from btrim(v_name) or not private.opening_pair_allowed(v_category, v_karat) then
      if not private.opening_pair_allowed(v_category, v_karat) then
        raise exception 'unsupported_category_karat';
      end if;
      raise exception 'invalid_input';
    end if;
    select product.id into v_id from public.inventory_products as product
    where product.shop_id = v_shop and product.category_code = v_category
      and product.karat = v_karat and product.name = v_name;
    if v_id is null then
      v_id := private.inventory_product_id(v_shop, v_name, v_category, v_karat);
    end if;
    return private.finish_catalog_command(
      v_shop, p_key, p_payload, v_actor, 'product_saved', v_id, v_gate ->> 'hash'
    );
  elsif v_kind = 'trader' then
    if jsonb_typeof(p_payload -> 'display_name') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'phone') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'note') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'active') is distinct from 'boolean' then
      raise exception 'invalid_input';
    end if;
    v_name := p_payload ->> 'display_name';
    v_phone := p_payload ->> 'phone';
    v_note := p_payload ->> 'note';
    v_active := (p_payload ->> 'active')::boolean;
    if v_name is distinct from btrim(v_name) or char_length(v_name) > 200
      or nullif(v_name, '') is null or char_length(v_phone) > 20
      or char_length(v_note) > 1000
      or (v_phone <> '' and v_phone !~ '^\+?[0-9]{7,15}$') then
      raise exception 'invalid_input';
    end if;
    select trader.id into v_id from public.traders as trader
    where trader.shop_id = v_shop and trader.display_name = v_name;
    if v_id is not null then
      if not exists (
        select 1 from public.traders as trader
        where trader.id = v_id and trader.phone = v_phone and trader.note = v_note
          and trader.active = v_active
      ) then
        raise exception 'payload_mismatch';
      end if;
    else
      insert into public.traders (shop_id, display_name, phone, note, active)
      values (v_shop, v_name, v_phone, v_note, v_active) returning id into v_id;
    end if;
    return private.finish_catalog_command(
      v_shop, p_key, p_payload, v_actor, 'trader_saved', v_id, v_gate ->> 'hash'
    );
  end if;
  if jsonb_typeof(p_payload -> 'label') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'active') is distinct from 'boolean' then
    raise exception 'invalid_input';
  end if;
  v_label := p_payload ->> 'label';
  v_active := (p_payload ->> 'active')::boolean;
  if v_label is distinct from btrim(v_label) or nullif(v_label, '') is null
    or char_length(v_label) > 120 then
    raise exception 'invalid_input';
  end if;
  if v_kind = 'bullion_denomination' then
    if jsonb_typeof(p_payload -> 'nominal_milligrams') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_nominal := private.opening_checked_bigint(
      private.opening_parse_amount(p_payload ->> 'nominal_milligrams'));
    if v_nominal <= 0 then raise exception 'invalid_input'; end if;
    select denomination.id into v_id from public.bullion_denominations as denomination
    where denomination.shop_id = v_shop and denomination.label = v_label;
    if v_id is not null then
      if not exists (
        select 1 from public.bullion_denominations as denomination
        where denomination.id = v_id and denomination.nominal_milligrams = v_nominal
          and denomination.active = v_active
      ) then
        raise exception 'payload_mismatch';
      end if;
    else
      insert into public.bullion_denominations (shop_id, label, nominal_milligrams, active)
      values (v_shop, v_label, v_nominal, v_active) returning id into v_id;
    end if;
    return private.finish_catalog_command(
      v_shop, p_key, p_payload, v_actor, 'bullion_denomination_saved', v_id, v_gate ->> 'hash'
    );
  end if;
  if p_payload -> 'nominal_milligrams' = 'null'::jsonb then
    v_nominal := null;
  elsif jsonb_typeof(p_payload -> 'nominal_milligrams') is distinct from 'string' then
    raise exception 'invalid_input';
  else
    v_nominal := private.opening_checked_bigint(
      private.opening_parse_amount(p_payload ->> 'nominal_milligrams'));
    if v_nominal <= 0 then raise exception 'invalid_input'; end if;
  end if;
  select coin.id into v_id from public.coin_types as coin
  where coin.shop_id = v_shop and coin.label = v_label;
  if v_id is not null then
    if not exists (
      select 1 from public.coin_types as coin
      where coin.id = v_id and coin.nominal_milligrams is not distinct from v_nominal
        and coin.active = v_active
    ) then
      raise exception 'payload_mismatch';
    end if;
  else
    insert into public.coin_types (shop_id, label, nominal_milligrams, active)
    values (v_shop, v_label, v_nominal, v_active) returning id into v_id;
  end if;
  return private.finish_catalog_command(
    v_shop, p_key, p_payload, v_actor, 'coin_type_saved', v_id, v_gate ->> 'hash'
  );
end;
$fn$;

create function public.save_inventory_product_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'product' then raise exception 'invalid_input'; end if;
  return private.save_catalog(p_idempotency_key, p_payload);
end;
$fn$;

create function public.save_bullion_denomination_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'bullion_denomination' then
    raise exception 'invalid_input';
  end if;
  return private.save_catalog(p_idempotency_key, p_payload);
end;
$fn$;

create function public.save_coin_type_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'coin_type' then raise exception 'invalid_input'; end if;
  return private.save_catalog(p_idempotency_key, p_payload);
end;
$fn$;

create function public.save_trader_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
begin
  if p_payload ->> 'kind' is distinct from 'trader' then raise exception 'invalid_input'; end if;
  return private.save_catalog(p_idempotency_key, p_payload);
end;
$fn$;

create function public.post_daily_ledger_trade_v2(p_idempotency_key uuid, p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_hash bytea; v_env public.inventory_command_envelopes%rowtype;
  v_day uuid; v_version bigint; v_kind text; v_inner jsonb; v_plan jsonb;
  v_lines jsonb := '[]'::jsonb; v_line jsonb; v_index integer := 0; v_result jsonb;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_idempotency_key is null or p_payload is null
    or jsonb_typeof(p_payload) <> 'object'
    or p_payload -> 'version' is distinct from '2'::jsonb
    or p_payload - 'version' - 'kind' - 'total_piastres' - 'tenders' - 'items'
      - 'description' - 'customer_name' - 'customer_phone' - 'note'
      - 'purchase_obligation_piastres' - 'lot_selections' - 'lot_identities'
      - 'expected_day_id' - 'expected_day_version' - 'pricing' <> '{}'::jsonb then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_hash := extensions.digest(convert_to(p_payload::text, 'UTF8'), 'sha256');
  select envelope.* into v_env from public.inventory_command_envelopes as envelope
  where envelope.shop_id = v_shop and envelope.idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_env.payload = p_payload and v_env.payload_sha256 = v_hash then
      return v_env.result || jsonb_build_object('replayed', true);
    end if;
    raise exception 'payload_mismatch';
  end if;
  perform 1 from public.financial_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key
  for update;
  if found then raise exception 'payload_mismatch'; end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select day.id, day.day_version into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  for update;
  if v_day is null then raise exception 'day_closed'; end if;
  if private.parse_expected_day(p_payload) is distinct from v_day
    or private.parse_expected_version(p_payload) is distinct from v_version then
    raise exception 'stale_day';
  end if;
  v_kind := p_payload ->> 'kind';
  if jsonb_typeof(p_payload -> 'items') is distinct from 'array' then
    raise exception 'invalid_input';
  end if;
  if v_kind in ('sale', 'scrap_sale') then
    if p_payload ? 'lot_identities'
      or jsonb_typeof(p_payload -> 'lot_selections') is distinct from 'array'
      or jsonb_array_length(p_payload -> 'lot_selections')
        <> jsonb_array_length(p_payload -> 'items') then
      raise exception 'invalid_input';
    end if;
    for v_line in select value from jsonb_array_elements(p_payload -> 'lot_selections') loop
      if jsonb_typeof(v_line) is distinct from 'object'
        or v_line - 'lot_id' - 'milligrams' - 'count' <> '{}'::jsonb
        or private.uuid_or_null(v_line -> 'lot_id') is null
        or jsonb_typeof(v_line -> 'milligrams') is distinct from 'string' then
        raise exception 'invalid_input';
      end if;
      if v_kind = 'scrap_sale' and v_line -> 'count' is distinct from 'null'::jsonb then
        raise exception 'invalid_input';
      end if;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'item_index', v_index,
        'lot_id', v_line ->> 'lot_id',
        'milligrams', v_line ->> 'milligrams',
        'count', v_line -> 'count'
      ));
      v_index := v_index + 1;
    end loop;
  elsif v_kind = 'purchase' then
    if p_payload ? 'lot_selections' then raise exception 'invalid_input'; end if;
    if p_payload ? 'lot_identities' then
      if jsonb_typeof(p_payload -> 'lot_identities') is distinct from 'array'
        or jsonb_array_length(p_payload -> 'lot_identities')
          <> jsonb_array_length(p_payload -> 'items') then
        raise exception 'invalid_input';
      end if;
      for v_line in select value from jsonb_array_elements(p_payload -> 'lot_identities') loop
        if jsonb_typeof(v_line) is distinct from 'object'
          or v_line - 'denomination_id' - 'coin_type_id' <> '{}'::jsonb then
          raise exception 'invalid_input';
        end if;
        if v_line ? 'denomination_id' then
          perform private.uuid_or_null(v_line -> 'denomination_id');
        end if;
        if v_line ? 'coin_type_id' then
          perform private.uuid_or_null(v_line -> 'coin_type_id');
        end if;
        v_lines := v_lines || jsonb_build_array(jsonb_build_object(
          'item_index', v_index,
          'denomination_id', v_line -> 'denomination_id',
          'coin_type_id', v_line -> 'coin_type_id'
        ));
        v_index := v_index + 1;
      end loop;
    end if;
  elsif v_kind = 'expense' then
    if p_payload ? 'lot_selections' or p_payload ? 'lot_identities' then
      raise exception 'invalid_input';
    end if;
  else
    raise exception 'invalid_input';
  end if;
  v_plan := jsonb_build_object('lines', v_lines);
  v_inner := p_payload - 'lot_selections' - 'lot_identities'
    - 'expected_day_id' - 'expected_day_version';
  if p_payload ? 'pricing' then
    v_inner := jsonb_set(v_inner, '{version}', '2'::jsonb);
  else
    v_inner := jsonb_set(v_inner, '{version}', '1'::jsonb);
  end if;
  insert into public.inventory_explicit_plans (shop_id, idempotency_key, plan)
  values (v_shop, p_idempotency_key, v_plan);
  v_result := public.post_daily_ledger_trade(p_idempotency_key, v_inner);
  insert into public.inventory_command_envelopes (
    shop_id, idempotency_key, payload, payload_sha256, operation_id, result
  ) values (
    v_shop, p_idempotency_key, p_payload, v_hash,
    (v_result ->> 'operation_id')::uuid, v_result
  );
  return v_result;
end;
$fn$;

create function private.bounded_limit(p_limit integer)
returns integer language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if p_limit is null then return 50; end if;
  if p_limit < 1 or p_limit > 100 then raise exception 'invalid_input'; end if;
  return p_limit;
end;
$fn$;

create function private.cursor_text(p_at timestamptz, p_id uuid)
returns text language sql immutable security invoker set search_path = '' as $fn$
  select to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"+00"')
    || '|' || p_id::text;
$fn$;

create function private.cursor_time(p_cursor text)
returns timestamptz language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if p_cursor is null or split_part(p_cursor, '|', 2) = ''
    or split_part(p_cursor, '|', 3) <> '' then
    raise exception 'invalid_input';
  end if;
  begin
    return split_part(p_cursor, '|', 1)::timestamptz;
  exception when invalid_datetime_format or datetime_field_overflow then
    raise exception 'invalid_input';
  end;
end;
$fn$;

create function private.cursor_id(p_cursor text)
returns uuid language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  begin
    return split_part(p_cursor, '|', 2)::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_input';
  end;
end;
$fn$;

create function private.assert_read_filters(
  p_category text, p_karat smallint, p_stock_class text, p_query text
) returns void language plpgsql immutable security invoker set search_path = '' as $fn$
begin
  if p_category is not null
    and p_category not in ('worked_jewelry', 'bullion', 'coin', 'scrap') then
    raise exception 'invalid_input';
  end if;
  if p_karat is not null and p_karat not in (14, 18, 21, 22, 24) then
    raise exception 'invalid_input';
  end if;
  if p_stock_class is not null
    and p_stock_class not in ('owned_available', 'owned_pending', 'trader_custody') then
    raise exception 'invalid_input';
  end if;
  if p_query is not null and char_length(p_query) > 120 then
    raise exception 'invalid_input';
  end if;
end;
$fn$;

create function public.get_inventory_totals_v1(
  p_category text default null, p_karat smallint default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare v_shop uuid; v_buckets jsonb;
begin
  perform private.assert_read_filters(p_category, p_karat, null, null);
  v_shop := private.opening_require_reader_shop();
  select coalesce(jsonb_agg(jsonb_build_object(
    'category', bucket.category_code,
    'karat', bucket.karat,
    'available_milligrams', bucket.available_mg::text,
    'available_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
      else to_jsonb(bucket.available_count::text) end,
    'pending_milligrams', bucket.pending_mg::text,
    'pending_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
      else to_jsonb(bucket.pending_count::text) end,
    'held_milligrams', bucket.held_mg::text,
    'held_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
      else to_jsonb(bucket.held_count::text) end
  ) order by bucket.category_code, bucket.karat), '[]'::jsonb)
  into v_buckets
  from (
    select lot.category_code, lot.karat,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'owned_available'), 0)::bigint as available_mg,
      coalesce(sum(movement.delta_count) filter (
        where lot.stock_class = 'owned_available' and lot.tracks_count), 0)::bigint as available_count,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'owned_pending'), 0)::bigint as pending_mg,
      coalesce(sum(movement.delta_count) filter (
        where lot.stock_class = 'owned_pending' and lot.tracks_count), 0)::bigint as pending_count,
      coalesce(sum(movement.delta_milligrams) filter (
        where lot.stock_class = 'trader_custody'), 0)::bigint as held_mg,
      coalesce(sum(movement.delta_count) filter (
        where lot.stock_class = 'trader_custody' and lot.tracks_count), 0)::bigint as held_count
    from public.inventory_lots as lot
    join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    where lot.shop_id = v_shop
      and (p_category is null or lot.category_code = p_category)
      and (p_karat is null or lot.karat = p_karat)
    group by lot.category_code, lot.karat
  ) as bucket;
  return jsonb_build_object('ok', true, 'buckets', v_buckets);
end;
$fn$;

create function public.list_inventory_lots_v1(
  p_category text default null, p_karat smallint default null,
  p_stock_class text default null, p_query text default null,
  p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  perform private.assert_read_filters(p_category, p_karat, p_stock_class, p_query);
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  for v_row in
    select lot.id, lot.created_at, lot.product_id, product.name as product_name,
      lot.display_name, lot.category_code, lot.karat, lot.stock_class,
      lot.legacy_aggregate, lot.original_milligrams, lot.original_count,
      lot.denomination_id, denomination.nominal_milligrams as nominal_milligrams,
      lot.coin_type_id, coin.nominal_milligrams as coin_nominal_milligrams,
      lot.trader_id, lot.origin_operation_id,
      coalesce(sum(movement.delta_milligrams), 0)::bigint as remaining_mg,
      coalesce(sum(movement.delta_count), 0)::bigint as remaining_count
    from public.inventory_lots as lot
    join public.inventory_products as product
      on product.shop_id = lot.shop_id and product.id = lot.product_id
    left join public.inventory_lot_movements as movement
      on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
    left join public.bullion_denominations as denomination
      on denomination.shop_id = lot.shop_id and denomination.id = lot.denomination_id
    left join public.coin_types as coin
      on coin.shop_id = lot.shop_id and coin.id = lot.coin_type_id
    where lot.shop_id = v_shop
      and (p_category is null or lot.category_code = p_category)
      and (p_karat is null or lot.karat = p_karat)
      and (p_stock_class is null or lot.stock_class = p_stock_class)
      and (p_query is null or btrim(p_query) = ''
        or strpos(lower(lot.display_name), lower(p_query)) > 0
        or strpos(lower(product.name), lower(p_query)) > 0)
      and (v_at is null or (lot.created_at, lot.id) < (v_at, v_id))
    group by lot.id, product.name, denomination.nominal_milligrams, coin.nominal_milligrams
    order by lot.created_at desc, lot.id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.created_at, v_row.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'lot_id', v_row.id,
      'product_id', v_row.product_id,
      'product_name', v_row.product_name,
      'display_name', v_row.display_name,
      'category', v_row.category_code,
      'karat', v_row.karat,
      'stock_class', v_row.stock_class,
      'legacy_aggregate', v_row.legacy_aggregate,
      'original_milligrams', v_row.original_milligrams::text,
      'original_count', case when v_row.original_count is null then 'null'::jsonb
        else to_jsonb(v_row.original_count::text) end,
      'remaining_milligrams', v_row.remaining_mg::text,
      'remaining_count', case when v_row.original_count is null then 'null'::jsonb
        else to_jsonb(v_row.remaining_count::text) end,
      'denomination_id', v_row.denomination_id,
      'nominal_milligrams', case when v_row.nominal_milligrams is null then 'null'::jsonb
        else to_jsonb(v_row.nominal_milligrams::text) end,
      'coin_type_id', v_row.coin_type_id,
      'coin_nominal_milligrams', case when v_row.coin_nominal_milligrams is null then 'null'::jsonb
        else to_jsonb(v_row.coin_nominal_milligrams::text) end,
      'trader_id', v_row.trader_id,
      'origin_operation_id', v_row.origin_operation_id,
      'created_at', v_row.created_at,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

create function public.list_lot_movements_v1(
  p_lot_id uuid, p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  if p_lot_id is null then raise exception 'invalid_input'; end if;
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  if not exists (
    select 1 from public.inventory_lots as lot
    where lot.shop_id = v_shop and lot.id = p_lot_id
  ) then
    raise exception 'not_found';
  end if;
  for v_row in
    select movement.id, movement.created_at, movement.delta_milligrams,
      movement.delta_count, movement.movement_kind, movement.allocation_mode,
      movement.operation_id, operation.kind as operation_kind
    from public.inventory_lot_movements as movement
    left join public.financial_operations as operation
      on operation.shop_id = movement.shop_id and operation.id = movement.operation_id
    where movement.shop_id = v_shop and movement.lot_id = p_lot_id
      and (v_at is null or (movement.created_at, movement.id) < (v_at, v_id))
    order by movement.created_at desc, movement.id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.created_at, v_row.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'movement_id', v_row.id,
      'delta_milligrams', v_row.delta_milligrams::text,
      'delta_count', v_row.delta_count::text,
      'movement_kind', v_row.movement_kind,
      'allocation_mode', v_row.allocation_mode,
      'operation_id', v_row.operation_id,
      'operation_kind', v_row.operation_kind,
      'created_at', v_row.created_at,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

create function public.search_traders_v1(
  p_query text default null, p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  if p_query is not null and char_length(p_query) > 120 then
    raise exception 'invalid_input';
  end if;
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  for v_row in
    select trader.id, trader.display_name, trader.phone, trader.active, trader.created_at
    from public.traders as trader
    where trader.shop_id = v_shop
      and (p_query is null or btrim(p_query) = ''
        or strpos(lower(trader.display_name), lower(p_query)) > 0)
      and (v_at is null or (trader.created_at, trader.id) < (v_at, v_id))
    order by trader.created_at desc, trader.id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.created_at, v_row.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'trader_id', v_row.id,
      'display_name', v_row.display_name,
      'phone', v_row.phone,
      'active', v_row.active,
      'created_at', v_row.created_at,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

create function public.get_trader_v1(p_trader_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_trader public.traders%rowtype; v_buckets jsonb;
  v_original bigint; v_current bigint; v_pending bigint;
  v_cash bigint; v_gold jsonb;
begin
  if p_trader_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  select * into v_trader from public.traders as trader
  where trader.shop_id = v_shop and trader.id = p_trader_id;
  if v_trader.id is null then raise exception 'not_found'; end if;
  select coalesce(sum(bucket.original_mg), 0)::bigint,
         coalesce(sum(bucket.current_mg), 0)::bigint,
         coalesce(sum(bucket.pending_count), 0)::bigint,
         coalesce(jsonb_agg(jsonb_build_object(
           'category', bucket.category_code,
           'karat', bucket.karat,
           'original_milligrams', bucket.original_mg::text,
           'original_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
             else to_jsonb(coalesce(bucket.original_count, 0)::text) end,
           'current_milligrams', bucket.current_mg::text,
           'current_count', case when bucket.category_code = 'scrap' then 'null'::jsonb
             else to_jsonb(bucket.current_count::text) end,
           'pending_receipt_count', bucket.pending_count::text
         ) order by bucket.category_code, bucket.karat), '[]'::jsonb)
    into v_original, v_current, v_pending, v_buckets
  from (
    select coalesce(receipts.category_code, held.category_code) as category_code,
      coalesce(receipts.karat, held.karat) as karat,
      coalesce(receipts.original_mg, 0) as original_mg,
      receipts.original_count,
      coalesce(held.current_mg, 0) as current_mg,
      coalesce(held.current_count, 0) as current_count,
      coalesce(receipts.pending_count, 0) as pending_count
    from (
      select receipt.category_code, receipt.karat,
        sum(receipt.milligrams)::bigint as original_mg,
        sum(receipt.piece_count)::bigint as original_count,
        count(*) filter (
          where receipt.milligrams > coalesce(allocated.milligrams, 0)
        )::bigint as pending_count
      from public.inventory_receipts as receipt
      left join (
        select allocation.receipt_id, sum(allocation.milligrams)::bigint as milligrams
        from public.receipt_quantity_allocations as allocation
        where allocation.shop_id = v_shop
        group by allocation.receipt_id
      ) as allocated on allocated.receipt_id = receipt.id
      where receipt.shop_id = v_shop and receipt.trader_id = p_trader_id
      group by receipt.category_code, receipt.karat
    ) as receipts
    full join (
      select lot.category_code, lot.karat,
        coalesce(sum(movement.delta_milligrams), 0)::bigint as current_mg,
        coalesce(sum(movement.delta_count), 0)::bigint as current_count
      from public.inventory_lots as lot
      join public.inventory_lot_movements as movement
        on movement.shop_id = lot.shop_id and movement.lot_id = lot.id
      where lot.shop_id = v_shop and lot.trader_id = p_trader_id
        and lot.stock_class = 'trader_custody'
      group by lot.category_code, lot.karat
    ) as held
      on held.category_code = receipts.category_code and held.karat = receipts.karat
  ) as bucket;
  select coalesce(sum(payable.remaining_piastres), 0)::bigint into v_cash
  from public.purchase_cash_payables as payable
  where payable.shop_id = v_shop and payable.trader_id = p_trader_id;
  select coalesce(jsonb_agg(jsonb_build_object(
    'karat', gold.karat,
    'initial_milligrams', gold.initial_mg::text,
    'remaining_milligrams', gold.remaining_mg::text
  ) order by gold.karat), '[]'::jsonb) into v_gold
  from (
    select obligation.karat,
      sum(obligation.initial_milligrams)::bigint as initial_mg,
      sum(obligation.remaining_milligrams)::bigint as remaining_mg
    from public.gold_obligations as obligation
    where obligation.shop_id = v_shop and obligation.trader_id = p_trader_id
    group by obligation.karat
  ) as gold;
  return jsonb_build_object(
    'ok', true,
    'trader_id', v_trader.id,
    'display_name', v_trader.display_name,
    'phone', v_trader.phone,
    'note', v_trader.note,
    'active', v_trader.active,
    'created_at', v_trader.created_at,
    'original_held_milligrams', v_original::text,
    'current_held_milligrams', v_current::text,
    'pending_receipt_count', v_pending::text,
    'cash_payable_remaining_piastres', v_cash::text,
    'gold_remaining', coalesce(v_gold, '[]'::jsonb),
    'buckets', v_buckets
  );
end;
$fn$;

create function public.list_trader_activity_v1(
  p_trader_id uuid, p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  if p_trader_id is null then raise exception 'invalid_input'; end if;
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  if not exists (
    select 1 from public.traders as trader
    where trader.shop_id = v_shop and trader.id = p_trader_id
  ) then
    raise exception 'not_found';
  end if;
  for v_row in
    select activity.id, activity.kind, activity.created_at, activity.shop_sequence,
      activity.receipt_id
    from (
      select operation.id, operation.kind, operation.created_at, operation.shop_sequence,
        coalesce(detail.payload ->> 'receipt_id', receipt_created.id::text) as receipt_id
      from public.financial_operations as operation
      join public.financial_operation_details as detail
        on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
      left join public.inventory_receipts as receipt_created
        on receipt_created.shop_id = operation.shop_id
       and receipt_created.operation_id = operation.id
      where operation.shop_id = v_shop
        and detail.payload ->> 'trader_id' = p_trader_id::text
      union
      select operation.id, operation.kind, operation.created_at, operation.shop_sequence,
        receipt_created.id::text
      from public.inventory_receipts as receipt_created
      join public.financial_operations as operation
        on operation.shop_id = receipt_created.shop_id
       and operation.id = receipt_created.operation_id
      where receipt_created.shop_id = v_shop
        and receipt_created.trader_id = p_trader_id
      union
      select operation.id, operation.kind, operation.created_at, operation.shop_sequence,
        linked.id::text
      from public.financial_operation_details as detail
      join public.inventory_receipts as linked
        on linked.shop_id = detail.shop_id
       and linked.id::text = detail.payload ->> 'receipt_id'
      join public.financial_operations as operation
        on operation.shop_id = detail.shop_id and operation.id = detail.operation_id
      where detail.shop_id = v_shop and linked.trader_id = p_trader_id
      union
      select operation.id, operation.kind, operation.created_at, operation.shop_sequence,
        null::text
      from public.purchase_cash_payables as payable
      join public.financial_operation_details as detail
        on detail.shop_id = payable.shop_id
       and detail.payload ->> 'purchase_operation_id' = payable.operation_id::text
      join public.financial_operations as operation
        on operation.shop_id = detail.shop_id and operation.id = detail.operation_id
      where payable.shop_id = v_shop and payable.trader_id = p_trader_id
        and operation.kind = 'purchase_settlement'
      union
      select operation.id, operation.kind, operation.created_at, operation.shop_sequence,
        null::text
      from public.gold_obligations as gold
      join public.financial_operation_details as detail
        on detail.shop_id = gold.shop_id
       and detail.payload ->> 'obligation_operation_id' = gold.operation_id::text
      join public.financial_operations as operation
        on operation.shop_id = detail.shop_id and operation.id = detail.operation_id
      where gold.shop_id = v_shop and gold.trader_id = p_trader_id
        and operation.kind = 'gold_obligation_settlement'
    ) as activity
    where v_at is null or (activity.created_at, activity.id) < (v_at, v_id)
    order by activity.created_at desc, activity.id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.created_at, v_row.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'operation_id', v_row.id,
      'kind', v_row.kind,
      'shop_sequence', v_row.shop_sequence,
      'receipt_id', v_row.receipt_id,
      'created_at', v_row.created_at,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

create function public.list_trader_obligations_v1(
  p_trader_id uuid, p_unit text default null,
  p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  if p_trader_id is null then raise exception 'invalid_input'; end if;
  if p_unit is not null and p_unit not in ('egp_piastres', 'gold_mg') then
    raise exception 'invalid_input';
  end if;
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  if not exists (
    select 1 from public.traders as trader
    where trader.shop_id = v_shop and trader.id = p_trader_id
  ) then
    raise exception 'not_found';
  end if;
  for v_row in
    select item.operation_id, item.unit, item.created_at, item.karat,
      item.original_amount, item.remaining_amount
    from (
      select payable.operation_id, 'egp_piastres'::text as unit, payable.created_at,
        null::smallint as karat, payable.initial_piastres as original_amount,
        payable.remaining_piastres as remaining_amount
      from public.purchase_cash_payables as payable
      where payable.shop_id = v_shop and payable.trader_id = p_trader_id
        and (p_unit is null or p_unit = 'egp_piastres')
      union all
      select gold.operation_id, 'gold_mg'::text, gold.created_at, gold.karat,
        gold.initial_milligrams, gold.remaining_milligrams
      from public.gold_obligations as gold
      where gold.shop_id = v_shop and gold.trader_id = p_trader_id
        and (p_unit is null or p_unit = 'gold_mg')
    ) as item
    where v_at is null or (item.created_at, item.operation_id) < (v_at, v_id)
    order by item.created_at desc, item.operation_id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.created_at, v_row.operation_id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'operation_id', v_row.operation_id,
      'unit', v_row.unit,
      'karat', v_row.karat,
      'original', v_row.original_amount::text,
      'remaining', v_row.remaining_amount::text,
      'created_at', v_row.created_at,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

create function public.list_inventory_receipts_v1(
  p_owner_kind text default null, p_trader_id uuid default null,
  p_recognition_policy text default null,
  p_limit integer default 50, p_cursor text default null
) returns jsonb language plpgsql security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_limit integer; v_at timestamptz; v_id uuid;
  v_items jsonb := '[]'::jsonb; v_count integer := 0; v_more boolean := false;
  v_cursor text; v_row record;
begin
  if p_owner_kind is not null and p_owner_kind not in ('shop', 'trader') then
    raise exception 'invalid_input';
  end if;
  if p_recognition_policy is not null
    and p_recognition_policy not in ('immediate', 'deferred', 'custody') then
    raise exception 'invalid_input';
  end if;
  v_limit := private.bounded_limit(p_limit);
  if p_cursor is not null then
    v_at := private.cursor_time(p_cursor);
    v_id := private.cursor_id(p_cursor);
  end if;
  v_shop := private.opening_require_reader_shop();
  if p_trader_id is not null and not exists (
    select 1 from public.traders as trader
    where trader.shop_id = v_shop and trader.id = p_trader_id
  ) then
    raise exception 'not_found';
  end if;
  for v_row in
    select receipt.id, receipt.operation_id, receipt.lot_id, receipt.product_id,
      product.name as product_name, receipt.owner_kind, receipt.trader_id,
      receipt.custodian_kind, receipt.counterparty_name, receipt.category_code,
      receipt.karat, receipt.milligrams, receipt.piece_count,
      receipt.recognition_policy, receipt.received_at,
      receipt.milligrams - coalesce(allocated.allocated_mg, 0) as remaining_mg,
      case when receipt.piece_count is null then null
        else receipt.piece_count - coalesce(allocated.allocated_count, 0) end
        as remaining_count
    from public.inventory_receipts as receipt
    join public.inventory_products as product
      on product.shop_id = receipt.shop_id and product.id = receipt.product_id
    left join lateral (
      select coalesce(sum(allocation.milligrams), 0)::bigint as allocated_mg,
        coalesce(sum(allocation.piece_count), 0)::bigint as allocated_count
      from public.receipt_quantity_allocations as allocation
      where allocation.shop_id = receipt.shop_id
        and allocation.receipt_id = receipt.id
    ) as allocated on true
    where receipt.shop_id = v_shop
      and (p_owner_kind is null or receipt.owner_kind = p_owner_kind)
      and (p_trader_id is null or receipt.trader_id = p_trader_id)
      and (p_recognition_policy is null
        or receipt.recognition_policy = p_recognition_policy)
      and (v_at is null or (receipt.received_at, receipt.id) < (v_at, v_id))
    order by receipt.received_at desc, receipt.id desc
    limit (v_limit + 1)
  loop
    v_count := v_count + 1;
    if v_count > v_limit then v_more := true; exit; end if;
    v_cursor := private.cursor_text(v_row.received_at, v_row.id);
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'receipt_id', v_row.id,
      'operation_id', v_row.operation_id,
      'lot_id', v_row.lot_id,
      'product_id', v_row.product_id,
      'product_name', v_row.product_name,
      'owner_kind', v_row.owner_kind,
      'trader_id', v_row.trader_id,
      'custodian_kind', v_row.custodian_kind,
      'counterparty_name', v_row.counterparty_name,
      'category', v_row.category_code,
      'karat', v_row.karat,
      'milligrams', v_row.milligrams::text,
      'count', case when v_row.piece_count is null then 'null'::jsonb
        else to_jsonb(v_row.piece_count::text) end,
      'remaining_milligrams', v_row.remaining_mg::text,
      'remaining_count', case when v_row.piece_count is null then 'null'::jsonb
        else to_jsonb(v_row.remaining_count::text) end,
      'recognition_policy', v_row.recognition_policy,
      'received_at', v_row.received_at,
      'cursor', v_cursor
    ));
  end loop;
  return jsonb_build_object(
    'ok', true, 'items', v_items,
    'next_cursor', case when v_more then v_cursor else null end
  );
end;
$fn$;

create index financial_operation_details_trader_ref_idx
  on public.financial_operation_details (shop_id, (payload ->> 'trader_id'))
  where payload ? 'trader_id';
create index financial_operation_details_receipt_ref_idx
  on public.financial_operation_details (shop_id, (payload ->> 'receipt_id'))
  where payload ? 'receipt_id';
create index financial_operation_details_purchase_ref_idx
  on public.financial_operation_details (shop_id, (payload ->> 'purchase_operation_id'))
  where payload ? 'purchase_operation_id';
create index financial_operation_details_obligation_ref_idx
  on public.financial_operation_details (shop_id, (payload ->> 'obligation_operation_id'))
  where payload ? 'obligation_operation_id';

-- Labels stock already on the books. Posts no journal and does not edit history.
create function private.reconcile_shop_legacy_lots(p_shop uuid)
returns void language plpgsql security definer set search_path = '' as $fn$
declare
  v_row record;
  v_have_mg bigint;
  v_have_count bigint;
  v_gap_mg bigint;
  v_gap_count bigint;
begin
  perform 1 from public.shops as shop where shop.id = p_shop for update;
  if not found then raise exception 'not_found'; end if;
  for v_row in
    select account.category_code, account.karat,
      coalesce(sum(posting.amount) filter (
        where account.account_kind in ('saleable_metal', 'scrap_metal')
      ), 0)::bigint as milligrams,
      coalesce(sum(posting.amount) filter (
        where account.account_kind = 'saleable_count'
      ), 0)::bigint as pieces,
      bool_or(account.account_kind = 'scrap_metal') as is_scrap
    from public.ledger_accounts as account
    left join public.journal_postings as posting
      on posting.shop_id = account.shop_id and posting.account_id = account.id
    where account.shop_id = p_shop
      and account.account_kind in ('saleable_metal', 'saleable_count', 'scrap_metal')
    group by account.category_code, account.karat
  loop
    select coalesce(sum(movement.delta_milligrams), 0)::bigint,
      coalesce(sum(movement.delta_count) filter (where lot.tracks_count), 0)::bigint
      into v_have_mg, v_have_count
    from public.inventory_lot_movements as movement
    join public.inventory_lots as lot
      on lot.shop_id = movement.shop_id and lot.id = movement.lot_id
    where lot.shop_id = p_shop and lot.stock_class = 'owned_available'
      and lot.category_code = v_row.category_code and lot.karat = v_row.karat
      and (
        movement.operation_id is null
        or movement.operation_id in (
          select synced.operation_id from public.inventory_lot_sync as synced
          where synced.shop_id = p_shop
        )
      );
    v_gap_mg := v_row.milligrams - coalesce(v_have_mg, 0);
    v_gap_count := v_row.pieces - coalesce(v_have_count, 0);
    if v_row.milligrams < 0 or v_row.pieces < 0 or v_gap_mg < 0 or v_gap_count < 0 then
      raise exception 'lot_journal_mismatch';
    end if;
    if coalesce(v_row.is_scrap, false) then
      if v_row.pieces <> 0 or v_gap_count <> 0 then
        raise exception 'lot_journal_mismatch';
      end if;
      if v_gap_mg > 0 then
        perform private.create_stock_lot(
          p_shop, null, 'رصيد سابق مجمّع', 'scrap', v_row.karat,
          v_gap_mg, null, 'owned_available', null, true,
          null, null, 'legacy_reconciliation', 'legacy_reconciliation'
        );
      end if;
    else
      if (v_row.milligrams = 0) <> (v_row.pieces = 0)
        or (v_gap_mg = 0) <> (v_gap_count = 0) then
        raise exception 'lot_journal_mismatch';
      end if;
      if v_gap_mg > 0 then
        perform private.create_stock_lot(
          p_shop, null, 'رصيد سابق مجمّع', v_row.category_code, v_row.karat,
          v_gap_mg, v_gap_count, 'owned_available', null, true,
          null, null, 'legacy_reconciliation', 'legacy_reconciliation'
        );
      end if;
    end if;
  end loop;
  insert into public.inventory_lot_sync (operation_id, shop_id)
  select operation.id, operation.shop_id
  from public.financial_operations as operation
  where operation.shop_id = p_shop
    and not exists (
      select 1 from public.inventory_lot_sync as synced
      where synced.operation_id = operation.id
    );
  perform private.assert_shop_lots(p_shop);
end;
$fn$;

do $inventory_rls$
declare v_table text;
begin
  foreach v_table in array array[
    'inventory_products', 'bullion_denominations', 'coin_types', 'traders',
    'inventory_lots', 'inventory_lot_movements', 'inventory_receipts',
    'receipt_quantity_allocations', 'gold_obligations', 'inventory_explicit_plans',
    'inventory_command_envelopes', 'inventory_catalog_requests',
    'inventory_catalog_events', 'inventory_lot_sync'
  ] loop
    execute format('alter table public.%I enable row level security', v_table);
    execute format('revoke all on table public.%I from public, anon, authenticated', v_table);
    execute format('grant select on table public.%I to authenticated', v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (private.opening_financial_visible(shop_id))',
      v_table || '_select_owner', v_table
    );
    if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
      execute format(
        'revoke insert, update, delete, truncate on table public.%I from service_role',
        v_table
      );
      execute format('grant select on table public.%I to service_role', v_table);
    end if;
  end loop;
end;
$inventory_rls$;

do $inventory_grants$
declare v_signature text; v_name text;
begin
  foreach v_name in array array[
    'parse_signed_amount', 'checked_signed_bigint', 'inventory_reject_mutation',
    'gold_obligations_remaining_only', 'purchase_cash_payables_remaining_only',
    'enforce_one_obligation_unit', 'require_shop_trader',
    'inventory_product_id', 'lot_remaining', 'add_lot_movement', 'create_stock_lot',
    'consume_named_lot', 'consume_fifo', 'post_account_delta', 'assert_operation_lots',
    'assert_shop_lots', 'line_milligrams', 'line_count', 'sync_operation_lots',
    'apply_operation_lots', 'sync_operation_lots_trigger', 'operation_effects',
    'begin_financial_command', 'insert_operation', 'finish_financial_command',
    'parse_expected_day', 'parse_expected_version', 'require_reason', 'replay_or_gate',
    'uuid_or_null', 'post_inventory_command', 'receipt_remaining', 'assert_receipt_bounds',
    'category_quantity', 'validated_tender_sum', 'lock_receipt', 'lock_lots_ordered',
    'take_receipt_quantity', 'insert_receipt_allocation', 'post_owned_increase',
    'post_cash_payment', 'post_inventory_receipt', 'spawn_owned_from_source',
    'post_inventory_recognition', 'post_ownership_transfer',
    'post_receipt_manual_allocation', 'post_gold_acquisition', 'post_gold_settlement',
    'begin_catalog_command', 'finish_catalog_command', 'save_catalog',
    'bounded_limit', 'cursor_text', 'cursor_time', 'cursor_id', 'assert_read_filters',
    'reconcile_shop_legacy_lots'
  ] loop
    for v_signature in
      select p.oid::regprocedure::text
      from pg_catalog.pg_proc as p
      join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
      where n.nspname = 'private' and p.proname = v_name
    loop
      execute format(
        'revoke all on function %s from public, anon, authenticated', v_signature
      );
    end loop;
  end loop;
  foreach v_name in array array[
    'post_inventory_addition_v1', 'post_inventory_removal_v1',
    'post_inventory_correction_v1', 'post_inventory_conversion_v1',
    'post_inventory_receipt_v1', 'post_inventory_recognition_v1',
    'post_ownership_transfer_v1', 'post_receipt_manual_allocation_v1',
    'post_gold_obligation_acquisition_v1', 'post_gold_obligation_settlement_v1',
    'post_daily_ledger_trade_v2', 'save_inventory_product_v1',
    'save_bullion_denomination_v1', 'save_coin_type_v1', 'save_trader_v1',
    'get_inventory_totals_v1', 'list_inventory_lots_v1', 'list_lot_movements_v1',
    'search_traders_v1', 'get_trader_v1', 'list_trader_activity_v1',
    'list_trader_obligations_v1', 'list_inventory_receipts_v1'
  ] loop
    for v_signature in
      select p.oid::regprocedure::text
      from pg_catalog.pg_proc as p
      join pg_catalog.pg_namespace as n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_name
    loop
      execute format('revoke all on function %s from public, anon', v_signature);
      execute format('grant execute on function %s to authenticated', v_signature);
    end loop;
  end loop;
end;
$inventory_grants$;

do $legacy_backfill$
declare v_shop uuid;
begin
  for v_shop in select shop.id from public.shops as shop order by shop.id loop
    perform private.reconcile_shop_legacy_lots(v_shop);
  end loop;
end;
$legacy_backfill$;

commit;

# Milestone 3 backend inventory/custody/obligation contract

Status: reviewed and applied to development project `xchapwvmvoefriqcxtvn` as `20261004081229_milestone_3_inventory_contract.sql`. Codex independently passed all nine SQL suites on fresh disposable PostgreSQL 17.11 database `eldafttar_m3r_41a6bf44`, and authenticated concurrency races on `eldafttar_m3r_5ba38715`; both owned databases were removed afterwards. Hosted inventory and RLS fixtures also passed inside rollback-only transactions. This is a bookkeeping model, not a legal-title or tax determination.

Shop is always derived from the signed-in owner. Public RPCs take no shop id and no actor override. Quantities on the wire are canonical integer strings. Intermediate sums use `numeric`. Same idempotency key with the same canonical payload returns the original result; a changed payload raises `payload_mismatch`.

## Schema (additive)

| Table | Role |
| --- | --- |
| `inventory_products` | Shop product identity: name, category, karat. Category/karat pairs reuse `private.opening_pair_allowed`. |
| `bullion_denominations` | Shop catalog. `nominal_milligrams` is identity only. |
| `coin_types` | Shop catalog. Nominal milligrams optional. |
| `traders` | Protected counterparty records. |
| `inventory_lots` | Immutable lot identity. Remaining quantity is the sum of movements. `legacy_aggregate` labels stock already on the books at migration; it posts no journal. `denomination_id` / `coin_type_id` never replace measured `original_milligrams`. `stock_class` is `owned_available`, `owned_pending`, or `trader_custody`. |
| `inventory_lot_movements` | Append-only quantity deltas. |
| `inventory_receipts` | Immutable physical receipt: owner, shop custodian, counterparty, product/lot, mg/count, server timestamp. |
| `receipt_quantity_allocations` | Recognition, ownership transfer, or verified manual link. Remainder cannot go negative. |
| `gold_obligations` | One unit: milligrams at exactly one karat. Cannot coexist on the same operation as `purchase_cash_payables`. |
| `inventory_explicit_plans` | Lot selections for `post_daily_ledger_trade_v2`. |
| `inventory_command_envelopes` | Wrapper idempotency for that v2 envelope. |
| `inventory_catalog_requests` / `inventory_catalog_events` | Catalog idempotency and audit. |
| `inventory_lot_sync` | Marks operations whose lot movements have been applied. |

Existing `financial_operations.kind`, audit actions, and outbox events are extended. Adjustment clearing accounts (`adjustment_money_clearing`, `adjustment_gold_clearing`, `adjustment_count_clearing`) were added to journal conservation. Old opening/movement clearing kinds remain valid.

Migration backfill `private.reconcile_shop_legacy_lots` labels pre-existing owned journal totals as `legacy_aggregate` lots with `allocation_mode = legacy_reconciliation`. It does not post a second opening or edit history. New openings after this migration create opening lots (`رصيد افتتاحي مجمّع`) with `legacy_aggregate = false` and an origin operation.

## Lock order

Shop row `FOR UPDATE`, then command/envelope row, then open business day, then receipt, then lots by id. Old bucket commands insert `financial_command_requests` last; a deferrable constraint trigger then FIFO-allocates lots. New inventory commands lock lots before posting.

## Public write RPCs

All `SECURITY DEFINER`, `search_path = ''`, granted to `authenticated`, revoked from `anon`/`public`. Failure is `RAISE EXCEPTION` with the stable code only.

Shared write fields: `version` JSON `1` (except the lot-selection envelope below), `kind`, `expected_day_id` (uuid string), `expected_day_version` (canonical integer string). `get_daily_ledger_day_state()` returns `day_version` as a JSON number; the client must send it as a string.

| RPC | `kind` | Effect |
| --- | --- | --- |
| `save_inventory_product_v1` | `product` | Insert-or-replay name/category/karat. Requires an open day. Does not bump `day_version`. |
| `save_bullion_denomination_v1` | `bullion_denomination` | `label`, `nominal_milligrams` string, `active`. Same label with different attributes is `payload_mismatch`. Rows are insert-once. |
| `save_coin_type_v1` | `coin_type` | `label`, `nominal_milligrams` string or JSON null, `active`. Insert-once. |
| `save_trader_v1` | `trader` | `display_name`, `phone`, `note`, `active`. Insert-once. |
| `post_inventory_addition_v1` | `inventory_addition` | `reason` plus `lines[]` (`item_name`, `category`, `karat`, `milligrams`, `count` or null for scrap, `denomination_id`, `coin_type_id`). Posts gold/count against adjustment clearing. Cash untouched. |
| `post_inventory_removal_v1` | `inventory_removal` | `reason` plus `lines[]` (`lot_id`, `milligrams`, `count`). Named owned lots only. Pair-safe. |
| `post_inventory_correction_v1` | `inventory_correction` | `reason`, `cash_deltas[]` (`method`, signed `piastres` string), `metal_deltas[]` (named-lot decrease `{lot_id, milligrams, count}` or new-lot increase `{item_name, category, karat, milligrams, count}`). |
| `post_inventory_conversion_v1` | `inventory_conversion` | Same karat, different category. `source_lot_id`, measured `milligrams`, counts. |
| `post_inventory_receipt_v1` | `inventory_receipt` | `owner_kind` `shop` with `recognition` `immediate` or `deferred`, or `trader` with `recognition` `custody` and `trader_id`. `trader_id` may be omitted or JSON null for shop receipts. Immediate posts owned stock once. Deferred holds `owned_pending` with no owned journal. Custody is excluded from owned stock and cash. |
| `post_inventory_recognition_v1` | `inventory_recognition` | Shop-owned deferred remainder only. Trader custody raises `custody_requires_transfer`. |
| `post_ownership_transfer_v1` | `ownership_transfer` | Trader custody remainder. Either EGP (`price_piastres`, `tenders`, optional `purchase_obligation_piastres` into existing `purchase_cash_payables`) or gold (`obligation_karat`, `obligation_milligrams`). Not both. New cash/gold obligation rows store immutable `trader_id` from the receipt. |
| `post_receipt_manual_allocation_v1` | `receipt_manual_allocation` | Shop-owned deferred receipt plus a matching confirmed `inventory_addition` lot: same shop/product/category/karat/original mg/count, unallocated remainder. Moves pending only. No second owned posting. Duplicate raises `already_allocated`. |
| `post_gold_obligation_acquisition_v1` | `gold_obligation_acquisition` | Shop-owned goods plus a gold payable. No EGP payable. Optional `trader_id` (omit or JSON null keeps the obligation unlinked). Present ids must belong to an active trader in this shop. Seller name is never used to infer a trader. |
| `post_gold_obligation_settlement_v1` | `gold_obligation_settlement` | `obligation_operation_id`, `deliveries[]` of owned lots at the obligation karat. Scrap `count` is JSON null. Cannot exceed remaining milligrams. |
| `post_daily_ledger_trade_v2` | envelope `version` `2` | Explicit lot selection for new clients. Inner command is `public.post_daily_ledger_trade`: inner version `1` without `pricing`, inner version `2` when `pricing` is present (Codex explicit-price migration). `sale` / `scrap_sale` require `lot_selections[]` matching items. `purchase` may send `lot_identities[]` (`denomination_id`, `coin_type_id`). Old v1 bucket commands still FIFO-allocate. |

Success JSON includes `ok`, `operation_id`, `replayed`, and for financial commands `effects.movements` (canonical strings), `receipt_id`, remaining EGP/gold obligation strings.

EGP purchase settlement stays `settle_purchase_cash_payable`. Ownership-transfer cash payables reuse that table and RPC. `purchase_cash_payables.trader_id` and `gold_obligations.trader_id` are nullable, indexed, and immutable after insert. Ordinary table writes remain revoked. Legacy purchases keep `trader_id` null even when `seller_name` matches a trader.

## Public read RPCs

| RPC | Returns |
| --- | --- |
| `get_inventory_totals_v1(category, karat)` | Per-bucket `available_*`, `pending_*`, `held_*` strings. Scrap counts are JSON null. Held is trader custody and is not available. |
| `list_inventory_lots_v1(category, karat, stock_class, query, limit, cursor)` | Paginated lots, remaining quantities, nominal catalog ids, `legacy_aggregate`. Default limit 50, max 100. |
| `list_lot_movements_v1(lot_id, limit, cursor)` | Movement history for one shop lot. |
| `search_traders_v1(query, limit, cursor)` | Name search. |
| `get_trader_v1(trader_id)` | Custody totals plus `cash_payable_remaining_piastres` and `gold_remaining[]` (`karat`, `initial_milligrams`, `remaining_milligrams`) as canonical strings. Unlinked payables/obligations are omitted. |
| `list_trader_activity_v1(trader_id, limit, cursor)` | Receipt, transfer, linked gold acquisition, and cash/gold settlements reached through immutable parent `trader_id`, not seller name. |
| `list_trader_obligations_v1(trader_id, unit, limit, cursor)` | `unit` omitted, `egp_piastres`, or `gold_mg`. Each item: `operation_id`, `unit`, `karat` (JSON null for cash), `original`, `remaining`, `created_at`, `cursor`. Limit 1..100. |
| `list_inventory_receipts_v1(owner_kind, trader_id, recognition_policy, limit, cursor)` | Server-derived `remaining_milligrams` / `remaining_count` (JSON null count for scrap). Immutable receipt/lot/product/owner/trader fields. Limit 1..100. |

Cursor is `UTC timestamp|uuid`. Authenticated owners may also `SELECT` the new tables through RLS (`private.opening_financial_visible`). Direct insert/update/delete are revoked. Append-only triggers reject table mutations.

## Old command lot maintenance

`opening_balances`, `sale`, `purchase`, `scrap_sale`, `scrap_to_stock`, `sale_return`, and `purchase_return` keep lot quantities. Unnamed old clients use deterministic FIFO: shop-owned available lots of that category and karat, `created_at` then `id`, pair-safe. Piece remainder is both-zero or both-positive. Negative remainder raises `negative_owned_balance`. Original operations stay immutable.

## Error codes

`unauthenticated`, `session_expired`, `forbidden`, `shop_unavailable`, `shop_not_active`, `invalid_input`, `negative_amount`, `overflow`, `unsupported_category_karat`, `payload_mismatch`, `not_found`, `stale_day`, `day_closed`, `already_allocated`, `custody_requires_transfer`, `settlement_exceeds_obligation`, `tender_mismatch`, `insufficient_lot`, `insufficient_stock`, `negative_owned_balance`, `stock_pair_mismatch`, `lot_journal_mismatch`, `mixed_obligation_unit`, `audit_append_only`.

## Local evidence (2026-10-04)

Isolated server: PostgreSQL 17.11, host 127.0.0.1 port 55432, user postgres trust. Verification uses a unique disposable `eldafttar_m3r_<8 hex>` database. The migration filename now matches its actual hosted version and sorts after pricing. Runners apply nonempty migrations in version order. Committed bootstrap still guards `eldafttar_test`. Existing databases are preserved. No commit or push was made.

Rollback-only `psql -X -v ON_ERROR_STOP=1` on `eldafttar_backend_test`, leftover users/shops/lots/operations = 0:

| File | Result |
| --- | --- |
| `identity_rls.sql` | `identity_rls_passed` |
| `identity_commands.sql` | `identity_commands_passed` |
| `egypt_owner_registration.sql` | `egypt_owner_registration_passed` |
| `opening_balances.sql` | `opening_balances_passed` |
| `opening_rls.sql` | `opening_rls_passed` |
| `daily_ledger_trades.sql` | passed (includes old scrap sale) |
| `invoice_price_components.sql` | `invoice_price_components_passed` |
| `milestone_3_inventory.sql` | `milestone_3_inventory_passed` |
| `milestone_3_inventory_rls.sql` | `milestone_3_inventory_rls_passed` |

`git diff --check` clean.

Two-connection races: `supabase/tests/run_milestone_3_concurrency.ps1` creates a unique `eldafttar_m3r_*` database, never drops a pre-existing name, applies hosted order, and runs workers as `SET ROLE authenticated` with JWT claims. Different-key recognition: one commit, one `stale_day` or `already_allocated`. Same-key retry: two `ok` rows, one operation. Gold-settlement race: one commit, non-negative remainder, one audit and outbox row, journals balanced. The owned disposable database is dropped afterwards. Single-session tests do not prove this.

## Incomplete for later work

Partial linked returns, exchanges, and invoice-level partial consideration (worked examples 16, 17, 19) are being implemented in a separate compensation migration; existing full linked return remains. Catalog rows cannot be updated after insert. The Flutter client is under review separately. No tax or legal-ownership claim. Clients must page `list_inventory_receipts_v1` rather than truncating table selects at 100 rows.


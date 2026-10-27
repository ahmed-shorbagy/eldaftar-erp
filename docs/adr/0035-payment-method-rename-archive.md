# ADR 0035: Payment method rename and archive (SET-02 / D24)

Status: implemented and applied on development `xchapwvmvoefriqcxtvn` on 2026-10-27. [Validation](../reviews/payment-methods-2026-10-27/validation.md), [deployment](../reviews/payment-methods-2026-10-27/deployment.md). Bounded SET-02 for the four existing cash methods. Does not add custom methods, shared balances, account deletion, or tender `account_id` payloads. Native/owner acceptance remain open.

## Decision (D24)

| Rule | Bound |
| --- | --- |
| Immutable account ID | Each shop’s `cash` / `instant_transfer` / `wallet` / `card` row in `ledger_accounts` keeps its UUID; journals post by `account_id` |
| Rename | Owner may change `display_label_ar` (1–40 Arabic-capable characters). New activity and live ledger reads use the new label |
| Archive | Owner may set `archived_at`. Archived methods are hidden from new entry UIs and rejected on new tender/transfer posts. Balances and history remain |
| Historical label snapshot | On insert into `financial_operation_details`, server stamps each tender (and cash-transfer from/to) with `label_ar` from the account at posting time. Clients must not send `label_ar` |
| No shared balances | One balance per method code per shop (unchanged unique index) |
| No delete with history | Accounts are never deleted; archive only. Custom extra methods remain out of scope |

## Access

Owner-only: `list_shop_payment_methods_v1`, `save_shop_payment_methods_v1` (idempotent key). Members with ledger read see live labels on cash lines; partners/employees do not manage methods.

## Compatibility

Flutter codec accepts shop-specific `label_ar` for the four codes and optional `archived`. Default labels (نقدي / انستا / محفظة / فيزا) remain the backfill and fallback. Full custom methods and tender payloads keyed only by `account_id` stay deferred.

## Acceptance

SQL: rename/archive owner path; non-owner forbidden; archived tender rejected on new trade/transfer; detail payload carries snapshot labels; live `get_daily_ledger_v2` cash uses account labels; no account row deleted. Flutter: «المزيد ← وسائل الدفع» Arabic RTL rename/archive with pending/success/failure. Deploy development with preservation. Native/owner acceptance remains open.

# Deployment 2026-10-21 — journal payment label «انستا»

2026-10-21, Africa/Cairo. Owner-facing instant-transfer copy is «انستا» (not «تحويل فوري» / «إنستا باي»).

## Applied

| Local migration | Hosted | Notes |
| --- | --- | --- |
| `20261021120000_ledger_feed_insta_label.sql` | repaired as applied | Patches `get_ledger_date_v1` and `get_ledger_operation_page` `payment_label` for `instant_transfer` → `انستا` |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` on that migration, then `migration repair --status applied 20261021120000`. No blind `db push`. Existing data preserved.

Hosted readback: both function bodies contain `انستا` and neither contains `تحويل فوري` nor `إنستا باي`.

Flutter UI, PDF, invoice, and codec labels already use `انستا` for `CashMethod.instantTransfer` / `instant_transfer`.

## Validation run

- Hosted function body check for `get_ledger_date_v1` and `get_ledger_operation_page`
- Flutter label sources under `app/lib` have no remaining `تحويل فوري`

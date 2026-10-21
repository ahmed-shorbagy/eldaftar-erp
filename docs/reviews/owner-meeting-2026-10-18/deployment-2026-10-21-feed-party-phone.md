# Deployment 2026-10-21 — optional customer phone on journal feed

2026-10-21, Africa/Cairo. Compact sale/purchase cards show optional «العميل» and «الجوال» when the trade payload recorded them.

## Applied

| Local migration | Hosted | Notes |
| --- | --- | --- |
| `20261021110000_ledger_feed_party_phone.sql` | repaired as applied | Patches `get_ledger_date_v1` and `get_ledger_operation_page` to emit optional `party_phone` from `customer_phone` |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` on that migration, then `migration repair --status applied 20261021110000`. No blind `db push`. Existing data preserved. Hosted readback confirmed both function bodies reference `party_phone`.

Flutter decodes optional `party_phone`, shows name/phone only when present, and keeps cards unchanged when both are absent.

## Validation run

- `flutter test test/ledger_journal_table_test.dart test/ledger_feed_merge_test.dart test/confirmed_ledger_dashboard_test.dart`
- SQL regression source `supabase/tests/ledger_date_read.sql` updated for `party_phone`

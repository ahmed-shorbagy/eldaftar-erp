# Shop staff grants and profile — local validation — 2026-10-26

- ADR: [0033](../../adr/0033-shop-staff-grants-and-profile.md)
- SQL object gate: `SHOP_STAFF_GRANTS_SQL_PASSED` via [shop_staff_grants.sql](../../../supabase/tests/shop_staff_grants.sql) on development after apply
- Flutter: `dart analyze` on shop profile/staff/workspace/accounts — no issues; `flutter test test/shop_account_grants_test.dart` — 3 passed
- Deno handler tests for `shop-staff-create` not run (Deno CLI unavailable on this machine)

Out of scope: HELP-02, ADM-06, analytics month/year, audit browser, NTF-01, payment-method rename, reset/retention, onboarding restoration.

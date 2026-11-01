# Subscription retention warning — validation — 2026-11-01

Status words used below mean different things. **Implemented** is the migration and Flutter code in the tree. **Locally verified** is the disposable Postgres run and the Flutter checks on this machine. **Hosted verified** is the development project `xchapwvmvoefriqcxtvn` after `20261101120000` was applied. **Owner-device accepted** is not claimed.

## Implemented

- [ADR 0038](../../adr/0038-subscription-retention-warning.md): retention ends four shop-local calendar months after `expires_at`. The owner sees `retention_ending` during the last 30 shop-local days and can dismiss it once for that expiry.
- An invalid shop zone uses `Africa/Cairo`. Partners and employees receive no row. Dismissing does not restore writes and does not change financial rows.
- Moving `expires_at` into the future, which is what `redeem_subscription_code` already does, restores writing. No shop row is deleted.
- Flutter shows «اقتراب نهاية مدة الاحتفاظ» with the shop-local date, the renewal action, and the sentence that this notice does not delete data.

## Locally verified

Disposable cluster via `supabase/tests/subscription_retention_local_runner.ps1` on database `eldaftar_retention_a1`:

- `SUBSCRIPTION_RETENTION_MIGRATION_ROLLBACK_PASSED` — rolling the migration back removes `subscription_retention_ends_at`, restores the three-argument kind function, and leaves `list_my_shop_accounts` unchanged.
- `SUBSCRIPTION_RETENTION_SQL_PASSED` — the notice suite, including the 31 January to 31 May calendar step, the warning open and close instants, the Cairo fallback, owner list and one dismissal, stale `expired` during the warning, unchanged financial-operation and shop counts, write denial, write restoration after a later expiry, and an employee seeing nothing.

The hosted guard in that SQL file was re-run on the same cluster after the guard was split so a missing migrations table is skipped. It again printed `SUBSCRIPTION_EXPIRY_NOTICES_SQL_PASSED`.

Flutter, from `app/`:

- `dart format` on the touched Dart files.
- `dart analyze` on the shop-account domain, gateway, banner, and the two tests: **No issues found.**
- `flutter test test/subscription_retention_notice_test.dart test/shop_accounts_gate_test.dart`: **All tests passed** (19). A later isolated run of the retention widget test also passed.

The widget test covers the banner at 320 in light and at 1440 in dark, including the date, the no-deletion sentence, dismiss, and the read-only state that remains. This is a widget check, not a device or screen-reader pass.

## Hosted verified

See [deployment.md](deployment.md). The same SQL file ran on development after the migration was recorded and exited 0. It rolls its fixtures back. Preservation counts of shops, entitlements, memberships, users, and financial rows did not change.

## Not accepted

Owner-device acceptance is open. Nothing is deleted when the four months end; the shop stays read-only. RET-03 reset, NTF-01, ADM-06, and D21 were not implemented.

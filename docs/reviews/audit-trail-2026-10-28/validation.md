# AUD-01 owner audit trail — validation — 2026-10-28

Status words used below mean different things. **Implemented** is the code and migration in the tree. **Locally verified** is the disposable Postgres run and the Flutter checks on this machine. **Hosted verified** is the development project `xchapwvmvoefriqcxtvn` after `20261028120000` was applied. **Owner-device accepted** is not claimed.

## Implemented

- [ADR 0037](../../adr/0037-owner-audit-trail.md): owner-only read of existing `financial_audit_events` through `list_shop_audit_trail_v1`. Newest-first keyset page. Arabic label, actor name from Auth metadata or the shop owner name, server UTC plus shop-local time, optional sequence and operation id, whitelist summary.
- Expired owners with a started entitlement may read. Pending shops get `shop_unavailable`. Partners, employees, count-only assignments, anonymous callers, revoked memberships and cross-shop cursors fail closed.
- Direct `SELECT` policy is owner-only (`financial_audit_events_select_owner`). Append-only trigger and write grants stay as they were. No new audit table, no financial post, no R2 kind.
- Flutter «المزيد ← سجل العمليات» for the owner when the gateway is wired. Loading, empty, retry, access loss, and «تحميل المزيد». Family chips are a server filter.
- Deferred from this feed: identity, grant, invoice message, invoice appearance, closing delegation, support inquiry, and ledger trade-change audit tables. Trade edit and delete already appear here as `trade_edited` and `trade_deleted`.

## Locally verified

Disposable cluster `eldaftar_audit_trail_a3` via `supabase/tests/audit_trail_local_runner.ps1`:

- `AUDIT_TRAIL_MIGRATION_ROLLBACK_PASSED` — rolling the migration back removes `list_shop_audit_trail_v1` and leaves `list_my_shop_accounts` unchanged.
- `AUDIT_TRAIL_SQL_PASSED` — owner page order and redaction, stable second page, deduction filter, stale cursor, expired-owner read, and denials for employee, partner, count-only, anonymous, revoked, pending, expired session, and cross-shop. Postgres `UPDATE`/`DELETE` hit `audit_append_only`. The read does not change `financial_operations` or `financial_audit_events` counts.

Flutter, from `app/`:

- `dart format` on the touched Dart files (no remaining diff).
- `dart analyze` on `lib/src/features/audit_trail`, the workspace and gateway wiring, `lib/main.dart`, and the three audit tests: **No issues found.** An earlier `flutter analyze` invocation crashed inside the Flutter tool snapshot (`analysis_server.dart.snapshot` / `dartaotruntime`) and wrote `app/flutter_01.log`, which was deleted. That crash was the analyzer host, and the later `dart analyze` of the same paths is the completed static check.
- `flutter test test/audit_trail_decode_test.dart test/audit_trail_screen_test.dart test/audit_trail_capture_test.dart`: **All tests passed** (8). Decode, empty/retry, server family filter, paging, access loss, owner link, and staff link hidden.

Arabic RTL widget captures in `app/build/audit-trail-review/` (light and dark, 320, 390, 1440, and 320 at text scale 1.7) were inspected. The title, read-only line, wrapping chips, and cards stay inside the 720-pixel measure. Latin timestamps and ids stay in LTR isolates. Enlarged text wraps the snapshot line onto a second line without an overflow stripe. This is a widget capture, not a device or screen-reader pass.

## Hosted verified

See [deployment.md](deployment.md). Migration applied once, history repaired to applied, hosted rollback script exited 0, and [preservation.json](preservation.json) shows shops, entitlements, memberships, auth users, financial operations, and every counted audit table unchanged. Migration count moved 72 → 73. Latest version moved from `20261027150000` to `20261028120000`.

## Not accepted

Owner-device acceptance is open. NTF-01, ADM-06, RET-01/02/03, custom payment methods, D21 shop-data admin access, and onboarding were not implemented. The feed does not include the deferred audit tables listed above. There is no export action.

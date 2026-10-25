# ADM-03 development deployment — 2026-10-25

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Codex applied only this task's migration after local checks passed and the CLI was re-authenticated to the project owner account. No reset, historical migration repair/replay beyond marking this version applied, data backfill, frontend publication, release build, commit or push.

## Local gates before deployment

- Migration rollback and fixture: `SUBSCRIPTION_EXPIRY_NOTICES_MIGRATION_ROLLBACK_PASSED`, `SUBSCRIPTION_EXPIRY_NOTICES_SQL_PASSED` via [subscription_expiry_notices_local_runner.ps1](../../../supabase/tests/subscription_expiry_notices_local_runner.ps1).
- Flutter: `dart analyze` clean on shop accounts/workspace; `flutter test test/shop_accounts_gate_test.dart` — 15 passed, including notice dismiss and Arabic RTL light/dark widths.
- Evidence: [validation.md](validation.md), [ADR 0029](../../adr/0029-subscription-expiry-notices.md).

## Reconciliation and exact identity

Before deployment, remote history ended at **20261022140217** with **61** migration rows. Local pending nonempty migration for this task was only **20261025093000_subscription_expiry_notices**. Historical timestamp/statement differences between local filenames and earlier hosted identities were left intact. No broad `db push`.

Reviewed/applied bytes: [20261025093000_subscription_expiry_notices.sql](../../../supabase/migrations/20261025093000_subscription_expiry_notices.sql).

SHA-256 of local bytes:
`27DA763465076BA8DB067AC195FEE3F98AF90453EABDFAB7BDC63F40DE971024`.

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` on that path, then `npx supabase migration repair --status applied --yes 20261025093000 --linked --project-ref xchapwvmvoefriqcxtvn`. Repair reported `[20261025093000] => applied`. History is now **62** rows; latest name `subscription_expiry_notices`.

## Hosted verification

[subscription_expiry_notices_hosted.sql](../../../supabase/tests/subscription_expiry_notices_hosted.sql) ran rollback-only on development and returned `SUBSCRIPTION_EXPIRY_NOTICES_HOSTED_SQL_PASSED` (renewal notice list + dismiss for an expired-window-eligible synthetic term; fixture rolled back).

## Preservation

Immediate before snapshot: **2026-10-25 06:40:21.053416 UTC**. After hosted verification: **2026-10-25 06:40:52.883415 UTC**.

Unchanged across application:

| Fingerprint | Value |
| --- | --- |
| Original 61 migration versions MD5 | `b074abf0d0e411211e3084b3df9d9be4` |
| `list_my_shop_accounts` definition MD5 | `7572213dedfcdf389de8497752484701` |
| shops / entitlements / memberships | 12 / 5 / 12 |
| auth users / sessions | 13 / 18 |
| financial_operations | 58 |
| private.subscription_codes | 0 |
| notice dismissals after rollback fixture | 0 |

Grants: authenticated can execute list and dismiss; anon cannot; authenticated has no direct SELECT on `subscription_notice_dismissals`. See [preservation.json](preservation.json).

Frontend remains unpublished. Owner acceptance remains open. No production or other-project deployment was performed.

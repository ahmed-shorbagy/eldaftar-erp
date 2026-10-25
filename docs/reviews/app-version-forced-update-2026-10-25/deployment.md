# ADM-04 development deployment — 2026-10-25

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Applied only this task's migration after local checks passed. No reset, historical migration repair/replay beyond marking this version applied, data backfill, frontend publication, release build, commit or push.

## Local gates before deployment

- Migration rollback and fixture: `APP_VERSION_FORCED_UPDATE_MIGRATION_ROLLBACK_PASSED`, `APP_VERSION_FORCED_UPDATE_SQL_PASSED` via [app_version_forced_update_local_runner.ps1](../../../supabase/tests/app_version_forced_update_local_runner.ps1).
- Flutter: `dart analyze` clean on app-version paths; `flutter test test/app_version_gate_test.dart` — 6 passed.
- React: `npx tsc -b`; `npm test -- --run src/appVersion` — 12 passed.
- Evidence: [validation.md](validation.md), [ADR 0030](../../adr/0030-app-version-forced-update.md).

## Reconciliation and exact identity

Before deployment, remote history ended at **20261025093000** with **62** migration rows. Local pending nonempty migration for this task was only **20261025100000_app_version_forced_update**. Historical timestamp/statement differences between local filenames and earlier hosted identities were left intact. No broad `db push`.

Reviewed/applied bytes: [20261025100000_app_version_forced_update.sql](../../../supabase/migrations/20261025100000_app_version_forced_update.sql).

SHA-256 of local bytes:
`EB1B4C63479CE3D1F4C9072CE2334F8FAA941912944BD2684E16739A4E2FCD14`.

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` on that path, then `npx supabase migration repair --status applied --yes 20261025100000 --linked --project-ref xchapwvmvoefriqcxtvn`. Repair reported `[20261025100000] => applied`. History is now **63** rows; latest name `app_version_forced_update`.

## Hosted verification

[app_version_forced_update_hosted.sql](../../../supabase/tests/app_version_forced_update_hosted.sql) ran rollback-only on development (exit 0): compare, anon read, admin set/clear on windows, table privilege denial; fixture rolled back. Policy row count remained the seeded three platforms with no leftover hosted minimum from the fixture.

## Preservation

Immediate before snapshot: **2026-10-25 06:57:20.72869 UTC**. After hosted verification: **2026-10-25 06:57:47.102133 UTC**.

Unchanged across application:

| Fingerprint | Value |
| --- | --- |
| Versions through 20261025093000 MD5 | `1f3537707a0a47e9b1852d3184fe7ffe` |
| `list_my_shop_accounts` definition MD5 | `7572213dedfcdf389de8497752484701` |
| shops / entitlements / memberships | 12 / 5 / 12 |
| auth users / sessions | 13 / 18 |
| financial_operations | 58 |
| private.subscription_codes | 0 |
| notice dismissals | 0 |

Added: `app_version_policies` (3 seeded platform rows), public get + admin get/set RPCs. Grants: anon and authenticated can execute `get_app_version_policy_v1`; authenticated can execute admin get/set; anon/authenticated have no direct SELECT on the policy table. See [preservation.json](preservation.json).

Frontend remains unpublished. Owner acceptance remains open. No production or other-project deployment was performed.

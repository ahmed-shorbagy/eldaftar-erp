# ADM-02/ADM-08 subscription-code issuance — implementer validation

Date: 2026-10-22. This record is local implementer verification only. Independent review, hosted deployment, frontend publication and owner acceptance were not run. Historical ADM-01, weekly Reports and other evidence were left in place. No commit or push.

## Delivered behavior

A signed-in platform administrator issues a hashed subscription code from selected subscriber detail. Duration is an integer of 1–3660 days. Code validity is an integer of 1–365 days, default 30. There is no month or year conversion. Review names the shop, duration and validity, states that issuance does not activate or extend, and labels any projected expiry as an estimate. The 32-character secret is shown once with an explicit copy action, only in session memory. Dismissal, navigation, unmount and access loss clear it. Timeout freezes the UUID v4 envelope; retry reuses the key. Replay confirms issuance with `code = null` and does not issue another code. History is the selected shop only, keyset-paged, with server-derived unused/expired/redeemed status and no raw codes, hashes, contact, owner identity or financial data.

`public.issue_subscription_code` and `public.redeem_subscription_code` remain the only activation path. Issue and redeem recheck current admin/owner session, identity and ban after contended locks. `service_role` issuance stays compatible. A currently banned owner cannot redeem. An expired D13 owner can renew. Two concurrent owner sessions cannot extend the same code twice.

## Fresh checks

| Gate | Result |
| --- | --- |
| Admin lint | From `admin/`, `npm run lint` (oxlint). Exit 0, no warnings on the passing run. |
| Admin typecheck | From `admin/`, `npx tsc -b --pretty false`. Exit 0. |
| Admin tests | From `admin/`, `npm test -- --maxWorkers=1`. **14 files, 87 tests**, exit 0. |
| SQL rollback, redemption regression, history/issue boundaries, hosted-shape fixture, two-connection race | From the repository root, `pwsh -NoProfile -File supabase/tests/admin_subscription_codes_local_runner.ps1 -Database eldaftar_admin_subscription_codes_adm02imple`. Printed `ADMIN_SUBSCRIPTION_CODES_MIGRATION_ROLLBACK_PASSED`, `SUBSCRIPTION_REDEMPTION_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_HOSTED_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_CONCURRENCY_PASSED`. Exit 0. Dedicated loopback port **55475** was stopped. Database `eldaftar_admin_subscription_codes_adm02imple` was left in the local data directory. Earlier failed suffixes `adm02impl`, `adm02implb` and `adm02implc` were also left in place and not dropped. |
| Dart analysis | From `app/`, `dart analyze` finished with `No issues found!`. Exit 0. |
| Flutter subscription contract | From `app/`, `flutter test test/subscription_activation_test.dart --reporter compact` passed **2** tests. Exit 0. Full `flutter test` and `flutter analyze --no-pub` were not rerun in this pass. |
| `git diff --check` | Exit 0. |

No `npm run build`, release/production build, real code issuance, hosted migration or frontend publication was run.

## Hosted verification script for Codex

Migration identity: `20261022122436_admin_subscription_code_issuance.sql`. Additive forward-only. Local rollback is the runner replacing the final `commit;` with `rollback;` before reapply.

Safe hosted sequence on development `xchapwvmvoefriqcxtvn` only:

1. Record preservation fingerprints for existing shops, entitlements, finance and identity audits. Do not reset.
2. Reconcile migration history, then apply only this pending migration.
3. Run `supabase/tests/admin_subscription_codes_hosted.sql` in a transaction after `select set_config('eldaftar.test_project_ref', 'xchapwvmvoefriqcxtvn', true);`. That fixture inserts synthetic rows and rolls them back.
4. Re-read the preservation fingerprints. Existing shop/entitlement/finance rows must match.

## What this record does not claim

Independent source review was not done. Hosted SQL against `xchapwvmvoefriqcxtvn` was not run. The React frontend was not published. No browser captures at 320/390/1440 were taken in this pass. A synthetic visual harness is at `admin/harness/adm02-subscription-codes` and uses fake display text `SYNTHETICDISPLAYCODE000000000000` only; it is not part of the production entry. Owner acceptance remains open. ADM-07, notices, Help, forced updates, impersonation, revocation, bulk issuance and Milestone 5 remain out of scope.

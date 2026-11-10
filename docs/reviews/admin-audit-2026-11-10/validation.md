# Platform-admin action history — validation and development deployment — 2026-11-10

Scope: [ADR 0046](../../adr/0046-platform-admin-audit.md), Phase 3 of the [admin completion plan](../../operations/admin-completion-plan-2026-11-10.md). No release build, production deployment, app publication or Edge Function change.

## Audit coverage found before the change

| Admin action | History before | After |
| --- | --- | --- |
| Issue subscription code | `private.subscription_code_events` | listed |
| Reveal subscriber contact | `admin_subscriber_contact_reveals` | listed |
| Change support status | `support_inquiry_events` | listed (admin changes only) |
| Set or clear forced-update minimum | last-updated fields only | new trigger events, listed |
| Create/update Help topic or article | last-updated fields only | new trigger events, listed |
| Publish/update/clear announcement | last-updated fields only | new trigger events, listed |

## Local gates

| Gate | Result |
| --- | --- |
| `admin_audit_local_runner.ps1` (fresh database, every migration, rollback check, `admin_audit.sql`) | `ADMIN_AUDIT_MIGRATION_ROLLBACK_PASSED`, `ADMIN_AUDIT_SQL_PASSED` |
| Mutation check: expected row count changed 11 → 12 | failed with `row_count 11` as intended; file restored |
| Overview, app-version, Help and support suites with this migration | all passed |
| `npm run lint` / `npx tsc -b` (admin) | clean |
| `npm test` (admin) | 27 files, 210 tests passed (after the picker fix, the audit files were rerun: 16 passed) |

The support runner first stopped on an incomplete scratch cluster left in TEMP from an earlier failed run (28 October, no `PG_VERSION`). It was moved aside to `data.incomplete-2026-10-28`, not deleted, and the suite then passed.

## Development deployment

Target: **xchapwvmvoefriqcxtvn** only.

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261110120000` | `platform_admin_audit` | `DBC3E0663E7BB98DDEA129A6AB3354E53B1B0F6927258318A0663E6CB5B56092` |

Applied once with `npx supabase db query --linked --yes --file …`, then `npx supabase migration repair --status applied 20261110120000 --linked --yes`. History: 99 → 100 rows, latest `20261110120000`. `admin_audit_hosted.sql` (rollback-only, project ref set transaction-locally) exited 0; the overview hosted check was rerun and also exited 0. Failures through this channel are known to surface (see the [overview record](../admin-overview-2026-11-10/validation.md)).

## Preservation

| Measure | Before | After |
| --- | --- | --- |
| Migration rows | 99 | 100 |
| Shops / entitlements / memberships / Auth users | 12 / 5 / 12 / 14 | 12 / 5 / 12 / 14 |
| Financial operations / `financial_audit_events` / `identity_audit_events` | 75 / 81 / 12 | 75 / 81 / 12 |
| Code events / contact reveals / support events | 0 / 0 / 0 | 0 / 0 / 0 |
| Help topics / articles | 0 / 0 | 0 / 0 |
| `platform_admin_audit_events` | — | 0 |
| Version policy digest | `03554579e9d5f3a088042161a562f1b7` | same |
| Announcement digest | `68934a3e9455fa72420237eb05902327` | same |
| Membership / entitlement digests | `f662ab26…` / `9ab14b7b…` | same |

Before `2026-11-10 14:09:07` UTC, after `2026-11-10 14:10:04` UTC.

## Visual review

Signed in on development at 1240 pixels: «سجل الإدارة» in the rail, family chips, admin picker listing both development admins, local-time snapshot and the empty state (no admin actions since deployment). One defect fixed: the admin picker showed a blank field for «كل المسؤولين» (MUI `displayEmpty`). Populated rows were reviewed with synthetic data in the gitignored harness at 375 pixels in light and dark: five action types, wrapped chips, shop links, and «غير معروف» for an unknown admin. No horizontal overflow.

## Limitations

History begins at this deployment. No date-range filter. Owner acceptance pending. Phase 4 (codes and broadcasts) is next.

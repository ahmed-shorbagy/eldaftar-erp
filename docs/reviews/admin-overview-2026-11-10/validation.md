# Admin overview — validation and development deployment — 2026-11-10

Scope: [ADR 0045](../../adr/0045-admin-overview.md), Phase 2 of the [admin completion plan](../../operations/admin-completion-plan-2026-11-10.md). Not committed. No release build, production deployment, app publication or Edge Function change.

## Local gates

| Gate | Result |
| --- | --- |
| `supabase/tests/admin_overview_local_runner.ps1` (fresh local database, every migration, rollback check of `20261110110000`, then `admin_overview.sql`) | `ADMIN_OVERVIEW_MIGRATION_ROLLBACK_PASSED`, `ADMIN_OVERVIEW_SQL_PASSED` |
| `supabase/tests/admin_subscribers_local_runner.ps1` (ADM-01 regression with this migration applied) | migration rollback, SQL and hosted-fixture checks passed |
| `npm run lint` (admin) | clean, 0 warnings |
| `npx tsc -b` (admin) | clean |
| `npm test` (admin) | 25 files, 194 tests passed |

## Development deployment

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only.

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261110110000` | `admin_overview` | `59219B8109D11EC16B8143E0B3E04B821B3F9829FBDBCE3940C9532A189C2BBB` |

Reconciliation: hosted history had 98 rows, latest `20261110100500`, matching local migrations from 20 October onward; the older version-stamp differences are pre-existing and were left intact. Only this migration was pending. It was applied once with `npx supabase db query --linked --yes --file supabase/migrations/20261110110000_admin_overview.sql`, then recorded with `npx supabase migration repair --status applied 20261110110000 --linked --yes` (`[20261110110000] => applied`). After: 99 rows, latest `20261110110000`.

Hosted verification: `supabase/tests/admin_overview_hosted.sql`, with the transaction-local `eldaftar.test_project_ref` set to the development project, ran through the same channel and exited 0. A deliberate failing probe through that channel returned the raised error and exit 1, so assertion failures surface. The test ends in `rollback`. **Hosted verified.**

## Preservation

| Measure | Before | After |
| --- | --- | --- |
| Migration rows | 98 | 99 |
| Latest version | `20261110100500` | `20261110110000` |
| Shops | 12 | 12 |
| Entitlements | 5 | 5 |
| Memberships | 12 | 12 |
| Auth users | 14 | 14 |
| Financial operations | 75 | 75 |
| `financial_audit_events` | 81 | 81 |
| `identity_audit_events` | 12 | 12 |
| Support inquiries | 0 | 0 |
| Platform admins | 2 | 2 |
| Membership digest (MD5) | `f662ab266ae75397897326ca06ca1f32` | `f662ab266ae75397897326ca06ca1f32` |
| Entitlement digest (MD5) | `9ab14b7bca184a7235740541616fd5e6` | `9ab14b7bca184a7235740541616fd5e6` |

Before snapshot `2026-11-10 13:03:01` UTC; after `2026-11-10 13:04:56` UTC.

## Visual review

Signed in as a development platform admin, Arabic RTL, 1240 and 375 pixels, light and dark. The overview showed figures consistent with the directory (12 shops: 1 active, 7 pending, 4 expired; 8 registrations in 30 days). «اشتراكات سارية» opened `/subscribers?status=active` with one row and «ساري» selected; `/subscribers?status=expiring_30` showed the expiring banner and «عرض كل المتاجر». One defect was found and fixed: clickable tiles centered their content at phone width (MUI `ButtonBase` default); they are now start-aligned like plain tiles. No horizontal overflow at 375 pixels.

## Limitations

Owner acceptance is pending. Windows are rolling durations, not calendar weeks. Registrations and support figures do not open filtered lists. Phase 3 (platform audit browser) is next.

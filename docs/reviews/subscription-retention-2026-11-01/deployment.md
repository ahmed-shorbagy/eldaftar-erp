# Subscription retention warning — development deployment — 2026-11-01

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Applied only this task's migration after local gates, then repaired migration history to `applied`. No reset, broad `db push`, commit, push, app publish, release build, or Edge Function redeploy. All hosted fixtures roll back. No shop data was deleted.

## Migration

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261101120000` | `subscription_retention_warning` | `0904F2FF8527BDC2BA199B2B9504EBAFD440A94268EDC290EA193FE53BA9747B` |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file supabase/migrations/20261101120000_subscription_retention_warning.sql`, then `npx supabase migration repair --status applied 20261101120000 --linked --project-ref xchapwvmvoefriqcxtvn --yes`, which reported `[20261101120000] => applied`. The SQL file was applied once.

## Reconciliation

Before: **73** migration rows, latest `20261028120000` (owner_audit_trail). After: **74** rows, latest `20261101120000`. Historical identities were left intact.

## Hosted verification

`supabase/tests/subscription_expiry_notices.sql` ran through the same linked query channel. It refuses to run on a hosted database that does not have `20261101120000` recorded, replays the notice and retention matrix, and ends in `rollback`. The command exited 0. An assertion failure raises and fails the command. **Hosted verified.**

## Preservation

| Measure | Before | After |
| --- | --- | --- |
| Migration count | 73 | 74 |
| Latest version | `20261028120000` | `20261101120000` |
| Shops | 12 | 12 |
| Entitlements | 5 | 5 |
| Memberships | 12 | 12 |
| Auth users | 13 | 13 |
| Financial operations | 58 | 58 |
| `financial_audit_events` | 59 | 59 |
| `identity_audit_events` | 12 | 12 |
| Grant / invoice message / invoice appearance / closing / support / trade-change audit rows | 0 | 0 |
| Membership role digest (MD5) | `2f2909292baa563ffd378c5dd5c1e969` | `2f2909292baa563ffd378c5dd5c1e969` |

Before snapshot `2026-11-01T09:11:09.980882` UTC. After snapshot `2026-11-01T09:11:59.155431` UTC.

## Limitations

Owner/device acceptance and Flutter publication remain open. The four-month mark does not delete data. RET-03, NTF-01, ADM-06, and D21 stay open. No production deployment.

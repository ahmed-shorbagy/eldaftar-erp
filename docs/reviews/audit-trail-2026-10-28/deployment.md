# AUD-01 owner audit trail — development deployment — 2026-10-28

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Applied only this task's migration after local gates, then repaired migration history to `applied`. No reset, broad `db push`, commit, push, app publish, release build, or Edge Function redeploy. All hosted fixtures roll back.

## Migration

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261028120000` | `owner_audit_trail` | `51DA04557BF13A72757E66A2115E2F1FB11BFDD14B6A217E75598D6E76374844` |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file supabase/migrations/20261028120000_owner_audit_trail.sql`, then `npx supabase migration repair --status applied 20261028120000 --linked --project-ref xchapwvmvoefriqcxtvn`, which reported `[20261028120000] => applied`. The repair needed one retry after a transient Cloudflare 520; the SQL file itself was not applied twice. No Edge Function is required.

## Reconciliation

Before: **72** migration rows, latest `20261027150000` (support_inquiries). The only pending local migration for this task was `20261028120000_owner_audit_trail`; it was reviewed and applied in full. After: **73** rows, latest `20261028120000`. Historical identities were left intact.

## Hosted verification

[audit_trail_hosted.sql](../../../supabase/tests/audit_trail_hosted.sql) ran through the same linked query channel as one script: it refuses to run without the migration row, sets the `app.eldaftar_dev_guard` development marker, replays the local role and behavior matrix, and ends in `rollback`. The command exited 0 with an empty result. An assertion failure raises and fails the command. **Hosted verified.**

## Preservation

Before/after snapshots ([before](preservation-before.json), [after](preservation-after.json), combined [preservation.json](preservation.json), script [preservation.sql](preservation.sql)):

| Measure | Before | After |
| --- | --- | --- |
| Migration count | 72 | 73 |
| Latest version | `20261027150000` | `20261028120000` |
| Shops | 12 | 12 |
| Entitlements | 5 | 5 |
| Memberships | 12 | 12 |
| Auth users | 13 | 13 |
| Financial operations | 58 | 58 |
| `financial_audit_events` | 59 | 59 |
| `identity_audit_events` | 12 | 12 |
| Grant / invoice message / invoice appearance / closing / support / trade-change audit rows | 0 | 0 |
| Membership role digest (MD5) | `2f2909292baa563ffd378c5dd5c1e969` | `2f2909292baa563ffd378c5dd5c1e969` |

The migration inserts no shop or audit rows. The hosted gate rolled back its fixtures.

## Limitations

Owner/device acceptance, Flutter publication, NTF-01, ADM-06, retention/reset, and the deferred audit domains remain open. Direct `SELECT` on `financial_audit_events` is now owner-only; security-definer report counters are unchanged. No production deployment.

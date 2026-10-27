# HELP-02 support inquiries — development deployment — 2026-10-27

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Applied only this task's migration after local gates, then repaired migration history to `applied`. No reset, broad `db push`, commit, push, app publish, or release build. All hosted fixtures roll back.

## Migration

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261027150000` | `support_inquiries` | `EFB83034FD21545675A1A941C2658B5278301AAD77001712FDEEF51B0D0C875D` |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file supabase/migrations/20261027150000_support_inquiries.sql`, then `npx supabase migration repair --status applied 20261027150000 --linked --project-ref xchapwvmvoefriqcxtvn`, which reported `[20261027150000] => applied`. No Edge Function is required by HELP-02.

## Reconciliation

Before: **71** migration rows, latest `20261027140000` (payment_method_labels). The only pending local migration for this task was `20261027150000_support_inquiries`; it was reviewed and applied in full. After: **72** rows, latest `20261027150000`. Historical identities were left intact.

## Hosted verification

[support_inquiries_hosted.sql](../../../supabase/tests/support_inquiries_hosted.sql) ran through the same linked query channel as a single transaction: it refuses to run without the migration row, sets the `app.eldaftar_dev_guard` development marker, replays the full local role/behavior matrix (owner/expired/pending owner create+list, partner/employee/anonymous/revoked/expired-session denials, body/category validation, rate limit, idempotent replay and `payload_mismatch`, `stale_cursor`, admin gate/list/search/transition/replay, append-only audit, shape CHECK) under `set local role authenticated` with forged-free request-claim fixtures, and ends in `rollback`. It exited successfully (any assertion failure aborts the transaction and fails the command), i.e. **SUPPORT_INQUIRIES_HOSTED_DO_BLOCK_PASSED**.

## Preservation

Before/after snapshots ([before](preservation-before.json), [after](preservation-after.json), scripts [before](preservation-before.sql), [after](preservation-after.sql)):

| Measure | Before | After |
| --- | --- | --- |
| Migration count | 71 | 72 |
| Latest version | `20261027140000` | `20261027150000` |
| Shops | 12 | 12 |
| Entitlements | 5 | 5 |
| Memberships | 12 | 12 |
| Auth users | 13 | 13 |
| Financial operations | 58 | 58 |
| Membership role digest (MD5) | `2f2909292baa563ffd378c5dd5c1e969` | `2f2909292baa563ffd378c5dd5c1e969` |
| `support_inquiries` rows | table absent | **0** |
| `support_inquiry_events` rows | table absent | **0** |

The two new tables exist empty after the rolled-back hosted gate: no test data persisted.

## Limitations

Deno handler tests not executed (no new function deployed). Owner/device acceptance on a real device, React admin publication, and any production deployment remain open. Admin rows expose shop id/name/registration-date only; the general D21 data-access proposal is unaffected.

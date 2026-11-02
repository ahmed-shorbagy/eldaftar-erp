# Ledger home read-write transaction — development deployment — 2026-11-02

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Applied only this task's migration after the local gate, then repaired migration history to `applied`. No reset, broad `db push`, commit, push, app publish, release build, or Edge Function redeploy. The hosted home read ran inside a transaction that rolled back. No shop data was deleted.

## Migration

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261102103000` | `ledger_home_read_write` | `422CDA2F16E561D0B676BD7533584DB9AC95B9A757E76F1F39B6F572A574F159` |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file supabase/migrations/20261102103000_ledger_home_read_write.sql`, then `npx supabase migration repair --status applied 20261102103000 --linked --project-ref xchapwvmvoefriqcxtvn --yes`, which reported `[20261102103000] => applied`. The SQL file was applied once.

## Local gate

`supabase/tests/ledger_home_read_write_local_runner.ps1 -Database eldaftar_home_lock_nov02b` reported `LEDGER_HOME_READ_WRITE_ROLLBACK_PASSED` and `LEDGER_HOME_READ_WRITE_SQL_PASSED`. Rollback left the function stable; the applied function is volatile. The SQL fixture rolls back.

## Hosted verification

`provolatile` for `public.get_daily_ledger_home_v1()` changed from `s` to `v`. A rolled-back authenticated read of that function for the affected owner shop returned `state = confirmed`, `read_model_version = 3`, with cash and `journal_context` present. **Hosted verified.**

## Preservation

| Measure | Before | After |
| --- | --- | --- |
| Migration count | 74 | 75 |
| Latest version | `20261101120000` | `20261102103000` |
| Shops | 12 | 12 |
| Entitlements | 5 | 5 |
| Memberships | 12 | 12 |
| Auth users | 13 | 13 |
| Financial operations | 58 | 58 |
| `financial_audit_events` | 59 | 59 |
| `identity_audit_events` | 12 | 12 |

## Limitations

The phone session was not reopened from this machine. The installed app calls the same function, so reopening the daily ledger is the remaining device check. No Flutter code changed.

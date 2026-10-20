# Authorized Supabase deployment — 2026-10-20

The user authorized deployment of all task backend changes to connected project `xchapwvmvoefriqcxtvn`. Codex applied the three reviewed migrations from implementation commit `5076c4f` through the Supabase plugin. All three calls returned success. The project remained ACTIVE_HEALTHY. [Implementation validation](validation.md) remains the historical local test record.

| Local migration | Hosted version | Raw SHA-256 |
| --- | --- | --- |
| [20261019184500_ledger_date_read.sql](../../../supabase/migrations/20261019184500_ledger_date_read.sql) | `20261020061540` | `ee2b7856de50a032db72e46f7677dfd3ab5506c6c3c708647d50397345be7019` |
| [20261019230000_ledger_trade_edit_delete.sql](../../../supabase/migrations/20261019230000_ledger_trade_edit_delete.sql) | `20261020061546` | `e722eff018c241e2c84688f5da0f976c289a1587087948f4072cad34f3337bf0` |
| [20261019233000_ledger_trade_cache_revision.sql](../../../supabase/migrations/20261019233000_ledger_trade_cache_revision.sql) | `20261020061552` | `c5b617279b5f8ed3f642aea6a5f80f611919e97e9dff2221d31df162618d6368` |

All three hosted SQL hashes match the reviewed files after CR removal and surrounding-whitespace trimming. Hosted timestamps were assigned by the plugin. All 42 previous migration hashes remained unchanged, bringing the history to 45 entries. No history repair or blind database push ran.

[Preservation evidence](deployment-evidence-2026-10-20.json), [aggregate query](deployment-preservation-query.sql), and [rollback-only authorization checks](deployment-verification-query.sql) document verification. All 65 pre-existing public base tables plus Auth users/sessions and Storage objects/buckets retained identical counts and full-row SHA-256 fingerprints: **69 of 69 unchanged**. The two new tables are empty. No hosted synthetic identity or financial transaction was created.

The hosted gate returned `HOSTED_LEDGER_AUTHORIZATION_GATES_PASSED`. Both new tables have RLS and an owner-read policy; ordinary clients cannot write directly. New RPCs deny anonymous execution and reject missing identity. Legacy refund/exchange writers and internal wrappers deny ordinary client execution. Private helpers have no client execution grants. Date reads remain STABLE, and installed inactive-operation predicates match the guarded patches.

Security advisor totals remain 112 intentional [authenticated definer RPC notices](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), seven existing [RLS/no-policy information notices](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), and one existing [leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance retains 12 existing unindexed-FK and one no-primary-key notices; unused-index notices increased from 33 to 37 for new indexes without workload. No new missing-FK-index or RLS finding appeared.

The unchanged owner-register Edge Function remains active at version 3. Supabase backend deployment is complete; Flutter UI distribution still requires an application release. No app release/production build, push, reset or real invoice dispatch ran during deployment. Native/two-device behavior and owner acceptance were not established by these checks.

This record was recovered from the retained deployment evidence after its original uncommitted documentation files were removed. Both implementation commits and hosted migrations were independently confirmed intact during recovery.

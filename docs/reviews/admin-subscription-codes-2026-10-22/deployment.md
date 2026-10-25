# ADM-02/ADM-08 development deployment — 2026-10-22

Target: **xchapwvmvoefriqcxtvn**, the authorized development project only. Codex applied only the independently reviewed task migration after local checks passed. No reset, historical migration repair/replay, data backfill, real customer issuance, frontend publication, release build, commit or push.

## Reconciliation and exact identity

Before deployment, 60 hosted migration names matched existing nonempty local migration files. Historical timestamp/statement differences were left intact. The old empty migration file was preserved. This task was the only pending nonempty migration. The API assigned **20261022140217_admin_subscription_code_issuance**; only the new uncommitted local filename was reconciled to that identity. Historical implementer records retain their earlier local identity `20261022122436`.

Reviewed/applied bytes: [20261022140217_admin_subscription_code_issuance.sql](../../../supabase/migrations/20261022140217_admin_subscription_code_issuance.sql).

SHA-256 of local bytes and hosted stored statement are identical:
`81b23fb9d2025d88d41bbe50a0d7c7e4f50bcea9d361300d2db6d18aa78358d8`.

Migration application returned success. It replaces the existing issuance/redemption function bodies, adds narrow private helpers/history RPC/index and reloads the schema cache. It grants no private table access. Installed definition fingerprints and grants are in [preservation.json](preservation.json).

## Hosted rollback verification

Each fixture ran against the pinned development connector inside its own transaction and rolled back synthetic users/shops/codes/terms/audits. No raw codes were returned to tool output or written into evidence. The code fixture and directory fixture set the transaction-local development guard.

- `admin_subscription_codes_hosted.sql`: `ADMIN_SUBSCRIPTION_CODES_HOSTED_SQL_PASSED`; current admin/session/ban/role boundaries, issuance without entitlement changes, secret-free replay and metadata allowlist.
- Original `subscription_redemption.sql`: `SUBSCRIPTION_REDEMPTION_HOSTED_SQL_PASSED`; existing owner binding, renewal, reuse, parameter mismatch, expiry/throttle/replay and D13 regression.
- Existing `admin_subscribers_hosted.sql`: `ADMIN_SUBSCRIBERS_HOSTED_FIXTURE_PASSED`; prior directory isolation preserved. One connector request-state error occurred when dispatching independent verification calls together; the directory fixture was rerun sequentially and passed.

Concurrent redemption was independently verified with real separate local PostgreSQL connections before deployment; hosted tests were rollback-only and did not run concurrent customer operations. Local migration rollback also restored original function-definition fingerprints and removed new objects before reapply.

## Preservation

Immediate before snapshot: **2026-10-22 13:59:35.761241 UTC**. After hosted verification: **2026-10-22 14:26:34.804673 UTC**. All **83 non-migration relations** match both row counts and SHA-256 of sorted JSON rows, covering every public/private table plus auth users/sessions and storage buckets/objects. The earlier 12:19 baseline also matched the immediate before snapshot. This includes shop, entitlement, financial, identity, media registry and subscription audit data. All **60 original migration records** (version/name/statement hash) match exactly; the only added row is this migration, bringing history to **61**. No original migration or data row was changed.

Rollback can consume sequence values; no shared sequences were reset and gap-free numbering is not claimed. Row preservation is the tested guarantee. Synthetic fixtures were rolled back; no customer code was issued. See [metadata-only evidence](preservation.json) for all relation/migration hashes, installed routine hashes and exact grants.

Hosted grants: authenticated can execute guarded history; anon and service_role cannot. Authenticated has no direct private-code SELECT or private-live-session helper execute. Service-role issuance remains authorized. Admins gain no financial/customer/contact/media/general shop access.

Security advisor delta: 13 pre-existing RLS-without-policy informational findings unchanged; authenticated security-definer findings 134 → 135, solely the intentional guarded history RPC; leaked-password-protection configuration warning unchanged. [Security-definer advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). No unrelated Auth configuration changed.

[Independent checks and responsive captures](independent-validation.md). **Frontend remains unpublished and owner acceptance remains pending.** No production or other-project deployment was performed.

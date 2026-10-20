# Owner meeting — authorized Supabase development deployment

2026-10-20, Africa/Cairo. The user explicitly instructed “do them and always do that” after being told the four meeting migrations and staff Edge Function were locally complete but undeployed. That authorizes this application and establishes routine deployment/hosted verification for completed Supabase task work on the existing development project `xchapwvmvoefriqcxtvn`. [AGENTS.md](../../../AGENTS.md) now records that standing instruction. It does not authorize other projects, production, destructive resets, paid resources, application publishing or release builds.

This record supersedes the deployment status of the [local validation checkpoint](validation.md) and [meeting register](audit.md), not their evidence or device/old-app acceptance limits. The existing unrelated shop-image/R2 work was preserved; ongoing R2 attachment changes in the shared workspace are a separate task.

## Applied sources

Preflight confirmed the established project was healthy on PostgreSQL 17.6.1.166. All 45 recorded hosted migration names mapped to local files and their full normalized sources matched, including the previously documented statement-array representation of invoice appearance. The four new APIs/tables were absent. Existing R2 image schema/function and `owner-register` were already present and were not redeployed.

The connected Supabase plugin applied each reviewed migration individually. No blind `db push`, historical migration repair or old migration replay occurred.

| Local source | Hosted version | Result |
| --- | --- | --- |
| `20261020092917_ledger_calendar_home.sql` | `20261020132100` | Applied |
| `20261020094919_closing_count_observations.sql` | `20261020132103` | Applied |
| `20261020100258_temporary_staff_closing_tasks.sql` | `20261020132106` | Applied |
| `20261020121826_invoice_document_render_v2.sql` | `20261020132110` | Applied |
| `20261020132245_closing_delegation_foreign_key_indexes.sql` | `20261020132445` | Applied after fresh local validation |

All five installed migration sources match the local sources after comment/whitespace/statement-separator normalization. The prior 45 versions, names, statement counts and full source hashes are unchanged; the final hosted migration count is 50. All 19 new/replaced function bodies were read back and match their reviewed local bodies exactly after line-ending/outer-whitespace normalization.

`closing-staff-create` is **ACTIVE, version 1**. The deployed eight source/config files match the uploaded local bundle. Its `deno.json` pins `@supabase/supabase-js` to 2.117.1; shared owner-registration helpers are included as bundle dependencies without redeploying `owner-register`. Gateway `verify_jwt=false` is intentional: the handler verifies the bearer through Auth and calls the reservation RPC with that caller's JWT. Only the server adapter uses Auth admin credentials and the service-only finalization RPC. No service credential is shipped to a client or saved in this record.

## Index follow-up

The first hosted performance check identified 14 missing FK indexes on the five new staff/task/audit tables. An index-only follow-up was generated with Supabase CLI 2.121.0, reviewed and applied only after the fresh local runner passed migration rollback, complete FK index coverage, calendar/staff/invoice regressions and the two-connection closing retry race.

The follow-up adds 14 covering indexes and changes no data, policy, grant or product behavior. The hosted catalog coverage gate passes for every FK on those five tables. Unindexed-FK advisor notices returned from 28 to the original 14, with zero remaining on the closing-delegation tables.

## Hosted verification

| Check | Evidence/result |
| --- | --- |
| Calendar and named close | The [calendar regression source](../../../supabase/tests/ledger_calendar_home.sql) passed in a rollback transaction: new-date empty journal with preserved balances, 105-note counters and pagination across reopened sessions, Cairo 23/25-hour DST boundaries, changed shop time zone, future/anonymous/cross-shop rejection, optional unmeasured weights, mismatch blocking and audited idempotent close. |
| Staff boundaries | The [staff regression source](../../../supabase/tests/staff_closing_delegation.sql) passed in a rollback transaction: service-only Auth binding, no general membership, no ledger/financial access, form without expected quantities/cash, revocation/expiry/stale-day/submission access loss, discrepancy review, owner close and linked employee/owner audits. |
| Invoice history | The [invoice regression source](../../../supabase/tests/invoice_appearance.sql) passed in a rollback transaction: owner isolation, logo/parser limits, immutable old copies, white/dark renderer-v2 editions, replay and no source-operation/dispatch effects. |
| FK coverage | The [catalog-only coverage gate](../../../supabase/tests/closing_delegation_index_coverage.sql) passed on the hosted database. |
| Grants and RLS | All five new tables have RLS enabled and deny anonymous/authenticated direct table grants. All 19 reviewed functions have empty search paths and deny anonymous execute. Private helpers and the Auth finalizer deny authenticated execute. Public task/owner RPCs enforce their narrow identities and scopes. |
| Live HTTP | 12 checks passed: CORS; absent/malformed bearer rejection; anonymous RPC denial; real Auth login with a stable admin-reserved UUID; a valid non-staff JWT returning only `not_staff`; Edge rejection of authenticated non-owner creation; malformed-body rejection; ownerless ledger denial; direct staff/task/audit denial; service-only finalization; temporary identity removal. |
| Preservation | Before/after row counts and complete row-content fingerprints match for **all 68 pre-existing public tables**. The three new public tables are empty after verification. All 45 historical migration rows and both pre-existing Edge Function versions were preserved. |

For the hosted SQL runs, only the dedicated-loopback guard was removed from the two locally guarded test sources; the verified target was pinned by the connected tool. Their synthetic fixtures and financial operations rolled back. This did not commit a test sale, invoice, count, close, member or shop.

The live HTTP probe created one uniquely marked, ownerless synthetic Auth identity with email confirmation set directly, logged in, verified authorization boundaries and then removed the identity/sessions. It created no shop, staff account, membership, financial operation or dispatch. No email, SMS, invitation, WhatsApp handoff or customer contact occurred. Normal Auth service logs and consumed sequence numbers are not represented as an absence of all platform-side effects. The HTTP checks do not claim a successful real-owner staff creation/count through a native client; the positive staff workflow was verified in hosted rollback SQL, and the live Auth and Edge authorization boundaries were checked separately.

All credentials, raw fingerprints and detailed HTTP manifests remain outside Git in the private task artifacts. They contain no committed customer data or secrets.

## Advisors and remaining acceptance

Security notices changed as expected: intentional [authenticated definer RPC notices](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) 116 → 128 for the 12 new authenticated APIs; [RLS-with-no-policy information](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy) 7 → 12 for the five intentionally direct-access-denied tables. Their RPC/grant boundaries passed. The pre-existing [leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains unchanged; no Auth policy setting was silently changed.

Performance retains the original 14 [unindexed FK notices](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), one existing [Auth RLS initplan notice](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan) and one existing no-primary-key information notice. [Unused-index information](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) was 36 before and 47 at the final snapshot; the new task/FK indexes remain necessary despite empty tables and limited probe usage. Existing unrelated notices are not claimed resolved.

The prior 1,530 Flutter tests, static analysis, 38 React tests/lint/TypeScript, six Edge handler tests and 228 RTL captures remain the application validation checkpoint. Only the SQL index follow-up, its runner/coverage check, standing instruction and deployment documentation changed in this deployment work, so application builds and unrelated tests were not repeated. Fresh local SQL and hosted SQL/HTTP checks passed, and documentation link/privacy/whitespace checks passed.

Deployment is complete for the meeting backend scope. Native camera/sharing, actual WhatsApp channel/recipient/cancellation behavior, two-device native sync and owner comparison to the complete old app remain acceptance checks. No application release/distribution, production deployment, source push, destructive data reset or paid resource creation was performed.

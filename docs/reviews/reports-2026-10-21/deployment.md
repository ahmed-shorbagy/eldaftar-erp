# Reports development deployment — 2026-10-21

Only the authorized established development project `xchapwvmvoefriqcxtvn` was used. This follows the direct Reports request and standing development-deployment authorization in [AGENTS.md](../../../AGENTS.md). No production/other project, reset, paid resource or application publishing was used.

## Reconciliation and installed artifacts

The pre-deployment history contained the same 57 entries recorded by [October 21 reconciliation](../stabilization-2026-10-21/development-reconciliation.md), including accepted timestamp mappings and the three latest ledger-home/feed migrations. The empty local pagination migration remains unchanged. Only this task's new migration was applied; nothing historical was replayed.

| Local artifact | Hosted result |
| --- | --- |
| `supabase/migrations/20261021125258_financial_day_reports.sql` | Applied through the connected migration API as **20261021125258 / financial_day_reports**. The CLI-created new local file was renamed to the actual hosted version after application; its source is unchanged. Adds owner-only day/report/PDF confirmation reads, service-only PDF metadata registration and the `report_pdf` registry constraints. |
| `supabase/functions/r2-media` | **ACTIVE v3**, updated from v2; all eight deployed source/dependency files match local content after newline normalization. Existing `verify_jwt=false` is preserved because the handler itself verifies the bearer through Auth and resolves owner membership before signing. |
| Other Edge Functions | `owner-register` remains v4 and `closing-staff-create` v1; neither was redeployed. |

The stored migration source and local file have the same whitespace-normalized SHA-256: `d1d6436c567609f8f90fbfad973a0eab7fcb43f67f1268d8bd35e3275ea91cb8`. Final history has **58 rows**. The full-row hash of the original 57 entries, including statement arrays, remains `9cc23dba6758c1ae4ce52e6be2337d85` before/after. There was no history repair or broad database push in this task.

## Hosted verification and preservation

The full [Report SQL fixture](../../../supabase/tests/financial_day_report.sql) passed on development inside one rollback transaction. It covers edits/deletions, actual partial/unpaid cash, independent karats, more than 100 complete detail rows, later-day partial return/replay, inventory-count cash/weight compensation, registry verification/idempotency, stale export and owner/staff/cross-shop/revoked/expired boundaries. Its temporary return grant rolls back. No synthetic Auth account, shop, operation, PDF registry row or staff identity was committed. Rollback does not reverse consumed sequence values or service logging.

Full-row fingerprints and counts before deployment and after hosted tests match across **all 72 public tables**. The migration creates no business data or additional table. Raw manifests and execution logs remain private/ignored; this record contains no customer data or credentials.

Deployed HTTP smoke: unauthenticated `POST /functions/v1/r2-media` for `report_pdf` returned **401 / unauthenticated**. This verifies denial, not a positive native R2 round trip. The authenticated service path is covered by SQL and isolated function/client tests; real device acceptance remains open.

Security advisors were reviewed before and after. Existing 13 deny-by-default RLS-without-policy information items remain unchanged. The authenticated SECURITY DEFINER inventory grows from 127 to 130 for the three explicitly owner-checked public Reports RPCs; anonymous/public execution is revoked and cross-shop/staff denials passed. These API boundary functions intentionally use the existing protected-reader architecture. See [function-exposure advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Existing [leaked-password protection configuration](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remains unchanged and outside this slice. No unexpected advisory category was introduced.

Flutter source remains local until the updated app is run or separately distributed. No commit, push, application publication or release/production build was performed. [Validation and acceptance limits](validation.md).

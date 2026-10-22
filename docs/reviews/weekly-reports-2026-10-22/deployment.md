# Weekly Reports development deployment — 2026-10-22

Only the authorized development project `xchapwvmvoefriqcxtvn` was used. This follows the standing development-deployment authorization in [AGENTS.md](../../../AGENTS.md). No production project, reset, paid resource, broad `db push`, application publishing or release build was used.

## Reconciliation before application

Hosted history had **58** rows. The latest was `20261021125258 / financial_day_reports`. `20261021133552` was absent, and `get_financial_week_report_v1` and `confirm_financial_week_pdf_v1` were absent. Public base tables: **72**. Authenticated `SECURITY DEFINER` functions in `public`: **130**. `r2-media` was already **ACTIVE v3** (updated 2026-10-21). `owner-register` remained v4 and `closing-staff-create` v1. No Edge Function was redeployed.

The full-row SHA-256 of those 58 migration rows, including statement arrays, was `cdc1bdfe1da95382eb1c0aeef4df26ed8872d71bff3418da3ba5a1329144dff5`. Table fingerprints were captured at `2026-10-22T07:25:26.382535+00:00`: 72 public tables plus `auth.users`, `auth.sessions`, `storage.objects` and `storage.buckets` (**76** fingerprints).

## Applied artifact

| Local artifact | Hosted result |
| --- | --- |
| `supabase/migrations/20261021133552_financial_week_reports.sql` | Applied with `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file`, then `npx supabase migration repair --status applied 20261021133552 --linked --project-ref xchapwvmvoefriqcxtvn --yes`. |

Raw file SHA-256: `6a0bd064fe7bc9a356588cc87bdf1217eed89c609dc18bd6f986e36d94592800`. The history row is version `20261021133552`, name `financial_week_reports`, **9** statements. Its whitespace-normalized statement hash is `048733807c80240d81d9df18b4b26c84a6e7f6b0d21b98aa94beceee3ee34665`. Joining those statements and ignoring semicolons matches the local file (5,648 normalized characters).

Installed function bodies:

| Function | SHA-256 of `pg_get_functiondef` | Execute |
| --- | --- | --- |
| `get_financial_week_report_v1(date)` | `3162ce156d51543971309f7b2bb5a7d2e2f83d6e27d56a9c20bcac9181f61f66` | `authenticated` and `service_role`; not `anon` |
| `confirm_financial_week_pdf_v1(date, text, text)` | `527292772a4cac1b636daf8cbcd45514131dbdba8e688dd1a8a9cd70ecf7c45c` | `authenticated` and `service_role`; not `anon` |

`get_financial_day_report_v1`, `confirm_financial_day_pdf_v1` and service-only `record_report_pdf_object_v1` kept the hashes recorded immediately before application. History is now **59** rows. The original 58-row full-row hash is unchanged.

## Hosted verification and preservation

`supabase/tests/financial_week_report.sql` and `supabase/tests/financial_day_report.sql` each ran on development through `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` and exited 0. Both files begin a transaction and roll it back; a failed assertion raises. The CLI prints the last row result rather than notices, so the pass signal is the zero exit after those raises. No synthetic shop, operation, registry row or staff identity was committed.

All **76** fingerprints match the pre-application capture. Public table count stays 72. Authenticated `SECURITY DEFINER` functions in `public` are now **132**, the previous 130 plus the two owner-checked weekly RPCs. Anonymous execute on the weekly read is false.

The Supabase security-advisor API was not available in this session. The equivalent catalog check was reviewed before and after. Public RLS-enabled tables without policies stayed at **6**. With the 7 `private` relations, that is the same 13-relation deny-by-default set recorded for the daily Reports deployment. The new functions are the intentional protected-reader API. See [function-exposure advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Leaked-password protection was not changed. No new table, bucket or media kind was added.

Flutter source remains local until the app is run or separately distributed. No commit, push or release/production build was performed. [Validation and acceptance limits](validation.md).

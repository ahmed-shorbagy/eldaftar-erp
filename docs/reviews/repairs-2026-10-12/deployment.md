# Repairs — development deployment and hosted verification

Date: 2026-10-12. The owner explicitly authorized Codex to handle deployment and related Supabase work through the connected Supabase plugin. Target: the existing development project `xchapwvmvoefriqcxtvn`, PostgreSQL 17.6.1.166, UTC. This record supplements the [earlier independent local validation](validation.md), which remains a historical snapshot. No application distribution, push, release/production build, paid branch creation, data reset or unrelated feature deployment occurred.

## Deployed migrations and history reconciliation

| Reviewed source | Hosted version | Source SHA-256 |
| --- | --- | --- |
| [20261012153000_repairs_custody_and_fees.sql](../../../supabase/migrations/20261012153000_repairs_custody_and_fees.sql) | `20261012134320` | `f2dfd2aa6cb45cd6265707aa1ae9ada3c5c32fbcf390731f1e936d760f556b81` |
| [20261012153001_repairs_foreign_key_indexes.sql](../../../supabase/migrations/20261012153001_repairs_foreign_key_indexes.sql) | `20261012135737` | `64d028e67d2ad77a7ccc098587ccafcdb06351b6cd635103651f7be6ba627325` |

Preflight found no repair tables/RPCs. The latest prerequisite was hosted `20261011140005_required_location_subscription_sync`; its full stored source matched local `20261011120249` after line-ending/outer-whitespace normalization. Existing helpers, sync publication and owner/ledger contracts were present. Previous deployments already document differently timestamped migrations. Only these two reviewed migrations were applied individually with the plugin's `apply_migration`. Their stored statements were read back and matched their source. No old migration was reapplied and no history entry was rewritten. Do not blindly run `db push` against this historically mapped checkout.

Post-deployment advisors identified four new unindexed repair foreign keys. The follow-up adds covering indexes for repair intake actor, linked fee operation, audit actor and custody actor. A cached Supabase CLI **2.120.0** was discovered during this run; `migration new --help` was checked and the follow-up was created with that CLI. Its generated local timestamp `20261012134705` preceded the earlier manually dated `20261012153000` source, so its source filename was adjusted to `20261012153001` to preserve fresh local apply order. Hosted versions remain the plugin-assigned timestamps above. The original reviewed repair source was unchanged. No repair Edge Function deployment was needed and no Auth/project configuration or client credentials changed.

The current Supabase changelog, PostgreSQL minor-release changes, Realtime schema restrictions and RLS guidance were reviewed. Repairs uses protected public sync rows; it does not modify the managed Realtime schema or use affected legacy encryption/custom operators.

## Hosted SQL results

**All 15 SQL suites passed on the hosted development database**, with explicit transactions ending in `ROLLBACK`, synthetic fixture collision checks, and no local Auth/Storage bootstrap:

`identity_rls`, `identity_commands`, `egypt_owner_registration`, `owner_feedback_registration`, `subscription_redemption`, `shop_sync_signals`, `opening_balances`, `opening_rls`, `daily_ledger_trades`, `invoice_price_components`, `milestone_3_inventory`, `milestone_3_inventory_rls`, `ledger_compensation`, `ledger_compensation_edges`, and `repairs_custody`.

The repair suite passed again after the index migration. Its tests cover owner/cross-shop/anonymous/revoked/expired authorization, denied direct writes, original-record/audit immutability, all five karats, exact weights/fees, full/partial/unpaid delivery, custody separation, cancellation/archive outstanding, stale versions, mismatched/duplicate retries, UTC/timezone behavior, context/list/detail reads and rollback after the final command write. The failure-injection trigger was rolled back and is absent from the hosted schema.

Before and after the rollback-only suites, counts stayed: **20 operations, 20 financial audits, 60 journals, 126 postings, 4 shops and 5 Auth users**. Repair rows, events and requests were zero after rollback. RLS was enabled on all four new tables.

A fresh disposable local PostgreSQL 17.11 run additionally passed every migration in source order, the four-index apply/rollback/reapply check, all 15 SQL/RLS suites, and the two-connection race. Its cluster was stopped in `finally`. Evidence: `tmp/repairs/deploy-db-918b4cda-5e22-413d-8eb6-a7138ba5270a-sql.log`. Earlier runner attempts were interrupted or failed on Windows PowerShell native stderr/NOTICE handling; the final Node runner uses native file descriptors and supersedes those wrapper failures. An initial local runner failed because its log made the initdb directory nonempty; that isolated runner was corrected before this successful run.

## Real authenticated API and Realtime results

Two isolated Egyptian owners were registered through the existing `owner-register` Edge Function, then authenticated through Supabase Auth. Exact identity/name guards protected temporary one-hour fixture entitlements. No real shop/account was used for posting.

Real REST RPC checks passed:

- Owner intake and received → in-progress → ready transitions preserve **1255 mg**, 21 karat and the original **15000-piastre estimate**.
- Other-shop detail access is denied and its table read returns no rows. Owner direct DELETE is denied. Anonymous `list_repairs_v1` returns **404 / PGRST202**, because the function is outside the anonymous executable API; authenticated list calls succeed.
- Concurrent same-key partial delivery returns one original result and one replay. Final **20000**, collected cash **8000**, outstanding **12000**; custody releases once. Changed payload with the same key is rejected. Command status reconciles the original repair.
- Concurrent different-key full delivery has one winner and one rejection. Final/collected **20000**, split cash **12000** and wallet **8000**, produces one fee operation.
- Unpaid delivery of **9000** releases custody and retains **9000** outstanding with no financial operation.
- Explicit cancellation returns custody; archive preserves partial outstanding. The outstanding search includes the archived repair and unpaid repair.
- Exactly **two fee operations** exist for the synthetic shop. Over the synthetic opening, cash is **120000 piastres**, wallet **108000**. Its sole owned stock lot stays **5000 mg**. Sales/purchase/gold-movement metrics remain zero.
- An authenticated Realtime subscription receives an UPDATE to the RLS-protected `shop_sync_signals` row with a positive `repair_revision`.
- Actual hosted ledger/context/detail/outstanding JSON decodes through the **current Flutter codecs**, with exact cash, gold and outstanding assertions.

The first HTTP probe expected only 401/403 for anonymous denial and stopped on the valid 404/PGRST202 response. Its cleanup completed; the same guarded synthetic accounts were reused with fresh in-memory test passwords for the corrected probe, rather than creating more accounts. The abandoned ready repair was cancelled through the audited return command. No permission implementation or assertion about successful anonymous access was weakened.

The final HTTP checks passed and the runner exited 0. Runtime keys, passwords and JWTs stayed in memory. Ignored local evidence: `tmp/repairs/hosted-http-manifest.json`, `hosted-http-initial.json`, `hosted-ledger-contract.json`, `deploy-http.mjs`, and `hosted-decode.dart`. No credentials or real customer data enter the repository.

## Cleanup and preserved records

| Synthetic fixture | Owner UUID | Shop UUID |
| --- | --- | --- |
| Repair workflow | `05fbc675-cbb6-47fb-a592-1cba125bd55b` | `5cda0990-fc0e-43cb-b1f6-57f2a2d4cea8` |
| Other-shop isolation | `09d54296-36dc-4ed1-9117-34ab02ad3457` | `08c52eeb-b620-424f-9eac-bbac2225f520` |

Both actors were globally signed out and banned, their exact owner memberships revoked, and fixture entitlements expired. Final verification: **0 live fixture sessions, 0 active fixture entitlements, 2 revoked memberships and 0 held custody**. Five synthetic repair records have five releases; two fee operations and one opening remain auditable. Outstanding **21000 piastres** stays on those inactive synthetic repairs. No financial/customer custody history was deleted to clean a test.

Final global counts: **23 operations, 23 financial audits, 65 journals, 138 postings, 6 shops, 7 Auth users**. All increases are explained by the two retained registration fixtures and the workflow shop's one opening plus two fees. Existing real financial records were preserved. These synthetic rows are deliberately confined to inaccessible, revoked test shops.

## Advisor review and remaining limits

No repair table is missing RLS and no repair RPC is executable by `anon`. Four new foreign-key findings are resolved; six unindexed foreign keys elsewhere predate this work. New-index unused notices are expected at this development traffic level and do not justify removing integrity-supporting indexes. [Performance advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

The security advisor reports nine additional authenticated SECURITY DEFINER endpoints, from 52 to 61. This is intentional: owners call checked transactional/read commands while direct writes remain denied. Each has a fixed search path, checked identity/session/shop access, explicit grants and tested cross-shop denial. [Security-definer advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable). Pre-existing leaked-password-protection and intentionally policy-free internal/audit-table notices remain; unrelated Auth policy/settings were not changed. [Password security guidance](https://supabase.com/docs/guides/auth/password-security).

Deployment, hosted SQL/RLS/API/concurrent-retry/Realtime checks and client response decoding are complete for REP-01/02/03. Native Android/Windows/iOS-to-hosted operation, physical-device keyboard/accessibility review and final owner acceptance remain open. The installed Flutter analysis launcher still needs its missing SDK snapshot; the earlier direct Dart analysis and 606 Flutter/38 React test results remain recorded. Only SQL indexes and documentation changed in this follow-up, so application tests/builds were not repeated. Broader debt settlement, CRM, reminders, reports and invoice customization are still outside this slice. Use the updated Flutter checkout to exercise the deployed repairs entry; no release package was distributed.

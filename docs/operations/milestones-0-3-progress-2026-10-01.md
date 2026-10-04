# Milestones 0–3 completion run — 2026-10-01

The user authorized completion of executable scope through Milestone 3, additive backend updates to project `xchapwvmvoefriqcxtvn`, and Grok implementation delegation. No project commit, push, application publication, data reset, or release build is authorized. External domain/legal approval and iOS signing must remain distinguished from implementation evidence.

## Privacy and delegation

Grok 1.0.41 is installed. Initial launch failed because the Codex sandbox could not read Grok's existing authentication/policy files. Automatic approval review rejected escalation until the user explicitly authorized sending code, tests, and internal technical documentation to xAI. The user supplied that authorization with exclusions for private Word sources, credentials, and customer data. Delegation uses a filtered temporary copy rather than the primary checkout. Codex reviewed the three private Word sources locally; they are excluded from delegation. No credential values were read into the report.

## Work queue

| Work | State |
| --- | --- |
| Audit existing implementation and reconcile scope | In progress; local inspection and Grok read-only audit |
| Preserve historical captures; make capture output configurable | Capture output moved to ignored build paths; previous tracked images restored byte-for-byte |
| Entry recovery, navigation, interactive practice/Help | Navigation and draft-only sale practice implemented and tested; email recovery under Grok review; inventory/trader guides pending their real controls |
| Product/lot identity, denominations, inventory commands and UI | Grok implementing the isolated backend contract; Flutter inventory integration remains open |
| Trader receipts, custody, verified recognition links and obligations | Grok implementing atomic backend commands; client integration and statement remain open |
| Ledger corrections, partial returns/exchanges, price adjustments | Explicit pricing implemented and applied; corrections, partial returns and exchanges remain open |
| Private day notes, pagination, stale/conflict and gap catch-up | Grok implementing the bounded notes/feed slice in a separate filtered copy |
| Accounting examples, ADRs, row-by-row evidence and final acceptance | Queued |

## Baseline checks

These results precede implementation and do not establish milestone acceptance.

- React: `npm run lint`, `npm test` (8 files, 34 tests), and `npx tsc -b` passed.
- Flutter: `flutter analyze --no-pub` terminated with no issues in 72.8 seconds when run with access to the installed SDK/cache. The workspace-sandboxed invocation produced no output. `flutter test --no-pub --reporter compact` passed all 217 tests in 46 seconds.
- Connected Supabase: all 19 repository migrations are present. Existing `daily_ledger_trades.sql` completed without error in one rollback-only transaction. This is a single-session regression suite, not concurrent-session proof.
- Historical captures rewritten by the baseline tests were restored byte-for-byte from the existing repository baseline. Capture helpers are being changed to use ignored build output by default, with `ELDAFTTAR_CAPTURE_DIR` available for a new dated evidence directory.

Exact counts before and after the ledger rollback test:

| Relation | Before | After |
| --- | ---: | ---: |
| auth.users | 2 | 2 |
| shops | 1 | 1 |
| shop_memberships | 1 | 1 |
| shop_entitlements | 1 | 1 |
| business_days | 2 | 2 |
| financial_operations | 16 | 16 |
| financial_operation_details | 15 | 15 |
| financial_command_requests | 16 | 16 |
| financial_audit_events | 16 | 16 |
| financial_outbox | 16 | 16 |
| ledger_accounts | 33 | 33 |
| journals | 47 | 47 |
| journal_postings | 98 | 98 |
| purchase_cash_payables | 2 | 2 |
| invoice_dispatch_confirmations | 0 | 0 |

Baseline security advisor: 17 authenticated SECURITY DEFINER RPC notices, three RLS-enabled/no-policy information notices, and leaked-password protection disabled. These predate this run. Command exposure is intentional only where server-side owner/session/entitlement checks are enforced. Remediation references: [RPC exposure](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

## Current implementation evidence

- Applied `20261001133047_explicit_invoice_price_components.sql` to the connected development project. Version 2 sale/purchase payloads record base, workmanship, described other charges and discount as canonical integer piastres. Version 1 operations and scrap sales retain their existing behavior.
- Local PostgreSQL replay of the original migrations and all six existing SQL/RLS suites passed. The new pricing suite passed locally and remotely in rollback-only transactions. The existing financial regression suite then passed remotely after the migration. Every count in the table above remained identical before and after both remote runs.
- The registration fixture now compares its synthetic additions against existing row counts. Its full local run passed. Automatic approval review rejected the broad remote registration fixture because it includes temporary DDL and trigger setup; that complete fixture has not been run remotely during this work. No rejected action was retried through another route.
- The security and performance advisors introduced no new pricing findings. Existing performance information notices comprise seven unindexed foreign keys, one table without a primary key and five unused indexes; the existing security notices remain as recorded above. Further inventory and media migrations still need their own advisor review.
- The full Flutter suite passed 227 tests after navigation, practice and domain pricing changes. Subsequent pricing UI tests passed, and the three PDF tests passed after adding an adjusted-price fixture. These scoped results do not replace the final full suite after integration.
- React lint, 35 tests in nine files and `npx tsc -b` passed after adding signed-out theme selection and its restart persistence regression test.
- Browser checks at 320 and 1440 pixels found Arabic RTL layout without horizontal overflow; sign-in and theme controls measured 48 pixels high. Both themes were captured; the persisted dark choice survived a reload. New captures live in `docs/reviews/milestones-0-3-2026-10-01/`.
- The adjusted-price Arabic PDF was rendered with Poppler and inspected: the explicit total of 1,040.02 EGP, its four components and split payment remain readable. The test artifact is synthetic and stays in ignored build output.

Milestones 0, 1, 2, and 3 remain open until the complete implementation and acceptance evidence are reconciled. Current progress is not a completion claim.

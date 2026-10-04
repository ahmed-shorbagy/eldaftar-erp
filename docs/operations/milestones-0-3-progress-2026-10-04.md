# Milestones 0–3 continuation — 2026-10-04

This continues the [2026-10-01 implementation record](milestones-0-3-progress-2026-10-01.md). The user's completion request and authorization for additive backend changes to development project `xchapwvmvoefriqcxtvn` remain in effect. Grok receives filtered implementation copies; private source documents, credentials and customer data remain excluded. No project commit, push, release build, data wipe or application deployment is authorized.

## Current reviewed checkout

Arabic workspace navigation, Help resume and a sale practice draft are implemented. Practice completion makes no financial RPC and persists no financial command. Explicit base price, workmanship, described other charges and discount use integer piastres and appear in review, confirmed detail and Arabic PDF. The matching migration is applied to development.

Grok's saved email recovery implementation has been reviewed and integrated. Its fixed callback, PKCE session handling, generic email acknowledgement, disabled duplicate requests, expired-link handling, reset gate and return to password sign-in have domain/HTTP/widget tests. Recovery tokens are excluded from session persistence; the reset screen keeps shop data hidden. Android/iOS scheme declarations and Windows protocol registration/forwarding are present. Native device delivery is not inferred from mocked HTTP or widget captures.

The recovered test had asserted session state before its asynchronous rejection completed. Review changed those assertions to await the same expected exception before checking state; no behavior assertion was removed. Temporary debug probes are absent. Recovery field semantics now use Arabic labels, and capture fonts come from bundled assets and the installed Flutter SDK instead of a Windows font path.

## Validation so far

- Flutter analysis terminated cleanly in 38.8 seconds; all 266 tests passed in approximately 30 seconds after recovery integration. Subsequent recovery accessibility/font changes passed the 28 affected widget/capture tests. The final integration will require a new full run.
- Recovery HTTP, widget and capture checks passed 37 tests before the accessibility/font review. Captures cover request, acknowledgement, failure, reset, rejected password and invalid link at 320/1440 pixels in both themes.
- React gates were rerun on 2026-10-04: lint, all 35 tests in nine files and `npx tsc -b` passed. Signed-out theme selection persists across restart. Browser evidence from 2026-10-01 remains in its original dated directory.
- The recovery widget suite also passed all five tests after adding a regression for Arabic accessible field labels.
- The shared ledger HTTP adapter now rejects delayed reads after the owner changes and treats a possibly committed mutation as unknown, preserving reconciliation. All 18 scoped ledger HTTP and purchase cash-settlement tests passed, including the three new delayed-response regressions. The final full run will include these changes.
- `git diff --check` passed after recovery integration. Historical captures and validation records remain intact.
- Inventory is now applied to development as `20261004081229_milestone_3_inventory_contract`, followed by its composite synchronization index migration. All nine local SQL suites and authenticated two-connection races passed independently. Hosted inventory and RLS rollback fixtures passed with all 23 recorded table counts unchanged. [Exact evidence](milestone-3-inventory-validation-2026-10-04.md). Notes and compensation have not yet been applied.
- Pricing and earlier financial regression records remain intact; current inventory counts are recorded separately from the October 1 baseline.

Representative recovery/workspace captures and review notes are in [the current visual review](../reviews/milestones-0-3-2026-10-04/validation.md).

## Remaining implementation queue

| Slice | Current state |
| --- | --- |
| Inventory, lots, custody and one-unit obligations backend | Reviewed, independently validated and applied to development; hosted rollback gates passed |
| Inventory/trader Flutter client, guides and statement | Generated work integrated into the primary checkout; Codex repairing and validating the combined client |
| Private daily notes and bounded feed/catch-up | Generated client and bounded-feed migration integrated; restart restoration, independent local backend SQL and hosted SQL/Storage validation complete; broader persistence review and LED-05 acceptance remain open |
| Discrepancy correction, partial returns and exchanges | Generated work preserved in an isolated copy; independent review, integration and validation remain |
| Integrated contracts and final acceptance documentation | Pending review and rerun after the implementation slices land |
| Payment-method rename/archive | Generated work preserved in an isolated copy; repair review, shell integration and validation remain |

All four latest Grok implementation/repair runs exited with status `failed` after xAI reported HTTP 402, `Grok Build usage balance exhausted`. These are interrupted runs, not accepted implementations. Their generated files are preserved. Codex is reviewing and integrating the saved changes; no Grok process is continuing in the background.

The first combined notes/inventory Flutter regression run passed 75 tests and failed 10. Review found a duplicated ledger fallback call, Arabic mock responses without UTF-8 headers, invalid single-piece partial-sale fixtures and tests that attempted to find virtualized off-screen controls. Repairs preserve the original business and server-confirmation assertions. Final acceptance still requires a fresh clean full run after all remaining integration.

After those repairs, Codex independently ran `dart format --output=none --set-exit-if-changed lib test` (137 files, zero changes), `flutter analyze` (no issues, 45.7 seconds) and the full `flutter test --reporter expanded` suite (355 tests passed, approximately 45 seconds). `git diff --check` also passed after removing two extra documentation EOF blank lines. This establishes the current integrated checkout's Flutter gate result. It does not establish completion of the unintegrated compensation/payment changes, hosted notes behavior, the remaining persistence review, visual acceptance or native device delivery.

After the user's dashboard sign-in and explicit action-time approval, `eldafttar://auth/recovery` was saved in development project `xchapwvmvoefriqcxtvn`. A fresh dashboard read confirmed one redirect URL and the unchanged site URL `http://localhost:3000`. The [configuration capture](../reviews/milestones-0-3-2026-10-04/supabase-recovery-redirect.jpg) excludes account identity and credentials. SMTP delivery and actual Android/iOS/Windows link handling still require their own evidence.

## Bounded daily-note restart restoration — complete

Only the daily-note restart restoration subtask is complete. LED-05 and milestones 0–3 remain open. The notes backend, hosted validation, corrections and payment settings are outside this change.

The screen now locks text, attachment selection and saving while reading a stored draft and reconciling its key. A completed key displays server-confirmed success and cleans that exact owner/shop/key and its local attachment without posting. Unknown, unavailable and rejected status keep the original text, attachment, key, owner, shop and business day frozen. A separate Arabic status check can unlock editing only on confirmed absence; retry uses the original canonical request. An unread local draft cannot be overwritten after storage failure: an Arabic error and restore retry remain visible. Generation checks discard delayed reads/status results after owner, shop or day changes, and action guards start before asynchronous lookups.

Grok delegation was attempted through the installed relay. Its first launch could not access its local policy/auth files; the authorized launch then exited with HTTP 402, `Grok Build usage balance exhausted`, before making edits. No further balance retry was made. Existing generated work and relay artifacts were preserved; Codex implemented and reviewed this bounded fix directly.

Final independent checks on 2026-10-04:

- Scoped `dart format --output=none --set-exit-if-changed` checked the five affected Dart files: zero changes.
- `flutter analyze`: no issues, 8.3 seconds. The initial analysis reported four brace-style diagnostics, all repaired before this final run.
- `flutter test --reporter expanded`: all 375 tests passed, final reporter time 41 seconds. This includes 16 new restoration regressions and four capture tests, plus the existing eight notes widget tests. The earlier scoped run passed all 28 tests. Initial scoped assertion failures were Dart record/list equality mistakes; the byte-content assertions were corrected, not removed.
- React `npm run lint`, `npm test -- --run` (35 tests across nine files) and `npx tsc -b`: all passed. No React implementation changed.
- Arabic RTL visual review: 24 synthetic captures, six states at 320×900 and 1440×900 in light/dark. Frozen text uses the existing `onSurface` role for readability; no palette change. [Current visual evidence and exact limitations](../reviews/milestones-0-3-2026-10-04/daily-note-restore/validation.md).
- `git diff --check` passed; documentation links, consistency and privacy reviewed. No Supabase edits or SQL/RLS/atomicity gate rerun: this patch changes client restoration and its regression coverage only. Historical server validation remains intact.

Sandboxed analysis/full-suite attempts stalled before output and were interrupted; the final SDK-access runs above completed. No commit, push, deployment, release build or React production build ran. Hosted notes/Storage and real device restart/file picking remain unverified by these synthetic tests.

## Bounded daily-notes backend local validation — complete

Only this local-validation subtask is complete; LED-05 and milestones 0–3 remain open. Codex independently initialized a temporary PostgreSQL 17.11 cluster on `127.0.0.1:55432`, created `eldafttar_notes_test`, applied all 22 earlier nonempty migrations, local Storage fixtures and `20261004090000_daily_notes_and_ledger_pagination.sql`. No migration repair was required. The cross-shop SQL fixture was repaired to capture synthetic foreign IDs before switching to the denied owner, avoiding a null-day default-list call under RLS.

The final frozen notes SQL suite passed with exit 0 and rollback in 89.8708882 seconds. Strengthened checks cover retry operation/request/audit/outbox counts, unchanged cash/stock/scrap/gold/totals around real note RPCs, completed status after closure and actual entitlement expiry, invalid attachment paths/owners, denied object replacement/deletion, notes search/limits, same-shop day isolation and exact string sequences above JavaScript's integer range. All nine existing backend suites also passed: **10/10 SQL suites green**. Post-run counts for shops, operations, requests, audit, outbox, journals, postings, attachments and Storage objects were all zero. The isolated server was stopped; local logs and historical unsuccessful attempts were retained.

[Exact commands, fixture repairs, checks and hosted limitations](daily-notes-pagination-validation.md#independent-local-validation--2026-10-04-complete). `git diff --check`, explicit whitespace checks on the untracked scoped files, and documentation link/consistency/privacy review passed. No application implementation changed; Flutter/React checks were not rerun for this SQL-fixture/documentation scope. No hosted Supabase operation, corrections/payment integration, commit, push, deployment, release or production build occurred. Real hosted Auth/Storage policies, grants, HTTP uploads/RPCs, signed URLs and device behavior remain unverified and require their own authorized validation.

## Bounded daily-notes hosted validation — historical approval checkpoint

The current bounded request permits read-only development inspection and local preparation only, superseding earlier broad additive-backend authorization for this task. Read-only inspection of `xchapwvmvoefriqcxtvn` confirms 22 migrations through inventory synchronization, daily notes absent, actual Auth/Storage schema compatibility, no buckets/Storage policies, and effective client UPDATE/DELETE grants protected by RLS. The hosted direct-delete guard differs from the local bootstrap.

The unchanged notes migration and separate target-fingerprint-guarded rollback harness are prepared for review. Existing local guards and historical records remain intact. [Exact preflight commands, baseline counts, mutation package and limitations](daily-notes-pagination-validation.md#independent-hosted-preflight-and-preparation--2026-10-04-awaiting-approval). Hosted SQL/Storage validation is **not complete**. Applying the notes migration and rollback SQL requires explicit approval; real temporary Storage objects and API cleanup require a separately reviewed approval stage. No corrections/payment integration, commit, push, application deployment or release/production build ran.

## Bounded daily-notes hosted validation — complete

Only this hosted-validation subtask is complete. The user subsequently gave explicit Supabase approval for this task. The notes migration is applied to development `xchapwvmvoefriqcxtvn` as **`20261004120509_daily_notes_and_ledger_pagination`**. A demonstrated hosted Storage ownership failure required one minimal repair: skip the owner-only RLS ALTER when RLS is already enabled. The failed application rolled back fully; the repaired application passed. A regression using the actual migration block verifies both already-enabled non-owner and owner-enable paths. No local bootstrap or weakened local guard was applied to hosted Supabase.

All required hosted synthetic SQL gates passed: owner isolation, retry operation/request/audit/outbox counts, payload mismatch, recognition after closure/expiry, attachment validation, unchanged financial balances/totals and bounded pagination with exact sequence strings. All **36 captured table counts matched** before fixtures, after SQL rollback and after HTTP cleanup. Real Storage HTTP owner upload/read, foreign/anonymous denial, duplicate/replacement denial, no-effect owner deletion, invalid upload rejection and privileged API cleanup passed. Two synthetic Auth accounts and shops plus one image object were removed; financial counts remain at the original baseline. Signed URL creation/read passed, but expiry and device acceptance are not established.

Current routine gates: Flutter formatting (139 files, zero changes), analysis (no issues, 4.8 seconds), all **375 Flutter tests** (42 seconds), React lint, all **35 tests / 9 files**, TypeScript `npx tsc -b`, harness syntax, the Storage ownership regression and whitespace/documentation review passed. [Exact commands, failure/repair evidence, all 36 counts, HTTP results and limitations](daily-notes-pagination-validation.md#independent-hosted-validation--2026-10-04-complete). Historical records and unrelated working files remain intact. No corrections/payment integration, commit, push, application deployment, release or production build ran.

## Next bounded task — daily-note persistence integrity

The next selected task is an independent review of the secure draft and encrypted-image persistence adapters and their submission/restoration call sites. Verify interrupted writes, overlapping save/clear operations, delayed cleanup versus a newer key, concurrent key initialization and owner/shop isolation; repair only demonstrated failures. Hosted backend validation and restart reconciliation remain the established baseline. This task is proposed, not started or accepted.

[Ready-to-use prompt, scope, checks and follow-on limits](daily-notes-persistence-next-task.md). Native secure-storage/file-picker/restart acceptance, app-to-hosted acceptance and signed-URL expiry remain separate later exercises. Inventory/corrections/payment work is not part of the next bounded task.

LED-05 and milestones 0, 1, 2 and 3 remain open. This document records progress, not milestone acceptance or a stakeholder/legal signature.

## Bounded daily-note local persistence integrity — complete

Only this persistence-integrity subtask is complete. Five demonstrated defect categories were repaired in the local adapters and persistence/cleanup call sites, with 13 new actual-adapter regressions. Final scoped formatting and Flutter analysis passed; all 388 Flutter tests, React lint, all 35 React tests in nine files and `npx tsc -b` passed. No backend behavior changed or Supabase operation ran. [Exact commands, reproduction evidence, repairs and limitations](daily-notes-persistence-validation-2026-10-04.md).

Earlier proposed-task and approval checkpoints above are historical. LED-05 and milestones 0–3 remain open; native secure storage, native picking/restart, device-to-hosted acceptance and signed-URL expiry remain unverified. No commit, push, deployment, release/production build or unrelated slice integration ran.

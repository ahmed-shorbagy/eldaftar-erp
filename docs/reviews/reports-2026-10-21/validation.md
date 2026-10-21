# Selected financial-day Reports — validation

Date: 2026-10-21, Africa/Cairo. Starting tree was clean at `2cca1d7`. All work remains uncommitted. The project rules, design contract, delivery/requirements/decisions and October 21 stabilization/development/acceptance records were read. Historical evidence was preserved.

## Delivered behavior

[ADR 0025](../../adr/0025-selected-financial-day-reports.md) defines the bounded accounting contract. Desktop Reports and phone More → Reports open an operational Arabic RTL screen. The owner selects an actual open or historical financial day. Complete server totals distinguish gross/returned/net sales and purchases, expenses, counts, net cash movement and exact independent 14/18/21/22/24k bought/sold weights. Transaction details retain source/reversal labels, source references, actual payment postings, exact metric contributions and inventory compensation. Opening cash is separate from movement; movement is not profit.

Arabic A4 export uses the complete authorized snapshot, bundled Cairo and exact numbers. It uploads through the authenticated R2 broker, requires verified registry metadata and a current fingerprint, verifies the downloaded hash, and then opens owner-selected desktop save or mobile share. A changed snapshot blocks output and requires another review/tap. Read failures clear old totals and expose retry; empty/no-day/loading, duplicate export, failed/unknown handoff, cancellation and success have explicit Arabic states. No weekly/admin action is exposed.

## Fresh checks

| Gate | Result |
| --- | --- |
| Scoped Dart formatting | Passed for changed/new Dart files. |
| Flutter analysis | `flutter analyze --no-pub` was attempted and failed with the already documented SDK launcher problem: the AOT analysis-server snapshot is invoked with the wrong runtime. Direct `dart analyze` passed with no issues. No SDK/global configuration was changed. |
| Complete Flutter suite | **1,573 passed**, zero failures. Baseline invoice samples were redirected to ignored build output to preserve historical review files. |
| Final report regressions | **14 passed** after final navigation/stale-export refinements: phone More navigation, historical selection, empty/error/retry, late-session response discard, cross-session refresh failure, exact values beyond binary integer precision, incomplete/duplicate/mismatched-response rejection, R2 download hash checks, duplicate export, failure retry, render/confirmation staleness and access loss before output. |
| PDF pagination | Final dedicated PDF test passed after layout refinement: 15-transaction synthetic sample **9 A4 pages**, empty sample **1 A4 page**. The earlier byte-size smoke assertion was replaced by meaningful page-count assertions. |
| React | `npm run lint`, `npm test -- --maxWorkers=1`, `npx tsc -b` passed: **9 files / 38 tests**. React source/tokens were unchanged. |
| R2 function | Deno formatting, lint and entrypoint type checking passed; **23 handler/signing tests passed**. New tests cover PDF-only MIME/key scope, bounded size, signature/end marker, content hash and metadata-only registrar calls. |
| Fresh local SQL/RLS/atomicity | Complete [local runner](../../../supabase/tests/ledger_calendar_home_local_runner.ps1) passed in dedicated disposable `eldaftar_owner_meeting_reports_20261021f`: all migrations, prior migration rollback checks, calendar/home/date reads, R2 notes/pagination, pricing, trade/dispatch, trade edit/delete, Reports, staff delegation, appearance, FK coverage and independent two-connection once-only closing. Its loopback cluster was stopped. |
| Report SQL | [Report fixture](../../../supabase/tests/financial_day_report.sql) passed locally and on authorized development inside rollback: exact large opening balance, partial/unpaid purchase distinction, delete reversal, edited replacement, stable fingerprint, historical-day identity, later-day partial return/replay, complete 106-row response, cash/inventory compensation without commerce inflation, unverified/stale PDF denial, metadata retry, cross-shop/count-only-staff/revoked denial and expired-owner reads. No historical return-write grant was retained. |
| Hosted application/preservation | [Deployment record](deployment.md): one pending migration and `r2-media` v3 only. All **72 public table** full-row fingerprints/counts are unchanged. The original **57 migration rows** are byte-for-byte unchanged; history now contains 58. |
| Arabic RTL review | **36 captures**: summary, gold and expanded details × 320/390/1440 × light/dark × 1.0/1.7 text scale. Contact sheets plus representative original-size images were reviewed. Selector clipping was fixed by separating selected date from opening/status text. PDF table columns were corrected to RTL order before final rendering. |
| Documentation/privacy | Current links, scope consistency, synthetic artifact provenance and `git diff --check` reviewed. No source requirement documents, credentials or real customer details were added. |

The initial synthetic trade fixture omitted a mandatory item key; a later compensation fixture omitted retained zero-balance scrap accounts. Both fixtures were corrected to the existing contracts before passing. Intermediate failures are not represented as passing checks.

## Visual evidence

The new [capture directory](captures/) contains only synthetic shop/transaction data. Representative views: [narrow dark enlarged](captures/summary-320-dark-1.7.png), [narrow light](captures/summary-320-light-1.0.png), [desktop dark gold](captures/gold-1440-dark-1.0.png), [desktop light details](captures/details-1440-light-1.0.png). The [final rendered PDF pages](pdf/) include the full multi-page and empty-report samples; the generated PDF files themselves remain ignored build artifacts.

## Acceptance limits

This establishes implementation, SQL authorization/accounting, injected-adapter behavior and Arabic render/layout evidence. It does not claim an actual signed-in native client → Auth → R2 upload/download, physical Android/iOS share target, native Windows save dialog, printer, screen reader or two-device owner acceptance. Those remain device acceptance work. There is no automatic WhatsApp dispatch or delivery claim. Existing Milestone 4 acceptance gaps, weekly reporting, wider period/category aggregation, admin dashboards and legal/tax invoice fields remain open. No commit, push, publish, application release or release/production build ran.

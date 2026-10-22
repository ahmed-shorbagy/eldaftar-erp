# Weekly financial Reports — validation

Date: 2026-10-22. The starting implementation commit is `7c0ae7a`. Planning edits already in the working tree were preserved. The October 21 weekly implementation note and the daily Reports validation/deployment records stay historical. This run did not commit or push.

## Delivered behavior

[ADR 0026](../../adr/0026-weekly-financial-reports.md) is the weekly contract. The week is seven inclusive financial dates ending on the selected date. The server chooses the default end and the selectable bounds. Every owned financial day in the range is included, including more than one day on the same date. An open day that crosses midnight stays one day. Gross, returned and net commerce stay distinct from actual cash movement. Category/karat groups show exact signed net grams and distinct movement counts. Group counts are not a unique weekly operation total, and the report does not allocate one transaction's money across categories.

Arabic RTL Reports opens «فتح التقرير الأسبوعي» for an owner session. The weekly screen keeps the selected end date across refresh, and export stays disabled while a file is in flight. The PDF reuses verified `report_pdf` through `r2-media` and `public.r2_media_objects`. Postgres stores the object key and verified metadata only.

## Fixes before the final gates

- Weekly integer parsing rejects non-string JSON numbers with `FormatException('weekly_integer')`.
- The weekly SQL fixture now hashes as the database owner, registers media through security-definer helpers, and posts inventory compensation with a complete stock payload. Expected phase and combined totals were not changed.
- The local SQL runner executes `financial_week_report.sql` on the reports-only path and on the full path.
- Group titles carry the gram lines in the expansion header, and the list padding includes a keyboard inset when one is present.
- Analyzer infos in the weekly codec, weekly screen, daily weekly-entry guard and the capture test were cleaned. The capture test taps a header only after that header is fully on screen.

Earlier fixture attempts `eldaftar_owner_meeting_weekly_20261022a` through `e` failed on those fixture defects and are not passes. The runner does not drop a database after a failure.

## Fresh checks

| Gate | Result |
| --- | --- |
| Scoped Dart formatting | `dart format` on the changed weekly Dart files. The last pass changed the capture test only. |
| Flutter analysis launcher | `flutter analyze --no-pub` from `app/` failed. The AOT analysis-server snapshot was invoked with the wrong runtime: `analysis_server.dart.snapshot is an AOT snapshot and should be run with 'dartaotruntime'`. No SDK or global configuration was changed. The crash logs were removed. |
| Direct Dart analysis | From `app/`, `dart analyze` finished with no issues. |
| Complete Flutter suite | From `app/`, `flutter test --reporter compact` passed **1,591** tests, exit 0. An earlier invocation from the repository root failed because `test` was not found there; it was rerun from `app/`. |
| Weekly and daily report tests | Weekly domain/codec/gateway/export, widget and PDF tests passed, including the daily report widget and PDF files in the same regression. The capture-only widget cases passed afterward: 12 of 12. |
| React | From `admin/`: `npm run lint` (oxlint, 0 warnings), `npm test -- --maxWorkers=1` (**9 files / 38 tests**), and `npx tsc -b` (exit 0). React source was unchanged. |
| Local SQL, reports only | `ledger_calendar_home_local_runner.ps1 -Database eldaftar_owner_meeting_weekly_20261022f -ReportsOnly` printed `FINANCIAL_WEEK_REPORT_SQL_PASSED`, `REPORTS_SQL_PASSED` and `SQL_EXIT=0`. The daily report fixture in that run also passed. |
| Local SQL, full runner | The same runner on `eldaftar_owner_meeting_weekly_20261022g` printed the weekly and daily report notices, the earlier calendar/home/trade/closing notices, `CALENDAR_HOME_SQL_PASSED` and `SQL_EXIT=0`. The loopback cluster was stopped. |
| Arabic UI | **36** synthetic captures: summary, expanded group and expanded transaction × 320/390/1440 × light/dark × text scale 1.0/1.7. Headers were tapped on screen. A separate 320×900 case at text scale 1.7, with a 280-pixel keyboard inset, found no overflow, found the labels «اختيار آخر يوم في الأسبوع» and «تصدير PDF أسبوعي», and accepted Tab without an exception. That case is a widget assertion, not one of the 36 captures. |
| Arabic PDF | Representative samples were rendered and rasterized at scale 1.5. Weekly empty is 2 pages, categories 6, long 22, same-date 6. Daily complete is 9 pages and daily empty is 1. The shared renderer source was not edited; daily pages were re-rendered for inspection. |

The weekly fixture's phase and combined expectations ran on the fresh local databases, including an opening balance past the binary integer limit, partial and unpaid trades, edit/delete/replacement, a cross-period return, cash transfer, settlement, inventory-count compensation, all five karats, multi-line groups, a fully offset 18k group, fingerprint stability, stale confirmation, registry replay, and denial for anonymous, other-shop, revoked, count-only staff and platform-admin callers. Expired-owner reads remain allowed by the existing reader guard. Report reads do not change financial, dispatch or audit counts inside the fixture.

## Visual evidence

Synthetic shop data only, under [captures](captures/) and [pdf](pdf/). The PDF binaries are ignored; the page rasters are the review files.

Representative UI: [narrow dark enlarged summary](captures/summary-320-dark-1.7.png), [narrow light summary](captures/summary-320-light-1.0.png), [enlarged group](captures/group-390-light-1.7.png), [desktop light summary](captures/summary-1440-light-1.0.png), [desktop dark details](captures/details-1440-dark-1.0.png).

Representative PDF pages: [weekly empty page 2](pdf/weekly-empty-page-2.png) continues the grouping note and the empty-ledger sentence; [category groups](pdf/weekly-categories-page-2.png) keep الصنف on the right and show a zero-net 18k group with two sale movements; [long last page](pdf/weekly-long-page-22.png) still has the repeating header and expense rows; [same-date groups](pdf/weekly-same-date-page-2.png) use the range 2026-10-10 through 2026-10-16; [daily empty](pdf/daily-empty-page-1.png) remains one page. Gold columns read العيار, then المباع, then المشتري. Large balances use grouped digits. Cash movement is not labelled as profit.

## Acceptance limits

This is local implementation evidence plus development-hosted SQL verification in [the deployment record](deployment.md). It does not claim a signed-in native client uploading to R2, a Windows save dialog, an Android or iOS share target, a printer, a screen reader, or two-device owner acceptance. Milestones 4 and 5 stay open. No release build, production build, commit or push ran.

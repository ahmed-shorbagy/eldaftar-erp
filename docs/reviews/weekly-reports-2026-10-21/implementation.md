# Weekly Reports — local implementation, verification deferred

Date: 2026-10-21, Africa/Cairo. The owner explicitly asked to proceed with the next real feature and leave checks/verification for later. The existing staged daily-report implementation, tests, screenshots and deployment records were preserved. No index reset, commit or push was performed.

## Implemented locally

- Reports → «فتح التقرير الأسبوعي» opens an Arabic RTL weekly screen using the existing theme and 720-pixel measure. The labelled end-date picker selects seven inclusive financial dates; the default is chosen by the server. The screen shows the range, snapshot/open-day state, exact money/count/karat totals, expandable category/karat contributions, and complete daily transaction details.
- `supabase/migrations/20261021133552_financial_week_reports.sql` adds `get_financial_week_report_v1(date)` and `confirm_financial_week_pdf_v1(date,text,text)`. It composes complete daily accounting snapshots under one stable read and uses the existing owner authorization boundary. It has no financial writes, new media store or table.
- The separate weekly domain, codec, gateway and export flow preserve exact values, validate complete response relationships and retain the selected range during confirmed sync. Empty, loading, failure/retry/latest-week, changed snapshot, access loss, duplicate export, cancellation and output states have Arabic copy.
- Weekly Arabic A4 output extends the shared daily renderer with range/category grouping, daily subtotals and dated repeating transaction headers. Both report views share the existing transaction-detail content. The HTTP gateway shares the verified R2 upload/confirm/readback implementation while calling the correct daily or weekly domain confirmation RPC.
- [ADR 0026](../../adr/0026-weekly-financial-reports.md) records the explicit seven-date rule, category movement count meaning and non-allocation of lump monetary totals across categories. Delivery/requirements/design/current pointers identify this as local, unverified work.

## Intentionally deferred

No automated tests, analysis, type checks, SQL execution, visual/PDF rendering checks or hosted verification ran for weekly reports. Formatting is source preparation only. The new migration is **pending, not deployed**; the standing development deployment authorization applies to completed, tested backend work, so unverified changes have not been applied. The previously deployed daily report and `r2-media` v3 remain unchanged on development.

Before deployment/acceptance, run these gates as one follow-up:

1. Scoped formatting, Flutter analysis/direct Dart fallback if still necessary, meaningful weekly codec/export/navigation/date-range tests, existing daily regressions, and React lint/tests/`npx tsc -b`. The shared renderer, transaction card and verified media helper need daily regression coverage as well as weekly tests.
2. Fresh local SQL over all migrations. Cover zero/multiple financial days per date, inclusive range boundaries, an open day spanning midnight/DST, server time-zone changes, historical end dates and an empty range. Check whole-week fingerprint stability across independent requests and changes inside/outside the selected period.
3. Assert weekly sums against exact expected postings: partial/unpaid trades, edited/deleted/repeated replacements, cross-period returns, cash transfers, settlements, count compensation, all five karats, multiple categories/lines within one operation, completely offset groups and detail sets larger than feed page limits. Verify distinct per-group movement counts without duplicate weekly operation effects.
4. Exercise anonymous, foreign-shop, count-only staff, revoked/session-lost, platform-admin and expired authorized-owner boundaries. Verify unconfirmed/cross-shop/stale-week PDF rejection and same-file R2 metadata replay, including access/content changes during upload and before native output.
5. Arabic RTL at 320/390/1440 widths, both themes, ordinary/enlarged text and keyboard focus. Render empty, multi-day, long-name/description, all-category/karat and long multi-page PDFs; review repeated headers, totals and numeral direction. Native save/share/R2 acceptance remains separate.
6. Reconcile development migration history and preserve existing data before applying only this pending migration to `xchapwvmvoefriqcxtvn`. Follow with rollback-only hosted fixtures, preservation comparison and a dated deployment record. No Edge Function redeployment is needed for this media-kind reuse.

Weekly Reports is not marked verified, hosted or owner-accepted. This task includes no release/production build, publishing, messages to others or admin dashboard work.

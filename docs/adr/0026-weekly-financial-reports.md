# ADR 0026: Weekly financial reports by category and karat

Status: locally verified and applied on development `xchapwvmvoefriqcxtvn` on 2026-10-22. [Validation](../reviews/weekly-reports-2026-10-22/validation.md), [deployment](../reviews/weekly-reports-2026-10-22/deployment.md). This adds the weekly part of D18/RPT-01/RPT-02/RPT-04. It does not change the historical daily-report acceptance record, close Milestones 4/5, or authorize admin dashboards. Native save/share/print and owner acceptance remain open.

## Selection and accounting

The bounded week is **seven consecutive financial dates ending on the selected date, inclusive**. The Arabic screen explicitly labels the end-date picker and both boundaries. No implicit Saturday/Monday convention is introduced. The initial end date comes from the server's open financial day, otherwise its latest financial day, otherwise the shop-local server calendar date. Historical end dates are selectable. Every owned `business_days` row whose `business_date` falls in the range is included, including multiple financial days with the same date. Calendar-midnight timestamps do not reassign transactions out of an unclosed financial day. The server supplies picker bounds; an existing financial date remains selectable even if a later shop time-zone change places it ahead of the current local calendar date.

`get_financial_week_report_v1(date)` reads a stable PostgreSQL snapshot and reuses the complete daily contract from [ADR 0025](0025-selected-financial-day-reports.md). It returns authoritative weekly totals, all five karat buckets, category/karat groups and every included daily snapshot with complete transaction details. There is no card/feed limit. Money, weights and counts remain integer strings in transport and BigInt in Flutter. Client reconciliation rejects incomplete, duplicate, cross-shop or inconsistent responses; visible totals come from the RPC.

Gross/returned/net sales and purchases, expenses, current operation counts, audit-row counts, opening initialization and actual signed cash retain the daily meanings. Ordinary returns affect the day on which they were posted. Edit/delete source trades and internal reversals do not inflate commerce totals, while their actual postings remain in cash movement. Inventory-count compensation changes actual cash/stock, not commerce quantities. Net cash is never profit.

Category/karat groups show exact net sold and bought grams and distinct operation movement counts, including ordinary returns. A single multi-category or multi-karat transaction can appear in several groups, so group movement counts must not be summed as the unique weekly operation count. Hidden source/reversal quantities have zero commerce contribution and are excluded from groups. A fully offset sale/return group may retain zero net weight and nonzero movement counts.

The trade's total monetary consideration may include discounts, workmanship and charges spanning multiple lines. This slice does not invent a price allocation between categories: money totals stay at the transaction/week level. Group drill-down shows each supporting item's signed weights with its operation and financial date; full monetary transaction details remain under each financial day.

## Output and access

The existing owner-reader guard protects both new public RPCs; anonymous/public execute privileges are revoked. Staff/count-only identities and platform administrators receive no report permission. Existing expired authorized-owner export behavior remains unchanged. Session/access loss discards screen content and blocks output. Sync refresh preserves the selected end date; errors clear old totals and offer retry or a server-chosen latest week.

The weekly Arabic A4 PDF includes the shop, selected boundaries, snapshot time, open-day state, money/count/karat totals, the category/karat table, daily subtotals and complete transaction details. Transaction headings repeat across page breaks with the financial date and operation number. It shares the daily renderer, bundled Cairo and semantic ink tokens. The daily screen and weekly day details share the transaction-detail component.

Reuse the existing verified `report_pdf` R2 kind and its 20 MiB/content-addressed limits. No Edge Function, media kind, bucket, inline bytes or new stored data is introduced. `confirm_financial_week_pdf_v1` requires the current whole-week fingerprint and the same shop/uploader's verified registry row. Generation timestamps and picker metadata are excluded from the content hash; included day ids/state/data remain in it. Export rereads before/after rendering and before external output, detects concurrent changes and clears temporary in-memory PDF bytes. It creates no financial or invoice-dispatch record.

## Delivery boundary

The October 21 [implementation note](../reviews/weekly-reports-2026-10-21/implementation.md) records the first local source drop, when checks were still deferred. The 2026-10-22 [validation](../reviews/weekly-reports-2026-10-22/validation.md) and [development deployment](../reviews/weekly-reports-2026-10-22/deployment.md) are the current evidence. Earlier daily deployment evidence stays intact. No commit, push, publish or release/production build is included.

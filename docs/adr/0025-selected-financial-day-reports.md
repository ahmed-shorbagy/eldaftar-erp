# ADR 0025: Selected financial-day report and Arabic PDF

Status: accepted for this bounded first Reports slice by the owner's direct 2026-10-21 implementation request. Weekly reports, calendar-period aggregation and admin dashboards remain later work under D18. Earlier acceptance records remain historical.

## Report meaning

Select an actual `business_days.id`, including closed historical days. Default to the server's open day, otherwise its most recently opened day. List all owned days; dates, state and shop-local opening times distinguish multiple days with the same date. No device-clock day boundary is used. Open-day reports are explicitly a snapshot up to their server-generated time.

`get_financial_day_report_v1` reads one consistent PostgreSQL statement snapshot. It returns complete transactions and server totals in one response, without a feed/card pagination limit. Every money/weight/sequence/count value travels as an integer decimal string. Flutter uses BigInt and rejects incomplete or inconsistent responses; its card loading never establishes report totals.

- Sales include confirmed sale and scrap sale consideration; purchases include confirmed purchase consideration, including unpaid amounts. Expenses use confirmed expense consideration.
- Edit/delete source trades and their internal reversals are excluded from commerce totals and current operation counts. The final active replacement counts once. Original/reversal rows remain visible with Arabic state labels and original-operation references.
- Ordinary sale/purchase returns subtract consideration and exact returned weights **on the financial day to which the return was posted**. Earlier financial days are not restated by a later-day return. Gross, returned and net money totals are separate. Per-karat sold/bought weights are net of that day's returns and may be negative. No mixed-karat weight total is shown.
- Net cash movement sums the day's signed `cash_method` journal postings, including payment settlements, returns, edits/deletions and inventory-count compensation. Opening balance initialization is shown separately and excluded from movement. Cash transfers cancel across methods. Net cash movement is never called profit.
- Current operation count excludes notes, opening/close markers and hidden edit/delete source/reversal rows. Sale, purchase, expense and ordinary-return counts are separate; full audit row count includes preserved source/reversal and opening/close rows. Count compensation and other confirmed financial operations remain current operations.
- Each detail row exposes its exact contribution to sale/purchase/expense/net cash, actual payment-method postings, item weights and signed inventory change by karat. Count compensation affects cash/inventory, not bought/sold commerce weights.

Example: purchase consideration 500.01 with 200.01 paid reports purchases 500.01 and cash -200.01. Replacing it with an unpaid 600.01 purchase reports purchases 600.01 and net cash zero for the purchase chain. Deleting a 100.01 sale reports zero commerce and zero net cash for its original/reversal pair. A later return of 40.01 / 1.000g of 21k appears as -40.01 net sales / -1.000g sold on the return day.

## Access and output

The authenticated owner reader boundary is enforced inside each public RPC, with a fixed empty search path and revoked anonymous/public execution. Cross-shop ids return no report. Count-only staff and platform administration acquire no report rights. Existing expired authorized-owner reads/exports remain available; revocation/session loss clears client content and blocks output.

Arabic A4 PDF uses bundled Cairo, `pdfArabic`, RTL text and separate LTR numeric runs. It includes the shop, day/status/opening/snapshot time, exact totals, all five karats, complete transaction details and repeating page identification. Shared brown/cream/dark app tokens remain unchanged; printed output uses the established light document ink roles.

The `report_pdf` media kind follows [ADR 0024](0024-cloudflare-r2-media-storage.md): `report-pdf/<shop>/<sha256>.pdf`, PDF-only, maximum 20 MiB. `r2-media` verifies owner scope, bounded bytes, PDF signature/end marker and SHA-256, then calls the service-only metadata registrar. No PDF bytes/base64 or signed URLs enter Postgres. The authenticated domain confirmation requires the verified registry row and the unchanged report fingerprint. Content addressing and insert-on-conflict metadata registration make same-file retries idempotent.

Re-read before rendering, after rendering, at server confirmation and before external output. A changed report requires reviewing the refreshed screen and another export tap. Read back from R2 and verify its hash before owner-selected desktop save or mobile share. Duplicate taps are disabled; failure/cancellation/unavailable/success states are explicit. Export creates no financial operation or invoice/dispatch record. Native share completion does not prove delivery. Native-device acceptance remains separate from adapter and render tests.

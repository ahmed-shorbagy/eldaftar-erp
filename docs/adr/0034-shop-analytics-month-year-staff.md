# ADR 0034: Shop analytics by week, month, year and owner-only staff weights

Status: implemented and applied on development `xchapwvmvoefriqcxtvn` on 2026-10-27. [Validation](../reviews/analytics-2026-10-27/validation.md), [deployment](../reviews/analytics-2026-10-27/deployment.md). Extends D18 for **صفحة التحليلات** (P-20 / RPT-02 wider periods). Does not change daily/weekly books (ADR 0025 / 0026), close Milestone 4/5, or authorize admin dashboards. No profit valuation (D26). Native/owner acceptance remain open.

## Periods

`get_financial_period_analytics_v1(p_period text, p_anchor date)` with `p_period` in `week|month|year`:

| Period | Bounds |
| --- | --- |
| `week` | Seven consecutive financial dates ending on the anchor, inclusive (same as ADR 0026) |
| `month` | Shop-calendar month containing the anchor: all `business_days.business_date` from first to last day of that month in the shop display zone |
| `year` | Shop-calendar year containing the anchor: 1 January through 31 December of that year |

Default anchor: open financial day date, else latest financial day, else shop-local server calendar date. Selectable bounds follow ADR 0026 (`first_business_date` / `last_selectable_date`). Multiple financial days on the same calendar date are all included.

Accounting reuses the complete daily contract from ADR 0025 (gross/returns/net, expenses, net cash as signed cash movement not profit, karat sold/bought). Shop summaries and gold buckets are aggregates over every included day. No invented category price allocation.

## Staff weights

When `private.is_shop_owner(shop)` is true, the response includes `actors[]`: one row per distinct `financial_operations.actor_user_id` that posted sale/purchase (and returns) in the period, with sold/bought milligrams by karat (14/18/21/22/24) using the same hidden/commerce rules as daily gold lines. Display name comes from Auth `raw_user_meta_data.display_name`, else shop `owner_display_name` for the owner membership, else a stable Arabic fallback.

Partners and employees with the `reports` grant receive shop totals only; `actors` is an empty array. Employees never receive other actors’ rows.

## Access and PDF

Public RPCs require `private.allow_member_permission('reports')`. PDF confirmation requires a verified `report_pdf` R2 object for the same shop and uploader, matching the day/week pattern; registry posting remains owner-only via existing `record_report_pdf_object_v1`. `confirm_financial_period_analytics_pdf_v1` rereads the analytics fingerprint before accept.

Arabic A4 PDF lists shop, period bounds, money/count summary, karat sold/bought, and (owners only) the staff weight table. No new media kind.

## Delivery boundary

Flutter route **التحليلات** is separate from **التقارير**. Native share/print and owner acceptance remain open after development deploy.

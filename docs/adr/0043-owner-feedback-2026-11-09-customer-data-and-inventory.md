# ADR 0043: Owner voice notes of 2026-11-09, customer data and instant inventory

Status: implemented and deployed to development on 2026-11-09; not committed. See [validation](../operations/owner-feedback-2026-11-09-batch-b-validation.md).
Date: 2026-11-09
Owners: product owner and engineering reviewer
Related requirement IDs: CRM-01, CRM-02, INV-01. Amends [ADR 0014](0014-customer-directory-notes-and-links.md): the sentence «No matching name or phone imports or merges transaction parties» no longer holds for sales and purchases. Manual link and unlink stay.
Supersedes: none.
Source: [implementation plan](../operations/owner-feedback-2026-11-09-plan-batch-b.md).

## Context

On 2026-11-09 the owner recorded ten voice notes. This record covers the customer page, automatic customer capture from sales and purchases, and the instant-inventory item table. Customers were created and linked only by hand. The customer list was a long text card titled «العملاء». Instant inventory listed lots, with no item-by-karat table and no figure strip. Closing a day must keep customer files and the instant-inventory table as they were.

## Decision

B-D1. The customers page is «بيانات العملاء» in the app bar, the phone navigation bar, the desktop rail, tooltips, and the workspace placeholder.

B-D2. The list keeps the old page’s body: figures at the top, then one card per customer. The uniform is the current brown, cream, and dark palette.

B-D3. Every confirmed sale and purchase with a customer phone or name creates or links a customer, including a new post, an edit replacement, and an exchange. Returns, expenses, and notes do not. One shop has one customer per normalized phone.

B-D4. Match the phone first. A valid phone of an active customer links that customer. A valid phone with no customer creates one. A phone owned by an archived customer links nothing and creates nothing. With no valid phone, one active customer of the same trimmed name is linked; none creates a customer without a phone; two or more link nothing. An invalid phone counts as no phone.

B-D5. An auto-created name is the trimmed sale name when it is 1–200 characters and contains an Arabic letter. Otherwise the name is «عميل {phone}» with the phone as typed. With neither a valid name nor a valid phone, nothing is created.

B-D6. Auto-capture never renames a customer and never changes its phones, VIP flag, notes, or open request.

B-D7. Auto-capture runs in the sale’s transaction and never makes the sale fail. An error inside it is caught. The sale commits without a customer link.

B-D8. Operations recorded before this change are not backfilled.

B-D9. Customers stay owner-only. An employee’s or partner’s sale still creates the customer on the server. Only the owner sees «بيانات العملاء».

B-D10. The instant-inventory table rows are item names of owned, available worked jewelry. Columns are karats. Each cell shows the piece count and the weight. Bullion and coins keep their sections. Scrap is the last row, weight only.

B-D11. The shop’s karat order is the four jewelry karats, default 18, 21, 22, 14. The first two always show. «عيارات أخرى» shows the other two. «ترتيب العيارات» reorders the four. The order and the expanded state are saved per shop on the device.

B-D12. The page starts with six figures in the ledger’s metric tile.

B-D13. Karat cells are 58 logical pixels with 4-pixel gaps (62 in the plan; narrowed on review so four karats fit a 375 px phone, as the owner asked). The item name takes the rest, at least 72, on up to two lines. Grams in the table use two decimals. With two karats the table does not scroll sideways at 375 px. When four columns do not fit, the table scrolls sideways and the name stays first.

B-D14 (review of 2026-11-09). A sale line takes stock from lots of the same item name first, then from the pooled opening lot «رصيد افتتاحي مجمّع», then from the oldest lot of the same category and karat. Before this, every sale took the oldest lot, so selling «خاتم» could reduce «سلسلة» in the table. Category and karat balances do not change; only the lot chosen does. The table shows the pooled opening lot as «رصيد افتتاحي (بدون صنف)». Opening stock has no item breakdown, so that row shrinks as unnamed or unmatched items are sold.

B-D15 (review of 2026-11-09). The customer list follows the owner's design order: search, then the four figures in one row at every width, then «قائمة العملاء». A card shows «منذ N يوم» from the viewer's date for display only, and the date when the device clock is behind. Small karat labels keep `onSurface` for contrast. The detail summary also lists grams the customer sold to the shop and the last confirmed operation.

Closing a day does not change customer rows, phones, notes, links, or events, and it does not change the instant-inventory table. Cash and gold balances still carry over, as in ADR 0042.

## Data and compatibility impact

Money stays integer piastres and gold stays integer milligrams. New migrations only, after `20261109100200`.

- `get_customer_overview_v1` returns active, VIP, active-in-30-days, and open-request counts as text. Partners and employees are forbidden.
- Trigger `financial_operation_details_customer_capture` calls `private.customer_auto_capture` after each detail insert. The capture’s exception block rolls back only its own writes.
- `customer_events` may record `source: 'auto'`.
- Customer reads that join `customer_operation_links` to operations ignore operations hidden by edit or delete.
- `private.consume_fifo_named` orders lots by the same item name, then pooled opening stock, then age. `private.apply_operation_lots_before_compensation` calls it for sale lines (`20261109120000_sale_consumes_named_item.sql`).
- `get_inventory_item_grid_v1` aggregates owned available worked jewelry by item name and karat, and returns scrap from the same balance `get_inventory_totals_v1` uses. It requires the inventory grant.

## Verification

- `app/test/customer_data_layout_test.dart`
- `app/test/inventory_item_grid_test.dart`
- `app/test/financial_trade_screen_test.dart`
- `supabase/tests/customers.sql`
- `supabase/tests/customer_auto_capture.sql`
- `supabase/tests/inventory_item_grid.sql`
- `supabase/tests/day_close_keeps_customers_and_inventory.sql`
- `supabase/tests/sale_named_item_and_day_read.sql`
- `app/test/owner_feedback_2026_11_09_fixes_test.dart`

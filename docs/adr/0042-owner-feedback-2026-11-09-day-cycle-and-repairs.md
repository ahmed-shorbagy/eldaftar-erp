# ADR 0042: Owner voice notes of 2026-11-09, day cycle and repairs

Status: implemented and deployed to development; not committed. See [validation](../operations/owner-feedback-2026-11-09-batch-a-validation.md).
Date: 2026-11-09
Owners: product owner and engineering reviewer
Related requirement IDs: LED-01, INV-01. Amends [ADR 0012](0012-repair-custody-and-fees.md) (an outstanding repair fee may be collected later, on the open day, by the owner) and [ADR 0006](0006-owner-confirmed-whatsapp-dispatch.md) (the pending-invoice list is sale-only and limited to the open day). Keeps the WhatsApp send button on a purchase's own operation screen.
Supersedes: none.
Source: [implementation plan](../operations/owner-feedback-2026-11-09-plan-batch-a.md).

## Context

On 2026-11-09 the owner recorded ten voice notes. This record covers the day cycle and repairs. Pending invoices currently list every unsent sale and purchase since the shop opened. After the owner closes the day, the home screen still shows that day's figures because a missing open day falls back to the calendar date, and an employee's home shows the last hundred of their operations of all time. A repair fee left outstanding at handover can never be collected later, and the day summary, home figures, and day report ignore repair revenue. The purchase-payment, item closing grid, and scrap-to-stock complaints in the same notes were already fixed on 2026-11-08 in [ADR 0041](0041-owner-feedback-2026-11-08-voice-notes.md); this batch verifies them and dismisses the keyboard on every multi-line field.

## Decision

A-D1. Daily flows reset and balances carry over. After the owner closes the day, the home screen shows zero for the day's sale, purchase, expense, return, and weight figures, empty «دفتر البيع» / «دفتر الشراء» / «دفتر المرتجعات», an empty «حركة الدفتر», and an empty «الفواتير المعلقة», until a new day is opened. Cash per payment method, gold stock, and scrap balances do not reset. Nothing is deleted.

A-D2. «الدفاتر» is a read-only list of closed days, newest first. Tapping a day opens that day's full ledger: its figures, books, and operations. A closed day cannot be reopened or edited from there. Edit and delete stay limited to the open day.

A-D3. «الفواتير المعلقة» lists sale operations of the open day that have not been confirmed as sent. Purchases never appear. When no day is open, the list is empty. Unsent sales of a closed day are not carried forward; they can still be sent from their operation screen inside «الدفاتر». The WhatsApp send button on a purchase's own operation screen stays.

A-D4. An employee's home also resets. It shows only the employee's own operations of the open day.

A-D5. Repair money posts to cash only when it is collected: at handover, or through «تحصيل المتبقي». Changing status to «جاهز للتسليم» posts nothing. Collected repair money is visible in the ledger feed («أجرة إصلاح»), in the home figure «إيراد الصيانة», and in the day summary and day report.

A-D6. Collecting an outstanding repair fee later is allowed for a repair in «تم التسليم» or «مؤرشف» with outstanding greater than zero, on the open day only, by the owner only. The amount is 1 piastre up to the outstanding amount. Tenders must sum to the amount. Several later collections are allowed until outstanding is zero.

A-D7. Every multi-line text field closes the keyboard on tap outside. Fields that do not need line breaks also close it with the keyboard's Done key. Every scrolling form that holds one of those fields closes the keyboard on drag.

A-D8. The trader custody flow in «الجرد الفوري» is a different business case and is not changed.

## Data and compatibility impact

Money stays integer piastres and gold stays integer milligrams. New migrations only, after `20261108160200`. Public RPCs that change are renamed to `…_before_<topic>`, revoked, and wrapped.

- `get_pending_invoice_sends` returns sales of the open day only.
- `get_daily_ledger_home_v1` is wrapped as `get_daily_ledger_home_v1_before_day_reset`. With no open day, daily flows are zeroed and balances are kept, plus `day_reset: true` and `last_closed_business_date`. An employee's feed is limited to the open day. With an open day, flows are limited to that open day's operations. `get_ledger_date_v1` reads every session of the calendar date, so a new day opened on the same date would otherwise show the closed session. Opening a day posts `open_day`, so the new day's feed contains that row.
- `private.ledger_zero_flows` zeroes numbers, numeric strings, and arrays inside a JSON value. It is closed to clients.
- Table `public.repair_fee_collections` records each later collection. Clients have no policies. The first fee operation stays on `repairs.financial_operation_id`.
- Operation kind `repair_fee_collection`, with audit and outbox action `repair_fee_collection_confirmed`, and repair event and command kind `repair_collect`. `private.compensation_extend_in_check` refuses an IN-list shorter than eight values, so the two short repair checks were altered directly with the same drop-and-add the helper would emit.
- `post_repair_collect_v1` posts the collection and reduces the outstanding fee. The public payload has no `kind`. `private.repair_claim` requires one, so the RPC adds `kind: repair_collect` only on the payload it passes to the claim, the finish, and the cash posting. `private.repair_guard` allows the balance update only while the transaction-local flag `eldaftar.repair_collect` is on. `repairs_state_check` now allows `collected_piastres > 0` with a null `financial_operation_id` on a delivered repair, and on one archived from delivered, so an unpaid handover can be collected later. The handover itself still requires the pairing when money is collected at delivery.
- The payment-method rewrite of 2026-10-27 dropped the empty-tender branch of `private.repair_tenders`. Unpaid handover still sends an empty list, so the zero-amount branch is restored. A positive amount still requires one to four tenders.
- `day_summary` and the day report gain `repair_piastres` and `repair_count`, the cash-method total and count of non-hidden `repair_fee` and `repair_fee_collection` operations on the day's business days. The weekly report function is unchanged: it sums the existing day-report keys and does not list repair keys on its own summary. Embedded day reports carry the new keys. Repair reads return `collections` in time order.
- A local home read showed no balance keys inside `day_summary` or `journal_context`. Summary keys: `sale_count`, `repair_count`, `expense_count`, `sale_piastres`, `gold_by_bucket`, `purchase_count`, `repair_piastres`, `expense_piastres`, `purchase_piastres`. Journal keys: `day_ids`, `note_count`, `server_now`, `return_count`, `business_date`, `next_midnight_at`. `private.ledger_zero_flows` therefore zeroes the day's flows without touching cash, stock, or scrap. Those balances stay on the base object.

## Verification

- `app/test/keyboard_dismiss_test.dart`
- `app/test/pending_invoices_sale_only_test.dart`
- `app/test/ledger_day_reset_test.dart`
- `app/test/ledger_archive_test.dart`
- `app/test/repair_collect_test.dart`
- `supabase/tests/pending_invoices_open_day.sql`
- `supabase/tests/ledger_home_day_reset.sql`
- `supabase/tests/repairs_custody.sql`
- `supabase/tests/repair_fee_collection.sql`

The [validation note](../operations/owner-feedback-2026-11-09-batch-a-validation.md) records the gates, the development deployment, and the hosted checks.

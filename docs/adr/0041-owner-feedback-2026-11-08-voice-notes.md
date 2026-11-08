# ADR 0041: Owner voice notes of 2026-11-08

Status: accepted on 2026-11-08 and partly implemented. Done: M1, M2, and the owner closing grid of M3. The purchase rules, and a fix that lets a new shop confirm opening balances again, are deployed to the development project only ([validation](../operations/owner-feedback-2026-11-08-voice-notes-validation.md)). Not committed.
Date: 2026-11-08
Owners: product owner and engineering reviewer
Related requirement IDs: LED-01, PUR-01, CAT-01, SALE-01. Amends [ADR 0007](0007-purchase-ownership-and-custody.md) (a new purchase is paid in full; a seller payable is no longer offered), [ADR 0021](0021-invoice-appearance-and-presentation-copies.md) (the presentation-copy panel is no longer shown on the operation screen), and [ADR 0040](0040-owner-feedback-2026-11-06-trade-invoice-whatsapp.md) (the server enforces purchase-to-scrap). Keeps the WhatsApp PDF send and owner confirmation from ADR 0040.
Supersedes: none.
Source: [implementation plan](../operations/owner-feedback-2026-11-08-voice-notes-plan.md).

## Context

On 2026-11-08 the owner recorded ten voice notes, read here as eleven items. Scrap transferred into stock must pick a real item name, and the optional note on that screen goes away because the keyboard cannot be dismissed. Daily closing is item-first, with compact piece counts and optional weight. The invoice screen keeps edit, delete, and WhatsApp, and drops the copy panel and the linked return or exchange button. A purchase is paid in full at once, jewelry purchases become scrap, and coins and bars stay their own stock. A standalone customer return reduces cash immediately at the agreed price and puts the piece back into the named stock. Expenses and returns can be edited or deleted on the open day only. Daily notes can be edited or deleted on any day, text only, with the image left in place and the audit trail kept.

## Decision

D1. An empty closing weight stays «لم يُوزن». It is never filled from the book weight. Only the piece count is required.

D2. A return reduces cash immediately from the payment methods the user enters, like a sale in reverse. The amount is the agreed price the user types. It is not a spot value and not the original sale price. The tender sum must equal the total.

D3. Scrap transferred to stock adds the weight, and a piece count defaulting to 1, to the item name and karat the user picks, for example «خاتم» 21. There is no SKU selection.

D4. Purchases are always fully paid at once. No new purchase may open a seller payable, and the server enforces this. Old purchases that already have a payable are not rewritten.

D5. The whole «نسخ الفاتورة» panel is removed from the operation screen. The WhatsApp PDF send button and its owner confirmation stay. «تعديل» and «مسح العملية» stay. `InvoiceCopyPanel` remains in the client with no entry point under `app/lib`; its server RPCs stay.

D6. The return or exchange button is removed from the sale and purchase operation screens. The linked-return and exchange RPCs stay. There is no UI entry.

D7. Returns and expenses use the same edit and delete window as a sale or purchase: the current open day only, no dependent follow-ups, and effects reviewed before confirming.

D8. Notes carry no balances, so the owner may edit or delete them on any day. Edit changes the text only. The image cannot be swapped. Delete hides the note. The audit trail keeps every version. The R2 object is not deleted.

D9. Closing grid columns are karats in the order 18, 21, 22, 14, limited to the karats that have a book bucket that day. Each count cell holds at most 4 digits (`9999`).

## Data and compatibility impact

Money stays integer piastres and gold stays integer milligrams. New migrations only, after `20261102103000`. Public RPCs that change are renamed to `…_before_<topic>`, revoked, and wrapped.

- New operation kind `customer_return`, with audit and outbox action `customer_return_confirmed`. A returned piece is posted into saleable metal and count for its category and karat, and into a named lot with movement kind `return`.
- Reversal kinds `expense_reversal` and `customer_return_reversal`, posted as a mirror of the source journals and lot movements.
- Table `public.daily_note_changes` for note edit and delete. Clients have no direct policies. Deleted notes drop out of lists, the feed, and `note_count`. The latest edit text is what reads return. `r2_media_objects` and attachment rows are not deleted. A signed read of a deleted note's object is refused.
- `post_daily_ledger_trade_v2` (and v1 if `authenticated` can still execute it) rejects a purchase that carries `purchase_obligation_piastres`, whose tenders do not equal the total, or whose items include `worked_jewelry`. Edits of an old purchase enforce payment only, so a historical jewelry line may stay `worked_jewelry`. Edit and the retired exchange post their replacement through v1 internally. Their wrappers set the transaction-local flag `eldaftar.purchase_keep_category` around that call, and v1 skips only the jewelry check while the flag is on. Clients cannot set it, because `set_config` is not an exposed RPC. Historic report and edit SQL suites restore the pre-rule writers inside their own rolled-back transaction. An idempotent replay of a stored command skips the new checks. `settle_purchase_cash_payable` stays for legacy payables.
- `get_my_closing_task_v1` adds `item_names` for the task's stock buckets only. Counts, weights, and cash are not returned.

## Verification

- `app/test/scrap_to_stock_test.dart`
- `app/test/operation_details_test.dart`
- `app/test/financial_operation_dispatch_test.dart`
- `app/test/purchase_full_payment_test.dart`
- `app/test/confirmed_operation_pdf_test.dart`
- `app/test/purchase_to_scrap_test.dart`
- `app/test/closing_item_grid_test.dart`
- `app/test/daily_close_grid_test.dart`
- `app/test/closing_delegation_test.dart`
- `app/test/meeting_owner_staff_close_test.dart`
- `app/test/customer_return_test.dart`
- `app/test/ledger_trade_change_test.dart`
- `app/test/daily_notes_widget_test.dart`
- `supabase/tests/purchase_paid_and_scrap_routing.sql`
- `supabase/tests/staff_closing_delegation.sql`
- `supabase/tests/customer_return.sql`
- `supabase/tests/expense_return_change.sql`
- `supabase/tests/daily_note_changes.sql`

[Validation](../operations/owner-feedback-2026-11-08-voice-notes-validation.md) records the gates, the development deployment, and the legacy purchase-payable count.

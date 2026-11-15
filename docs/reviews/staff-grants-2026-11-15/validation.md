# Staff grant entry points — validation and development deployment — 2026-11-15

- ADR: [0033](../../adr/0033-shop-staff-grants-and-profile.md) (no new decision; this restores its grant model)
- Migration: [`20261115090000_staff_grant_entry_points.sql`](../../../supabase/migrations/20261115090000_staff_grant_entry_points.sql), SHA-256 `74824a4818b5d7fae547c09315561434026f220a01a495c8010a4518d8680a36`
- Regression test: [`staff_grant_entry_points.sql`](../../../supabase/tests/staff_grant_entry_points.sql), registered in `run-rls-tests.mjs`
- Target: development `xchapwvmvoefriqcxtvn` only

## How it was found

An end-to-end story ran on development over the real HTTP API with the same request shapes as the Flutter app and the React dashboard. It covered sign-up through `owner-register`, a temporary platform admin issuing, replaying and revoking codes, owner redemption (wrong, revoked, reused and valid codes), opening balances, sale, purchase, expense, an idempotent retry, an oversell refusal, staff creation through `shop-staff-create`, the day report, day close and the next day. Everything matched the expected figures except staff.

An employee with the `sale` grant got `forbidden` on every sale. `private.opening_require_reader_shop()` admits staff only after the caller declares the needed grant with `private.allow_member_permission`. `public.post_daily_ledger_trade`, the path the app uses for every sale, purchase, expense and scrap sale, never declared one. Only `post_daily_ledger_trade_v2` was wrapped on 2026-10-26, and the app uses v2 only for explicit-lot sales. `shop_staff_grants.sql` checked the text of the v2 wrapper and never ran a staff sale.

A rolled-back probe as a full partner (all six grants) and as an employee, with the declared grant cleared before each call as in a fresh request, found more entry points with the same gap:

| Entry point | Cause | Grant now declared |
| --- | --- | --- |
| `post_daily_ledger_trade` | never wrapped | `sale` (sale, scrap sale), `purchase`, `expense`; other kinds declare nothing |
| `get_inventory_totals_v1` | the 2026-10-26 wrapper was replaced the same day by `create or replace` in `20261026130000` | `inventory` |
| `get_ledger_day_v1` | written after ADR 0033 | `ledger_read`; the body reads through `get_ledger_date_v2`, which already limits employees |
| `get_ledger_operation_page_v2` | written after ADR 0033 | `ledger_read` for partners; employees refused, because the body reads every operation of the day |
| `get_invoice_presentations_v1`, `get_invoice_presentation_v1`, `get_invoice_dispatch_state`, `get_invoice_brand_source_v1`, `get_invoice_message_source_v1`, `get_invoice_appearance_v1`, `get_invoice_message_v1`, `post_invoice_presentation_v2`, `get_invoice_presentation_status_v1`, `get_pending_invoice_sends` | never wrapped (only `confirm_invoice_whatsapp_send` was) | `invoice_send`; an employee only for their own sales, and the pending queue lists only their own |
| `confirm_invoice_whatsapp_send` | wrapped, but an employee could confirm any sale | adds the employee own-sale rule |

`list_shop_payment_methods_v1` and `get_shop_profile_v1` also refuse staff. That is intended: only the owner's settings screens call them.

The declared grant is a transaction-local setting. The first version of the fix left it set after the wrapper returned, so `customers.sql` caught a staff sale followed by an owner-only customer read in the same transaction. The wrappers now restore the previous value (`private.begin_member_permission` / `private.end_member_permission`), and the new test checks this.

## Gates

- `staff_grant_entry_points.sql` on development, rolled back: fails before the migration (`employee_sale_with_grant ERROR forbidden`) and passes with it; passes again against the deployed version.
- Before/after comparison on development, each suite rolled back without and with the migration: 30 suites unchanged and passing (`batch_c_review_fixes`, `customer_auto_capture`, `customer_auto_capture_phone`, `customer_statistics`, `customers`, `customers_edges`, `daily_ledger_trades`, `day_close_keeps_customers_and_inventory`, `debts`, `expense_feed_description`, `expense_return_change`, `financial_day_report`, `financial_week_report`, `inventory_item_grid`, `invoice_appearance`, `invoice_message`, `invoice_price_components`, `jewelry_item_names`, `last_piece_weight_rule`, `ledger_compensation`, `ledger_compensation_edges`, `ledger_home_day_reset`, `legacy_pooled_lot_name`, `legacy_read_shapes`, `milestone_3_inventory`, `pending_invoices_open_day`, `purchase_paid_and_scrap_routing`, `sale_named_item_and_day_read`, `shop_staff_grants`, `trade_change_tender_label`). `daily_notes_pagination_hosted`, `inventory_trader_page_summaries` (pgTAP) and `ledger_trade_cache_revision` (psql syntax) fail the same way with and without it, because they don't fit a single-query run.
- After deployment, over the real API as the test employee: sale confirmed, retry replayed with the same operation, owner cash +10,000.00, the audit trail names the employee, and expense, purchase, stock totals, invoice reads and customers without the grant are refused.
- No Flutter or React code changed, so the app and dashboard gates were not needed. `git diff --check` clean.

## Deployment

Applied with `supabase db query --remote -f` and recorded with `supabase migration repair --status applied 20261115090000`. Hosted history was 108 rows ending at `20261113110000` and is now 109 rows ending at `20261115090000`. History since 2026-10-20 matched the repository beforehand. The earlier mismatches are the known renamed versions from previous deployment records.

Preservation ([query](preservation.sql)), before and after: 14 shops, 6 entitlements, 15 memberships (checksum `8bb56f1fd0a7b2cfdbeab227b986f3a3` unchanged), 1 member grant, 17 Auth users, 93 financial operations, 97 lot movements and 1 dispatch confirmation. No reset, no other project, no app publication.

## Test data left on development

- The shop «محل تجربة شاملة E2E» (active for 360 days) with its owner and one employee («موظف تجربة», sale grant only). It holds opening balances, sales, a purchase, an expense, one closed day and one open day.
- A second test account with a pending shop («حساب مشرف تجربة E2E»). Its temporary platform-admin row was added for the code test and removed afterwards.
- Credentials stay outside the repository.

## Second change: employee ledger reads and staff controls

The first change made staff trades work but left three gaps in the app, all fixed the same day.

**Employee home did not load.** For an employee, `get_daily_ledger_home_v2` returned a five-field stub (no `read_model_version`, `cash`, `business_day` or `day_summary`), and `parseDailyLedger` rejected it with `FormatException: version` (checked with a throwaway test). **Employee day reads were always empty.** Their filter matched `actor_user_id` on feed items, which carry no actor id, and they dropped `day_summary`, which `parseLedgerDate` requires. **Every staff operation was named as the owner's.** The date read set `actor_display_name` from `shops.owner_display_name`, and the operation detail did the same, so an owner saw their employees' sales as their own.

Migration [`20261115100000_employee_ledger_reads.sql`](../../../supabase/migrations/20261115100000_employee_ledger_reads.sql), SHA-256 `d1bbb58ed5948b0822f9f3f15a88c983143e2585044068ecbc87be3fe23b3012`:

- `get_daily_ledger_home_v2` routes employees to `private.employee_ledger_home()`. It returns the same version-3 read model as the owner's, built only from the employee's operations: their feed, their own day totals and gold movement (`private.ledger_actor_day_summary`), the cash method labels with zero amounts (the sale form needs the labels), and empty stock and scrap. Owners and partners are unchanged.
- The employee date read filters rows by each operation's recorded actor and sends the employee's own summary. `get_ledger_day_v1` replaces its shop-wide recomputed summary with the employee's own. The first capture of this fix caught that leak before deployment.
- Feed rows, operation pages and operation detail name each operation's recorder (`private.ledger_actor_name`): the shop's owner name for the owner (kept current by the profile screen), the staff member's display name otherwise.

App ([design note](../../design-system.md)):

- `LedgerControlAccess` (application layer) maps grants to ledger controls: sale, scrap sale and customer return need sale; purchase needs purchase; expense needs expense; pending invoices and invoice sharing need invoice send; «الدفاتر» needs reports. Cash transfer and scrap-to-stock also need shop balances, so employees never get them. Opening balances, opening and closing the day, daily notes, and trade edit/delete stay with the owner.
- The ledger hides the shop-cash tile and its settings option for employees. Staff see an owner-only opening message and closed-day copy without an open-day action. The trade outcome, operation detail, archive and pending-invoice screens take the invoice and edit/delete rules.

Gates for the second change:

- `employee_ledger_reads.sql` (new, registered): fails before (`seller_home_shape`), passes after. Before/after on development for 32 suites: all pass after. `ledger_home_day_reset.sql`, `sale_named_item_and_day_read.sql` and `staff_grant_entry_points.sql` asserted the old employee stub (`employee_ledger` flag, no `day_summary`); they now assert the new contract (own feed and totals, zero cash, no stock or scrap).
- Deployed like the first change. History is 110 rows ending at `20261115100000`. Preservation unchanged apart from the test operations of this run (95 operations, 99 lot movements; membership checksum `8bb56f1fd0a7b2cfdbeab227b986f3a3`).
- Over the real API after deployment: the employee home is version 3 with only their own rows, zero cash, no stock or scrap and their own 10,000.00 sales total. Their date read shows only their rows and summary. The owner's home names «موظف تجربة» on the employee's sale and keeps shop cash. Both live employee responses parse in the app (throwaway test, deleted).
- Flutter: `dart format` clean, `dart analyze --fatal-infos` no issues, full `flutter test` 1,930 passed. New: `employee_ledger_test.dart` (server-shape parse, access matrix, employee dashboard at 320/390/1240 in both themes, owner control case, closed-day copy), a staff case in `invoice_message_dispatch_test.dart`, and `staff_ledger_capture_test.dart` (employee, partner and owner; 320, 390 and 1440; light and dark; 36 captures under `tmp/staff-ledger`, reviewed).

## Still open

- `get_inventory_item_grid_v1` and `list_inventory_lots_v1` correctly refuse staff without the `inventory` grant. The sale review reads the grid only for the advance «آخر قطعة» notice and ignores a failure (`financial_trade_screen.dart`, `_checkLastPieces`), so a sale-only employee can still sell but doesn't see that notice before confirming. The server still applies the last-piece rule (ADR 0047 D1).
- The bottom bar and rail always show «الجرد الفوري», «بيانات العملاء» and «التقارير». A member without the grant gets an Arabic «لا توجد صلاحية…» page with a link back to the ledger. Hiding those destinations is optional polish.
- An employee's feed is the open day's newest 100 shop operations filtered to theirs. In a very busy shop, older own rows of the same day appear when they load older rows.
- Device acceptance with partner and employee accounts on Android, iOS and Windows; synthetic captures are not a device pass.

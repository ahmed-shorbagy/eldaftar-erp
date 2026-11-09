# Owner voice notes (2026-11-09), batch A: day cycle, pending invoices, repairs, re-reported fixes

Status: implemented on development `xchapwvmvoefriqcxtvn` (2026-11-09). Not committed. See [validation](owner-feedback-2026-11-09-batch-a-validation.md).
Scope: the Flutter app (Android, iOS, Windows) and the Supabase backend it calls. The React admin dashboard is out of scope.
Source: 10 owner voice notes received 2026-11-09, translated into FB-001 … FB-010. This batch covers FB-005, FB-006, FB-007, FB-008, FB-009, FB-010 and the keyboard part of FB-010. [Batch B](owner-feedback-2026-11-09-plan-batch-b.md) covers FB-001 to FB-004.
Decision record to write: ADR 0042 (task A0.1).

Follow this plan step by step. Every task names its files, the exact Arabic copy, the widget keys tests use, what "done" means, and the tests to add. If the code contradicts this plan, stop and ask the project lead. Do not improvise around it.

Batch A and batch B touch different files except `shop_workspace.dart` (both add one link in «المزيد») and `docs/decisions.md`. They can run in parallel if the second one to finish rebases those two files.

---

## 0. Rules for every task

1. Read `AGENTS.md` and `docs/design-system.md` first. All UI copy is Arabic and RTL. Use theme tokens (`AppTokens`, `Theme.of(context).colorScheme`, `AppSemanticColors`). No hard-coded colors.
2. Money is integer piastres and gold is integer milligrams. Use `Piastres`, `Milligrams`, `PieceCount` (`app/lib/src/features/daily_ledger/domain/quantities.dart`). Never use `double` for money or grams.
3. Every financial mutation keeps the existing pattern: idempotency key, `PendingFinancialCommands.save` before the RPC, `FinancialCommitted` / `FinancialRejected` / unknown, then `statusGateway.status` to reconcile. Copy it from `scrap_to_stock_screen.dart`. Do not write a new pattern.
4. Server changes are **new** migrations only, under `supabase/migrations/`, timestamped after `20261108160200`. Never edit an old migration. To change a public RPC: `alter function … rename to …_before_<topic>`, revoke it from `public, anon, authenticated`, then create a new wrapper with the same name and signature (example: `20261026120200_shop_staff_grant_enforcement.sql`).
5. Before you wrap or `create or replace` a function, read its **live** definition, not an old migration file. Many functions were patched several times. After applying all migrations to your local database, run `select pg_get_functiondef('public.<name>(<args>)'::regprocedure);` and build on that text.
6. To add a value to an enumerated check (operation kind, audit action, outbox event), use `private.compensation_extend_in_check(...)` (see `20261013092829_debt_records.sql`, lines 13–30).
7. Keep the Flutter Clean Architecture layers: domain (pure Dart) → application (interfaces) → data (HTTP/codec) → presentation.
8. Gates before a task counts as done:
   - `dart format` on changed files, `flutter analyze`, `flutter test` (the files named in the task, then the whole suite once per milestone).
   - SQL: add every new test file to the list in `supabase/run-rls-tests.mjs`, then run `npm run test:rls` from `supabase/` against a local disposable database.
   - Visual check of each changed screen: Arabic RTL, light **and** dark, 375 px phone width and ≥1280 px desktop width.
   - No release builds and no `npm run build` unless the user asks.
9. Deployment: after a milestone's server changes pass locally, deploy only that milestone's new migrations to the development project `xchapwvmvoefriqcxtvn` (standing authorization in AGENTS.md). Reconcile migration history first. Run the hosted checks the task lists and record them in the validation note (A5.2). No production deploy, no resets.
10. Grok may implement but must not commit or push. Codex reviews and commits.

---

## 1. Items that are already implemented (re-reported by the owner)

Four complaints in these voice notes were already fixed on 2026-11-08 ([ADR 0041](../adr/0041-owner-feedback-2026-11-08-voice-notes.md), commits `c38f981` and `361ad2e`, deployed to development). The owner was almost certainly testing an older build.

| Item | Already done by | What this batch does |
|---|---|---|
| FB-008 purchase does not reduce cash; remove «سداد مبلغ مستحق», «المدفوع عند الشراء», «المستحق للبائع الآن» | ADR 0041 D4, migration `20261108114028_purchase_paid_and_scrap_routing.sql`, `purchase_full_payment_test.dart` | A1.1: verify on development and record proof |
| FB-007 daily closing by item type, count required, weight optional | ADR 0041 D1/D9, `closing_item_grid.dart`, `closing_item_grid_view.dart` | A1.2: verify |
| FB-004 compact 4-digit count cells | ADR 0041 D9 (`ClosingCountCell`, 64 px) | A1.2: verify at 375 px |
| FB-010 scrap → stock: real item names, no optional note, 2 g added to «خاتم» and removed from scrap | ADR 0041 D3, `scrap_to_stock_screen.dart` | A1.3: verify. A1.4 fixes the same keyboard bug on every other multi-line field |

**Prerequisite the project lead handles, not the implementer:** the owner needs a build that contains commits `c38f981` and later. Release builds need the user's explicit authorization (AGENTS.md). Do not run one yourself.

---

## 2. Decisions fixed by this plan

Do not reopen these. The three "needs clarification" questions from the feedback summary are answered in A-D2, A-D3 (row FB-010) and A-D1 of ADR 0041.

| # | Question | Decision |
|---|---|---|
| A-D1 | What "everything resets to zero" means (FB-006) | **Daily flows** reset, **balances** carry over. After the owner closes the day, the home screen shows zero for the day's sale, purchase, expense, return and weight figures, empty «دفتر البيع» / «دفتر الشراء» / «دفتر المرتجعات», an empty «حركة الدفتر», and an empty «الفواتير المعلقة», until a new day is opened. Cash per payment method, gold stock and scrap balances do **not** reset; they are real money and gold in the shop. Nothing is deleted. |
| A-D2 | What «الدفاتر» is (clarification 1) | A **read-only** list of closed days, newest first. Tapping a day opens that day's full ledger: its figures, books and operations. A closed day cannot be reopened or edited from there. The existing server rule stays: edit and delete work on the open day only. |
| A-D3 | Pending invoices (FB-005) | «الفواتير المعلقة» lists **sale** operations of the **open day** that have not been confirmed as sent. Purchases never appear. When no day is open, the list is empty. Unsent sales of a closed day are not carried forward; they can still be sent from their operation screen inside «الدفاتر». The WhatsApp send button on a purchase's own operation screen stays (see owner confirmation 1). |
| A-D4 | Employee home after close | An employee's home also resets: it shows only the employee's own operations of the open day. Today it shows the last 100 of all time. |
| A-D5 | When repair money reaches cash (FB-009) | Repair money posts to cash only when it is collected: at handover (already implemented, ADR 0012) or through the new «تحصيل المتبقي» (A4.2). Changing status to «جاهز للتسليم» posts nothing. Collected repair money is visible in the ledger feed («أجرة إصلاح»), in a new home figure «إيراد الصيانة», and in the day summary and day report. |
| A-D6 | Collecting an outstanding repair fee later | Allowed for a repair in «تم التسليم» or «مؤرشف» with outstanding > 0, on the open day only, by the owner only. The amount is 1 piastre up to the outstanding amount. Tenders must sum to the amount. Several later collections are allowed until outstanding is 0. |
| A-D7 | The keyboard trap (FB-010 note) | Every multi-line text field in the app closes the keyboard on tap outside. Fields that do not need line breaks also close it with the keyboard's Done key. Every scrolling form closes the keyboard on drag. |
| A-D8 | Trader credit purchases | The trader custody flow in «الجرد الفوري» (ownership transfer with «المدفوع الآن» and a payable to a trader) is a different business case (buying from a trader on credit). It is **not** changed. |

### Owner confirmations (do not block work; the default above is implemented)
1. Should the WhatsApp invoice button also disappear from a purchase's operation screen? Default: it stays.
2. Should «الفواتير المعلقة» keep a closed day's unsent sales? Default: no, per the voice note.

---

## 3. What the code does today (root causes)

| Item | Where | Today |
|---|---|---|
| FB-005 | `supabase/migrations/20261019230000_ledger_trade_edit_delete.sql:1426` `public.get_pending_invoice_sends` | `operation.kind in ('sale', 'purchase')` and **no** business-day filter. Every unsent sale and purchase since the shop opened is listed. |
| FB-005 | `app/lib/src/features/daily_ledger/presentation/pending_invoice_sends_screen.dart` | Labels rows «بيع» or «شراء». |
| FB-006 home | `public.get_daily_ledger_home_v1` (`20261021101500_ledger_home_open_day.sql`, wrapped by `20261026120200_shop_staff_grant_enforcement.sql:287`) | With an open day, it reads that day. With **no** open day (right after close), `v_open_date` is null, and `get_ledger_date_v1(null, …)` falls back to the **calendar date**, so the closed day's operations and totals stay on the home screen. The employee branch shows the last 100 own operations of all time. |
| FB-006 archive | `app/lib/src/features/daily_ledger/presentation/ledger_date_screen.dart` | A full "ledger for one date" screen exists, but nothing opens it since commit `84832f8`. `list_financial_report_days_v1` already lists every business day with its status. |
| FB-009 | `20261012153000_repairs_custody_and_fees.sql`, `private.repair_post_fee` | Handover with collection **does** post a `repair_fee` operation to cash, and the feed shows «أجرة إصلاح». Gaps: (a) a fee left outstanding at handover can never be collected later (the repair row is frozen after delivery and holds one `financial_operation_id`); (b) day summary, home figures and the day report ignore `repair_fee`. |
| FB-010 keyboard | 13 multi-line `TextField`s, listed in A1.4 | No `onTapOutside`, no Done action. On a phone the keyboard cannot be dismissed. |

---

## 4. Milestones and order

| Milestone | Items | Layers | Risk |
|---|---|---|---|
| A0 | ADR 0042 | docs | low |
| A1 | Verify FB-004/007/008/010; keyboard sweep | Flutter, hosted checks | low |
| A2 | FB-005 pending invoices | SQL + Flutter | low |
| A3 | FB-006 day reset and «الدفاتر» | SQL + Flutter | medium |
| A4 | FB-009 repairs in the ledger | SQL + Flutter | high (money) |
| A5 | Gates, validation note, owner checklist | docs + hosted checks | low |

A2 and A3 both change home or ledger reads. Do A2 first, then A3. A4 is independent of A2 and A3.

---

## A0 — Bookkeeping

### A0.1 Write ADR 0042
- File: `docs/adr/0042-owner-feedback-2026-11-09-day-cycle-and-repairs.md`. Copy the structure of `docs/adr/0041-owner-feedback-2026-11-08-voice-notes.md`.
- Context: one paragraph on FB-005, FB-006, FB-009 and the re-reported items.
- Decision: section 2 of this plan (A-D1 … A-D8).
- Data impact: `get_pending_invoice_sends` sale-only and open-day-only; home wrapper `…_before_day_reset`; `repair_fee_collections` table and `post_repair_collect_v1`; `repair_piastres`/`repair_count` in the day summary and day report.
- Amends: ADR 0012 (later collection of an outstanding fee is now allowed), ADR 0006 (pending list is sale-only, open day only).
- Add one line to `docs/decisions.md`, in the same style as the 0041 line.
- Done when: `git diff --check` is clean and every link resolves.

---

## A1 — Re-reported items and the keyboard sweep

### A1.1 (FB-008) Verify that a purchase reduces cash
No code change unless a check fails.
1. Run `flutter test test/purchase_full_payment_test.dart test/operation_details_test.dart test/confirmed_operation_pdf_test.dart` and `npm run test:rls` (which includes `purchase_paid_and_scrap_routing.sql`). All must pass.
2. Run `grep -rn "سداد مبلغ مستحق\|المستحق للبائع\|المدفوع عند الشراء" app/lib`. The only allowed match is inside `partial_return_screen.dart` (no entry point). `confirmed_operation_pdf.dart` and `message_template.dart` may still read the `purchase_obligation_piastres` key of **old** purchases; leave that.
3. Hosted read-only check on `xchapwvmvoefriqcxtvn`. Record the output in the validation note:
   ```sql
   -- Every purchase posted since the rule shipped must move cash by exactly -total.
   select o.id, d.payload ->> 'total_piastres' as total,
     coalesce(sum(p.amount) filter (where a.account_kind = 'cash_method'), 0) as cash_delta
   from public.financial_operations o
   join public.financial_operation_details d on d.shop_id = o.shop_id and d.operation_id = o.id
   left join public.journal_postings p on p.shop_id = o.shop_id and p.operation_id = o.id
   left join public.ledger_accounts a on a.shop_id = p.shop_id and a.id = p.account_id
   where o.kind = 'purchase' and o.created_at > '2026-11-08 12:00+02'
   group by o.id, d.payload;
   ```
   Pass: for every row, `cash_delta = -total`. This is the same join `get_financial_day_report_v1` uses for cash.
4. Done when: all three pass. If any fails, stop and report to the project lead with the output. Do not patch around it.

### A1.2 (FB-007, FB-004) Verify the closing grid
1. Run `flutter test test/closing_item_grid_test.dart test/daily_close_grid_test.dart test/closing_delegation_test.dart test/meeting_owner_staff_close_test.dart`.
2. Visual check of «تقفيل اليومية» and the staff count form at 375 px with all four karats (18, 21, 22, 14) in the book: four count cells and the item name fit with no horizontal scroll. Light and dark.
3. Done when both pass. Record a screenshot description in the validation note.

### A1.3 (FB-010) Verify scrap → stock
1. Run `flutter test test/scrap_to_stock_test.dart`.
2. On the development project, transfer «خاتم» 21, 2.000 g. Check: scrap 21 −2.000 g, worked jewelry 21 +2.000 g and +1 piece, a lot named «خاتم», cash unchanged. No «ملاحظة اختيارية» field on the screen. No «مشغولات» text on the screen.
3. Clarification 2 from the summary is already settled by ADR 0041 D3: scrap is kept per karat. The user picks the scrap karat, and the new stock is the same karat.

### A1.4 (A-D7) Keyboard dismissal on every multi-line field
1. New file `app/lib/src/theme/keyboard_dismiss.dart`:
   ```dart
   import 'package:flutter/widgets.dart';

   /// Closes the on-screen keyboard. Used by multi-line fields and forms.
   void dismissKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

   /// For TextField.onTapOutside.
   void dismissKeyboardOnTapOutside(PointerDownEvent _) => dismissKeyboard();
   ```
2. Apply it to each field below. **Group 1, single-paragraph notes:** add `textInputAction: TextInputAction.done`, `onSubmitted: (_) => dismissKeyboard()`, and `onTapOutside: dismissKeyboardOnTapOutside`. **Group 2, text that needs line breaks:** keep the existing input action and add only `onTapOutside: dismissKeyboardOnTapOutside`.

   | File (line at plan time) | Field | Group |
   |---|---|---|
   | `daily_ledger/presentation/cash_transfer_screen.dart:278` | `transfer-note` | 1 |
   | `daily_ledger/presentation/financial_trade_screen.dart:1110, 1138, 1216, 1234` | each `maxLines: 3` field | 1 (skip any that already has `onTapOutside`) |
   | `daily_ledger/presentation/ledger_correction_screen.dart:454` | reason | 1 |
   | `daily_ledger/presentation/linked_return_screen.dart:251` | «سبب أو ملاحظة اختيارية» | 1 |
   | `daily_ledger/presentation/partial_return_screen.dart:762` | note | 1 |
   | `repairs/presentation/repair_screen.dart:911, 1244` | description / reason | 1 |
   | `customers/presentation/customer_screen.dart:1609` | note body | 1 |
   | `daily_notes/presentation/daily_notes_screen.dart:1071, 1344` | note text, edit text | 2 |
   | `invoice_message/presentation/message_settings_screen.dart:441` | template body | 2 |
   | `support/presentation/support_screen.dart:386` | message | 2 |
   Line numbers drift. Find each field with `grep -n "maxLines: [3-9]"` in the file. `customer_screen.dart:1041` is a `Text`, not a field; leave it.
3. On the `ListView` (or `SingleChildScrollView`) that holds each of those forms, set `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` if it is not already set.
4. Tests: new `app/test/keyboard_dismiss_test.dart`. For `CashTransferScreen` and `RepairScreen` intake: focus the note field, tap the screen title, and expect `FocusManager.instance.primaryFocus` to be no longer the field and `tester.testTextInput.isVisible` to be false. For one group-1 field, `tester.testTextInput.receiveAction(TextInputAction.done)` closes it.
- Done when: the test passes and, on an Android emulator, each listed field can be left by tapping outside.

---

## A2 — Pending invoices: sales of the open day only (FB-005)

### A2.1 Server
New migration `supabase/migrations/20261109100000_pending_invoices_open_day_sales.sql`.
1. Read the live `public.get_pending_invoice_sends(bigint)` (rule 5). Write `create or replace function public.get_pending_invoice_sends(p_before_sequence bigint default null)` with the same body and two changes in the `where` of the `page` CTE:
   - `and operation.kind in ('sale', 'purchase')` → `and operation.kind = 'sale'`
   - add `and operation.business_day_id in (select day.id from public.business_days as day where day.shop_id = v_shop and day.status = 'open')`
2. Keep `revoke … from public, anon` and `grant execute … to authenticated` exactly as before. End with `notify pgrst, 'reload schema';`.
3. SQL test, new file `supabase/tests/pending_invoices_open_day.sql`:
   (a) an unsent sale on the open day is listed; (b) an unsent purchase on the open day is **not** listed; (c) a sale confirmed as sent is not listed; (d) after `close_daily_ledger_day_v2`, the list is empty; (e) after opening a new day, the old day's unsent sale is still not listed and a new sale is; (f) a hidden (edited or deleted) sale is not listed; (g) another shop's sale is never listed.

### A2.2 Client
File `app/lib/src/features/daily_ledger/presentation/pending_invoice_sends_screen.dart`.
1. In `_open`, `labelAr` becomes the constant `'بيع'`.
2. Empty state text: **«لا توجد فواتير بيع معلقة في اليوم المفتوح.»** Replace whatever the current empty text is.
3. Add one line under the app bar title: **«فواتير البيع غير المرسلة في اليوم المفتوح فقط.»** (`bodySmall`, `onSurfaceVariant`).
4. If the codec still decodes `kind`, ignore any row whose `kind != 'sale'` (protects against an old server).
- Tests: extend the existing pending-invoice test (find it with `grep -rln PendingInvoiceSendsScreen app/test`), or create `app/test/pending_invoices_sale_only_test.dart`: a fake page with one sale and one purchase shows only the sale; the empty page shows the new empty text.

---

## A3 — Day close resets the home; «الدفاتر» archive (FB-006)

### A3.1 Server: home shows zero flows when no day is open
New migration `supabase/migrations/20261109100100_ledger_home_day_reset.sql`.
1. Helper:
   ```sql
   create function private.ledger_zero_flows(p_value jsonb) returns jsonb
   language sql immutable set search_path = '' as $fn$
     select case pg_catalog.jsonb_typeof(p_value)
       when 'object' then coalesce((
         select pg_catalog.jsonb_object_agg(entry.key, private.ledger_zero_flows(entry.value))
         from pg_catalog.jsonb_each(p_value) as entry), '{}'::jsonb)
       when 'array' then '[]'::jsonb
       when 'number' then '0'::jsonb
       when 'string' then case when p_value #>> '{}' ~ '^-?[0-9]+$' then '"0"'::jsonb else p_value end
       else p_value
     end;
   $fn$;
   revoke all on function private.ledger_zero_flows(jsonb) from public, anon, authenticated;
   ```
2. `alter function public.get_daily_ledger_home_v1() rename to get_daily_ledger_home_v1_before_day_reset;` then revoke it from `public, anon, authenticated`.
3. New `public.get_daily_ledger_home_v1()`, `language plpgsql volatile security definer set search_path = ''` (it must stay **volatile**; see `20261102103000_ledger_home_read_write.sql`):
   ```text
   v_result := public.get_daily_ledger_home_v1_before_day_reset();
   if v_result ->> 'state' is distinct from 'confirmed' then return v_result; end if;
   v_shop := private.opening_require_reader_shop();
   select array_agg(day.id) into v_open_days from public.business_days day
     where day.shop_id = v_shop and day.status = 'open';
   select day.business_date into v_last_closed from public.business_days day
     where day.shop_id = v_shop and day.status = 'closed'
     order by day.opened_at desc, day.id desc limit 1;

   if coalesce(v_result ->> 'employee_ledger', 'false') = 'true' then
     -- A-D4: keep only the employee's operations of the open day.
     v_result := jsonb_set(v_result, '{feed}', coalesce((
       select jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
       from jsonb_array_elements(v_result -> 'feed') item
       join public.financial_operations o
         on o.shop_id = v_shop and o.id = (item ->> 'operation_id')::uuid
       where o.business_day_id = any (coalesce(v_open_days, '{}'))), '[]'));
     return v_result || jsonb_build_object('day_reset', v_open_days is null,
       'last_closed_business_date', v_last_closed);
   end if;

   if v_open_days is not null then
     return v_result || jsonb_build_object('day_reset', false,
       'last_closed_business_date', v_last_closed);
   end if;

   -- A-D1: no open day. Zero the day's flows; keep balances.
   return v_result || jsonb_build_object(
     'feed', '[]'::jsonb,
     'feed_page', (v_result -> 'feed_page') || jsonb_build_object(
       'has_more', false, 'next_before_sequence', null),
     'day_summary', private.ledger_zero_flows(v_result -> 'day_summary'),
     'journal_context', private.ledger_zero_flows(v_result -> 'journal_context')
        || jsonb_build_object('business_date', v_last_closed, 'day_ids', '[]'::jsonb),
     'day_reset', true,
     'last_closed_business_date', v_last_closed);
   ```
   Write it as real PL/pgSQL with declared variables. Use `pg_catalog.`-qualified calls as the rest of the file does.
4. Before you finish, print the real `journal_context` and `day_summary` objects from a local home read. Check every key: a key that is a **balance** (cash per method, stock) must not be inside `day_summary` or `journal_context`. If one is, keep it unzeroed with `|| jsonb_build_object('<key>', v_result #> '{journal_context,<key>}')` and list it in ADR 0042. Balances come from the base object (`get_daily_ledger_v2`) and are not touched.
5. Grants: `revoke all … from public, anon; grant execute … to authenticated;` and a `comment on function` that says: «Open day: unchanged. No open day: zero daily flows, keep balances (ADR 0042).»
6. SQL test, new file `supabase/tests/ledger_home_day_reset.sql`:
   (a) open day with one sale of EGP 5,000: `day_summary.sale_piastres = '500000'`, feed has 1 row, `day_reset = false`;
   (b) after close: `day_reset = true`, feed `[]`, `day_summary.sale_piastres = '0'`, `sale_count = 0`, `last_closed_business_date` = the closed date;
   (c) after close, the base balances are the same as just before close (compare the cash-by-method object before and after);
   (d) after opening a new day: `day_reset = false`, feed `[]` until a new operation is posted;
   (e) employee: before close sees only their own open-day rows; after close sees `[]`; never sees `day_summary` balances (unchanged rule);
   (f) `get_ledger_date_v1(<closed date>)` still returns the closed day's sale (nothing was deleted).

### A3.2 Client: read the reset flag
1. `app/lib/src/features/daily_ledger/application/daily_ledger_view.dart`: add `final bool dayReset;` (default `false`) and `final String? lastClosedBusinessDate;` to the confirmed view.
2. `data/daily_ledger_codec.dart`: decode `day_reset` (bool, missing = `false`) and `last_closed_business_date` (string `YYYY-MM-DD` or null).
3. `presentation/confirmed_ledger_dashboard.dart`: when `view.dayReset` is true, show a card at the top of the books area (key `ledger-day-reset`):
   - Title: **«تم تقفيل اليوم»**
   - Body: **«الدفاتر فارغة حتى تفتح يومًا جديدًا. الأرصدة النقدية والمخزون كما هي.»**
   - Buttons: **«فتح يوم جديد»** (reuse the existing `onOpenDay` callback; key `ledger-day-reset-open`) and **«عرض يوم {date} في الدفاتر»** (key `ledger-day-reset-archive`; `{date}` = `lastClosedBusinessDate` formatted like the existing ledger date header). The second button calls a new `onOpenArchive(String date)` callback.
   - Use `Card` with `colorScheme.secondaryContainer`. No new colors.
4. The journals, metrics and activity list already render from the (now empty or zero) data. Do not add client-side zeroing.
- Tests: new `app/test/ledger_day_reset_test.dart`. Codec: `day_reset: true` parses; missing key parses as false. Widget: a `dayReset` view shows the card, zero sale figure, «دفتر البيع» empty state, and both buttons; a normal view does not show the card.

### A3.3 Client: the «الدفاتر» screen
New file `app/lib/src/features/daily_ledger/presentation/ledger_archive_screen.dart`.
1. Constructor:
   ```dart
   const LedgerArchiveScreen({
     super.key,
     required this.reportGateway,   // ReportGateway from features/reports/application/report_gateway.dart
     required this.dateGateway,     // LedgerDateGateway
     required this.financialGateway,// FinancialGateway, to open an operation
     required this.userId,
     required this.shopId,
     required this.canRead,         // bool Function()
     this.syncTicks,
     this.initialDate,              // 'YYYY-MM-DD'; when set, open that day directly after load
   });
   ```
2. Load: `reportGateway.reportDays(userId, shopId)`. Keep `status == 'closed'` only. Remove duplicate dates (several business days can share one date; keep the first). Newest first.
3. Layout (`AppBar` title **«الدفاتر»**, body inside the usual `AppTokens.contentMaxWidth` constraint):
   - Month header rows, e.g. **«نوفمبر 2026»** (Arabic month names; reuse the date formatting helper the ledger header uses; search `ledger_app_bar.dart` for it).
   - One `ListTile` per date (key `ledger-archive-{date}`): title = weekday and date, e.g. «الأحد 8 نوفمبر 2026»; subtitle **«مقفول · فُتح {HH:mm}»** from `openedAtShop`; trailing `Icons.chevron_left`.
   - Loading: `LinearProgressIndicator`. Error: **«تعذر تحميل الدفاتر. أعد المحاولة.»** with a «إعادة المحاولة» button. Empty: **«لا توجد أيام مقفولة بعد.»**
4. Tap a date → push `LedgerDateScreen` with the new `initialDate` (A3.4), `gateway: dateGateway`, and:
   - `onOperation`: push `FinancialOperationScreen(gateway: financialGateway, userId, shopId, canRead, canWrite: () => false, line: line, syncTicks)`. Archived days are read-only. Copy the other arguments from `_openOperation` in `daily_ledger_screen.dart`.
   - `loadItems`: `financialGateway.operation(callerUserId: userId, operationId: id)` → `ledgerLineItemsFromPayload(payload['payload'])`. Copy `_loadOperationItems` from `daily_ledger_screen.dart` without its cache.
5. `syncTicks` reloads the list.

### A3.4 `LedgerDateScreen` opens a given date
File `ledger_date_screen.dart`.
1. Add `final String? initialDate;` to the constructor. In `initState`, set `_selectedDate = widget.initialDate;` before `_load()`.
2. When `initialDate` is set, the app bar title is **«دفتر {date}»** (same date format as A3.3); otherwise it stays «دفتر حسب التاريخ».
3. Do not add a date picker.

### A3.5 Entry points
1. «المزيد» → «الصفحات» in `app/lib/src/shell/shop_workspace.dart` `_morePages()`: add as the **first** link **«الدفاتر»** (`Icons.menu_book_outlined`, key `workspace-ledger-archive`). Show it when `widget.shop.hasPermission(ShopPermission.reports)` (the list RPC needs the reports grant; owners have every grant). It calls a new `final WidgetBuilder? ledgerArchiveBuilder;` on `ShopWorkspace`, the same way `repairBuilder` is used.
2. `app/lib/src/features/shop_accounts/presentation/shop_accounts_gate.dart`: next to `repairBuilder:` add
   `ledgerArchiveBuilder: opening is! ReportGateway || opening is! LedgerDateGateway || opening is! FinancialGateway || userId == null ? null : (context) => LedgerArchiveScreen(...)`, passing `opening` as all three gateways, `syncTicks: _ticks`, and a `canRead` that copies the `repairBuilder` `canWrite` closure without the entitlement check.
3. The home card button «عرض يوم {date} في الدفاتر» (A3.2) pushes `LedgerArchiveScreen(initialDate: date)` from `daily_ledger_screen.dart`, built with `widget.gateway` the same way.
- Tests: new `app/test/ledger_archive_test.dart`: only closed days are listed, newest first, one row per date; tapping a row opens `LedgerDateScreen` titled «دفتر {date}» and calls `readLedgerDate` with that date; `initialDate` opens the day directly; the «المزيد» link exists for an owner and is hidden for an employee without the reports grant; an operation opened from the archive shows no «تعديل» or «مسح العملية».

---

## A4 — Repairs connected to cash and the ledger (FB-009)

### A4.1 Server: repair revenue in the day figures
New migration `supabase/migrations/20261109100200_repair_revenue_in_ledger.sql`.
1. `get_ledger_date_v1_before_staff` (live definition, rule 5): in the `day_summary` object add
   - `'repair_piastres'`: the sum of cash-method postings of non-hidden `repair_fee` operations on the day's `business_day_id`s, as text. Use the same `journal_postings` / `ledger_accounts.account_kind = 'cash_method'` join that `get_financial_day_report_v1` uses for `cash` (`20261021125258_financial_day_reports.sql`, lines 57–65), plus `repair_fee_collection` operations from A4.2.
   - `'repair_count'`: the count of those operations.
   Use `create or replace` on the `_before_staff` function. The staff wrapper already removes `day_summary` for employees.
2. `get_financial_day_report_v1_before_staff` (live definition): add `repair_piastres` and `repair_count` to the summary in the same way. Do the same in the weekly report function if it builds its own totals (`20261021133552_financial_week_reports.sql`); if it sums the day reports, nothing to do.
3. Feed: confirm the ledger feed already returns `repair_fee` rows (it does not filter by kind). Add `repair_fee_collection` (A4.2) to `private.ledger_operation_label` with label **«تحصيل متبقي صيانة»**.
- SQL test (extend `supabase/tests/repairs_custody.sql`): a handover collecting EGP 200 cash on the open day gives `day_summary.repair_piastres = '20000'`, `repair_count = 1`, and the day report the same; an unpaid handover gives 0; the home after close (A3) shows 0.

### A4.2 Server: collect an outstanding fee later
Same migration.
1. Extend checks with `private.compensation_extend_in_check`: operation kind `repair_fee_collection`; audit action and outbox event `repair_fee_collection_confirmed`; `repair_events.event_type` and `repair_command_requests.command_kind` += `repair_collect`.
2. New table:
   ```sql
   create table public.repair_fee_collections (
     id uuid primary key default pg_catalog.gen_random_uuid(),
     shop_id uuid not null,
     repair_id uuid not null,
     operation_id uuid not null,
     piastres bigint not null check (piastres > 0),
     actor_user_id uuid not null,
     created_at timestamptz not null,
     constraint repair_fee_collections_repair_fkey foreign key (shop_id, repair_id)
       references public.repairs (shop_id, id),
     constraint repair_fee_collections_operation_fkey foreign key (shop_id, operation_id)
       references public.financial_operations (shop_id, id),
     constraint repair_fee_collections_actor_fkey foreign key (shop_id, actor_user_id)
       references public.shop_memberships (shop_id, user_id)
   );
   create index repair_fee_collections_repair_idx on public.repair_fee_collections (shop_id, repair_id, created_at);
   alter table public.repair_fee_collections enable row level security;
   ```
   No client policies. Add an append-only trigger with `private.repair_reject_mutation()` for update and delete.
3. `private.repair_guard()`: `create or replace` from its live definition and add **one** allowed transition: when `old.status in ('delivered', 'archived')` and `pg_catalog.current_setting('eldaftar.repair_collect', true) = 'on'`, allow an update where only `collected_piastres` increases, `outstanding_piastres` decreases by the same amount (never below 0), and `record_version`/`updated_at` change as the other commands change them. Every other column must equal `old`. `financial_operation_id` keeps the first fee operation; later ones live in `repair_fee_collections`.
4. RPC `public.post_repair_collect_v1(p_idempotency_key uuid, p_payload jsonb) returns jsonb`, `security definer`, `search_path = ''`. Copy the structure of `post_repair_handover_v1` (owner check, shop lock, `private.repair_claim` / `private.repair_finish`, open-day and `stale_day` check).
   - Payload (no other keys): `{"version": 1, "repair_id": "<uuid>", "expected_version": "<record_version>", "day_id": "<uuid>", "day_version": "<n>", "amount_piastres": "<n>", "tenders": [{"method": "cash", "piastres": "<n>"}]}`
   - Rules: the repair is `delivered` or `archived`, else `repair_not_delivered`; `0 < amount ≤ outstanding`, else `invalid_input`; 1–4 distinct active methods, tender sum = amount, else `tender_mismatch`; open day only, else `day_closed`.
   - Effects in one transaction: post cash with a new `private.repair_post_collection(...)`. Create it by copying the live `private.repair_post_fee` (it writes the operation, journal, audit, outbox and `financial_command_requests`) and changing only two literals: the operation kind `'repair_fee'` → `'repair_fee_collection'`, and the audit/outbox action `'repair_fee_confirmed'` → `'repair_fee_collection_confirmed'`. Leave `repair_post_fee` unchanged. Then `set_config('eldaftar.repair_collect', 'on', true)`, update the repair (collected += amount, outstanding −= amount, version + 1), `set_config('eldaftar.repair_collect', 'off', true)`, insert into `repair_fee_collections`, write a `repair_events` row `repair_collect`, `private.bump_shop_sync(shop, 'repair')`.
   - Return the same shape `post_repair_handover_v1` returns, plus `collection_operation_id`.
   - Grant execute to `authenticated` only.
5. Repair reads (`get_repair_v1` or whatever returns the detail, found with `grep -n "function public.get_repair" supabase/migrations/*`): add `collections: [{operation_id, piastres, created_at_shop}]` in time order.
- SQL test (new `supabase/tests/repair_fee_collection.sql`): final 20,000 with 8,000 collected at handover, then collect 12,000 (7,000 cash + 5,000 wallet): cash +7,000 and wallet +5,000, outstanding 0, two operations; collecting 1 more → `invalid_input`; collecting on a `received` repair → `repair_not_delivered`; replay → same result; same key with another payload → `payload_mismatch`; a closed day → `day_closed`; partner or employee → `forbidden`; a direct `update public.repairs` from SQL without the flag fails; the outstanding filter no longer lists the repair.

### A4.3 Client: «تحصيل المتبقي»
Files: `app/lib/src/features/repairs/application/` (gateway interface), `repairs/data/` (codec and HTTP; the HTTP implementation lives in `daily_ledger/data/http_opening_gateway.dart` next to the other repair RPCs), `repairs/presentation/repair_screen.dart`, `repairs/presentation/repair_copy.dart`.
1. Gateway: `Future<RepairTransport> collectOutstanding({required String callerUserId, required String idempotencyKey, required Map<String, Object?> payload})` calling `post_repair_collect_v1`. Reuse the handover transport and pending-command types. Add `'repair_collect' => 'post_repair_collect_v1'` to the pending-command replay map.
2. Repair detail, when status is «تم التسليم» or «مؤرشف» and outstanding > 0: a `FilledButton.icon` **«تحصيل المتبقي»** (key `repair-collect`, `Icons.payments_outlined`). Hide it when the day is closed, the shop is read-only, or outstanding is 0.
3. Form (same screen, a new stage like the handover stage):
   - Line **«المتبقي: {amount}»**.
   - **«المبلغ المحصّل»** money field, default = the full outstanding.
   - The tender rows from the handover stage (copy that widget code; do not duplicate the parsing logic, call the same domain function).
   - Review card: **«تزيد النقدية: {amount}»**, one line per method, **«يصبح المتبقي: {rest}»**. Confirm button **«تأكيد التحصيل»**.
   - Success: **«تم تحصيل المبلغ وإضافته إلى النقدية.»** Call `onCollected` so the ledger refreshes (already wired in `shop_accounts_gate.dart`).
4. Error copy (`repair_copy.dart` `repairFailureText`): `repair_not_delivered` → **«التحصيل متاح بعد تسليم القطعة فقط.»**. Validation copy for amount > outstanding: **«المبلغ أكبر من المتبقي.»**
5. Detail history: list each collection as **«تحصيل {amount} · {date}»** under the fee lines.
6. `daily_ledger_codec.dart` kind labels: add `'repair_fee_collection': 'تحصيل متبقي صيانة'`. `financial_operation_screen.dart`: treat `repair_fee_collection` like `repair_fee` (label «النقد المحصّل»).
- Tests (new `app/test/repair_collect_test.dart`): the button shows only for delivered/archived with outstanding > 0; the review shows the cash increase and the new outstanding; the payload matches the contract exactly; amount > outstanding shows the error; an unknown result keeps the key and offers «التحقق وإعادة المحاولة»; `onCollected` fires on success.

### A4.4 Client: «إيراد الصيانة» on the ledger home
1. `application/ledger_home_metrics.dart`: add `'repair'` to `ledgerMetricIds` (not to `ledgerDefaultHomeMetrics`; the owner chooses it in «تخصيص»). Check that `migrateLedgerMetricLayout` keeps a saved `'repair'` id and that an older saved layout without it still loads unchanged; add a unit test for both.
2. `presentation/ledger_metric_specs.dart` `ledgerMetricValues`: `'repair'` → label **«إيراد الصيانة»**, value = money of `daySummary['repair_piastres']`, unit «جنيه», icon `Icons.handyman_outlined`, tone `positive`. Add the label to `ledgerMetricLabel`.
3. Day report screen and PDF (`reports/presentation/reports_screen.dart`, `report_pdf.dart`, `reports/domain/financial_day_report.dart`, `report_codec.dart`): add a row **«إيراد الصيانة»** with `repair_piastres` and `repair_count`. A missing key from an old server reads as 0.
- Tests: metric spec returns the repair figure; the customize sheet lists «إيراد الصيانة»; the day report shows the row; codec defaults to 0.

---

## A5 — Finish

### A5.1 Gates
- `flutter analyze`, full `flutter test`, full `npm run test:rls`.
- React lint, tests and `npx tsc -b` only if a file under `supabase/contracts/` changed.
- Visual review: pending invoices, home after close (card and zero figures), «الدفاتر» list and a day, «تحصيل المتبقي» form and review, «إيراد الصيانة» tile, day report. Arabic RTL, light and dark, 375 px and ≥1280 px, Windows desktop and an Android emulator.

### A5.2 Validation note and deployment record
- New `docs/operations/owner-feedback-2026-11-09-batch-a-validation.md`, in the format of `owner-feedback-2026-11-08-voice-notes-validation.md`: what ran, results, limitations, the A1.1 query output, migrations deployed to `xchapwvmvoefriqcxtvn`, and hosted checks: (a) home read with no open day returns `day_reset: true`; (b) pending list returns sales only; (c) one `post_repair_collect_v1` on a test repair.
- Set ADR 0042 status to "implemented and deployed to development; not committed".

### A5.3 Owner acceptance checklist (send in Arabic)
1. الشراء: بعد تأكيد الشراء تنقص النقدية فورًا بنفس المبلغ ومن نفس وسيلة الدفع. لا توجد «سداد مبلغ مستحق» ولا «المدفوع عند الشراء» ولا «المستحق للبائع الآن».
2. الفواتير المعلقة: فواتير البيع فقط، ولليوم المفتوح فقط.
3. تقفيل اليومية: بعد التقفيل تصبح دفاتر البيع والشراء والمرتجعات والفواتير المعلقة فارغة وأرقام اليوم صفرًا، وتبقى أرصدة النقدية والمخزون كما هي.
4. صفحة «الدفاتر» في «المزيد»: كل يوم مقفول بأرقامه وعملياته، للقراءة فقط.
5. الصيانة: التحصيل عند التسليم يزيد النقدية ويظهر في الدفتر. المتبقي يمكن تحصيله لاحقًا من «تحصيل المتبقي». «إيراد الصيانة» متاح في أرقام الدفتر وفي التقرير اليومي.
6. تقفيل اليومية بالأصناف (خاتم، سلسلة…) مع العدد إجباري والوزن اختياري.
7. التحويل من الكسر للمخزون: اختيار الصنف، بدون خانة ملاحظات، والكيبورد يُغلق باللمس خارج الخانة في كل الشاشات.

---

## Traceability

| Feedback | Tasks |
|---|---|
| FB-004 | A1.2 (closing). Inventory grid: batch B |
| FB-005 | A2.1, A2.2 |
| FB-006 | A3.1–A3.5 |
| FB-007 | A1.2 |
| FB-008 | A1.1 |
| FB-009 | A4.1–A4.4 |
| FB-010 | A1.3, A1.4 |
| Clarification 1 (archive editable?) | A-D2 |
| Clarification 2 (scrap karat) | A1.3 (ADR 0041 D3) |
| Clarification 3 (closing without weight) | ADR 0041 D1: an empty weight stays «لم يُوزن» and is never filled from the book weight. Only counts are matched. The stored observation keeps a null weight for that cell, so the record shows it was not weighed. No new flag is needed |

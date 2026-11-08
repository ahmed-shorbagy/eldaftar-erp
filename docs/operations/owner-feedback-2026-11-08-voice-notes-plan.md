# Owner voice-note feedback (2026-11-08): implementation plan

Status: plan only. Nothing here is implemented yet.
Scope: the Flutter app (Android, iOS, Windows) and the Supabase backend it calls. The React admin dashboard is out of scope.
Source: 10 owner voice notes, translated into 11 items (FB-001 … FB-011).
Decision record to write: [ADR 0041](../adr/) (task T0.1).

This plan is meant to be followed step by step. Every task names its files, the exact Arabic copy, the widget keys tests use, what "done" means, and the tests to add. If something you find in the code contradicts this plan, stop and ask. Do not improvise around it.

---

## 0. Rules that apply to every task

1. Read `AGENTS.md` and `docs/design-system.md` first. All UI copy is Arabic and RTL. Use theme tokens (`AppTokens`, `Theme.of(context).colorScheme`). No hard-coded colors.
2. Money is integer piastres and gold is integer milligrams. Use the existing `Piastres`, `Milligrams`, `PieceCount` types (`app/lib/src/features/daily_ledger/domain/quantities.dart`). Never use `double` for money or grams.
3. Every financial mutation keeps the existing pattern: idempotency key, `PendingFinancialCommands.save` before the RPC, `FinancialCommitted`/`FinancialRejected`/unknown, then `statusGateway.status` to reconcile. Copy the pattern from `scrap_to_stock_screen.dart`. Do not write a new one.
4. Server changes are **new** migrations only, under `supabase/migrations/`, timestamped after `20261102103000`. Never edit an old migration. To change a public RPC, follow the repo's pattern: `alter function … rename to …_before_<topic>`, revoke it, then create a new wrapper with the same name and signature (see `20261026120200_shop_staff_grant_enforcement.sql`).
5. To add a value to an enumerated check (operation kind, audit action, outbox event, lot movement kind), use `private.compensation_extend_in_check(...)` (see `20261013092829_debt_records.sql`, lines 13–30). Do not drop and re-add the constraint by hand.
6. Keep the Flutter Clean Architecture layers: domain (pure Dart) → application (gateways, interfaces) → data (HTTP/codec) → presentation.
7. Gates before a task counts as done (AGENTS.md):
   - `dart format` on changed files, `flutter analyze`, `flutter test` (at least the files listed in the task, then the whole suite once per milestone).
   - For SQL: run the task's SQL test locally with `npm run test:rls` from `supabase/` against a local disposable database (add the new test file to the list in `supabase/run-rls-tests.mjs`).
   - Visual check of each changed screen in Arabic RTL, in light **and** dark themes, at 375 px phone width and ≥1280 px desktop width.
   - Do **not** run release builds or `npm run build` unless the user asks.
8. Deployment: once a milestone's server changes pass locally, deploy only that milestone's new migrations to the development project `xchapwvmvoefriqcxtvn` (standing authorization in AGENTS.md). Reconcile migration history first, then run hosted verification and add a deployment record to the validation note (T7.2). No production deploy, no resets.
9. Grok may implement, but must not commit or push. Codex reviews and commits.

---

## 1. Decisions fixed by this plan (the client's 3 open questions, plus 6 more)

The implementer must not reopen these. D5 and D8 were unclear in the voice notes. On 2026-11-08 the project lead adopted the recommended reading for both (rationale in the table). They are no longer open.

| # | Question | Decision |
|---|---|---|
| D1 | Closing: weight left empty (FB-003) | Empty weight stays "لم يُوزن" (unmeasured). It is **never** auto-filled from book weight. This is the existing rule in `closing_count_observation.dart`. Only the piece count is required. |
| D2 | Return: cash effect and price basis (FB-010) | A return reduces cash **immediately**, from the payment methods the user enters, like a sale in reverse. The amount is the **agreed price the user types**. It is not a spot value and not the original sale price. Tender sum must equal the total. |
| D3 | Scrap → stock: SKU or pool (FB-001) | The transfer adds the weight (and piece count, default 1) to the **item name + karat** the user picks, e.g. «خاتم» 21. The server already creates a named inventory lot from `item_name`. There is no SKU selection. |
| D4 | Purchase: partial payment (FB-007) | Purchases are always fully paid at once. No new purchase may open a seller payable, and the server enforces this. Old purchases that already have a payable are not rewritten (T2.4 checks how many exist). |
| D5 | Which invoice actions remain (FB-005) | Remove the whole «نسخ الفاتورة» panel. **Keep** the WhatsApp PDF send button and its owner confirmation. Keep «تعديل» and «مسح العملية». Rationale: "nothing except edit and delete" referred to the copy section he was listing, and he asked for the WhatsApp button on 2026-11-06 (ADR 0040). |
| D6 | Return/exchange button (FB-006) | Remove it from both the sale and the purchase operation screens. Server RPCs for linked returns and exchange stay for compatibility; there is just no UI entry. |
| D7 | Edit/delete window for returns and expenses (FB-011) | Same rule as sale/purchase: current open day only, no dependent follow-ups, effects reviewed before confirming. |
| D8 | Edit/delete window for notes (FB-011) | Notes carry no balances, so they can be edited or deleted on **any** day by the owner. Rationale: «خلصت من واحدة عاوز أشيلها» means he uses notes as reminders, which are often finished on a later day. Expenses stay open-day only (D7). Edit changes the text only; the image cannot be swapped. Delete hides the note. The audit trail keeps every version. The R2 object is not deleted. |
| D9 | Closing grid columns (FB-004) | Columns are karats in owner order **18, 21, 22, 14**, limited to the karats that have a book bucket that day. Each cell holds up to 4 digits (`9999`). |

---

## 2. What the code does today (root causes)

Read this so you understand *why* each change is needed.

| Item | Where | Today |
|---|---|---|
| FB-001 | `app/lib/src/features/daily_ledger/presentation/scrap_to_stock_screen.dart` | The category dropdown shows `StockCategory` values: «مشغولات» / «سبائك» / «جنيهات» (`opening_copy.dart:31`). Item name is a free-text `TextField` («اسم الصنف الجديد»). |
| FB-002 | same file, the `TextField(controller: _note, maxLines: 3)` | A multi-line field with no Done action inside a `ListView` with a `bottomNavigationBar`. The keyboard cannot be dismissed. |
| FB-003/004 | `daily_ledger/presentation/daily_close_screen.dart` `_namedStockFields()`, and `closing_delegation/presentation/physical_count_editor.dart` | Grouped by karat bucket («عيار 18») with a name dropdown per row and «إضافة نوع من هذا العيار». The owner wants item-first rows with a compact count per karat. The staff editor uses a **free-text** name, because the staff task carries no item names. |
| FB-005 | `invoice_appearance/presentation/invoice_copy_panel.dart`, embedded at `financial_operation_screen.dart` (`InvoiceCopyPanel(...)`) | Shows «نسخ الفاتورة», «معاينة المستند الأصلي الثابت», «حفظ المستند الأصلي الثابت», «عرض/تحديث النسخ الموسومة», «إصدار نسخة موسومة جديدة». |
| FB-006 | `financial_operation_screen.dart`, key `operation-create-return` | Button «تسجيل مرتجع أو استبدال» / «تسجيل مرتجع كامل». |
| FB-007 | `financial_trade_screen.dart` `_paymentFields()` and step 2; `domain/financial_draft.dart` `compose()` | **Root cause of "cash not deducted":** a purchase has a separate «سعر الشراء الكلي» field. Tender amounts may be left empty (helper text: «يمكن ترك المدفوع فارغاً…»). Empty tenders give `cashPaid = 0` and `purchase_obligation_piastres = total`, so cash does not move and a seller payable opens. The operation screen then shows «المدفوع عند الشراء», «المستحق للبائع الآن», and «سداد مبلغ مستحق». |
| FB-008/009 | `financial_trade_screen.dart` `_purchaseToScrap` / `_bookedCategory` (commit `220ac44`, ADR 0040) | **Already implemented in the client:** a purchased `worked_jewelry` line is booked as `scrap` at its karat; coins and bars keep their category. The owner was probably testing an older build. The server does **not** enforce it. |
| FB-010 | Returns today are only *linked* returns (`sale_return`/`purchase_return`) created from the original operation. | There is no standalone "add return" flow. |
| FB-011 | Server `post_ledger_trade_change_v1` / `review_ledger_trade_change_v1` (`20261019230000_ledger_trade_edit_delete.sql`) reject any kind except `sale`/`purchase` (`trade_not_editable`). Daily notes (`kind = 'daily_note'`) have no edit/delete RPC at all. | |

---

## 3. Milestones and order

Do them in this order. Each milestone is shippable and reviewable on its own.

| Milestone | Items | Layers | Risk |
|---|---|---|---|
| M0 | ADR + plan bookkeeping | docs | low |
| M1 | FB-002, FB-005, FB-006, FB-001 | Flutter only | low |
| M2 | FB-007, FB-008/009 enforcement | Flutter + SQL | medium (money) |
| M3 | FB-003, FB-004 | Flutter + small SQL (staff names) | medium |
| M4 | FB-010 standalone return | SQL + Flutter | high (new operation kind) |
| M5 | FB-011 edit/delete for expenses and returns | SQL + Flutter | high |
| M6 | FB-011 edit/delete for notes | SQL + Flutter | medium |
| M7 | Validation note, deploy record, owner acceptance | docs + hosted checks | low |

M5 depends on M4, because returns must exist before they can be edited. M1, M2, M3 and M6 are independent of each other.

---

## M0 — Bookkeeping

### T0.1 Write ADR 0041
- File: `docs/adr/0041-owner-feedback-2026-11-08-voice-notes.md`. Copy the structure of `docs/adr/0040-owner-feedback-2026-11-06-trade-invoice-whatsapp.md`.
- Content: Context (the 11 items in one paragraph); Decision = section 1 of this plan (D1–D9); Data impact = new kind `customer_return`, reversal kinds, `daily_note_changes` table, purchase-paid rule, staff-task item names; Verification = list of test files from this plan.
- Amends: ADR 0007 (partial purchase payable no longer offered), ADR 0021 (presentation-copy panel no longer shown in the operation screen), ADR 0040 (server now enforces purchase-to-scrap).
- Add the ADR to the list in `docs/decisions.md` and/or `docs/adr` index, the same way 0040 was added.
- Done when: `git diff --check` is clean and every link resolves.

---

## M1 — Flutter-only fixes

### T1.1 (FB-002) Remove the optional note from scrap → stock
File: `app/lib/src/features/daily_ledger/presentation/scrap_to_stock_screen.dart`
1. Delete `final _note = TextEditingController();`, its `dispose()`, and the whole `TextField(controller: _note, … label: 'ملاحظة اختيارية')` block together with the `SizedBox(height: 12)` above it.
2. In `_startReview()`, remove the condition `_note.text.trim().length > 1000`.
3. In `_payload()`, keep the key but send an empty string: `'note': '',`. The server requires the key (`20260930063913_daily_ledger_scrap_to_stock.sql`, the `?&` check).
4. Set `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag` on the screen's `ListView`.
5. Same bug class elsewhere: the note `TextField` in `financial_trade_screen.dart` (`key: Key('trade-note')`, `maxLines: 3`) gets `textInputAction: TextInputAction.done`, `onSubmitted: (_) => FocusScope.of(context).unfocus()`, and `onTapOutside: (_) => FocusScope.of(context).unfocus()`. Do not remove that field; the owner only asked to remove the scrap-transfer note.
- Tests (`app/test/scrap_to_stock_test.dart`): (a) `find.text('ملاحظة اختيارية')` finds nothing; (b) the submitted payload has `note == ''`; (c) existing tests still pass after updating any that typed a note.
- Done when: on a phone emulator, tapping any field in the scrap screen and then tapping outside or pressing Done closes the keyboard, with no blank space left.

### T1.2 (FB-005) Remove the invoice-copy panel from the operation screen
File: `app/lib/src/features/daily_ledger/presentation/financial_operation_screen.dart`
1. Delete the whole `if (_active && (_copyKind == 'sale' || _copyKind == 'purchase')) InvoiceCopyPanel(...)` block.
2. Remove the import `../../invoice_appearance/presentation/invoice_copy_panel.dart`, plus `_copyKind` if nothing else uses it.
3. **Do not delete** `invoice_copy_panel.dart` or its server RPCs. Other code or tests may use them. Run `grep -rn InvoiceCopyPanel app/lib`. If the panel is no longer referenced anywhere in `app/lib`, leave the file but note in ADR 0041 that it has no entry point.
4. Keep the WhatsApp block (D5, decided: it stays), but simplify it to:
   - Title «إرسال عبر واتساب».
   - The primary button (key `operation-whatsapp-share`) with label **«إرسال الفاتورة PDF على واتساب»** (ADR 0040 wording; replace «مشاركة مستند PDF عبر واتساب»).
   - The confirmation state line («أكد المالك الإرسال عبر واتساب» / «لم يؤكد الإرسال»).
   - Remove the «تحديث حالة الإرسال» `TextButton` and the «وقت التأكيد» line. The state already reloads on `syncTicks`.
- Tests: update `app/test/operation_details_test.dart` and `financial_operation_dispatch_test.dart`. Assert that none of these texts appear on a sale or a purchase: «نسخ الفاتورة», «معاينة المستند الأصلي الثابت», «حفظ المستند الأصلي الثابت», «عرض النسخ الموسومة», «تحديث النسخ الموسومة», «تحديث حالة الإرسال». Assert that «تعديل», «مسح العملية», and «إرسال الفاتورة PDF على واتساب» are present.

### T1.3 (FB-006) Remove "register return or exchange"
Same file.
1. Delete the whole block that renders `OutlinedButton.icon(key: const Key('operation-create-return'), …)`, including the `returned_by_operation_id` text «سُجل مرتجع كامل لهذه العملية.» and `_returnBusy`'s `LinearProgressIndicator`.
2. Delete `_returnOperation()` and `_returnBusy` if they become unused (the analyzer will tell you). Remove the now-unused imports (`linked_return_screen.dart`, `partial_return_screen.dart`, `exchange_effect_review.dart`) **only if** the analyzer reports them as unused.
3. Do not delete the linked-return screens or the server functions.
- Tests: in `operation_details_test.dart`, assert that `find.byKey(Key('operation-create-return'))` finds nothing for a sale and for a purchase. Delete or rewrite tests that drove the return through this button (`linked_return_test.dart` may drive the screen directly; keep tests that do not depend on the button).

### T1.4 (FB-001) Scrap → stock picks real item names
File: `scrap_to_stock_screen.dart`, plus its call site `daily_ledger_screen.dart:725`.

**Behavior:**
1. Field order: «عيار الكسر» dropdown (unchanged; it already lists only karats with scrap, in `orderedKarats` order) → «المتاح: … جرام» → **«الصنف»** picker → «الوزن بالجرام» + «عدد القطع» → review.
2. The «الصنف» picker replaces **both** the category dropdown and the free-text name. It reuses the trade picker widgets in `trade_item_picker.dart` (`TradeChoiceGrid`, `TradeChoiceTile`, and `showTradeItemPicker` for «أخرى»).
3. Tiles shown for the selected scrap karat:
   - When `StockCategory.workedJewelry.allowsKarat(karat)` (14, 18, 21, 22): «خاتم», «حلق», «سلسلة», «تعليقة» with the same `JewelryGlyph` icons as `financial_trade_screen.dart` `_mainChoices`, then «أخرى».
   - When `StockCategory.coin.allowsKarat(karat)` (21): also «جنيهات» (category `coin`).
   - When `StockCategory.bullion.allowsKarat(karat)` (24): only «سبائك» (category `bullion`).
   - «أخرى» opens `showTradeItemPicker` with the 13 built-in names (move the `_otherJewelry` list from `financial_trade_screen.dart` into a shared top-level `const tradeOtherJewelryNames` in `trade_item_picker.dart` and use it from both places), followed by the shop's own `worked_jewelry` products for that karat, loaded with `InventoryGateway.products(...)`.
4. The word «مشغولات» must not appear anywhere on this screen, including the review card.
5. Selected tile → `_category` = its category code and `_name` = its label. The `_name` `TextEditingController` and its `TextField` are deleted. Keep a `String? _itemName`.
6. Validation message if no item is chosen: **«اختر الصنف.»**
7. Review card text:
   - «ينقص الكسر: {grams} · عيار {karat}»
   - «يزيد مخزون {itemName} عيار {karat}: {grams} · {count} قطعة»
   - «النقدية لا تتغير.»
8. Payload is unchanged in shape: `category` = chosen category code, `item_name` = the chosen label, `note: ''`.
9. Constructor: add `final InventoryGateway? catalog;` (same type as `FinancialTradeScreen.catalog`). At `daily_ledger_screen.dart:725`, pass the gateway the same way it is passed to `FinancialTradeScreen`. If `catalog` is null or the load fails, show only the built-in names plus a `TextButton` «تعذر تحميل أصناف المتجر. إعادة المحاولة».
- Keys for tests: tiles `scrap-stock-item-{label}` (e.g. `scrap-stock-item-خاتم`), «أخرى» tile `scrap-stock-item-other`.
- Tests (`scrap_to_stock_test.dart`): (a) karat 21 shows خاتم/حلق/سلسلة/تعليقة/جنيهات/أخرى and no «مشغولات»; (b) karat 24 shows only «سبائك»; (c) picking «خاتم» at 21 with 2.000 g sends `{category: worked_jewelry, karat: 21, milligrams: '2000', item_name: 'خاتم', note: ''}`; (d) picking a shop product from «أخرى» sends its name; (e) review without an item shows «اختر الصنف.».

---

## M2 — Purchases are always fully paid (FB-007), and purchase routing is enforced (FB-008/009)

### T2.1 Client: purchase payment works exactly like sale payment
File: `app/lib/src/features/daily_ledger/presentation/financial_trade_screen.dart`
1. Delete the `_purchaseTotal` controller, its `dispose()`, both «سعر الشراء الكلي» `TextField`s (key `trade-purchase-price`, one in step 2 and one in `_paymentFields`), and the helper text «يمكن ترك المدفوع فارغاً أو أقل من سعر الشراء. يبقى الفرق مستحقاً للعميل.».
2. In `_totalPounds()`, delete the `if (widget.kind == FinancialKind.purchase && tender.amount.text.trim().isEmpty) continue;` branch.
3. Where the draft is composed (around line 478), use `_totalPounds() ?? ''` for **all** kinds. Delete the `_purchaseTotal` branch. In the tenders list, delete the purchase-only `tender.amount.text.trim().isNotEmpty` filter.
4. Around line 341, replace the use of `_purchaseTotal` with `_totalPounds()`.
5. In `_prefill` (line 256), stop writing `_purchaseTotal.text`. Tenders already prefill from `initial['tenders']`. If a legacy purchase had `purchase_obligation_piastres`, the prefilled tenders sum to less than the total. That is fine: the user must enter the full amount, and the draft rule in T2.2 enforces it.
6. Label: for a purchase, the total line reads **«الإجمالي المدفوع: {amount}»** (key `trade-paid-total`). Replace «المدفوع الآن: …».
7. Review step: for a purchase, the effects card must say **«تنقص النقدية: {amount}»**, followed by one line per tender («{method label}: {amount}»).
- Customer field label for purchases stays «اسم العميل (اختياري)».

### T2.2 Client domain: no purchase payable
File: `app/lib/src/features/daily_ledger/domain/financial_draft.dart`
1. In `compose()`:
   - Change `if ((tenders.isEmpty && kind != FinancialKind.purchase) || tenders.length > 4)` to `if (tenders.isEmpty || tenders.length > 4)`.
   - Change the tender-sum check to `if (tenderSum != parsedTotal.value.value) → tenderMismatch` for **every** kind.
2. Delete `purchasePayable`, `parsedPayable`, and the `'purchase_obligation_piastres'` entry in `toJson()`. Keep `cashPaid` if other code reads it; otherwise delete it.
3. Fix every compile error the analyzer reports from removing `purchasePayable`.
- Tests (create `app/test/purchase_full_payment_test.dart`): (a) purchase with empty tenders → `invalidTender`; (b) purchase where tenders are less than the total → `tenderMismatch`; (c) purchase fully paid by cash + instant transfer → draft JSON has no `purchase_obligation_piastres` key and tender sum == total; (d) widget test: the purchase form has no `trade-purchase-price` field, and after entering items + 1 tender of 50,000 the review shows «تنقص النقدية: 50,000». Use whatever pound format `displayPounds` produces, and assert using `displayPounds` itself rather than a hard-coded string.

### T2.3 Client: remove payable UI and wording
1. `financial_operation_screen.dart`: delete the whole `if (widget.line.kind == 'purchase') ...[` block (the «المدفوع عند الشراء» text, «المستحق للبائع الآن», and the «سداد مبلغ مستحق» button) and `_settlePurchase` plus the `purchase_cash_settlement_screen.dart` import, if they become unused. For a purchase, the top card label stays «سعر الشراء الكلي». The «وسائل الدفع» list below already shows how it was paid.
2. `daily_ledger/application/confirmed_operation_pdf.dart:137`: delete the row `_row('المدفوع عند الشراء', …)`.
3. `invoice_message/domain/message_template.dart:25`: change the label of the `paid` placeholder from «المدفوع عند الشراء» to **«المدفوع»**. Do not change the placeholder key.
4. `grep -rn "المستحق للبائع\|سداد مبلغ مستحق\|المدفوع عند الشراء" app/lib` must return no matches outside `partial_return_screen.dart`, which has no entry point after T1.3.
- Tests: update `confirmed_operation_pdf_test.dart` and `operation_details_test.dart`. Assert those three strings are absent.

### T2.4 Server: reject unpaid purchases and jewelry purchases
New migration: `supabase/migrations/20261108114028_purchase_paid_and_scrap_routing.sql` (implemented and deployed to the development project on 2026-11-08; see the [validation note](owner-feedback-2026-11-08-voice-notes-validation.md))
1. Rename `public.post_daily_ledger_trade_v2(uuid, jsonb)` to `post_daily_ledger_trade_v2_before_paid_purchase` and revoke it from `public, anon, authenticated`. Create a new `public.post_daily_ledger_trade_v2(p_idempotency_key uuid, p_payload jsonb)` that is `security definer`, `set search_path = ''`, and:
   - if `p_payload ->> 'kind' = 'purchase'`:
     - if `p_payload ? 'purchase_obligation_piastres'` → `raise exception 'purchase_must_be_paid'`;
     - if the sum of `tenders[*].piastres` (numeric) `<> (p_payload ->> 'total_piastres')::numeric` → `raise exception 'purchase_must_be_paid'`;
     - if any `items[*].category = 'worked_jewelry'` → `raise exception 'purchase_jewelry_is_scrap'`;
   - then `return public.post_daily_ledger_trade_v2_before_paid_purchase(p_idempotency_key, p_payload);`
   - Important: the idempotent replay of an *old* request must still succeed. Before the new checks, look up `public.financial_command_requests` for `(shop, p_idempotency_key)`. If a row exists, skip the checks and delegate. Get the shop with `private.opening_require_reader_shop()`.
   - Grant execute to `authenticated` only.
2. Do the same check for the edit path. `post_ledger_trade_change_v1` and `review_ledger_trade_change_v1` accept a `p_replacement`. Rename and wrap both (`…_before_paid_purchase`). When `p_action = 'edit'` and the source kind is `purchase`, apply the two `purchase_must_be_paid` checks to `p_replacement`. Do **not** apply the jewelry check to edits: an old purchase line may legitimately stay `worked_jewelry` (ADR 0040).
3. Check whether the old v1 `public.post_daily_ledger_trade(uuid, jsonb)` is still executable by `authenticated`:
   ```sql
   select has_function_privilege('authenticated', 'public.post_daily_ledger_trade(uuid, jsonb)', 'execute');
   ```
   If true, wrap it the same way (rename, then a wrapper with the same checks).
4. Leave `public.settle_purchase_cash_payable` in place. Legacy payables can still be settled by SQL or a later product decision.
5. Hosted read-only check after deploy. Record the count in the validation note; if it is > 0, tell the owner:
   ```sql
   select count(*) from public.financial_operations o
   join public.financial_operation_details d on d.operation_id = o.id
   where o.kind = 'purchase' and d.payload ? 'purchase_obligation_piastres';
   ```
- SQL test (new `supabase/tests/purchase_paid_and_scrap_routing.sql`, added to `run-rls-tests.mjs`): (a) purchase with empty tenders → `purchase_must_be_paid`; (b) partial tenders → `purchase_must_be_paid`; (c) payload with `purchase_obligation_piastres` → `purchase_must_be_paid`; (d) purchase item `worked_jewelry` → `purchase_jewelry_is_scrap`; (e) a fully paid scrap purchase of 21k 10.000 g for EGP 60,000 cash: cash account −6,000,000 piastres, scrap 21 +10,000 mg, in one transaction; (f) a coin purchase increases `coin` stock, not scrap (FB-009); a bullion purchase increases `bullion` (FB-009); (g) replaying the same idempotency key returns `replayed: true`; (h) an edit replacement with partial tenders → `purchase_must_be_paid`; (i) the employee/partner grant rules still apply (no `purchase` grant → `forbidden`).

### T2.5 Client: map the new server errors
File: `financial_trade_screen.dart` `_serverCopy(code)`.
- `purchase_must_be_paid` → **«يجب دفع سعر الشراء كاملًا. تأكد أن مجموع طرق الدفع يساوي الإجمالي.»**
- `purchase_jewelry_is_scrap` → **«المشغولات المشتراة تُسجَّل كسرًا. حدّث التطبيق وأعد المحاولة.»** (Only an outdated client can hit this.)
- Tests: one widget test per code, with a fake gateway returning `FinancialRejected(code)`.

### T2.6 (FB-008/009) Verify the existing purchase-to-scrap behavior
No new code unless a check fails.
1. Run `app/test/purchase_to_scrap_test.dart`. It must pass.
2. Add these cases if they are missing: buying «خاتم» 21 → payload line `category: 'scrap', karat: 21`; buying «سلسلة» 18 → `scrap` 18; buying «جنيهات» → `coin` 21; buying «سبائك» → `bullion` 24; karat chips in the purchase form are ordered 18, 21, 24, 22, 14 (`karatDisplayOrder`).
3. Review copy for a jewelry purchase must say «يزيد كسر عيار {k}: {grams}». It must not say «مخزون خاتم».

---

## M3 — Daily closing by item type with compact counts (FB-003, FB-004)

### T3.1 Domain: build closing rows from item names
New file: `app/lib/src/features/daily_ledger/domain/closing_item_grid.dart` (pure Dart, no Flutter imports).
```dart
/// One row of the closing grid: an item name and its category.
final class ClosingGridRow { const ClosingGridRow(this.name, this.category); final String name; final String category; }

/// Builds the item rows and karat columns for closing.
/// [bookStock] is counts['stock'] (list of {category, karat, count, milligrams}).
/// [shopNames] are (name, category, karat) from InventoryGateway.products.
final class ClosingItemGrid {
  final List<int> jewelryKarats;     // karats with a worked_jewelry bucket, in order 18,21,22,14
  final List<ClosingGridRow> rows;   // see rules below
  ...
}
```
Rules:
1. `jewelryKarats` = karats of `worked_jewelry` buckets in `bookStock`, ordered by `[18, 21, 22, 14]` (D9).
2. Jewelry rows, in this order: «خاتم», «حلق», «سلسلة», «تعليقة» (always, if there is any jewelry bucket), then each distinct shop product name with category `worked_jewelry` and a karat in `jewelryKarats`, in first-seen order and without duplicates.
3. If a `coin` bucket exists, add one row «جنيهات» (category `coin`, single column = its karat). If a `bullion` bucket exists, add one row «سبائك» (category `bullion`, single column = 24).
4. `toObservations(Map<(rowName, karat), (String countText, String gramsText)>)` returns the `stock` list for `closingObservationsMatch`: one `{item_name, category, karat, count, milligrams|null}` per **non-empty** cell. Count is canonical integer text, 1–4 digits. A cell with an empty count is omitted. A cell with weight but no count is an error.
5. The existing match rule stays as it is (the server sums counts per category:karat). Do not change `closing_count_observation.dart`.
- Tests (`app/test/closing_item_grid_test.dart`): ordering 18, 21, 22, 14 when the book has all four; only 18 and 21 when only those exist; built-in names first, shop products after, no duplicates; coin/bullion rows only when the bucket exists; `toObservations` omits empty cells and rejects weight-without-count; 4-digit max (`10000` rejected).

### T3.2 Owner closing screen: item-first grid
File: `daily_ledger/presentation/daily_close_screen.dart`. Replace `_namedStockFields()` and `_observations`.
Layout for the «المخزون» section:
```
               ١٨      ٢١      ٢٢      ١٤        ← header row: «عيار 18» … (label text «18», «21», «22», «14»)
خاتم          [   ]   [   ]   [   ]   [   ]
حلق           [   ]   [   ]   [   ]   [   ]
سلسلة         [   ]   [   ]   [   ]   [   ]
تعليقة         [   ]   [   ]   [   ]   [   ]
<shop products…>
جنيهات        [   ]                             (its own karat only)
سبائك         [   ]
[ + إضافة صنف آخر ]          [ ▢ إدخال الأوزان (اختياري) ]
```
1. Header text above the grid: **«اكتب عدد القطع لكل صنف وعيار. الوزن اختياري.»**
2. Item name column: flexible width, `Text` with `maxLines: 1`, `overflow: TextOverflow.ellipsis`.
3. Count cell: a new widget `ClosingCountCell` in `ledger_form_fields.dart`. It is a `TextField` with fixed width **64 logical px** (wide enough for `9999` at the body font), `textAlign: TextAlign.center`, `textDirection: TextDirection.ltr`, `keyboardType: TextInputType.number`, `inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)]`, `isDense: true`, and `contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4)`. Decoration comes from `ledgerFieldDecoration` with **no label** (the column header is the label). Semantics label: «عدد {name} عيار {karat}».
4. Spacing between cells: `AppTokens.spaceSm`. Wrap the grid in a `SingleChildScrollView(scrollDirection: Axis.horizontal)` only as a fallback. At 375 px, 4 cells × 64 + name column must fit with no horizontal scroll; verify it in the visual check.
5. «إدخال الأوزان (اختياري)»: a `SwitchListTile` (key `close-weights-toggle`), off by default. When on, each row shows a second line of the same 4 cells for grams (`GramInputFormatter(decimalPlaces: 3)`, width 80 px, hint «جم»). Weights stay optional per cell (D1).
6. «إضافة صنف آخر» (key `close-add-item`): opens `showTradeItemPicker` with the 13 built-in names (`tradeOtherJewelryNames` from T1.4) and the shop products. It adds a jewelry row and ignores a name that is already a row.
7. Keyboard: every cell uses `textInputAction: TextInputAction.next`; the last one uses `done`. `ListView` gets `keyboardDismissBehavior: onDrag`.
8. Cash and scrap sections are unchanged, but list scrap karats in `orderedKarats` order.
9. Error copy when the totals do not match is unchanged («يوجد فرق بين العد الفعلي والأرصدة المسجلة…»). New error for a weight without a count: **«اكتب العدد قبل الوزن.»**
10. Remove the legacy non-named branch only if `_namedCounts` is always true in production. Check `ClosingObservationGateway` implementers; if the HTTP gateway implements it, delete the `!_namedCounts` UI branch and its `_stock` map.
- Keys: `close-count-{rowIndex}-{karat}`, `close-weight-{rowIndex}-{karat}`.
- Tests (update the close tests in `financial_trade_screen_test.dart` or move them to a new `app/test/daily_close_grid_test.dart`): (a) with a book of 21k = 3 pieces and 18k = 2, the header shows only 18 and 21, in that order; (b) entering خاتم/21 = 2, سلسلة/21 = 1, حلق/18 = 2 passes review and sends three observation rows; (c) 5 digits cannot be typed; (d) a weight without a count shows «اكتب العدد قبل الوزن.»; (e) no «مشغولات» text on the screen; (f) golden or visual check at 375 px light and dark.

### T3.3 Server: give the closing staff task the item names
New migration: `2026111013xxxx_closing_task_item_names.sql`
1. Find the current definition of `public.get_my_closing_task_v1` (`20261020100258_temporary_staff_closing_tasks.sql`, around line 259). Rename it to `get_my_closing_task_v1_before_item_names` and wrap it. The wrapper adds one key to the returned JSON when the task is assigned:
   `'item_names', coalesce((select jsonb_agg(jsonb_build_object('name', p.name, 'category', p.category_code, 'karat', p.karat) order by p.created_at, p.id) from public.inventory_products p where p.shop_id = <task shop> and (p.category_code, p.karat) in (<stock buckets of the task>)), '[]'::jsonb)`
   Limit it to 200 rows.
2. It returns names only. Never return counts, weights, or cash. Staff must not learn book balances (AGENTS.md).
3. SQL test (extend `supabase/tests/staff_closing_delegation.sql`): an assigned counter sees `item_names` for its task's buckets only; another shop's products are not visible; the response has no `count`/`milligrams` keys for stock; after submission the task (and the names) are gone.

### T3.4 Staff count editor uses the same grid
Files: `closing_delegation/application/closing_delegation_gateway.dart`, `closing_delegation/data/closing_delegation_codec.dart`, `closing_delegation/presentation/physical_count_editor.dart`.
1. Add `final List<(String name, String category, int karat)> itemNames;` to `StaffCountAssignment` (default `const []`). Decode `item_names` in the codec; a missing key means `[]`, for old servers.
2. Rebuild `PhysicalCountEditor` on top of `ClosingItemGrid` (T3.1) and the same row/cell widgets as T3.2. Extract the grid into a shared widget `ClosingItemGridView` in `daily_ledger/presentation/closing_item_grid_view.dart` and use it from both screens. Do not copy and paste it.
3. The staff screen has no cash section (unchanged) and never shows book numbers.
- Tests: update `app/test/closing_delegation_test.dart` and `meeting_owner_staff_close_test.dart`. The staff editor shows خاتم/حلق/سلسلة/تعليقة plus the server names, with compact 4-digit cells, and sends rows with `item_name` set to the row label.

---

## M4 — Standalone return from the returns ledger (FB-010)

### T4.1 Server: `customer_return` operation (contract is fixed)
New migration: `2026111014xxxx_customer_return.sql`. Put the posting logic in `private.post_customer_return_core(p_shop, p_key, p_payload, p_day, p_actor, p_at)` and make the public RPC a thin wrapper (grant check, shop lock, idempotency), so M5 can reuse the core.
- New operation kind: **`customer_return`**. Arabic label: **«مرتجع»**.
- RPC: `public.post_customer_return_v1(p_idempotency_key uuid, p_payload jsonb) returns jsonb`.
- Permission: `private.allow_member_permission('sale')`, the same grant as selling.
- Payload (version 1). No other keys are allowed:
```json
{
  "version": 1,
  "kind": "customer_return",
  "total_piastres": "6000000",
  "tenders": [{"method": "cash", "piastres": "6000000"}],
  "items": [{"category": "worked_jewelry", "karat": 21, "milligrams": "10000",
             "count": "1", "item_name": "خاتم", "line_price_piastres": null}],
  "customer_name": "", "customer_phone": "", "note": ""
}
```
Validation, matching `post_daily_ledger_trade` for a sale:
- 1–50 items. Category ∈ {`worked_jewelry`, `coin`, `bullion`} (never `scrap`); karat allowed for the category (`private.opening_pair_allowed`); milligrams > 0; count > 0.
- Item name: 1–120 characters, trimmed.
- 1–4 tenders, distinct methods, each > 0, active cash methods (`private.assert_active_cash_methods`). Tender sum **must equal** `total_piastres` (D2).
- Line prices: all null, or all set and summing to the total.
- Phone: same regex as sale. Note ≤ 1000 characters. Customer name ≤ 200.
- Errors: `invalid_input`, `day_closed`, `shop_not_active`, `negative_owned_balance` (not enough cash in a method), `payload_mismatch` (same key, different payload).

Effects (one transaction, shop row locked `for update`, open day locked):
- For each tender: cash account of that method **−piastres**, against the same counter-account a sale uses (mirror the sale's cash journal with the sign flipped).
- For each item: `saleable_metal` (category, karat) **+mg** and `saleable_count` (category, karat) **+count**, posted exactly like a purchase line of the same category. Copy the purchase posting code from the latest `public.post_daily_ledger_trade` definition (`20261005091822_complete_owner_feedback.sql` or later; use `grep -ln "function public.post_daily_ledger_trade("` to find the newest).
- Lot sync: in `private.sync_operation_lots` (latest definition; `grep -ln "function private.sync_operation_lots"`), add a branch for `v_kind = 'customer_return'` that calls `private.create_stock_lot(p_shop, p_operation, v_line->>'item_name', category, karat, mg, count, 'owned_available', null, false, null, null, 'return', 'manual')` per item. A returned «خاتم» therefore goes into the «خاتم» stock (FB-010).
- `financial_operations` row with kind `customer_return`, the next `shop_sequence`, the open day, `actor_user_id = auth.uid()`, and `created_at = clock_timestamp()`. `financial_operation_details.payload = p_payload`.
- Audit `financial_audit_events.action = 'customer_return_confirmed'`, outbox `event_type = 'customer_return_confirmed'`, `financial_command_requests` row, `business_days.day_version + 1`, `private.bump_shop_sync(shop, 'customer')`.
- Extend the checks with `private.compensation_extend_in_check`: `financial_operations_kind_check` += `customer_return`; audit action += `customer_return_confirmed`; outbox += `customer_return_confirmed`. The lot movement kind `return` and allocation mode `manual` already exist; verify this in the constraint.

Reads to update in the same migration (rename-and-wrap or `create or replace`, whichever the current definition allows):
1. Ledger feed (`get_daily_ledger_v2`, `get_ledger_operation_page`, `get_daily_ledger_home_v1`, the ledger date read): a `customer_return` row has `is_return: true`, a label of «مرتجع», `total_piastres`, `has_note`, `party_name`/phone like a sale, and items for the card preview (ADR 0039 loads items for return cards).
2. `journalContext.returnCount` / day summary: count `customer_return` as a return.
3. Day/week reports and analytics (`get_financial_day_report_v1_before_staff`, `get_financial_week_report_v1_before_staff`, the functions in `20261027120000_financial_period_analytics.sql`): treat `customer_return` like `sale_return`. It reduces net sales by `total_piastres` and reduces net sold grams per category and karat. `return_count` includes it.
4. Owner audit trail (`20261028120000_owner_audit_trail.sql`): Arabic label for `customer_return_confirmed` = «تسجيل مرتجع».
5. Employee scoping: an employee sees only their own `customer_return` rows (the same filter that the staff wrappers apply to other kinds).
- SQL test (new `supabase/tests/customer_return.sql`): (a) returning خاتم 21k 10.000 g for EGP 60,000 cash: cash −6,000,000, worked_jewelry 21 +10,000 mg and +1 count, one lot named «خاتم»; (b) a returned coin goes to `coin`, a returned bar to `bullion`; (c) `scrap` category → `invalid_input`; (d) tender ≠ total → `invalid_input`; (e) not enough cash → `negative_owned_balance` with no partial writes; (f) replay → `replayed: true`; (g) no `sale` grant → `forbidden`; an employee's feed shows only their own returns; (h) day report net sales go down by the return total; (i) a closed day → `day_closed`.

### T4.2 Client domain and gateway
1. `financial_draft.dart`: add `FinancialKind.customerReturn`. In `compose()`, `customerReturn` behaves like `sale` (tenders required, sum == total) and additionally rejects `scrap` items. `toJson()` emits `kind: 'customer_return'` and **no** `description` and no `pricing` (pricing is not offered for returns). Keep the key set exactly as in the contract above. Because `toJson()` currently always includes `description`, branch for `customerReturn`.
2. `application/financial_gateway.dart`: add an interface
   ```dart
   abstract interface class CustomerReturnGateway {
     Future<FinancialCommandResult> postCustomerReturn({required String callerUserId, required String idempotencyKey, required Map<String, Object?> payload});
   }
   ```
3. `data/http_opening_gateway.dart`: implement it with `_financialCommand(callerUserId, 'post_customer_return_v1', {'p_idempotency_key': key, 'p_payload': payload})`. Add `'customer_return' => 'post_customer_return_v1'` to the pending-command replay map (around line 557).
4. `data/daily_ledger_codec.dart` (around line 642): allow `isReturn` for `customer_return`. Add the label «مرتجع» wherever kinds map to Arabic labels (`grep -rn "'sale_return'" app/lib` lists them).
- Tests: `financial_draft` unit tests for the new kind; codec test that decodes a `customer_return` feed row with `is_return: true`.

### T4.3 Client UI: «إضافة مرتجع»
1. Entry points (both required):
   - In `confirmed_ledger_dashboard.dart`, the `_CompactBookRow` for «دفتر المرتجعات» gets a trailing `FilledButton.tonalIcon` (key `ledger-add-return`, icon `Icons.add`, label **«إضافة مرتجع»**).
   - In the history sheet, when the «دفتر المرتجعات» filter is selected, the same button sits at the top of the list.
   - Show the button only when the gateway implements `CustomerReturnGateway`, the user has the `sale` grant, and the day is open. Hide it otherwise; do not just disable it.
   - Make sure the returns row is visible by default (`_showReturns` default `true`); keep the toggle.
2. Form: reuse `FinancialTradeScreen` with `kind: FinancialKind.customerReturn`.
   - Title **«إضافة مرتجع»**.
   - Item tiles: the same as a sale (خاتم، حلق، سلسلة، تعليقة، جنيهات، سبائك، أخرى). No «كسر». Karat chips in `karatDisplayOrder`.
   - `_purchaseToScrap` must be false for this kind, so items keep their category.
   - Payment section title **«طريقة رد المبلغ»**; total line **«إجمالي المبلغ المرتجع: {amount}»**.
   - Customer name/phone optional (same fields as sale); note optional (with the keyboard fix from T1.1).
   - Hide «تفصيل السعر والمصنعية». Keep «سعر لكل صنف» if the shop has it on.
   - Review card: «تنقص النقدية: {amount}» plus one line per tender, then per item **«يزيد مخزون {name} عيار {karat}: {grams} · {count} قطعة»**. Confirm button **«تأكيد المرتجع»**.
   - Success: pop back with `true`; the ledger refreshes the same way as after a sale.
   - Server error copy: `negative_owned_balance` → **«الرصيد النقدي في وسيلة الدفع لا يكفي لرد المبلغ.»**; `day_closed` → the existing day-closed copy.
3. Operation screen for a `customer_return` line (`financial_operation_screen.dart`): top card label **«المبلغ المرتجع»**, items list, tenders list, notes. No invoice, no WhatsApp.
- Tests (new `app/test/customer_return_test.dart`): the button appears in the returns row and opens «إضافة مرتجع»; no «كسر» tile; a خاتم 21k 2.000 g, EGP 5,000 cash flow sends the exact payload; the review shows the cash decrease and the stock increase; tender ≠ total shows the existing mismatch copy; a pending/unknown result shows «التحقق من الحالة» and reconciles; the button is hidden without the `sale` grant.

---

## M5 — Edit and delete for expenses and returns (FB-011, part 1)

### T5.1 Server: generic mirror reversal
New migration: `2026111015xxxx_expense_and_return_edit_delete.sql`
1. New private function `private.post_mirror_reversal(p_shop uuid, p_key uuid, p_source uuid, p_kind text, p_day uuid, p_actor uuid, p_at timestamptz) returns uuid`:
   - Inserts a `financial_operations` row of kind `p_kind` (`expense_reversal` or `customer_return_reversal`, added via `compensation_extend_in_check`).
   - For every `journal` of the source: inserts a journal with the same `unit_kind`, `karat`, and `bucket_key`, and for every posting, a posting on the same account with **−amount**.
   - For every `inventory_lot_movements` row of the source: `private.add_lot_movement(p_shop, lot_id, new_op, -delta_mg, -delta_count, 'return', 'return_mirror')`.
   - Inserts `financial_command_requests` for `p_key`. Returns the new operation id.
2. Extend `review_ledger_trade_change_v1` and `post_ledger_trade_change_v1` (rename-and-wrap, or `create or replace` of the internal helpers):
   - Allowed kinds become `sale`, `purchase`, `expense`, `customer_return`.
   - For `expense`/`customer_return`, the reversal uses `private.post_mirror_reversal(...)` instead of `private.post_linked_return_core`, and the edit replacement uses `post_daily_ledger_trade` (expense) or the core of `post_customer_return_v1` (return; split the core into `private.post_customer_return_core(...)` in M4 so it can be called here).
   - `private.trade_change_assert_draft` must accept an `expense` draft (description required, no items) and a `customer_return` draft (the M4 contract).
   - `private.trade_change_effects` must compute the effects for these kinds so the review screen can show them: expense = the cash per method comes back on delete; return = cash comes back and stock goes down on delete.
   - `private.trade_change_assert_followups`: a `customer_return` whose lots were already consumed by a later sale cannot be edited or deleted (`trade_has_followups`).
   - `private.trade_change_assert_affordable`: deleting a return must not make stock negative, and editing an expense to a larger amount must not make cash negative.
   - Permission: keep whatever owner/grant check the sale/purchase change uses today. Additionally require `expense` grant for expense changes and `sale` grant for return changes.
   - Open day only (D7); same `stale_trade_review` token logic.
   - `private.ledger_trade_hidden` already hides the source and the reversal through `ledger_trade_changes`. Verify that feeds, reports, and the day summary (`expense_count`, `expense_piastres`, return counts) exclude hidden rows for the two new kinds.
   - Audit: reuse `trade_edited` / `trade_deleted`.
- SQL test (extend `supabase/tests/ledger_trade_change.sql`, or a new `expense_return_change.sql`): delete an expense → cash restored, `expense_count` −1, feed hides it; edit an expense 500 → 700 → cash −200 net, one active row; delete a return → cash −refund reversed and stock back; delete a return whose ring was later sold → `trade_has_followups`; a closed-day expense → `trade_not_editable`/`day_closed`; replaying the change key → replayed; a stale review → `stale_trade_review`; staff without a grant → `forbidden`.

### T5.2 Client: edit/delete buttons for expenses and returns
1. `financial_operation_screen.dart`: the edit/delete block currently requires `kind == 'sale' || kind == 'purchase'`. Extend the condition to `expense` and `customer_return`. Keep the explanatory text and the keys `operation-edit` / `operation-delete`. Linked `sale_return`/`purchase_return` rows stay non-editable.
2. `_changeTrade('edit')` opens `FinancialTradeScreen` with `initialPayload` and the matching kind (`expense` or `customerReturn`), reusing the `onDraftReviewed` → `review_ledger_trade_change_v1` → `LedgerTradeChangeScreen` flow. Make sure `_prefill` handles an expense (description, tenders) and a return (items, tenders, customer).
3. `ledger_trade_change_screen.dart`: add effect copy for the new kinds, e.g. «حذف المصروف يعيد {amount} إلى {method}.» and «حذف المرتجع يعيد {amount} إلى {method} ويُنقص مخزون {name} عيار {karat}: {grams}.»
4. `application/ledger_trade_change.dart` / `data/ledger_trade_change_codec.dart`: accept the new kinds and effects.
5. Map `trade_has_followups` → **«لا يمكن تعديل أو مسح هذه العملية لأن عمليات لاحقة اعتمدت عليها.»**. Reuse the existing copy if there is one.
- Tests (extend `app/test/ledger_trade_change_test.dart`): the edit/delete buttons show for expense and customer_return and are hidden for sale_return; delete expense → review shows the cash effect → confirm → the row is gone after sync; edit expense prefills the description and amount.

---

## M6 — Edit and delete for daily notes (FB-011, part 2)

### T6.1 Server
New migration: `2026111016xxxx_daily_note_edit_delete.sql`
1. Table `public.daily_note_changes`:
   `id uuid pk default gen_random_uuid(), shop_id uuid not null, note_operation_id uuid not null, action text not null check (action in ('edit','delete')), text text, actor_user_id uuid not null, created_at timestamptz not null, command_key uuid not null, unique (shop_id, command_key)`. Add a FK `(shop_id, note_operation_id)` → `financial_operations (shop_id, id)` and a FK on the actor membership (copy from `ledger_trade_changes`). Enable RLS with **no** client policies (clients cannot read or write it directly). Add an index on `(shop_id, note_operation_id, created_at desc)`.
2. RPC `public.post_daily_note_change_v1(p_idempotency_key uuid, p_note_operation_id uuid, p_action text, p_text text) returns jsonb`. It is owner-only (notes are owner-only per AGENTS.md; use the same owner check `post_daily_note` uses), `security definer`, `search_path = ''`, and locks the shop.
   - The source must exist, be kind `daily_note`, belong to the shop, and not already be deleted → otherwise `not_found` / `note_deleted`.
   - `edit`: `p_text` is trimmed, ≤ 1000 characters (or whatever limit `post_daily_note` uses; read it). It may be empty only if the note has an attachment; otherwise `invalid_input`.
   - `delete`: `p_text` must be null.
   - Idempotency: reuse `financial_command_requests` with the canonical payload `{kind:'daily_note_change', note_operation_id, action, text}`, the same replay / `payload_mismatch` behavior.
   - Audit: actions `daily_note_edited` / `daily_note_deleted` (extend the checks); outbox the same; `private.bump_shop_sync(shop, <the sync channel notes use>)`.
   - Any day is allowed (D8).
3. Reads: `list_daily_notes`, `list_daily_notes_date_v1`, `get_daily_note`, and the ledger feed rows of kind `daily_note` must (a) **exclude** notes whose latest change is `delete`, and (b) return the latest `edit` text instead of the original, plus `edited: true` and `edited_at`. The feed's `note_count` excludes deleted notes. Keep the original payload untouched.
4. Media: do not touch `r2_media_objects` or the attachment rows. A deleted note's image is no longer listed or signed for reading. Check the `r2-media` read path: it must refuse a signed read for a deleted note's object. If it resolves objects through `get_daily_note`, step 3 covers it; otherwise add the check there and say so in ADR 0041.
- SQL test (new `supabase/tests/daily_note_changes.sql`): edit → the list shows the new text and `edited: true`; delete → it disappears from the list, the feed, and `note_count`; editing a deleted note → `note_deleted`; replay → replayed; a different payload with the same key → `payload_mismatch`; partner/employee → `forbidden`; another shop → `not_found`; a closed-day note can be edited.

### T6.2 Client
Files: `daily_notes/application/notes_gateway.dart`, `daily_notes/data/note_codec.dart`, `daily_notes/presentation/daily_notes_screen.dart`.
1. Gateway: `Future<NoteChangeResult> changeNote({required String callerUserId, required String idempotencyKey, required String noteOperationId, required String action, String? text})`, calling `post_daily_note_change_v1`.
2. Codec: read `edited` (bool, default false) and `edited_at`.
3. UI: each note card gets a trailing `PopupMenuButton` (key `note-menu-{operationId}`, tooltip «خيارات الملاحظة») with **«تعديل»** and **«مسح»**.
   - «تعديل» opens a bottom sheet (dialog at wide width) with a single `TextField` prefilled with the text, `maxLines: 5`, `textInputAction: TextInputAction.done`, `onTapOutside` unfocus, and buttons **«حفظ التعديل»** / «إلغاء».
   - «مسح» opens a confirmation dialog: title **«مسح الملاحظة؟»**, body **«ستختفي الملاحظة من الدفتر. يبقى سجل التدقيق محفوظًا.»**, buttons **«مسح»** (error color from the theme) / «إلغاء».
   - States: while in flight the button is disabled and shows a progress indicator; on success, the snack bar shows «تم حفظ التعديل.» / «تم مسح الملاحظة.»; on failure, «تعذر حفظ التغيير. أعد المحاولة.»; when the result is unknown, keep the same idempotency key and offer «إعادة المحاولة».
   - An edited note shows a small «معدّلة» caption under the time.
4. The ledger card for a daily note (in the ledger home) opens the same menu or the notes screen. Use whichever the existing tap does; do not add a second way.
- Tests (extend `app/test/daily_notes_widget_test.dart`): the menu shows تعديل/مسح; edit sends the new text with one key and retries with the same key; delete shows the confirmation dialog and then removes the card after sync; the «معدّلة» caption appears; partner/employee sessions do not see the menu (notes stay owner-only).

---

## M7 — Finish

### T7.1 Full gates
- `flutter analyze` and `flutter test` (the whole suite), and `npm run test:rls` locally with all new SQL test files listed.
- Run `npx tsc -b` and the React lint/tests **only if** a shared contract file under `supabase/contracts/` changed. If you add the new RPCs to `supabase/contracts/`, the admin does not call them, but run the check anyway.
- Visual review of every changed screen: scrap→stock, purchase form, operation screen (sale, purchase, return, expense), closing grid (owner and staff), returns ledger + «إضافة مرتجع», notes menu. Each one in Arabic RTL, light + dark, at 375 px and ≥1280 px, on Windows desktop and an Android emulator.

### T7.2 Validation note and deployment record
- New `docs/operations/owner-feedback-2026-11-08-voice-notes-validation.md`, in the same format as `owner-feedback-2026-11-08-validation.md`: what ran, results, limitations, the hosted deployment record for `xchapwvmvoefriqcxtvn` (migrations applied, hosted checks, the legacy-payable count from T2.4 step 5).
- Mark ADR 0041 status "implemented … not committed / deployed to dev".

### T7.3 Owner acceptance checklist (send to the owner in Arabic)
1. التحويل من الكسر للمخزون: اختيار «خاتم» عيار 21 بوزن 2 جرام يُنقص كسر 21 ويزيد مخزون الخواتم. لا توجد خانة ملاحظات.
2. تقفيل اليومية: صف لكل صنف وأعمدة 18 ثم 21 ثم 22 ثم 14، وخانة صغيرة للعدد حتى 4 أرقام، والوزن اختياري.
3. صفحة الفاتورة: لا توجد خيارات النسخ أو «تسجيل مرتجع أو استبدال»؛ يوجد تعديل ومسح وإرسال واتساب.
4. الشراء: يُخصم المبلغ كاملًا من النقدية فورًا بأي وسيلة دفع، ولا توجد خانة «المستحق للبائع» أو «سداد مبلغ مستحق».
5. شراء خاتم أو سلسلة يزيد الكسر بعياره؛ شراء جنيهات يزيد الجنيهات؛ شراء سبائك يزيد السبائك.
6. دفتر المرتجعات: زر «إضافة مرتجع»؛ المرتجع يُنقص النقدية ويزيد مخزون الصنف نفسه.
7. تعديل ومسح في المرتجعات والمصروفات (يوم العمل المفتوح) وفي الملاحظات (أي يوم).
8. زر «إرسال الفاتورة PDF على واتساب» باقٍ في صفحة الفاتورة، وتعديل الملاحظات ومسحها متاح لأي يوم.

---

## Traceability

| Feedback | Tasks |
|---|---|
| FB-001 | T1.4 |
| FB-002 | T1.1 |
| FB-003 | T3.1, T3.2, T3.3, T3.4 |
| FB-004 | T3.1 (order), T3.2 (compact cells) |
| FB-005 | T1.2 |
| FB-006 | T1.3 |
| FB-007 | T2.1–T2.5 |
| FB-008 | T2.4 (server), T2.6 (verify) |
| FB-009 | T2.4 test (f), T2.6 |
| FB-010 | M4 (contract, T4.2, T4.3) |
| FB-011 | M5 (expenses, returns), M6 (notes) |

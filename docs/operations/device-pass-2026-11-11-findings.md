# Device pass 2026-11-11: findings and work list

Scope: a full hands-on run of the Flutter app on the Android emulator (Pixel, 1080×2400, Arabic RTL, dark theme first) against the development project `xchapwvmvoefriqcxtvn`, test shop «ahmed», checked against the owner requirements recorded from 2026-11-06 to 2026-11-10 (ADR 0039–0046 and their plans). Test data was added and removed freely; it is development data only.

Status key: **Fixed** = changed in the working tree (not committed); **Open** = recorded for a later session; **Decision** = needs the owner or product to choose before code changes.

Severity: **S1** blocks a core workflow or corrupts data, **S2** wrong result or broken feature with a workaround, **S3** UX/visual defect.

## Fixed in this pass

| # | Sev | Area | Finding | Fix | Evidence |
|---|---|---|---|---|---|
| F1 | S1 | Ledger edit | «تعديل» on any sale or purchase posted after 2026-11-05 failed with «تعذر إعداد التغيير أو حفظه». `20261027140000_payment_method_labels` stores `label_ar` in each tender; `trade_change_assert_draft` (and the post path) rejected that key. No edit had ever succeeded on development. | Migration `20261111090000_trade_change_tender_label.sql`: both public trade-change RPCs drop the server-owned `label_ar` from `p_replacement` before validating and hashing (`…_before_tender_label` kept, revoked). Deployed to development, history repaired. | `supabase/tests/trade_change_tender_label.sql` (registered); hosted rolled-back runs of it plus `expense_return_change`, `purchase_paid_and_scrap_routing`, `customer_auto_capture`, `pending_invoices_open_day`, `financial_day_report`, `financial_week_report` pass. Edit confirmed in the app. |
| F2 | S1 | Ledger edit / sync | Edit and delete reviews turned stale within ≤45 s and could not be confirmed («أعد فتح المراجعة…»). `ShopSyncCoordinator`'s poll invalidated every scope on each tick without reading the revision, so every open screen also reloaded every 45 s. | `shop_sync_coordinator.dart`: the poll now runs `_catchUp()` (read, compare revisions, invalidate only changed scopes; full refresh only when the read fails). | `app/test/shop_sync_coordinator_test.dart` (3 new tests; the unchanged-revision test fails on the old code). Edit confirmed after 55 s on the review screen. |
| F3 | S1 | Customers | Every customer auto-created from a sale or purchase (ADR 0043 B-D3) showed «بدون رقم هاتف» with no WhatsApp or call action. Customer reads join phones to `customer_number_declarations`; auto-capture inserted the phone without starting a declaration. | Migration `20261111091000_customer_phone_declaration.sql`: an after-insert trigger on `customer_phones` starts the `unknown` declaration; backfill for phones missing one. Deployed to development. | `supabase/tests/customer_auto_capture_phone.sql` (registered; fails without the fix with `list phones []`); `customers`, `customer_saved_numbers`, `customers_edges`, `batch_c_review_fixes` pass with it. Phone, WhatsApp and call buttons confirmed in the app. |
| F4 | S2 | Inventory calculator | «اجمالي الوزنة 21 مع النقدية»: the price field groups digits («5,000») and the dialog parsed the grouped text, so every price ≥ 1,000 was rejected. | `inventory_figures.dart` parses with `cashInputValue`. | `app/test/inventory_item_grid_test.dart` «the cash calculator accepts a grouped gram price». 5,000 → 483.25 g confirmed. |
| F5 | S1 | Inventory calculator | Closing the price dialog (Back or Cancel) disposed its controller during the exit animation; in debug the whole inventory tab became a red error screen. | The dialog is its own `StatefulWidget` that owns and disposes the controller; Done key submits. | Same test (it reproduced the crash before the fix). |
| F7 | S3 | Inventory carousel (C-D5) | The figure list was `reverse: true`; in RTL that put the first figure («عيار 18») on the far left, and free scrolling left cards cut at both edges. | `inventory_figures.dart`: no reverse; `PageScrollPhysics` with slots of exactly one viewport per page. Order and snapping confirmed on the emulator at 375 px and at landscape width. | `app/test/inventory_item_grid_test.dart` «the first figure is the rightmost tile in RTL» (fails on the old code). |
| F6 | S3 | Arabic RTL text | Latin names and phone numbers scrambled «·» lines and names: «ahmed · 5 نوفمبر» (notes, repair log, debt log) and «عميل 201001234567+» (customer card/detail), «الهاتف: +» wrapped alone (repair detail). | `isolateText` / `isolatePhoneRuns` in `theme/amount_format.dart`, applied to daily notes, repair log and phone, debt log, customer card and detail names. | `app/test/isolate_phone_runs_test.dart`. |

## Open findings

### Data and correctness

| # | Sev | Area | Finding | Suggested direction |
|---|---|---|---|---|
| O1 | S1 | Stock lots (B-D14) | When a sale line's weight differs from the last piece of its named lot (for example an edit 10.50 g → 10.00 g, or a real sale whose weight differs from the recorded piece), `consume_fifo_named` skips that lot (it may not leave weight with zero pieces) and takes the weight from the oldest lots of other items. Observed: the edited chain sale took 8.80 g + 1.20 g from «خاتم» lots; «سلاسل 18» still shows 1 piece / 10.50 g, «خواتم 18» lost a piece. | **Decision**: when the last piece of a named lot is sold, either take the whole remaining weight (difference becomes a stock adjustment), or allow a residue, or block with a clear message. Then fix the edit path too. |
| O2 | S2 | Stock lots / grid | The test shop's pooled opening lots are named «رصيد سابق مجمّع» (`legacy_aggregate = true`, from an older backfill). B-D14's pooled-second preference and C-D4's row label only recognize «رصيد افتتاحي مجمّع», so this shop shows «رصيد سابق مجمع» in the table, never prefers the pooled lot, and offers «رصيد سابق مجمع» as a sellable item under «أخرى». Only one shop has such lots. | Treat `legacy_aggregate` lots as the pooled opening lot in `consume_fifo_named`, `get_inventory_item_grid_v1`, and the product list; hide the pooled pseudo-product from «أخرى». |
| O3 | S2 | Invoice logo (ADR 0039) | The shop has a logo and an active entitlement, but no invoice appearance revision exists, so invoices print the generic diamond. Automatic application runs only for a signup draft or a logo saved after 2026-11-08; logos saved before are never applied. | One-time: apply the current shop logo to invoice appearance for active shops without a revision (client on first owner workspace, or a reviewed server backfill). |
| O4 | S3 | Weight display | The edit screen shows stored weights with three decimals («10.500») while new entry allows two; the weight sheets order karats differently (22, 21, 18, 14) from the choice lists (18, 21, 22, 14). | Align display rules with design-system.md. |

### UX and visual (owner-facing)

| # | Sev | Screen | Finding |
|---|---|---|---|
| U1 | S2 | Daily close | One Back press (or swipe back) discards every count entered, with no confirmation and no saved draft. This is the owner's longest daily form. Add a discard confirmation and keep a local draft. |
| U2 | S3 | Ledger home | The ⚡ quick-actions button covers the weight column of the cards and fully hides values on some rows. Reserve bottom padding or move the default position. |
| U3 | S3 | Sale/purchase review | The review does not show per-line prices (when «سعر لكل صنف» is on) or the customer phone. |
| U4 | S3 | Sale/purchase form | With per-line prices, the payment amount is not prefilled with the line-price total. |
| U5 | S3 | Expense | Expense cards show only «مصروف» and the amount, not the description. The expense form puts «طرق الدفع» above the description; the expense review shows the five-step sale stepper and an empty divider block; the detail says «لا توجد بيانات عميل». |
| U6 | S3 | Trade-change review | Shows «التغير في مستحقات الشراء» on sales (and on every purchase now that purchases are fully paid). Hide when zero / not a purchase with a legacy payable. |
| U7 | S3 | Edit screen | Extra «الفئة» dropdown not on the add form; the category grid highlights the last-added category, not the line being edited; prices show «25000.00» instead of «25,000». |
| U8 | S3 | Card labels | «اسم البائع» on a purchase card names the staff member, but on a purchase the seller is the customer. Use «المسجِّل» or similar. |
| U9 | S3 | Operation detail | Title «بيع» appears twice (app bar and body); the body is a plain text list. |
| U10 | S3 | Payment methods sheet | Title «وسائل الدفع» repeated as the sheet title and the section title. |
| U11 | S3 | Inventory carousel | Order and snapping fixed (F7). Still open: tiles are tall with empty space below the value. |
| U12 | S3 | Repairs | After every status change the owner lands on a bare «تم حفظ الطلب» page and must go back and reopen the repair. Handover with «تحصيل الكل» does not prefill the amount or method (later collection does). Collection asks for the same amount twice for a single tender. Review lists weight twice («الوزن» and «الوزن المدخل»). «العيار» and «العطل» fields touch with no gap. |
| U13 | S3 | Customers | After a status change the success page is cramped (icon and text not centered). The selected filter chip scrolls half off-screen. |
| U14 | S3 | Daily notes | The edit sheet has no title. A previous unsent draft image appears preloaded on entry. |
| U15 | S3 | Day close | Pressing Done moves focus to the next cell, which is easy to mistype into (owner should see where the cursor is). Tapping outside a count cell does not close the keyboard. |
| U16 | S3 | Ledger after close | «إضافة بيع» / «إضافة شراء» stay styled as active while no day is open; tapping shows «يوم العمل مغلق…». Disable them or replace with «فتح يوم جديد». |
| U17 | S3 | Ledger header after close | The header still reads «يوم العمل 30 سبتمبر 2026» after that day is closed. Show «لا يوجد يوم مفتوح» or the last closed date as such. |
| U18 | S3 | «الدفاتر» list | Each closed day shows only «مقفول · فُتح 14:19»; the close time is not shown. |
| U19 | S3 | Admin sign-in | A valid shop-owner account gets «تعذر تسجيل الدخول. تحقق من البيانات» (reads as wrong password). **Decision**: keep generic (no account enumeration) or say the account has no admin access. |
| U20 | S3 | Scrap-to-stock | Returns straight to the ledger with a snackbar, unlike sale/purchase which show a success page; weight there accepts three decimals while sale/purchase accept two. Align. |

### Questions for the owner

- «المزيد ← المساعدة» opens platform Help articles. The owner's 2026-10-05 feedback removed guides and help cards; confirm the Help page itself should stay.
- O1 (which stock a sale takes when the weight differs from the recorded piece) needs a rule before code changes.

## Previously recorded open items (from earlier validation notes)

- `supabase/tests/ledger_trade_change.sql` fails `return_write_still_granted` on development; it is not in `run-rls-tests.mjs`. Its expectation predates ADR 0041 D6 (the return/exchange RPCs stay). Update or retire the file.
- `npm run test:rls` on a local disposable database has not run on this machine (no Docker).
- Device acceptance still open: WhatsApp PDF send on a phone with WhatsApp (B7), logo sharpness (A3), iOS share sheet, Windows WhatsApp hand-off.
- A release build for the owner is still needed for the 2026-11-09/10 UI; only on explicit request.

## Not covered in this pass

- Admin dashboard pages behind sign-in (overview, subscribers, codes, audit history): the only test credentials are a shop owner, which the admin gate correctly refuses. Needs a platform-admin test account.
- Windows build at desktop size: access to the window was declined; the wide layout was checked on the emulator in landscape (≈914 dp, five-destination rail) instead.
- Employee and partner accounts (grants, own-operations home), staff closing-count delegation, debts, traders, analytics and weekly reports, invoice appearance and message settings, shop profile and logo upload, sign-up and password recovery.
- WhatsApp on a device with WhatsApp installed, iOS.

## Gates after the fixes (2026-11-11)

- `dart format --set-exit-if-changed lib test`: clean. `dart analyze --fatal-infos`: no issues. `flutter test`: 1,827 passed.
- `admin/`: `npm run lint` and `npx tsc -b` clean; `npm test` 209/210 under load, the one timeout (`SupportMailboxPanel.test.tsx`) passes 12/12 when rerun alone.
- SQL: hosted rolled-back runs listed under F1 and F3. `git diff --check`: clean.
- Development deployment: migrations `20261111090000` and `20261111091000` applied with `supabase db query --linked` and recorded with `migration repair --status applied`; hosted history ends at `20261111091000`.

## Verified working in this pass

Greeting and logo header, money-only tiles, «وزن مباع» / «وزن مشترى» sheets with scrap per karat and no piece counts, payment-method sheet totals, plural built-in items and «أخرى», karat orders, two-decimal entry, «سعر لكل صنف» remembered and enforced, split tenders, phone default +20 (owner country), «العميل» labels, auto-customer naming «عميل {phone}», invoice PDF (shop name, «العميل», line prices, no internal note), WhatsApp share fallback and separate «نعم، أُرسلت», pending invoices sale-only for the open day, purchase jewelry → scrap, coin «هل تريد إضافتها لمخزون الجنيهات؟» with karats 24, 21, 22, 18, 14, purchase must be fully paid, operation screen without copies panel or return button, edit and delete with net-effect review, expense delete, customer return into named stock, note edit («معدّلة») and delete, inventory zero rows and figures, customer list figures, WhatsApp-group flag, tag and filter, «المرمات» naming, repair handover unpaid and later partial collection, «تحصيل متبقي مرمة» in the feed, item-first day close with exact match, and the reset after close (only cash carried: 563,172), pending invoices empty with no open day, «الدفاتر» newest first with a read-only closed day (WhatsApp send kept), opening a new day with cash carried, scrap-to-stock with an item name and no note field, light theme on the ledger, inventory, customers and «المزيد», the wide layout with the five-destination rail, and the admin sign-in in light and dark at 375 px.

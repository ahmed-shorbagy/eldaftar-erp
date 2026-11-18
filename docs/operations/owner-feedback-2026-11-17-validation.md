# Owner feedback of 2026-11-17: validation record

Scope: milestones of [owner-feedback-2026-11-17-plan.md](owner-feedback-2026-11-17-plan.md). This record is extended as each milestone lands.

## M0. Daily ledger blocked after confirming opening balances (FB-005)

Date: 2026-11-18. Client fix and tests only. No migration, no Edge Function, nothing deployed. Not committed. No release build was made, so the owner's device still runs the affected build.

### Cause, confirmed on development `xchapwvmvoefriqcxtvn`

Checked read-only, inside transactions that were rolled back.

- The affected shop's opening is committed: operation 1 is `opening_balances`, on an open business day dated 2026-11-17. No data repair is needed.
- `get_daily_ledger_home_v2`, read as that shop's owner, returns `state: confirmed`, `read_model_version: 3`, `day_reset: false`, and the opening row with `kind: opening_balances`. The legacy `get_daily_ledger` returns the same operation as `opening_balances_confirmed`.
- `OpeningFlowCoordinator._matches` accepted the read only when the feed held a row of kind `opening_balances_confirmed` for the acknowledged operation. The app reads the home function, so the check could never pass for a new shop. The acknowledged attempt stayed stored on the device and each launch repeated the refusal.

Shops that confirmed their opening before the app moved to the home read were not affected. Every shop opened since then is.

### Change

- `app/lib/src/features/daily_ledger/application/opening_flow.dart`: after the server acknowledges the opening, a confirmed ledger with a business day is the refreshed ledger. The feed is no longer inspected. It is the open day's page, it names the row differently per read, and it does not carry the opening once that day is closed. The `opening_already_confirmed` path already accepted a confirmed ledger on the same grounds.
- `app/lib/src/features/daily_ledger/presentation/daily_ledger_screen.dart`: the notice «تعذر تحديث الدفتر بعد التأكيد» has «إعادة المحاولة», which rereads the ledger. It is no longer a dead end when a read does fail.

A device already stuck needs no manual step: with the fixed build the next read is accepted and the stored attempt is retired. The opening is not posted again.

### Tests

- `app/test/opening_refresh_after_confirm_test.dart` (new, 5 tests). The scripted ledger has the shape the development project returned for a newly opened shop. Covers: the home row kind; confirm then read reaches the ledger; a stuck acknowledged attempt recovers on launch without a second post; the same after the opening day was closed and the feed is empty; a failed read resolves on retry with one confirm call. Four of the five fail on the code before the fix with `OpeningRefreshFailed`.
- `app/test/daily_ledger_widget_test.dart`: the notice shows «إعادة المحاولة», and tapping it opens the ledger and retires the stored attempt.
- `supabase/tests/opening_home_feed.sql` (new, registered in `supabase/run-rls-tests.mjs`): a new shop confirms zero balances; the home read is confirmed, has its business day and one feed row of kind `opening_balances` for the confirmed operation; the legacy read still names it `opening_balances_confirmed`.

### Gates

- `dart format` on the changed files: clean.
- `dart analyze` (whole app): no issues. `flutter analyze` crashed inside the Flutter tool on this machine before analysing, so `dart analyze` was used.
- `flutter test` (full suite): **1936 passed**.
- `opening_home_feed.sql` on development: all checks passed in one block that ends by raising, so the synthetic user, shop, and opening were rolled back. Not run on a local database; none was available.
- `git diff --check`: clean.
- React and TypeScript gates: not run. `admin/` is untouched.

### Device check (Android emulator, 2026-11-18)

Debug build from the working tree, against development, Arabic RTL, dark theme.

- A new owner and shop were registered through the app's own sign-up and activated with one 30-day row in `shop_entitlements` on development (approved by the developer for this test). The credentials are in the git-ignored `app/config/.env.test-shop`. The shop stays on development as test data.
- The new shop opened on «إعداد الأرصدة الافتتاحية», the screen in the owner's screenshots. «تأكيد أرصدة صفرية», then «تأكيد الأرصدة الافتتاحية», opened the daily ledger with zero cash and empty sale and purchase books. The notice «تعذر تحديث الدفتر بعد التأكيد» did not appear.
- After a force stop and relaunch the ledger opened again on «يوم العمل 18 نوفمبر 2026».
- The older test shop, already confirmed, still opens its ledger on the same build.

### Not done

- No release build, so the fix is not on the owner's phone. Building is opt-in under `AGENTS.md`.
- The owner's own stuck phone was not available. Its recovery path is covered by the automated test of a stored acknowledged attempt, not by a device run.

## M1, part 1. The ordinary clock (FB-001)

Date: 2026-11-18. Client changes only (Flutter and React). No migration, nothing deployed, not committed. Stored instants are unchanged: server-generated UTC. Only the display changed.

Rule applied: twelve hours with ص/م, no seconds, no time-zone name, no «UTC», no «توقيت الخادم» or «توقيت المتجر».

### Change

- App: one formatter, `app/lib/src/theme/shop_clock.dart` (wall times the server already converted to the shop zone) and `shop_instant.dart` (instants, converted to the shop zone, or the device zone when none is given). The ledger's existing helpers now delegate to it.
- Screens and PDFs moved to it: ledger timestamps and the «الدفاتر» list, operation PDF, invoice PDF, invoice message time, day and weekly reports and their PDF, analytics PDF, audit trail, customer dates, debt due dates, reminders and their history, debt statement screen and PDF, message settings, support and broadcast dates, the subscription expiry notice.
- Removed from the screen: zone ids such as `Africa/Cairo`, «المنطقة الزمنية», «وقت الخادم UTC», «الوقت العالمي», and raw ISO timestamps. The audit trail shows one line, «الوقت».
- PDF cells that are drawn left to right use `shopNumericDateTimeLtr`, so ص/م sits on the reader's side of the digits as it does on screen.
- Admin: `formatServerInstant` in `admin/src/subscribers/subscriptionFormat.ts` no longer uses the 24-hour cycle or the long zone name. Every admin panel formats through it.

### Tests and gates

- New `app/test/shop_clock_test.dart`: afternoon hours, midnight and noon, the shop day across UTC midnight, no zone name or «UTC» in any output, no direction marks in PDF and message text.
- Nine existing Flutter tests asserted the 24-hour or raw text and now assert the rule: compact ledger, ledger archive, invoice message, repair detail, support dates, customer statistics, and the two debt reminder tests (which also assert that no zone id is shown).
- Admin: `subscriptionFormat.test.ts` asserts 2:05 م for 14:05 Cairo, 12 at midnight and noon, and no «توقيت», «أوروبا», UTC or seconds.
- `dart analyze` (whole app): no issues. `flutter test`: **1941 passed**. One run had a single failure in `invoice_branding_pdf_capture_test.dart` that passed alone and in the next full run; treated as a timing flake of that render test.
- Admin: `npx vitest run` **245 passed**, `npx tsc -b` clean, `npm run lint` clean. One vitest run made while the emulator build was compiling timed out in two unrelated panels; both pass alone and in the idle full run.
- `git diff --check`: clean.
- Device: «الدفاتر» reads «مقفول · فُتح 2:19 م · أُقفل 11 نوفمبر 2026 10:27 ص». The audit trail reads «الوقت: 11 نوفمبر 2026، 2:06 م» and «آخر تحديث للقائمة: 18 نوفمبر 2026، 9:11 ص». The invoice render reads the date, 10:00, then ص from the right.

### Notes

- `invoice_branding_pdf_capture_test.dart` rewrites the PNG files under `docs/reviews/invoice-branding-2026-10-21/pdf/`. They now differ because the invoice time changed. They were restored to keep that review record as it was; the test will rewrite them on each run.
- Not checked on a device: reports, analytics, debts and support screens, and the printed report and statement PDFs. They are covered by widget tests only.
- The admin dashboard was not opened in a browser; no platform-admin test account is available.
- Seen in passing, not changed: the audit card's last line shows the date as digits that reorder in RTL («11-11-2026»).

## M1, part 2. The ledger opens with no opening-balances form (FB-006, FB-022)

Date: 2026-11-18. Flutter client only. No migration, nothing deployed, not committed. Decision: [ADR 0049](../adr/0049-ledger-opens-without-opening-form.md).

### Change

- Removed from `daily_ledger_screen.dart`: the opening form, its stock and scrap rows, its review, and the «تأكيد أرصدة صفرية» button. Removed from `daily_ledger_controller.dart`: the form's fields and draft handling.
- For the owner of an active shop with no confirmed opening, the controller sends the existing `confirm_opening_balances` command with zero balances and shows the ledger when the server confirms. The command keeps its stored idempotency key.
- New states: «تعذر فتح الدفتر» with «إعادة المحاولة» after a failed attempt, «جارٍ فتح الدفتر» with «إعادة المحاولة» when the reply is unknown, «لم يفتح صاحب المحل الدفتر بعد.» for staff, «لم يُفتح دفتر هذا المحل بعد.» for an expired or pending shop.
- Staff waiting for the owner, and an opening with an unknown reply, now resolve on the next sync instead of on the next restart.
- Wording that named «الأرصدة الافتتاحية» elsewhere was changed: the payment-methods empty state, the already-open message, and the refresh notice («تم فتح الدفتر»).

### Tests and gates

- New `app/test/ledger_opens_directly_test.dart` (8 tests) and three new screen tests in `daily_ledger_widget_test.dart`; see ADR 0049 for what each covers.
- Removed with the form: eight screen tests of its fields, review, and draft, and the screenshot captures of the form in `daily_ledger_capture_test.dart`. That file keeps the helpers other tests import and the opened-ledger captures.
- Six other screen tests were adapted because a new shop now opens instead of showing the form.
- `dart analyze` (whole app): no issues. `flutter test`: **1938 passed**. `git diff --check`: clean.
- React and SQL gates: not affected by this part and not rerun.

### Device check (Android emulator)

- A second new owner and shop were registered through the app's sign-up and activated with one 30-day row in `shop_entitlements` on development. Its credentials are in the git-ignored `app/config/.env.test-shop` beside the first test shop's.
- On launch the app showed the daily ledger at once: «يوم العمل 18 نوفمبر 2026», zero cash, empty sale and purchase books. No setup screen appeared.
- On development that shop has one operation, `opening_balances` number 1, one open business day, postings that total zero, and one audit event.

### Open question for the owner

There is no simple way to enter starting cash. Gold can be added from «الجرد الفوري» with «إضافة مخزون». Cash changes only through sales, purchases, expenses, transfers between methods, and the counted correction at day close. The owner did not ask for a cash button and did not say where starting balances should be entered. «إضافة أو تعديل نقدية» in «الجرد الفوري», as in the old app, could be built on the existing `post_ledger_correction_v1` command. It is not built and will not be until he answers.

## Step 0 of the handoff. Branch state (2026-11-18, second session)

`git status` was clean on `owner-feedback-2026-11-17` at `20f5ae0` (the handoff note) over `cb318d8` (FB-005, the clock, the opening form). Nothing was uncommitted. Work continued on that branch. Nothing was pushed or merged.

## M1, part 3. Two-decimal weights (FB-002)

Date: 2026-11-18. Flutter client, `AGENTS.md`, ADRs and the design guide. No migration, no Edge Function, nothing deployed. Committed on `owner-feedback-2026-11-17` on the developer's word; not pushed or merged. Decision: [ADR 0050](../adr/0050-two-decimal-weights.md).

### Rule change

- `AGENTS.md`: «Preserve gram precision to three decimal places» became: store exact integer milligrams; enter and display every weight with two decimals in every screen, PDF and message; never show a third decimal, a milligram figure, or a decimal-places hint. Approved by the developer on 2026-11-18.
- ADR 0050 is new. ADR 0004 (display rule) and ADR 0047 D7 carry a dated amendment note that points to it; their original text is kept.
- `docs/design-system.md`: a «Weights» section at the top, and fifteen sentences that described three decimals or milligram figures were changed.

### Change

- One rounding function, `twoDecimalGrams` (`quantities.dart`), integer arithmetic, half away from zero. Display goes through `displayGrams` / `displayMilligrams` / `displayGoldEffect` (`amount_format.dart`). Fields go through `GramInputFormatter`, `gramFieldText` and `readGramField` (`gram_input.dart`).
- Formatters folded into it: `customerGrams`, `signedGramsText`, `debtGold`, the inline one in `debt_due_screen.dart`, `statementGold`, `gramsOf`, `repairWeight`, `reportGrams`, `Milligrams.gramsText` (used by the invoice, the operation PDF, the operation, return and correction screens, and the message template). Removed: `repairGramsExact`, `repairRoundingHidesMilligrams`, the `exact:` switches on `debtGold` and `repairWeight`, and the milligram suffix of `displayGoldEffect`.
- Entry: the domain parse `Milligrams.parseGrams` accepts at most two decimals. Every weight field has the two-decimal formatter, including fields that had none (debt amount, settlement and lot weight, repair weight, the day-correction weight, every inventory form).
- Removed text: «ثلاث خانات، مثل 1.255» and «أدخل وزنًا أكبر من صفر بثلاث خانات عشرية.» (repairs), «ثلاثة أرقام عشرية كحد أقصى» (debts), «حتى منزلتين عشريتين» (scrap to stock), «أدخل الوزن بمنزلتين عشريتين كحد أقصى.» (sale and purchase), and the «(1,255 ملليجرام)» suffix on confirmations. The repair detail shows one line «الوزن» instead of «الوزن الظاهر» and «الوزن الأصلي».
- The invoice PDF and image print two decimals («1.83 جم»; total «4.39 جم»). Reports, the weekly report, analytics, the report PDF, the debt statement PDF and the trader statement PDF print two decimals.
- The admin dashboard shows no weights. `admin/` is untouched.

### Weights stored earlier with a third decimal

Counted on development `xchapwvmvoefriqcxtvn` on 2026-11-18, read-only: three shops created between 2026-09-27 and 2026-10-13 hold them (8 gold postings, 6 gold balances, 6 lot movements, 4 lots, 1 receipt, 6 repairs, 2 gold debts; values such as 1.255 and 65.555). The two test shops of 2026-11-18 hold none.

Display rule applied, for the developer to confirm: nothing is rewritten; such a weight reads rounded half away from zero (1.255 reads 1.26); entering a recorded weight as it reads means that whole weight. So an unrelated edit of an old sale keeps its weight, a full return or settlement of an old line takes all of it, and a day count typed at the shown balance raises no 0.005 g difference. The last-piece banner is not shown for a difference two decimals do not show.

### Tests

- New `app/test/two_decimal_weights_test.dart` (17 tests): rounding, sign, grouping; every formatter gives the same two decimals; no milligram figure; entry of at most two decimals, Arabic digits; the field refuses a third decimal; a recorded third-decimal weight is kept when left as shown and replaced when changed; a new sale line cannot carry a third decimal; a scan of `app/lib` that fails on a three-decimal formatter, a milligram label, or a decimal-places hint.
- New cases in `owner_answers_2026_11_11_test.dart` (last piece) and `debt_rules_test.dart` (an old gold debt settled in full at its shown weight).
- Existing tests in 22 files asserted three decimals, milligram text, or typed a third decimal (65 failed before they were changed). They now assert the rule. `ledger_trade_change_test.dart` keeps its check that an edit which leaves an old 1.255 g line alone resends 1255 milligrams, with the field now showing 1.26.

### Gates

- `dart format` on `lib` and `test`: no changes left. `dart analyze` (whole app): no issues.
- `flutter test` (full suite): **1956 passed** (1938 before, plus 18 new).
- `git diff --check`: clean.
- React, TypeScript and SQL gates: not run. `admin/` and `supabase/` are untouched.
- The full run rewrote the invoice PNG captures under `docs/reviews/invoice-branding-2026-10-21/pdf/` and the Windows generated files; both were restored. The regenerated invoice was read before restoring: lines «1.83 جم» and «2.56 جم», total «4.39 جم».

### Device check (Android emulator)

Debug build from the working tree on `emulator-5554`, against development, Arabic RTL, dark theme, signed in to the second test shop of 2026-11-18.

- «الجرد الفوري», «إضافة مخزون»: typing 5.255 in «الوزن الفعلي بالجرام» leaves 5.25 in the field. The review reads «يزيد المتاح للبيع: 5.25 جرام». The addition was confirmed («تم حفظ العملية بنجاح.») and stays on development as test data: one item of 5.25 g at 21.
- «الجرد الفوري» after it: the figure «عيار 21» reads 5.25 جرام, «أرصدة الذهب» reads 5.25 جرام, «وزنة التجار الأصلية» reads 0.00 جرام, and the lot row reads 5.25 under «الوزن بالجرام». These rows used three decimals before.
- «المرمات», «استلام قطعة»: «الوزن بالجرام» has no hint, and typing 1.255 leaves 1.25. Nothing was saved.

### Not done

- Not seen on the device: a sale and its review, the ledger cards, returns, the day count, debts, reports, and the PDFs. The sale path could not be reached because of the defect below. They are covered by the widget and unit tests only. Light theme and desktop width were not re-inspected; no layout changed.
- No weight stored with a third decimal was viewed on the device; the test shops have none. That rule is covered by tests only.
- The developer has not yet confirmed the display rule for older third-decimal weights (ADR 0050, decision 5).
- No release build; building is opt-in under `AGENTS.md`.

### Found during the device check, not fixed: «إضافة مخزون» makes the daily ledger unreadable

After the test addition, the «الدفتر» tab of that shop shows «تعذر إتمام العملية. حاول مجددًا.» and «المزيد» shows «تعذر تحميل أرصدة الدفتر.». It does not come from the weights change.

- Cause, confirmed: `get_daily_ledger_home_v2` returns the addition in the open day's feed as `kind: inventory_addition` with `label_ar: null` (read as the shop owner on development, rolled back). The client's feed parser (`daily_ledger_codec.dart`, the `labels` map) does not know that kind and passes the null label on as a string, which throws a type error. A probe test with that row in the standard v2 payload reproduced it; the probe was not kept.
- Effect: any shop that adds, and probably removes or corrects, stock from «الجرد الفوري» loses its daily ledger while that operation is in the open day's feed. Same family as FB-005: the home feed now carries every operation kind of the day.
- Why it matters now: «إضافة مخزون» is the only way to enter starting gold since the opening form was removed, and the handoff proposes it to the owner.
- Not fixed, because the fix needs a decision: which wording each inventory operation gets in «حركة الدفتر», or whether such rows are left out of the feed. The second test shop stays in this state as the reproduction. *Fixed later the same day; see the next section.*

## Fix: stock operations no longer break the daily ledger

Date: 2026-11-18. Flutter client only. No migration, nothing deployed. Committed on `owner-feedback-2026-11-17` on the developer's word; not pushed or merged. Decided by the developer on 2026-11-18: leave these rows out of the daily ledger, as in the old app, whose «الدفتر اليومي» lists only sales and purchases. The owner has not been asked; if he wants stock additions listed, that belongs to the «الدفتر اليومي» page review, with his wording.

### Cause

The open day's feed carries every operation of the day. `private.ledger_operation_label` returns null for ten operation kinds, checked on development against the kinds the table allows: `inventory_addition`, `inventory_removal`, `inventory_correction`, `inventory_conversion`, `inventory_receipt`, `inventory_recognition`, `ownership_transfer`, `receipt_manual_allocation`, `expense_reversal`, `customer_return_reversal`. The client parser passed the null label on as a string and threw, so the whole ledger read failed. The last two are the rows an edit or delete of an expense or a customer return leaves behind, so those actions broke the ledger the same way.

### Change

`app/lib/src/features/daily_ledger/data/daily_ledger_codec.dart`: a feed row whose kind this build does not list and whose label the server left null is skipped, in the home read and in the paged read. Everything else stays strict: a listed kind without its label, an unknown kind that carries a label, and a malformed row are still refused. The operations stay on the server and in «سجل العمليات»; the stock they changed shows in «الجرد الفوري».

Checked before the change: the feed is merged by operation id and paged by the server's cursor, with no check that sequences are contiguous, and the day close does not read the feed. One limit: a catch-up page made only of skipped rows stops that catch-up early; it would take a hundred such operations in a row.

### Tests and gates

- New `app/test/ledger_feed_unlisted_kinds_test.dart` (16 tests): the row development returned for the addition; each of the ten kinds is left out and the other rows are kept; a day with only such rows reads as an empty ledger; the paged read leaves them out and keeps its cursor; the three strict cases above still throw. Before the fix the first case threw a type error (probe run on the unfixed code).
- The response development returned for the affected shop was run through the fixed parser and read as one feed row and one stock row. That check was a throwaway and is not kept.
- `dart format`: no changes left. `dart analyze` (whole app): no issues. `flutter test` (full suite): **1972 passed**. `git diff --check`: clean.

### Device check (Android emulator)

Debug build from the working tree, the second test shop, which was in the broken state.

- «الدفتر» opens on «يوم العمل 18 نوفمبر 2026» with the sale and purchase books. «حركة الدفتر» lists «رصيد افتتاحي» only. «المزيد» shows «باقي أرقام الدفتر» again.
- The clean build opened the ledger on its first launch and on six more after a force stop. Three launches of the same code with one temporary log line also opened it.
- One launch did not: the first rebuild after the fix, built while the full test suite was compiling, still showed «تعذر إتمام العملية.» although the server answered the read with 200. It was not reproduced in the ten launches after it and its cause was not found.
- With the ledger open, the weights check that the defect had blocked was done: in «إضافة بيع», typing 2.505 leaves 2.50, and the review reads «2.50 جرام» and «ينقص مخزون خواتم عيار 18: 2.50 جرام · 1 قطعة». The sale was not confirmed.

## M1, part 4. «مشغولات» is not shown (FB-003)

Date: 2026-11-18. Flutter client and the design guide. No migration, nothing deployed. Committed on `owner-feedback-2026-11-17` on the developer's word; not pushed or merged. `admin/` never used the word.

### Wording

The owner's instruction is that the word goes and work is by item names. Where that left a choice, the developer decided on 2026-11-18; the owner has not confirmed these three choices.

| Where | Before | Now | Source |
| --- | --- | --- | --- |
| A line that already shows the item name (sale and purchase review, operation detail, edit review, debt lot and receipt lines, the lot table, the invoice) | «خواتم · عيار 18» with «مشغولات» beside or under it | The item name alone. Bullion, coins and scrap keep their kind word. | Owner: by item names |
| A row with a karat and no item name (stock effect lines, the unnamed day count, exchange and edit effects, trader totals and their PDF, weekly report groups) | «مشغولات عيار 21» | «عيار 21» | Developer's choice. The old app's «عيار 18» and «عيار 21» figures already mean jewelry. |
| Headings and choice lists (the «الفئة» list in the inventory forms, the inventory filter, the sold and bought weight sheets, the ledger stock groups, the gold-debt receipt list, the category column of the weekly report PDF) | «مشغولات», «مشغولات ذهبية» | «أصناف» | Developer's choice, after «الأصناف حسب العيار» on the inventory page |
| Inventory figures | «وزن المشغولات», «اجمالي الوزنة 21 (مشغولات + سبائك)» | «وزن الأصناف», «اجمالي الوزنة 21» | Developer's choice; the second is the old app's label |
| Message an outdated build can receive | «المشغولات المشتراة تُسجَّل كسرًا. …» | «الأصناف المشتراة تُسجَّل كسرًا. …» | Follows the «أصناف» choice; not put to the developer separately |

### Change

- `karatRowLabel` in `opening_copy.dart` writes rows that have a karat and no item name. The label functions for headings and lists (`stockCategoryLabel`, `goldCategoryLabel`, `inventoryCategoryLabel`, `debtCategoryLabels`, `reportCategory`, and the private ones in the operation, exchange and edit screens) return «أصناف».
- The ledger's stock groups took their heading from the server's label. They now take it from `goldCategoryLabel`.
- The server still sends «مشغولات» as `label_ar` of jewelry stock rows, and older builds expect it. The parser keeps that one wire constant to check the read; no screen prints it. No server change was made.
- Not changed: «عملات» for coins in inventory, debts and the invoice, which is on the banned list for step 3; and the lot filter, the category lists and the other inventory blocks the plan removes in the «الجرد الفوري» page review.

### Tests and gates

- New `app/test/jewelry_wording_test.dart` (5 tests): the karat-only row; bullion, coins and scrap keep their names; every list label is «أصناف»; the stock addition review lines; a scan of `app/lib` and `admin/src` that fails on the word anywhere except the parser's wire constant.
- Six existing test files asserted the old word and now assert the rule: the bought-weight sheet heading, the inventory total label, the invoice line, the edit review line, the outdated-build message, and the weekly report group.
- `dart format`: no changes left. `dart analyze` (whole app): no issues. `flutter test` (full suite): **1977 passed** (1972 before, plus 5 new). `git diff --check`: clean.

### Device check (Android emulator)

Debug build from the working tree, the second test shop, dark theme.

- «الجرد الفوري»: the filter reads «أصناف»; the lot row reads the item name with nothing under it; the figures read «اجمالي الوزنة 21» and «اجمالي الوزنة 21 (مع الكسر)».
- «إضافة مخزون»: «الفئة» reads «أصناف»; the review reads «يزيد المتاح للبيع: 3.50 جرام عيار 21.» and «يزيد عدد المتاح للبيع (عيار 21): 1.». Not confirmed.
- «إضافة بيع» review: «خواتم · عيار 18», «1 قطعة», «2.50 جرام». Not confirmed.
- Not seen on the device: the sold and bought weight sheets, the day count, debts, the trader screens, reports, the invoice, and «وزن الأصناف». They are covered by tests and by the source scan. Light theme and desktop width were not re-inspected; no layout changed.

## M1, part 5. The owner glossary and the guard (handoff step 3)

Date: 2026-11-18 (third session). Tests and documentation only. No file under `app/lib`, `admin/` or `supabase/` changed: no screen text, no migration, nothing deployed. Committed on `owner-feedback-2026-11-17` on the developer's word; not pushed or merged.

Started from a clean tree on `owner-feedback-2026-11-17` at `ae8c6ec`.

### What was added

- [docs/owner-glossary.md](../owner-glossary.md): each term the owner rejected, where the app still shows it, his word, the source of that word, and its state. Section 2 drafts the open rows as questions for him. Section 3 lists words found in the app that he has not rejected, as proposals. It is linked from `docs/design-system.md` (a new first section, «The owner's words») and from the handoff.
- `app/test/owner_terms_guard_test.dart` (16 tests): one list of banned terms, each with its reason; two exact allowed lines; one list of waiting terms. It scans `app/lib` and `admin/src` and names the file and line of an offender.
- The source scans at the end of `jewelry_wording_test.dart` and `two_decimal_weights_test.dart` moved into the guard, so the list is in one place. Their other tests are unchanged. A test in the guard runs the wording both scans used to stop («مشغولات عيار 21», «ثلاث خانات، مثل 1.255», «ثلاثة أرقام عشرية كحد أقصى», «حتى منزلتين عشريتين», «حتى ثلاث منازل», «(1,255 ملليجرام)», `toStringAsFixed(3)`, `decimalPlaces: 3`, the three-digit pad) through the new rules. The guard is stricter than they were in four ways: the weight wording is checked in `admin/src` too, vowel marks and the tatweel are removed before matching, an offender is reported by line, and an allowed line must still exist.

### How each candidate term was sorted

The handoff's rule: a term is banned only when its replacement is in place. Every candidate was searched in `app/lib` and `admin/src`.

| Group | Terms |
| --- | --- |
| Gone from the screens, banned now | «مشغولات» (as before, one wire line allowed); «الصيانة» ([ADR 0044](../adr/0044-owner-answers-2026-11-10.md) C-D7; not on the handoff's list); milligram spellings; decimal-places hints («منازل», «منزلة», «منزلتين», «ثلاث خانات», «عشري» in any form); third-decimal formatter calls in `app/lib`; zone names beside a time («توقيت الخادم», «توقيت المتجر», «التوقيت العالمي», «الوقت العالمي», «توقيت شرق أوروبا») with the formatter options that print them (`timeZoneName`, `hourCycle`, `hour12: false`); «UTC» or «GMT» on a line of Arabic text |
| Still shown, his word known, assigned to step 4 | «التجار والأمانات» (3 lines), «الديون» as the page name (19), «العطل» (4), «وصف القطعة» (1), «الحيازة» in repairs (5), «باقي أرقام الدفتر» (1) |
| Still shown, his word known, a plain swap, waiting on the developer | «عملات» as the coin category label, to «جنيهات»: `debt_copy.dart`, `inventory_copy.dart`, `branded_invoice_document.dart` (the invoice), `financial_week_report.dart` («عملات ذهبية»), and the list nouns in `inventory_forms.dart` and `inventory_screen.dart`. Not made in this step. *Made later the same day; see the next section.* |
| Still shown, his word not recorded or the page is to be redesigned | «حيازة» outside repairs (5), «أمانة» (33), «كشف أمانة» (4), «بانتظار الاعتراف» and «اعتراف» (14), «متاح للبيع» (7), «دفعات» (15), «فئة سبيكة اسمية» and «اسمي» (21), the coin catalog lines «نوع العملة» (6), the bare word «توقيت» (3), repairs «أرشفة» (10) |
| Not in the source | «إضافة صف» (FB-004). Not banned: what he rejected there is not established. |

Terms rejected in one sense only are matched in that sense, and the glossary says how: «أمانة» and «أمانات» as whole words («بأمان» is left alone), «الديون» with the article («ديون» the noun is left alone), «دفعة» and «دفعات» («الدفع» is left alone), «عشري» but not «عشرين», «UTC» on a line of Arabic text but not the zone id in code. Two could not be banned by word: the repairs «أرشفة» (customers, debts and payment methods archive too) and the bare «توقيت» (the owner writes «التوقيت» himself for the time of day; the three lines left are reminder messages and one admin hint, not zone labels).

The waiting terms are in the guard as a second list. When the last line that shows one is removed, the test fails until the term is moved to the banned list. Step 4 will meet this at each rename; that is intended.

### Proof that the guard fails

Scratch edits, undone afterwards with `git checkout`:

- `'worked_jewelry': 'مشغولات'` put back in `debt_copy.dart`, «الصيانة» added to `repair_copy.dart`, and the admin hint in `admin/src/broadcasts/copy.ts` changed to «توقيت الخادم UTC، …». The run failed four tests, each naming its line, for example `app/lib/src/features/debts/presentation/debt_copy.dart:38: 'worked_jewelry': 'مشغولات',` and `admin/src/broadcasts/copy.ts:38: startsAtHelp: 'توقيت الخادم UTC، خلال 90 يومًا.',`.
- «وصف القطعة» renamed in `repair_screen.dart`: the run failed with «وصف القطعة» (was waiting on handoff step 4: «اسم الصنف») and the instruction to move it to the banned list.

### Gates

- `dart format lib test`: no changes left. `dart analyze` (whole app): no issues.
- `flutter test` (full suite): **1991 passed** (1977 before, less the two scans that moved, plus the 16 tests of the guard).
- `git diff --check`: clean.
- The full run rewrote the invoice PNG captures under `docs/reviews/invoice-branding-2026-10-21/pdf/` and the Windows generated files; both were restored.
- React, TypeScript and SQL gates: not run. `admin/` and `supabase/` are untouched. The guard reads `admin/src` from the Flutter test.
- Documentation: links in the glossary, the design guide and the handoff were checked to resolve; the glossary holds no customer data, credentials or contract details.

### Device check

None. No screen text changed, so there was nothing to see on the emulator.

### Not done

- No screen was changed. Every rejected term that was on a screen at `ae8c6ec` is still there; the glossary says what each waits on.
- The six «عملات» swaps wait for the developer's word. *Approved and made later the same day; see the next section.*
- The words in the glossary's section 3 are the assistant's findings («النقد» against his «النقدية», «المتجر» against «المحل», «الخادم», «يوم العمل» and others). None is banned or changed.
- The voice notes and the 24-item summary are not in the repository. Sources for FB items cite the plan and the handoff, not his recorded words.
- `inventoryGuideSteps`, `traderGuideSteps` and the `InventoryGuide` widget are unused since the guides were removed. They were left in place; their text holds waiting terms, so it has to go before those terms can be banned.
- Handoff steps 4, 5 and 6 were not started.

## M1, part 6. Coins read «جنيهات» in six labels

Date: 2026-11-18 (third session). Flutter client text only. No layout, navigation or behaviour change, no migration, nothing deployed. Committed on `owner-feedback-2026-11-17` on the developer's word; not pushed or merged. The developer approved these six swaps on 2026-11-18 after they were listed in part 5. «جنيهات» is the owner's word: the old app's table row and type list, «قسم الجنيهات» in the requirements, and [ADR 0044](../adr/0044-owner-answers-2026-11-10.md) C-D2 and C-D8. The daily ledger already said «جنيهات».

### Change

| File | Before | Now | Where it shows |
| --- | --- | --- | --- |
| `debts/presentation/debt_copy.dart` | «عملات» | «جنيهات» | The category of a gold debt's receipt and lot lines |
| `inventory/presentation/inventory_copy.dart` | «عملات» | «جنيهات» | The «الفئة» list of the inventory forms, the inventory filter, stock effect lines |
| `invoice_appearance/domain/branded_invoice_document.dart` | «عملات» | «جنيهات» | The kind line under a coin item on the invoice |
| `reports/domain/financial_week_report.dart` | «عملات ذهبية» | «جنيهات» | The category group of the weekly report and its PDF |
| `inventory/presentation/inventory_forms.dart` | «عملات» | «جنيهات» | The count line under the coin list of the add-stock form: «المعروض 3 جنيهات. …», «جنيهات أقدم» |
| `inventory/presentation/inventory_screen.dart` | «عملات» | «جنيهات» | The same count line in the catalog block of «الجرد الفوري» |

Not changed: the six coin catalog lines («نوع العملة», «نوع عملة», «هوية العملة 3», «— عملة 3»). They have no plain swap and wait for the «الجرد الفوري» page review, so «عملة» stays in the guard's waiting list and is not banned yet. The glossary row and the handoff say so.

### Tests and gates

- New in `jewelry_wording_test.dart`: coins are «جنيهات» in every label function (ledger, inventory, debts, weekly report). New in `invoice_appearance_test.dart`: a coin line carries «جنيهات» as its kind on the invoice. No existing test asserted the old word.
- `dart format lib test`: no changes left. `dart analyze` (whole app): no issues.
- `flutter test` (full suite): **1993 passed** (1991 before, plus 2 new).
- `git diff --check`: clean. The files the full run rewrites were restored.
- React, TypeScript and SQL gates: not run. `admin/` and `supabase/` are untouched.

### Device and render check

Debug build from the working tree on `emulator-5554`, against development, Arabic RTL, dark theme, the second test shop of 2026-11-18.

- «الجرد الفوري», «إضافة مخزون»: the «الفئة» list reads «أصناف», «سبائك», «جنيهات», «كسر», and the field shows «جنيهات» once chosen. Nothing was saved.
- «الجرد الفوري», «الكتالوج»: the count line reads «المعروض 0 جنيهات. لا يوجد مؤشر لصف أقدم.». The button under it still reads «نوع عملة», as expected.
- The invoice: the capture test's purchase invoice with a coin line was read before it was restored. The kind line under the item reads «جنيهات».
- Not seen on the device: the gold-debt receipt list, the weekly report group and its PDF, and a stock effect line for coins; the test shop has no coins, debts or report data. They are covered by the new label tests. Light theme and desktop width were not inspected; no layout changed.

## Still open in M1

Nothing in M1 itself. Before the owner build: his answer on where starting cash and gold are entered, and his word on «أصناف» and the two figure labels.

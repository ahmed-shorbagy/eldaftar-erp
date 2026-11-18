# Owner feedback of 2026-11-17: plan

Status: decisions 1 to 3 approved on 2026-11-18. M0 is implemented, confirmed on development and on the emulator. The clock part of M1, the removal of the opening-balances form ([ADR 0049](../adr/0049-ledger-opens-without-opening-form.md)), and two-decimal weights ([ADR 0050](../adr/0050-two-decimal-weights.md)) are implemented. All are in the [validation record](owner-feedback-2026-11-17-validation.md). «مشغولات» is removed from every screen. The glossary of the owner's terms is [docs/owner-glossary.md](../owner-glossary.md) and the guard is `app/test/owner_terms_guard_test.dart`; it bans the terms already gone from the screens and keeps the others as waiting. M2 onward is not started. M0, the clock and the opening form are committed as `cb318d8`, and the weights work in the commit after the handoff note, all on `owner-feedback-2026-11-17`. Nothing pushed, migrated or deployed.
Date: 2026-11-18
Source: six owner voice notes and four screenshots of 2026-11-17, the 24-item feedback summary prepared from them, the requirement documents at the repository root, and the [old app reference](../reference/old-app-2026-11-10/README.md).

## 1. What the owner is telling us

The owner could not use the app at all, and he has now repeated three corrections several times. Read together, the six notes say four things:

1. **The app is blocked.** After confirming zero opening balances the daily ledger shows «تعذر تحديث الدفتر بعد التأكيد» and nothing else. Every other comment was made without being able to test.
2. **Three standing rules were given before and are still broken**: the clock, the word «مشغولات», and weight decimals. He now doubts that his comments reach the person writing the code.
3. **The vocabulary is not his trade's.** «حيازة», «أمانة», «بانتظار الاعتراف», «دفعات», «عملة», «العطل», «كشف أمانة محاسبي» and similar terms come from our data model, not from a gold shop.
4. **He wants to go page by page.** Agree each page before building it, starting from the old app's pages and adding the new logic from the requirements, and stop delivering everything at once.

The plan follows from that: unblock first, fix the three standing rules everywhere and make them impossible to regress, then rebuild one page at a time, each behind an owner sign-off.

## 2. Findings from the code

### 2.1 The blocked ledger (FB-005) has a specific cause

Found by reading the code, then confirmed on the development project `xchapwvmvoefriqcxtvn` on 2026-11-18 (see the validation record).

- After the confirm call succeeds, `OpeningFlowCoordinator._matches` (`app/lib/src/features/daily_ledger/application/opening_flow.dart:509`) accepts the ledger read only if its feed contains a row of kind `opening_balances_confirmed` for that operation.
- The app reads the ledger with `get_daily_ledger_home_v2`. Since the home read took its feed from the date read, that row arrives with the operation kind `opening_balances` (`supabase/migrations/20261019184500_ledger_date_read.sql:177`, `'kind', kept.kind`). Only the legacy `get_daily_ledger` emits `opening_balances_confirmed`.
- The parser accepts both kinds (`daily_ledger_codec.dart:619-620`); only this one check does not. The result is `OpeningRefreshFailed`.
- The acknowledged attempt is stored on the device, so every launch repeats the same check and the same banner. The opening itself is committed on the server.
- Tests miss it because the flow tests script a fake gateway that returns the legacy kind (`app/test/daily_ledger_flow_test.dart:63`). No test feeds a real `get_daily_ledger_home_v2` payload of a fresh shop through the flow.

If this is confirmed, every newly registered shop is affected and shops that confirmed their opening earlier are not. A fixed build clears the stuck state by itself: the next read matches and the pending record is retired. No data repair is expected.

### 2.2 The clock complaint (FB-001) is a format, not an offset

The summary reads it as «remove the EET offset». The notes say something else: «الساعة ٢ تبقى الساعة ٢» and «اللي بنماينص منه ١٢ ساعة» describe a 24-hour clock, and «توقيت أوروبا الشرقية» is the zone name printed beside it.

- Admin: `admin/src/subscribers/subscriptionFormat.ts:70-80` formats every instant with `hourCycle: 'h23'` and `timeZoneName: 'long'`, which renders as «14:05:09 توقيت شرق أوروبا».
- App: a 12-hour helper exists (`formatShopTwelveHourTime`, `opening_copy.dart:126`) but many screens print the server's `YYYY-MM-DD HH24:MI:SS` text and zone labels directly: `reports_screen.dart:376,383`, `weekly_reports_screen.dart:374`, `report_pdf.dart:102-109,244`, `audit_trail_screen.dart:325` («توقيت الخادم»), `debt_native_screen.dart:513,638`, `debt_due_screen.dart:678`, `debt_statement_pdf.dart:110`, `subscription_notice_banner.dart:13`.

The stored times are correct. Storage stays UTC and server-generated. Only the display changes: 12-hour clock with ص/م in the shop's time, no zone name, no «توقيت الخادم».

### 2.3 Other findings that change the summary

| Summary item | What the code shows |
| --- | --- |
| FB-003 «مشغولات» | Label of the stock category `worked_jewelry` in 14 places (opening form, invoices, reports, debts, inventory, operation screens) plus two figure labels: «وزن المشغولات» and «اجمالي الوزنة 21 (مشغولات + سبائك)». The opening form asks for a category, so it can never be item-first. |
| FB-002 decimals | About twenty separate gram formatters and several input hints («حتى ثلاث منازل», «ثلاث خانات، مثل 1.255»). `AGENTS.md` and ADR 0004 require three decimals, and ADR 0047 D7 keeps a stored third decimal visible. These conflict with the owner's rule and must be amended, not worked around. |
| FB-004 «إضافة صف» | The string does not exist in the current source. It may come from the installed build. Find it on the device before claiming a fix. |
| FB-010 «تصفية الدفعات» | This is the lot filter («بحث في الدفعات», chips الفئة / العيار / الحيازة), not a payment settlement. The whole lot concept is internal and should leave the page. |
| FB-008, FB-009 | [ADR 0044](../adr/0044-owner-answers-2026-11-10.md) C-D4 put «جنيهات» as the first table row and «كسر» as the last, read from the old app. The owner now wants both out of the table. That decision is reversed, with a new ADR. |
| FB-019 «مؤرشفة» | The repair screen has an archive stage and wording. The old app has delete with a confirmation; the requirements ask for «Dialog عند الاستلام أو المسح». |
| FB-013 weight optional | A zero weight is rejected in the domain (`repair_rules.dart:277`, `weightRequired`) and the review says «تزيد الحيازة بهذا الوزن». Making it optional is a server change, not a label. |
| FB-015 الحسابات | The trader module is a custody model (receipt, pending recognition, manual link, ownership transfer, gold obligations). The requirements describe «الحسابات (الأبونيهات)»: an account per trader with «وزنة 21» and «أجرة», an optional stock link with a status per weight, settlement from scrap, stock or cash, search, and a PDF. The fit between the two is unknown until examined in that page's milestone. |

### 2.4 What the requirements say about «الجرد الفوري»

From «متطلبات الابليكشن و كل صفحة»: التحييفات for 14, 18, 21, 22 and 24; cash with its انستا / محفظة / فيزا breakdown; scrap for 14 and 22 when present; a section for السبائك with each weight and its count; a section for الجنيهات by ربع / نصف / جنيه with weight and count; deleting an item; «وزنة التجار (الأبونيهات)» shown on its own; the total original weight; item rows for 14 and 22 when present.

The current page has the carousel and the item table. It lacks the two sections with their detail view, has «كسر» and «جنيهات» inside the table, and adds lot lists, custody classes, a catalog, and trader actions that the owner does not recognize. The current totals convert to 21 with bullion counted as 24 (`inventory_item_grid.dart`, `_to21`). The owner asked on what basis; the factors and what each total includes must come from him as worked numbers before any figure is kept.

## 3. Decisions needed before work starts

| # | Decision | Recommendation |
| --- | --- | --- |
| 1 | Weight precision. The owner's rule is two decimals. `AGENTS.md` says three. | Keep integer milligrams in storage, with no migration. Enter and display two decimals everywhere through one formatter and one input. Amend `AGENTS.md`, ADR 0004 and ADR 0047 D7 in the same change. Count stored weights with a non-zero third decimal on development and decide their display before shipping. |
| 2 | Opening balances. The owner does not want the setup form on entry. | Remove the form. A new shop opens straight on the ledger with a zero opening confirmed automatically through the existing idempotent command. Cash and weights are then entered from «الجرد الفوري» with «إضافة أو تعديل نقدية» and «إضافة أو تعديل وزنة», as in the old app. Confirm with the owner in the first page meeting (FB-022). |
| 3 | Hosted access. The connected Supabase connectors point at other projects. | Provide access to `xchapwvmvoefriqcxtvn`, or run the reproduction and deployment from the usual environment. Milestone 0 cannot be called verified without it. |
| 4 | Delivery rhythm. | One page per delivery after Build 1, each with the owner sign-off in section 5. |

## 4. Milestones

Every milestone runs the gates in `AGENTS.md` for what it touches, records its validation note under `docs/operations/`, and keeps installed older builds working under [ADR 0044](../adr/0044-owner-answers-2026-11-10.md) C-D1: server reads that old builds call keep their shape, and new fields go to new reads.

### M0. Unblock the daily ledger

1. Reproduce on a local database and on development: register a shop, confirm zero opening balances, read `get_daily_ledger_home_v2`, and record the feed row kind.
2. Fix the post-commit match to accept the opening row the home read actually returns. Keep the operation id check.
3. Regression tests: a flow test fed with a recorded `get_daily_ledger_home_v2` payload of a fresh shop (zero and non-zero), a test that a stored acknowledged attempt resolves on the next launch, and a SQL test asserting the opening operation is in the home feed of a new shop.
4. Review the dead-end itself: «تعذر تحديث الدفتر بعد التأكيد» must offer «إعادة المحاولة» and never leave an empty screen.
5. Confirm on the owner's stuck shop that the fixed build opens the ledger.

Done when a new shop reaches the working ledger on a device, and the owner's existing shop does too.

### M1. The three standing rules, everywhere

**Clock.** One display helper in the app and one in the admin: 12-hour, ص/م, shop time, no zone name. Replace every raw timestamp and zone label listed in 2.2, including PDFs. Remove «توقيت الخادم» and zone ids from owner-facing text. Tests cover midnight, noon, and the day boundary.

**Weights.** One formatter and one input for grams across the app, replacing the separate formatters. Two decimals in entry, review, cards, tables, PDFs, and WhatsApp text. Remove every «ثلاث منازل» hint. Admin too where a weight appears.

**«مشغولات».** The category name is never shown. Jewelry appears by item name. Rename the two figure labels with the owner's wording. Invoices, reports, debts, and operation screens show the item name they already carry.

**Guard.** A glossary file of the owner's terms, and a test that fails when a banned term appears in `app/lib` or `admin/src`: مشغولات، حيازة، أمانة، بانتظار الاعتراف، متاح للبيع، دفعات، عملة، العطل، وصف القطعة، الديون (as a page name), كشف أمانة، فئة سبيكة اسمية، and three-decimal hints. This is what stops a fifth repetition.

**Opening form.** Per decision 2: remove the form and its review, auto-confirm zero for the owner, and show staff a plain waiting state until the owner has opened the shop. New ADR amending ADR 0004.

### M2. «المزيد» and names (text and navigation only)

- Page names as in the old app: «الدفاتر», «الحسابات», «المرمات», «التحليلات», «النوتة». Rename «الديون» in all 19 places and «التجار والأمانات» in all 3.
- Remove «باقي أرقام الدفتر» and the inventory figures from «المزيد» (`ledger_more_balances.dart`). «المزيد» lists pages and settings only.
- Repairs labels: «اسم الصنف», «متطلبات التصليح», and no «الحيازة» wording.
- «التقارير» against «التحليلات» (FB-020, FB-024): the requirements place the PDF and weekly reports under «صفحة الدفاتر». Proposal for the owner: move reports inside «الدفاتر» and keep «التحليلات» as the charts page.

**Build 1 = M0 + M1 + M2.** It gives the owner a working app in his words, so his real review of the numbers can begin.

### M3 onward. One page per delivery

Each page starts with the sign-off in section 5. Order proposed to the owner:

| Page | Scope to agree |
| --- | --- |
| **M3 «الجرد الفوري»** | Old layout: figures, then «إضافة أو تعديل نقدية», «إضافة صنف», «إضافة أو تعديل وزنة». New sections «السبائك» and «الجنيهات» at the top, each with a detail button like the cash breakdown, listing every item with its weight and count, and «إضافة صنف للسبائك» / «إضافة صنف للجنيهات». Table of jewelry items only, with its own total, and item delete. «الكسر» in its own card per karat (FB-023). «الوزنة الأصلية» (the shop's) and «وزنة التجار» (taken from traders). التحييفات for all five karats from the owner's worked numbers (FB-021). Removed from the page: lot search and filters, custody classes, «أرصدة الذهب», the trader action group, the catalog block. Server tables and commands stay; only entry points go. A cash adjustment command may be needed; check before designing. New ADR reversing ADR 0044 C-D4. |
| **M4 «الحسابات»** | Old layout: «وزنة 21», «اجمالي الأجر», «إضافة حساب», a card per account. New logic from the requirements: optional «إضافة للمخزون» after each addition, a status per weight, a count of weights not yet added, settlement from scrap, stock or cash, search, PDF, karats 14 and 22. Name only on the add form. First step is a gap analysis of the custody model against this, because «أجرة» may not exist in it. |
| **M5 «المرمات»** | Optional weight (domain rule, SQL check, review text). Delete with a dialog instead of archive, if the owner confirms. Handover dialog and cash question are already built; verify against the requirements. |
| **M6 «النوتة»** | «للمحل» and «على المحل» with totals in money and weight, and the stock or cash question on settlement. Compare with the current debts flow. |
| **M7 «الدفتر اليومي»** | The owner's first real review of the numbers: every sale, purchase, return, expense, and close checked against his own examples for cash, stock, scrap, and التحييف. |
| **M8 «الدفاتر» and «التحليلات»** | Per the decision taken in M2. |

## 5. Sign-off for each page

The owner offered a meeting per page. Each page goes through the same six steps, and no code is written before step 3.

1. **Sheet.** One Arabic page: the old app's screenshot, the current screen, the proposed layout, the exact words on every button and label, and what is removed.
2. **Worked numbers.** Two or three examples in the owner's figures, for instance: stock before, a sale of a named item, stock and cash after. For «الجرد الفوري», the conversion of each karat to 21.
3. **Agreement.** A call or voice reply. The answers are written into an ADR the same day, in his words.
4. **Build.** Only what the sheet shows. Anything else found on the way is listed for the next sheet, not added.
5. **Proof.** Device screenshots in Arabic, both themes, sent with the build, plus the examples from step 2 run on the build with the results.
6. **Acceptance.** The owner's reply is recorded in the validation note. The page is closed only then.

## 6. Traceability

| Item | Where | Item | Where |
| --- | --- | --- | --- |
| FB-001 | M1 clock | FB-013 | M5 |
| FB-002 | M1 weights, decision 1 | FB-014 | M2 |
| FB-003 | M1, M3 | FB-015 | M2 name, M4 |
| FB-004 | M1, locate on device first | FB-016 | M3 |
| FB-005 | M0 | FB-017 | M2 |
| FB-006 | M1 opening form, decision 2 | FB-018 | M2 |
| FB-007 | M3 | FB-019 | M5 |
| FB-008 | M3 | FB-020 | M2 proposal, M8 |
| FB-009 | M3 | FB-021 | M3 sheet |
| FB-010 | M3 | FB-022 | decision 2, M3 sheet |
| FB-011 | M1 guard, M3 | FB-023 | M3 sheet |
| FB-012 | M2 | FB-024 | M2 proposal, section 5 |

## 7. Risks

- **M0 is a diagnosis by reading.** If the reproduction shows a different cause, M0 changes and Build 1 waits for it.
- **Two decimals over stored milligrams.** Totals are summed in milligrams and shown at two decimals, so a column may differ from the sum of its displayed rows by 0.01. Agree the rounding with the owner on the «الجرد الفوري» sheet.
- **Removing entry points, not data.** Lots, custody classes, and trader commands stay on the server. Existing development data created through them must still read correctly on the simplified pages.
- **Installed older builds.** Every server change keeps the old read shapes (ADR 0044 C-D1).
- **Scope.** M4 may be larger than a re-skin. Its gap analysis decides that before any date is promised.

## 8. Proposed reply to the owner

A draft for the developer to send. Nothing has been sent.

> وعليكم السلام يا فندم. كلامك كله واضح ومعاك حق فيه.
> أول حاجة: مشكلة «تعذر تحديث الدفتر بعد التأكيد» عرفنا سببها وهي أول حاجة هتتصلح، وهبعتلك نسخة تشتغل بيها على طول.
> في نفس النسخة هيتقفل التلات حاجات اللي اتكررت: الساعة هتبقى عادي (٢ يعني ٢) ومن غير «توقيت أوروبا الشرقية»، الوزن رقمين عشريين بس في كل الأبلكيشن، وكلمة «مشغولات» هتتشال خالص والشغل كله بالأصناف. وكمان الدفتر هيفتح على طول من غير شاشة إدخال الأرصدة.
> بعد كده هنمشي زي ما حضرتك قلت صفحة صفحة: قبل كل صفحة هبعتلك ورقة فيها شكل الصفحة القديمة والشكل المقترح والكلام المكتوب عليها، ونتفق عليها في مكالمة، وبعدين تتنفذ. نبدأ بالجرد الفوري، وبعده الحسابات، وبعده المرمات والنوتة.
> محتاج من حضرتك في مكالمة الجرد: التحييف لكل عيار بأرقام من عندك، ومكان الكسر في الصفحة.

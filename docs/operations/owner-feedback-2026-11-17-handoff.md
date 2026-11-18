# Owner feedback of 2026-11-17: handoff for the next session

Written 2026-11-18. Read this first, then the three documents it points to. It replaces nothing; it says where the work stands and what to do next.

- Plan: [owner-feedback-2026-11-17-plan.md](owner-feedback-2026-11-17-plan.md). The 24 feedback items, the findings behind them, the milestones, and the traceability table.
- What was done and how it was checked: [owner-feedback-2026-11-17-validation.md](owner-feedback-2026-11-17-validation.md).
- Decision record for the removed opening form: [ADR 0049](../adr/0049-ledger-opens-without-opening-form.md).
- What the owner's pages should resemble: [old app reference](../reference/old-app-2026-11-10/README.md), with screenshots.
- Project rules: `AGENTS.md` at the repository root.

## 1. The situation

The shop owner sent six voice notes on 2026-11-17. He could not use the app, he has repeated some corrections up to four times, and he says the app speaks in terms no gold trader uses. He asked to agree each page before it is built.

Three rules for all work on this feedback:

1. **Build only what he asked for.** When a change needs something he did not ask for, stop and put it to him as a question. On 2026-11-18 a cash-entry button was nearly built on an inference; the developer stopped it. Label inferences as inferences.
2. **Use his words.** Check every label against the old app reference and the requirement documents at the repository root. Never show a data-model term.
3. **One page per delivery after the first build**, each agreed with him first (plan, section 5).

Read the voice notes yourself when they matter; do not rely on the summary alone. The summary read a 24-hour-clock complaint as a time-zone offset.

## 2. Where the work stands

The work below is committed as `cb318d8` on the local branch `owner-feedback-2026-11-17`, on top of `51ab2d9` from `main`. It is not pushed and not merged into `main`. Nothing was deployed: no migration and no Edge Function changed. No release build exists, so the owner's phone still has the broken version.

| Item | State | Evidence |
| --- | --- | --- |
| **FB-005** ledger blocked after confirming opening balances | Done | Cause confirmed on development. Fixed in `opening_flow.dart`. Emulator: a new shop confirmed zero balances and reached the ledger. |
| **FB-001** clock | Done, app and admin | 12-hour with ص/م, no seconds, no zone name. One formatter: `app/lib/src/theme/shop_clock.dart` and `shop_instant.dart`; admin `subscriptionFormat.ts`. Seen on the emulator in «الدفاتر» and «سجل العمليات». |
| **FB-006** opening-balances screen | Done | Form removed. A new shop opens on the ledger; the owner's app confirms a zero opening by itself. Emulator: a second new shop opened directly. |
| **FB-002** two-decimal weights | Done on 2026-11-18 (second session), committed on the branch, not pushed | [ADR 0050](../adr/0050-two-decimal-weights.md). One formatter and one input; `AGENTS.md`, ADR 0004 and ADR 0047 D7 amended. See the validation record for tests and the emulator check. |
| **FB-003** «مشغولات» | Done on 2026-11-18 (second session) | The word is shown nowhere. Rows with no item name read «عيار 21»; lists and headings say «أصناف». See the validation record, «M1, part 4». |
| Banned-terms test and glossary | Not started | |
| M2 names and «المزيد» | Not started | |
| M3 onward, page by page | Not started | Needs the owner's sign-off per page |

Gates at the end of the session: `dart analyze` clean, `flutter test` 1938 passed, admin `vitest` 245 passed, `tsc -b` and lint clean, `git diff --check` clean. `supabase/tests/opening_home_feed.sql` passed on development in a rolled-back run; it has not run on a local database.

Decisions the developer approved on 2026-11-18:

1. Weights: keep integer milligrams in storage, enter and display two decimals everywhere, and amend `AGENTS.md`, ADR 0004 and ADR 0047 D7 to match. Done on 2026-11-18 (second session): `AGENTS.md` now states the two-decimal rule.
2. Opening balances: remove the form. Done.
3. Access to development `xchapwvmvoefriqcxtvn` through the Supabase connector. Working.

## 3. Open questions for the owner

Do not build any of these before he answers. Collect them for one message or the first page call.

1. **Starting cash and gold.** The setup screen is gone, as he asked. Where does he want to enter the cash and gold a shop already has? Gold can be added from «الجرد الفوري» with «إضافة مخزون». Cash has no simple entry. The old app used «اضافة او تعديل نقدية» and «اضافة او تعديل وزنة» on «جرد فوري»; `post_ledger_correction_v1` could carry a cash entry without a migration. Suggested wording: «بعد ما شيلنا شاشة الأرصدة، تحب تدخل النقدية والذهب اللي معاك في المحل منين؟»
2. **التحييفات (FB-021).** The factor for each karat to 21, with numbers of his own, and what each total includes. He asked on what basis «عيار 21» includes bullion.
3. **«الكسر» in «الجرد الفوري» (FB-023).** Its own card per karat, or off the page.
4. **«التقارير» and «التحليلات» (FB-020, FB-024).** Proposal: move reports inside «الدفاتر» and keep «التحليلات» for charts.
5. **Repairs archive (FB-019).** Replace archive with delete and a confirmation, as in the old app.
6. **Which page first** in the page-by-page review. Proposal: «الجرد الفوري».
7. **«أصناف» and two figure labels.** With «مشغولات» gone, lists and headings that need a word say «أصناف», and the inventory figures read «وزن الأصناف» and «اجمالي الوزنة 21». The developer chose these on 2026-11-18. Ask him whether they are his words.

He has not seen two engineering choices that follow from his request: the automatic zero opening, and the wording «لم يفتح صاحب المحل الدفتر بعد.» for staff. Show them with the first build.

A draft reply to him is in the plan, section 8. It was not sent. It mentions entering balances from «الجرد الفوري»; turn that into question 1 before sending.

## 4. What to do next, in order

### Step 0. Start from the committed branch

The three finished changes (the FB-005 fix, the clock, and the opening-form removal with ADR 0049) are in one commit on `owner-feedback-2026-11-17`. Check `git status` and `git log --oneline -3` first. Ask the developer whether to keep working on that branch or merge it into `main` first; do not push or merge without his word. Per `AGENTS.md`, review the diff and rerun the gates before each new commit.

### Step 1. Two-decimal weights (FB-002)

Done on 2026-11-18 in the second session; see the validation record, «M1, part 3». The notes below are kept as the record of what was asked. Open for the developer: confirm the display rule for weights stored earlier with a third decimal (ADR 0050, decision 5).

- Amend the rule first: `AGENTS.md` («Preserve gram precision to three decimal places»), ADR 0004, ADR 0047 D7. Storage stays integer milligrams; no migration.
- One formatter and one input for grams. Start from `app/lib/src/theme/amount_format.dart` (`displayGrams` already rounds to two decimals; `displayGoldEffect` appends milligrams, which must go).
- Separate gram formatters to fold in: `customerGrams`, `signedGramsText`, `debtGold`, `statementGold`, `gramsOf` (inventory), `_gramsOf` (invoice), `repairGramsExact`, `repairWeight`, `reportGrams` (uses three), and the private `_grams` helpers in `confirmed_operation_pdf.dart`, `financial_operation_screen.dart`, `ledger_correction_screen.dart`, `linked_return_screen.dart`, `partial_return_screen.dart`, `scrap_to_stock_screen.dart`. Find the rest with a search for `exact: true` and `toStringAsFixed(3)`.
- Inputs: remove every three-decimal hint (repairs has «ثلاث خانات، مثل 1.255»). Entry accepts at most two decimals.
- Before shipping, count stored weights on development whose third decimal is not zero and decide with the developer how they display.
- The invoice in `docs/reviews` shows «10.000 جم»; the invoice PDF is in scope.

### Step 2. «مشغولات» (FB-003)

Done on 2026-11-18 in the second session; see the validation record, «M1, part 4». The notes below are kept as the record of what was asked.

The word is the display label of stock category `worked_jewelry`. Sites: `invoice_appearance_screen.dart:640`, `branded_invoice_document.dart:234`, `financial_week_report.dart:54`, `debt_copy.dart:38`, `inventory_copy.dart:9`, `daily_ledger_codec.dart:11`, `financial_operation_screen.dart`, `exchange_effect_review.dart`, `ledger_balance_sections.dart`, `ledger_trade_change_screen.dart`, `opening_copy.dart`, `financial_trade_screen.dart` (an error message), and two figure labels: «وزن المشغولات» in `inventory_item_grid_view.dart` and «اجمالي الوزنة 21 (مشغولات + سبائك)» in `inventory_item_grid.dart`. Line numbers moved; search for the word.

The category name is never shown; jewelry appears by item name. Where a row has no item name (old pooled opening lots), decide the wording with the developer; do not invent a new category word. The two figure labels need the owner's wording: ask.

### Step 3. Guard

A glossary of the owner's terms under `docs/`, and a test that fails when a banned term appears in `app/lib` or `admin/src`. Banned so far: مشغولات، حيازة، أمانة (as custody), بانتظار الاعتراف، متاح للبيع، دفعات، عملة (for coins; he says جنيهات), العطل، وصف القطعة، الديون as a page name, كشف أمانة، فئة سبيكة اسمية، «منازل» hints, «توقيت», «UTC». Add each term only once its replacement is in place, or the test fails on day one.

### Step 4. M2: names and «المزيد»

Text and navigation only; see the plan. «الحسابات» for «التجار والأمانات» (3 places), «النوتة» for «الديون» (19 places), repairs labels «اسم الصنف» and «متطلبات التصليح», no «الحيازة» wording in repairs, and remove «باقي أرقام الدفتر» and the inventory figures from «المزيد» (`ledger_more_balances.dart`, `shop_workspace.dart` `_morePages`).

FB-004 «إضافة صف»: the string is not in the source. The owner saw it after pressing «إضافة صنف» on the opening form, which is now removed. Look for it on the emulator in the inventory add flows before closing the item.

### Step 5. First build for the owner

Steps 1 to 4 plus what is already done. A release build is opt-in under `AGENTS.md`; ask the developer. Send the open questions with it.

### Step 6. Page by page

Plan sections 4 (M3 to M8) and 5. Each page: an Arabic sheet (old screen, current screen, proposal, exact words, what is removed), worked numbers in his figures, his agreement recorded in an ADR, then the build, device proof, and his acceptance.

## 5. Working environment

- **Tests.** From `app/`: `dart format`, `dart analyze`, `flutter test`. `flutter analyze` crashes inside the tool on this machine; use `dart analyze`. From `admin/`: `npx vitest run`, `npx tsc -b`, `npm run lint`. Run the admin suite when the machine is idle; it times out in unrelated panels while a Gradle build is running.
- **A full test run rewrites tracked files.** It regenerates `docs/reviews/invoice-branding-2026-10-21/pdf/*.png` (they differ now because the invoice time changed) and touches `app/windows/flutter/generated_*`. Restore both with `git checkout --` after each run. `invoice_branding_pdf_capture_test.dart` failed once in a full run and passed alone and in the next run.
- **Emulator.** `emulator-5554`, 1080x2400. `adb` is not on the path; it is under the Android SDK at `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`. Debug build and launch, from `app/`: `flutter run -d emulator-5554 --no-resident --dart-define-from-file=config/local.json`. The first build takes several minutes; run it in the background.
- **Driving the emulator.** Helper scripts are in the git-ignored `tmp/owner-feedback-1117/`: `dev.sh` (`shot`, `tap`, `text`, `key`, `swipe`, `ui`) and `signup.sh` (signs out and registers a new shop through the app). `dev.sh ui` prints the Arabic text on screen with its bounds, which is cheaper and more exact than a screenshot. `adb input text` is ASCII only. Close the keyboard (`key 4`) after each field or the next tap lands on the wrong field.
- **Test shops on development.** Two were created on 2026-11-18 through the app's sign-up and activated with one row each in `shop_entitlements` (30 days). Credentials are in the git-ignored `app/config/.env.test-shop`. Both are opened and empty. The emulator is signed in to the second one. The older test shop «ahmed» has real test history; the developer has its login. A test of the direct-open behaviour needs a shop that has never been opened: register another with `signup.sh` and insert its entitlement row. Creating a test shop was approved for the opening-flow test; ask before creating more for other purposes.
- **Development database.** Supabase project `xchapwvmvoefriqcxtvn`, through the connector that lists that project (pass `project_id`). A second Supabase connector in the session points at an unrelated project. To run a hosted check without leaving data, use one `do $$ … $$` block that ends with `raise exception 'RESULT %', …`: the result arrives in the error text and everything rolls back. To read as a user, set `request.jwt.claims` and `request.jwt.claim.sub` with `set_config(…, true)` inside that block.
- **Server compatibility.** Installed older builds must keep working ([ADR 0044](../adr/0044-owner-answers-2026-11-10.md) C-D1): reads they call keep their shape, and new fields go to new reads. The current app reads the ledger with `get_daily_ledger_home_v2`, which names the opening row `opening_balances`; the legacy `get_daily_ledger` names it `opening_balances_confirmed`.
- **Editing files with Arabic or direction marks.** Shell here-documents with long Arabic text and quotes failed twice; write a script file and run it. A `\u2066` typed into a tool argument arrives as the real character, and the analyzer rejects direction marks in source: write the escape sequence.

## 6. Seen and not fixed

- **«إضافة مخزون» makes the daily ledger unreadable** (found 2026-11-18, second session). An `inventory_addition` row in the open day's feed has no label and the client parser throws. Details and the reproduction are in the validation record, «M1, part 3». Fixed the same day in the app: rows the server gives no ledger label are left out of the ledger. See the validation record, «Fix: stock operations no longer break the daily ledger». One launch after the fix still failed and was not reproduced; watch for it.
- The audit card's last line shows a date whose digits reorder in Arabic («11-11-2026» for 2026-11-11).
- The debt reminder screen still carries technical wording beyond the clock. It belongs to the «النوتة» page milestone.
- `InvoiceCopyPanel` has no entry point in the app (ADR 0041 D5) but was kept in step with the clock rule.
- Not checked on a device after the clock change: reports, analytics, debts, support, and the printed report and statement PDFs. The admin dashboard was not opened in a browser; no platform-admin test account is available.

## 7. Prompt for the new session

> Continue the owner feedback of 2026-11-17 for ElDafttar ERP. Read `docs/operations/owner-feedback-2026-11-17-handoff.md` first and follow it, then the plan and validation record it links.
>
> Rules: build only what the owner asked for and stop to ask when something he did not ask for is needed; use his wording, checked against `docs/reference/old-app-2026-11-10/`; follow `AGENTS.md`.
>
> Start with step 0 (confirm the branch and commit you are on and tell me if anything is uncommitted), then step 1, two-decimal weights, including the `AGENTS.md` amendment I approved. Test on the Android emulator as described in section 5. Record each step in the validation record. Do not start the page-by-page work in step 6 until I bring the owner's answers to the open questions in section 3.

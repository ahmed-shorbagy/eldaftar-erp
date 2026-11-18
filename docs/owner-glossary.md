# Owner glossary: the terms he rejected and the words he uses

Written 2026-11-18 for the owner feedback of 2026-11-17 ([plan](operations/owner-feedback-2026-11-17-plan.md), [handoff](operations/owner-feedback-2026-11-17-handoff.md) step 3). The shop owner said the app speaks in terms no gold trader uses. This file lists each term he rejected, where the app still shows it, his word for it, where that word comes from, and whether the change is done.

Rules for every screen, PDF and message, in the app and in the admin dashboard:

1. Use the owner's word. If this file has no word of his for something, ask him; do not invent one.
2. Never show a term from the data model.
3. A term goes into the guard only when it is gone from the screens. Until then its row here says what it waits on.

The guard is `app/test/owner_terms_guard_test.dart`. It scans `app/lib` and `admin/src` and fails, naming the file and line, when a banned term appears. It also holds the waiting terms: when the last line showing one is removed, the test fails until the term is moved to the banned list, so a finished rename cannot be left unguarded.

Sources used here: the [old app reference](reference/old-app-2026-11-10/README.md) with its screenshots, the owner's requirement documents at the repository root («متطلبات الابليكشن و كل صفحة», «صفحة الدفتر اليومي», «الاساسيات المطلوبة للدفتر»; not committed), the ADRs that record his answers, and the developer's dated decisions. Items marked FB-nnn are the feedback of 2026-11-17 as the plan and the handoff record it. The voice notes and the 24-item summary are not in the repository, so no row quotes them directly.

Line counts were taken on 2026-11-18 at commit `ae8c6ec`. Line numbers move; search for the word.

## 1. Rejected terms

One table, ordered by state:

- **Replaced**: gone from the screens and banned by the guard.
- **Waiting on step 4**: his word is known. The rename is assigned to handoff step 4 and was not done in step 3.
- **Waiting** on a page review or on the owner: still shown, and his word for it is not recorded or the screen that shows it is to be redesigned with him. Each is agreed on that page's sheet (plan, section 5).

The counts include five lines of guide text in `inventory/presentation/inventory_copy.dart` (`inventoryGuideSteps`, `traderGuideSteps`) that no screen has used since the guides were removed on 2026-10-05. They hold «الحيازة», «الأمانة», «بانتظار الاعتراف» and «المتاح للبيع», and the guard reads them like any other line.

| Rejected term | Where the app shows it today | The owner's word | Source | State |
| --- | --- | --- | --- | --- |
| «مشغولات» | Nowhere. One wire constant stays in `daily_ledger/data/daily_ledger_codec.dart`: the server sends it as the label of jewelry stock rows and older builds expect it. The parser checks the read against it and no screen prints it. | The item's name. A row with a karat and no item name reads «عيار 21». Headings and lists say «أصناف» (see 1.1). | FB-003; validation record, «M1, part 4»; developer's decisions of 2026-11-18 | **Replaced.** Banned as the stem «مشغول», with that one line allowed. |
| «الصيانة» | Nowhere. | «المرمات»; one is «مرمة». | [ADR 0044](adr/0044-owner-answers-2026-11-10.md) C-D7; old app side menu «المرمات» | **Replaced.** Banned as «صيانة». |
| «ملليجرام» and any milligram figure | Nowhere. | Grams with two decimals: «1.83 جرام». | FB-002; [ADR 0050](adr/0050-two-decimal-weights.md); `AGENTS.md` | **Replaced.** Banned in its spellings (ملليجرام، مليجرام، ميليجرام، ملجم). |
| Decimal-places hints: «منازل», «منزلتين», «ثلاث خانات», «ثلاثة أرقام عشرية» | Nowhere. | No hint. The field takes two decimals and says nothing about it. | FB-002; ADR 0050; `AGENTS.md` | **Replaced.** Banned: «منازل», «منزلة», «منزلتين», «ثلاث خانات», and the word «عشري» in any form. «عشرين» (twenty) and «خانات» alone (the ledger's six summary tiles) are left alone. |
| A third decimal printed by code: `toStringAsFixed(3)`, `decimalPlaces: 3`, a three-digit pad before «جرام» | Nowhere. | `displayGrams` and the other formatters in `app/lib/src/theme/amount_format.dart`. | ADR 0050 | **Replaced.** Banned in `app/lib`. |
| A zone name beside a time: «توقيت الخادم», «توقيت المتجر», «التوقيت العالمي», «الوقت العالمي», «توقيت شرق أوروبا» | Nowhere. One admin test line asserts that «التوقيت العالمي» is absent; that line is allowed. | The ordinary clock: twelve hours with ص/م, no seconds, no zone. | FB-001; plan 2.2; validation record, «M1, part 1» | **Replaced.** Banned as those phrases, and as the formatter options that print them: `timeZoneName`, `hourCycle`, `hour12: false`. |
| «UTC» | Nowhere on a screen. It stays in code as a zone id (`'UTC'`, `tz.UTC`) and in comments. | Nothing; the time alone. | FB-001; validation record, «M1, part 1» | **Replaced.** Banned where «UTC» or «GMT» is on a line of Arabic text that is not a comment. Limit: a label built with no Arabic on its line is not caught; `shop_clock_test.dart` and the admin `subscriptionFormat.test.ts` check the formatters' output. |
| «التجار والأمانات» (page name) | 3 lines: the «المزيد» link (`shell/shop_workspace.dart`), the page title (`inventory/presentation/trader_screen.dart`), the action group on «الجرد الفوري» (`inventory_screen.dart`) | «الحسابات» | Old app: side menu «حسابات», page «الحسابات»; requirements: «صفحة الحسابات (الابونيهات)»; handoff step 4 | **Waiting on step 4.** |
| «الديون» (page name) | 19 lines in 8 files: the page title and its back links (`debts/presentation/debt_screen.dart`), the «المزيد» link, «مواعيد الديون», the reminder channel name (`debt_notification_port.dart`), ledger banners («افتح الديون من المزيد للتحقق منه.»), account-gate messages («افتح الديون لمراجعة المستحقات.») | «النوتة» | Old app side menu and page «النوتة»; requirements: «صفحة النوتة»; handoff step 4 | **Waiting on step 4.** The rejected sense is the name with the article, «الديون». «دين» and «ديون» as plain nouns («كشف حساب دين», «لا توجد ديون في هذا العرض.») are not matched; whether he says «حساب» there, as the old page does («اضافة حساب»), is a question for the «النوتة» page review. |
| «العطل» | 4 lines in `repairs/presentation/repair_screen.dart`: the field label, the search hint, the review line and the card line | «متطلبات التصليح» | Old app repair card; plan M2; handoff step 4 | **Waiting on step 4.** Matched as the word «العطل»; «معطلة» is not it. |
| «وصف القطعة» | 1 line: the first field of «استلام قطعة» in `repair_screen.dart` | «اسم الصنف» | Plan M2; handoff step 4. The old app's card calls this field «المنتج»; step 4 should check which of the two he said. | **Waiting on step 4.** |
| «الحيازة» in repairs | 5 lines in `repair_screen.dart`: «تبقى القطعة في الحيازة. لا يتغير المخزون القابل للبيع ولا النقد.», «تزيد الحيازة بهذا الوزن مرة واحدة.», «الحيازة قائمة» / «الحيازة مُحررة», «تحرير الحيازة: …», and the cancel text | No word; these lines go. The old page says «ملحوظة: العمليات التي تتم بالصفحة ليس لها علاقة بجرد المحل». | Plan M2 («no «الحيازة» wording»); handoff step 4; old app repair page | **Waiting on step 4.** |
| «باقي أرقام الدفتر» | 1 line: a heading inside «المزيد» (`daily_ledger/presentation/ledger_more_balances.dart`), under «الأرقام والمخزون» | Nothing; «المزيد» lists pages and settings only. | Plan M2; handoff step 4 | **Waiting on step 4.** |
| «حيازة» outside repairs | 5 lines: the filter chip «الحيازة» on «الجرد الفوري», «ما زال في الحيازة» on the trader screen and its PDF, and two lines of guide text in `inventory_copy.dart` that no screen uses since the guides were removed | Not recorded. | Plan, section 1, point 3; plan M3 (custody classes leave the page) | Waiting on the «الجرد الفوري» and «الحسابات» page reviews. |
| «أمانة» (as custody) | 33 lines in 9 files. Inventory: «أمانة تاجر», «أمانة التجار الحالية», «نقل ملكية الأمانة», «إيصال الأمانة», «ملك تاجر — أمانة». Traders: «استلام أمانة», the PDF footer. Debts: review lines such as «الأثر على النقد والذهب والمخزون والأمانة والفواتير: صفر» and «الأمانة: …». | Not recorded. The requirements speak of «وزنة التجار (الأبونيهات)» and «حساب التاجر». | Plan, section 1, point 3; requirements, «صفحة الجرد الفوري» and «صفحة الحسابات» | Waiting on the «الجرد الفوري», «الحسابات» and «النوتة» page reviews. Matched as the words «أمانة» and «أمانات» with any attached particle («والأمانة»). «بأمان» (safely, in the linked return screen) is not matched. |
| «كشف أمانة», «كشف أمانة محاسبي» | 4 lines: the button on the trader screen, the title of its PDF, and two status messages («أُعد كشف الأمانة من الأرقام المؤكدة.») | Not recorded. The requirement is «إمكانية طبع كل تاجر pdf». | Plan, section 1, point 3 | Waiting on the «الحسابات» page review. |
| «بانتظار الاعتراف» and «اعتراف» | 14 lines in 4 files: «مملوك بانتظار الاعتراف», «اعتراف بكمية معلقة», «اعتراف جزئي أو كامل», «سبب الاعتراف» on the inventory page and forms; «اعتراف بالمخزون» in a trader's activity | Not recorded. For a trader's weight the requirements give «لم تتم إضافتها للمخزون», «تمت إضافتها للمخزون» and «تمت إضافتها يدويًا». That these replace «بانتظار الاعتراف» is an inference, not his statement. | Plan, section 1, point 3; requirements, «صفحة الحسابات» | Waiting on the «الجرد الفوري» and «الحسابات» page reviews. |
| «متاح للبيع» | 7 lines in 3 files: the stock class label, the figure «المتاح للبيع», «فوري إلى المتاح للبيع», and the review line of «إضافة مخزون»: «يزيد المتاح للبيع: 5.25 جرام عيار 21.» | Not recorded. | Handoff step 3 | Waiting on the «الجرد الفوري» page review. He will meet the review line first: «إضافة مخزون» is today the only way to enter the gold a shop starts with (handoff, question 1). |
| «دفعات» | 15 lines in 3 files, all on the inventory page and forms: «الدفعات», «بحث في الدفعات», «تصفية الدفعات», «المزيد من الدفعات», «بيع دفعة محددة», «حركة الدفعة» | Nothing; the lot list leaves the page. He read «تصفية الدفعات» as settling payments (FB-010). | Plan 2.3, FB-010; plan M3 | Waiting on the «الجرد الفوري» page review. Matched as the words «دفعة» and «دفعات»; «الدفع», «طرق الدفع» and «مدفوع» are not matched. |
| «عملة», «عملات» (for coins) | 12 lines in 6 files. (a) Six plain labels: the category name in debts (`debt_copy.dart`), inventory (`inventory_copy.dart`), the invoice (`branded_invoice_document.dart`), the weekly report («عملات ذهبية», `financial_week_report.dart`), and two list nouns (`inventory_forms.dart`, `inventory_screen.dart`). (b) Six lines of the coin catalog: «نوع العملة», «نوع عملة», «هوية العملة 3», «— عملة 3». | «جنيهات» | Old app: the table row and the type list «جنيهات، سبائك، كسر»; requirements: «قسم الجنيهات», «صنف سبائك او جنيهات»; ADR 0044 C-D2 and C-D8 («مخزون الجنيهات»); handoff step 3. The daily ledger already says «جنيهات». | (a) Waiting on the developer: six word swaps to «جنيهات», listed for his permission on 2026-11-18. (b) Waiting on the «الجرد الفوري» page review: «نوع العملة» has no plain swap, and the requirements call these «أصناف الجنيهات» (ربع جنيه، نصف جنيه، جنيه). |
| «فئة سبيكة اسمية» and «اسمي» | 21 lines in 4 files: «فئة السبيكة الاسمية», «الوزن الاسمي بالجرام», «بدون وزن اسمي», «بدون هوية اسمية», «الأوزان الاسمية» in the purchase sheet, and «— اسمي 10.00» in stock rows | Not recorded. The requirements say «تخصيص قسم للسبائك مع الأوزان وعدد كل وزن» and list «أصناف السبائك» by weight (0.25 جرام … 100 جرام). | Handoff step 3; requirements, «صفحة الجرد الفوري»; «صفحة الدفتر اليومي» | Waiting on the «الجرد الفوري» page review. A ban on «اسمي» would also catch «اسمي» meaning “my name”; no screen says that today. |
| «توقيت» | 3 lines. Two reminder messages on the debts page (`debts/presentation/debt_native_screen.dart`): «الوقت غير موجود أو ملتبس بسبب التوقيت الصيفي. اختر وقتًا آخر.» and «تغير الرصيد أو الموعد أو توقيت المحل. أعد القراءة والمراجعة.». One admin hint under a broadcast's start time (`admin/src/broadcasts/copy.ts`): «بتوقيت جهازك، خلال 90 يومًا.» | Not recorded for these. What he rejected is the zone name printed beside a time, and that is replaced (the row «توقيت الخادم» above). He writes «التوقيت» himself for the time of day («التوقيت الساعه كام»). | FB-001; handoff step 3; requirements, «صفحة الدفتر اليومي» | Waiting. The reminder messages go with the «النوتة» page review (handoff, section 6). The admin hint waits on the developer. A ban on the bare word would forbid his own use of it, so only the zone labels are banned. |
| «مؤرشفة», «أرشفة المرمة» (repairs) | 10 lines in `repairs/presentation/repair_copy.dart` and `repair_screen.dart`: the stage «أرشفة المرمة», the button «أرشفة السجل», the filter «المؤرشفة» | Proposed, not confirmed: «مسح» with a confirmation, as in the old app. The requirement is «إظهار Dialog عند الاستلام أو المسح». | FB-019; handoff, question 5 | Waiting on the owner. Not in the guard: customers, debts and payment methods also archive, so the word cannot be banned; only a rule limited to the repairs folder could. |
| «إضافة صف» (FB-004) | Not in the source. He saw it after pressing «إضافة صنف» on the opening form, which is removed. | Not established. | Plan 2.3; handoff step 4 | Open. Step 4 looks for it on the emulator. Not in the guard, because what he rejected there is not established. |

### 1.1 Chosen for him and not yet confirmed

These words replaced a rejected term. They are the developer's choices of 2026-11-18, not the owner's words (handoff, question 7, and question 4).

| Word shown | Where | Chosen by | To confirm |
| --- | --- | --- | --- |
| «أصناف» | Headings and choice lists where «مشغولات» stood: the «الفئة» list, the inventory filter, the sold and bought weight sheets, the ledger stock groups, the weekly report | Developer, 2026-11-18, after «الأصناف حسب العيار» on the inventory page | His word for jewelry as a group. |
| «وزن الأصناف», «اجمالي الوزنة 21» | Two figures on «الجرد الفوري» | Developer, 2026-11-18; the second is the old app's label | His wording for both. |
| «عيار 21» for a row with no item name | Stock effect lines, the unnamed day count, trader totals | Developer, 2026-11-18; the old app's «عيار 18» and «عيار 21» figures mean jewelry | That a bare karat reads as jewelry to him. |
| «التقارير» as its own tab beside «التحليلات» | Bottom bar and «المزيد» | Earlier design | Proposal: reports move inside «الدفاتر» and «التحليلات» keeps the charts (FB-020, FB-024). |
| «لم يفتح صاحب المحل الدفتر بعد.» | Staff, before the owner has opened the shop | [ADR 0049](adr/0049-ledger-opens-without-opening-form.md) | Shown to him with the first build. |

## 2. The open rows as questions for the owner

Drafts by the assistant, for the developer to edit and send. Nothing was sent. Each stands for a row above; the page-review rows are better asked on that page's sheet than one by one.

1. «أصناف» and the two figures: «بعد ما شيلنا كلمة "مشغولات"، العناوين بقى مكتوب فيها "أصناف"، وفي الجرد "وزن الأصناف" و"اجمالي الوزنة 21". دي الكلمات اللي تحبها ولا ليها اسم تاني عندك؟»
2. «أمانة» and «كشف أمانة»: «البضاعة اللي في المحل وهي بتاعة تاجر، بتسميها إيه؟ والورقة اللي بتتطبع بحساب التاجر تحب يتكتب فوقها إيه؟»
3. «بانتظار الاعتراف»: «وزنة التاجر اللي اتسجلت ولسه ما دخلتش المخزون: نكتب عليها "لم تتم إضافتها للمخزون" و"تمت إضافتها للمخزون" زي ما في المتطلبات؟»
4. «متاح للبيع»: «لما تضيف وزنة للمخزون، المراجعة بتقول "يزيد المتاح للبيع". تحب تتكتب إزاي؟»
5. «فئة سبيكة اسمية»: «وزن السبيكة المكتوب عليها (5 جرام، 10 جرام…) بتسميه إيه؟ "أصناف السبائك" زي ما في المتطلبات؟»
6. Repairs archive (handoff, question 5): «في المرمات، نشيل "أرشفة" ونخليها "مسح" برسالة تأكيد زي الأبلكيشن القديم؟»
7. «دين» inside «النوتة»: «جوه النوتة، نقول "حساب" زي القديم ("اضافة حساب") بدل كلمة "دين"؟»

The handoff's own open questions (starting cash and gold, التحييفات, «الكسر», reports against analytics, which page first) stay in its section 3.

## 3. Proposed rows: the assistant's findings, not the owner's

Found on 2026-11-18 by reading every Arabic string in `app/lib` and comparing names with the old app and the requirements. The owner has not rejected any of these. Nothing here is banned or changed. Each needs the developer's word, and most need the owner's, before it moves to section 1.

### 3.1 A word of his exists and the app says something else

| The app says | Lines in `app/lib` | Example | His documents and old app say | Note |
| --- | --- | --- | --- | --- |
| «النقد» | 71 in 32 files | «تعذر… لا يتغير النقد أو الذهب», «وسيلة النقد», «أرصدة النقد والمخزون» | «النقدية»: «اجمالي النقدية» (old app), «النقدية المتاحة», «نقدية الانستا» (requirements) | The app also says «النقدية» in 20 lines. |
| «المتجر» | 53 in 26 files (and 30 lines of the admin) | «بيانات المتجر», «صاحب المتجر», «إعدادات المتجر», «انتهت صلاحية الجلسة. أعد الدخول للمتجر.» | «المحل»: «اسم المحل», «صاحب المحل», «جرد المحل» | The app mixes both: «لوجو المحل» beside «بيانات المتجر». |
| «المصروفات», «مصروف» | 19 in 11 files | The ledger tile «المصروفات», the quick action «مصروف», «وصف المصروف» | «المصاريف اليومية» (old app button), «إضافة مصاريف» (requirements). The requirements say «إضافة المصروفات» once, in the staff permissions. | |
| «وسيلة الدفع», «وسائل الدفع», «وسيلة النقد», «وسيلة القبض» | 37 in 17 files | The «المزيد» link «وسائل الدفع», the sale field «وسيلة الدفع» | «طريقة الدفع» (old sale form), «إضافة طريقة دفع اخري» (requirements) | The app says «طريقة الدفع» / «طرق الدفع» in 8 lines. |
| «استلام قطعة» | 1 | The button that adds a repair | «اضافة مرمة» (old app) | |
| «جرام محيف عيار 21», «عرض الذهب بمحيف عيار» | 2 | The ledger's gold tiles | «وزن متحيفة», «التحييفات» (requirements) | The form of the word differs: «محيف» against «متحيفة». |
| «يوم العمل» | 37 in 16 files | «يوم العمل 18 نوفمبر 2026», «يوم العمل مغلق. افتح اليوم قبل إضافة عملية.» | «اليومية»: «تقفيل اليومية», «إغلاق اليومية», «فتح دفتر جديد» | |
| «الطرف», «اسم الطرف» | 10 in 5 files | The debt form field «الطرف», the statement PDF line | «اسم العميل» (old repair card), «اضافة حساب» (old «النوتة»), «عميل او محل» (requirements) | |
| «الفئة», «فئة», «فئات سبائك» | 20 in 7 files | The «الفئة» list in the inventory forms, «تحويل فئة بنفس العيار», «الفئة: كسر» | «اختيار النوع» (old weight form); «الصنف» everywhere else | |

### 3.2 Words from the data model or from software, with no word of his recorded

| The app says | Lines in `app/lib` | Example | Note |
| --- | --- | --- | --- |
| «الخادم» | 50 in 25 files (and 5 in the admin) | «بانتظار تأكيد الخادم», «رفض الخادم الطلب», «لم يصل رد الخادم» | His requirement: a clear message that the operation succeeded or failed and why, «خصوصًا ضعف الإنترنت». |
| «المفتاح» (the retry key) | 5 | «لم يؤكد الخادم المرتجع. أعد المحاولة بالمفتاح نفسه.», «يحتفظ بالمفتاح والموعد الأصليين.» | Not «مفتاح الدولة», the dial code. |
| «الجلسة» | 25 in 20 files | «انتهت الجلسة. سجّل الدخول مرة أخرى.» | |
| «للقراءة فقط», «قراءة فقط» | 23 in 18 files | «الاشتراك منتهٍ. العرض للقراءة فقط.», «منتهي - للقراءة فقط» | The state of an expired subscription. |
| «المستحق», «مستحقات الذهب», «التزام الذهب» | 45 and 14 | «سداد مستحق شراء», «وزن الذهب المستحق بالجرام», «عيار الالتزام» | Money or gold the shop still owes for a purchase or to a trader. Belongs with «الحسابات» and «النوتة». |
| «مملوك», «ملكية», «نقل الملكية» | 27 in 11 files | «نقل ملكية الأمانة», «العملية تجعل رصيداً مملوكاً سالباً.» | Same model as «أمانة» and «بانتظار الاعتراف». |
| «الكتالوج», «هوية» | 13 and 7 | «بحث في هوية الكتالوج», «منتج في الكتالوج», «هوية السبيكة 12», «هوية الدين» | Internal identifiers on a screen and in the debt statement PDF. The plan removes the catalog block in M3. |
| «أمر مخزون», «أوامر» | 2 | «أكملها من الدفتر قبل أي أمر مخزون.», «هذا النموذج للقراءة ولا يرسل أوامر.» | |
| «اللقطة», «لقطة محاسبية» | 9 in 6 files | «وقت اللقطة» in reports and the statement PDF | |
| «مساهمة» | 10 in 3 files | «مساهمة صافي المبيعات», «مساهمة المباع بالجرام» in reports | |
| «تسلسل», «مرجع», «رقم عملية المصدر» | 13 | «تسلسل العملية» in «سجل العمليات», «مرجع العملية الأصلية» | |
| «الأثر», «بلا قيد», «القيد الأصلي» | 11 | «الأثر على النقد والذهب والمخزون والأمانة والفواتير: صفر», «سداد بلا قيد» | Accounting phrasing in the debts reviews. |
| «رصيد افتتاحي مجمّع», «رصيد سابق مجمّع» | 5 | Lot rows and the lot picker | The inventory grid already shows «رصيد افتتاحي (بدون صنف)». |
| «محرف», «محارف» | 10 in 3 files | «الحد الأقصى للنص ٤٠٠ محرف و٨ فواصل أسطر.» | The everyday word is «حرف». |
| «نسخة موسومة» | 14 in 1 file | `InvoiceCopyPanel` | The panel has no entry point in the app (handoff, section 6). |
| «لوجو» beside «الشعار» | 36 and 20 | «لوجو المحل», «تعذر حفظ الشعار.» | One thing, two words. Which he says is not recorded. |
| Technical wording of the debt reminders | — | «اكتملت مطابقة طلبات الجهاز مع النظام.», «ساعة الجهاز تختلف عن وقت الخادم.», «وقت غير موجود أو ملتبس بعد تغيير التاريخ أو المنطقة الزمنية.» | Already noted in the handoff, section 6; goes with the «النوتة» page. «وقت الخادم» and «المنطقة الزمنية» are why those two phrases are not in the clock ban. |

### 3.3 Page names against the old app

| Old app | The app today | State |
| --- | --- | --- |
| «الدفتر اليومي» | «الدفتر اليومي» (tab label «الدفتر») | Same. |
| «جرد فوري» | «الجرد الفوري» | The requirements say «الجرد الفوري». |
| «حسابات» / «الحسابات» | «التجار والأمانات» | Step 4 (section 1). |
| «المرمات» | «المرمات» | Done (ADR 0044). |
| «تحليلات» | «التحليلات», and a separate «التقارير» | Open (1.1). |
| «الدفاتر» | «الدفاتر» | Same. |
| «النوتة» | «الديون» | Step 4 (section 1). |
| «اضافة موظف» | «الموظفون والصلاحيات» | The requirements say «صفحة إضافة الموظفين والصلاحيات». |
| — | «بيانات العملاء», «سجل العمليات», «فريق عد التقفيل», «المساعدة», «تواصل مع الدعم» | New pages from the requirements. «فريق عد التقفيل» is our name; he describes it as «يبعتها لموظف للتمام علي عدد الأصناف و تمام النقدية». |

## 4. Adding a term

1. Add or update its row here, with the source of his word.
2. If it is still on a screen, add it to `_waiting` in the guard with what it waits on.
3. When its last line is gone, the guard fails and names it. Move it to `_banned` with a one-line reason, and mark the row Replaced.
4. A line that must keep a banned term (a value the server contract requires) goes in `_allowed` with the file and the whole line. Never allow a whole file.
5. If a word is rejected in one sense only, match that sense (see «أمانة», «الديون», «UTC») and say here how. If it cannot be matched precisely, leave it out of the guard and say so, as for the repairs archive.

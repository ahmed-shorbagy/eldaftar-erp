# Owner feedback 2026-11-06 (10 voice notes) — implementation plan

Status: planned, not started. Scope: Flutter app (`app/`) on Android, iOS and Windows. **No database migration, RPC or Edge Function change is needed** — every rule below fits the server contract that already exists (verified on 2026-11-08, see "Facts"). The React admin is not affected.

Builds on the uncommitted 2026-11-08 work ([plan](owner-feedback-2026-11-08-plan.md)). Do not start until that work is committed, because several files overlap.

Do the tasks **in the order given**: most of them edit `financial_trade_screen.dart`. Copy every Arabic string exactly. If the code does not match what a task says, stop and ask. Do not add anything not listed.s

---

## 0. Rules for the implementer

1. Read `AGENTS.md` and `docs/design-system.md` first. Theme tokens and `ColorScheme` roles only.
2. Do not commit or push.
3. After every task, from `app/`: `dart format lib test`, `dart analyze`, `flutter test`. All clean before the next task.
4. No release builds. No new guides/help cards.
5. Money and grams stay integer piastres / milligrams. Never `double`.

## 1. Open questions for the owner (ask now, in parallel with the work)

The tasks below already pick a default for each, so work does not wait. Only the answer changes a single constant or block.

| # | Question | Default in this plan | Where |
|---|---|---|---|
| Q1 | «رصيد مجمع» under «أخرى»: this text **does not exist** anywhere in the current app. Please send a screenshot. Is the phone running an old build? | Nothing to change; if a screenshot shows it, remove that element. | — |
| Q2 | "Seller name at the top of the invoice": both invoice PDFs already print the **shop name** (`shops.name`) at the top. Please send a screenshot of the invoice you sent. | Add a test that locks the header to the shop name (Task 4). Possibly the test shop was registered with a person's name. | Task 4 |
| Q3 | Purchased **coins and bars**: do they also go to scrap, or stay as coins/bars stock? (The voice note lists only jewelry and karats 18/21/22/14.) | Jewelry → scrap. Coins and bars stay coins/bars stock. | Task 1, `_purchaseToScrap` |
| Q4 | The old app's default «أخرى» item list. | Proposed list in Task 9; owner confirms or edits it before release. | Task 9, `_otherJewelry` |

### Recommended answers (implement these unless the owner says otherwise)

**Q1 — «رصيد مجمع»: treat as an old build, and make builds identifiable.**
The current code has no such field, so there is nothing to remove. The real problem is that feedback arrives from builds we cannot identify. Recommended edit (Task 9b below): show the app version at the bottom of «المزيد». Then every owner screenshot tells us which build it came from. Ask the owner to update to the latest build and re-check «أخرى»; if the field still appears, the screenshot plus the version pinpoints it.

**Q2 — Seller name on the invoice: keep the shop name; make the shop name easy to fix.**
Both invoice PDFs already print the registered shop name, and the send action exists only for sales (where the customer box is labelled «العميل», not «البائع»). The most likely cause is that the owner's test shop was registered with a person's name. Recommended edits:
1. Keep Task 4 as written: lock the header to the shop name with a test, and never print the seller (`actor_display_name`) anywhere on a customer document.
2. Ask the owner to check «المزيد ← بيانات المتجر ← اسم المتجر». If it shows a person's name, they correct it there; new invoice copies use the new name.
3. In the branded PDF, label the counterparty box «العميل» for **both** sale and purchase (`branded_invoice_pdf.dart`, `_customer()`: replace `document.kind == 'sale' ? 'العميل' : 'البائع'` with `'العميل'`). A shop's customer is always «العميل» to the owner, and the word «البائع» on a document reads as "the shop's seller", which is exactly the confusion reported.

**Q3 — Purchased coins and bars: keep them as coins/bars stock (do not convert to scrap).**
Reasons:
- Coins and bars are resold as they are, at their nominal weight and piece count. Booking them as scrap loses the piece count and the denomination. Coin and bar stock would then be wrong, and the closing count could not reconcile.
- The owner's examples were all jewelry («سلسلة، خاتم، حلق»), and his karat list (18, 21, 22, 14) is the worked-jewelry list; 24 karat bars and 21 karat coins are not in it.
- Scrap is the "melt" bucket. A damaged coin or bar can still be bought explicitly as «كسر» from the same form.

Keep `_purchaseToScrap` mapping only `worked_jewelry` → `scrap`.

**Q4 — Default «أخرى» list: use these 13, most common first.**
`دبلة، محبس، غويشة، إسورة، انسيال، خلخال، كوليه، طقم، نص طقم، بروش، توينز، كف، ميدالية`
These are standard Egyptian retail jewelry names that are not already main tiles («خاتم، حلق، سلسلة، تعليقة»). Anything shop-specific is added by the owner through «صنف جديد» in الجرد الفوري (Task 9). Ask the owner only whether a name is missing; do not block the release on it.

## 2. Facts the plan relies on (verified in code)

- Sale/purchase entry: `app/lib/src/features/daily_ledger/presentation/financial_trade_screen.dart`. Sale and purchase use `_fastEntry` (one form). `_ItemEntry` holds `category, karat, name, grams, count, price`.
- Server trade validation (`supabase/migrations/20261005091822_complete_owner_feedback.sql` and later) **accepts a purchase line with `category: 'scrap'` and any `item_name`**, with `count: null`. Scrap karats allowed: 14, 18, 21, 22, 24. So "purchased ring goes to scrap" is client-only.
- Per-item prices: each line has optional `line_price_piastres`; server enforces **all lines priced or none**, and the sum must equal the invoice total (`line_price_mismatch`). The domain (`financial_draft.dart`) already enforces the same. The fast-entry form shows the price field only when editing an operation that already had prices — that is the "removed option".
- Customer phone on the server: `^\+?[0-9]{7,15}$` (trades), CRM: `^\+[1-9][0-9]{6,14}$` with Egyptian rules. Client normalizer already exists: `normalizeCustomerPhone()` in `customers/domain/customer_rules.dart`.
- WhatsApp text today: `messageWhatsappUri()` in `invoice_message/domain/message_template.dart` builds `https://wa.me/…` and accepts **Egyptian numbers only**; `UrlMessageLauncher` opens it with `launchUrl` → Android shows "open with" (browser vs WhatsApp). That is the owner's "doesn't open WhatsApp directly".
- Invoice file today: `invoice_pdf_share_dialog.dart` offers «إرسال صورة عبر واتساب» (PNG through the system share sheet, no number, no text) and «PDF للطباعة أو المشاركة». The text message and the file are two separate actions.
- Default message text: `defaultInvoiceMessage` in `message_template.dart` (client-only constant; server stores `null` for "default"). Shops can already edit it in `message_settings_screen.dart` (ADR 0022).
- Notes: both PDFs print the internal note — `branded_invoice_pdf.dart` (`document.note`) and `confirmed_operation_pdf.dart` (`payload['note']`).
- Weight helper text: two places in `financial_trade_screen.dart` (`helper: 'دقة 0.01 جرام · منزلتان عشريتان كحد أقصى'`).
- «اسم العميل (اختياري)» sits as the **first field inside an `ExpansionTile`**; its floating label is drawn above the field and the tile's clip cuts the top half. Same for the first field of «ملاحظات (اختياري)».
- Coins/bars picker: `trade_nominal_picker.dart`. Bars have 9 denominations (coins 5), so the chips wrap to several rows and the «الأعداد المختارة» rows are pushed below the fold inside the scrolling list.
- «صنف جديد» exists in the sale form (`_otherCategoryGrid` → `TradeAddTile`) and in the picker (`onCreate`). Inventory already has a product form (`CatalogProductForm`) behind a small outlined button «منتج في الكتالوج» at the bottom of `inventory_screen.dart`.
- Karat lists are sorted ascending (`..sort()`) → 14 is first.

---

## Priority 1 — critical

### Task 1 — Purchased jewelry adds to scrap, not jewelry stock (FB-010)

**File** `financial_trade_screen.dart`

1. Add to `_FinancialTradeScreenState`:
   ```dart
   /// Owner rule 2026-11-06: purchased jewelry is booked as scrap at its karat.
   /// Coins and bars keep their own stock (owner question Q3).
   bool get _purchaseToScrap => widget.kind == FinancialKind.purchase;
   String _bookedCategory(String category) =>
       _purchaseToScrap && category == 'worked_jewelry' ? 'scrap' : category;
   ```
2. Every place that assigns `row.category = …` / `line.category = …` / `item.category = …` from a choice (in `_chooseCategory`, `_otherCategoryGrid` onTap, `_addOtherProduct`, the picker result handling) must assign `_bookedCategory(<category>)`. Keep `row.name.text` as the chosen name («خاتم», «حلق», «دبلة»…). Karat: keep the chosen karat; if it is not in `ScrapKarats.allowed`, use 18.
3. `_choiceSelected`: for purchase, a jewelry tile is selected when `item.name.text == label` (unchanged) — do not compare category.
4. Item card category dropdown: when `_purchaseToScrap`, list only «سبائك», «جنيهات», «كسر» (remove «مشغولات» via `openingCategoryChoices.where((c) => c != StockCategory.workedJewelry)`). Scrap rows already hide «العدد».
5. Editing an **old** purchase whose payload has `worked_jewelry` lines: leave those lines as they are (do not rewrite history). The dropdown shows «مشغولات» only for such a row (`row.category == 'worked_jewelry'`).
6. Exchange flows (`exchangeReturnPayload != null`), scrap sale and sale are unchanged.

**Acceptance**: buy «خاتم» 18 — 3.50 g → confirmed operation line `{category: 'scrap', karat: 18, item_name: 'خاتم', count: null}`; the day's «وزن مشترى» sheet shows it under «كسر» 18; scrap stock 18 rises by 3.50 g; jewelry stock unchanged.

**Tests** (new `app/test/purchase_to_scrap_test.dart`, use the fake gateway pattern from `batch2_trade_form_test.dart`): ring purchase → submitted payload line category `scrap`, count `null`, name `خاتم`; bars purchase → category `bullion`; sale ring → `worked_jewelry`; edit of an old purchase with a `worked_jewelry` line keeps it.

### Task 2 — Karat order 18, 21, 24, 22, 14 everywhere (FB-010)

1. In `daily_ledger/domain/opening_catalog.dart` add:
   ```dart
   /// Owner order: the common Egyptian karats first, 22 and 14 last.
   const karatDisplayOrder = <int>[18, 21, 24, 22, 14];
   List<int> orderedKarats(Iterable<int> allowed) => [
     for (final karat in karatDisplayOrder)
       if (allowed.contains(karat)) karat,
   ];
   ```
2. Replace every ascending karat list in UI with `orderedKarats(...)`. Find them with:
   ```bash
   grep -rnE "karats(\.toList\(\))?\.\.sort\(\)|\.\.sort\(\)\)|scrapKaratChoices|<int>\[14, 18" app/lib
   ```
   Known places: `financial_trade_screen.dart` (`_itemCard` karats, and the `allowed…first` default in the category `onChanged`), `trade_item_picker.dart` (worked-jewelry karats), `daily_ledger_screen.dart` (~line 1578), `daily_ledger_controller.dart` (~line 175), `opening_copy.dart` (`scrapKaratChoices` → `[18, 21, 24, 22, 14]`), and inventory forms (`karatsFor` in `inventory_forms.dart`). Defaults that use `.first` now become 18 (or 24 for bars, 21 for coins — single-karat categories are unaffected).
3. Do not change server data or the metric strip ids.

**Tests**: `orderedKarats({14,18,21,22})` → `[18,21,22,14]`; `orderedKarats(ScrapKarats.allowed)` → `[18,21,24,22,14]`; a widget test opening the karat dropdown on a purchase scrap row shows 18 first and 14 last.

### Task 3 — Per-item prices are an option again (FB-005)

**File** `financial_trade_screen.dart` (+ `shared_preferences`, already a dependency)

1. State: `bool _linePricing = false;` loaded in `initState` from `SharedPreferences` key `'trade_line_pricing_${widget.shopId}'` (wrap in try/catch; default `false`). When editing an operation whose items carry `line_price_piastres`, force `true` for this screen without saving.
2. In `_fastEntryWidgets`, directly above the first item card, add:
   ```dart
   SwitchListTile(
     key: const Key('trade-line-pricing'),
     contentPadding: EdgeInsets.zero,
     title: const Text('سعر لكل صنف'),
     value: _linePricing,
     onChanged: _busy ? null : _setLinePricing,
   )
   ```
   `_setLinePricing(bool on)`: setState; when turning off, clear every `row.price`; persist to the same key (try/catch, ignore failure).
3. In `_itemCard`, when `_fastEntry && _linePricing`, show under the weight field:
   `ledgerMoneyField(key: Key('trade-line-price-$index'), controller: row.price, label: 'سعر الصنف', …)` with `onChanged: (_) => setState(() {})`. Remove the old edit-only `trade-edit-line-price-$index` field (the new one covers edits).
4. Under the item list (still in fast entry, when `_linePricing`), show one line: `'مجموع أسعار الأصناف: ${displayPounds(sum)}'` (key `trade-line-price-sum`), where `sum` adds `Piastres.parsePounds(cashInputValue(row.price.text))` of all rows (skip invalid). For a **sale** add, when the sum differs from `_totalPounds()`: `'الفرق عن المدفوع: …'` in `colorScheme.error`. For a **purchase** compare against `_purchaseTotal`.
5. Payment split stays exactly as today (cash / Instapay / Visa / wallet tenders). No change to tenders.
6. Validation already exists: `FinancialIssue` for missing prices and `line_price_mismatch` («أسعار الأصناف لا تساوي الإجمالي.»). When `_linePricing` is on and a row's price is empty, show `'أدخل سعر كل صنف أو أوقف «سعر لكل صنف».'` before review.

**Acceptance**: switch on → ring 5,000 + earring 3,000; tenders cash 6,000 + Visa 2,000 → saves; ledger card, operation details and both PDFs show each item price. Switch stays on next time for that shop. Switch off → prices cleared, one total as today.

**Tests**: priced sale submits `line_price_piastres` per line; mismatch shows the error and does not submit; off → all `null`; preference restored on reopen.

### Task 4 — Invoice: shop name on top, internal notes never printed (FB-004)

1. `invoice_appearance/application/branded_invoice_pdf.dart`: in `widgets()`, the box after totals prints `document.description` and `document.note`. **Remove `document.note`** from the PDF (keep `description`). The box shows only when `description != null`.
2. `daily_ledger/application/confirmed_operation_pdf.dart`: delete the block that prints `'ملاحظة: ${payload['note']}'`.
3. Do not remove the note from the app screens (`financial_operation_screen.dart` keeps showing it to the shop).
4. Header: both PDFs already print the shop name. Add tests that lock it:
   - branded: document with `shopName: 'مجوهرات الاختبار'` and an operation whose `actor_display_name` is `'بائع الاختبار'` → PDF text contains the shop name and **not** the actor name. (Use the existing PDF text-extraction helper used in `invoice_appearance` tests; search `test/` for `branded_invoice` to find it.)
   - legacy PDF: same assertion for `buildConfirmedOperationPdf` (or its actual name in `confirmed_operation_pdf.dart`).
   - note `'ملاحظة داخلية'` in payload → absent from both PDFs.
5. `branded_invoice_pdf.dart` `_customer()`: the box label becomes `'العميل'` for both sale and purchase (replace `document.kind == 'sale' ? 'العميل' : 'البائع'`). Test: purchase PDF contains «العميل» and not «البائع».
6. If Q2's screenshot shows something else, fix that exact element and extend the same test.

### Task 5 — One button: PDF + message, straight to the customer's WhatsApp (FB-003)

This is the largest task. Platform limits are real and must be stated in Arabic in the UI (below).

**5a. Message text default and settings**
1. `invoice_message/domain/message_template.dart`: replace `defaultInvoiceMessage` with:
   ```dart
   const defaultInvoiceMessage =
       'أهلاً بحضرتك، يسعدنا تعاملكم مع {shop_name}.\n'
       'فاتورتكم رقم {sequence} جاهزة بإجمالي {total}.\n'
       'شكراً لتعاملكم.';
   ```
   Bump `messageRendererVersion` to `2`. (All three placeholders are on the ADR 0022 allowlist; the template is client-side, the server stores `null` for default.)
2. Add a link in «المزيد» → «الفاتورة» group (`shop_workspace.dart`), owner only, when `widget.messageBuilder != null`: `_link('رسالة الفاتورة', Icons.chat_outlined, _openMessage, key: const Key('workspace-invoice-message'))`. The settings screen already supports edit and reset-to-default.

**5b. Phone for WhatsApp** — replace `messageEgyptianPhone` with `messageWhatsappPhone(Object? raw)` that returns digits without `+`: accept `normalizeCustomerPhone(raw)` (handles `01…` → `+20…` and `+<code>…`) and return `normalized.substring(1)`; `null` if invalid. Update `messageWhatsappUri` and all callers/tests.

**5c. Text-only message opens WhatsApp directly** — `invoice_message/data/url_message_launcher.dart`: given the `https://wa.me/<digits>?text=…` uri, first try `whatsapp://send?phone=<digits>&text=<same encoded text>` with `launchUrl(mode: LaunchMode.externalNonBrowserApplication)`; if that returns false or throws `PlatformException`, fall back to the current `https` launch. (Manifest/Info.plist already declare the `whatsapp` scheme.)

**5d. PDF + message to the customer's chat**
1. New port in `daily_ledger/application/invoice_whatsapp_share.dart`:
   ```dart
   enum WhatsappShareResult { opened, sheetOpened, notInstalled, failed }
   abstract interface class InvoiceWhatsappShare {
     Future<WhatsappShareResult> sharePdf({
       required Uint8List pdf,
       required String filename,
       required String? phoneDigits, // e.g. 201012345678, null if unknown
       required String text,
     });
   }
   ```
2. Implementation `daily_ledger/data/platform_invoice_whatsapp_share.dart`:
   - **Android** — MethodChannel `eldafttar/whatsapp_share`, method `sharePdf`, args `{path, phone, text}`. Dart writes the PDF to `getTemporaryDirectory()/invoices/<filename>` first.
     Kotlin in `MainActivity.kt` (second channel next to the existing one): build `Intent(Intent.ACTION_SEND)` with `type = "application/pdf"`, `EXTRA_STREAM = FileProvider.getUriForFile(this, "$packageName.invoicefiles", File(path))`, `EXTRA_TEXT = text`, `addFlags(FLAG_GRANT_READ_URI_PERMISSION)`, and when `phone` is non-null `putExtra("jid", "$phone@s.whatsapp.net")`. Try `setPackage("com.whatsapp")`, then `"com.whatsapp.w4b"`; return `"opened"`; if both throw `ActivityNotFoundException` return `"not_installed"`. Validate `phone` with `^[1-9][0-9]{6,14}$` and `path` inside `cacheDir/invoices`, else `error("invalid")`.
     Manifest: add inside `<application>`:
     ```xml
     <provider android:name="androidx.core.content.FileProvider"
         android:authorities="${applicationId}.invoicefiles"
         android:exported="false" android:grantUriPermissions="true">
       <meta-data android:name="android.support.FILE_PROVIDER_PATHS"
           android:resource="@xml/invoice_file_paths" />
     </provider>
     ```
     New `android/app/src/main/res/xml/invoice_file_paths.xml`: `<paths><cache-path name="invoices" path="invoices/" /></paths>`. In `<queries>` add `<package android:name="com.whatsapp" />` and `<package android:name="com.whatsapp.w4b" />`. If `androidx.core` is not already on the classpath, add `implementation("androidx.core:core-ktx:1.13.1")` to `android/app/build.gradle(.kts)`.
   - **iOS** — Apple does not let an app attach a file to a specific WhatsApp chat. Use `SharePlus.instance.share(ShareParams(files: [XFile(path, mimeType: 'application/pdf')], text: text, …))` → return `sheetOpened` when status is success.
   - **Windows** — WhatsApp Desktop cannot receive a file by link. Save the PDF to `<Documents>\الدفتر\الفواتير\<filename>` (`path_provider` `getApplicationDocumentsDirectory()`), open the chat with `whatsapp://send?phone=<digits>&text=<encoded>` (fallback `https://wa.me/…`), then run `Process.run('explorer.exe', ['/select,', path])` so the file is highlighted for dragging. Return `opened`.
3. `invoice_pdf_share_dialog.dart`:
   - Replace the «إرسال صورة عبر واتساب» button (`invoice-image-share`) with a primary `FilledButton.icon` key `invoice-whatsapp-pdf`, label `'إرسال الفاتورة PDF على واتساب'`, WhatsApp icon (`theme/whatsapp_icon.dart`). It produces the PDF exactly like the current `_Action.pdf` path (same presentation-copy issuance and idempotency), gets the text from `MessageHandoff.prepare(...)` when `widget.gateway is InvoiceMessageGateway` (else `''`), gets `phoneDigits` from `messageWhatsappPhone(payload['customer_phone'])`, then calls the port.
   - Remove the PNG path (`_Action.image`, `_sharePng`, rasterizer use) from this dialog. Keep «PDF للطباعة أو المشاركة» as the secondary button and the legacy document action.
   - Status text after the call (all replace the current `_say` messages for this action):
     - `opened` with phone: `'فُتحت محادثة العميل في واتساب ومعها الفاتورة والرسالة. أرسلها ثم أكّد هنا.'`
     - `opened` without phone: `'فُتح واتساب ومعه الفاتورة. اختر العميل وأرسل، ثم أكّد هنا.'`
     - `sheetOpened` (iOS): `'اختر واتساب ثم العميل وأرسل، ثم أكّد هنا.'`
     - Windows `opened`: `'فُتحت محادثة العميل. اسحب ملف الفاتورة المحدد إلى المحادثة وأرسل، ثم أكّد هنا.'`
     - `notInstalled`: fall back to the system share sheet with the PDF and text and say `'واتساب غير مثبت. اختر تطبيقاً للمشاركة.'`
     - `failed`: `'تعذر فتح واتساب. حاول مجدداً.'` (error style)
   - Opening WhatsApp **never** marks the invoice as sent; the existing «نعم، أُرسلت» confirmation stays (ADR 0006).
4. Wire `PlatformInvoiceWhatsappShare` where the dialog is created (`showInvoicePdfShareDialog` gets an optional `InvoiceWhatsappShare? whatsapp` for tests; default to the platform implementation).

**Acceptance (Android device)**: sale with customer phone `01012345678` → tap «إرسال الفاتورة PDF على واتساب» → WhatsApp opens **that customer's chat** with the PDF attached and the default message as caption, no app chooser. Foreign number `+966512345678` → same. No phone → WhatsApp contact picker with the PDF. Message edited in «رسالة الفاتورة» is the one used.

**Tests**: fake `InvoiceWhatsappShare` receives `application/pdf` bytes (starts with `%PDF`), filename `.pdf`, the rendered default text, phone `201012345678`; `notInstalled` falls back; no image action key exists; message tests for `messageWhatsappPhone` (Egyptian local, `+20`, `+966…`, invalid); launcher test that tries `whatsapp://` first then `https`.

---

## Priority 2

### Task 6 — Customer phone: country code (default Egypt) and "missing digit" errors (FB-001)

1. New domain file `customers/domain/phone_countries.dart`:
   ```dart
   final class PhoneCountry {
     const PhoneCountry(this.nameAr, this.dial, this.lengths, {this.mobilePrefix});
     final String nameAr, dial;   // dial without '+', e.g. '20'
     final Set<int> lengths;      // national significant digits (no leading 0)
     final String? mobilePrefix;  // regex source for the start of the national digits
     bool prefixOk(String national) =>
         mobilePrefix == null || RegExp('^(?:$mobilePrefix)').hasMatch(national);
   }
   const egypt = PhoneCountry('مصر', '20', {10}, mobilePrefix: '1[0125]');
   ```
   List (`const phoneCountries`), in this order, with `mobilePrefix` in backticks: مصر 20 {10} `1[0125]`; السعودية 966 {9} `5`; الإمارات 971 {9} `5`; الكويت 965 {8}; قطر 974 {8}; البحرين 973 {8}; عُمان 968 {8}; الأردن 962 {9} `7`; العراق 964 {10} `7`; ليبيا 218 {9}; السودان 249 {9}; فلسطين 970 {9}; سوريا 963 {9}; اليمن 967 {9}; لبنان 961 {7, 8}; تونس 216 {8}; الجزائر 213 {9}; المغرب 212 {9}; تركيا 90 {10}; المملكة المتحدة 44 {10}; الولايات المتحدة وكندا 1 {10}; ألمانيا 49 {10, 11}; إيطاليا 39 {9, 10}; فرنسا 33 {9}.
2. `PhoneCheck checkCustomerPhone(PhoneCountry country, String national)` returns either `e164` (`'+<dial><digits>'`) or an Arabic error. Rules: fold Arabic-Indic digits (`foldCustomerDigits`), strip spaces/dashes, strip one leading `0`; then
   - fewer digits than `min(lengths)` → `'الرقم ناقص ${n} ${n == 1 ? 'رقم' : 'أرقام'}.'`
   - more than `max(lengths)` → `'الرقم أطول من المعتاد في ${country.nameAr}.'`
   - Egypt pattern fails → `'رقم الموبايل المصري يبدأ بـ 010 أو 011 أو 012 أو 015.'`
   - other pattern fails → `'تحقق من رقم ${country.nameAr}.'`
   - If the user types a full `+…` number, detect the country by longest matching dial code and validate against it.
3. Widget `customers/presentation/customer_phone_field.dart`: a row with a compact country `DropdownButton` (shows `+20`, list shows `'مصر +20'`) and an LTR `TextFormField` (`keyboardType: phone`). **Default country is always Egypt**; the user only changes it for a foreign number. Validation runs on field submit/review (not on every keystroke) and shows the error under the field. Exposes the E.164 value or `null` when empty.
4. Use it for the **customer** phone in: sale form `trade-customer-phone` (`financial_trade_screen.dart`), customer profile phones `customer-phone-$i` (`customer_screen.dart`, remove its helper `'رقم مصري محلي أو رقم دولي يبدأ بـ +'`), and debt phone `debt-phone` (`debt_screen.dart`). Keep the same widget keys on the inner text field. Store/send the E.164 value (server regexes already accept it). When loading an old value like `01012345678`, show Egypt + `1012345678`.
5. Do not change staff, shop-profile or registration phone fields.

**Tests** (`phone_countries_test.dart`): `0101234567` (Egypt, 9 digits) → «الرقم ناقص 1 رقم.»; `01712345678` → Egypt prefix error; `01012345678` → `+201012345678`; Saudi `512345678` → `+966512345678`; `+966512345678` typed in Egypt mode → detected as Saudi; Arabic-Indic digits accepted. Widget test: sale with a short number cannot reach review and shows the error.

### Task 7 — Sale form polish: label clipping, helper text, locked coin/bar count (FB-002, FB-008, FB-006)

**File** `financial_trade_screen.dart`
1. **FB-002** — both `ExpansionTile`s (`trade-customer-disclosure`, `trade-notes-disclosure`): add `childrenPadding: const EdgeInsetsDirectional.only(top: 12, bottom: 8)` so the first field's floating label is not clipped. Test: at 360 px width and text scale 1.3, after expanding, `tester.getRect(find.text('اسم العميل (اختياري)')).top >= tester.getRect(find.byKey(Key('trade-customer-disclosure'))).top` and the label's full height is inside the tile.
2. **FB-008** — delete both `helper: 'دقة 0.01 جرام · منزلتان عشريتان كحد أقصى'` arguments. Keep `GramInputFormatter(decimalPlaces: 2)` and the review-time error.
3. **FB-006** — `_ItemEntry`: add `bool countFromPicker = false;`. In the nominal-picker fill loop (the `for (final entry in selected.indexed)` block in `_chooseCategory`) set `line.countFromPicker = true`. When a row changes category or name through any other path, set it to `false`.
   In `_itemCard`, the `trade-count-$index` `TextField` gets `readOnly: row.countFromPicker`, and when read-only: `suffixIcon: const Icon(Icons.lock_outline, size: 18)` and `onTap: () => _chooseCategory(row.category == 'coin' ? 'جنيهات' : 'سبائك', row.category, target: row)` (reopens the picker to change counts). No helper text. Weight stays editable.
   Tests: after picking 2 × «جنيه ذهب», the count field is read-only (typing does nothing), tapping it opens the picker; a manually added coin row (picker unavailable) stays editable.

### Task 8 — Bars picker: quantities visible without scrolling (FB-007)

**File** `trade_nominal_picker.dart`
1. Move the «الأعداد المختارة» block (title + `_SelectedQuantityRow`s) **out of the scrolling `ListView`** into the fixed bottom area, directly above `nominal-total`, inside `ConstrainedBox(constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.3), child: SingleChildScrollView(child: Column(...)))`. It appears as soon as one chip is selected — same for coins and bars.
2. Shorten the instruction text to `'اضغط النوع لاختياره، ثم حدد العدد بالأسفل.'`.
3. Keep keys `nominal-qty-row-$index`, `nominal-total`, `nominal-apply`.

**Test**: bars picker at 360×640 → tap the last chip (`nominal-select-8`) → `nominal-qty-row-8` is on screen (its rect is inside the view) without any scroll; same for coins.

### Task 9 — «أخرى»: smaller tiles, default items, «صنف جديد» moves to الجرد الفوري (FB-009, FB-011)

1. **Smaller** — `trade_item_picker.dart`: add `final bool dense;` (default `false`) to `TradeChoiceTile`; when dense: `minHeight: 40`, padding `EdgeInsets.symmetric(horizontal: 4, vertical: 6)`, text style `labelMedium`. In `financial_trade_screen.dart` `_otherCategoryGrid`, use `TradeChoiceGrid(columns: 5, compactColumns: 3, …)` with `dense: true` tiles. Same `dense` in the picker's «أصناف أخرى» section.
2. **Default items** — replace `_otherJewelry` with the list below (owner to confirm, Q4), all `worked_jewelry`, in this order:
   `دبلة، محبس، غويشة، إسورة، انسيال، خلخال، كوليه، طقم، نص طقم، بروش، توينز، كف، ميدالية`.
   Update `_mainNames`/reserved checks only if a name collides with a main tile (none do).
3. **Remove «صنف جديد» from sale/purchase** — in `_otherCategoryGrid` delete the `TradeAddTile` (`trade-add-other-product`); in `_openItemPicker` pass `onCreate: null`; delete `_addOtherProduct` and `_createOtherProduct` and their now-unused state (`_productPending`…) only if nothing else uses them (`dart analyze` will tell).
4. **Add «صنف جديد» to الجرد الفوري** — `inventory/presentation/inventory_screen.dart`: add near the top of the main list (above the balances) a `FilledButton.icon(key: Key('inventory-new-item'), icon: Icon(Icons.add), label: Text('صنف جديد'), onPressed: () => _open(CatalogProductForm(scope: _scope)))`, visible with the same permission as the existing `inventory-product` action. Remove the old bottom action `'منتج في الكتالوج'` (`inventory-product`) to avoid two entries. In `CatalogProductForm` (`inventory_forms.dart`) rename label `'اسم المنتج'` → `'اسم الصنف'` and add hint `'مثال: بروش، كوليه، محبس'`. The saved product already appears in «أخرى» on sale/purchase (loaded from the catalog).

**Tests**: «أخرى» grid shows the 13 defaults and no `trade-add-other-product`; picker has no create row; inventory shows `inventory-new-item` and saving a product makes it appear in the sale «أخرى» grid (fake catalog); tile height ≤ 44 at scale 1.0.

---

### Task 9b — App version visible in «المزيد» (Q1)

1. `app/lib/src/app.dart` already receives `appVersion` (from `package_info_plus`, used by the forced-update check). Pass it down to `ShopWorkspace` as `final String? appVersion;` (through `ShopAccountsGate` where `ShopWorkspace` is built).
2. In `_morePage()` (`shell/shop_workspace.dart`), after the last group, add a centered `Text('الإصدار ${widget.appVersion}', key: const Key('workspace-app-version'))` in `bodySmall` with `colorScheme.onSurfaceVariant`, LTR digits wrapped with `⁦…⁩`. Hide it when `appVersion` is null.
3. Test: «المزيد» shows `workspace-app-version` with the passed version.

## Task 10 — Records, review, validation

1. New ADR `docs/adr/0040-owner-feedback-2026-11-06-trade-invoice-whatsapp.md`: purchased jewelry booked as scrap (Q3 default for coins/bars); karat display order; optional per-item prices with per-shop remembered switch; internal notes never printed; PDF + message handoff per platform (Android direct chat via share intent with `jid`, iOS share sheet, Windows chat + selected file) — amends ADR 0022's Egypt-only phone and "no PDF" exclusions and keeps ADR 0006 owner-confirmed dispatch; international customer phones with Egypt default; «صنف جديد» only in inventory; default «أخرى» list.
2. Update `docs/decisions.md`, `docs/requirements-matrix.md`, `docs/design-system.md` (dense choice tiles, phone field, picker footer).
3. Visual review in Arabic RTL, light and dark, at 360, 390 and 1440 px and text scale 1.3: sale form (switch on/off, customer section expanded, locked coin count), bars picker, purchase with ring, invoice dialog, inventory top, «المزيد» → «رسالة الفاتورة». Use the capture-test pattern (`test/*_capture_test.dart` writes PNGs under `app/build/`).
4. **Device check (required for Task 5)**: on a real Android phone with WhatsApp: Egyptian number, Saudi number, no number, WhatsApp Business only, WhatsApp not installed. On Windows with WhatsApp Desktop. Record results.
5. Gates: `dart format --set-exit-if-changed lib test`, `dart analyze`, `flutter test`, `git diff --check`. No SQL/React change → state that SQL/React gates were not needed.
6. Write `docs/operations/owner-feedback-2026-11-06-validation.md` with commands, results, screenshots, device results, and what was not verified.

## Traceability

| Owner item | Task |
|---|---|
| FB-001 phone validation + country code | 6 (+5b for WhatsApp) |
| FB-002 «اسم العميل (اختياري)» cut off | 7 |
| FB-003 direct WhatsApp, PDF not image, default + editable message | 5 |
| FB-004 shop name on invoice, notes not printed | 4 (+Q2) |
| FB-005 per-item price option, payment split kept | 3 |
| FB-006 coin/bar count locked after picking | 7 |
| FB-007 bars quantity visible | 8 |
| FB-008 remove weight helper text | 7 |
| FB-009 smaller «أخرى», default items | 9 (+Q4) |
| FB-010 purchases go to scrap; karat order 18/21 first, 22/14 last | 1, 2 (+Q3) |
| FB-011 «صنف جديد» in الجرد الفوري | 9 |
| FB-012 «رصيد مجمع» | Q1 (not in current code) + 9b (version shown) |

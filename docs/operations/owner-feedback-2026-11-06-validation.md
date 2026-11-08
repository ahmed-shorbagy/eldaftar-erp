# Owner feedback 2026-11-06 — validation

Date: 2026-11-08. Flutter client only (`app/`). No commit, no push, no release build, no schema, Edge Function, or R2 change. SQL and React gates were not run; this change does not touch `admin/` or `supabase/`.

Records: [ADR 0040](../adr/0040-owner-feedback-2026-11-06-trade-invoice-whatsapp.md), [decisions](../decisions.md), [requirements](../requirements-matrix.md), [design system](../design-system.md).

## Commands

From `app/`:

| Command | Result |
| --- | --- |
| `dart format --set-exit-if-changed lib test` | Clean. Exit 0. One earlier pass reformatted `test/owner_feedback_2026_11_06_test.dart`; the repeat changed 0 files. |
| `dart analyze` | No issues found. Exit 0. |
| `flutter analyze` | Crashes in this environment. The analysis server snapshot must be run with `dartaotruntime`. `dart analyze` is the substitute. |
| `flutter test` | 1697 tests passed, about 3 minutes, exit 0. This run includes the capture test and the inventory karat-filter fix. |
| `git diff --check` | Exit 0. Git printed LF-to-CRLF warnings only, including `docs/decisions.md` and `docs/requirements-matrix.md`. |

## What the tests cover

- Purchased jewelry is booked as scrap. Coins and bars keep their category. An exchange purchase is unchanged. A historical worked-jewelry purchase line is not rewritten.
- Karat choice lists are 18, 21, 24, 22, 14, limited to the karats that category allows. Wire indexes, metric ids, and payload sorts stay.
- «سعر لكل صنف» prices every line or none, the sum must equal the invoice total, and the shop choice is remembered. Editing an operation that already has line prices turns the switch on for that screen only.
- Both invoice PDFs print the shop name, omit the internal note, and label the counterparty «العميل» for a sale and a purchase. The description still prints.
- The default message is the three-line template and the renderer version is 2. WhatsApp digits come from `normalizeCustomerPhone`; a bare `2010…` is not a number. The launcher tries `whatsapp://send` and then `https://wa.me`. The dialog sends the PDF bytes, a `.pdf` name, and the caption. «واتساب غير مثبت» falls back to the share sheet and does not confirm dispatch. «المزيد» → «الفاتورة» opens «رسالة الفاتورة».
- Egypt is the default country. A short Egyptian number shows «الرقم ناقص 1 رقم.» and blocks review. The stored value is E.164.
- The weight helper is gone. A count taken from the coin or bar picker is read-only and reopens the picker. The customer label stays inside the expanded section at 360×800 and text scale 1.3. «أخرى» tiles are at most 44 pixels tall. The last bar quantity stays inside the picker footer. «المزيد» shows «الإصدار 1.4.2».
- «صنف جديد» is the inventory create control. The sale grid has no add button. Creating a product from the item picker is gone. Catalog products still appear under «أخرى».
- The الجرد الفوري karat filter uses the same display order. With no category selected the chips are 18, 21, 24, 22, 14.

## Screenshots

`test/owner_feedback_2026_11_06_capture_test.dart` wrote 80 PNGs under `app/build/owner-feedback-2026-11-06/`. Each scene is Arabic RTL, light and dark, at 360, 390, and 1440, plus 360 at text scale 1.3. `app/build/` is gitignored.

Reviewed on screen: the sale form with the switch off and on, the locked coin count and its lock icon, the expanded customer name inside its section, the thirteen «أخرى» names with no add button, a purchase of خاتم at karat 18, the bars sheet with the selected quantity in the footer above the total, the invoice dialog with «إرسال الفاتورة PDF على واتساب», الجرد الفوري with «صنف جديد» above the cash totals, and «المزيد» opening «رسالة الفاتورة» with the three-line preview and «الإصدار 1.4.2». Dark uses the same brown and cream roles. The purchase captures show the per-line switch on because the sale capture in the same shop turned it on first; that is the remembered choice.

On a 360-pixel phone the «أخرى» grid’s own width is under 360, so it uses three columns. Five columns appear when the grid itself is at least 360 wide. At text scale 1.3 the last name sits against the review bar until the list is scrolled; the tile height test still holds.

The inventory captures have no open business day, so «صنف جديد» is disabled and the screen says «لا يوجد يوم عمل مفتوح.»

## Device review

Task 5 was not run on a device:

| Check | Result |
| --- | --- |
| Android, WhatsApp installed, Egyptian number `01012345678` | Not run. |
| Android, Saudi number `+966512345678` | Not run. |
| Android, no customer number | Not run. |
| Android, WhatsApp Business only | Not run. |
| Android, WhatsApp not installed | Not run. The widget test covers the fallback copy only. |
| Windows, WhatsApp Desktop, file highlighted under Documents\الدفتر\الفواتير | Not run. |

## Not verified

- `flutter analyze` (tool crash, above).
- A signed-in walkthrough on Android, iOS, or Windows. The PNGs are widget captures, not a device pass.
- The Task 5 device checks in the table above.
- Hosted Supabase. Nothing in this change is deployable there.
- Owner acceptance. Q1 still has nothing named «رصيد مجمع» in the current code; the version line is the way to identify the build in a later screenshot.

## Review on 2026-11-08

Every task was checked against the plan and the owner notes. Purchased jewelry is booked as scrap, the karat order is in place, and so are line prices, the PDF header and notes, the WhatsApp button, the phone countries, the locked count, the picker footer, «أخرى», «صنف جديد», and the version line. Nothing outside the plan was added, except one small fix: choosing «أخرى» no longer scrolls the grid away.

Fixes made in review:

- **Customer phone lost when the section was closed.** `CustomerPhoneField` wrote the number to the form only during validation. In the sale form, the number lives inside «تفاصيل العميل (اختياري)», and closing that section removes the field. A number typed and then hidden was saved as empty, and the WhatsApp step had no number. The field now updates the stored value on every edit and country change. Review also checks the stored value when the field is hidden. There are regression tests in `test/phone_countries_test.dart`; both fail without the fix.
- **Windows status with no customer number.** The message said the customer's chat was open. It now says «فُتح واتساب. اختر العميل، ثم اسحب ملف الفاتورة المحدد إلى المحادثة وأرسل، ثم أكّد هنا.»
- **The WhatsApp phone error still said "Egyptian."** It now reads «لا يحتوي المستند المؤكد على رقم هاتف صالح لواتساب.»
- **iPad share sheet.** The iOS path now passes the dialog's position (`origin` on `InvoiceWhatsappShare`) and reports `failed` instead of throwing.
- **Empty «الفاتورة» group.** The group is shown only when it has an entry: it needs invoice appearance, or the owner's «رسالة الفاتورة».
- **Historical record.** `test/invoice_branding_pdf_capture_test.dart` rewrites `docs/reviews/invoice-branding-2026-10-21/pdf/partial-purchase-page-1.png` on every full test run, and the new «العميل» label changes the image. The committed image was restored. Do not commit the regenerated one.

Gates after the review fixes, from `app/`:

- `dart format --set-exit-if-changed lib test`: 0 changed.
- `dart analyze`: no issues.
- `flutter test`: 1699 passed.

The device checks above are still open.

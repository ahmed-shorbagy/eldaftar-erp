# Owner answers of 2026-11-10: implementation plan (batch C)

For whoever implements this. Every decision below is final unless marked "ask the owner". Follow [AGENTS.md](../../AGENTS.md): Arabic RTL, theme tokens only, integer piastres and milligrams, server-confirmed writes, tests before reporting, deploy only to development `xchapwvmvoefriqcxtvn`, no release build and no commit or push unless the user says so.

Sources:
- Owner answers: [batch 1](owner-answers-2026-11-10-batch-1.md) (A1–A5) and [batch 2](owner-answers-2026-11-10-batch-2.md) (B1–B9).
- Old app reference and screenshots: [docs/reference/old-app-2026-11-10](../reference/old-app-2026-11-10/README.md).
- Current state: batches A and B of 2026-11-09 ([ADR 0042](../adr/0042-owner-feedback-2026-11-09-day-cycle-and-repairs.md), [ADR 0043](../adr/0043-owner-feedback-2026-11-09-customer-data-and-inventory.md), [validation](owner-feedback-2026-11-09-batch-b-validation.md)). The working tree holds batch B uncommitted; commit or review it before starting, so this batch has its own diff.

## 1. Decisions

| ID | Topic | Decision |
|---|---|---|
| C-D1 | Older app builds (A1) | A server change must never break an installed older build. Public read RPCs that existed at commit `361ad2e` return exactly the keys that commit's client parsers accept. New fields go to new `_v2` reads that only the current app calls. |
| C-D2 | Basic items (A4, B4, B9) | The built-in jewelry items are the old app's names, plural, in the old app's table order: محابس، توينز، غوايش، سلاسل، انسيالات، حلقان، اساور، تعاليق، كوليهات، دبل، خواتم. جنيهات stays a category and is the first table row; سبائك and كسر stay categories. No other built-ins: the «أخرى» list drops every name not in the old app (خلخال، طقم، نص طقم، بروش، كف، ميدالية) and the singular forms (دبلة، محبس، غويشة، إسورة، انسيال، كوليه). Merchants still add their own items. |
| C-D3 | Old singular names | Existing data keeps its stored names. One canonical map joins them in reads and stock choice: خاتم→خواتم، حلق→حلقان، سلسلة→سلاسل، تعليقة→تعاليق، دبلة→دبل، محبس→محابس، غويشة→غوايش، إسورة→اساور، انسيال→انسيالات، كوليه→كوليهات. New lines are stored with the plural name. |
| C-D4 | Item table rows (B4) | «الأصناف حسب العيار» always lists جنيهات then the 11 built-ins, with zeros when there is no stock, then custom items with stock, then «رصيد افتتاحي (بدون صنف)» when it has stock, then «كسر» and «الإجمالي». |
| C-D5 | Inventory figures | Replace the six figures with the old app's carousel, in its order: عيار 18، عيار 21، عدد السبائك، وزن السبائك، اجمالي النقدية، الكسر 18، الكسر 21، اجمالي الكسر 21، اجمالي الوزنة 21 (مشغولات + سبائك)، اجمالي الوزنة 21 (مع الكسر)، and «اجمالي الوزنة 21 مع النقدية» which asks «أدخل سعر الجرام» and shows the result. Add «عيار 22» / «عيار 14» / «الكسر 22» / «الكسر 14» only when that karat has stock. The cash calculator is display only and saves nothing. |
| C-D6 | Day close (B2) | After a close the ledger home shows the carried cash and zero for every daily figure, book, note, and expense. Gold and scrap balances are not on the home screen; they stay in «الجرد الفوري». This is the current behavior; lock it with a test. |
| C-D7 | Repairs name (B3) | «الصيانة» becomes «المرمات» everywhere in the UI, the reports, the PDF, and the copy. One repair is «مرمة». Database names and RPC names stay. Collection timing does not change. |
| C-D8 | Coins and bullion bought (B8) | After a coin or bullion line is confirmed on a purchase form, a half-height sheet asks «هل تريد إضافتها لمخزون الجنيهات؟» (or «السبائك»). «نعم» keeps the line. «لا» shows the karats (24 and 21 first, then 22, 18, 14) and turns the line into scrap at that karat with the same weight and no count. |
| C-D9 | Customer WhatsApp group (B6) | A customer has «في جروب الواتساب» (yes/no), set with VIP and open request, owner only, audited. It shows on the card, in the detail header, as a filter chip «جروب الواتساب», and as a quick action. |
| C-D10 | Customer phone country (B1) | Every customer phone field (customers, sale, purchase, repair) starts on the country of the shop owner's own registered phone. The picker stays for foreign numbers. The current country list already covers the Arab countries; keep it. |
| C-D11 | Party label | The customer fields of a sale and a purchase are titled «العميل» on both («تفاصيل العميل (اختياري)», «اسم العميل (اختياري)»). The purchase capture hint says «العميل». |
| C-D12 | Invoice header (A2) | No code change. The header prints `shops.name`. The owner corrects the test shop name in «المزيد ← بيانات المتجر». |

Not in this batch (proposed to the owner earlier, not answered): price per item on a trade, the default invoice message wording, the iPhone/desktop WhatsApp file flow, and ledger item-row count. Keep current behavior.

## 2. Milestones

| Milestone | Items | Risk |
|---|---|---|
| C0 | ADR 0044, decisions log | low |
| C1 | Older builds keep working (A1) | **high, do first** |
| C2 | Basic items and name map (A4, B4, B9) | high (touches sales stock choice) |
| C3 | Inventory table rows and figures (B4, old app) | medium |
| C4 | «المرمات» rename (B3) | low |
| C5 | Coin and bullion purchase question (B8) | medium |
| C6 | Customer WhatsApp group flag (B6) | medium |
| C7 | Customer phone default country (B1) and «العميل» label | low |
| C8 | Day-close lock test (B2), ledger WhatsApp button (B7), logo fallback (A3) | low |
| C9 | Gates, deployment, validation, owner checklist | low |

C1 ships alone first if time is short: it restores the owner's ledger.

---

## C0 — Bookkeeping

1. Write `docs/adr/0044-owner-answers-2026-11-10.md` with the structure of ADR 0043: context (the two answer batches and the outage), decisions C-D1 … C-D12, data impact, verification list. It amends ADR 0042 (A-D5 wording «المرمات»; C-D1 compatibility rule) and ADR 0043 (B-D10, B-D12 replaced by C-D4, C-D5).
2. Add one line to `docs/decisions.md` at the top.
3. Add a design-guide section «Owner answers — 2026-11-10» to `docs/design-system.md` when C3, C5, C6 land (carousel, rows with zeros, purchase sheet, WhatsApp-group flag).

## C1 — Older builds keep working (A1)

Cause: the owner's installed build (navigation shows «الحساب», so before `f8f52ff`/`361ad2e`) parses the home read strictly. Since 2026-11-09 the server adds `day_reset` and `last_closed_business_date` at the top and `repair_piastres` / `repair_count` inside `day_summary`. Its parser accepts only `{read_model_version, state, entitlement_status, can_confirm, business_day, cash, stock, scrap, feed, day_summary, journal_context}` plus optional `feed_page`, `trade_change_sequence`, and a `day_summary` of exactly 6 or 7 keys (`git show 361ad2e:app/lib/src/features/daily_ledger/data/daily_ledger_codec.dart`).

### C1.1 Inventory of changed reads
For each public RPC changed since `361ad2e` (`git diff 361ad2e -- supabase/migrations`), compare its current output keys with the parser of that read at `361ad2e`. At least:
- `get_daily_ledger_home_v1` (top keys, `day_summary`)
- `get_ledger_date_v1` (`day_summary` repair keys)
- `get_financial_day_report_v1` (summary repair keys)
- `get_repair_v1` (`collections`)
- `get_pending_invoice_sends` (shape unchanged; behavior only)
- customer reads and `list_inventory_*` (check)
Write the result as a table in the validation note: RPC, new keys, old parser strict yes/no.

### C1.2 Migration `supabase/migrations/20261110100000_legacy_read_shapes.sql`
For each read where the old parser is strict:
1. Rename the current public function: `alter function public.<name>(…) rename to <name>_full;` and revoke it from `public`, `anon`, `authenticated`.
2. Create `public.<name>_v2(…)` (same arguments) returning `public.<name>_full(…)` unchanged. Grant `authenticated`; revoke `anon`, `public`.
3. Create the legacy `public.<name>(…)` returning `public.<name>_full(…)` with the new keys removed. Same grants as v2:
   - home: `- 'day_reset' - 'last_closed_business_date'` and `day_summary - 'repair_piastres' - 'repair_count'`.
   - date and day report: remove `repair_piastres`, `repair_count` from their summaries.
   - repair detail: remove `collections` if the old parser is strict.
4. `get_ledger_day_v1` (new on 2026-11-09) is used only by the current app; leave it.
5. Comment each legacy function: "Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1)."

### C1.3 App
Switch the current app to the `_v2` names: `http_opening_gateway.dart` (home, ledger date, day report, repair detail as applicable). Keep the old names nowhere in `app/lib`.

### C1.4 Tests
- SQL `supabase/tests/legacy_read_shapes.sql` (add to `run-rls-tests.mjs`): for an owner and an employee, the legacy home has no `day_reset`, `last_closed_business_date`, and its `day_summary` has only the 6 or 7 legacy keys; v2 has them all; a closed day still zeroes flows in both.
- Flutter `app/test/legacy_read_shapes_test.dart`: copy the `361ad2e` parser into a test helper (`git show 361ad2e:…/daily_ledger_codec.dart`, keep only `parseDailyLedger` and its private helpers) and assert it parses a fixture that matches the legacy server output. This test guards C-D1 for every later change.
- Gateway test: the HTTP gateway calls `get_daily_ledger_home_v2`.

Done when: the legacy home read passes the old parser in the test, the current app reads v2, and the hosted legacy read (rolled-back check) has no new keys.

## C2 — Basic items and the name map (A4, B4, B9)

### C2.1 Domain constants (Flutter)
New `app/lib/src/features/daily_ledger/domain/jewelry_items.dart`:
```dart
/// Old app order (owner, 2026-11-10). Plural, as stored for new lines.
const jewelryBuiltIns = <String>['محابس','توينز','غوايش','سلاسل','انسيالات','حلقان','اساور','تعاليق','كوليهات','دبل','خواتم'];
/// Names stored before 2026-11-10 → their built-in.
const jewelryLegacyNames = <String, String>{'خاتم':'خواتم','حلق':'حلقان','سلسلة':'سلاسل','تعليقة':'تعاليق','دبلة':'دبل','محبس':'محابس','غويشة':'غوايش','إسورة':'اساور','اسورة':'اساور','انسيال':'انسيالات','كوليه':'كوليهات'};
String canonicalJewelryName(String name) => jewelryLegacyNames[name.trim()] ?? name.trim();
```
Unit tests: every legacy name maps; a custom name passes through trimmed.

### C2.2 Replace the item lists
- `trade_item_picker.dart`: `tradeOtherJewelryNames` → the built-ins not shown as main tiles. Remove the 13 old names.
- `financial_trade_screen.dart`: main tiles become خواتم، حلقان، سلاسل، تعاليق (same glyphs), then جنيهات، سبائك، كسر، أخرى; `_mainNames` and `_otherChoices` use `jewelryBuiltIns`.
- `scrap_to_stock_screen.dart` (`_jewelry`, `reservedNames`), `closing_item_grid.dart` (`builtInJewelry` → all 11 in order), `physical_count_editor.dart` if it lists names.
- `grep -rn "'خاتم'\|'حلق'\|'سلسلة'\|'تعليقة'" app/lib` must only return `jewelry_items.dart` afterwards.
- Update tests that expect the singular names (`grep -rln "'خاتم'" app/test`); keep a legacy-data test that a stored «خاتم» line still displays and still groups as «خواتم».

### C2.3 Server
Migration `…_jewelry_item_names.sql`:
1. `private.canonical_jewelry_name(text) returns text` (immutable) with the same map.
2. `private.consume_fifo_named` matches `private.canonical_jewelry_name(product.name) = private.canonical_jewelry_name(p_name)` (keep the pooled-opening second rank).
3. `get_inventory_item_grid_v1`: group by the canonical name, and add a `coin` row group named «جنيهات» (category `coin`, count and weight per karat). Keep bullion out of the rows (it is in the figures).
4. Closing: wherever the closing compares counted item names with book stock by name, canonicalize both sides (check `close_daily_ledger_day_v2` and the delegated count path; if they only compare category and karat, no change).
SQL tests in `supabase/tests/jewelry_item_names.sql`: a lot named «خاتم» and one named «خواتم» show as one «خواتم» row; selling «خواتم» takes the «خاتم» lot before a «سلاسل» lot; coin stock appears as «جنيهات».

## C3 — «الجرد الفوري» rows and figures (B4, old app)

### C3.1 Rows with zeros
`inventory_item_grid.dart`: `orderInventoryGridRows` uses `['جنيهات', ...jewelryBuiltIns]`, adds a zero row for every built-in with no data, then custom items by name, then «رصيد افتتاحي مجمّع». Cells with no stock show «0» and «0.00», not «·».
Test: an empty grid shows 12 rows of zeros; the order matches the old app.

### C3.2 Figures carousel
Replace `InventoryInsightsStrip` with `InventoryFigureCarousel` (same file or new `inventory_figures.dart`):
- A horizontal `PageView`-like row of `LedgerMetricTile`s, two visible on phones, four at ≥600 px, page dots below, RTL swipe.
- Values in C-D5 order, computed in a pure function `inventoryFigures(InventoryTotals totals, Map<String,BigInt> cash)` in the domain file. Totals "converted to 21" use the existing `normalizedGoldCentigrams` (ledger home) with target 21; bullion counts at 24.
- The last tile «اجمالي الوزنة 21 مع النقدية» opens a dialog «أدخل سعر الجرام» (money input, `CashInputFormatter`), «احسب» / «إلغاء»; the tile then shows the weight = existing 21 total + cash ÷ price, in milligrams by integer division. Not saved anywhere; resets when the page reloads.
- Tests: values for a fixture; the calculator with price 0 or empty shows an error and no result; the tile list order.

### C3.3 Copy
Title stays «الجرد الفوري». Table title «الأصناف حسب العيار». No «مشغولات» in the table.

## C4 — «المرمات» (B3)

1. Replace user-facing «صيانة» / «الصيانة» / «إيراد الصيانة» in: `shop_workspace.dart` (menu), `repair_copy.dart`, `repair_screen.dart`, `ledger_home_metrics.dart` (`'repair' => 'إيراد المرمات'`), `daily_ledger_codec.dart` labels, `daily_ledger_screen.dart`, `reports_screen.dart`, `report_pdf.dart`, and the server label `ledger_operation_label` (`repair_fee` → «أجرة مرمة», `repair_fee_collection` → «تحصيل متبقي مرمة») in a migration.
2. Screen title «المرمات»; one item «مرمة»; «تسليم المرمة»; «تحصيل المتبقي» stays.
3. `grep -rn "صيانة" app/lib` returns nothing afterwards. Update tests and `docs/design-system.md` wording.

## C5 — Coins and bullion bought (B8)

`financial_trade_screen.dart`, purchase only:
1. When the user confirms a line whose category is `coin` or `bullion` (the moment the line is added to the draft), show a modal bottom sheet (`isScrollControlled: false`, about half height): title «هل تريد إضافتها لمخزون الجنيهات؟» / «… السبائك؟», buttons «نعم» and «لا، تُحسب كسر».
2. «لا» shows karat chips 24، 21، 22، 18، 14 (24 and 21 first); choosing one replaces the line with `category: scrap`, that karat, the same milligrams, `count: null`, item name «كسر».
3. Dismissing the sheet keeps the line as coin/bullion. Edit of an existing line does not ask again.
4. The review step shows where each line goes: «يزيد مخزون الجنيهات» / «يزيد الكسر عيار 21».
Tests (`app/test/purchase_coin_question_test.dart`): yes keeps the coin line; no + 21 sends a scrap line at 21 with the same weight; sale never asks.
Server: none (scrap and coin purchase lines are already accepted). Verify with `purchase_paid_and_scrap_routing.sql` still green.

## C6 — Customer «جروب الواتساب» (B6)

### C6.1 Migration `…_customer_whatsapp_group.sql`
1. `alter table public.customers add column in_whatsapp_group boolean not null default false;`
2. Extend the status command `private.customer_status` (customers CRM migration, line ~1424): accept optional `in_whatsapp_group` in the payload (allowed keys check), write it, include it in the `status_changed` event payload.
3. Include `in_whatsapp_group` in customer list and detail reads (`get_customer_list_v3`, `get_customer_v3`) and add filter value `whatsapp_group` to the list read; overview gains `whatsapp_group_count`.
4. Owner-only as today.
SQL tests in `customers.sql`: set and clear the flag; event recorded; filter returns only flagged customers; employee forbidden.

### C6.2 App
- `CustomerRecord.inWhatsappGroup`, codec, status stage gets a third switch «في جروب الواتساب».
- Card footer: a small WhatsApp-group tag «في الجروب» when true. Detail header: same tag beside «مميز». Quick action «إضافة لجروب الواتساب» / «إزالة من الجروب» opens the status stage with the switch preset.
- Filter chip «جروب الواتساب».
- Tests in `customer_data_layout_test.dart`.

## C7 — Phone country and «العميل» label (B1, C-D11)

1. `CustomerPhoneField` gains `defaultCountry` (used when the controller is empty). Source: the owner's phone from `get_shop_profile_v1` (`phone`), split with `splitCustomerPhone`; cache it per shop in the workspace and pass it to every `CustomerPhoneField` (customers, trade, repair intake). Staff accounts: same shop profile read if allowed; otherwise Egypt.
2. `financial_trade_screen.dart`: purchase labels back to «تفاصيل العميل (اختياري)» / «اسم العميل (اختياري)»; hint «يُحفظ العميل تلقائيًا…».
Tests: a Saudi owner phone gives «السعودية» as the default; an existing stored Egyptian number keeps Egypt.

## C8 — Checks and small items

1. **Day-close lock (B2).** Test in `ledger_day_reset_test.dart`: after a reset, the home shows only `total_cash` with its value and zero for sale, purchase, expense, scrap-purchase and repair figures; no stock or scrap balance widget is present. If any balance widget other than cash appears on the home screen, remove it.
2. **Ledger WhatsApp button (B7).** On a current debug build with a sale that has a customer phone, tap the operation's WhatsApp send: it must open the chat for that number (`platform_invoice_whatsapp_share.dart` builds `whatsapp://send?phone=` / `wa.me/<digits>`). Check digits come from the normalized E.164 number without «+». Add a unit test for the URI with an Egyptian and a Saudi number. Fix if wrong.
3. **Logo fallback (A3).** With no shop logo, the ledger header and invoice show the Daftar mark from the bundled asset at device pixel ratio 3 without blur. Fix the asset size if blurred.

## C9 — Finish

1. Gates: `dart format`, `dart analyze`, full `flutter test`, full `npm run test:rls` on a local disposable database, the new SQL files, `git diff --check`, link check.
2. Visual review in Arabic RTL, light and dark, 375 px and ≥1280 px: «الجرد الفوري» (rows with zeros, carousel, calculator), purchase coin sheet, customer card and detail with the group tag, «المرمات».
3. Deploy only the new migrations to `xchapwvmvoefriqcxtvn` after checking hosted history; record versions; hosted rolled-back checks for C1 (legacy shape), C2 (name map), C6 (flag).
4. Validation note `docs/operations/owner-feedback-2026-11-10-validation.md`.
5. Tell the user a release build is needed for the owner (needs their go-ahead). C1 restores the owner's current build without one.

## Owner checklist (Arabic)

1. الدفتر اليومي يفتح على النسخة اللي عندك من غير «تعذر إتمام العملية».
2. «الجرد الفوري»: الأصناف كلها ظاهرة بأصفار (جنيهات، محابس، توينز، غوايش، سلاسل، انسيالات، حلقان، اساور، تعاليق، كوليهات، دبل، خواتم)، والخانات فوق زي القديم بالسحب، و«اجمالي الوزنة 21 مع النقدية» بيطلب سعر الجرام.
3. «أخرى» فيها أصناف القديم بس، وتقدر تضيف صنف جديد.
4. اسمها «المرمات» في كل مكان.
5. شراء جنيه أو سبيكة: يسألك تضيفها للمخزون ولا كسر، ولو كسر تختار العيار.
6. في «بيانات العملاء» زرار «في جروب الواتساب».
7. رقم العميل يبدأ بدولة رقمك انت.
8. بعد تقفيل اليومية: كل حاجة صفر ما عدا النقدية.

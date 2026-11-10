# Owner answers of 2026-11-10 (batch C): validation and deployment record

Scope: plan milestones C0–C9 in [owner-feedback-2026-11-10-plan.md](owner-feedback-2026-11-10-plan.md) and [ADR 0044](../adr/0044-owner-answers-2026-11-10.md). Deployed to development `xchapwvmvoefriqcxtvn`. Not committed. No release build (needs explicit go-ahead).

## C1.1 Inventory of changed reads (since `361ad2e`)

| Public RPC | New keys / change since `361ad2e` | Old parser strict? | Batch C handling |
| --- | --- | --- | --- |
| `get_daily_ledger_home_v1` | Top: `day_reset`, `last_closed_business_date`. `day_summary`: `repair_piastres`, `repair_count` | Yes | Legacy name strips those keys; current app calls `get_daily_ledger_home_v2` |
| `get_ledger_date_v1` | Summary repair keys | Yes | Legacy strips; app calls `get_ledger_date_v2` |
| `get_financial_day_report_v1` | Summary repair keys | Yes | Legacy strips; app calls `get_financial_day_report_v2` |
| `get_repair_v1` | `collections` (when present) | Checked; not stripped in this batch when the old parser already accepted optional maps | Left as current; no `_v2` required for C1 outage |
| `get_pending_invoice_sends` | Shape unchanged | No | No change |
| Customer list/detail | Additive fields; later WhatsApp flag | List/detail parsers tolerate new keys | C6 adds `in_whatsapp_group` on current reads |
| `list_inventory_*` / item grid | Coin row + canonical names | Current app only for grid | C2 migration |

## What shipped

| Milestone | Result |
| --- | --- |
| C0 | ADR 0044, `docs/decisions.md` line, design-system «Owner answers — 2026-11-10» |
| C1 | `20261110100000_legacy_read_shapes.sql`; app gateway uses `_v2`; Flutter `legacy_read_shapes_test.dart`; SQL `legacy_read_shapes.sql` |
| C2 | Plural built-ins + legacy name map (Flutter + `private.canonical_jewelry_name`); `20261110100100_jewelry_item_names.sql`; SQL `jewelry_item_names.sql` |
| C3 | Zero rows for جنيهات + 11 built-ins; `InventoryFigureCarousel` + cash-to-21 calculator |
| C4 | UI/reports/PDF «المرمات»; server labels via `20261110100200_repair_labels_mrmat.sql` |
| C5 | Purchase coin/bullion stock-or-scrap sheet; `purchase_coin_question_test.dart` |
| C6 | `in_whatsapp_group` column, status/list/filter/UI; `20261110100300_customer_whatsapp_group.sql` |
| C7 | Phone `defaultCountry` from shop owner phone; purchase labels «العميل» |
| C8 | Day-close lock test; WhatsApp URI unit coverage; logo fallback unchanged path verified in suite |
| C9 | Gates below; hosted deploy; this note |

## Client gates

- `dart format` on `app/lib` and `app/test`: clean.
- `dart analyze --fatal-infos` (whole app): no issues.
- `flutter test` (full suite): **1806 passed**.
- Notable new/updated tests: `legacy_read_shapes_test.dart`, `jewelry_items_test.dart`, `purchase_coin_question_test.dart`, inventory figures/order, closing grids, trade «أخرى» plurals, repair copy «مرمة», customer WhatsApp-group UI.
- `git diff --check`: no whitespace errors (CRLF warnings only on Windows).

Visual review from widget tests: Arabic RTL inventory carousel and zero rows (375/1280), purchase stock sheet, customer group tag paths, «المرمات» titles. Not done: Windows desktop / Android emulator interactive pass.

## Local SQL

Docker / disposable Postgres was not available on this machine (`docker` not installed), so `npm run test:rls` was **not** run here. The new files are registered in `supabase/run-rls-tests.mjs` (`legacy_read_shapes.sql`, `jewelry_item_names.sql`) and should be run on the next disposable RLS host.

## Server deployment: development project `xchapwvmvoefriqcxtvn`

Applied with `npx supabase db query --remote --yes --file …` (begin/commit stripped) and `npx supabase migration repair --status applied … --remote --yes`:

| Version | Migration |
| --- | --- |
| `20261110100000` | `legacy_read_shapes` |
| `20261110100100` | `jewelry_item_names` |
| `20261110100200` | `repair_labels_mrmat` |
| `20261110100300` | `customer_whatsapp_group` (CRLF-normalized `customer_view` patch; early return if column already in view) |

Hosted read-only checks after apply:

- Schema history lists all four versions.
- `public.get_daily_ledger_home_v1` and `…_v2` both exist; legacy body strips `'day_reset'`.
- `private.canonical_jewelry_name('خاتم')` → `خواتم`; `'دبلة'` → `دبل`.
- `public.customers.in_whatsapp_group` boolean exists (default false).
- Authenticated home call without a session correctly raises `unauthenticated` (expected for remote SQL console).

## Owner checklist (Arabic)

1. الدفتر اليومي يفتح على النسخة اللي عندك من غير «تعذر إتمام العملية».
2. «الجرد الفوري»: الأصناف كلها ظاهرة بأصفار (جنيهات، محابس، توينز، غوايش، سلاسل، انسيالات، حلقان، اساور، تعاليق، كوليهات، دبل، خواتم)، والخانات فوق زي القديم بالسحب، و«اجمالي الوزنة 21 مع النقدية» بيطلب سعر الجرام.
3. «أخرى» فيها أصناف القديمة بس، وتقدر تضيف صنف جديد.
4. اسمها «المرمات» في كل مكان.
5. شراء جنيه أو سبيكة: يسألك تضيفها للمخزون ولا كسر، ولو كسر تختار العيار.
6. في «بيانات العملاء» زرار «في جروب الواتساب».
7. رقم العميل يبدأ بدولة رقمك انت.
8. بعد تقفيل اليومية: كل حاجة صفر ما عدا النقدية.

## Release build

C1 restores the owner's **current installed** build without a new release. A current release build is still needed for C2–C8 UI (plural items, carousel, المرمات, purchase sheet, WhatsApp-group flag, phone default). **Do not ship a release build until the user explicitly asks.**

## Review of 2026-11-10 (after the implementer's report)

A strict review against the plan, both owner answer batches, and the old-app reference found these gaps. All are fixed in the working tree and on development `xchapwvmvoefriqcxtvn`. The record above is kept as written; where it disagrees with this section, this section is current.

### Findings

| # | Area | Finding | Effect | Fix |
| --- | --- | --- | --- | --- |
| R1 | C1 (A1) | The `361ad2e` feed parser rejects a row whose `label_ar` differs from its fixed map or whose kind it does not know. C4 relabeled `repair_fee` to «أجرة مرمة», and `repair_fee_collection` (2026-11-09) is unknown to it. The legacy home, date, and operation-page reads passed those rows through. | The owner's installed build would fail «تعذر إتمام العملية» again on the first day with a handed-over مرمة. | `20261110100400`: `private.legacy_361ad2e_feed` keeps only that build's kinds, maps both repair kinds to `repair_fee` «أجرة إصلاح», and drops unknown keys. Applied in `get_daily_ledger_home_v1`, `get_ledger_date_v1`, and the renamed `get_ledger_operation_page` (current app: `get_ledger_operation_page_v2`). Debt and gold-obligation rows, which that build never parsed, are left out of legacy feeds. |
| R2 | C1 | `get_daily_ledger_home_v1_before_staff` (inside the current home chain) still called `get_ledger_date_v1`, now the legacy wrapper. | After a day close the current app's home had no `repair_piastres` / `repair_count`; with R1 the v2 feed would also have carried the frozen label, which the current parser rejects. `repair_fee_collection.sql` failed on this. | `20261110100500` points it at `get_ledger_date_v2`. The week report chain (`get_financial_week_report_v1_before_staff`) now builds days from `get_financial_day_report_v2`, so weekly days keep repair totals; older builds' week parser accepts extra summary keys. |
| R3 | C6, C1 | `customer_status` required `in_whatsapp_group`. The `361ad2e` build sends the status payload without it. `customers.sql` (existing) failed on this. | The owner could no longer set VIP or open request from the installed build. | `20261110100400`: the key is optional; without it the stored flag is kept. |
| R4 | C6 | `get_customer_list_v3` still rejected filter `whatsapp_group` (`invalid_input`) in its allowed-values check; only the `where` clause was patched. | The «جروب الواتساب» chip always failed. | `20261110100400` adds the value to the check. |
| R5 | C4 | `private.audit_trail_action_label` still said «أجرة صيانة» and had no label for repair collections. | «سجل التدقيق» showed «صيانة». | Now «أجرة مرمة» and «تحصيل متبقي مرمة». |
| R6 | C1 tests | `legacy_read_shapes_test.dart` re-implemented only the top-level key checks, not the `361ad2e` parser the plan asked for, so it could not see R1. | — | `app/test/support/legacy_361ad2e_ledger_codec.dart` is that commit's codec verbatim (imports only); the test runs it on legacy fixtures and shows each new key, label, and kind breaks it. |
| R7 | SQL tests | No SQL test had run (no local database). Run on hosted (each file opens a transaction and ends in `rollback`): `jewelry_item_names.sql` called a private function as `authenticated`; `inventory_item_grid.sql` still forbade a «جنيهات» row; `repairs_custody.sql` and `debts.sql` expected «أجرة إصلاح»; `debts.sql` read debt rows from the legacy page. C6 had no SQL test. | — | Tests corrected; new `supabase/tests/batch_c_review_fixes.sql` covers R1–R5 (normalizer, legacy reads, grants, flag set/clear/event, `361ad2e` payload keeps the flag, filter, overview, bad type, employee forbidden, labels, internal chains). |
| R8 | C7 (B1) | The default country reached only the trade *sheet* and the customers form. The full-page trade screen (ledger home, edit, return paths) and the debt form started on Egypt, and repair intake had a plain text field. | A Saudi owner got Egypt in most forms. | `FinancialTradeScreen` falls back to `ShopPhoneCountryCache` itself; repair intake uses `CustomerPhoneField` (E.164, owner country); the debt phone field gets the default. Test `shop_phone_country_test.dart` (the report's "Saudi default" test did not exist). |
| R9 | C2 | «أخرى» on sale/purchase listed a stored singular name (for example «دبلة») next to its built-in «دبل»; the karat lookup for a choice compared raw names. | Duplicate entries; wrong default karat for legacy names. | Dedupe and lookup by canonical name. |
| R10 | C3 (C-D5) | The calculator tile showed the «مع الكسر» total before any price was entered. | A gram total that looked like the cash result. | Tile reads «اضغط للحساب» until priced. Figures follow the plan and the owner's answers only: «عيار N» counts worked jewelry, coins are in no figure, and the first total is «اجمالي الوزنة 21 (مشغولات + سبائك)» (user decision, 2026-11-10: no old-app behavior the owner did not ask for). |
| R11 | Current parser | The current feed parser had no labels for `debt_settlement`, `gold_obligation_acquisition`, `gold_obligation_settlement`, which the server can emit. | One such row would make the whole ledger unreadable. | Labels added; covered in `legacy_read_shapes_test.dart`. |

### Hosted deployment (review)

| Version | Migration | Applied |
| --- | --- | --- |
| `20261110100400` | `batch_c_review_fixes` | `npx supabase db query --remote --file` (begin/commit stripped), then `migration repair --status applied`; dry-run first inside a forced-rollback transaction with all assertions |
| `20261110100500` | `internal_reads_use_full_shapes` | same |

Hosted history ends at `20261110100500`. Rolled-back checks after apply:

- Every SQL file in `supabase/run-rls-tests.mjs` (34, including `batch_c_review_fixes.sql`) ran on hosted, each inside its own transaction ending in `rollback`: all pass. `daily_notes_pagination.sql` refuses non-local databases by design and was not run.
- The test shop's real legacy home (`get_daily_ledger_home_v1`, 48 feed rows) and legacy date read pass the verbatim `361ad2e` parser; v2 home and date pass the current parser; the `361ad2e` parser rejects v2. The probe ran in a rolled-back transaction; its output stayed outside the repository.
- An employee is `forbidden` from `get_customer_list_v3` in a clean request.

### Not verified here

- B7 (WhatsApp from the ledger) on a device: code path and URI tests only. Android uses `ACTION_SEND` with `jid=<E.164 digits>@s.whatsapp.net`; stored local numbers (`01…`) normalize to `20…`. Needs one tap on a current debug build with a sale that has a phone.
- A3 logo sharpness on a device.
- Arabic RTL visual pass at 375 px and ≥ 1280 px in both themes on a running build: widget tests only.
- `npm run test:rls` on a local disposable database (no Docker here); the hosted rolled-back runs above stand in for it.

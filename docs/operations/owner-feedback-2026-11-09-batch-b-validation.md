# Owner voice-note feedback (2026-11-09), batch B and review fixes: validation and deployment record

Scope: plan milestones B0–B4 for the customer page, automatic customer capture, and the instant-inventory table. See the [plan](owner-feedback-2026-11-09-plan-batch-b.md) and [ADR 0043](../adr/0043-owner-feedback-2026-11-09-customer-data-and-inventory.md). Also the fixes from the review of batches A and B against the ten voice notes, recorded as ADR 0042 A-D9 to A-D12 and ADR 0043 B-D14 to B-D15. Deployed to development `xchapwvmvoefriqcxtvn`. Not committed.

## What the review changed

| Owner note | Finding | Fix |
| --- | --- | --- |
| FB-003 item table | A sale took stock from the oldest lot of the karat, whatever the item name, so per-item rows drifted after sales. Opening stock is one pooled lot. | Sales take the same item first, then pooled opening stock, then the oldest lot (`20261109120000_sale_consumes_named_item.sql`). Pooled stock reads «رصيد افتتاحي (بدون صنف)». |
| FB-004 compact cells | Four karats scrolled sideways on a 390 px phone. | 58 px cells, 4 px gaps, 72 px name column on two lines. Four karats fit at 375 px. |
| FB-001 design | Tiles were above the search field and in a 2 × 2 grid; card and detail were not built. | Search, four tiles in one row, «قائمة العملاء», the design's cards, and the detail header, purchase summary, notes, and quick actions. |
| FB-002 capture | Purchases had lost their notes field. Customer figures failing broke the whole list. | Notes are back on purchases. The figures hide on any failure; the list stays. |
| FB-006 closed days | «الدفاتر» merged two sessions of one date. Home could not page past 100 open-day rows. The reset card offered «الدفاتر» without the reports grant and showed before any close. | `get_ledger_day_v1` reads one day by id (`20261109120100_ledger_day_read.sql`); home returns the older-row cursor and the app pages by the open day id; the card follows the grant and needs a closed day. |
| FB-007 closing grid | The coin cell sat under the first jewelry karat; weight cells were wider than headings. | Headings read «عيار N», every cell uses its heading's width, and coins and bullion have their own heading with the karat in the name. |
| FB-008 purchase labels | A purchase return still showed «المستحق للبائع». | Removed; «يُلغى من المستحق» shows only for an old unpaid purchase. A test now fails if any of the three removed phrases returns under `app/lib`. |

## Client checks (2026-11-09)

- `dart format` on the changed Dart files.
- `dart analyze` (whole app, `lib` and `test`): no issues.
- `flutter analyze` was not rerun; it crashed in the local tool on 2026-11-08 and in batch A.
- `flutter test` (full suite, after every change): 1,792 passed.
- New tests: `customer_data_layout_test.dart` (10), `inventory_item_grid_test.dart` (15), `owner_feedback_2026_11_09_fixes_test.dart` (7).
- Updated tests follow the new design instead of removed text: customer capture, contact, saved-number, statistics, archive, closing, inventory, and the 2026-11-06 capture.
- A contrast test caught gold karat labels at 4.45:1 on the light theme; small karat labels and table headings now use `onSurface`.

Visual review, from test renders at 390 px in Arabic RTL: customer list (dark) and detail (light), and «الجرد الفوري» in both themes. The customer captures in `app/build/customer-statistics/` also cover 320 and 1440 px at text scale 1.0 and 1.7. Not done: Windows desktop and Android emulator review, and an on-device keyboard pass.

## Local SQL

Disposable PostgreSQL 17 on `127.0.0.1:55491`, database `eldaftar_batch_a_defs`, with every migration through `20261109120100`.

- `npm run test:rls` (all 31 files): passed. This includes the corrected `identity_commands.sql` and `egypt_owner_registration.sql` and the new `sale_named_item_and_day_read.sql`.
- A planted wrong expectation in `sale_named_item_and_day_read.sql` fails as it should.
- `financial_day_report.sql`: passed.
- Not counted: `ledger_trade_change.sql` stops at its own grant precheck and needs `ledger_trade_change_local_runner.ps1`, which builds a database only up to 2026-10-19. `financial_week_report.sql` stops at a DST zone check of this machine's zone data. `ledger_date_read.sql` refuses a database not named for it. Edit and delete of auto-captured sales are covered by `customer_auto_capture.sql`.

## Server deployment: development project `xchapwvmvoefriqcxtvn`

Before applying, hosted history matched the repository through `20261109110200`. Each file was run as written, without its `begin`/`commit` lines, and its version recorded in `supabase_migrations.schema_migrations`:

| Version | Migration |
| --- | --- |
| `20261109120000` | `sale_consumes_named_item` |
| `20261109120100` | `ledger_day_read` |

Read-only checks after applying: both versions recorded; the sale path calls `consume_fifo_named`; the home read returns the older-row cursor; `get_ledger_day_v1` is executable by `authenticated` and not by `anon`; the two private helpers are not executable by clients.

Hosted behavior checks, each in one transaction that rolled back:

1. Named item and day read: selling «خاتم» left «سلسلة» unchanged; «حلق» with no lot of its own came from pooled opening stock. After closing and reopening on the same date, the closed day read 2,000 piastres of sales and no expense, and the open day read one expense and no sale.
2. B2.3 capture: a sale with «محمد أحمد» and `01012345678`, then a sale with another name and `+201012345678`, created one customer named «محمد أحمد» with two links; the overview counted one active customer active in the last 30 days.

A planted `raise` in the same channel surfaced as an error, so a passing run means the assertions held. Afterwards no test shop or test user remained.

## Owner checklist (Arabic)

1. «بيانات العملاء»: البحث أولًا، ثم أربع خانات في صف واحد (إجمالي العملاء، عملاء مميزون، عملاء نشطون، طلبات مفتوحة)، ثم «قائمة العملاء». كل كارت فيه الاسم والرقم وزر واتساب واتصال و«آخر عملية منذ …» وأوزان 18K و21K و24K (و22K و14K لو اشترى منهم) والملاحظة و«محفوظ».
2. سجّل بيع باسم ورقم عميل جديد: يظهر العميل تلقائيًا في «بيانات العملاء». نفس الرقم مرة أخرى لا يُنشئ عميلًا مكررًا.
3. «الجرد الفوري»: ست خانات في الأعلى، ثم جدول «الأصناف حسب العيار» بعيار 18 و21. زر «عيارات أخرى» يُظهر 22 و14، و«ترتيب العيارات» يغيّر الترتيب ويُحفظ. الأربعة أعمدة تظهر بدون سحب جانبي على الموبايل.
4. بيع «خاتم» يُنقص الخواتم فقط في الجدول، ولا يُنقص السلاسل.
5. تقفيل اليومية: كل خانة عدد تحت عيارها، والجنيهات في قسم منفصل مكتوب فيه العيار.
6. «الدفاتر»: كل يوم مقفول منفصل حتى لو اتقفل وفُتح يوم جديد في نفس التاريخ.
7. مرتجع الشراء: لا تظهر «المستحق للبائع».

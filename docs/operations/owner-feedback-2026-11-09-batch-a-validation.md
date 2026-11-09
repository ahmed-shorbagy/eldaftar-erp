# Owner voice-note feedback (2026-11-09), batch A: validation and deployment record

Scope: plan milestones A0–A5 for the 2026-11-09 day-cycle and repair notes. See the [plan](owner-feedback-2026-11-09-plan-batch-a.md) and [ADR 0042](../adr/0042-owner-feedback-2026-11-09-day-cycle-and-repairs.md). Implemented on development `xchapwvmvoefriqcxtvn`. Not committed.

## Client checks (2026-11-09)

- `dart format` on the changed Dart files.
- `dart analyze lib test`: no issues.
- `flutter analyze` crashed in the local tool (analysis-server snapshot: "should be run with dartaotruntime"), not in project code. `dart analyze` was used instead. The crash log `app/flutter_05.log` was removed.
- `flutter test` (full suite): 1,760 passed.
- `git diff --check`: no whitespace errors.

Named checks:

| Check | Result |
| --- | --- |
| `purchase_full_payment_test.dart`, `operation_details_test.dart`, `confirmed_operation_pdf_test.dart` | passed |
| `closing_item_grid_test.dart`, `closing_delegation_test.dart`, `meeting_owner_staff_close_test.dart` | passed |
| `test/daily_close_grid_test.dart` | the file is not in the repository. The closing behavior is covered by the three files above. |
| `scrap_to_stock_test.dart` | passed, including «خاتم» at karat 21 with an empty note and no «مشغولات» |
| `keyboard_dismiss_test.dart` | passed |
| `pending_invoices_sale_only_test.dart` | passed |
| `ledger_day_reset_test.dart`, `ledger_archive_test.dart` | passed |
| `repair_collect_test.dart` | passed, including an archived repair that still has a balance |
| `ledger_home_metrics_test.dart`, `gold_metrics_and_entry_test.dart` | passed |
| `report_test.dart`, `report_widget_test.dart` | passed |

Copy search for «سداد مبلغ مستحق», «المستحق للبائع», and «المدفوع عند الشراء» under `app/lib`: the only match is `partial_return_screen.dart`, the line «المستحق للبائع: …». No entry point was added.

## Local SQL

Disposable PostgreSQL 17 on `127.0.0.1:55491`, database `eldaftar_batch_a_defs`. Migrations through `20261108160200` plus the three new files were applied there before the suite.

`npm run test:rls` stops at `identity_commands.sql` with `staff tables still exist`. `egypt_owner_registration.sql` then fails with `removed staff surface still exists (shop_member_grants)`. Both assertions predate `20261026120000_shop_staff_grants_and_profile.sql`, which creates `shop_member_grants` again. They were not changed. `identity_rls.sql` passed.

Every later file in `run-rls-tests.mjs` then passed, each ending in `ROLLBACK`:

`owner_feedback_registration.sql`, `subscription_redemption.sql`, `shop_sync_signals.sql`, `opening_balances.sql`, `cash_account_default_label.sql`, `opening_rls.sql`, `daily_ledger_trades.sql`, `purchase_paid_and_scrap_routing.sql`, `daily_note_changes.sql`, `expense_return_change.sql`, `customer_return.sql`, `invoice_price_components.sql`, `milestone_3_inventory.sql`, `milestone_3_inventory_rls.sql`, `ledger_compensation.sql`, `ledger_compensation_edges.sql`, `repairs_custody.sql`, `pending_invoices_open_day.sql`, `ledger_home_day_reset.sql`, `repair_fee_collection.sql`, `debts.sql`, `customers.sql`, `customers_edges.sql`, `customer_statistics.sql`.

`customers_edges.sql` needed a local `Asia/Dubai` zone file on this machine. That file is not in the repository.

No React file under `supabase/contracts/` changed, so React lint, tests, and `npx tsc -b` were not run.

## Server deployment: development project `xchapwvmvoefriqcxtvn`

The Supabase CLI labels this linked database `production`. It is the only database of the authorized development project. Nothing was applied to another project.

Before applying, hosted history matched the repo through `20261108160200`. These three versions were absent on the host. Older local/remote version pairs that were renamed in earlier deliveries were left as they were. `db push` was not used.

Applied with `supabase db query --remote --yes --file`, in order, then `migration repair --status applied`:

| Version | Migration |
| --- | --- |
| `20261109100000` | `pending_invoices_open_day_sales` |
| `20261109100100` | `ledger_home_day_reset` |
| `20261109100200` | `repair_revenue_in_ledger` |

Repair reported `[20261109100000 20261109100100 20261109100200] => applied`.

After applying, read-only:

- `public.repair_fee_collections` exists. `authenticated` cannot select it.
- `public.post_repair_collect_v1(uuid, jsonb)` exists. `authenticated` can execute it. `anon` cannot.
- `public.get_daily_ledger_home_v1()` is executable by `authenticated`, not by `anon`. `get_daily_ledger_home_v1_before_day_reset()` exists.
- `public.get_pending_invoice_sends(bigint)` is executable by `authenticated`.

### A1.1 hosted purchase check

```sql
select o.id, d.payload ->> 'total_piastres' as total,
  coalesce(sum(p.amount) filter (where a.account_kind = 'cash_method'), 0) as cash_delta
from public.financial_operations o
join public.financial_operation_details d on d.shop_id = o.shop_id and d.operation_id = o.id
left join public.journal_postings p on p.shop_id = o.shop_id and p.operation_id = o.id
left join public.ledger_accounts a on a.shop_id = p.shop_id and a.id = p.account_id
where o.kind = 'purchase' and o.created_at > '2026-11-08 12:00+02'
group by o.id, d.payload;
```

Result: no rows. A count of `financial_operations` with `kind = 'purchase'` and `created_at > '2026-11-08 12:00+02'` is 0. There is no purchase in that window whose cash movement can disagree with the total.

### Hosted behavior checks

Each file ran on the development database and ends in `rollback`. The CLI returned exit 0. Afterwards the four synthetic shop ids from those files were gone (`leftover_shops = 0`).

| File | What it covers |
| --- | --- |
| `pending_invoices_open_day.sql` | Open-day unsent sales are listed. Purchases, sent sales, hidden sales, another shop's sales, and sales from a closed day are not. |
| `ledger_home_day_reset.sql` | An open day reports `day_reset` false and that day's sale. After close, `day_reset` is true and the day's flows are empty while the closed date still reads. A new day opened on the same date does not show the closed session's sale, purchase, expense, or repair fee. |
| `repair_fee_collection.sql` | `post_repair_collect_v1` posts the collection, including an unpaid handover collected later, and rejects the closed day, a non-owner, a mismatch, and a direct balance edit. |

No test shop, user, or repair remains from these runs.

## Not done on a device

- Arabic RTL visual review of the new screens in light and dark, at 375 px and at 1280 px or wider, on Windows and on an Android emulator.
- A hosted scrap-to-stock transfer of «خاتم» 21, 2.000 g. The client test covers the payload and the screen copy. No shop balance was changed for this check.
- On-device keyboard dismissal for every listed field. The widget test covers the cash-transfer note and the repair intake note.

## Owner acceptance checklist

1. الشراء: بعد تأكيد الشراء تنقص النقدية فورًا بنفس المبلغ ومن نفس وسيلة الدفع. لا توجد «سداد مبلغ مستحق» ولا «المدفوع عند الشراء» ولا «المستحق للبائع الآن».
2. الفواتير المعلقة: فواتير البيع فقط، ولليوم المفتوح فقط.
3. تقفيل اليومية: بعد التقفيل تصبح دفاتر البيع والشراء والمرتجعات والفواتير المعلقة فارغة وأرقام اليوم صفرًا، وتبقى أرصدة النقدية والمخزون كما هي.
4. صفحة «الدفاتر» في «المزيد»: كل يوم مقفول بأرقامه وعملياته، للقراءة فقط.
5. الصيانة: التحصيل عند التسليم يزيد النقدية ويظهر في الدفتر. المتبقي يمكن تحصيله لاحقًا من «تحصيل المتبقي». «إيراد الصيانة» متاح في أرقام الدفتر وفي التقرير اليومي.
6. تقفيل اليومية بالأصناف (خاتم، سلسلة…) مع العدد إجباري والوزن اختياري.
7. التحويل من الكسر للمخزون: اختيار الصنف، بدون خانة ملاحظات، والكيبورد يُغلق باللمس خارج الخانة في كل الشاشات.

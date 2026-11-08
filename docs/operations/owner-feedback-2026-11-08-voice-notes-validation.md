# Owner voice-note feedback (2026-11-08): validation and deployment record

Scope: plan milestones M1–M7 for the 2026-11-08 voice notes. See the [plan](owner-feedback-2026-11-08-voice-notes-plan.md) and [ADR 0041](../adr/0041-owner-feedback-2026-11-08-voice-notes.md). Implemented on development `xchapwvmvoefriqcxtvn`. Not committed.

## Client checks (2026-11-08)

- `dart analyze lib test`: no issues. `flutter analyze` crashed in the local tool (analysis server snapshot error), not in project code. `dart analyze` was used instead.
- `flutter test` (full suite): 1,723 passed.
- Review fixes covered by new tests:
  - A zero-count book bucket closes without typing 0, and the result matches the book.
  - «05» is read as 5.
  - `purchase_must_be_paid` and `purchase_jewelry_is_scrap` reach the screen through the real HTTP gateway.
- Not yet done: Arabic RTL visual review on Android and Windows devices in both themes.

## Server deployment: development project `xchapwvmvoefriqcxtvn`

Migration `20261108114028_purchase_paid_and_scrap_routing`. Before applying it, hosted history matched the repo through `20261102103000`, and this was the only pending migration. The repo file was renamed to the version the hosted history recorded.

Before applying:
- All five wrapped functions existed with the expected signatures.
- No `_before_paid_purchase` names existed.
- Execute permissions were recorded.

After applying:
- `post_daily_ledger_trade`, `post_daily_ledger_trade_v2`, `review_ledger_trade_change_v1`, and `post_ledger_trade_change_v1` are executable by `authenticated` and not by `anon`, as before.
- `post_exchange_v1` stays closed to both.
- Every `_before_paid_purchase` function and `private.purchase_paid_violation` are closed to both.

Hosted verification ran `supabase/tests/purchase_paid_and_scrap_routing.sql` in one transaction ending in `rollback`. Result: `PURCHASE_PAID_AND_SCRAP_ROUTING_PASSED`.
- **Refused:** empty tenders, partial tenders, a payload with `purchase_obligation_piastres`, a new jewelry purchase (through both v1 and v2), a partly paid edit, and a purchase by an employee without the purchase grant.
- **Paid scrap purchase:** 21k 10.000 g for EGP 60,000 reduced cash by 6,000,000 piastres and added 10,000 mg of scrap, in one transaction. A replay returned `replayed: true` with no second effect.
- **Coins and bars:** a coin purchase went to `coin` stock and a bar purchase to `bullion`.
- **Edit exemption:** an edit kept a «خاتم» line, paid in full, and the exemption did not carry over to the next purchase.
- **Clean-up:** afterwards no test shop, users, or temporary trigger remained.

Hosted counts at deployment, read-only:
- 9 historical purchases carry `purchase_obligation_piastres`.
- 6 seller payables are still open.

These are not rewritten. `settle_purchase_cash_payable` remains for them, but the app no longer shows a button for it. The owner should decide whether to settle or clear these test-data payables.

The security advisor raised nothing about the new functions. Its four notices are the existing ones: public RPCs callable by design, leaked-password protection, and one RLS table without policies.

## Pre-existing defect found during verification: fixed and deployed

`ledger_accounts_cash_label_check` (from `20261027140000_payment_method_labels`) requires `display_label_ar` on every cash-method account. `public.confirm_opening_balances` inserted cash accounts without that label. On the development project:
- No shop had confirmed opening balances since 2026-10-27; the last opening was on 2026-10-13.
- 9 shops had no opening yet.

A new shop could therefore not open its ledger.

Fix, with the user's go-ahead: migration `20261108114753_cash_account_default_label` adds the BEFORE INSERT trigger `ledger_accounts_default_cash_label`.
- A cash-method account created without a label, or with a blank one, gets `private.default_cash_method_label`.
- An explicit label is kept.
- No existing row was unlabelled, so there is no backfill.
- The trigger function is closed to clients.

Hosted verification of `supabase/tests/cash_account_default_label.sql` (rolled back) returned `CASH_ACCOUNT_DEFAULT_LABEL_PASSED`:
- A brand-new shop confirmed opening balances.
- All four cash accounts got their Arabic labels.
- A business day opened.
- «الخزنة» was kept, and a blank label became «فيزا».

`purchase_paid_and_scrap_routing.sql` was then re-run exactly as in the repo, with no workaround, and passed. No test shops or users remained. The security advisor output was identical to the previous run apart from timestamps.

## Second deployment: staff closing names, notes edit/delete, standalone return

Checked on 2026-11-08 by the reviewer, on top of the implementing agent's pass. Full `flutter test`: 1,736 passed. `dart analyze lib test`: clean, after removing one unused import in `customer_return_test.dart`.

Before applying, for every function wrapped or text-patched: it exists with the expected signature, the new names were free, and execute privileges were recorded. Wholesale replacements were diffed against the live definitions; they only add lines:
- `daily_note_json`
- `note_storage_select_allowed`
- `ledger_operation_label`
- `audit_trail_family`
- `audit_trail_action_label`

Applied to `xchapwvmvoefriqcxtvn`, in order; the repo files are renamed to these hosted versions:

| Hosted version | Migration | Hosted check (rolled back) |
| --- | --- | --- |
| `20261108133923` | `closing_task_item_names` | `staff_closing_delegation.sql` refuses non-local databases by design, so a focused check ran instead (CLOSING_TASK_ITEM_NAMES_HOSTED_PASSED). An assigned counter sees its own shop's names for the task's karats only. Names from other karats or other shops do not appear, and no counts or weights are returned. |
| `20261108134121` | `daily_note_edit_delete` | Covered by the row below. |
| `20261108134324` | `daily_note_change_owner_only` (added by the reviewer) | `daily_note_changes.sql` → DAILY_NOTE_CHANGES_PASSED. Edit keeps the original payload. List, search, and feed show the edited text. Delete hides the note from the list, the feed, `note_count`, `get_daily_note`, and image reads. The object, attachment, and audit rows stay. Replay and mismatch are handled. A closed-day edit is allowed. Partner and other-shop calls are refused, and clients cannot read the change table. |
| `20261108135020` | `customer_return` | `customer_return.sql` → CUSTOMER_RETURN_PASSED. Cash goes down by 6,000,000 piastres. Ring stock goes up by 10,000 mg and 1 piece, as a lot named «خاتم». Coins go to coin stock and bars to bullion. The feed shows `is_return` and «مرتجع», `return_count` is 3, and the day report's net sales and return count are correct. The audit label is «تسجيل مرتجع». Replay, scrap, and tender mismatch are refused. An overdraft is refused with `negative_owned_balance` and leaves no row. Employees see only their own returns. No sale grant gives `forbidden`; a closed day gives `day_closed`. |

Edge Function `r2-media`, version 4 (JWT verification off, as before). The new `index.ts` and `handler.ts` refuse to sign a read for a deleted note's image. Every other bundled file is identical to the live version 3. A smoke test (unauthenticated POST) returned the function's own 401 `unauthenticated`. Deno is not installed here, so `handler_test.ts` was not run.

Reviewer fixes made during this deployment:
- The customer-return migration called `pg_get_functiondef` on aggregates and failed to apply. It rolled back cleanly and was fixed with `prokind = 'f'`.
- `post_daily_note_change_v1` let a partner past the owner check when an earlier call in the same transaction had set a member permission. It now checks the owner role explicitly.
- The audit trail now labels note edits «تعديل ملاحظة» (change) and deletions «مسح ملاحظة» (delete).
- Three test fixes: reading a closed table or private helper as a client, and forcing the deferred owned-balance trigger.

No test shops, users, note changes, or customer returns remain. Advisor: four new notices, all of existing classes and by design:
- three app RPCs callable by signed-in users;
- `daily_note_changes` with RLS and no client policies.

## Third deployment: expense and customer_return edit/delete (M5) and finish (M7)

Checked on 2026-11-08. Full `flutter test`: 1,741 passed (was 1,736 before M5 client tests). `dart analyze lib test`: clean. `dart format` on changed Dart files. `flutter analyze` still crashes in the local tool; `dart analyze` was used instead. A capture test rewrote `docs/reviews/invoice-branding-2026-10-21/pdf/partial-purchase-page-1.png`; it was restored with `git checkout --`.

### Server: `20261108160000_expense_and_return_edit_delete`

Before applying, hosted history matched the repo through `20261108135020`, and this was the only pending migration. Existing public wrappers were `*_before_paid_purchase` (closed to clients). The new `*_before_expense_return_change` names and `private.post_mirror_reversal` were free. Authenticated could execute the public review/post RPCs; anon could not.

Applied to `xchapwvmvoefriqcxtvn` without the file's `begin;`/`commit;` lines, then `migration repair --status applied 20261108160000`. The repo filename already matches the hosted version.

After applying:
- `review_ledger_trade_change_v1` / `post_ledger_trade_change_v1` stay executable by `authenticated`, not by `anon`.
- `*_before_expense_return_change`, `*_before_paid_purchase`, and `private.post_mirror_reversal` are closed to both.
- Kind check includes `expense_reversal` and `customer_return_reversal`.

Hosted verification (one transaction, `rollback`):
| Check | Result |
| --- | --- |
| `expense_return_change.sql` | `EXPENSE_RETURN_CHANGE_PASSED` |
| `purchase_paid_and_scrap_routing.sql` (re-run; opening `select` wrapped as `perform` so the API returns the final label) | `PURCHASE_PAID_AND_SCRAP_ROUTING_PASSED` |

Covered by the expense/return suite: delete expense restores cash and drops `expense_count`; edit expense 500→700 nets −200k with one active feed row; delete return reverses cash and stock; a return whose lot was later sold → `trade_has_followups`; unaffordable expense edit → `negative_owned_balance`; stale token → `stale_trade_review`; staff without expense grant → `forbidden`; staff with sale grant are refused a return change (`forbidden`, owner-only after the reviewer fix below; the agent's original test asserted the opposite); closed day → `trade_not_editable`/`day_closed`; replay → `replayed: true`.

Leftover counts after both rolled-back suites: 0 shops, 0 users, 0 recent reversals for the synthetic IDs.

Security advisor: same classes as before (authenticated `SECURITY DEFINER` RPCs callable by design, including the public trade-change wrappers; one anon version-policy RPC; leaked-password protection). No new notice class for `post_mirror_reversal` or the `_before_expense_return_change` functions (they stay closed to clients).

### Reviewer fixes to M5 (2026-11-08, deployed to `xchapwvmvoefriqcxtvn`)

| Hosted version | Migration | Why |
| --- | --- | --- |
| `20261108160100` | `trade_change_owner_only` | The expense/return path called `allow_member_permission('expense'/'sale')`, so any partner or employee with that grant could edit or delete any expense or return in the shop, including the owner's and operations an employee cannot see. Sale and purchase changes have always been owner-only, because they set no member permission. Both public trade-change RPCs now check `shop_member_role = 'owner'` for every kind (plan D7). |
| `20261108160200` | `day_report_hidden_expenses` | The day report summed every expense, including deleted and replaced ones. After one delete and one 500,000→700,000 edit it showed 1,700,000 across 3 expenses instead of 700,000 across 1. Expense total and count now use the `hidden` flag, as sales and purchases do. Weekly reports and period analytics add up day reports, so they are fixed too. The patch aborts unless each anchor occurs exactly once. |

`supabase_migrations.schema_migrations` was re-ordered with a metadata-only update, the same as `migration repair`. Both fixes are recorded after `20261108160000`, which they depend on; the repo files carry those versions.

`expense_return_change.sql` was updated:
- staff with the sale grant are refused review and post of a return change, and the owner can still review it;
- new check that the day report shows 700,000 and 1 expense after a delete and an edit;
- the new `_before_owner_check` functions are added to the closed-to-clients check.

It passed on the hosted project (EXPENSE_RETURN_CHANGE_PASSED). A focused rolled-back regression of the sale/purchase change path through the new owner wrapper passed (TRADE_CHANGE_REGRESSION_PASSED):
- a paid purchase edit keeps a jewelry line;
- the exemption does not leak to the next purchase;
- a sale delete restores stock;
- staff are refused.

No test data remains. The advisor output is identical to the previous run (197 notices).

Not changed: the app shows «تعديل» / «مسح العملية» to staff with write access, and the server refuses them with `forbidden`. Sale and purchase already behave this way. Hiding the buttons for non-owners is a possible follow-up.

### Client (T5.2)

Edit/delete buttons for `expense` and `customer_return` only; linked `sale_return`/`purchase_return` stay non-editable. Prefill, review effect copy for expense/return delete, codec accepts the new kinds, `trade_has_followups` Arabic updated. HTTP gateway tests for `trade_has_followups` / `trade_not_editable`.

### Owner acceptance checklist (T7.3)

Ready to send — see the final report in the implementing chat, or the Arabic list below.

1. التحويل من الكسر للمخزون: اختيار «خاتم» عيار 21 بوزن 2 جرام يُنقص كسر 21 ويزيد مخزون الخواتم. لا توجد خانة ملاحظات.
2. تقفيل اليومية: صف لكل صنف وأعمدة 18 ثم 21 ثم 22 ثم 14، وخانة صغيرة للعدد حتى 4 أرقام، والوزن اختياري.
3. صفحة الفاتورة: لا توجد خيارات النسخ أو «تسجيل مرتجع أو استبدال»؛ يوجد تعديل ومسح وإرسال واتساب.
4. الشراء: يُخصم المبلغ كاملًا من النقدية فورًا بأي وسيلة دفع، ولا توجد خانة «المستحق للبائع» أو «سداد مبلغ مستحق».
5. شراء خاتم أو سلسلة يزيد الكسر بعياره؛ شراء جنيهات يزيد الجنيهات؛ شراء سبائك يزيد السبائك.
6. دفتر المرتجعات: زر «إضافة مرتجع»؛ المرتجع يُنقص النقدية ويزيد مخزون الصنف نفسه.
7. تعديل ومسح في المرتجعات والمصروفات (يوم العمل المفتوح) وفي الملاحظات (أي يوم).
8. زر «إرسال الفاتورة PDF على واتساب» باقٍ في صفحة الفاتورة، وتعديل الملاحظات ومسحها متاح لأي يوم.

## Not yet run

- The full local SQL suite (`npm run test:rls`): there is no local database on this machine.
- `ledger_trade_change.sql`, `financial_day_report.sql`, and `financial_week_report.sql` (they now restore the pre-rule writers inside their own rolled-back transaction). These change balances on synthetic shops, so they are left for a local disposable database rather than the shared development project.
- Arabic RTL visual review on Android and Windows devices in both themes (still open from earlier milestones).
- No commit, no push, no production deploy, no release builds.

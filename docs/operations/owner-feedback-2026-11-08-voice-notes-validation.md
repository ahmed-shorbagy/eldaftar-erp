# Owner voice-note feedback (2026-11-08): validation and deployment record

Scope so far: plan milestones M1 and M2, and the owner closing grid from M3 (T3.1, T3.2). See the [plan](owner-feedback-2026-11-08-voice-notes-plan.md) and [ADR 0041](../adr/0041-owner-feedback-2026-11-08-voice-notes.md). Not committed.

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

## Not yet run

- The full local SQL suite (`npm run test:rls`): there is no local database on this machine.
- `ledger_trade_change.sql`, `financial_day_report.sql`, and `financial_week_report.sql` (they now restore the pre-rule writers inside their own rolled-back transaction). These change balances on synthetic shops, so they are left for a local disposable database rather than the shared development project.

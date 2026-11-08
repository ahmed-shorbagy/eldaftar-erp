# Completion prompt: owner voice-note feedback (2026-11-08)

Copy everything below the line into the implementing agent.

---

You are finishing the 2026-11-08 owner feedback in the ElDafttar ERP monorepo at `D:\Eldaftar ERP`. Work in the Flutter app (`app/`) and the Supabase backend (`supabase/`). The React admin is out of scope.

## Read first, in this order

1. `AGENTS.md`. It overrides everything except the user. Do not commit or push.
2. `docs/operations/owner-feedback-2026-11-08-voice-notes-plan.md`. This is the specification. Follow it task by task. Decisions D1–D9 in section 1 are final; do not reopen them.
3. `docs/adr/0041-owner-feedback-2026-11-08-voice-notes.md`
4. `docs/operations/owner-feedback-2026-11-08-voice-notes-validation.md`. What is already done and deployed.
5. `docs/design-system.md`, before any UI change.

## Already done: do not redo or rewrite

- **T0.1** (ADR), **M1** (T1.1–T1.4), **M2** (T2.1–T2.6), **T3.1–T3.2**.
- **Deployed to the development project:**
  - `20261108114028_purchase_paid_and_scrap_routing`
  - `20261108114753_cash_account_default_label` (fixes new shops being unable to confirm opening balances)
- **Current gates:**
  - The full Flutter suite passes (1,723 tests).
  - `dart analyze lib test` is clean. `flutter analyze` crashes in the local tool; use `dart analyze`.

## Your job: finish every remaining task in the plan

Do them in this order. Each one must be complete, tested, and green before you start the next.

1. **T3.3 + T3.4.** Staff closing task returns `item_names`; the staff count editor uses the shared `ClosingItemGridView` / `ClosingItemGrid`, with no copied grid code.
2. **M6 (T6.1, T6.2).** Edit and delete for daily notes. Owner only, any day, text-only edit, audit kept, R2 object not deleted. A deleted note's image must not be readable.
3. **M4 (T4.1, T4.2, T4.3).** Standalone `customer_return` and «إضافة مرتجع» in the returns ledger. Reports, feed, `is_return`, return counts, audit labels, and employee scoping must all include the new kind.
4. **M5 (T5.1, T5.2).** Edit and delete for `expense` and `customer_return`, via the generic mirror reversal. Open day only. `trade_has_followups` when lots were consumed.
5. **M7 (T7.1–T7.3).** Full gates, validation note updated, deployment record, and the Arabic owner checklist with every item marked.

## Hard rules learned from the last round (each one was a real bug)

1. **Wrap the current wrapper, not an old one.** `public.post_daily_ledger_trade`, `post_daily_ledger_trade_v2`, `review_ledger_trade_change_v1`, `post_ledger_trade_change_v1`, and `post_exchange_v1` are now wrappers over `*_before_paid_purchase` functions.
   - When M5 changes the trade-change functions, rename the *current public* function (for example to `…_before_expense_return_change`) and wrap that.
   - Keep the transaction-local flag `eldaftar.purchase_keep_category`: it is set around the internal replacement post. Purchase edits must still be paid in full and may keep a historical jewelry line.
   - Re-run `supabase/tests/purchase_paid_and_scrap_routing.sql` after M5.
2. **Internal callers.** The app's normal trade path calls v1 `post_daily_ledger_trade`, not v2, and edit/exchange call v1 internally. Before adding any check to a shared function, grep every internal caller (`grep -rn "public.<name>(" supabase/migrations`) and decide per caller.
3. **Server error codes.** Every new server error code must be added to `_errorCodes` in `app/lib/src/features/daily_ledger/data/http_opening_gateway.dart` (and the notes gateway's equivalent list). Test it through `HttpOpeningGateway` with `MockClient`, as in `app/test/daily_ledger_http_test.dart`. A fake-gateway test alone is not enough.
4. **Arabic-Indic digits** (٠–٩) must work in every new numeric field. Use `GramInputFormatter` / `canonicalNumericEntry`, never `FilteringTextInputFormatter.digitsOnly`.
5. **Zero book buckets.** The book snapshot keeps buckets with zero balance. The staff count editor must use `ClosingItemGrid.toObservations`, which already sends zero rows for untouched zero buckets. Add a staff-side test for a zero bucket.
6. **Run the full Flutter suite** (`flutter test` in `app/`), not only the files you touched. Update every stale test, and never weaken an assertion to make it pass.
7. **Historical records.** If a test run rewrites files under `docs/reviews/`, restore them with `git checkout -- <path>`. Historical validation records stay intact.
8. **SQL test fixtures for new shops** may call `confirm_opening_balances`; it works again after the label fix.
   - Legacy fixtures that need old partly paid or jewelry purchases must restore the pre-rule writers inside their own rolled-back transaction. See the header of `supabase/tests/ledger_trade_change.sql`.
   - Never re-grant those functions in a migration.
9. **Money and grams** stay integer piastres and milligrams (`Piastres`, `Milligrams`, `PieceCount`). No `double`.
10. **No unrequested features.** Do not add anything the plan does not list. If the code contradicts the plan, stop and report; do not improvise.

## Migrations and deployment

- New files go in `supabase/migrations/`, timestamped after `20261108114753`.
- Use the rename-and-wrap pattern and `private.compensation_extend_in_check` for enumerated checks, as the plan says.
- **Locally:** if Docker and the Supabase CLI are available, run `supabase start`, then `npm run test:rls` from `supabase/` with `SUPABASE_TEST_DATABASE_URL` set. Also run `ledger_trade_change.sql`, `financial_day_report.sql`, and `financial_week_report.sql`. If no local database is available, say so; do not claim they passed.
- **Development project `xchapwvmvoefriqcxtvn`.** The user's standing authorization covers this project only.
  1. List the hosted migrations and confirm only your new ones are pending.
  2. Confirm that every function you rename exists with the expected signature and that the new names are free.
  3. Record execute privileges for `authenticated` and `anon` before applying.
  4. Apply each migration without its own `begin;`/`commit;` lines.
  5. Re-check privileges afterwards. Public RPCs keep their previous access, and every `_before_*` and private function stays closed to clients.
  6. Rename the repo file to the version the hosted history recorded.
  7. Run each new SQL test file on the hosted project inside one transaction that ends in `rollback`, with a final `select '<NAME>_PASSED'`.
  8. Verify that no test shops or users remain.
  9. Compare the security advisor output with the previous run.
- Never touch production or any other project. No resets, no paid resources, no release builds, no `npm run build`.

## Done means

- Every task in the plan's traceability table is implemented and has its listed tests.
- `dart format` has been run on the changed files.
- `dart analyze lib test` is clean.
- The full `flutter test` passes.
- Every new SQL test has passed locally or on the hosted project, with the method stated.
- All new migrations are deployed to the development project and verified.
- ADR 0041 status and the validation note are updated, including the deployment record and anything not verified.
- `git diff --check` is clean.
- Arabic RTL screens have been checked in light and dark, at 375 px and ≥1280 px. If you could not check on a device, say so plainly.

## Final report

Use this format:

1. **Per task:** done or not done, the files changed, and the tests added.
2. **Gates:** each command you ran and its exact result.
3. **Deployments:** hosted versions and verification results.
4. **Deviations from the plan,** with the reason for each.
5. **Anything not verified.**
6. **The Arabic owner checklist (T7.3),** ready to send.

Nothing goes unreported, and do not claim anything you did not run.

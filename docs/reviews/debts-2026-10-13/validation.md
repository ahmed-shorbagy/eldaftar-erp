# DEBT-01 — initial local validation

Date: 2026-10-13. Scope: Milestone 4 debt slice only. Implemented locally and left uncommitted. Not deployed. Codex has not yet run the routine gates or hosted checks. Historical Batch 1, Batch 2, and repairs records stay as they are.

## What this note covers

The owner opens الديون from More. A debt is money or gold at one karat (14, 18, 21, 22, 24), in one direction. Purchase cash payables and gold obligations stay in their own tables and appear live in the list and detail, including existing purchase, settlement, and return history. They are not copied. Repair outstanding fees are not imported.

A standalone declaration is a historical or external balance. It posts no journal, lot, receipt, custody row, payable, or gold obligation, and it does not need an open day. Settlement of a source balance must move cash or gold. Standalone no-ledger settlement is allowed only with a reason; it records that choice and does not bump the business day. Moving money uses the selected methods. Outgoing gold consumes owned lots or scrap at the same karat. Incoming gold creates an owned available lot and an immediate shop-owned receipt. It is not custody and it is not a sale.

Cancel is limited to a wholly unsettled standalone debt, with a reason and no physical effect. Archive keeps history and remaining. The same idempotency key replays. A changed payload is rejected. A second key that reuses a settlement reference or external reference is rejected. Two concurrent settlements that reviewed the same snapshot produce one success and one `stale_debt`. `settlement_exceeds_obligation` applies when the reviewed remaining still matches and the amount is larger. The working rule is [ADR 0013](../../adr/0013-debt-balances-and-settlement.md).

## Local gates run in this change

| Gate | Outcome |
| --- | --- |
| `dart format` on the debt feature, its wiring, and the new tests | Applied. A later `dart format` of `debt_rules.dart` reported 0 changes. |
| `dart analyze` of `app/lib/src/features/debts`, the touched ledger/shop/workspace files, and the new debt tests | No issues found. `flutter analyze` was not run. |
| Focused `flutter test` | 74 tests passed, exit 0. Files: `debt_rules_test.dart`, `debt_codec_test.dart`, `debt_command_flow_test.dart`, `debt_persistence_test.dart`, `debt_widget_test.dart`, `debt_pending_navigation_test.dart`, `debt_capture_test.dart`, `shop_sync_coordinator_test.dart`, `repair_review_regression_test.dart`, `repair_pending_navigation_test.dart`. |
| Isolated SQL | `node tmp/debts/deploy-local.mjs` exit 0. Fresh cluster `127.0.0.1:55447/eldaftar_debts`, all repository migrations, then `supabase/tests/debts.sql`, `shop_sync_signals.sql`, `repairs_custody.sql`, and `supabase/tests/debts_concurrency.mjs`. Evidence: `tmp/debts/deploy-db-5ae937d9-fce6-449c-9032-d90042ccc2fd-sql.log`. The server was stopped in `finally`. |
| `git diff --check` | Exit 0 on the uncommitted tree. |

The full `flutter test` suite, admin `npm run lint`, `npm run test -- --run`, `npx tsc -b`, and `node supabase/run-rls-tests.mjs` were not run here. `debts.sql` is already listed in that runner for Codex. No release build and no `npm run build`.

Synthetic captures, 54 PNGs, are under `app/build/debts`: list, detail, form, review, pending, error, success, keyboard, and text scale, at 320, 390, and 1440, in light and dark. Widget tests asserted the Arabic states and raised no exceptions. A spot check of the 390 list in both themes, the 320 light no-ledger review, and the 1440 dark form showed RTL Cairo layout, the shared brown/cream/dark surfaces, exact piastres on review, and a centered 720-pixel form. This is not a device screenshot review.

## Limits

No hosted deployment and no access to development project `xchapwvmvoefriqcxtvn`. No owner-device acceptance. Reminders, debt PDFs, CRM, reports, and invoice customization are out of scope. React admin has no owner debts page.

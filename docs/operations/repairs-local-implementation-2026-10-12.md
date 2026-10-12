# Repairs local implementation — 2026-10-12

Implementer note for REP-01/02/03. Codex owns the final requirements matrix and the exact validation record. This note is not acceptance, and the migration is not deployed.

## Behavior in this slice

The owner registers a repair contact on the repair: name, optional phone, item, grams to three decimals, karat 14/18/21/22/24, issue, notes, and an optional estimated fee in integer piastres. Intake review states that custody increases by the measured weight and that saleable stock and cash stay at zero. Ordinary weight display uses two decimals. The confirmation adds the exact milligram count when that rounding hides precision. 1.255 g is stored as 1255 mg and shown as 1.26 g with 1,255 ملليجرام.

Statuses are received, in progress, ready, and delivered, plus cancelled and archived. Original intake, custody events, and audit stay immutable. Times are stored in server UTC and shown in the shop-local timestamp returned by the server. The list is searchable and keyset-paginated. Open is the default filter. Delivered, cancelled, archived, and outstanding filters remain available, including an archived repair that still has an outstanding fee.

The owner confirms intake, status change, handover, cancellation, and archive before the command is sent. There is no hard delete. Cancellation of an active repair requires a reason and an explicit return to the customer. It releases custody once and posts no fee. There is no pre-handover collection. Archive is only for delivered or cancelled records. It does not reverse cash or forgive the outstanding fee.

Handover is only from ready. The final fee is editable. Collection is all, part, or none through the existing cash methods, bounded by `0 <= collected <= final`. Zero collection releases custody once, writes no journal, and does not bump the business day. A collected fee posts once through the existing daily-ledger journal, cash, day, version, and idempotency path, with kind `repair_fee` and label أجرة إصلاح. Outstanding = final − collected stays on the repair. No debt, obligation, scrap, catalog, lot, or saleable-stock row is written for customer gold. A fee post may add an `inventory_lot_sync` marker and no lot movement.

Retry authority for repair commands is `get_repair_command_status`. A collected fee also writes `financial_command_requests`, but `get_opening_status` is not the repair reconciliation source because zero-fee commands cannot use that table. The client saves the encrypted command before send. A failed save does not send. An unknown timeout keeps the original key and payload. Cleanup of a matching key happens only after a confirmed or rejected status, and a cleanup failure still keeps the known outcome.

Navigation is the existing More entry الإصلاحات. An active owner with the repair gateway can write. An expired entitlement is read-only. A missing gateway or user shows الإصلاحات غير متاحة في هذا الاتصال. Pending shops do not open the workspace. There is no demo success, onboarding, or guide.

## Local checks run by the implementer

These are implementer runs on 2026-10-12. They are not Codex's final gates.

| Check | Result |
| --- | --- |
| `dart format` on the repair Dart paths | Last pass formatted 5 files, 0 changed |
| `flutter analyze` in `app/` | Failed. Missing `analysis_server.dart.snapshot`. Flutter 3.38.5 wrote `app/flutter_05.log`; that crash log was removed |
| `dart analyze lib test` from `app/` | No issues found |
| `flutter test --reporter expanded` from `app/` | 574 passed, exit 0. One existing off-screen tap warning in `owner_feedback_completion_test.dart` did not fail the run |
| `npm run lint` in `admin/` | oxlint completed with no findings |
| `npm run test -- --run` in `admin/` | 9 files, 38 tests passed |
| `npx tsc -b` in `admin/` | Exit 0 |
| Local SQL on `127.0.0.1:55445` / `eldafttar_repairs` | Exit 0. Evidence directory `tmp/repairs/primary-db-2d8a6141495d437d99c16e2321fbd806`. Server stopped |
| Repair migration round-trip | Pass. `public.repairs` and `repair_revision` were absent after rollback, then the migration applied |
| `supabase/run-rls-tests.mjs` | 15 SQL files, including `repairs_custody.sql`, completed with `ON_ERROR_STOP`. The repairs file ends in `rollback` |
| `supabase/tests/repairs_concurrency.mjs` | Pass. Two connections: same-key handover replay, changed-payload rejection, one release per competing repair |
| `git diff --check` | No whitespace errors on the tracked diff. New dart, sql, mjs, md, and ps1 files had no trailing whitespace. No production or release build was run |

The disposable runner is `tmp/repairs/primary-sql.ps1`. It applies every migration, proves the repair migration rolls back, then runs the RLS runner and the separate race script. The race script is not registered inside `run-rls-tests.mjs`. Codex port 55446 was not used.

## Captures

`app/test/repair_capture_test.dart` writes 30 PNGs under `docs/reviews/repairs-2026-10-12/screens/`. The names are `review`, `pending`, `success`, `keyboard`, and `text-scale`, each at 320, 390, and 1440, in light and dark. The tests expect no Flutter exception, including overflow. The 320 light review shows 1.255 g as 1.26 g with 1,255 ملليجرام, stock 0, and cash 0. There is no repair mockup. The intended column is documented in `docs/design-system.md`.

## Deployment

`supabase/migrations/20261012153000_repairs_custody_and_fees.sql` is local only. The Supabase CLI is not installed and was not installed for this task. Hosted project `xchapwvmvoefriqcxtvn` was not changed. The Flutter sync select includes `repair_revision` and fails closed until this migration is applied by a later authorized deployment.

## Limits left for the product

Images, a customer directory, debts, reminders, reports, invoice customization, repair loss, material use, taxes, accrual, and later settlement of an outstanding fee are outside this slice. Archive does not forgive an outstanding fee. A second handover is rejected as `repair_not_ready`. The client also whitelists `custody_already_released`, but the migration does not raise that code. A raw unique violation on the custody direction, if one ever escaped the status guard, stays an unknown result and is not presented as saved.

## Subsequent Codex review

The implementer results and paths above are a historical snapshot. The [independent validation record](../reviews/repairs-2026-10-12/validation.md) supersedes them for the final working tree, including navigation copy, safe sync compatibility, reconciliation, SQL/client fixes, expanded test counts and regenerated captures.

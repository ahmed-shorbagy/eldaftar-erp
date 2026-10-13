# DEBT-01 — Codex independent validation

Date: 2026-10-13. Supplements the historical [initial record](validation.md). Grok session `01a13487-2730-73d3-aa4f-9efedf5afc74` completed scoped implementation and backend correction without committing, pushing or deploying. Codex reviewed the diff and corrected pending recovery identity, stale responses, frozen forms, receipt selection, exact parsing, Arabic history, dropdown overflow and immutable source original amounts. Source settlements delegate to existing purchase/gold contracts so returns and trader books see one operation.

| Independent gate | Result / evidence |
| --- | --- |
| Scoped `dart format` | Applied to changed Dart files. |
| `flutter analyze` | Attempted; installed SDK lacks `C:\flutter\bin\cache\dart-sdk\bin\snapshots\analysis_server.dart.snapshot`. Environment limitation, not a pass; `tmp/debts/codex-flutter-analyze.log`. |
| `dart analyze app/lib app/test` | No issues, `tmp/debts/codex-dart-analyze-final.log`. Final history edits also passed, `codex-history-analyze.log`. |
| Full `flutter test` | 702 passed, exit 0; `tmp/debts/codex-full-flutter.log`. Includes Batch 1/2, repairs and debt precision, persistence, retry, pending navigation and identity-change regressions. |
| Final codec/visual scope | `flutter test test/debt_codec_test.dart test/debt_moving_capture_test.dart test/debt_capture_test.dart`: 62 passed after final history changes. |
| Admin `npm run lint` | Passed; `tmp/debts/codex-react-lint.log`. |
| Admin `npm run test -- --run` | 38 passed across 9 files; `tmp/debts/codex-react-tests.log`. |
| Admin `npx tsc -b` | Passed; `tmp/debts/codex-typescript.log`. |
| Fresh database | `node tmp/debts/codex-local.mjs`: all migrations, debt apply/rollback schema comparison/reapply, all 16 SQL/RLS suites and independent-connection race passed, exit 0. Evidence `tmp/debts/codex-db-ee8abe1b-3751-43b4-bf6f-8a6d11990e5d-sql.log`; server stopped. |
| Hosted regression follow-up | Fresh migration rollback/reapply, scoped debt suite with both ledger directions and race passed; `DEBT_FOLLOWUP=1 node tmp/debts/codex-local.mjs`, `tmp/debts/codex-db-9860d79c-2070-4335-a6fe-1b105ed5d790-sql.log`. First fixture incorrectly used cursor 0; corrected to positive 1. Failed log retained under `codex-db-14c425fe-747f-436c-a071-7b9882e640d6`. |
| Hosted client codec | Temporary `flutter test app/tmp/debt_hosted_contract_test.dart` from app: 1 passed with actual hosted context/list/archived history. Initial invocation had a temporary path error, corrected. |
| `git diff --check` | Passed. |

SQL coverage: owner/cross-shop/anonymous/revoked/expired boundaries, immutable history, injected posting rollback, exact money/milligrams, excess settlement, replay and payload mismatch, exact declaration duplicates, gold receipt ownership, no unit conversion, no repair import, legacy/new purchase settlement followed by return refund, actual settled versus cancelled amounts, and concurrent stale snapshots. Two connections yield one settlement and one stale rejection; same-key retry replays.

Synthetic Flutter captures cover 320/390/1440 widths and both themes: list/detail/declaration/review/pending/error/success/keyboard/text scale plus moving money and incoming/outgoing gold. Codex inspected phone gold reviews in both themes, desktop money/gold reviews in both themes, phone history and desktop list. Shared tokens, Arabic RTL, LTR numbers/contact, readable wrapping and exact milligrams were visible without overflow. Ignored captures are under `app/build/debts`; these are widget captures, not native-device acceptance.

No push, application publishing, release build or React production build. Native owner acceptance and acceptance of ADR 0013 bounded accounting assumptions remain open. [Development deployment](deployment.md).

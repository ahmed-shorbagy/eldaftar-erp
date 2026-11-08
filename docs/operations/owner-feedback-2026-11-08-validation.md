# Owner feedback 2026-11-08 — validation

Date: 2026-11-08. Flutter client only. No commit, no push, no release build, no schema, Edge Function, or R2 change. React and SQL gates were not run; this change does not touch `admin/` or `supabase/`.

## Commands

From `app/`:

| Command | Result |
| --- | --- |
| `dart format --set-exit-if-changed lib test` | Clean after formatting `shop_image_copy.dart`. Exit 0. |
| `dart analyze` | No issues found. Exit 0. |
| `flutter analyze` | Crashes in this environment. The analysis server snapshot must be run with `dartaotruntime` (`analysis_server.dart.snapshot is an AOT snapshot`). Flutter 3.38.5, Dart 3.10.4. Crash log: `app/flutter_03.log` (gitignored). `dart analyze` is the substitute. |
| `flutter test` | 1671 tests passed, about 3 minutes, exit 0. This full run was after Tasks 1–8. Two later analyzer fixes (an unused private `key` on the header pill button, and a null-aware map entry in `ledger_line_items_test.dart`) were rechecked with `dart analyze` and with `flutter test test/ledger_line_items_test.dart test/ledger_app_bar_shop_image_test.dart` (4 passed). The full suite was not repeated after those two edits. |
| `git diff --check` | Exit 0. Git printed LF-to-CRLF warnings only. |

Tasks 1–7 were checked with the tests named in the plan for that task, not with a separate full `flutter test` each time. The suite above is the full run.

## What the tests cover

Money tiles hide the normalized gold line. «وزن مباع» and «وزن مشترى» open per-karat sheets, including scrap, with no piece count. Sale cards preview three items and a price column. A note draws a dot on a trade card and not on a daily note. The header greets with «أهلاً» and falls back to `BrandMark`. «المزيد» lists the old drawer pages and the old account page, and the menu button is gone. «لوجو المحل» replaces the old shop-image name. Registration always saves a chosen logo as the invoice draft. `ApplyShopLogoToInvoice` keeps slogan, address, layout, and accent, skips an identical sha, refuses an inactive entitlement without a write, and retries a transport failure with one revision and the same key. The appearance screen tests still pass.

## Screenshots and device review

No new screenshots were taken. Windows is installed as a Flutter device, and Pixel 7 and Pixel 9 emulators exist, but none was launched. A signed-in walkthrough of the ledger, both weight sheets, a five-item card, a noted card, «المزيد», the header with and without a logo, and the signup «لوجو المحل» step was not done in light and dark, at 360, 390, and 1280, or at text scale 1.3. Widget tests do exercise Arabic RTL in light and dark, including the workspace at 320 and 1440 and the new screens at phone width. Flutter tests fail on overflow, and that suite passed. That is not a substitute for the device pass.

## Not verified

- `flutter analyze` (tool crash, above).
- Live Windows debug and Android emulator review, including text scale 1.3.
- A second full `flutter test` after the two analyzer-only edits.
- Hosted Supabase. Nothing in this change is deployable there.
- Owner acceptance.

## Review pass — 2026-11-08

Reviewed the uncommitted diff against FB-001 … FB-009. Fixes applied during review:

- Ledger cards no longer blank and reload their item rows on every sync tick; a refresh re-reads quietly and keeps the shown rows until the new read arrives (regression test in `ledger_journal_table_test.dart`).
- The «السعر» column is shown only when the invoice has per-item prices (all-or-none on the server); otherwise the card total stands alone instead of a column of dashes (regression test).
- `ApplyShopLogoToInvoice.call` never throws; an unreachable server reports `failed` so the «مظهر الفاتورة» tile cannot stay on «جارٍ إضافة…» (regression test).
- The registration logo is also applied when the shop becomes active in the same session (subscription redeemed), not only on the next app start.
- Remaining «شعار التسجيل» wording aligned to «لوجو المحل».
- Unrelated files in the diff are `dart format` reflows only (no behavior change), required by the format gate.

Gates after the review: `dart format --set-exit-if-changed lib test` clean, `dart analyze` no issues, `flutter test` 1674 passed, `git diff --check` clean. Visual check from the capture tests' screenshots (ledger top and journals, light/dark, 320/390/1440, text 1.6). A signed-in device walkthrough on Windows/Android is still not done.

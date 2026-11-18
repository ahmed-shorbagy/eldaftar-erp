# Owner feedback of 2026-11-17: validation record

Scope: milestones of [owner-feedback-2026-11-17-plan.md](owner-feedback-2026-11-17-plan.md). This record is extended as each milestone lands.

## M0. Daily ledger blocked after confirming opening balances (FB-005)

Date: 2026-11-18. Client fix and tests only. No migration, no Edge Function, nothing deployed. Not committed. No release build was made, so the owner's device still runs the affected build.

### Cause, confirmed on development `xchapwvmvoefriqcxtvn`

Checked read-only, inside transactions that were rolled back.

- The affected shop's opening is committed: operation 1 is `opening_balances`, on an open business day dated 2026-11-17. No data repair is needed.
- `get_daily_ledger_home_v2`, read as that shop's owner, returns `state: confirmed`, `read_model_version: 3`, `day_reset: false`, and the opening row with `kind: opening_balances`. The legacy `get_daily_ledger` returns the same operation as `opening_balances_confirmed`.
- `OpeningFlowCoordinator._matches` accepted the read only when the feed held a row of kind `opening_balances_confirmed` for the acknowledged operation. The app reads the home function, so the check could never pass for a new shop. The acknowledged attempt stayed stored on the device and each launch repeated the refusal.

Shops that confirmed their opening before the app moved to the home read were not affected. Every shop opened since then is.

### Change

- `app/lib/src/features/daily_ledger/application/opening_flow.dart`: after the server acknowledges the opening, a confirmed ledger with a business day is the refreshed ledger. The feed is no longer inspected. It is the open day's page, it names the row differently per read, and it does not carry the opening once that day is closed. The `opening_already_confirmed` path already accepted a confirmed ledger on the same grounds.
- `app/lib/src/features/daily_ledger/presentation/daily_ledger_screen.dart`: the notice «تعذر تحديث الدفتر بعد التأكيد» has «إعادة المحاولة», which rereads the ledger. It is no longer a dead end when a read does fail.

A device already stuck needs no manual step: with the fixed build the next read is accepted and the stored attempt is retired. The opening is not posted again.

### Tests

- `app/test/opening_refresh_after_confirm_test.dart` (new, 5 tests). The scripted ledger has the shape the development project returned for a newly opened shop. Covers: the home row kind; confirm then read reaches the ledger; a stuck acknowledged attempt recovers on launch without a second post; the same after the opening day was closed and the feed is empty; a failed read resolves on retry with one confirm call. Four of the five fail on the code before the fix with `OpeningRefreshFailed`.
- `app/test/daily_ledger_widget_test.dart`: the notice shows «إعادة المحاولة», and tapping it opens the ledger and retires the stored attempt.
- `supabase/tests/opening_home_feed.sql` (new, registered in `supabase/run-rls-tests.mjs`): a new shop confirms zero balances; the home read is confirmed, has its business day and one feed row of kind `opening_balances` for the confirmed operation; the legacy read still names it `opening_balances_confirmed`.

### Gates

- `dart format` on the changed files: clean.
- `dart analyze` (whole app): no issues. `flutter analyze` crashed inside the Flutter tool on this machine before analysing, so `dart analyze` was used.
- `flutter test` (full suite): **1936 passed**.
- `opening_home_feed.sql` on development: all checks passed in one block that ends by raising, so the synthetic user, shop, and opening were rolled back. Not run on a local database; none was available.
- `git diff --check`: clean.
- React and TypeScript gates: not run. `admin/` is untouched.

### Device check (Android emulator, 2026-11-18)

Debug build from the working tree, against development, Arabic RTL, dark theme.

- A new owner and shop were registered through the app's own sign-up and activated with one 30-day row in `shop_entitlements` on development (approved by the developer for this test). The credentials are in the git-ignored `app/config/.env.test-shop`. The shop stays on development as test data.
- The new shop opened on «إعداد الأرصدة الافتتاحية», the screen in the owner's screenshots. «تأكيد أرصدة صفرية», then «تأكيد الأرصدة الافتتاحية», opened the daily ledger with zero cash and empty sale and purchase books. The notice «تعذر تحديث الدفتر بعد التأكيد» did not appear.
- After a force stop and relaunch the ledger opened again on «يوم العمل 18 نوفمبر 2026».
- The older test shop, already confirmed, still opens its ledger on the same build.

### Not done

- No release build, so the fix is not on the owner's phone. Building is opt-in under `AGENTS.md`.
- The owner's own stuck phone was not available. Its recovery path is covered by the automated test of a stored acknowledged attempt, not by a device run.

## M1, part 1. The ordinary clock (FB-001)

Date: 2026-11-18. Client changes only (Flutter and React). No migration, nothing deployed, not committed. Stored instants are unchanged: server-generated UTC. Only the display changed.

Rule applied: twelve hours with ص/م, no seconds, no time-zone name, no «UTC», no «توقيت الخادم» or «توقيت المتجر».

### Change

- App: one formatter, `app/lib/src/theme/shop_clock.dart` (wall times the server already converted to the shop zone) and `shop_instant.dart` (instants, converted to the shop zone, or the device zone when none is given). The ledger's existing helpers now delegate to it.
- Screens and PDFs moved to it: ledger timestamps and the «الدفاتر» list, operation PDF, invoice PDF, invoice message time, day and weekly reports and their PDF, analytics PDF, audit trail, customer dates, debt due dates, reminders and their history, debt statement screen and PDF, message settings, support and broadcast dates, the subscription expiry notice.
- Removed from the screen: zone ids such as `Africa/Cairo`, «المنطقة الزمنية», «وقت الخادم UTC», «الوقت العالمي», and raw ISO timestamps. The audit trail shows one line, «الوقت».
- PDF cells that are drawn left to right use `shopNumericDateTimeLtr`, so ص/م sits on the reader's side of the digits as it does on screen.
- Admin: `formatServerInstant` in `admin/src/subscribers/subscriptionFormat.ts` no longer uses the 24-hour cycle or the long zone name. Every admin panel formats through it.

### Tests and gates

- New `app/test/shop_clock_test.dart`: afternoon hours, midnight and noon, the shop day across UTC midnight, no zone name or «UTC» in any output, no direction marks in PDF and message text.
- Nine existing Flutter tests asserted the 24-hour or raw text and now assert the rule: compact ledger, ledger archive, invoice message, repair detail, support dates, customer statistics, and the two debt reminder tests (which also assert that no zone id is shown).
- Admin: `subscriptionFormat.test.ts` asserts 2:05 م for 14:05 Cairo, 12 at midnight and noon, and no «توقيت», «أوروبا», UTC or seconds.
- `dart analyze` (whole app): no issues. `flutter test`: **1941 passed**. One run had a single failure in `invoice_branding_pdf_capture_test.dart` that passed alone and in the next full run; treated as a timing flake of that render test.
- Admin: `npx vitest run` **245 passed**, `npx tsc -b` clean, `npm run lint` clean. One vitest run made while the emulator build was compiling timed out in two unrelated panels; both pass alone and in the idle full run.
- `git diff --check`: clean.
- Device: «الدفاتر» reads «مقفول · فُتح 2:19 م · أُقفل 11 نوفمبر 2026 10:27 ص». The audit trail reads «الوقت: 11 نوفمبر 2026، 2:06 م» and «آخر تحديث للقائمة: 18 نوفمبر 2026، 9:11 ص». The invoice render reads the date, 10:00, then ص from the right.

### Notes

- `invoice_branding_pdf_capture_test.dart` rewrites the PNG files under `docs/reviews/invoice-branding-2026-10-21/pdf/`. They now differ because the invoice time changed. They were restored to keep that review record as it was; the test will rewrite them on each run.
- Not checked on a device: reports, analytics, debts and support screens, and the printed report and statement PDFs. They are covered by widget tests only.
- The admin dashboard was not opened in a browser; no platform-admin test account is available.
- Seen in passing, not changed: the audit card's last line shows the date as digits that reorder in RTL («11-11-2026»).

## M1, part 2. The ledger opens with no opening-balances form (FB-006, FB-022)

Date: 2026-11-18. Flutter client only. No migration, nothing deployed, not committed. Decision: [ADR 0049](../adr/0049-ledger-opens-without-opening-form.md).

### Change

- Removed from `daily_ledger_screen.dart`: the opening form, its stock and scrap rows, its review, and the «تأكيد أرصدة صفرية» button. Removed from `daily_ledger_controller.dart`: the form's fields and draft handling.
- For the owner of an active shop with no confirmed opening, the controller sends the existing `confirm_opening_balances` command with zero balances and shows the ledger when the server confirms. The command keeps its stored idempotency key.
- New states: «تعذر فتح الدفتر» with «إعادة المحاولة» after a failed attempt, «جارٍ فتح الدفتر» with «إعادة المحاولة» when the reply is unknown, «لم يفتح صاحب المحل الدفتر بعد.» for staff, «لم يُفتح دفتر هذا المحل بعد.» for an expired or pending shop.
- Staff waiting for the owner, and an opening with an unknown reply, now resolve on the next sync instead of on the next restart.
- Wording that named «الأرصدة الافتتاحية» elsewhere was changed: the payment-methods empty state, the already-open message, and the refresh notice («تم فتح الدفتر»).

### Tests and gates

- New `app/test/ledger_opens_directly_test.dart` (8 tests) and three new screen tests in `daily_ledger_widget_test.dart`; see ADR 0049 for what each covers.
- Removed with the form: eight screen tests of its fields, review, and draft, and the screenshot captures of the form in `daily_ledger_capture_test.dart`. That file keeps the helpers other tests import and the opened-ledger captures.
- Six other screen tests were adapted because a new shop now opens instead of showing the form.
- `dart analyze` (whole app): no issues. `flutter test`: **1938 passed**. `git diff --check`: clean.
- React and SQL gates: not affected by this part and not rerun.

### Device check (Android emulator)

- A second new owner and shop were registered through the app's sign-up and activated with one 30-day row in `shop_entitlements` on development. Its credentials are in the git-ignored `app/config/.env.test-shop` beside the first test shop's.
- On launch the app showed the daily ledger at once: «يوم العمل 18 نوفمبر 2026», zero cash, empty sale and purchase books. No setup screen appeared.
- On development that shop has one operation, `opening_balances` number 1, one open business day, postings that total zero, and one audit event.

### Open question for the owner

There is no simple way to enter starting cash. Gold can be added from «الجرد الفوري» with «إضافة مخزون». Cash changes only through sales, purchases, expenses, transfers between methods, and the counted correction at day close. The owner did not ask for a cash button and did not say where starting balances should be entered. «إضافة أو تعديل نقدية» in «الجرد الفوري», as in the old app, could be built on the existing `post_ledger_correction_v1` command. It is not built and will not be until he answers.

## Still open in M1

Two-decimal weights, removing «مشغولات», and the banned-terms test and glossary. Before the owner build: his answer on where starting cash and gold are entered.

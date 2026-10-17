# Invoice appearance — independent validation

Milestone 4 slice 10. Recorded 2026-10-17, Africa/Cairo, after owner-confirmed [ADR 0021](../../adr/0021-invoice-appearance-and-presentation-copies.md) and the [separate implementation review](implementation-review.md). Development application to xchapwvmvoefriqcxtvn had already succeeded. This continuation reran only read-only preservation proofs. It did not apply SQL again, upload a logo, insert a fixture, commit, push, or run a release build.

The same session that implemented the slice also wrote this record after the delegated run had stopped. It is not a second implementer. Gates below distinguish earlier session results from checks repeated while closing the slice.

## Client and local SQL gates

| Gate | Result |
| --- | --- |
| Scoped Dart format | `dart format` on the invoice-appearance library and the screen, domain, and PDF tests. One screen-test file changed, then the command was clean. After the post-review copy-panel and screen edits, `dart format` on those two presentation files reported zero changes. |
| Flutter analysis | After the null-aware map fix, analysis of the PDF capture test was clean. After the post-review edits, `flutter analyze --no-fatal-infos` on `invoice_copy_panel.dart` and `invoice_appearance_screen.dart` reported no issues in 6.5 seconds. The full `app/` tree was not re-analyzed in this closing pass. |
| Flutter tests | From `app/`, one run of `invoice_appearance_test.dart`, `invoice_appearance_screen_test.dart`, `invoice_branding_pdf_capture_test.dart`, and `confirmed_operation_pdf_test.dart` exited 0 with `00:10 +13: All tests passed!`. That run was before the post-review presentation edits. The PDF capture test was not repeated after moving `?` onto the nullable map value; analysis of that file was clean and the edit does not change PDF bytes. After the copy-panel and expired-owner edits, `flutter test test/invoice_appearance_screen_test.dart` exited 0 with `00:10 +4: All tests passed!`. The full Flutter suite was not run. |
| React | From `admin/`, `npm run lint` (oxlint, 0 problems), `npx tsc -b`, and vitest (9 files, 38 tests) passed earlier. This slice does not change `admin/`. Those commands were not repeated in the closing pass. |
| Local SQL | Disposable PostgreSQL 17.6 on 127.0.0.1:55454, database `eldaftar_invoice_appearance`. After the POSIX-whitespace clear, the runner from 2026-10-17T17:17:24 to 17:17:31 passed migration rollback/apply, `supabase/tests/invoice_appearance.sql`, `supabase/tests/shop_sync_signals.sql`, and `supabase/tests/invoice_appearance_concurrency.mjs`. Log line `ALL_LOCAL_SQL_PASSED`. An earlier pass at 16:59:34 predates that whitespace edit. `invoice_appearance.sql` stays out of `supabase/run-rls-tests.mjs`. |

Concurrency on that disposable database observed one replayed appearance command returning the same revision, one stale expected revision, and a payload mismatch. Cleanup of its own synthetic rows used `session_replication_role = replica` and then asserted zero leftover rows. Ordinary deletes stay blocked by `audit_append_only`.

## Arabic RTL and PDF pages

UI chrome PNGs were not written. `RenderRepaintBoundary.toImage` hangs in this Windows `flutter_tester`, and no `toImage` call remains in the suite. The screen test covers loading, empty, edited, upload pending, review, stale, recovery, confirmed, and expired states through text, at 320, 390, and 1440, in light and dark, including text scale 1.7. One dialog test opens the synthetic preview and expects «معاينة تجريبية لا تُنشئ عملية أو إرسالاً».

Rendered pages under [pdf/](pdf/) were produced again after the bidi fix, at about 16:44. This closing pass opened `long-names-page-1.png`, `partial-purchase-page-1.png`, and `many-items-page-6.png`.

The long-name page keeps a brown header, a wrapped shop name, a four-line address, sequence 44, edition 1, separate operation and copy times, a long item name, and 12.500 grams inside the page. Labels sit on the right. The purchase page shows cash, wallet, paid, and remaining lines without clipping, including «المستحق عند الشراء كما سُجّل عند تأكيد الشراء». Page 6 of the long list shows items 26–28, then الإجمالي 1,000, نقد 600, and تحويل فوري 400, with «تتمة النسخة» and «إصدار 1». The file set also contains karats pages 1–2, legacy karats pages 1–2, missing-logo page 1, and transparent-logo page 1. This pass did not reopen those four fixtures. `many-items` is six pages.

## Post-review fixes and the JPEG limit

The review found no blocking bug. Three suggestions were corrected in the tree before the hosted file was applied: RTL time labels, POSIX whitespace clearing, and the expired-owner phase while a logo upload is pending. The reviewer did not re-review those edits. JPEG confirmation still stores the submitted bytes and stops at the first EOI, so trailing bytes can remain. The normal client path re-encodes in `prepareLogo` and strips PNG chunks before upload. That limit stays documented. It is not treated as a second migration.

## Hosted preservation rechecked while closing

Read-only queries after application:

- `shop_sync_signals` still has 11 rows. Removing `appearance_revision` from each row and hashing equals the pre-apply digest `c5af424abc106e8dcc3abd5db7e3e243d05f5788b15b657fa0287d69f68c1b5f`. The column exists once.
- Public and private function fingerprint, excluding `bump_shop_sync`, `shop_sync_touch`, and the new appearance function names, equals the pre-apply fingerprint `a9599c3da1f68926c4d39544d51cf27b0cf03c76cd4784281cbd19d3232faffa`.
- `supabase_migrations.schema_migrations` has 40 rows, latest `20261017140000`, and zero null `statements` arrays. Version `20261016090329` is still named `debt_native_reminders` with one statement. Version `20261017140000` is named `invoice_appearance` with 99 statement-array elements. Statement text was not printed.

The [deployment record](deployment.md) holds the 55 unchanged table pairs, six new empty tables, and the storage counts. No customer row, object name, token, or credential is in this record.

## Limits

Milestone 4, full DOC-01, DOC-04, and SET-04 stay open. Wider all-screens D12 prototype approval stays open. Android, iOS, and Windows device and owner acceptance of this screen, and of native reminders, stay open. Export, preview, share, and opening WhatsApp do not confirm sending or delivery. No hosted logo was uploaded. The disposable database was dropped and its cluster stopped after these records, as a local test cluster only.

# Invoice appearance: separate implementation review

Date 2026-10-17. This review edited no application or test file and mutated no hosted data. Migrations were not applied, hosted Supabase was not queried, and no server was started. The implementer's local Postgres 17 run (127.0.0.1:55454, `ALL_LOCAL_SQL_PASSED` at 2026-10-17T16:59:34) was not repeated. UI chrome PNGs were not treated as proof.

## Assessment

No blocking bug was found. This does not approve development application, and it does not complete Milestone 4, DOC-01, DOC-04, or native acceptance. Arabic RTL light and dark captures and rendered PDF pages are still open.

Appearance and presentation posts insert only their own revision, audit, and idempotency rows, then call `private.bump_shop_sync` once with scope `appearance`. They lock the shop and, for a presentation, the financial operation, but they do not update those rows or post cash, gold, stock, debt, repair, CRM, ledger, or dispatch. Reported effects stay zero. The copy panel and the appearance screen do not call the dispatch command. Share and save text say the action is not send or delivery confirmation. The existing WhatsApp confirmation controls stay on their own path and still use `buildConfirmedOperationPdf`.

`private.bump_shop_sync` and `private.shop_sync_touch` keep ledger, inventory, trader, invoice, day, location, subscription, repair, debt, and customer, and add appearance. `shop_sync_touch` names the new tables, but this migration does not create `shop_sync_*` triggers on them, so a post does not increment twice. Logo confirmation does not bump sync. Debt-reminder callers of `bump_shop_sync(..., 'debt')` still hit the debt counter.

Reads use `opening_require_reader_shop` and `opening_financial_visible`, which allow an expired owner after `starts_at`. Writes, logo confirmation, and new presentation revisions use `can_write_shop`. Tables are force-RLS, select-only for `authenticated`, and append-only. Logo bytes are tied to `(shop_id, id)`. The storage policy is insert-only on private bucket `eldafttar-private-invoice-logos` and does not change the notes bucket. Clearing a logo writes a new appearance revision and leaves historical logo rows in place.

A presentation copies the current appearance fields and the immutable operation payload. The hash covers kind, UTC `created_at`, operation id, that payload, and `shop_sequence`. A mismatch raises `stale_operation` on create and the client refuses export when `content_matches` is false. Purchase rendering uses `purchase_obligation_piastres` and the tender sum, not `purchase_cash_payables.remaining_piastres`. The same idempotency key returns the stored edition. A new edition needs a new key and the current `expected_latest_edition`. A stale appearance revision is rejected. Replay is recognized before the write check.

The branded PDF page is RTL. `_value` uses LTR only when the value has no Arabic-block character. Shop name, slogan, address, and item names stay on the RTL page. `buildConfirmedOperationPdf` is still the legacy renderer.

The shared locker accepts `invoice_appearance` and `invoice_presentation` only after the existing sale, purchase, debt, repair, CRM, native, and other matchers. A different stored kind is left in place (`other_pending` / `pending_financial_exists`). Unknown kinds still fail closed.

## Findings

1. Suggestion. `app/lib/src/features/invoice_appearance/presentation/invoice_copy_panel.dart` (`_digits`, used for `وقت العملية` and `وقت إنشاء النسخة`). Those Arabic labels are wrapped in `TextDirection.ltr`. The branded PDF does not do this. It does not block development application: it is preview chrome, not the frozen PDF, and it does not change money, dispatch, or the locker.

2. Suggestion. `supabase/migrations/20261017140000_invoice_appearance.sql`, `private.invoice_optional_text`. `btrim` removes ASCII spaces only, so a newline-only or other non-space whitespace value is stored instead of cleared. The Flutter normalizer uses `String.trim` before the normal save, and other C0 controls are still rejected. It does not block development application.

3. Suggestion. `supabase/migrations/20261017140000_invoice_appearance.sql`, `confirm_invoice_logo_v1` and `private.invoice_logo_facts`. Confirmation stores the submitted bytes. Strict mode rejects animation and extra PNG chunks, and it rejects JPEG APP1, but it stops at the first JPEG EOI, so trailing bytes and other JPEG metadata segments can remain. The storage check matches path, MIME, and metadata size; it does not read the object body. `prepareLogo` re-encodes before the normal upload, and historical logo rows are not deleted. It does not block development application.

4. Suggestion. `app/lib/src/features/invoice_appearance/presentation/invoice_appearance_screen.dart`. An expired owner with a leftover logo upload stays in `uploadPending`, and the retry button calls `_pickLogo`, which returns immediately because `canWrite` is false. No appearance or logo RPC runs. It does not block development application.

## Post-review corrections — 2026-10-17

The finishing session recorded these notes after this review was written. The reviewer did not re-review them.

1. Corrected before application. Copy-panel time labels keep the Arabic label in RTL. Only the stamp after `: ` is isolated LTR.
2. Corrected before application. `private.invoice_optional_text` clears a value that is empty after POSIX `[[:space:]]` is removed. The disposable database was rerun after this edit: `ALL_LOCAL_SQL_PASSED` at 2026-10-17T17:17:31.
3. Left as a known limit. JPEG confirmation still stores the submitted bytes and stops at the first EOI. The storage check matches path, MIME, and metadata size. The normal client path re-encodes in `prepareLogo`.
4. Corrected before application. When the owner cannot write, the screen uses the expired phase even if a logo upload is still pending. The screen test then passed, 4 tests.

This note does not itself approve development application. The application record is [deployment](deployment.md).

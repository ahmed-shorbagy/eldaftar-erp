# Auth and ledger functional feedback — independent validation

Date: 2026-10-19. This extends the [earlier auth/ledger UI delivery](../owner-feedback-ledger-auth-2026-10-19/validation.md); historical records and captures remain unchanged.

## Delivered behavior

- Login, signup, and password-recovery rejection copy use Arabic letters/characters rather than bytes. Encoding-based password validation remains enforced.
- The mixed-karat Total Gold figure is removed. Six slots select among thirteen figures; the other seven remain in More. Default selection is cash, sales, purchases, gold sold, gold bought, and expenses.
- Gold equivalents default to 21k, with 14/18/21/22/24 selection. Integer milligrams × source karat are summed before division by target karat and one final display rounding. Monetary totals remain monetary. Actual sale weights for 18/21/24 and scrap-only purchase weights for 18/21/22/24 are separate selectable figures.
- Shop-local preferences hide 14k/22k scrap choices in new trade entry. Saved records and balances retain those karats. New sale input accepts at most two nonzero decimal places, including localized digits; exact trailing zeros canonicalize. Stored milligrams and inherited historical three-decimal weights remain exact. Numeric fields request numeric keyboards. Retained historical refund fields have visible zero placeholders.
- Date navigation loads an authorized shop date using the server's time zone, combines reopened sessions on that date, and exposes empty-day and older-page states. Current cash/inventory balances are not presented as historical balances.
- Refund/exchange entry controls are replaced by Edit and Delete on sale/purchase details. Only the current open business day without linked follow-up operations qualifies. Editing restores the exact original fields, including optional pricing, line prices, description, customer details, and notes.
- A separate server-derived review shows net cash by method, stock by category/karat and count, scrap, payable changes, and the edited record before confirmation. Delete undoes the original effects and hides its active invoice/ledger entry while retaining immutable audit history. Edit atomically reverses and replaces the source. Pending requests persist before posting; retries retain their key/body; stale reviews and duplicate submissions are blocked.
- Server revisions invalidate cached older pages after an edit/delete in another session. Historical summaries and feeds exclude changed sources and internal reversals. Readers cannot bypass the protected wrappers; revoked access clears protected detail content.

The [design guide](../../design-system.md) and [backend contract](../../operations/ledger-trade-edit-delete.md) describe the final behavior. No new palette or actor roles were introduced.

## Independent gates

| Check | Observed result |
| --- | --- |
| Dart formatting | Scoped to changed/new Dart files; passed with suppressed analytics. |
| Flutter analysis | `flutter --suppress-analytics analyze --no-pub`; passed without issues. |
| Flutter regression suite | All non-capture test files, `flutter --suppress-analytics test --no-pub ... --reporter expanded`; **1,221 tests passed**. Includes exact normalization, two-decimal entry, six-slot migration/persistence, hidden scrap choices, historical codecs/pagination/access, priced edits, pending/retry, server rejection, and cache invalidation. |
| Visual matrix | Opt-in `owner_ledger_functions_capture_test.dart` with `LEDGER_FUNCTIONS_CAPTURE=true` and `--update-goldens`; **12 matrix tests / 180 PNGs**, no layout exceptions. |
| Admin | `npm run lint`, `npm test -- --reporter=dot`, and `npx tsc -b`; passed, **9 files / 38 tests**. No production build. |
| Migration round trips | Date read, trade edit/delete, and cache revision rollback/apply checks passed on fresh disposable local database `eldaftar_trade_change_codex_final4`, port **55470**. |
| Financial SQL/RLS | `ledger_trade_change.sql`, `ledger_trade_cache_revision.sql`, compensation, compensation edges, daily ledger trades, customer statistics, debts, and final-schema date reads passed. Checks include owner isolation, anonymous denial, append-only history, expired access, protected private helpers, revoked legacy writers, insufficient balances, linked-operation rejection, injected replacement failure, and idempotency. |
| Concurrency | Independent Postgres connections: one edit/delete wins, its peer receives `operation_replaced`; replay succeeds; token/body mismatch is rejected; concurrent same-key posts produce one replay and one financial change. |
| Historical integration | Sale edit counted once, sale/purchase deletion excluded, a reopened date combines both sessions, closed-session changes rejected, and limit-one pagination matches the complete visible feed despite hidden head/intermediate/tail rows. Cache sequence increased monotonically without crossing shop boundaries. |
| Date read contract | **52 checks**, **11 feed-shape matches**, **11 cursor pages** passed. Includes empty/future dates, owner/session boundaries, shop time zones, and no read-side financial mutation. |
| Documentation/diff | Local links, current-guide consistency, synthetic-data/privacy review, and `git diff --check` passed. |

Codex reran the database gates rather than accepting Grok's reports. The reusable repository runner is `supabase/tests/ledger_trade_change_local_runner.ps1`, pinned to a dedicated local port/database prefix. Independent validation used the same runner with only the repository location, dedicated port/data-directory, and matching concurrency guard adapted in temporary artifacts. The test cluster was stopped afterward and its synthetic data retained. No hosted database was accessed or changed.

The verified migration SHA-256 values are:

```text
ee2b7856de50a032db72e46f7677dfd3ab5506c6c3c708647d50397345be7019  20261019184500_ledger_date_read.sql
e722eff018c241e2c84688f5da0f976c289a1587087948f4072cad34f3337bf0  20261019230000_ledger_trade_edit_delete.sql
c5b617279b5f8ed3f642aea6a5f80f611919e97e9dff2221d31df162618d6368  20261019233000_ledger_trade_cache_revision.sql
```

Two scoped Grok runs implemented the date reader and financial mutation core without committing or pushing. A later integration follow-up supplied historical filtering and null-payment handling but was stopped after a tool error and prolonged planning. Codex completed the client integration, read consistency/cache handling, regression corrections, final source review, and independent gates. Interim runs exposed obsolete UI expectations, nested-scroll capture harness issues, and a volatility assertion that needed to require the stronger stable date snapshot. These were corrected without disabling tests. An initial Windows process-output wait during local cluster startup is not counted as a passing gate; the subsequent complete fresh-database run above is the SQL evidence.

Historical return-math fixtures temporarily grant retired writers inside rolled-back test transactions. Existing legacy concurrency scripts remain guarded to their original dedicated disposable databases; those unrelated race suites were not rerun. The new trade-change concurrency suite was rerun against the final schema.

## Arabic RTL inspection

[Actual captures](captures/) cover 15 states at **320/390/1440** logical pixels, **light/dark**, and text scales **1.0/1.7**: both password hints, 21k/24k summaries, six-slot selection, scrap settings, More karat figures, populated/empty date views, date picker, prefilled edit, delete/edit effects review, unknown request, and confirmed change. Main-ledger captures use the actual daily-workspace shell; More uses its actual 720-pixel content measure. Cairo, image assets, and shared semantic tokens are loaded.

Codex inspected samples including [enlarged login hint](captures/login-password-hint-320-dark-1.7.png), [signup hint](captures/signup-password-hint-390-light-1.0.png), [desktop ledger](captures/summary21-1440-light-1.0.png), [phone cash summary](captures/summary21-320-dark-1.0.png), [enlarged customization](captures/six-slots-390-light-1.7.png), [scrap settings](captures/scrap-settings-1440-light-1.7.png), [karat figures](captures/karat-more-390-dark-1.0.png), [enlarged historical ledger](captures/dated-ledger-320-light-1.7.png), [date picker](captures/date-picker-320-dark-1.0.png), [edit form](captures/edit-form-320-light-1.7.png), [delete effects](captures/delete-review-320-light-1.7.png), [edited details](captures/edit-review-390-dark-1.7.png), [pending request](captures/unknown-change-390-light-1.0.png), and [confirmed change](captures/confirmed-change-1440-dark-1.7.png).

Image inspection found a cash header wrapping into individual letters; summary widths now account for labels, icons, and actions, and final captures were regenerated. Partial next tiles indicate horizontal scrolling. Enlarged forms/reviews scroll internally; the primary edit action remains reachable. No sampled clipping/readability blocker remained.

All identities, phone numbers, invoices, and balances in tests/captures are synthetic. This establishes widget-level and isolated-server verification, not native-device keyboard, screen-reader, or owner acceptance. No Android/iOS/Windows release build, React production build, publishing, deployment, or hosted financial mutation was performed. The new backend migrations still require the normal authorized deployment process.

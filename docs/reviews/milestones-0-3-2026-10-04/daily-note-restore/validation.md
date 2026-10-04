# Daily-note restart restoration — 2026-10-04

Only this bounded client restoration subtask is complete. LED-05 and milestones 0–3 remain open. See the [current progress record](../../../operations/milestones-0-3-progress-2026-10-04.md). No Supabase, compensation or payment settings changes were made.

## Behavior and regression evidence

`daily_notes_screen.dart` uses the existing application interfaces and immutable domain draft; no storage or backend implementation was added to presentation. Text, picking and save are disabled through stored-draft loading and key reconciliation. Server completion cleans the exact owner/shop/key and local attachment and shows success without posting. Unknown or unavailable status freezes the original payload and context. Rejected status also cannot authorize edits. Reconciliation retry unlocks only on server-confirmed absence; submission retry retains the original key, text, image and business day. Storage read errors keep all writes blocked and expose an Arabic restore retry. Duplicate callbacks are guarded synchronously before lookup. Generation checks discard late restore/status results on owner, shop and day changes.

The 16 new widget regressions cover the read-to-lookup lock, exact confirmed cleanup without posting, preservation of a replacement draft with another key, unknown and thrown/unavailable status with exact image/payload retry, reconciliation-only retry and duplicate callbacks, storage read failure and recovery without overwriting, rejected status, concurrent save/attachment lookup guards, and delayed read/status results for all three context changes. The existing uncertain-day regression now asserts that text is disabled immediately after restart rather than simulating an allowed edit before reconciliation. It still verifies the original text and day in the retried command.

## Final checks

- Scoped `dart format --output=none --set-exit-if-changed`: five Dart files, zero changes.
- `flutter analyze`: no issues, 8.3 seconds.
- `flutter test --reporter expanded`: 375 passed, final reporter time 41 seconds. Full log is local ignored `app/build/daily-note-restore-full-tests.log`.
- Earlier scoped restoration/widget/capture run: 28 passed (16 new restoration, eight existing widget, four new capture tests).
- React `npm run lint`: passed; `npm test -- --run`: 35 passed in nine files, 14.77 seconds; `npx tsc -b`: passed.
- `git diff --check`, documentation link/consistency/privacy review: passed.

Initial regression failures were two Dart record comparisons containing separately allocated byte lists. Final tests compare owner, object path and byte contents separately. Initial analysis reported four brace-style diagnostics, repaired. The first capture harness stalled on image encoding outside `runAsync`; the final harness uses the established asynchronous capture pattern. Sandboxed full-suite/analysis starts stalled before output, were interrupted, and were replaced by successful SDK-access runs. Grok's authorized delegation failed before edits on exhausted balance; no further attempt followed it.

## Visual review

All 24 synthetic widget captures below were inspected. The six states appear at 320×900 and 1440×900 in Arabic RTL, light and dark. The existing vertical scroll layout and 48-pixel controls remain. Arabic status/error/retry text wraps without overlap or horizontal overflow. The original text remains readable while frozen using `ColorScheme.onSurface`; loading, disabled controls, errors and buttons use the existing [theme contract](../../../design-system.md). Enabled/disabled button color transitions finish before capture. Fonts come from bundled Noto Sans Arabic and the installed Flutter SDK's Material icons. The uncertain request button says `إعادة المحاولة بنفس الطلب`, and the separate status-only action says `التحقق من حالة الملاحظة`.

| State | 320 light | 320 dark | 1440 light | 1440 dark |
| --- | --- | --- | --- | --- |
| Stored draft loading | [Capture](loading-320-light.png) | [Capture](loading-320-dark.png) | [Capture](loading-1440-light.png) | [Capture](loading-1440-dark.png) |
| Key lookup | [Capture](lookup-320-light.png) | [Capture](lookup-320-dark.png) | [Capture](lookup-1440-light.png) | [Capture](lookup-1440-dark.png) |
| Unknown, original frozen | [Capture](unknown-320-light.png) | [Capture](unknown-320-dark.png) | [Capture](unknown-1440-light.png) | [Capture](unknown-1440-dark.png) |
| Confirmed absent, editable | [Capture](absent-320-light.png) | [Capture](absent-320-dark.png) | [Capture](absent-1440-light.png) | [Capture](absent-1440-dark.png) |
| Confirmed success | [Capture](confirmed-320-light.png) | [Capture](confirmed-320-dark.png) | [Capture](confirmed-1440-light.png) | [Capture](confirmed-1440-dark.png) |
| Storage read error/retry | [Capture](storage-error-320-light.png) | [Capture](storage-error-320-dark.png) | [Capture](storage-error-1440-light.png) | [Capture](storage-error-1440-dark.png) |

The screenshots use synthetic text and owner/shop identifiers, no credentials or customer data. They exercise dependency-injected storage and server status and prove client state handling, not physical device restart, platform image picking, hosted Storage or notes RPC delivery. Status unavailable uses the same frozen layout as unknown, with its thrown-error path covered by the regression test. Cleanup remains best effort; a retained confirmed local draft is reconciled again after the next restart. SQL/RLS/atomicity checks were not rerun because backend contracts and financial operations were untouched. No release/production build, commit, push or deployment ran. Historical validation and captures are intact.

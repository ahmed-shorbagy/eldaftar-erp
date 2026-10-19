# Authentication and daily ledger simplification — 2026-10-19

The owner's pasted UI feedback is the reference for this change. Grok Build implemented the main changes using the explicitly requested grok-delegate workflow. Codex reviewed the actual diff, corrected behavior and visual defects, and independently ran the final gates. No backend schema, RLS policy, financial command, authentication contract or invoice payload changed.

## Delivered behavior

| Request | Result |
| --- | --- |
| Visible jewelry background | Full-bleed photo remains visible around and through the auth panel. Input surfaces remain readable; the dark upper overlay protects branding contrast. |
| Internally scrolling registration | A bounded panel scrolls its heading, three required account/shop/review steps, fields and primary action. Keyboard and enlarged-text tests retain access to fields and submit. |
| Personalized ledger | Actual shop name in «أهلاً …», with a two-line greeting to retain the name at narrow/enlarged widths. |
| Six selected figures | Exactly six of seven figures at every width; select the seventh for More and reorder the remaining six. Per-shop preferences migrate hidden/count/duplicate/legacy entries safely. The summary itself cannot be hidden. |
| Removed clutter | No Gold Movement UI, operation-count box, separate cash-balances section or inventory/scrap section on home. |
| More and cash disclosure | More reads the seventh figure and opens inventory/scrap. The single total-cash tile opens payment-method balances wherever that tile is selected. Open breakdowns follow sync, mark stale retained values, reject late replies, and clear on access loss or identity change. Missing connections do not wait on local preferences. |
| Compact transactions | Smaller framed cards, row position, amount, seller and 12-hour time. Initial cards hide weights/payment methods; explicit detail expansion retains structured items and read retry. Header and circular button open the operation. Dark borders use the shared light-yellow semantic role. |
| Numbering | Display positions 1…n follow the selected journal/history order and filter, including legacy records. Permanent server operation references stay in operation details. Positions can change when sort/filter/pagination changes. |
| Customer, time and notes | Details omit the redundant day, show shop-local ص/م time, name/mobile or honest absent/partial placeholders, and an explicit notes indicator with expandable actual text. Arabic labels retain direction and phone digits are isolated. |
| Other categories | Text-only predefined دبلة، غويشة، إسورة، خلخال، طقم grid. No manual item name, inventory shortcut or product-table controls in that surface. Supported worked-jewelry payloads, bullion/coin nominal suggestions and confirmation remain intact. |

Notes use the existing primary accent with explicit Arabic text rather than adding a blue palette. Operation detail retains its existing page route and invoice actions. Balance/history detail surfaces retain the established responsive sheet/dialog pattern. Gold/money storage, exact confirmations, idempotency, server audit, ownership and theme persistence remain unchanged.

## Independent final verification

| Gate | Observed result |
| --- | --- |
| Scoped Dart formatting | Installed Dart `--suppress-analytics format` on all 29 touched/new Dart files: passed. |
| Flutter analysis | `flutter --suppress-analytics analyze --no-pub`: no issues. |
| Full regression | In `app/`, `$testFiles = @(rg --files test -g '*_test.dart' \| Where-Object { $_ -notmatch 'capture' }); flutter --suppress-analytics test --no-pub @testFiles --reporter expanded`: **1,195 passed**, exit 0, 1:13. |
| Correction scopes | Eight affected/new test files: **55 passed**. Earlier focused auth/ledger check: **39 passed**. |
| New visual harness | `flutter --suppress-analytics test --no-pub --dart-define=OWNER_FEEDBACK_CAPTURE=true --update-goldens test/owner_feedback_2026_10_19_capture_test.dart --reporter expanded`: **12 passed**, exit 0, 120 actual PNGs. |
| React | In `admin/`, `npm run lint`, `npm test`, `npx tsc -b`: passed, **9 files / 38 tests**. Rechecked after the shared token edit. |
| SQL/RLS | Not rerun: no SQL, policies, commands or backend contracts changed. Existing Flutter financial/domain/HTTP/auth/retry/codec regressions are included in the full suite. This is not fresh database-policy verification. |
| Diff and documentation | `git diff --check`, local documentation links, current-guide consistency and synthetic-data/privacy review passed. Historical validation records were left intact. |

The first delegated relay failed on a Windows log-file lock; the resumed session stalled in compaction and was stopped. Codex completed the review corrections directly. An unfiltered early Flutter run stalled in a historical screenshot generator and is not counted as validation. An interim independent non-capture run had 1,188 passes and seven failures: five unavailable-connection preference waits plus two obsolete collapsed/lazy-list expectations. These were corrected without skipping tests; the final full run above supersedes that run. An initial formatter invocation formatted successfully but failed its telemetry write; the final suppressed-analytics formatter and analyzer passed. The temporary captures in the wrong `app/docs/` path were removed; they are not final evidence.

Existing UI tests were updated for the explicit greeting, removed sections, six-choice customization, predefined category grid, seller/time copy and collapsed cards. Structured-item race/retry, source filtering, pagination, permissions, precision and invoice-send confirmation assertions remain covered. No tests were disabled. The new capture harness is opt-in and does not overwrite historical evidence.

## Arabic RTL visual review

[Actual captures](captures/) cover 10 states × 320/390/1440 logical pixels × light/dark × text scales 1.0/1.7: login, signup top/bottom, ledger, compact journals, More, inventory/scrap, customer details, notes and Other categories. Captures use Cairo, actual shared tokens and synthetic gateways. Auth images are decoded before capture.

Codex inspected samples including [light login](captures/login-320-light-1.0.png), [dark login](captures/login-390-dark-1.0.png), [enlarged signup bottom](captures/signup-bottom-320-dark-1.7.png), [enlarged shop greeting](captures/ledger-320-dark-1.7.png), [light compact journals](captures/transactions-320-light-1.0.png), [dark enlarged journals](captures/transactions-390-dark-1.7.png), [desktop inventory](captures/inventory-1440-dark-1.0.png), [customer details](captures/details-1440-light-1.7.png) and [desktop Other grid](captures/other-categories-1440-light-1.7.png). The final captures include the contrast and two-line greeting corrections. No sampled clipping or readability blocker remained; partial next tiles in the horizontal strip indicate scrolling. Full matrix tests also assert no layout exceptions.

All shop/customer names and phone values in this evidence are synthetic. This establishes widget-level visual and behavior verification, not native-device, screen-reader or owner acceptance. No release/production build, publishing, deployment or hosted write was requested or performed by this task.

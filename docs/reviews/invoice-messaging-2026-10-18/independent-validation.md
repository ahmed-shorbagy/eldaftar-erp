# Invoice message templates — independent validation

Closed 2026-10-19, Africa/Cairo, for [confirmed D35](../../adr/0022-invoice-message-templates.md) and the entire [reviewed plan](../../operations/invoice-messaging-slice-prompt-2026-10-18.md). Codex inspected the actual Grok backend diff and independently ran the relevant gates after integration/corrections. This is independent of Grok's execution/self-report; the validating Codex also implemented the client, so it is not represented as a second independent implementer. A [separate read-only reviewer](implementation-review.md) inspected the final code and evidence without rerunning gates. Hosted application remains unauthorized.

## Commands and outcomes

| Gate | Exact scope / observed result |
| --- | --- |
| Dart formatting | Final `C:/flutter/bin/cache/dart-sdk/bin/dart.exe format --output=none --set-exit-if-changed` on 26 touched Dart source/test files: exit 0, 26 formatted, zero changed. Paths were the modified tracked Dart files, new invoice-message library and `invoice_message*_test.dart`; no historical formatter sweep. |
| Flutter analysis | Full `flutter analyze --no-pub` in `app/` after final code/test additions: exit 0, `No issues found!` (104.9 seconds). |
| Flutter regression | In `app/`, `$testFiles = @(rg --files test -g '*_test.dart' \| Where-Object { $_ -notmatch 'capture' }); flutter test --no-pub @testFiles --reporter expanded`: exit 0, **1,179 passed**, 1:23. Log `eldaftar-invoice-message-flutter-final-20261019.log` in the local task temp directory. Includes all message/domain/HTTP/widget/dispatch tests, existing PDF/appearance, sync, accounting, authorization adapters, auth and business regressions. Filename-based capture generators were excluded to avoid overwriting historical evidence; the new capture generator ran separately below. |
| New capture generator | `flutter test --no-pub --dart-define=MESSAGE_CAPTURE=true --update-goldens test/invoice_message_capture_test.dart`: exit 0, 12 tests, 276 PNGs. Uses synthetic fixtures and Cairo/Material font loading; no real message or native launcher. |
| React lint | `npm run lint` in `admin/`: passed, oxlint zero problems. No admin source changes. |
| React tests | `npm test` in `admin/`: passed, 9 files / 38 tests. |
| TypeScript | `npx tsc -b` in `admin/`: exit 0. This is type checking, not the production build. The unchanged admin gates passed earlier in this same implementation session and were not repeated at closing. |
| Fresh local backend | `pwsh -NoProfile -File supabase/tests/invoice_message_local_runner.ps1 -Database eldaftar_invoice_message_roundtrip_20261019 -Port 55464`: exit 0. PostgreSQL **17.6**, loopback only, fresh dedicated cluster/database. Migration SHA, rollback/apply, message SQL, concurrency, prior appearance, sync and trade regressions all passed; details below. |
| Diff / documentation | Final `git diff --check`: exit 0. Local link review checked 395 targets with zero missing. Consistency/privacy review and the 744-file historical preservation comparison passed. New evidence contains only synthetic fixtures, schema metadata and code hashes. No secrets, live customer/contact records or private source documents were added. |

The earlier 1,177-test full run passed before the last injected dispatch and HTTP timeout tests; the final 1,179-test run supersedes it. One interim scoped invocation named nonexistent `shop_sync_test.dart`; it reported a load failure, not a product failure. The final complete non-capture run includes the actual `shop_sync_coordinator_test.dart` / `supabase_shop_sync_gateway_test.dart` and passes. An initial final-format attempt used a nonexistent SDK path; the corrected installed path above passed. Neither failed invocation is counted as a passed gate.

The existing sign-out widget regression needed deterministic asynchronous cleanup and an empty fake path-provider directory. The test now awaits the actual sign-out completion without keeping a pointer event pending, and never points at real saved copies. `path_provider_platform_interface` was already installed and is now an explicit test dev dependency. Production sign-out behavior was not changed.

## Domain, client and recovery evidence

The tests cover default/custom/whitespace/reset, every allowed token, escaped/unclosed/unknown braces, nonrecursive replacement, CRLF/lone CR, malformed Unicode, emoji scalar counts, control rejection, exact scalar/newline/rendered/encoded-URI bounds and no truncation. The documented sale example renders `73`, `بيع`, `1,234.50`, `3.705`, and two item lines. Purchase original tender/obligation values remain independent from later live balance changes. V1/v2 payloads, all five karats, optional empty values and very large exact integers are covered.

Application/HTTP/locker/widget tests exercise owner/token/shop change, late responses, expired read/replay versus blocked writes, revision conflicts and draft preservation, separate appearance/message sync, resume/refresh, exact receipts and original-envelope recovery, foreign/unknown pending bytes, keyboard token insertion, duplicated submissions and status-first timeout reconciliation. A simulated HTTP response timeout after server commitment recovers the original receipt with one send. No claim of real OS process termination is made; restart recovery is tested by constructing a new flow around the preserved encrypted command.

Handoff tests change template/name/zone/operation/destination/session between preview and launch, exercise midnight and non-Cairo zone conversion, validate existing Egyptian snapshot phones, and reject malformed/missing ones. Changed facts require another explicit action. Opened/unavailable/failure/unknown results remain distinct; no cancellation claim is made. The operation-screen HTTP regression verifies that preview/launch never call a financial command or confirmation; only the separate owner action calls the existing confirmation RPC with operation ID/key, without text/phone. Legacy PDF and branded-copy flows remain separate.

## Local SQL, authorization and preservation

Final local log: `eldaftar-invoice-message-roundtrip-20261019.log` in the task temp directory. Its first line matches the reviewed migration SHA-256:

```
2340064a9501017822a131e0c712297be006571ec93fe0e7c4593c117a5df986
MIGRATION_ROLLBACK_PASSED
MIGRATION_APPLY_PASSED
INVOICE_MESSAGE_SQL
INVOICE_MESSAGE_CONCURRENCY
INVOICE_APPEARANCE_SQL
SHOP_SYNC_SQL
DAILY_LEDGER_TRADES_SQL
ALL_LOCAL_SQL_PASSED
LOCAL_CLUSTER_STOPPED_DATA_RETAINED
```

The runner bootstraps the ordered historical migrations into a fresh dedicated local database, applies the new migration inside a transaction then rolls back and asserts its new column/table/RPC are absent, applies it persistently, and checks the migration file hash has not changed. The existing-database branch intentionally does not reapply migrations; it is not the basis of the round-trip claim. The runner stops only a cluster it started and retains its data. Previous failed setup/test attempts were repaired before this fresh exit-0 run: restored missing time-zone files from the existing PostgreSQL archive, valid synthetic UUIDs, SQL syntax/assertions/search-path issues and the protected digest helper's permissions. No historical migration or hosted database was changed to make the gate pass.

`supabase/tests/invoice_message.sql` executes real PostgreSQL roles and policies for owner, other shop, anonymous, revoked, pending, expired and implicit platform-admin cases; denies direct table writes; checks append-only audit/request protection, definer search paths/grants, grammar/limits/reset, UTC/local timestamps and non-Cairo midnight behavior. It verifies active-write restrictions, expired reads/reconciliation, replay/payload mismatch/stale revisions and an injected audit failure rolling back the entire command. Protected row digests across 23 financial/stock/custody/debt/CRM/repair/dispatch/appearance/history tables remain unchanged. These row-content digests use **MD5** as equality checks, distinct from the migration/archive SHA-256 hashes.

`supabase/tests/invoice_message_concurrency.mjs` runs same-key races, competing expected revisions and changed-payload retries against the dedicated loopback database. Same-key results converge; competing edits produce one stale revision; changed payload fails. Random fixture IDs avoid collisions. Concurrency revisions/requests/audits are retained; only synthetic access/entitlements are retired. No replica-mode history deletion or reset is used. The historical `invoice_appearance.sql`, `shop_sync_signals.sql` and `daily_ledger_trades.sql` also passed after the new migration. These are local synthetic authorization/preservation proofs, not a hosted data comparison.

## Arabic RTL captures

[Captures](captures/) contain **276 actual Flutter PNGs**: 23 states × widths 320/390/1440 × light/dark × text scales 1.0/1.7. States: loading, default, tokens, edited, invalid, overflow, keyboard-focus, review, submitting, unknown recovery, confirmed, stale, expired, access-loss, settings-failure, preparing, handoff-preview, handoff-stale, handoff-opened, handoff-unavailable, handoff-failure, handoff-unknown and missing-phone. The outer capture includes Navigator dialogs and uses the actual theme tokens/Cairo/RTL layout.

Codex and the separate reviewer opened and visually inspected samples spanning all widths/themes/scales, including [320 dark enlarged tokens](captures/tokens-320-dark-1.7.png), [390 dark default](captures/default-390-dark-1.0.png), [1440 light enlarged handoff](captures/handoff-preview-1440-light-1.7.png), review/recovery, stale and failure states. No sampled clipping, palette or readability blocker remained. The widget matrix additionally checks all combinations for layout errors and tests keyboard/Arabic semantic labels. This is not a claim of exhaustive manual inspection of every image, native screen-reader acceptance or real WhatsApp behavior.

## Acceptance limits

Hosted application, hosted two-session/device synchronization and native/owner acceptance remain open. No hosted reads/mutations or real customer messages occurred. Windows may open a browser for `wa.me`; OS cancellation, sending and delivery are unobservable. No Android/iOS/Windows release, React production build, publishing, reset, commit or push was run. [Pending exact backend change and future authorization/preservation](no-deployment.md), [repository history preservation](preservation-check-2026-10-19.json), [bounded completion](../../operations/invoice-messaging-completion-status-2026-10-18.md).

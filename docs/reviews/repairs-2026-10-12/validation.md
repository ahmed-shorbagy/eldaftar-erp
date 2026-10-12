# Repairs REP-01/02/03 — independent validation

Date: 2026-10-12. Scope: the first Milestone 4 repairs slice only. Implemented and reviewed locally; not deployed or accepted on owner devices. Historical Batch 1/2 records remain intact.

## Delivered behavior and accounting bounds

The owner opens **الصيانة** from More, registers the repair contact/item, exact measured gold, karat, issue, notes and optional estimate, searches repairs, reads immutable intake and Arabic audit history, and advances received → in progress → ready → delivered. Intake, status change, final handover, cancellation and archive have explicit confirmation. Customer custody never becomes owned inventory or scrap.

Handover edits the final fee and collects all, a strict partial amount, or none. The review shows final/collected/outstanding amounts, each cash method, exact custody release, and zero saleable-stock effect. Positive collection uses the existing open-day/version contract and posts one balanced `repair_fee` operation through cash and `movement_money_clearing`. A zero collection posts no financial operation and needs no open day. Remaining fees stay on the repair, including after archive; this slice does not settle them later or create debt records. Cancellation means an explicitly confirmed zero-fee return to the customer, with a reason. Archive preserves cash, outstanding and all history. These bounded working rules are recorded in [ADR 0012](../../adr/0012-repair-custody-and-fees.md) and the [repair contract](../../operations/repairs-contract.md).

Storage uses integer piastres/milligrams, validates PostgreSQL bigint bounds and supports 14/18/21/22/24 karats. Editable measured grams retain three decimals; ordinary weight displays two with integer rounding, and review also exposes exact milligrams. Original fields/payloads and custody/audit events cannot be edited through owner access. Backend owner checks, RLS, shop locking, expected versions and stored canonical request payloads protect every mutation. Unknown requests retain the same key/payload and disable competing submissions; failed status reads never erase them. Confirmed collection refreshes the ledger; repair/ledger/day sync revisions refresh open repair routes.

## Delegation and Codex review

Grok Build implemented the scoped brief through grok-delegate and did not commit or push. Codex independently inspected the diff, new files and existing-test changes, corrected defects, and reran the gates below. ui-ux-pro-max informed form labels, destructive confirmations and responsive review; the existing shared theme remained authoritative. The Supabase plugin was used only for read-only inspection of the linked development project, existing financial/RLS contracts and UTC timezone. No hosted mutation occurred.

Material review fixes included a reproduced nested-aggregate failure in the context RPC; complete collected-fee/customer summaries for existing ledger readers; UTC wire timestamps independent of session timezone; actual JSON null for an absent estimate; removal of a production test-failure switch; strict pending-request reconciliation and response identity checks; serialized shared pending storage; repair-specific ledger resume/navigation; route/identity/stale-response guards; dynamic read-only entitlement; and visible unavailable/persistence-failure states. Narrow-phone payment fields now stack so the complete method balance is readable. Tests added for these defects preserve the earlier behavioral assertions.

## Independent gate results

| Gate | Exact outcome |
| --- | --- |
| Scoped Dart format | 26 changed/new Dart files; 0 changed, exit 0 using `dart format --output=none --set-exit-if-changed`. |
| `flutter analyze` | Attempted; exit 1 before analysis because the installed Flutter 3.38.5 SDK lacks `dart-sdk/bin/snapshots/analysis_server.dart.snapshot`. No SDK installation/upgrade performed. |
| `dart analyze app/lib app/test` | No issues found, exit 0; independent substitute for the broken launcher. |
| Full `flutter test` | 606 tests passed, exit 0 (full suite, including existing Batch 1/2 regressions). |
| React `npm run lint` | Passed, exit 0. No React repairs page was added. |
| React `npm run test -- --run` | 38 tests in 9 files passed, exit 0. |
| React `npx tsc -b` | Passed, exit 0. No production build ran. |
| SQL migration | Every repository migration applied to a fresh disposable local PostgreSQL cluster. Repair migration applied inside a transaction, rolled back with both repair tables and `repair_revision` absent, then reapplied successfully. |
| SQL/RLS runner | All 15 suites passed with `ON_ERROR_STOP=1`, including identity/registration, subscriptions/sync, opening, trades/pricing, inventory, compensation and repairs. |
| Two-connection repair races | Passed: same-key handover replay, changed-payload rejection, competing different-key handover; exactly one fee/release per delivered repair. |
| Diff/docs/privacy | `git diff --check`, current document-link consistency and implementation-artifact/privacy review passed. Synthetic fixtures only; no credentials or source requirement documents added. |

The repairs SQL gate covers customer custody separation, exact fees, full/partial/unpaid delivery, cancellation/archive with outstanding preserved, immutable originals/events, owner/cross-shop/anonymous/revoked/expired permissions, denied direct writes, stale versions, duplicate/mismatched retries and atomic rollback after the final write. The injected failure trigger exists only in the test transaction. Session timezone Asia/Tokyo and shop-local timezone changes preserve persisted UTC instants. The concurrency fixture retains two owned-stock/custody scenarios and asserts inventory movements and obligations are unchanged by repairs.

The client gates cover domain calculations, bigint limits, actual local SQL JSON decoding, frozen unknown requests, failed/forbidden status reads, wrong-kind/wrong-repair responses, thrown transports, cleanup/storage failures, competing storage instances, sync revisions, stale pages/detail, changing shop identity/entitlement, pending ledger navigation, fee collection choices and critical confirmation paths. The actual SQL fixture is synthetic and exported with the hosted project's verified UTC session setting. An earlier full run had 605 passes and one fixture timezone failure; the fixture was corrected and the final full rerun above supersedes it. The decoder was not weakened.

Reproducible SQL entry points: `node supabase/run-rls-tests.mjs` and `node supabase/tests/repairs_concurrency.mjs`, with a freshly migrated local-only database matching their explicit safety guards. Codex's scratch target was `127.0.0.1:55446/eldaftar_repairs_primary`; the server was stopped in `finally`. Local evidence: `tmp/repairs/primary-db-cd4062d7d2c44fa5802a1ec228434a93/{sql,gates}.log`, `tmp/repairs/codex-full-flutter-final.log`, and `tmp/repairs/codex-flutter-analyze.log`. These ignored logs contain no hosted customer records.

## Arabic RTL and visual evidence

The full Flutter suite generates 78 synthetic PNG captures: 13 states × widths 320/390/1440 × light/dark themes. States are list, detail, intake review, paid form, partial review, unpaid review, cancellation review, archive review, pending, success, keyboard, enlarged text and unavailable backend. Each capture asserts no Flutter layout exception. Codex reviewed representative final phone/desktop captures in both themes for Arabic direction, readable cash/gold/status text, confirmation hierarchy, shared brown/cream/dark roles and responsive payment fields. Full captures remain locally under `app/build/repairs/` and regenerate with `flutter test test/repair_capture_test.dart`; review sheets are ignored local aids under `tmp/repairs/review-sheets/`. These are widget renders with synthetic gateways, not native-to-hosted proof.

## Deployment and remaining acceptance limits

The single additive migration is [20261012153000_repairs_custody_and_fees.sql](../../../supabase/migrations/20261012153000_repairs_custody_and_fees.sql). Before an authorized deployment, reconcile the linked project's historical migration versions and apply this reviewed migration using the project's migration process, then distribute the updated Flutter client. Do not blindly push the full local history. Existing sync reads tolerate an absent repair revision, and repair intake is disabled with visible unavailability until its RPCs exist. No repair Edge Function deployment is needed. The Supabase CLI was unavailable; the timestamped migration was created manually and validated with native local PostgreSQL tools.

Hosted repair HTTP/RLS/realtime validation, native Android/Windows/iOS-to-hosted testing, physical-device keyboard/accessibility review and final owner acceptance remain open. The normal `flutter analyze` launcher must be rerun after the missing installed-SDK snapshot is repaired. No hosted deployment, publishing, push, release build or React production build was authorized or performed. Later settlement of repair outstanding, material consumption/loss, ownership transfer, taxes/accrual, general CRM, debt reminders, reports and invoice customization remain outside this slice. The local gates do not mark all Milestone 4 complete.

## Subsequent authorized deployment

The owner later authorized Supabase deployment. The [deployment record](deployment.md) supplements this historical local snapshot with exact hosted versions, SQL/API/Realtime verification, advisor fixes and cleanup. The earlier results above remain intact.

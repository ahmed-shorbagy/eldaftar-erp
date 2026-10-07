# Ledger compensation implementation and validation — 2026-10-06

This record supplements the historical [Milestones 0–3 progress](../../operations/milestones-0-3-progress-2026-10-04.md) and [owner-feedback deployment](../owner-feedback-2026-10-06/deployment.md). The owner approved the preceding app experience; this scope adds correction, partial return and exchange controls without repeating or claiming new owner acceptance. All pre-existing uncommitted work remains in the checkout.

## Implemented behavior

- Physical-count mismatch exposes a reviewed compensating correction with a required Arabic reason and exact cash, category/karat gold and piece deltas. It uses the current server day/version, rejects stale or invalid counts, and preserves original operations, postings, audit and existing lot identities. The previous close-count screen is discarded after confirmation; close-day requires a newly fetched snapshot and a new matching physical count. Corrections that would require merging distinct lots or transferring their product identity fail rather than invent that allocation.
- Linked returns select original item indices, exact measured milligrams and counts, owner-entered consideration, and explicit split refund allocation. Price-component amounts are explicitly entered for priced originals; no proportional price is calculated. Purchase consideration cancels the remaining payable first, then records the reviewed cash refund. Cumulative weight/count/consideration and actual paid cash remain bounded. A later full return fills only the remaining quantities and consideration and still requires explicit refund allocation. Zero consideration is permitted when actual goods remain to be returned.
- Purchase returns consume quantities acquired by that original purchase and named item. Available unrelated gold cannot substitute for an exhausted original acquisition. Piece remainders cannot leave positive weight with zero count.
- Exchanges reuse the owner-accepted category/item/payment/detail/review form for the replacement, including multiple lines, explicit pricing, optional names, split payments and unpaid purchase obligations. One envelope commits return, replacement and their linked parent in one server transaction. Both sides and exact net cash by method, gold by category/karat and piece counts are reviewed. Failure rolls back postings, payables, lots, versions, requests, audit and outbox on both sides.
- Requests are durably stored before posting. Unknown responses and restored pending commands retain their original key and payload; status reconciliation and retries reuse that request. The current gateway, pending decoder, ledger/page decoder and confirmed operation detail support the added kinds. Confirmed route results refresh the existing ledger/day read paths.

The Arabic RTL clients retain both themes, dark startup, separate journals, all eight metric controls, optional customer names and currency-free amounts. No tours, guide cards, employee roles, shop selection or payment-method settings were integrated. Financial authority remains the signed-in owner on the server.

## Deployment

Development target only: `xchapwvmvoefriqcxtvn`. No application distribution, commit, push, release/production build, reset or other-project deployment occurred.

| Local source | Hosted version | Source SHA-256 | Status |
| --- | --- | --- | --- |
| `20261006080053_ledger_compensation.sql` | `20261006083846` | `1688E5B1B19331E9F22B348A52F0413CDB9F7466CF5E55485546F15AE601CA92` | Applied; hosted statement matches reviewed source after newline normalization |
| `20261006123700_ledger_return_refund_allocation.sql` | `20261006124322` | `D61925E7F8502928FB2E5D385AD7F2A6E836A41569464D7822D6E9C65EBFFF39` | Applied; guarded predecessor matched and hosted statement matches reviewed source after newline normalization |

Hosted compatibility was inspected before the first migration: all nine relevant predecessor function fingerprints exactly matched an independent local predecessor replay; no compensation function/helper names conflicted. Existing inventory and daily-note constraint values were preserved. The current registration/trade/pagination updates were retained. Only the reviewed compensation migration was applied, rather than pushing all local migrations. The refund-allocation follow-up checks its exact normalized predecessor function fingerprint and updates only the return core; the first deployed source remains unchanged.

The allocation repair permits a refund method different from the original tender. Its limit is the actual cumulative cash paid, while outgoing sale refunds also require available cash in each selected shop method. The first interrupted attempt to create that repair did not execute: automatic approval review could not run because of a usage limit. Work resumed after the user said “continue”.

## Verification evidence

### Local PostgreSQL and concurrency

A new isolated PostgreSQL 17.11 cluster on `127.0.0.1:55439` was created for this task, with disposable databases only. Temporary Auth/Storage bootstrap copies were guarded to their exact new database names and never applied to hosted Supabase. A clean replay of all local migrations through the refund-allocation repair passed, followed by all twelve affected rollback suites: identity RLS/commands, Egypt/owner-feedback registration, opening/owner RLS, trades, pricing, inventory/owner RLS, compensation and compensation edges.

Real independent PostgreSQL connections passed identical-key replay with one operation, changed-payload rejection, competing-return stale-version rejection, cumulative full-return rejection and exact operation/audit/request counts. This is local concurrent-connection evidence, not hosted concurrency or an HTTP race. Both final concurrency runs passed; their synthetic fixtures remain in separate task-owned disposable databases; no financial/audit records were deleted.

Adversarial gates cover mixed weight/count corrections, mandatory Arabic reason, negative/invalid count rejection, fresh close-day matching counts, three-decimal measured returns, partial/full remaining consideration, zero-consideration goods remainder, payable cancellation before cash, purchase exchanges with independent replacement payables, first/second-side rollback and rejected source-item substitution. Later tests confirm sealed originals remain immutable while returns and corrections post in the current open server day; changing the session time zone to Pacific/Honolulu cannot change that day identity.

### Hosted PostgreSQL

Eight hosted rollback suites passed after the initial deployment: identity RLS, opening RLS, trades, pricing, inventory, inventory RLS, compensation and compensation edges. The historical-day/time-zone extension also passed separately. After the allocation repair, compensation, compensation edges, trade and inventory RLS suites passed again, including an explicitly selected cash refund for an original card sale, with unchanged counts. Fixtures have collision guards and explicit BEGIN/ROLLBACK; cleanup was planned as transaction rollback before hosted creation. No persistent synthetic financial/Auth/Storage fixtures or new real sessions were created.

All fifteen recorded table counts matched before deployment and after the hosted suites: shops 3, Auth users 4, sessions 9, memberships 3, identity audits 3, operations 18, financial audits 18, command requests 18, outbox 18, journals 54, postings 113, inventory lots 11, lot movements 11 and purchase payables 3. Existing retained registration fixtures and immutable real financial rows were preserved.

The actual hosted synthetic ledger/page and twelve operation-detail responses were captured within a transaction that rolled back. The current Flutter codecs decoded the captured response, including correction/exchange labels, enriched return item summaries, exact values, remainders and immutable original details. This is captured-hosted-contract decoding, not a native client posting to hosted Supabase.

### Flutter, React and native

- Scoped Dart formatting: 46 files, zero changes; Flutter analysis: no issues. The full suite passed 452 tests before the allocation repair and **454 tests in the final run**, including explicit full-remaining confirmation and refund-allocation regression coverage. Final analysis passed with no issues; the final hosted-response codec regression also passed separately.
- React lint, all 37 tests in nine files, and `npx --offline tsc -b` passed. React implementation/tokens were unchanged.
- Android emulator `emulator-5554`, Android 16/API 36: `flutter test integration_test/compensation_review_test.dart -d emulator-5554 --no-pub` passed all six focused debug/native cases, covering correction, return and exchange in both themes. Gateways and secure storage are synthetic; this is native UI/command-envelope evidence, not hosted financial posting or native secure-storage acceptance.
- Twelve widget captures at 320×1200 and 1440×1200 cover the three workflows in light/dark Arabic RTL. Six native captures supplement them. Signed effects use isolated LTR numeric values in Arabic labels. Keyboard-aware test taps were corrected after the initial native exchange attempt missed an off-screen action. The final native run passed; after the continuation disconnected the device, the existing Pixel 9 emulator was started headlessly without a wipe/reset and all six cases passed again. The earlier failed/offline attempts are not accepted evidence.

[Widget captures](screens) and [Android synthetic captures](native) preserve the shared palette and accepted replacement form. The narrower controls, review hierarchy, exact signed values and both themes were inspected. No unrelated owner acceptance was repeated.

### Advisors and limitations

After both deployments, the security advisor reports no ERROR finding: 50 intentional authenticated SECURITY DEFINER RPC warnings (45 before this slice), three deny-by-default RLS tables without policies and disabled leaked-password protection. Owner/RLS/command gates passed; unrelated settings were not changed. [RPC advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password-protection guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Still unverified: running native client → hosted financial success/reconciliation across sessions/restarts; real timeout-after-commit/network races; Windows/iOS and physical-device execution; final owner acceptance of the added controls; staging/pilot and wider milestone acceptance. The prior app approval remains intact. These evidence gaps must not be presented as completed Milestone 0–3 acceptance.

## Final delivery checkpoint

Both reviewed migrations are deployed and normalized readback matches their sources. Final local clean replay and all twelve SQL/RLS suites, local independent-connection races, hosted rollback/compatibility/atomicity checks, actual hosted-response decoding, scoped formatting, Flutter analysis/all 454 tests, React lint/all 37 tests/TypeScript and all six focused Android synthetic native cases pass. Arabic RTL phone/desktop light/dark review includes the final spacing and full-remaining confirmation state. Documentation links, consistency, privacy and `git diff --check` pass.

The task-owned local database cluster is stopped with its synthetic concurrency fixture/audit records retained. The task-started headless emulator is stopped after validation. Hosted cleanup required no deletion because every financial fixture rolled back. No commit, push, distribution, release/production build, data reset or payment-method-settings integration occurred. Whole-milestone and remaining real native-to-hosted/owner/staging acceptance stay open as listed above.

# ADM-02/ADM-08 final correction — implementer record

Date: 2026-10-22. Final bounded correction of the current ADM-02 tree. `validation.md` and `correction.md` are unchanged historical records. Independent review, hosted deployment, frontend publication, browser matrix and owner acceptance were not run. No commit or push.

## Defects fixed

1. The origin lease is a required argument of `issueSubscriptionCode`. After the pre-write session probe and before the RPC, the gateway asserts that exact user and session. The same assertion runs on completion and on a read retry. There is no unbound production write route. `authorizeCopy` asserts the lease after the awaited `get(shopId)` as well as before it. A delayed or missing auth event cannot issue or authorize copy under a replacement admin session. Same-session token refresh still accepts one write without automatic issue/retry. Tests cover silent replacement, missing binding, and post-get copy reassert.

2. History order compares exact UTC instants, including fractional microseconds and offset-equivalent timestamps. `Date.parse` milliseconds are not used. `next_cursor` timestamp and id bind to the last returned row. An input cursor must sit strictly after the first row in keyset order. Tests accept `.000002Z` id `...001` then `.000001Z` id `...002`, accept an offset-equivalent first row, and reject reversed order, a cursor timestamp that does not match the last row, and a first row that is not after the input cursor.

3. After entitlement `SELECT FOR UPDATE`, the redeem path captures `FOUND`, refreshes `clock_timestamp()`, and rechecks owner session, ban, unrevoked shop binding and code expiry before renewal. The new clock decides an active extension versus a new expired/future term. Issue and redeem recheck live owner/shop binding after a prior-request or code row-lock wait before replay or mutation. Typed committed attempts and replay-before-throttle stay in place. Separate-connection tests cover session expiry, membership revocation, code expiry and entitlement expiry while the entitlement row is locked.

4. Session-expiry-during-wait tests set `not_after` strictly after the waiter `xact_start` and before lock release, assert those relations, then let time elapse without a further update. That requires the current-clock guard; `caller_session_accepted()`/`now()` alone would still accept. Assertion messages do not include raw returned secrets.

5. `watchBoundSession` arms a timer for bound `expires_at`, rearms on same-session refresh, and clears on unwatch/release. NaN, Infinity and missing expiry invalidate the lease. A fake-timer test expires with no further UI or auth event. An old timer does not clear a correctly refreshed lease.

6. Bind unavailability shows Arabic pending, failure and retry, and disables issuance until a session is bound. `issuing` and copy latches reset on pagehide and selected-shop disposal. An abandoned in-flight issue cannot leave a reopened form inert, restore the old secret, or issue automatically. Tests cover unavailable bind plus retry, and pagehide during pending issue followed by an explicit new review.

## Fresh checks

| Gate | Result |
| --- | --- |
| Admin lint | From `admin/`, `npm run lint` (oxlint). Exit 0, no warnings. |
| Admin typecheck | From `admin/`, `npx tsc -b --pretty false`. Exit 0. |
| Admin tests | From `admin/`, `npm test -- --maxWorkers=1`. **14 files, 115 tests**, exit 0. |
| SQL rollback (function defs), redemption, ADM-02 SQL/hosted, ADM-01 SQL/hosted, identity RLS/commands, shop sync, two-connection races | From the repository root, `pwsh -NoProfile -File supabase/tests/admin_subscription_codes_local_runner.ps1 -Database eldaftar_admin_subscription_codes_adm02finalh`. Printed `ADMIN_SUBSCRIPTION_CODES_MIGRATION_ROLLBACK_PASSED`, `SUBSCRIPTION_REDEMPTION_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_HOSTED_SQL_PASSED`, `ADMIN_SUBSCRIBERS_SQL_PASSED`, `ADMIN_SUBSCRIBERS_HOSTED_SQL_PASSED`, `IDENTITY_RLS_SQL_PASSED`, `IDENTITY_COMMANDS_SQL_PASSED`, `SHOP_SYNC_SIGNALS_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_CONCURRENCY_PASSED`. Exit 0. Dedicated loopback port **55475** was stopped. Database `eldaftar_admin_subscription_codes_adm02finalh` was left in the local data directory. Earlier suffixes `adm02impl`, `adm02implb`, `adm02implc`, `adm02imple`, `adm02corr`, `adm02final`, `adm02finalb`, `adm02finalc`, `adm02finald`, `adm02finale`, `adm02finalf` and `adm02finalg` were left in place. |
| `git diff --check` | Exit 0. |
| Flutter | Not rerun. |

No `npm run build`, release/production build, real code issuance, hosted migration or frontend publication was run.

## What this record does not claim

Independent source review after this final correction was not done. Hosted SQL against `xchapwvmvoefriqcxtvn` was not run. The React frontend was not published. Browser matrix verification remains Codex's. Owner acceptance remains open.

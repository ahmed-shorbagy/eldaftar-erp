# ADM-02/ADM-08 correction — implementer record

Date: 2026-10-22. Correction of the Codex-reviewed ADM-02/ADM-08 tree. The first implementer record `validation.md` is unchanged. Independent review, hosted deployment, frontend publication and owner acceptance were not run. No commit or push.

## Defects fixed

1. Opaque selected-shop session binding/lease. Origin user and session are compared on issue, retry, copy and history continuations. Sign-out, account switch, same-user replacement session and local expiry invalidate immediately. Copy performs a live `admin_get_subscriber_v1` read. Visible/focus revalidate without automatic issuance. Same-session token refresh keeps a valid secret and does not write twice. Unknown or replaced sessions cannot adopt the lease. Code-path probes reject expired and malformed sessions; directory list/get contracts stay as they were. Listeners unsubscribe and stale checks cancel.

2. Copy-after-dismissal race: action/mounted generation plus secret and session equality after every await before `clipboard.writeText`. Pending copy is disabled. Callbacks after dismissal or access loss are inert. Tests cover pending-copy then close, and replaced-session while the copy check is pending.

3. One transient secret store; issuance metadata no longer carries the code. Dismiss, navigation, pagehide, unmount, access loss, session loss, selected-shop change and copy authorization errors purge the visible and backing secret. Late responses do not repopulate it.

4. History issue/retry/paging use request, mounted and shop guards. Other-shop pages are dropped. Stale reads cannot overwrite a newer page or selected shop or resurrect a secret.

5. `unusedSubscriptionCodeMethods` left production `SubscriberDirectoryGateway.ts`. Fixture helpers live in `admin/src/test/subscriptionCodeGateway.ts`. Production gateway methods stay real.

6. Issue parse requires exactly one row matching shop, request key, duration and `issued_via`, validates then drops `owner_user_id`. History parse matches shop, page size, canonical cursor, unique order-consistent rows, and status/redeemed metadata without using the client clock. Invalid write bodies freeze the envelope as an unknown outcome with same-key retry. Arabic copy distinguishes conflict, not-found, unavailable and unknown. Transport uncertainty does not claim certain failure.

7. `private.subscription_session_live()` checks session `not_after` and bans against `clock_timestamp()` after locks. Missing session-id claims remain accepted for legacy fixtures. Global `caller_session_accepted()` is unchanged. Separate-connection tests cover admin revocation, session deletion and session expiry while issuance is blocked; owner session expiry and revocation while redemption is blocked; same-key concurrent issue (one row, one event, issued+replayed); same-key concurrent redeem (activated+replayed); different keys extend once; committed invalid attempts persist throttle; successful replay still precedes throttle. Runner rollback compares original issue/redeem/guard function definitions, not only absence of new objects. Existing redemption, ADM-01, identity RLS/commands and shop-sync tests ran on the same fresh database.

8. After Shift-Tab from Close to Issue, another Shift-Tab reaches the named detail scroll region. Escape, focus restoration and late-reply assertions stay in place.

## Fresh checks

| Gate | Result |
| --- | --- |
| Admin lint | From `admin/`, `npm run lint` (oxlint). Exit 0, no warnings. |
| Admin typecheck | From `admin/`, `npx tsc -b --pretty false`. Exit 0. |
| Admin tests | From `admin/`, `npm test -- --maxWorkers=1`. **14 files, 106 tests**, exit 0. |
| SQL rollback (function defs), redemption, ADM-02 SQL/hosted, ADM-01 SQL/hosted, identity RLS/commands, shop sync, two-connection races | From the repository root, `pwsh -NoProfile -File supabase/tests/admin_subscription_codes_local_runner.ps1 -Database eldaftar_admin_subscription_codes_adm02corr`. Printed `ADMIN_SUBSCRIPTION_CODES_MIGRATION_ROLLBACK_PASSED`, `SUBSCRIPTION_REDEMPTION_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_HOSTED_SQL_PASSED`, `ADMIN_SUBSCRIBERS_SQL_PASSED`, `ADMIN_SUBSCRIBERS_HOSTED_SQL_PASSED`, `IDENTITY_RLS_SQL_PASSED`, `IDENTITY_COMMANDS_SQL_PASSED`, `SHOP_SYNC_SIGNALS_SQL_PASSED`, `ADMIN_SUBSCRIPTION_CODES_CONCURRENCY_PASSED`. Exit 0. Dedicated loopback port **55475** was stopped. Database `eldaftar_admin_subscription_codes_adm02corr` was left in the local data directory. Earlier suffixes `adm02impl`, `adm02implb`, `adm02implc` and `adm02imple` were left in place. |
| `git diff --check` | Exit 0. |
| Flutter | Not rerun. Codex independently ran all 1591 Flutter tests and direct Dart SDK analysis (pass). `flutter analyze --no-pub` remains the documented AOT launcher failure. |

No `npm run build`, release/production build, real code issuance, hosted migration or frontend publication was run.

## What this record does not claim

Independent source review after this correction was not done. Hosted SQL against `xchapwvmvoefriqcxtvn` was not run. The React frontend was not published. Browser matrix verification remains Codex's. Owner acceptance remains open.

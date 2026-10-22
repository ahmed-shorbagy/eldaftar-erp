# ADM-01 subscriber directory — local validation

Date: 2026-10-22. This record covers the read-only directory slice in [ADR 0027](../../adr/0027-admin-subscriber-directory.md). It is local verification only. Hosted deployment, hosted role tests and owner acceptance were not run. Weekly Reports evidence and the calendar local runner were left in place. No commit or push.

## Delivered behavior

A signed-in platform administrator sees «المشتركون» instead of the prototype shell. Missing configuration and failed startup still show the prototype. The page shows four global counts (all, active, pending, expired) and a separately labelled filtered count. Search accepts a shop name or a full shop id. Status filters are الكل، ساري، بانتظار التفعيل، and منتهٍ. Paging is server keyset order by registration time then shop id, 20 rows on the client, at most 25 in SQL. The detail dialog shows the same allowlist. Shops with no entitlement are listed. Status comes from the server clock using the existing pending, active and expired rule. Dates render in Arabic with Latin digits, once in UTC and once for the snapshot line. Subscription status is labelled as independent of owner-account access.

`admin_list_subscribers_v1` and `admin_get_subscriber_v1` check the live admin session inside the same statement as the read. Anonymous callers, ordinary owners, count-only staff, revoked administrators, anonymous or deleted identities, currently banned administrators, and expired or unknown sessions are rejected. User metadata is not read. Contact, location, ledger, customer, invoice, report, media and audit columns are not returned. Existing shop report and customer reads still deny a platform administrator. The read does not change finance, entitlements, dispatch or business audits inside the fixture.

## Fixture correction before the passing SQL run

The first local runner attempt applied every migration, rolled the new migration back, reapplied it, then failed in `admin_subscribers.sql` with `read_effect`. The digest compared `timestamptz::text`, which changes when the test sets `TimeZone`. The digest now formats entitlement bounds in UTC. The same attempt also taught the shops visibility check to treat a missing table privilege as denial. The migration SQL was not changed between the failed attempt and the passing rerun. The passing run is the one recorded below.

## Fresh checks

| Gate | Result |
| --- | --- |
| Admin typecheck | From `admin/`, `npx tsc -b --pretty false`. Exit 0. |
| Admin lint | From `admin/`, `npm run lint` (oxlint). Exit 0, no warnings on the final run. |
| Admin tests | From `admin/`, `npm test -- --maxWorkers=1`. **12 files, 51 tests**, exit 0. |
| SQL rollback and behavior | From the repository root, `pwsh -File supabase/tests/admin_subscribers_local_runner.ps1`. Printed `ADMIN_SUBSCRIBERS_MIGRATION_ROLLBACK_PASSED` and `ADMIN_SUBSCRIBERS_SQL_PASSED`. Exit 0. The loopback cluster on port 55473 was stopped. |
| Flutter analysis launcher | From `app/`, `flutter analyze --no-pub` failed. The AOT analysis-server snapshot was invoked with the wrong runtime: `analysis_server.dart.snapshot is an AOT snapshot and should be run with 'dartaotruntime'`. No SDK or global configuration was changed. The crash log `app/flutter_15.log` was removed. |
| Direct Dart analysis | From `app/`, `dart analyze` finished with `No issues found!`. Exit 0. |
| Flutter tests | From `app/`, `flutter test --reporter compact` passed **1,591** tests. Exit 0. No `app/` source was edited for this slice. |
| Dart formatting | Not run. This slice edits no Dart files. The existing weekly Dart changes were left untouched. |
| `git diff --check` | Exit 0. |

The SQL fixture uses synthetic shops only. It checks execute grants, security-definer and empty `search_path`, absence of metadata and contact fields in the function text, the registration index, and denial for anon, a missing user, an owner whose metadata claims admin, count-only staff, a revoked admin, an anonymous identity, a deleted identity, a future-banned admin, and a metadata-only pretender. Expired and unknown sessions return `session_expired`. Exact start is active. Expiry equal to the server clock is expired. A start one microsecond in the future is pending. A shop with no entitlement is pending. Name search treats `%` and `_` as letters. A full UUID matches one shop. A partial UUID matches none. Duplicate names stay in id order. Keyset pages agree in `Africa/Cairo`, `UTC` and `Asia/Riyadh`. Global counts stay unfiltered while the filtered count follows search and status. Inserts made after a cursor was issued do not appear on that later page and do not duplicate the first page's ids. A fresh first page sees the new shops and the new counts. `list_financial_report_days_v1` and `get_customer_list_v3` return `forbidden` for the platform admin. `list_my_shop_accounts` returns no row. Direct shop reads are denied. An entitlement update is denied. The finance, entitlement, dispatch, audit, membership and media digest matches before the fixture's own later inserts. The transaction rolls back.

React tests cover the exact count `9007199254740993`, filter reset, literal `%_` search, refresh that keeps the applied search, a late list that cannot replace the current filter, access loss that clears the table and calls auth refresh, Escape on the detail dialog, a late detail that does not reopen it, retry, resume revalidation, and narrow cards in the dark theme. The ready-admin shell test now expects «المشتركون» when a directory gateway is injected. Failed startup and missing configuration still expect the prototype. Those older assertions were not removed.

## What this record does not claim

No browser at 320, 390 or 1440 was opened. jsdom checked the narrow card branch, dark `colorScheme`, Arabic labels and Escape. Pixel review in both themes, at ordinary and enlarged text, remains for the reviewer. No synthetic screenshot harness was added.

Hosted SQL against `xchapwvmvoefriqcxtvn` was not run. Migration history was not reconciled on the server. No preservation baseline of hosted entitlements or financial tables was taken. No Edge Function was deployed. The implementation pass stopped before that standing deployment because this run was limited to local gates.

ADM-01 is not fully accepted. Codes, renewal, activation, contact and location permissions, notifications, Help, forced updates, impersonation and retention are out of scope. Milestone 5 is not complete. Owner acceptance is not claimed.

## Reviewer corrections — 2026-10-22

Codex reviewed the first run above and asked for a correction-only pass. The first-run results stay as recorded. This section is the later pass. No commit, push, hosted SQL, or deployment was run. Flutter was not rerun. The first local database was not dropped.

### What changed

The directory gateway records the signed-in user, access token, and session id before each list or detail call and checks them again before accepting the reply. Sign-out, a different account, or a replaced session drops the reply. A same-user token refresh retries once with the same search and filter; a second change in that retry fails as retryable and does not keep the first payload. User metadata is not treated as authority. Explicit sign-out and an account change clear admin state immediately and invalidate an in-flight admin check. A same-user token refresh does not clear admin state before the next check.

Dates use the browser display zone by default, in Arabic, with Latin digits and the zone name. UTC and Africa/Cairo are covered, including an instant that is 21 October in UTC and 22 October in Cairo. Status still comes from the server. The page and the detail each show one «البيانات حتى» time.

`private.admin_subscriber_gate()` still returns `unauthenticated` and `session_expired`, and it still rejects a current ban. Identity and platform-admin membership now come from `public.is_platform_admin()`. Name search parses a full UUID once with `CASE`. The cursor must be 66 characters and exactly three canonical fields. The local runner requires a fresh database suffix and refuses a database that already exists. It no longer calls `dropdb`. Rollback and reapply remain.

The introduction is the business purpose. Field labels say بداية الاشتراك, نهاية الاشتراك, and البيانات حتى. Shop names are headings. Fields are a definition list. Large counts can wrap. The 1120-pixel measure and the palette are unchanged.

ADR 0027 now says each response is one snapshot and the cursor is a keyset. A later registration can appear on a later page. The fixture still inserts shops before and after an issued cursor and reads the next limited page; it is not a frozen cross-page snapshot and it is not two concurrent connections.

### Fresh checks for this pass

| Gate | Result |
| --- | --- |
| Admin lint | From `admin/`, `npm run lint` (oxlint). Exit 0. |
| Admin typecheck | From `admin/`, `npx tsc -b --pretty false`. Exit 0. |
| Admin tests | From `admin/`, `npm test -- --maxWorkers=1`. **12 files, 67 tests**, exit 0. |
| SQL rollback and behavior | From the repository root, `pwsh -File supabase/tests/admin_subscribers_local_runner.ps1 -Database eldaftar_admin_subscribers_adm01corr`. Printed `ADMIN_SUBSCRIBERS_MIGRATION_ROLLBACK_PASSED` and `ADMIN_SUBSCRIBERS_SQL_PASSED`. Exit 0. The loopback cluster on port 55473 was stopped. The database `eldaftar_admin_subscribers_adm01corr` was left in the local data directory. |

### What this correction pass does not claim

No browser at 320, 390, or 1440 was opened in this pass. Codex owns the synthetic Vite review and the final captures. Hosted SQL was not run, and `supabase/tests/admin_subscribers_hosted.sql` was not edited. `app/` was not edited. No release build was run.

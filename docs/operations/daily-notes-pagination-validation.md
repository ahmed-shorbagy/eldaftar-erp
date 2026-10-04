# Daily notes and ledger pagination

Local and hosted validation for owner-scoped daily notes and the bounded ledger feed. The latest hosted section includes real Auth/Storage HTTP evidence. This is not a device acceptance or signed-URL expiry record; earlier local-only records remain historical.

## Contracts

`post_daily_note` is the only note write. The shop and the open business day come from the owner session. The same idempotency key with the same canonical payload returns the original note. A different payload raises `payload_mismatch` and does not add a second audit row. A note inserts `financial_operations.kind = daily_note`, optional `daily_note_attachments`, one `daily_note_recorded` audit row, and one outbox row. It inserts no journal and does not change sale, purchase, or expense totals.

Text is required unless a verified private image is attached. The image must already exist in bucket `eldafttar-private-notes` at `shopUUID/dayUUID/clientUUID.jpg|png|webp`, owned by the caller, with `image/jpeg`, `image/png`, or `image/webp` and size at most 5MiB. An attachment whose owner expression is not distinct from true, including both owner columns null, is `attachment_rejected`. Registration does not replace the object. Clients have select and insert only. There is no client update, delete, or upsert grant.

A recorded idempotency key for the same shop is recognized before the active-entitlement and open-day gates. Replaying that key after the day is closed, or after the shop entitlement has expired, returns the original business day. A new key is still `day_closed` or `shop_not_active`.

`list_daily_notes` reads at most 50 rows. The text filter is applied before the limit. The page query materializes the matching operation ids first, then builds JSON for the returned page only. The latest note sequence is one indexed row, and a day with no notes reports sequence `0`. A day id from another shop is `invalid_input`. Attachment lookups have indexes on `(shop_id, operation_id)` and `(shop_id, business_day_id)`.

Device image files are AES-256-GCM with a fresh nonce and an authentication tag. The 32-byte key is in Flutter secure storage, scoped to the signed-in user and shop, and is not written into the file. A missing key, a corrupt key, or a tampered file fails closed and does not return plaintext. Delete removes only that user, shop, and object file. Signed URLs and tokens are not stored in the draft or the image file.

`get_ledger_operation_page` accepts a day, or the latest day, and either `before_sequence` or `after_sequence`. Both cursors are rejected. The limit is 1..100 and the query fetches limit+1. `shop_sequence` is an exact decimal string. The summary RPC still returns gross sale, purchase, and expense figures from the previous ledger function and replaces only the confirmed feed, capped at 100 rows, plus `feed_page`. `get_daily_ledger` and the previous v2 function remain. History past one page is walked with the page RPC. Two hundred is a single-response guard in the client, not a history cap.

The client asks `get_daily_note_status` before creating again. Upload uses `x-upsert: false`. HTTP 200 or 409 continues to the same note key and is not confirmation. Signed read URLs are requested for 300 seconds, must use the configured Supabase origin and the exact private bucket object path, and are not written to the note draft. After every notes or feed response, the gateway reads the current owner again. A mutation that may already have committed becomes unknown when that owner changed. A read is not applied. An owner mismatch before the request is still a rejection, because nothing was sent. A financial pending command still blocks financial buttons. The notes action is separate.

The notes screen tags list, search, and preview requests. An owner or day change discards the in-flight result. While a key is unknown, the original canonical payload stays immutable: a later day, edited text, or a new image is not substituted under that key. Status is reconciled before an edit or a new draft. Changed image bytes get a new object id. A local draft or file failure is shown in Arabic and the in-memory image stays. A confirmed server result stays success when local cleanup fails, so the client does not post the same request again by mistake.

Ledger `loadOlder` and `catchUp` capture the generation, owner, shop, day, and cursor before the await. A page for another shop or day is discarded. A result or error that arrives after reset, or for a new owner or day, is discarded. Reset does not clear a newer generation's busy flag. Adopting a summary whose rows sit entirely above the catch-up anchor does not move that anchor, so unseen rows between the held head and the new summary remain for the next catch-up. The older cursor is kept.

## Files

- `supabase/migrations/20261004090000_daily_notes_and_ledger_pagination.sql` (current filename; the original implementation record used `20261001132331`)
- `supabase/tests/local_storage_bootstrap.sql` (local `eldafttar_notes_test` only)
- `supabase/tests/daily_notes_pagination.sql`
- Flutter notes feature under `app/lib/src/features/daily_notes/`
- Ledger codec, HTTP gateway, activity merge, and the daily ledger screen integration

`supabase/run-rls-tests.mjs` is unchanged. Codex can add the new SQL file to that runner later.

## Original local SQL gate recipe (historical)

The original recipe specified `eldafttar_notes_test` on `127.0.0.1:55432`, a temporary copy of `supabase/tests/local_auth_bootstrap.sql` with that database-name guard, 19 existing nonempty migrations, Storage bootstrap, then notes, followed by six existing SQL tests and the notes suite. That migration/test count is historical; use the current recipe below. The notes suite and bootstraps have local database guards; the existing regression suites are rollback-only but do not all have database guards. The repository Auth bootstrap remains unchanged.

`supabase/tests/local_storage_bootstrap.sql` creates minimal `storage.buckets`, `storage.objects`, and `storage.foldername` / `filename` / `extension` only on local `eldafttar_notes_test`, and only when those objects are missing. The notes migration does not create them. It targets the hosted Storage schema: private bucket, authenticated select including an expired owner, insert only for an active owner on the current open day, with owner, path, media type, and size checks. Kind, audit, and outbox checks gain the note values without dropping kinds already permitted by another migration.

## Orphan objects

An uploaded object can remain without a note if the note RPC never confirms it. This slice does not delete it. Cleanup is a separate admin operation, not a client reset and not part of this migration.

## Independent local validation — 2026-10-04 (complete)

Only this local backend-validation subtask is complete. LED-05 and milestones 0–3 remain open. No hosted Supabase access or modification, corrections/payment-settings integration, commit, push, deployment, release build or React production build occurred.

Codex used PostgreSQL **17.11**, an independently initialized temporary cluster listening only on **127.0.0.1:55432**, and database **eldafttar_notes_test**. No existing cluster or database was reset. The existing repository Auth bootstrap was copied with only its database guard changed. All **22 earlier nonempty migrations**, then the minimal local Storage bootstrap, then **20261004090000_daily_notes_and_ledger_pagination.sql** applied with `ON_ERROR_STOP=1`. The empty corrections migration was skipped; corrections were not integrated. The notes migration needed no repair.

The first original suite run failed at `cross_list_succeeded`: its cross-shop fixture attempted to discover the foreign note/day under the other owner's RLS, producing a null day and unintentionally calling the default-day list. The repair discovers both synthetic IDs as the fixture administrator, asserts that the note exists, then switches back to `authenticated` before testing access. This also makes the detail check exercise an existing foreign note rather than null input. A subsequent attempt was inconclusive because the SQL source was edited while `psql` was reading it. All final runs use a frozen copy. An added same-shop closed-day fixture initially omitted `closed_at`; that fixture was corrected to satisfy the existing closure constraint. Historical run logs remain intact.

The final notes suite exited **0**, ending in `ROLLBACK`, in **89.8708882 seconds**. The frozen copy and repository test had identical SHA-256 `8AFB75EE13A026F1C311CB157A82B3F227B5F17EF22112C1FDA307277E75AD26`. The unchanged notes migration SHA-256 is `FE89CEB1660A3CCF1B131D8E9E2560252C5C6985FD41E0B8F59905A5523F045E`.

| Requested gate | Local evidence and result |
| --- | --- |
| Owner-only notes and attachments | Passed real `authenticated` role switches; foreign note/day RPC denial and private-object isolation, revoked membership, anonymous user/role, platform admin and stale/crossed sessions. Catalog checks confirm attachments have owner-scoped RLS and select-only client grants; five notes/page RPCs deny anonymous execution and have empty definer search paths. |
| Same-key retries | Passed original note identity/replay checks and explicit one operation, command request, audit and outbox checks after retry and mismatch. |
| Changed payload | Passed `payload_mismatch` rejection without duplicate rows. |
| Recognition after closure/expiry | Passed original-day replay and completed status after real closure; added actual entitlement expiry after a confirmed RPC, preserving replay/status and attachment visibility while rejecting a new key. Original pre-seeded expired-owner fixture also passed. |
| Invalid attachments | Passed null/wrong stored owner, duplicate registration, wrong upload owner, extra folder, malformed object ID, foreign day/shop paths, unsupported media and size above 5MiB. Owner cannot update/delete objects. These are SQL metadata/policy tests, not byte-content inspection by Storage HTTP. |
| No financial effects | Added full before/after equality of the ledger root excluding only feed/page metadata around actual text/image note RPCs, covering cash, stock, scrap and gross/gold summary. Existing no-note-journal, unchanged postings/day-version and gross totals checks also passed. |
| Pagination | Passed 520+ single-row history pages, thousands of rows with intentional gaps, bounded index plan, 100-row summary cap, both cursor directions, invalid cursors/limits, cross-shop/day checks, search-before-limit and notes limit rejection. Added same-shop other-day isolation and exact string values above `9007199254740993`. |

All nine existing regression suites also exited **0** against this migrated database: `identity_rls.sql`, `identity_commands.sql`, `egypt_owner_registration.sql`, `opening_balances.sql`, `opening_rls.sql`, `daily_ledger_trades.sql`, `invoice_price_components.sql`, `milestone_3_inventory.sql`, `milestone_3_inventory_rls.sql`. Combined result: **10/10 SQL suites passed**. No Flutter/React source changed, so application analysis/tests, UI captures and builds were not rerun for this SQL-fixture/documentation task.

### Commands and retained local evidence

Run directory: `C:\Users\Aqsa\AppData\Local\Temp\eldafttar-notes-validation-c80aed4b59c648a09a8a1dd283d4428e`. Logs remain local and contain only synthetic fixtures. `initdb.log`, per-migration `.sql.log` files, the nine named suite logs, `daily_notes_final.log`, `acl.log`, `rollback-counts.log` and server logs preserve the results, including earlier unsuccessful attempts. Temporary files are not repository artifacts.

The exact executable/connection arguments used throughout were:

```powershell
$pgBin = Join-Path $env:TEMP 'eldafttar-postgres17/pgsql/bin'
$taskDir = 'C:\Users\Aqsa\AppData\Local\Temp\eldafttar-notes-validation-c80aed4b59c648a09a8a1dd283d4428e'
& "$pgBin/psql.exe" --version
& "$pgBin/initdb.exe" -D "$taskDir/data" -U postgres -A trust --encoding=UTF8 --locale=C
# pg_ctl start failed with restricted-token error 87; direct hidden launch succeeded.
$taskProcess = Start-Process -FilePath "$pgBin/postgres.exe" -ArgumentList @(
  '-D', ('"' + "$taskDir/data" + '"'), '-h', '127.0.0.1', '-p', '55432'
) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$taskDir/server.stdout.log" -RedirectStandardError "$taskDir/server.stderr.log"
& "$pgBin/createdb.exe" -h 127.0.0.1 -p 55432 -U postgres eldafttar_notes_test
$boot = (Get-Content supabase/tests/local_auth_bootstrap.sql -Raw).Replace(
  "current_database() <> 'eldafttar_test'", "current_database() <> 'eldafttar_notes_test'")
Set-Content "$taskDir/auth.sql" $boot -Encoding utf8
```

Each file was applied with this exact invocation, stopping on a nonzero exit; standard output/error was redirected to a separate local log:

```powershell
& "$pgBin/psql.exe" -h 127.0.0.1 -p 55432 -U postgres -d eldafttar_notes_test -X -v ON_ERROR_STOP=1 -f $file
```

Application order was `auth.sql`, `Get-ChildItem supabase/migrations/*.sql | Where-Object { $_.Length -gt 0 -and $_.Name -lt '20261004090000' } | Sort-Object Name`, `local_storage_bootstrap.sql`, then the notes migration. The nine regression files above used the same invocation. The final notes command was:

```powershell
Copy-Item -LiteralPath supabase/tests/daily_notes_pagination.sql -Destination "$taskDir/daily_notes_final.sql"
& "$pgBin/psql.exe" -h 127.0.0.1 -p 55432 -U postgres -d eldafttar_notes_test -X -v ON_ERROR_STOP=1 -f "$taskDir/daily_notes_final.sql" > "$taskDir/daily_notes_final.log" 2>&1
Get-FileHash supabase/tests/daily_notes_pagination.sql
Get-FileHash "$taskDir/daily_notes_final.sql"
Get-FileHash supabase/migrations/20261004090000_daily_notes_and_ledger_pagination.sql
```

Read-only catalog probes used `psql` with the same connection flags and `-c`: `has_table_privilege` for `anon`/`authenticated` on attachment SELECT/INSERT/UPDATE/DELETE and Storage UPDATE/DELETE, and `has_function_privilege('anon', oid, 'EXECUTE')`, `prosecdef`, `proconfig` for the five notes/page RPCs. Result: authenticated attachment SELECT only; no anonymous attachment access or RPC execution; no client Storage UPDATE/DELETE; all five definer search paths empty.

The exact `-c` SQL for those probes (line wrapping only):

```sql
select role_name,
  has_table_privilege(role_name, 'public.daily_note_attachments', 'SELECT') as attachment_read,
  has_table_privilege(role_name, 'public.daily_note_attachments', 'INSERT,UPDATE,DELETE') as attachment_write,
  has_table_privilege(role_name, 'storage.objects', 'UPDATE,DELETE') as storage_replace_or_delete
from (values ('anon'),('authenticated')) as roles(role_name);
select proname, has_function_privilege('anon', p.oid, 'EXECUTE') as anon_execute,
  p.prosecdef, p.proconfig
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and proname in
  ('post_daily_note','get_daily_note_status','get_daily_note','list_daily_notes','get_ledger_operation_page');
```

Post-run rollback verification queried counts for `shops`, `financial_operations`, `financial_command_requests`, `financial_audit_events`, `financial_outbox`, `journals`, `journal_postings`, `daily_note_attachments`, and `storage.objects`: **all nine counts were zero**, matching the empty fixture baseline. Only the migration-created private bucket remains. The isolated server was shut down using `pg_ctl -D "$taskDir/data" -m fast -w stop`; the temporary cluster/logs were retained, with no pre-existing database deleted.

The exact rollback verification `-c` SQL (line wrapping only):

```sql
select 'shops' as relation,count(*) from public.shops
union all select 'operations',count(*) from public.financial_operations
union all select 'requests',count(*) from public.financial_command_requests
union all select 'audit',count(*) from public.financial_audit_events
union all select 'outbox',count(*) from public.financial_outbox
union all select 'journals',count(*) from public.journals
union all select 'postings',count(*) from public.journal_postings
union all select 'attachments',count(*) from public.daily_note_attachments
union all select 'storage_objects',count(*) from storage.objects;
```

`git diff --check` passed. Because the four scoped files are already untracked in this checkout, they were also checked individually with `git -c core.safecrlf=false diff --no-index --check -- NUL <file>`: no whitespace diagnostics (exit 1 denotes added-file differences). Documentation links, consistency and privacy were reviewed; previous dated records and unrelated working files were preserved.

### Later hosted validation remains open

There is no demonstrated local backend blocker. The minimal Auth/Storage bootstrap does **not** establish compatibility with the target project's real Storage schema, existing permissive policies or effective grants, GoTrue/session delivery, upload-time metadata, REST RPC behavior or signed URLs. Hosted application/rollback gates require separately authorized access, a real-schema/policy/grant preflight, and a hosted-safe rollback harness: the current notes suite deliberately refuses a nonlocal database. Do not remove that guard or apply either local bootstrap to hosted Supabase. Real upload/read/replacement denial and signed-URL expiry, device file picking/restart, and orphan cleanup need separate evidence. No hosted acceptance is inferred from this run.

## Independent hosted preflight and preparation — 2026-10-04 (awaiting approval)

The current bounded request authorizes read-only hosted inspection and local preparation only. It supersedes broader authorization in older progress text for this task. No hosted migration, synthetic SQL write, Storage upload or cleanup has run. Hosted validation, LED-05 and milestones 0–3 remain open.

### Read-only development evidence

All connector calls explicitly targeted `xchapwvmvoefriqcxtvn`. `supabase_get_project({id: "xchapwvmvoefriqcxtvn"})` confirmed `ACTIVE_HEALTHY`, database host `db.xchapwvmvoefriqcxtvn.supabase.co`, PostgreSQL `17.6.1.166`. Account-identifying project metadata is deliberately omitted here. `supabase_list_migrations({project_id: "xchapwvmvoefriqcxtvn"})` returned 22 migrations, ending with `20261004081229_milestone_3_inventory_contract` and `20261004081347_inventory_sync_operation_index`; daily notes is absent.

Exact SQL SELECTs are saved in [daily_notes_hosted_preflight.sql](../../supabase/tests/daily_notes_hosted_preflight.sql). Execute each statement separately as `supabase_execute_sql({project_id: "xchapwvmvoefriqcxtvn", query: <statement>})` to retain every result. The initial multi-statement read-only transaction returned only its final grant result; the missing schema/policy/bucket results were retrieved with the subsequent aggregated SELECTs. No user rows, credentials or tokens were selected.

- Actual database/session identity: database `postgres`, role `postgres`; `app.settings.project_ref` is absent. Independently inspected `pg_control_system().system_identifier` is the exact string `7678071634733212629`. The separate harness requires this fingerprint and database name; it cannot trust a caller-set project label. A database rebuild requires a fresh preflight and reviewed fingerprint update.
- Actual Auth schema has `users.is_anonymous` and `sessions.not_after`; the synthetic fixture insert columns exist. `users.is_sso_user` and `is_anonymous` default false. No custom user triggers were found. Real `auth.uid()` reads the scalar sub setting or JSON claims; `auth.jwt()` reads singular/plural JSON claim settings. The harness clears ambient JSON claims without replacing either function.
- Actual Storage objects include UUID `owner`, text `owner_id`, JSONB `metadata`, generated/default timestamps and object IDs; buckets include private flag, byte limit, MIME array and default `STANDARD` type. All columns used by the migration exist. `foldername`, `filename`, `extension` exist.
- There are **zero buckets and zero Storage policies**. Storage objects/buckets both have RLS enabled. Both `anon` and `authenticated` have effective SELECT/INSERT/UPDATE/DELETE grants on both tables. Absent policies deny row access; the migration adds only the bucket-scoped owner SELECT/INSERT policies. It does not revoke hosted global UPDATE/DELETE grants or change another bucket's access. Replacement denial must be established through RLS row effects and separately through HTTP.
- Storage has `protect_objects_delete` and `update_objects_updated_at` triggers. The delete guard raises SQLSTATE `42501` unless `storage.allow_delete_query=true`; the harness neither disables it nor sets that bypass. SQL delete denial alone therefore cannot prove the API's delete authorization.
- Notes table/functions/helpers and renamed legacy ledger function are absent, with no name collisions. Existing `get_daily_ledger_v2` is owned by `postgres`. The three actual enumerated constraints contain the current inventory/trade kinds; the migration's additive check extension preserves those expressions.

Read-only baseline counts, **not a post-test rollback result**:

| Relation | Count |
| --- | ---: |
| auth.users | 2 |
| auth.sessions | 8 |
| storage.buckets | 0 |
| storage.objects | 0 |
| public.shops | 1 |
| public.financial_operations | 18 |
| public.financial_command_requests | 18 |
| public.financial_audit_events | 18 |
| public.financial_outbox | 18 |
| public.journals | 54 |
| public.journal_postings | 113 |

### Reviewed mutation package

The migration [20261004090000_daily_notes_and_ledger_pagination.sql](../../supabase/migrations/20261004090000_daily_notes_and_ledger_pagination.sql) remains unchanged, SHA-256 `FE89CEB1660A3CCF1B131D8E9E2560252C5C6985FD41E0B8F59905A5523F045E`. Review covered hosted schema compatibility, additive constraints, owner checks, empty definer search paths, client grants, replay before entitlement/day gates, attachment metadata validation, atomic operation/request/audit/outbox writes, no journal writes and bounded exact-string feeds. No demonstrated migration failure warrants a repair before execution.

The separate [daily_notes_pagination_hosted.sql](../../supabase/tests/daily_notes_pagination_hosted.sql) retains the meaningful note/page assertions from the independently validated local suite. Local suite and Auth/Storage bootstrap guards are untouched. The hosted harness:

- Requires the inspected target fingerprint, existing notes migration, and no collisions with fixed synthetic owner/shop/session IDs before any fixtures.
- Uses repeatable-read, a 3-second lock timeout and 180-second statement timeout; snapshots every public table plus Auth users/sessions and Storage buckets/objects before a savepoint.
- Uses only synthetic owners, shops, financial fixtures and rollback-only Storage metadata. No HTTP bytes, login sessions or permanent test identities are created by this SQL run.
- Checks owner/RLS boundaries, replay/mismatch operation/request/audit/outbox counts, recognition after closure/actual expiry, attachment paths/owners/media/size, unchanged financial summaries/postings/day versions, search-before-limit, both pagination directions, same-shop day separation, thousands of rows/gaps, and sequence strings beyond JavaScript integer precision.
- Accepts denied UPDATE as either permission rejection or zero affected rows, reflecting real hosted grants. DELETE is limited to one synthetic path and cannot bypass the hosted protection trigger.
- Omits global `ANALYZE` and live constraint mutations from the local fixture. Logs the natural EXPLAIN plan without asserting a particular cost choice against stale hosted statistics; retains the index-existence, limit and behavioral pagination checks. Local indexed-plan evidence remains historical and intact.
- Rolls back fixtures to the savepoint, asserts every captured table count matches, reports exact before/after counts, then rolls back the whole transaction. After execution, an independent connector count query must also be recorded. On an error/timeout, explicitly roll back or discard that connection; no COMMIT is allowed.

Prepared harness SHA-256: `9B1356D68CF407D6B43F3DCEE5321A27BCBF046DC9A8C9AE02A6BC6C17AF4A7D`.

Local preparation checks passed: the unchanged hosted harness exited **3** against the disposable database with the expected target-refusal message, before fixture writes. A temporary local-only copy with a matching local database/address/fingerprint guard then exited **0**, passed all assertions and ended in `ROLLBACK`. All captured table counts matched (empty synthetic tables; one pre-existing bucket and 27 governorate reference rows unchanged). Its fixed report label still says the intended hosted project; this rehearsal is explicitly **local evidence only**. The temporary server was stopped and logs retained beside the historical logs.

Exact rehearsal commands (the first psql exit is the expected negative test):

```powershell
$pgBin = Join-Path $env:TEMP 'eldafttar-postgres17/pgsql/bin'
$taskDir = Join-Path $env:TEMP 'eldafttar-notes-validation-c80aed4b59c648a09a8a1dd283d4428e'
Start-Process -FilePath "$pgBin/postgres.exe" -ArgumentList @(
  '-D', ('"' + "$taskDir/data" + '"'), '-h', '127.0.0.1', '-p', '55432'
) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$taskDir/hosted-preparation.stdout.log" -RedirectStandardError "$taskDir/hosted-preparation.stderr.log"
& "$pgBin/psql.exe" -h 127.0.0.1 -p 55432 -U postgres -d eldafttar_notes_test -X -v ON_ERROR_STOP=1 -f supabase/tests/daily_notes_pagination_hosted.sql > "$taskDir/hosted-guard-negative.log" 2>&1
$localId = (& "$pgBin/psql.exe" -h 127.0.0.1 -p 55432 -U postgres -d eldafttar_notes_test -X -At -c 'select system_identifier::text from pg_control_system();').Trim()
$harness = (Get-Content supabase/tests/daily_notes_pagination_hosted.sql -Raw).Replace(
  "current_database() <> 'postgres'",
  "current_database() <> 'eldafttar_notes_test' or inet_server_addr() is distinct from '127.0.0.1'::inet"
).Replace("'7678071634733212629'", "'$localId'")
[IO.File]::WriteAllText("$taskDir/hosted-harness-local-rehearsal.sql", $harness, [Text.UTF8Encoding]::new($false))
& "$pgBin/psql.exe" -h 127.0.0.1 -p 55432 -U postgres -d eldafttar_notes_test -X -v ON_ERROR_STOP=1 -f "$taskDir/hosted-harness-local-rehearsal.sql" > "$taskDir/hosted-harness-local-rehearsal.log" 2>&1
& "$pgBin/pg_ctl.exe" -D "$taskDir/data" -m fast -w stop
```

No Flutter/React code or migration changed; no application gates or builds were rerun for this harness/documentation preparation. Scoped whitespace, documentation link/consistency/privacy review and `git diff --check` passed. SQL backend behavior was rehearsed as described; actual hosted SQL and Storage API results remain pending.

After explicit approval, recheck migration absence and package hashes; apply only this reviewed migration through `supabase_apply_migration`, then send the frozen hosted harness as one `supabase_execute_sql` query. Do not apply any other migration or either bootstrap. Record the actual assigned migration version, not an assumed filename-derived version.

Real Storage API validation remains a separate approval stage for temporary synthetic Auth/shop/day fixtures, image objects and scoped cleanup via the Storage/Auth APIs. It must test owner upload/read, foreign/anonymous denial, replacement/upsert/delete denial, and unchanged bytes after rejected replacement. Credentials must stay transient and out of repository/log output. A concrete fixture/cleanup package must be reviewed before requesting that approval. SQL metadata validation does not establish HTTP uploads, signed-URL expiry, GoTrue delivery, device picking/restart or orphan cleanup acceptance.

Current references checked: [Storage access control](https://supabase.com/docs/guides/storage/security/access-control) and [Storage schema](https://supabase.com/docs/guides/storage/schema/design). The web tool could not read the changelog markdown because of its content type; no SDK or API convention was changed based on assumed changelog contents.

## Independent hosted validation — 2026-10-04 (complete)

Only the bounded **hosted-validation subtask** is complete. LED-05 and milestones 0–3 remain open. After preparation, the user explicitly approved all Supabase work for this request, covering the reviewed migration, rollback SQL, temporary synthetic fixtures and scoped API cleanup. No local bootstrap or weakened local guard was used on hosted Supabase.

### Demonstrated failure and minimal repair

The first `supabase_apply_migration({project_id: "xchapwvmvoefriqcxtvn", name: "daily_notes_and_ledger_pagination", query: <reviewed migration>})` failed with SQLSTATE `42501`, `must be owner of table objects`. Independent reads confirmed the migration record, notes table and bucket were absent: the transaction rolled back. Storage tables belong to `supabase_storage_admin`; project `postgres` has grant options and policy-management support but cannot unconditionally alter the managed table.

The only migration repair conditionally enables Storage RLS when it is not already enabled. Hosted RLS stays enabled; no owner, grant, trigger or policy was weakened. The reviewed repaired migration succeeded through the same apply call. `supabase_list_migrations` confirmed **`20261004120509_daily_notes_and_ledger_pagination`**, the actual hosted assigned version. Current migration SHA-256: `51FA2AE5236D49E2F923626735B08C97541579C9BF9E972FFDF177A480C9F636`. The pre-repair hash above remains historical evidence.

[daily_notes_storage_rls_local.ps1](../../supabase/tests/daily_notes_storage_rls_local.ps1) extracts the **actual migration block** for a meaningful local regression. It proves unconditional ALTER by a non-owner is denied, the repaired block succeeds with already-enabled RLS, and the owner path enables disabled RLS. Exact command `& supabase/tests/daily_notes_storage_rls_local.ps1` passed, exit 0 and `ROLLBACK`; redirected log `hosted-storage-rls-regression.log` is in the historical temporary run directory above. The disposable server was stopped and historical logs retained.

### Hosted SQL results and exact table counts

Exact call: `supabase_execute_sql({project_id: "xchapwvmvoefriqcxtvn", query: <complete frozen supabase/tests/daily_notes_pagination_hosted.sql contents>})`. Harness hash remained `9B1356D68CF407D6B43F3DCEE5321A27BCBF046DC9A8C9AE02A6BC6C17AF4A7D`. Result: **SQL checks passed; synthetic fixtures rolled back**.

Passed: owner isolation and revoked/anonymous/admin/stale-session boundaries; identical replay with one operation/request/audit/outbox; payload mismatch; recognition after closure and actual expiry; attachment ownership/path/MIME/size validation; unchanged financial balances/totals/postings/day versions; bounded feeds/catch-up, day separation, thousands of rows with gaps and exact string sequences above `9007199254740993`. Storage SQL denial was interpreted through real hosted grants/triggers, separately from HTTP evidence below.

All **36 counts match** before fixtures, after rollback to the savepoint, and in the independent final query after HTTP cleanup. This baseline is **after migration**: the newly configured bucket persists at 1, compared with pre-migration 0.

| Relation | Before SQL fixtures | After SQL rollback | After HTTP cleanup |
| --- | ---: | ---: | ---: |
| auth.sessions | 8 | 8 | 8 |
| auth.users | 2 | 2 | 2 |
| public.bullion_denominations | 0 | 0 | 0 |
| public.business_days | 2 | 2 | 2 |
| public.coin_types | 0 | 0 | 0 |
| public.daily_note_attachments | 0 | 0 | 0 |
| public.egypt_governorates | 27 | 27 | 27 |
| public.financial_audit_events | 18 | 18 | 18 |
| public.financial_command_requests | 18 | 18 | 18 |
| public.financial_operation_details | 17 | 17 | 17 |
| public.financial_operations | 18 | 18 | 18 |
| public.financial_outbox | 18 | 18 | 18 |
| public.gold_obligations | 0 | 0 | 0 |
| public.identity_audit_events | 1 | 1 | 1 |
| public.inventory_catalog_events | 0 | 0 | 0 |
| public.inventory_catalog_requests | 0 | 0 | 0 |
| public.inventory_command_envelopes | 0 | 0 | 0 |
| public.inventory_explicit_plans | 0 | 0 | 0 |
| public.inventory_lot_movements | 11 | 11 | 11 |
| public.inventory_lot_sync | 18 | 18 | 18 |
| public.inventory_lots | 11 | 11 | 11 |
| public.inventory_products | 11 | 11 | 11 |
| public.inventory_receipts | 0 | 0 | 0 |
| public.invoice_dispatch_confirmations | 0 | 0 | 0 |
| public.journal_postings | 113 | 113 | 113 |
| public.journals | 54 | 54 | 54 |
| public.ledger_accounts | 33 | 33 | 33 |
| public.platform_admins | 1 | 1 | 1 |
| public.purchase_cash_payables | 3 | 3 | 3 |
| public.receipt_quantity_allocations | 0 | 0 | 0 |
| public.shop_entitlements | 1 | 1 | 1 |
| public.shop_memberships | 1 | 1 | 1 |
| public.shops | 1 | 1 | 1 |
| public.traders | 0 | 0 | 0 |
| storage.buckets | 1 | 1 | 1 |
| storage.objects | 0 | 0 | 0 |

Exact final count query construction (relation names come from the guarded harness report):

```javascript
const union = Object.keys(sqlReport.counts).map(relation =>
  `select '${relation}' relation,count(*) n from ${relation}`).join(' union all ');
await supabase_execute_sql({project_id: 'xchapwvmvoefriqcxtvn',
  query: `select jsonb_object_agg(relation,n) as counts from (${union}) c;`});
```

### Real Auth/Storage HTTP results and cleanup

Reviewed artifacts: [HTTP checks](../../supabase/tests/daily_notes_storage_hosted.mjs), [phase driver](../../supabase/tests/daily_notes_storage_hosted_runner.mjs), [setup SQL](../../supabase/tests/daily_notes_storage_hosted_fixtures.sql), [cleanup SQL](../../supabase/tests/daily_notes_storage_hosted_cleanup.sql). SQL checks the actual cluster fingerprint; HTTP checks the project and credential JWT project/role claims, rejects redirects and uses only target-relative requests. Credentials, random passwords and tokens remain in memory, outside repository files and output.

The connector provides publishable/anon keys. For privileged API cleanup, the signed-in dashboard's **existing** legacy server key was read through its visible key control using the Browser skill, retained in memory and sent only to this project's synthetic Auth/Storage APIs. No credential was created or changed; the dashboard tab was closed. The first restricted-network attempt failed with socket `EACCES` before any account creation. The network-enabled worker completed. No temporary DELETE policy was created. The worker was stopped and transient credential bindings cleared after cleanup.

Exact command: `node supabase/tests/daily_notes_storage_hosted_runner.mjs`. Input echo was disabled before supplying the in-memory `{projectId,anonKey,serviceKey}` configuration. Subsequent newline-delimited commands, in order: `{"phase":"createUsers"}`, `{"phase":"run"}`, `{"phase":"cleanupObjects"}`, `{"phase":"cleanupUsers"}`. Setup SQL ran between createUsers/run; application cleanup SQL ran between cleanupObjects/cleanupUsers. Both used `supabase_execute_sql` with explicit project and UUID-only placeholder substitution from the manifest. Two synthetic users were created by Auth admin API, assigned separate shops and signed in through the real password endpoint; this is not SMTP or application registration acceptance.

Exact synthetic replacements:

```json
{"SHOP":"eb603bee-7beb-4af8-b3d3-273f80ad7ddd","OTHER_SHOP":"fdfa2178-5c4b-4ec2-b2a8-9c0e7b584712","DAY":"c5452610-c1ac-4fa5-b5ac-a54b9581c063","OWNER":"ec36e61f-6690-4aec-a091-5cf0225025f3","OTHER_OWNER":"397982c6-259a-47b0-8ea6-8db3be460988"}
```

Object path: `eb603bee-7beb-4af8-b3d3-273f80ad7ddd/c5452610-c1ac-4fa5-b5ac-a54b9581c063/b17978ba-01de-4875-9460-3b9c7acf6b00.png`.

| HTTP check | Result |
| --- | --- |
| Synthetic Auth creation / password sign-in | HTTP 200 for both users |
| Owner PNG upload, `x-upsert:false` | HTTP 200; 68 bytes |
| Owner authenticated read | HTTP 200; exact bytes |
| Foreign owner / anonymous / public URL read | HTTP 400; no bytes disclosed |
| Duplicate non-upsert / upsert replacement / PUT replacement | HTTP 400 |
| Owner DELETE | HTTP 200, empty array; zero objects removed |
| Read after replacement/deletion attempts | HTTP 200; bytes unchanged |
| Foreign owner upload / malformed name / MIME mismatch / >5MiB upload | HTTP 400 |
| 300-second signed URL creation / immediate read | HTTP 200; exact bytes; expiry **untested** |
| Privileged exact-path Storage API cleanup | HTTP 200; exactly one object removed |
| Synthetic global sign-out / Auth admin deletion | HTTP 204 / HTTP 200, both users |

Real upload metadata had both owner columns set to the synthetic owner, MIME `image/png`, numeric size/contentLength 68. A separate note RPC transaction accepted that actual upload, asserted one attachment and then rolled back; final attachment count is zero. Exact probe is recorded below. Final synthetic shop/user lookups returned zero. Application fixtures were removed only after API object cleanup, then accounts were globally signed out and deleted through Auth admin API. No synthetic financial operation was committed. Auth service request/audit logs may remain; no service logs were purged and they are outside the 36-table unchanged-count claim.

Exact real-upload metadata probe, executed through `supabase_execute_sql` on `xchapwvmvoefriqcxtvn`:

```sql
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','ec36e61f-6690-4aec-a091-5cf0225025f3',true),
  set_config('request.jwt.claims','{}',true),set_config('request.jwt.claim','',true),
  set_config('request.jwt.claim.session_id','',true);
do $probe$
declare result jsonb;
begin
  result:=public.post_daily_note('7d105762-488d-48e9-b153-de925023ac3d',jsonb_build_object(
    'version',1,'kind','daily_note','business_day_id','c5452610-c1ac-4fa5-b5ac-a54b9581c063',
    'text','اختبار مرفق مؤقت','attachment',jsonb_build_object(
      'client_object_id','b17978ba-01de-4875-9460-3b9c7acf6b00','mime_type','image/png',
      'extension','png','byte_size','68')));
  if result->>'ok' is distinct from 'true'
    or (select count(*) from public.daily_note_attachments
      where operation_id=(result->>'note_id')::uuid)<>1 then
    raise exception 'real upload metadata registration failed';
  end if;
end;
$probe$;
reset role;
select count(*) as temporary_attachment_count from public.daily_note_attachments;
rollback;
```

### Routine checks and remaining limits

- `dart format --output=none --set-exit-if-changed lib test`: 139 files, zero changes.
- `flutter analyze`: no issues, 4.8 seconds. The sandboxed attempt stalled without output and was interrupted; the final SDK-access run passed.
- `flutter test --reporter expanded`: **375 tests passed**, final reporter time 42 seconds.
- React `npm run lint`, `npm test -- --run` (**35 tests / 9 files**, 5.59 seconds), `npx tsc -b`: exit 0.
- Both `node --check` commands, actual-migration ownership regression, `git diff --check`, scoped untracked whitespace and documentation link/consistency/privacy checks passed. No UI implementation changed or new visual acceptance is claimed.
- `supabase_get_advisors({project_id: "xchapwvmvoefriqcxtvn", type: "security"})` reported three existing RLS-without-policy informational findings, 45 authenticated-definer warnings (including the intentionally owner-gated RPCs) and disabled leaked-password protection. No broad settings repair was made. Scoped owner isolation, anonymous execute denial and empty search paths passed. References: [definer warning](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS information](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

No required check for this bounded hosted-validation subtask is blocked. Signed-URL **expiry**, native device picking/restart, app-to-hosted end-to-end acceptance, SMTP, concurrent live-traffic/load testing and a general orphan-cleanup lifecycle remain unverified. No corrections/payment integration, commit, push, application deployment, release build or React production build ran. LED-05 and milestones remain open.

## Next bounded task

The next selected task is [daily-note persistence integrity](daily-notes-persistence-next-task.md): independently review the actual secure draft/encrypted image adapters, overlapping writes/cleanup, interrupted file writes and owner/shop isolation, with minimal demonstrated repairs. This is proposed work, not a new validation result. Preserve the completed hosted and restart-reconciliation evidence. Native device/app-to-hosted acceptance and signed-URL expiry remain separate follow-on work; LED-05 and milestones remain open.

## Limits

`get_daily_ledger_v2` keeps the previous gross sale, purchase, and expense totals and the net cash, stock, and scrap balances. Its confirmed feed is an indexed page of at most 100 rows and does not build the previous unbounded feed. Catch-up walks at most 20 pages of 100 per pass and continues on the next resume, timer, or refresh. A separate net and gross summary RPC is left for the compensation lane. Local SQL does not prove phone or desktop file picking, signed-URL expiry on a storage host, or a remote Supabase project. Review captures under `app/build/m03-notes-review` include the ledger controls and the note form, attached image, retry, and error at 320 and 1440 in both themes. No customer data and no service key are used.

## Independent local persistence integrity — 2026-10-04 complete

Only this persistence-integrity subtask is complete. Five demonstrated defect categories were repaired in the local adapters and persistence/cleanup call sites, with 13 new actual-adapter regressions. Final scoped formatting and Flutter analysis passed; all 388 Flutter tests, React lint, all 35 React tests in nine files and `npx tsc -b` passed. No backend behavior changed or Supabase operation ran. [Exact commands, reproduction evidence, repairs and limitations](daily-notes-persistence-validation-2026-10-04.md).

Earlier proposed-task and approval checkpoints above are historical. LED-05 and milestones 0–3 remain open; native secure storage, native picking/restart, device-to-hosted acceptance and signed-URL expiry remain unverified. No commit, push, deployment, release/production build or unrelated slice integration ran.

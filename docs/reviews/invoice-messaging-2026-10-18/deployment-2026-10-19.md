# Invoice message templates — authorized development application

2026-10-19, Africa/Cairo. After the local implementation/review/validation checkpoint, the owner explicitly authorized applying the concrete backend changes: “applly them you are authrized also”. Codex applied only the reviewed SET-04 metadata migration and a reviewed two-index follow-up to development `xchapwvmvoefriqcxtvn` through the connected Supabase plugin. The [earlier no-deployment record](no-deployment.md), [local validation](independent-validation.md) and [implementation review](implementation-review.md) remain unchanged historical checkpoints. This record supersedes their deployment status, not their evidence or acceptance limits.

| Local reviewed source | Hosted version / name | Raw source SHA-256 | Hosted normalized SQL SHA-256 |
| --- | --- | --- | --- |
| [20261018075947_invoice_message_templates.sql](../../../supabase/migrations/20261018075947_invoice_message_templates.sql) | `20261019063249` / `invoice_message_templates` | `2340064a9501017822a131e0c712297be006571ec93fe0e7c4593c117a5df986` | `2e132ee7104a67d8bccb81ecc9d06dfb894857341e264e44fd71694d40e6f783` |
| [20261019063514_invoice_message_actor_indexes.sql](../../../supabase/migrations/20261019063514_invoice_message_actor_indexes.sql) | `20261019063646` / `invoice_message_actor_indexes` | `1ccdbbeb60ea8a7eb9ef3fdcb15be8fd7cf706f8de6bbf6e44c88dd54112b241` | `fb146cc2adf252f8378fe1449910a072297a5fb36b94a24801c75061278a2d1e` |

Normalized SQL hashes remove CR and trim surrounding whitespace from UTF-8 source/stored statements. Both stored single-statement SQL hashes match their reviewed local sources under that normalization. The plugin assigned hosted timestamps; local sources were not renamed and history was not repaired to imitate them. Both `apply_migration` calls returned `success: true`. First application began 06:32:44 UTC; final preservation/advisor readback followed the second application. No blind `db push` or migration-history rewrite.

## Reconciliation and scope

All **40** existing hosted versions/names mapped to local sources before application. Thirty-seven full normalized source hashes matched. The two already documented comment/whitespace differences (`daily_ledger_trades`, `inventory_sync_operation_index`) and the 99-element repaired statement-array representation of `invoice_appearance` were inspected: full-line-comment/whitespace/statement-separator normalization matched, and the actual hosted `bump_shop_sync` and `invoice_operation_facts` bodies matched the local appearance prerequisites exactly. The empty historical preparation marker remains undeployed. All 40 prior migration rows, statement counts and hashes remain unchanged afterward; final count is 42.

The main migration adds three append-only owner-readable tables, separate message sync revision, parser/helpers and five narrow owner/session-checked RPCs. Only `private.bump_shop_sync` is replaced, retaining previous scope behavior. No defaults are backfilled: the three tables remain empty; all 11 message sync revisions are zero. Runtime read absence represents the existing four-line default. No appearance edition, financial payload or dispatch audit is rewritten.

After the first application, the performance advisor identified two missing covering indexes on the new tables' `(shop_id, actor_user_id)` foreign keys. A separate migration adds only those two indexes. The original migration remains byte-identical. The follow-up was generated with the Supabase CLI, [separately reviewed](deployment-review-2026-10-19.md), and verified on a fresh local cluster before its own hosted application. No new product policy or financial behavior was introduced.

## Preservation proof

[Exact aggregate before/after evidence and migration mapping](hosted-preservation-2026-10-19.json), [preservation query](hosted-preservation-query.sql). Only counts, deterministic digests and schema metadata are retained; no customer/contact rows, identity details, credentials or tokens are exported.

- **61 pre-existing protected public tables** have identical counts and canonical full-row SHA-256 before the first apply and after both applies. This covers cash/gold/stock/custody/ledger/debt/CRM/repair/dispatch/appearance/presentation/history, including prior audit/request rows.
- `shop_sync_signals` remains at **11 rows**. Its full digest changes only because of the added zero-valued column. Removing `message_revision` from each row produces the unchanged SHA-256 `2991ca3955a203fe5afea7f36804c04ffe60f27b3aeab88f514a44cb1f3b55e2`. No existing sync value or timestamp changed.
- Existing public/private function definitions **and grants**, excluding the permitted bump and 12 additions, retain SHA-256 `13405c77e8804f02062d3a6d14edce7f65412716f5dce64fe357cb646842743a`. Existing policy and trigger fingerprints are unchanged (MD5 equality checks, recorded separately from SHA-256 data/source hashes).
- Auth users (**12**), sessions (**16**), storage objects (**2**) and their full-row SHA-256 digests are unchanged. Bucket metadata digest is unchanged. No Auth or storage policy was modified.
- Public base-table count is **62 → 65**. All three additions have zero rows and the empty SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.
- The follow-up's own immediate before/after pair also changes no rows. It adds only two valid indexes. No hosted synthetic identity, session, membership, entitlement, save, financial operation, dispatch event or fault trigger was created; no retirement/delete/reset was necessary.

Activity before this new baseline is preserved. For example, financial operations now number 55 and journal postings 311, versus 51/295 in slice 10's earlier record. Those are not migration effects, and nothing was reset to the older totals.

## Verification and advisors

The [hosted rollback-only verification query](hosted-verification-query.sql) returned `HOSTED_READONLY_AUTHORIZATION_AND_PARSER_PASSED`. It checks template CRLF normalization/default reset/invalid-token rejection, authenticated direct-write denial and unscoped RLS visibility, all five RPCs rejecting absent identity, and anonymous execute denial. It performs no data writes. All **13** installed new/replaced function-body hashes match the reviewed source. All private helpers deny client execute; all five public RPCs allow authenticated execute and deny anonymous execute, with empty search paths. Each new table has RLS enabled and forced and exactly one owner-read policy. Both actor foreign keys have valid ready covering indexes.

The follow-up local command was:

```
pwsh -NoProfile -File supabase/tests/invoice_message_local_runner.ps1 -Database eldaftar_invoice_message_indexes_20261019 -Port 55465
```

Exit 0, fresh PostgreSQL 17.6 database. Log `eldaftar-invoice-message-indexes-20261019.log` in the task temp directory records main and index migration rollback/apply, `ACTOR_INDEXES_COVERAGE_PASSED`, message real-role SQL/RLS/atomic rollback, concurrency, historical appearance/sync/trade gates, `ALL_LOCAL_SQL_PASSED`, and `LOCAL_CLUSTER_STOPPED_DATA_RETAINED`. Both reviewed file hashes remained fixed. Earlier client gates (1,179 Flutter tests, analysis/formatting, React lint/38 tests/TypeScript and 276 RTL captures) were unchanged and were not needlessly repeated for the index-only follow-up.

Security advisor notices: the intentional [authenticated definer RPC notice](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) increases **107 → 112**, exactly the five new owner/session-checked APIs. Seven existing no-policy information notices and the pre-existing [leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remain; neither is claimed resolved. No new RLS/policy or mutable-search-path notice was introduced.

Performance: [unindexed FK notices](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys) temporarily increased **12 → 14**, then returned to **12** after the follow-up. The existing no-primary-key information notice remains one. [Unused-index notices](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) increase **30 → 33** for the three new indexes on empty metadata tables; these are intentional access/FK indexes, retained for future use. Existing unrelated findings remain outside this slice.

Native/two-device/screen-reader/owner acceptance remains open. SQL authorization checks do not establish actual hosted client session synchronization or real native WhatsApp behavior. No real messages, app distribution, Android/iOS/Windows release or React production build, publication, commit, push, reset or history deletion occurred.

Closing documentation checks: Codex resolved 414 local link targets with zero missing and reran `git diff --check` successfully. All 744 historical tracked files were rechecked against the initial HEAD baseline with zero changes (existing CRLF normalization for text, byte comparison for binaries). The separate reviewer cross-checked the deployment narrative against all 61 protected pairs, migration hashes, metadata/advisor totals and 27 evidence links; it found no concrete consistency or privacy error. Its review remained read-only with no hosted calls or gate reruns.

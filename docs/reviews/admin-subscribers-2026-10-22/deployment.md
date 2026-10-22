# ADM-01 development deployment — 2026-10-22

Only established development **xchapwvmvoefriqcxtvn** was used, under the owner's task selection and standing authorization in [AGENTS.md](../../../AGENTS.md). This record supplements [independent verification](independent-validation.md) and the preserved [implementation validation](validation.md). No production/other project, paid resource, reset or application publication was involved.

## Reconciliation and installed source

The pre-application catalog had **59** migration rows; each name matched a non-empty local migration. Only admin_subscriber_directory was pending. The historical empty ledger_pagination_and_corrections file remains unchanged. Both new public RPCs and their index were absent before application.

The connected migration API applied only the reviewed new SQL as **20261022094412 / admin_subscriber_directory**. The CLI-created local filename 20261022082352_admin_subscriber_directory.sql was then renamed to [20261022094412_admin_subscriber_directory.sql](../../../supabase/migrations/20261022094412_admin_subscriber_directory.sql), preserving its bytes. The runner discovers the migration by its unique suffix, so the identity reconciliation does not change its behavior. There was no history repair, historical replay or broad database push.

The raw local file SHA-256 and stored migration statement SHA-256 are identical:

    7cfb7cc128d845901acbb53c6be400273c6e9c9d8dc0d4c88e1f99a09d356ad6

Hosted history stores one statement array entry containing the exact submitted SQL. It adds one registration-order index, two public read RPCs and three private helpers; it creates no table and changes no financial, entitlement or media rows. No Edge Function was redeployed.

| Installed public function | SHA-256 of pg_get_functiondef |
| --- | --- |
| admin_list_subscribers_v1(text,text,text,integer) | f6c528773a0bc72d04e91567dc0b3af16608734e7668e90507cc430bb541941a |
| admin_get_subscriber_v1(uuid) | 595ab0e3c4ccd6aa9b145a8960640572850b06ad5c309de4b84edefe06a9cba6 |

Anonymous execution is denied. Authenticated execution reaches the live admin/session/ban guard; it does not grant shop-data permission. The three private helpers deny both anonymous and authenticated direct execution. Source and role fixtures establish the intended boundary.

## Hosted fixture and data preservation

The [hosted fixture](../../../supabase/tests/admin_subscribers_hosted.sql) first passed against a fresh local database, then against pinned development with its explicit transaction-local project guard. It uses repeatable-read isolation, baseline-relative counts and a unique synthetic namespace. It neither truncates nor edits existing shops/terms. It covers exact status boundaries, filtered/global counts, literal/identifier search, complete paging, metadata allowlists, owner/staff/banned/deleted/anonymous/revoked denial, session loss, live admin revocation and continued shop report/customer isolation. It rolls back and returned **ADMIN_SUBSCRIBERS_HOSTED_FIXTURE_PASSED**. An earlier connector call returned an expired-request-state error and was not counted as a pass; a fresh call succeeded. The migration itself was not retried.

Full-row SHA-256 fingerprints/counts were captured at server UTC **09:43:38.877211** before deployment and **09:54:28.007895** after hosted verification. All **76** entries match: all **72 public tables**, auth.users, auth.sessions, storage.objects and storage.buckets. No synthetic fixture account, session, grant, staff row, shop or entitlement remains committed. Raw manifests remain ignored; this record contains no row values or customer data.

History now has **60** rows. The original 59 rows, including statement arrays, retain this complete-row SHA-256:

    e6dbda386f5c97ae569ef1e270cbe9d4acbc710bf987c60fca77ddc2e35d95ef

Security advisors were compared before and after. The existing 13 deny-by-default RLS-without-policy information findings and leaked-password configuration finding are unchanged. Authenticated SECURITY DEFINER findings increase from 132 to 134 for the two intentionally admin-checked public APIs; real-role denials passed. [Function exposure advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [password configuration reference](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). No unexpected advisory category was introduced.

The React source remains local until separately run or distributed. Real owner acceptance and a real admin browser-to-hosted session remain separate. No application publishing, release/production build, commit or push ran.

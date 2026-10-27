# Next feature plan: HELP-02 support contact — 2026-10-27

Status: the owner selected HELP-02 on 2026-10-27 and this plan prepares the bounded slice. Implementation has not started; the [ready-to-paste prompt](help-support-prompt-2026-10-27.md) executes the task when submitted. The current delivered pointer remains SET-02/D24 payment methods: [task pointer](next-slice-prompt.md). Creating these planning documents runs no migration and deploys nothing.

## Why this feature

P-22 / HELP-02 in the [requirements matrix](../requirements-matrix.md): “If search fails, the user can contact support inside the app.” The delivered ADM-05 slice ([ADR 0031](../adr/0031-help-content-and-announcements.md)) already gives owners a platform-managed Arabic FAQ with client-side search (`app/lib/src/features/help/`) and platform admins content CRUD (`admin/src/help/`), but a search that finds nothing dead-ends: the empty and no-match states offer only retry. The app has no in-app way to ask for help and admins have no inbox.

ADM-05 deliberately kept HELP-02 separate. This slice supplies exactly the missing fallback; it does not expand the FAQ, add ADM-06 broadcasts, soft update banners, in-context guides ([ADR 0010](../adr/0010-owner-feedback-registration-and-ledger.md)) or retention.

## Proposed first-slice behavior

- **Entry.** The existing Help screen («المساعدة», reached from «المزيد») gains a persistent Arabic action «تواصل مع الدعم». It is always visible and is additionally emphasized for the current session when a search returns no match, so the no-result dead-end has a clear next step. A separate support route opens the inquiry form and the owner's own inquiry list.
- **Who may submit.** Authenticated single-owner shop accounts, including owners whose entitlement has expired: D13 already lets expired accounts read help content, and support about renewal must remain reachable, so write access follows the same reader set. Partner, employee and temporary count-only accounts cannot submit in this slice; anonymous callers are rejected at the database.
- **Submission.** One text-only form: optional category (اتصال بالاشتراك، مشكلة تقنية، سؤال بعد النقد، أخرى — enum on the server) and a required Arabic message body. Body: trimmed, 10–1000 characters after trimming, newline allowed, other control characters rejected, donor name/entity is the server session — never typed. No topic/article reference is required. No attachments, screenshots or audio: that would need a new R2 media kind per [ADR 0024](../adr/0024-cloudflare-r2-media-storage.md) and stays out of scope.
- **What is stored.** One row per inquiry: owner id, shop id, category, body, `new` status, server-generated UTC timestamps, an idempotency key and append-only audit of status changes. The server never copies ledger, customer, invoice or financial data into the inquiry. No automatic app-version or device fingerprint collection in this slice.
- **Rate limit.** At most 10 non-closed inquiries per shop; the form states the limit and blocks a new draft when it is reached, rather than silently failing.
- **Owner view.** The owner sees only their own inquiries newest-first: status, server-local date (shop time zone, LTR digits) and title/body. Paging is bounded keyset paging; the first page shows the latest.
- **Admin triage (bounded).** Platform admins get a read-mostly «الدعم الفني» mailbox in React: keyset list with status filter and search by exact shop identifier, and a read-only detail showing shop id/name and registration date (sources already readable under [ADR 0027](../adr/0027-admin-subscriber-directory.md)) plus the inquiry itself. Admin actions are limited to status transitions `new → in_progress → answered → closed` with a required non-empty Arabic reply text (10–1000 characters) when marking answered. Replies and status are immutable after save except the `answered → closed` step; every change is audited with the acting admin, key and server UTC.
- **Owner sees the reply.** The owner's inquiry list shows `answered`/`closed` with the reply text and server date. No push routine, no new notice type and no announcement integration in this slice; if a platform-wide notice is needed, admins can already use the ADM-05 announcement.
- **No reply hotline handoff.** No `wa.me`/dialer handoff for platform support in this slice; the inquiry record inside the app is the contact channel. An external contact singleton can be proposed later only if the owner asks.

## Authorization and data boundary (D21)

[D21](../decisions.md) says platform staff must not inherit access to shop customer/ledger data; access needs an explicitly approved, narrow, audited path. This slice creates exactly such a path for the inquiries themselves — owners author rows, admins read and triage them through `admin_subscriber_gate()` — while every pre-existing boundary stays intact:

- Inquiry tables remain RLS-on with no table grants to `anon`/`authenticated`; owners read/write only through versioned RPCs scoped to their own rows; admins list/update only through gate-checked security-definer RPCs.
- Admin mailbox surfaces shop id/name and registration date only — no ADM-07 contact/location PII, no subscription mutations, no ledger/stock/customer/invoice/report access and no R2 objects.
- Owner reads/writes have zero financial, entitlement, dispatch or business-audit effect. Submission is not a financial command; it still uses the command envelope, one idempotency key across retries, and definitive validation failures do not consume the key.
- Anonymous, cross-shop, revoked-owner, count-only and lost-session callers must fail; an expired owner can submit and read own rows; platform admins remain denied by ordinary owner-facing shop APIs.
- Record the bounded contract in a new ADR when implementation begins, stating that this explicit inquiry path does not implement the general D21 time-limited shop-data access mechanism (which stays separate).

## Backend sketch (to be reviewed against the live schema before migration)

Additive migration `20261027100000_support_inquiries.sql` following existing schema conventions:

- `support_inquiries` table (status enum or CHECK per existing style), `support_inquiry_status_events` append-only audit, indexes for keyset `(created_at, id)` and per-shop owner reads, and no new R2 kind.
- Owner RPCs: `create_support_inquiry_v1`, `list_my_support_inquiries_v1`. Admin RPCs: `admin_list_support_inquiries_v1`, `admin_update_support_inquiry_status_v1`, gate-checked like [ADR 0031](../adr/0031-help-content-and-announcements.md) admin writes. Helpers ungranted; `service_role` revoked where the role exists.

Name the contract before coding; the submitted prompt instructs inspecting the applied schema first and adjusting identifiers to match house conventions while keeping `_v1` versioning.

## Delivery steps

1. Inspect the applied development schema, ADM-05 gateway/screen and React help code; record the exact read/write contract in the new ADR.
2. Add rollback-only SQL/RLS tests (insert/read/status rules, expired-owner allowance, staff/anonymous/admin-denials, rate limit, audit append-only, idempotent replay) before any hosted application.
3. Implement the Flutter support route and Help entry (domain → data → presentation, Supabase adapter behind the domain-owned interface), with pending/confirmed/failure states, duplicate-tap prevention and preserved idempotency key.
4. Implement the React «الدعم الفني» mailbox with loading/empty/retry/access-loss states and immutable reply/status editing.
5. Run scoped gates: Dart formatting/`flutter analyze`/`flutter test`; admin `npm run lint`/`npm test`/`npx tsc -b`; affected SQL/RLS/atomicity checks. Arabic RTL visual review in both themes at 320/390/1440 and enlarged text.
6. Deploy only the reviewed task changes to development `xchapwvmvoefriqcxtvn` under standing authorization, run hosted role/behavior tests with rollback fixtures, and record preservation of all data and migration history.
7. Update the ADR, requirements matrix, plan, decisions, task pointer and dated validation/deployment records. Owner/device acceptance and frontend publication remain open; no commit, push, publication or release build.

## After this slice

HELP-02 closes the P-22 support fallback. Remaining Help-family scope stays separate: ADM-06 broadcast workflow, video content, soft optional-update banners, and actual D21 shop-data access if ever product-approved. The DOC-04 native invoice-output harness ([acceptance checklist](../reviews/stabilization-2026-10-21/acceptance.md)) and the Milestone 4/5 owner/device acceptance items remain visible backlog and are not replaced by this feature.

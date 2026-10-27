# ADR 0036: In-app support inquiries and admin triage (HELP-02)

Status: implemented, locally verified, and deployed to the development project `xchapwvmvoefriqcxtvn` on 2026-10-27 (migration `20261027150000` applied and marked applied; hosted rollback-only role/behavior gate passed; preservation counts unchanged). [Contract](../../supabase/contracts/support-inquiry-v1.md), [validation](../reviews/help-support-2026-10-27/validation.md), [deployment](../reviews/help-support-2026-10-27/deployment.md). Bounded HELP-02: one text-only owner support form and a platform-admin triage mailbox. Does not add attachments (no new R2 media kind per [ADR 0024](0024-cloudflare-r2-media-storage.md)), ADM-06 broadcasts, soft-update banners, in-context guides ([ADR 0010](0010-owner-feedback-registration-and-ledger.md)), WhatsApp handoff, hotline links, retention, or push/notice integration. Owner/device acceptance and publication remain open.

## Explicit narrow support path (D21 approval rule)

This feature is an explicit, audited support path: platform staff read and triage only inquiries the owner deliberately wrote for support. It does **not** implement the general D21 time-limited shop-data access mechanism, which stays a separate proposal. Admin reads expose shop id/name and registration-date context only — no ADM-07 contacts/location ([ADR 0027](0027-admin-subscriber-directory.md)), no subscription mutation, no ledger/stock/customer/invoice/report/R2 access.

## Decision

| Rule | Bound |
| --- | --- |
| Eligibility | Owner of the session's shop only, via unrevoked `shop_memberships` row. **No entitlement check**: pending and expired (read-only) owners may submit and read their own rows |
| Denials | Partner, employee, count-only assignment, anonymous, deleted/banned identity, expired session, revoked membership, and non-admin callers fail at the database (`unauthorized`/`forbidden`) |
| Body | Arabic text 10–1000 characters after Unicode trim; newline is the only accepted control character (CR, Tab and all others rejected); no attachments |
| Category | Optional enum: `subscription` (اتصال بالاشتراك), `technical` (مشكلة تقنية), `financial_question` (سؤال بعد النقد), `other` (أخرى), or null |
| Status flow | Exactly `new → in_progress → answered → closed`; no other transition; closed is terminal |
| Reply | Required, validated 10–1000 like the body, only at `in_progress → answered`; must be null for `answered → closed`; immutable afterwards |
| Rate limit | Creating is rejected at 10 or more non-closed inquiries per shop (`inquiry_limit`); definitive validation failures never consume the idempotency key |
| Idempotency | One key per `(shop_id, idempotency_key)`; identical retry replays the saved row (`result_status: "replayed"`); changed payload fails `payload_mismatch` |
| Audit | `support_inquiry_events` append-only (trigger rejects update/delete): actor, key, before/after status, reply, server UTC |
| Admin gate | `admin_list_support_inquiries_v1`, `admin_update_support_inquiry_status_v1` re-check `private.admin_subscriber_gate()` on every call; lost admin rights return no rows and apply no write |
| Effects | Zero financial, entitlement, dispatch or business-audit effect; no R2 use; no backfill of defaults |

## Backend shape

`public.support_inquiries` (RLS on, no policies, revoked from `anon`/`authenticated`) with a shape CHECK binding reply/timestamps to status, and `public.support_inquiry_events` (append-only). Keyset indexes for owner, shop, and admin ordering plus a partial index for the rate-limit count. Owner RPCs `create_support_inquiry_v1`, `list_my_support_inquiries_v1` (page 1–50 default 20, `open_count`/`open_limit`/`snapshot_at`, `stale_cursor` on a missing cursor row); admin RPCs with exact shop-identifier search only (free text selects nothing). Errors: `invalid_input` (22023), `inquiry_limit` (22023), `payload_mismatch`, `unauthorized`/`unauthenticated`/`session_expired`/`forbidden` (42501), `stale_cursor` (P0001), `invalid_transition` (P0001), `not_found` (P0002). Helpers ungranted; `service_role` revoked where the role exists. No edit of `list_my_shop_accounts` or any existing contract.

## Clients

Flutter: persistent «تواصل مع الدعم» action in the Help screen (visible always, emphasized when search finds no match; no tour or guide card is reintroduced). Owner-only text form with category picker, live Arabic validation, exact remaining-character count, duplicate-submit guard, truthful pending/confirmed/failure/retry/limit/access-loss states, and the owner's inquiry list (newest first, keyset paging, status/reply/shop-local LTR dates, snapshot freshness). React admin: read-only «الدعم الفني» mailbox with status filter, exact shop-identifier search, bounded paging, triage editor with Arabic confirmation of each saved transition and honest loading/empty/retry/refresh/access-expiry states. All Arabic RTL with the shared brown/cream/dark tokens.

## Acceptance

SQL: full owner/expired/staff/anonymous/revoked/session/gate matrix, rate limit, transitions, reply requirement, immutable audit, replay/mismatch, rollback round trip (local runner). Flutter and React tests: validation, states, duplicate taps, paging, stale disposal, mailbox reads/filters/triage/access loss. Arabic RTL visual review in both themes at 320/390/1440 and enlarged text. Hosted role/behavior tests with preservation baselines on development `xchapwvmvoefriqcxtvn`. Owner/device acceptance and frontend publication remain open.

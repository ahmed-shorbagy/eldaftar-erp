# ADR 0037: Owner audit trail browser (AUD-01)

Status: implemented, locally verified, and deployed to the development project `xchapwvmvoefriqcxtvn` on 2026-10-28 (migration `20261028120000` applied and marked applied; hosted rollback gate passed; preservation counts unchanged). [Validation](../reviews/audit-trail-2026-10-28/validation.md). Bounded AUD-01: a read-only Arabic browser over the existing append-only `public.financial_audit_events` feed. Does not add a second history, a financial post, a new R2 media kind ([ADR 0024](0024-cloudflare-r2-media-storage.md)), NTF-01 notices, ADM-06 broadcasts, retention or reset, custom payment methods, D21 shop-data admin access, or onboarding/guide cards ([ADR 0010](0010-owner-feedback-registration-and-ledger.md)). Owner/device acceptance and publication remain open.

## Decision

| Rule | Bound |
| --- | --- |
| Surface | Owner «المزيد ← سجل العمليات». Title «سجل العمليات». The screen states that the page is read-only and changes no balance |
| Eligibility | Session shop owner only. Shop id is derived from the session; the RPC takes no shop argument |
| Expired owner | Same D13 read posture as other owner financial reads: a started entitlement that has expired still allows this read. The owner cannot mutate |
| Pending owner | No entitlement, or `starts_at` still in the future, returns `shop_unavailable`. This matches financial reads and differs from HELP-02, which skips the entitlement check |
| Denials | Partner (even with every grant), employee, count-only assignment, anonymous, missing user, expired session, revoked membership, and cross-shop fail closed at the database. A cursor that names another shop's row is `stale_cursor`, not a leak |
| Source | Existing `financial_audit_events` rows only. No new audit table and no client write |
| Order | Newest first: `created_at desc, id desc`. Keyset cursor is both `p_before_at` and `p_before_id`, or neither. Page size 1–50, default 20. The next cursor is the last returned row |
| Row | Arabic action label, family, actor display name, server UTC, shop-local time from `shops.time_zone` via `private.shop_display_zone`, optional operation id and shop sequence, compact summary |
| Actor name | `auth.users.raw_user_meta_data.display_name` when non-blank. If the actor is the shop owner and that metadata is blank, `shops.owner_display_name`. Otherwise JSON null. The client shows «الاسم غير متاح». The feed never fabricates «مستخدم» |
| Summary | Whitelist only: sequence, business date, «مع عملية بديلة» / «حذف دون بديل», «جرد الإغلاق مسجّل», attachment yes/no, channel `whatsapp` as واتساب, and digit-only piastre texts. Empty whitelist becomes «سجل مالي». Raw `details`, phones, emails, exception text, object keys and count snapshots are not returned |
| Families | Server filter, one family each: `change` (trade edit, ledger correction, exchange, inventory correction), `delete` (`trade_deleted`), `deduction` (expense, inventory removal, sale return, purchase return), `post` (every other known action and any unknown future action, labelled «عملية مسجّلة» with the raw action code shown beside it). Invalid family is `invalid_input` |
| Append-only | The existing `audit_append_only` trigger stays. UPDATE and DELETE remain revoked from `authenticated`. This slice does not grant INSERT |
| SELECT policy | `financial_audit_events_select_opening` (any member who could read opening financials) is replaced by `financial_audit_events_select_owner`, which requires `private.audit_trail_owner_visible`: accepted session, non-anonymous user, `is_shop_owner`, and a started entitlement. This tightens direct table reads. Security-definer counters used by existing reports still run as their owner |
| Effects | Zero financial effect. No balance change, no posting, no R2 write, no admin path into the shop ledger |

## Deferred audit domains

These tables stay append-only and are not merged into this feed: `identity_audit_events`, `shop_member_grant_audits`, `invoice_message_audits`, `invoice_appearance_audits`, `closing_delegation_audit`, `support_inquiry_events`, and `ledger_trade_change_audits`. Trade edit and delete already land in `financial_audit_events` as `trade_edited` and `trade_deleted`, so the trade-change table is not duplicated here.

## Backend shape

Migration `20261028120000_owner_audit_trail.sql`. Index `financial_audit_events_shop_feed_idx` on `(shop_id, created_at desc, id desc)`. Public RPC `list_shop_audit_trail_v1(p_family text, p_before_at timestamptz, p_before_id uuid, p_limit integer)` is `stable`, security definer, `search_path = ''`, granted to `authenticated` only. `service_role` is revoked where that role exists. Helpers `audit_trail_family`, `audit_trail_action_label`, `audit_trail_summary` and `audit_trail_actor_name` are private and ungranted. `audit_trail_owner_visible` is granted to `authenticated` only so the owner SELECT policy can call it. The JSON object is `entries`, `next_cursor_at`, `next_cursor_id`, `time_zone`, `snapshot_at`. An entry has no `details` and no `shop_id`. Errors: `invalid_input` (22023), `unauthenticated` / `session_expired` / `forbidden` / `shop_unavailable` (42501), `stale_cursor` (P0001).

## Client

Flutter Clean Architecture under `app/lib/src/features/audit_trail`: domain model and gateway independent of Flutter and Supabase, a Supabase RPC adapter, and an Arabic RTL screen. States: loading, empty (including an empty family), retry, access loss, and «تحميل المزيد». Family chips call the server filter. Latin digits, ids and timestamps use LTR isolation. Cairo, existing brown/cream/dark tokens, 48-pixel padded chips, and the 720-pixel measure. The more-menu link is owner-only and appears only when the gateway is wired. No edit, delete, or export control.

## Acceptance

Local SQL covers owner list, expired-owner read, partner/employee/anonymous/count-only/revoked/pending/cross-shop denials, stable keyset paging, summary redaction, and append-only. Flutter tests cover decode, empty/error/retry, paging, access loss, and the owner versus staff link. Widget captures cover both themes at 320, 390 and 1440, including 1.7 text scale. Hosted verification and preservation are in the review folder. Owner/device acceptance remains open.

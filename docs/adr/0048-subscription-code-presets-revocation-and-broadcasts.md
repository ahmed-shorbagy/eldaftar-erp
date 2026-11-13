# ADR 0048: Subscription-code presets and revocation, and subscriber broadcasts

Status: accepted 2026-11-13 (owner decisions D-A2 and D-A3 of 2026-11-10); implemented, locally verified and development-deployed 2026-11-13 ([validation and deployment](../reviews/admin-phase4-2026-11-13/validation.md)). Owner acceptance and frontend publication pending.
Date: 2026-11-13
Owners: product owner and engineering reviewer
Related requirement IDs: ADM-02, ADM-06, AUD-01
Supersedes: none. Extends [ADR 0028](0028-admin-subscription-code-issuance.md) and [ADR 0046](0046-platform-admin-audit.md). Reuses the owner-notice rules of [ADR 0029](0029-subscription-expiry-notices.md) and the announcement banner of [ADR 0031](0031-help-content-and-announcements.md).

## Context

The owner's dashboard brief asks for subscription durations of «شهر – 6 شهور – سنة – تحديد المدة يدويًا» (month, six months, year, or manual) and for «إمكانية ارسال رسائل ليهم» (the ability to send subscribers messages). ADR 0028 issues codes for a custom day count only. A code can't be withdrawn once issued, and no admin message reaches a shop other than the single platform announcement. Phase 4 of the [admin completion plan](../operations/admin-completion-plan-2026-11-10.md) covers both. The owner answered D-A2 and D-A3 on 2026-11-10.

Example: an admin issues a 6-month code for a shop and sends it on WhatsApp to the wrong number. Today it stays valid for 30 days. With this ADR the admin revokes it with the reason «أُرسل إلى رقم خطأ», then issues a new one. Later the admin wants every shop whose term ends within 7 days to see a renewal message. Today only the global announcement can do that, and every shop sees it.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Presets as new server plan types | The plan is stored by name | A second duration model beside `duration_days`. The 1–3660 check already covers every preset. |
| B. Presets as client shortcuts for `duration_days` | No schema change. The history shows the real days granted. | The preset name isn't stored. History shows days only. |
| C. Revoke by deleting the code row | Simple | Loses history and audit |
| D. Revoke by marking the row and ending code validity at revocation time | Owner redemption is unchanged (it already rejects an expired code). History keeps the row. | The stored code expiry becomes the revocation time. The original expiry moves to the audit event. |
| E. Broadcasts through the existing announcement | Reuses everything | One message for all shops. No segments, read state or history. |
| F. New broadcast tables with a recipient list frozen on the server | Segments, read state, counts and withdrawal | New tables, RPCs and screens in both clients |

## Decision

Options B, D and F.

### Code presets (D-A2)

The issue form offers شهر = 30 days, 3 أشهر = 90, 6 أشهر = 180, سنة = 360, and «مدة يدوية» (manual). Manual keeps the existing 1–3660 integer field. A preset only fills `p_duration_days`. `public.issue_subscription_code` and its validation, replay and audit are unchanged. Review and history keep showing days. 360 days for a year is the owner's confirmed rule and may be revisited.

### Code revocation

`public.admin_revoke_subscription_code_v1(p_code_id uuid, p_reason text, p_request_key uuid)` is security definer and needs a live platform-admin session, rechecked after the row lock as in ADR 0028. The reason is trimmed text of 3–200 characters on a single line, with no control characters. The request key is a UUID v4.

Under a lock on the code row:
- The same request key on the same code with the same reason returns `replayed`. The same key on another code or with another reason raises `request_key_reused`.
- An already revoked code returns `already_revoked`. A redeemed code returns `redeemed`. A code whose validity has passed returns `expired`. Nothing is written in these three cases.
- Otherwise it sets `revoked_at`, `revoked_by`, `revoke_reason`, `revoke_request_key` and `code_expires_at = clock_timestamp()`. It then appends `subscription_code_revoked` to `private.subscription_code_events` with the original expiry and the reason, and returns `revoked`.

Revocation never touches `shop_entitlements`, so a redeemed term is never shortened. A redemption racing a revocation serializes on the same row lock: whichever commits first wins. A revoked code then fails redemption as `expired_code`, so the Flutter dialog needs no new status. Unknown or wrong-shop ids raise `not_found`.

History moves to `public.admin_list_subscription_codes_v2`. It has the same shape, paging and gate as v1, plus `revoked_at` and `revoke_reason` per row, and a `revoked` status that ranks after `redeemed` and before `expired`. v1 is left as it was for older clients, which see a revoked code as `expired`.

The React detail page adds «إلغاء الرمز» (revoke code) on unused rows. A confirmation names the shop, issue time and duration, requires the reason, and states that revocation doesn't change the current subscription. The request key is frozen per confirmation. A timeout retries with the same key.

### Copy and share

The one-time secret dialog keeps «نسخ الرمز» (copy code). Where the browser supports the Web Share API, it adds «مشاركة» (share). Share sends an Arabic text with the code and the day count, after the same session check as copy. It is never offered once the secret is cleared. Bulk send waits for external channels, as D-A3 says.

### Broadcasts (D-A3, ADM-06)

**Data.** `public.platform_broadcasts` holds one message: id, request key (unique), creator, server creation time, segment, segment days, segment shop, Arabic title (1–80 characters), body (1–1000, newlines allowed), optional https link (12–2048), `starts_at`, `ends_at`, frozen `recipient_count`, and withdrawal time, actor and reason. `public.platform_broadcast_recipients` holds (broadcast, shop, `delivered_at`, `read_at`). RLS is enabled and no client role has table privileges. Every read and write goes through security-definer RPCs.

**Segments.** `all` covers every shop with an unrevoked owner. `active`, `pending` and `expired` use the directory rule of ADR 0027. `expiring` covers active shops whose term ends within N days, N from 1 to 90. `shop` covers one exact shop. The recipient list is frozen when the admin confirms, including for a scheduled send. Shops that register later, or change status before a scheduled `starts_at`, are not added or removed. An empty audience raises `empty_audience`.

**Timing.** `starts_at` defaults to the server time at confirmation. A scheduled time may be up to 90 days ahead. `ends_at` defaults to `starts_at + 30 days` and must be after `starts_at` and at most 365 days after it. All times are server UTC. The admin dashboard shows them in the viewer's time zone. No scheduler is needed: visibility is computed at read time.

**Admin RPCs** (platform-admin gate, live session rechecked after locks):
- `admin_preview_broadcast_audience_v1(segment, days, shop_id)` returns the current recipient count and snapshot time.
- `admin_send_broadcast_v1(request_key, segment, days, shop_id, title, body, link, starts_at, ends_at, expected_count)` freezes the list in one transaction. If the count differs from `expected_count` (the number the admin confirmed), it raises `audience_changed`, so the admin reviews again. A replay with the same key and payload returns `replayed`. A different payload raises `request_key_reused`.
- `admin_withdraw_broadcast_v1(broadcast_id, reason)` sets the withdrawal fields once (reason 3–200). A second call returns `already_withdrawn`. A message can't be edited.
- `admin_list_broadcasts_v1(cursor, page_size)` pages newest first. Each row has the content, segment, times, state (`scheduled`, `active`, `ended`, `withdrawn`), and recipient, delivered and read counts as exact strings.

**Owner RPCs.** Only the current unrevoked owner of the recipient shop, in a live session, may read. Partners, employees, count-only assignees and other shops fail closed. Expired and pending owners still receive messages.
- `list_my_broadcasts_v1()` returns up to 50 visible messages, newest first, the unread count and the shop time zone used to show times. A message is visible when started, not ended and not withdrawn. The call stamps `delivered_at` once per recipient row.
- `mark_broadcast_read_v1(broadcast_id)` stamps `read_at` once and is idempotent.

**Owner experience.** «الرسائل» (Messages) appears in «المزيد» (More) with the unread count. The inbox lists messages and opens one in full, which marks it read. The newest unread message shows as a banner on the workspace, reusing the announcement banner. «إخفاء» (hide) on the banner marks that message read.

**Audit.** `public.platform_admin_audit_events` gains the `broadcast` family with `broadcast_sent` (segment, recipient count, starts and ends, title up to 120 characters) and `broadcast_withdrawn` (title and reason). Code revocation appears in the `codes` family as `subscription_code_revoked` (duration, reason). «سجل الإدارة» lists all of these. Bodies, links and recipient shop lists never appear in the audit summaries.

Out of scope: WhatsApp, email and push channels; images and files; per-person read tracking; editing a sent message; bulk code sending; partner and employee recipients.

## Data and compatibility impact

There are two additive migrations. The code migration adds four nullable columns, a pair check and a unique revoke key to `private.subscription_codes`. It adds the revoke RPC and history v2, and replaces the audit read so it includes revocations. `issue_subscription_code`, `redeem_subscription_code` and history v1 keep their signatures and bodies. The broadcast migration adds two tables, the RPCs above, and widens the audit family and action checks. It replaces the audit read again.

Older Flutter clients ignore the new RPCs. The React audit parser is strict, so the dashboard must be deployed with the backend: an older dashboard would reject the new audit actions.

Rollback drops the new functions, tables and columns. Before that, export `platform_broadcasts`, its recipients and the revocation events if their history is to be kept. Privacy: the recipient tables hold shop ids only, and no contact data is read or stored.

## Verification

SQL in a rolled-back transaction on development covers:
- grants;
- anonymous, owner, partner, revoked-admin and banned-admin denial;
- revoke states, replay and key reuse;
- redemption after revocation;
- the redeemed term left unchanged;
- each segment's membership and its freezing;
- `audience_changed`, `empty_audience` and send replay;
- schedule and end visibility;
- withdrawal;
- owner-only inbox reads;
- delivered and read stamping;
- audit rows and their absence of bodies.

React tests cover presets, revoke dialog states, share availability, the composer review, counts, withdrawal and audit labels. Flutter tests cover the gateway parser, the inbox and read marking, the unread count, and the banner in Arabic RTL, light and dark. Visual review uses 375 and 1240 pixels for the dashboard, and 320, 390 and 1440 for the app. Owner acceptance remains open.

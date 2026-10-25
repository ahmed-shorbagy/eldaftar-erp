# ADR 0029: Server-timed in-app subscription expiry notices

Status: implemented, locally verified and development-deployed for the bounded ADM-03 slice on 2026-10-25. [Validation](../reviews/subscription-notices-2026-10-25/validation.md), [deployment/preservation](../reviews/subscription-notices-2026-10-25/deployment.md). Outbound dispatch, contact/location, retention/deletion and financial access remain separate. Frontend publication and owner acceptance remain pending.

Related requirement IDs: ADM-03
Supersedes: none. Reuses D13 expired-owner read/export access and the entitlement clock in `list_my_shop_accounts`. Builds on the hashed redemption contract in [ADR 0028](0028-admin-subscription-code-issuance.md).

## Context

PAGES requires a three-day renewal reminder and a notice at expiry. Shop owners already see pending, active and expired status from `list_my_shop_accounts`, and an expired shop already shows a permanent Arabic read-only banner with renewal. That access state is not a dismissible acknowledgement. The product owner confirmed two in-app notices: one while the term is still active and within 72 hours of expiry, and one after the server marks the shop expired. Each notice can be dismissed once for the current entitlement expiry. Dismissing the reminder does not hide the later expiry notice. Device clocks, push, email, WhatsApp, OS notifications, admin broadcasts, forced updates and retention warnings are outside this slice.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Client derives the 72-hour window from `subscription_expires_at` | No new RPC | Device clock can show or hide the notice early or late; dismissals are not durable across devices |
| B. Server derives the current undismissed notice and stores dismissals keyed to the entitlement expiry | One clock, durable dismissals, renewal starts a new pair when `expires_at` changes | Requires a narrow table and two RPCs |
| C. Admin-authored notice rows with scheduling jobs | Supports later ADM-05/ADM-06 content | Larger surface, not needed for fixed subscription thresholds |

## Decision

Option B.

The database clock decides both notices. Active still means `starts_at <= now() < expires_at`. `renewal_due` is that active window intersected with `expires_at - interval '72 hours' <= now()`. `expired` is `now() >= expires_at`. A pending shop has neither notice. The two windows do not overlap, so the owner sees at most one notice.

Dismissals live in `public.subscription_notice_dismissals`: shop, owner user, kind (`renewal_due` or `expired`), `entitlement_expires_at`, and server `dismissed_at`. The unique key of those four identity columns is the retry identity. A second identical dismiss succeeds without a second row. There is no ordinary update or delete path. Redemption already writes a new `expires_at`, so the next term starts a new pair.

`public.list_my_subscription_notices_v1()` returns only the current undismissed notice for each shop the caller owns: shop id, kind and that entitlement expiry. No contact, location, code or financial columns. `public.dismiss_subscription_notice_v1(shop_id, kind, expires_at)` checks the live owner session used by the account list, then requires the arguments to match the server's current notice. An expired owner may dismiss. The RPC does not use the financial-write entitlement gate and does not change entitlements or ledger state. A stale kind or expiry is rejected.

The Flutter workspace shows one Arabic banner for the selected shop. The renewal reminder states that writing remains available until the server expiry and offers the existing activation dialog. The expiry notice is a short dismissible acknowledgement. The permanent read-only banner and «تفعيل الاشتراك» control remain after that notice is dismissed. Dismiss uses «إخفاء التنبيه», stays disabled while the request is in flight, and stays visible with a retry message if the server does not confirm it. The staff count portal receives no notice. D13 remains unchanged: expiry still blocks shop writes and still allows read and export.

## Data and compatibility impact

Migration `20261025093000_subscription_expiry_notices.sql` adds the dismissal table and the two RPCs. `list_my_shop_accounts` is unchanged. Old clients ignore the new RPCs. No table grants to `anon` or `authenticated`. No backfill. Rollback drops the two functions and the table.

## Verification

SQL covers 73 hours before expiry (no notice), the instant 72 hours before (`renewal_due`), the expiry instant (`expired`), dismissing the reminder then seeing the expiry notice, dismissing expiry without changing the entitlement or write block, a new `expires_at` showing notices again, a second dismiss as a no-op, foreign shop / anonymous / stale expiry rejection, and an expired owner dismiss. Flutter covers server-driven banner display, failed dismiss remaining visible, and the expired read-only screen still showing access state and renewal after a successful dismiss. Arabic RTL light/dark review at phone and desktop widths is required. Development deployment and preservation remain separate from owner acceptance.

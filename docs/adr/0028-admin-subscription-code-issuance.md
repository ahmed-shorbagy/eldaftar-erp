# ADR 0028: Admin subscription-code issuance and history

Status: implemented, independently reviewed, locally verified and development-deployed for the bounded ADM-02/ADM-08 slice on 2026-10-22. Frontend publication and owner acceptance remain pending.

Related requirement IDs: ADM-02, ADM-08
Supersedes: none. Reuses the hashed issuance/redemption contract in [ADR 0011](0011-required-location-subscription-sync.md) and the directory gate in [ADR 0027](0027-admin-subscriber-directory.md).

## Context

Platform administrators could list registered shops and their subscription terms, but they could not issue a hashed activation code from the React dashboard. Operators still needed an out-of-band SQL call. Shop owners already redeem through `public.redeem_subscription_code`. Issuance must not activate or extend a term. Only owner redemption does that. Raw codes must never be stored, logged, or recovered after the first response.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Parallel admin activation RPC that writes entitlements | Immediate shop access after an admin click | Two activation systems, race with owner redemption, contradicts the existing hashed-code contract |
| B. Reuse `public.issue_subscription_code` and `public.redeem_subscription_code`, add a narrow history metadata RPC | One issuance path, existing owner redemption, hashed single-use codes | Admin UI must treat the returned secret as session-only and explain replay |
| C. Grant administrators `SELECT` on `private.subscription_codes` | Simple history query | Exposes hashes, owner ids, request keys and would weaken the private-schema boundary |

## Decision

Option B.

Issuance is the existing `public.issue_subscription_code(shop_id, duration_days, code_ttl_days, request_key)` function. Duration is an integer of 1–3660 days. Code validity is an integer of 1–365 days, default 30. There is no month/year plan conversion. Platform-admin and `service_role` issuance remain. After contended locks the function rechecks the current admin or service-role identity, including session, deleted/anonymous identity and a current ban, and rechecks the unrevoked owner binding. A replay of the same UUID v4 request key with the same shop, duration and TTL returns `status = replayed` and `code = null`. A mismatched replay raises `request_key_reused`. Issuance does not insert or update `shop_entitlements`.

Owner redemption remains `public.redeem_subscription_code`. It keeps owner/shop binding, single use, atomic renewal from the server clock taken after locks, committed invalid attempts, replay before the throttle, and D13 expired-owner renewal. A currently banned, deleted or anonymous identity, or an expired session, is rejected. Authorization is rechecked after contended locks. Signatures stay compatible.

History is a new security-definer RPC `public.admin_list_subscription_codes_v1(shop_id, cursor, page_size)` for one selected shop. It uses `private.admin_subscriber_gate()` in the same statement as the rows. The allowlist is shop id/name, snapshot time, exact `row_count`, page size, and per-row id, issued time, duration, TTL, code expiry, `issued_via`, server-derived `unused` / `expired` / `redeemed` status, and `redeemed_at`. An expiry equal to `now()` is expired. Redeemed wins over expiry. Raw codes, hashes, request keys, owner identity, issuer user id, contact, location and financial columns are not selected. Page size is 1–25. The client asks for 20. Order is `issued_at` descending, then `id` descending. The cursor is the same 66-character `v1|UTC timestamp|uuid` form as the directory.

The React detail surface issues from the selected shop. Review names the shop, duration and code validity, states that issuance does not activate or extend, and labels any projected expiry as an estimate. The 32-character secret is shown once, with an explicit copy action, only in session memory. It is cleared on dismissal, navigation, access loss or unmount. Timeout freezes the request envelope. Retry reuses the UUID v4 key. Replay never issues another code automatically. A replaced session discards a late secret. A same-user token refresh does not retry the write.

Out of scope: revocation, entitlement editing, bulk issuance, automatic dispatch, real customer issuance, ADM-07 contact/location, notices, Help, forced updates, impersonation and retention.

## Data and compatibility impact

Migration [20261022140217_admin_subscription_code_issuance.sql](../../supabase/migrations/20261022140217_admin_subscription_code_issuance.sql) replaces the issue and redeem function bodies in place, adds `private.subscription_owner_session()`, a shop/issued/id index, and the history RPC. No table grants. `service_role` keeps issue execute and is revoked from history. Old clients ignore the new history RPC. Existing Flutter redemption keeps the same arguments and typed statuses.

## Verification

Local disposable PostgreSQL applies every migration, rolls the new file back, reapplies it, then runs `subscription_redemption.sql`, `admin_subscription_codes.sql`, the hosted-shape fixture, and a two-connection redemption race. React tests cover one-time display, copy, storage/log exclusion, dismissal, late replies, duplicate submits, timeout retry, replay, parsers, range errors and history paging. Independent review, hosted deployment, frontend publication and owner acceptance remain separate.

Independent final evidence: [validation](../reviews/admin-subscription-codes-2026-10-22/independent-validation.md), [deployment and preservation](../reviews/admin-subscription-codes-2026-10-22/deployment.md). Historical implementer records retain their original claims and pre-deployment filename.

# Subscription code issuance and redemption

This is the operator workflow for hashed shop activation codes. Writing this file does not issue a code, apply a remote migration, or change a hosted project.

## Trust boundary

- Shop owners never read `private.subscription_codes`, attempt rows, or raw hashes.
- Flutter and React clients never embed a service-role key.
- Issuance is limited to a current platform-admin session (`public.is_platform_admin()` plus an accepted, non-anonymous, non-deleted Auth session) or a `service_role` operator session.
- `issued_via` records `platform_admin` or `service_role`. Service-role rows keep `issued_by` null so the shop owner is not attributed as the issuer.

## Issue a code

The React administration detail for a selected shop is the bounded operator path after ADM-02. SQL remains available for `service_role` operators. Writing this file does not issue a code.

Development `xchapwvmvoefriqcxtvn` has the reviewed `20261022140217_admin_subscription_code_issuance.sql` applied. [Deployment/preservation](../reviews/admin-subscription-codes-2026-10-22/deployment.md). The React frontend remains unpublished and owner acceptance is pending.

For a project with `20261011120249_required_location_subscription_sync.sql` and the issuance migration applied:

1. Confirm the shop id and the unrevoked owner membership from the subscriber directory. Do not open shop financial, contact or owner-identity records.
2. Choose a duration in integer days (1–3660) and a code TTL in integer days (1–365, default 30). Do not convert from a month or year plan.
3. Review the shop name, duration and TTL. Issuance does not activate or extend the shop. Only owner redemption does.
4. The dashboard generates a UUID v4 request key. Keep that key with the operator notes if using SQL. The database never stores the raw code.
5. Call `public.issue_subscription_code(shop_id, duration_days, code_ttl_days, request_key)` as a current platform-admin session or as service role.
6. The 32-character hexadecimal code is shown once. Copy it explicitly and deliver it out of band. Do not write it to browser storage, logs, analytics, URLs or audits. Closing the dialog, leaving the shop, or losing the session clears it.
7. Retrying the same request key with the same shop, duration, and TTL returns `status = replayed` and `code = null`. That confirms the earlier issuance; it does not reveal the code again and must not automatically issue another code. If the code was lost, a new issuance requires a separate deliberate operator decision and fresh review; never generate a new key automatically. The unused previous code remains redeemable until its TTL.
8. History for that shop is `public.admin_list_subscription_codes_v1`. It returns unused/expired/redeemed metadata only.

A currently banned, deleted, anonymous or revoked administrator cannot issue or read history. `service_role` issuance still records `issued_via = service_role` with a null `issued_by`.

## Owner redemption

The signed-in owner calls `public.redeem_subscription_code(request_key, code)` from the Flutter activation dialog. The RPC:

- binds the code to that owner and shop
- is single-use
- extends an active entitlement or starts a new term from the server clock taken after locks
- replays an identical request key before applying the invalid-attempt throttle
- records invalid attempts in a committed transaction by returning a typed `status` instead of raising, then maps that status on the client

Pending owners may read `public.shop_sync_signals` revision rows only. They cannot read financial tables until an entitlement exists.

## Rollout

Local disposable PostgreSQL replay and RLS suites verify the contract. The owner subsequently authorized the migration and owner-register deployment to the existing development project; see the [deployment record](../reviews/owner-feedback-batch1-2026-10-11/deployment.md). Auth configuration changes and production issuance were not part of that run.

An exact server expiry is available after issuance/replay; the review expiry is explicitly estimated. History uses server status at its snapshot, with 20 rows requested and a hard server maximum of 25. Refresh to obtain a new status snapshot. A timeout keeps the original request envelope only in the current session. If dismissed or the session is lost, use history to confirm issuance; the raw code cannot be recovered. There is no revocation in this slice.

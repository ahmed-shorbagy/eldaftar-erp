# Subscription code issuance and redemption

This is the operator workflow for hashed shop activation codes. Writing this file does not issue a code, apply a remote migration, or change a hosted project.

## Trust boundary

- Shop owners never read `private.subscription_codes`, attempt rows, or raw hashes.
- Flutter and React clients never embed a service-role key.
- Issuance is limited to a current platform-admin session (`public.is_platform_admin()` plus an accepted, non-anonymous, non-deleted Auth session) or a `service_role` operator session.
- `issued_via` records `platform_admin` or `service_role`. Service-role rows keep `issued_by` null so the shop owner is not attributed as the issuer.

## Issue a code

After the migration `20261011120249_required_location_subscription_sync.sql` is applied to a project by an authorized operator:

1. Confirm the shop id and the unrevoked owner membership.
2. Choose a duration in days (1–3660) and a code TTL in days (1–365, default 30).
3. Generate the required UUID v4 request key and keep it with the operator notes. The database never stores the raw code.
4. Call `public.issue_subscription_code(shop_id, duration_days, code_ttl_days, request_key)` as platform admin or service role.
5. Deliver the returned 32-character hexadecimal code out of band. Treat it as a secret.
6. Retrying the same request key with the same shop, duration, and TTL returns `status = replayed` and `code = null`. That confirms the earlier issuance; it does not reveal the code again. If the code was lost, issue a new request key. The unused previous code remains redeemable until its TTL.

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

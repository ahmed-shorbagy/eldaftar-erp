# Milestone 1 identity validation

## Current state

The Flutter shop client and React platform dashboard gate their prototype shells behind Supabase Auth. Only a verified email session may pass the client gate. React additionally calls the separate `is_platform_admin` RPC. The database migrations add shops, memberships, grants, invitations, audit records, one entitlement per shop, and server-side authorization helpers. Financial posting, subscription-code redemption, invoice dispatch, and real ERP modules are outside this identity draft. The prototype banner remains visible after sign-in.

On 2026-09-24, the seven ordered migrations were applied through the Supabase plugin to project `xchapwvmvoefriqcxtvn`, which the owner identified as the development database. The remote migration versions match the filenames in `supabase/migrations/`. Both `identity_rls.sql` and `identity_commands.sql` passed against PostgreSQL 17.6 in that project; each test ended with `ROLLBACK`, and follow-up counts found zero synthetic shops and users. No local `psql`, Supabase CLI, Docker, or Podman runtime was available, so clean local replay and CI remain unverified. There is no separate staging or production project yet; this development database must not be treated as a production acceptance gate.

## Owner-controlled environments

Create separate development, staging, and production Supabase projects under the product owner's organization. Store each project's URL and public publishable key in the clients' ignored local configuration. Keep service-role credentials and database passwords server-side and outside Git. Platform administrators are provisioned by an authorized operator in `platform_admins`; ordinary authenticated users have no table-write grant. Shop entitlement provisioning likewise remains an operator step until the approved subscription redemption flow is implemented. A newly created shop has no entitlement and is pending activation.

Create separate R2 buckets and scoped keys for each environment before the upload milestone. Record who owns backups, key rotation, incident response, and restore approval under D20. Arrange the macOS/iOS signing host and owner store accounts before release work. No production project, store account, or signing key is created by this repository change.

## Local migration and policy gate

On a disposable local Supabase instance:

1. Apply the ordered files in `supabase/migrations/`.
2. Set `SUPABASE_TEST_DATABASE_URL` to its local PostgreSQL URL. The runner refuses a non-local host.
3. Run `npm run test:rls` from `supabase/`. It uses `psql` and rolls its synthetic fixtures back.
4. Recreate the instance and reapply the migrations to check repeatable clean setup. Then test migration from the previous schema snapshot before staging.
5. Sign in as distinct verified owner, partner, employee, revoked user, and platform admin against staging. Check anonymous, cross-shop, expired read/write, invitation-email, and grant-escalation cases. Do not rely on hidden UI controls as evidence.

The two SQL scripts passed on the temporary development project and roll back their fixtures. Run them again on a clean local database and later on staging before release. Record exact command output and migration hashes in staging evidence.

## Advisor review

The security advisor reports three intentionally unreadable tables with RLS and no policies: invitations, identity audit, and platform admins. It also flags seven authenticated `SECURITY DEFINER` RPCs that form the explicit command/query API; each uses a fixed search path and server-side actor checks. Review these functions again before production. The performance advisor's RLS auth-call warning was resolved by migration `20260924130348_policy_auth_cache.sql`. Its remaining informational findings are a composite-unique membership table without a separate primary key and unused indexes on the empty schema.
## Client gates run on this workstation

- Flutter: `dart format lib test`, `flutter analyze`, `flutter test`, `flutter build windows`, `flutter build apk`.
- React: `npm run lint`, `npm test`, `npm run build`.
- iOS signing and build require macOS and are not covered here.

## Unfinished acceptance evidence

D10 employee read scope remains default deny beyond the explicit grants. D12 still needs an approved all-screens Arabic RTL prototype or an explicit product-owner deferral; a sign-in shell is not that prototype. Interactive onboarding, Help resume, shop setup UI, staff administration UI, visual baselines, and live backend failure/session-expiry demonstrations remain to be built and reviewed. D14/D15/D20 govern retention, reset, and owner infrastructure before production subscriptions. The financial worked examples remain unsigned, so no financial posting schema or commands are present.

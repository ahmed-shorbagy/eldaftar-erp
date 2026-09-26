# ADR 0003: owner-only shop access

- Status: accepted
- Date: 2026-09-26
- Decision owner: product owner
- Supersedes: the staff, partner, invitation, and per-user grant parts of ADR 0001 and ADR 0002

## Context

The product owner removed staff invitations and permissions from scope. ElDafttar is a single-user shop product: one Supabase Auth user owns and operates one shop. No partner or employee account can join a shop, and no per-user permission matrix is needed. Platform administrators remain a separate operational identity and do not inherit access to shop data.

The existing development schema contains dormant invitation and grant tables and RPCs from the earlier multi-user design. Registration already creates exactly one owner identity and one shop, and development contains no users, shops, invitations, grants, or customer data.

## Decision

Each shop has exactly one owner Auth account, and each owner Auth account belongs to exactly one shop. `shop_memberships` remains as the owner-to-shop association for RLS and account suspension, but its compatibility `role` column is constrained to `owner`. `revoked_at` remains available to suspend the owner account and close shop access.

The staff invitation and grant tables, their RPCs, and the staff authorization helpers are removed. Future financial commands authorize the signed-in, non-revoked owner through the shop boundary and active entitlement; they do not check operation-specific user grants. Expiry still follows D13: the owner can read and export retained shop data, while writes require an active entitlement.

The React platform-admin role remains independent. A platform administrator cannot read ordinary shop data merely because they are an administrator. User metadata is not an authorization source.

## Consequences

- There are no staff, partner, invitation, permission-grant, or employee-reporting screens.
- One owner cannot attach the same Auth account to a second shop, and a shop cannot have a second owner account.
- Audit records still store the acting owner and server timestamp. Actor fields are retained even though there is one shop user.
- Subscription redemption attaches to one shop and its sole owner account.
- Password recovery remains a separate future design because email and phone ownership are unverified.
- Multi-user shop access would require a new product decision, ADR, migration, identity-binding design, and authorization test suite.

## Migration and compatibility

The forward development migration fails closed if any non-owner membership, duplicate shop owner, or owner attached to multiple shops exists. It then removes invitation/grant objects, constrains ownership cardinality, and narrows the membership read policy to the current owner. The existing `list_my_shop_accounts` response retains `member_role = owner` for client compatibility.

Old clients cannot call the removed staff RPCs. Those RPCs were already unavailable to the current clients, and no staff UI was shipped. The development database had zero customer identities and shop rows before this decision.

## Acceptance

- The database rejects `partner` and `employee` memberships.
- The database rejects a second owner for one shop and one owner attached to a second shop.
- Invitation/grant tables, RPCs, and authorization helpers do not exist.
- Anonymous, cross-shop, revoked-owner, expired-write, and platform-admin shop access remain denied.
- Pending, active, and expired owner states remain visible through `list_my_shop_accounts`.
- Flutter accepts only `member_role = owner` from the backend.

The migration is applied to development, the rollback-only SQL suites pass, and the Flutter adapter enforces the owner role. Exact evidence and remaining release limitations are recorded in [the Milestone 1 validation record](../operations/milestone-1-validation.md).

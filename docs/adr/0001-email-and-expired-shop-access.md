# Verified email sign-in and access after subscription expiry

Status: accepted
Date: 2026-09-24
Owners: product owner
Related requirement IDs: D25, D13, D28. D10 remains undecided. D14 retention and deletion remain separately undecided.
Supersedes: none

## Context

ElDafttar ERP authenticates every shop user with Supabase Auth and authorizes shop data in the backend with row-level security and role grants. Hiding a control in the Flutter or React client is not authorization. D28, already accepted on 2026-09-24, attaches one subscription entitlement to one shop. Invited staff share that shop's term. Each person still receives only their own membership grants. A person in more than one shop must pass the entitlement check for each shop separately.

Two identity and entitlement questions were still open. D25 asked whether owner and staff sign-in, and invitation acceptance, use phone, email, or both. D13 asked what login, read, export, and financial writes do after the shop subscription expires, which is a different question from how long data is retained or when it is deleted (D14).

D10, which roles may see full day totals, other employees' operations, customer phone numbers, and reports, is not decided here. Source text says employees see their own operations, while some ledger drawings show shop-wide totals. Until the product owner decides D10, visibility defaults to deny.

Shop example. A gold shop redeems one code. The owner signs in with a verified email and invites a salesperson and a partner, each to their own verified email. While the subscription is active, the salesperson can post only the operations their grants allow, and cannot read another employee's operations or shop-wide totals unless a later D10 decision explicitly grants that. When the subscription expires, none of the three can post a sale, purchase, expense, stock change, close-day, or other shop write. Each existing authorized member can still read and export the shop data their grants already allow, until the separate retention and deletion lifecycle removes or restricts that data. Renewing or replacing the entitlement is what restores writes. Inviting a fourth person does not create a second entitlement for the same shop.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| D25 A. Verified email for Supabase Auth sign-in and for accepting an invitation | One verified identifier for owner and staff, recovery, and admin subscriber identity. Invitation acceptance is tied to a confirmed mailbox. Matches Supabase email verification. | Phone-only shops need an email before they can join. Phone remains a shop or customer contact field, not the auth identifier. |
| D25 B. Phone as the primary sign-in identifier, email optional | Matches a shop phone shown in settings mockups. | SMS verification, recovery, and invitation binding are a different auth design and were not chosen. |
| D25 C. Accept either phone or email without requiring verification | Lowest friction at first login. | An unverified identifier can bind the wrong person to a shop membership and to subscription administration. |
| D13 A. After expiry, block shop writes; allow reads and exports for existing authorized members until the retention/deletion lifecycle | Staff can still reconcile, export, and renew without posting new cash, grams, or ledger rows. Entitlement stays distinct from D14 deletion. | Clients must show a clear read-only state. Exports of financial history need the same grant checks as reads. |
| D13 B. Block all shop access at expiry | Smaller data-exposure window. | Conflicts with the need to read and export retained books while renewal is still possible. |
| D13 C. Allow writes during a grace period | Fewer interrupted sales. | Extends financial mutation past the paid term without an accepted grace rule. |
| D28 unchanged. One entitlement per shop, shared by invited staff, individual grants | Staff do not each consume a code. Permissions stay per person. | A second shop still needs its own entitlement. Grant bugs must not be papered over by a shared login. |

## Decision

Accepted by the product owner on 2026-09-24.

**D25.** Owner and staff sign in with Supabase Auth using a verified email address. An invitation is accepted only by that verified email. Unverified email, phone number, and display name are not sign-in identifiers and do not accept an invitation. Phone numbers may still exist on shop and customer records; they do not authenticate a member or prove invitation acceptance.

**D13.** When a shop subscription is expired, the backend rejects shop writes for every member, including the owner. Shop writes include any mutation of cash, gold grams, piece counts, stock, scrap, customer balances, ledger or business-day state, invoices, and other tenant business records. Existing authorized members may still read shop data and export it, limited to the grants they already hold, until the separately decided retention and deletion lifecycle (D14) ends that access. This record does not set the four-month clock, the 30-day warning, legal hold, audit retention, or backup deletion. Login to an existing membership remains available so those members can read, export, and renew. A lapsed entitlement does not delete data and does not by itself revoke individual grants. New financial posts stay forbidden until a current entitlement covers the shop again.

**D28, reaffirmed.** These choices do not change D28. One entitlement covers one shop and is shared by that shop's invited staff. Each member keeps individual grants. Staff membership never creates an extra entitlement. Multiple shops require separate entitlements. Expiry blocks writes for the whole shop; it does not collapse staff into the owner's permissions, and an active entitlement does not widen a member's grants.

**D10, not decided.** Employee visibility of full day totals, other employees' operations, CRM phone numbers, and reports stays undecided. Implement and test default deny. Do not infer a shop-wide employee view from mockups or from the shared shop entitlement.

UI must show success, pending, or failure for every mutation and must not present a blocked post-expiry write as saved. Authorization is enforced in row-level security and server functions, not only by hiding buttons. Arabic copy for the read-only and invitation states is required when those screens are built. No cash amount, gram weight, or piece count is redefined by this decision.

## Data and compatibility impact

- Identity: Supabase Auth email, with verification required before owner or staff sign-in and before an invitation is accepted. Membership rows bind to `auth.users` only after that verification. Store the invited email and the acceptance outcome; do not treat JWT user metadata as the grant source.
- Invitations that are pending, expired, revoked, or addressed to a different email fail closed and do not create a membership.
- Entitlements stay shop-scoped under D28. Membership and role grants stay person-scoped. Expiry is an entitlement state, not a grant edit and not a deletion.
- After expiry, policies and write RPCs deny inserts, updates, and deletes of shop business data for every role. Select and export paths remain allowed for current authorized members, still filtered by their grants and by default-deny D10 behavior. Anonymous, cross-shop, and revoked members stay denied for both read and write.
- There is no production schema to migrate and no old client to keep compatible (D01). Clients that call a write after expiry must surface the server rejection and leave the ledger unchanged.
- Rollback of this policy is a product change: switching the sign-in identifier or re-opening writes after expiry needs a superseding ADR. It is not a data backfill.
- Privacy: verified email is an account identifier and must not be committed in fixtures as a real person's address. Exports after expiry still contain shop financial data and follow the same membership scope as reads. Retention deletion remains a separate decision.

## Verification

- Owner and staff cannot complete sign-in or accept an invitation until the email is verified. A second person cannot accept an invitation sent to a different email.
- Two staff members on one shop share one entitlement record. Each call is allowed only when that member's own grants allow it. A second shop for the same person requires a second entitlement.
- With an expired subscription, an owner sale, purchase, expense, inventory edit, close-day, and invoice mutation are rejected and create no cash, gram, or count movement. The same member can read and export rows they are already allowed to see.
- A revoked member, a member of another shop, and an anonymous session cannot read or export the expired shop.
- Employee queries for another employee's operations, shop-wide day totals, CRM phone numbers, and reports return nothing until D10 is accepted. A test that only hides the widget in the client fails this decision.
- RLS tests cover anonymous, revoked, cross-shop, expired-subscription read, expired-subscription write, and per-grant staff cases, including a crafted `shop_id`.
- Acceptance owner: product owner for D25, D13, and the D28 reaffirmation. Engineering records the tests. D10 and D14 are not accepted by this ADR.

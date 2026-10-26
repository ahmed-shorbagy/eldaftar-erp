# ADR 0033: Shop staff grants and shop profile

Status: implemented, locally verified and development-deployed for the bounded staff/profile slice on 2026-10-26. [Validation](../reviews/shop-staff-2026-10-26/validation.md), [deployment/preservation](../reviews/shop-staff-2026-10-26/deployment.md). Frontend publication and owner acceptance remain pending.

Related requirement IDs: ID-02, SET-01 (profile edit portion), DOC-02 (pending-send with dispatch grant)
Supersedes: the no-staff / no-partner / no-grant parts of [ADR 0003](0003-owner-only-shop-access.md) and D10. Does not supersede [ADR 0023](0023-owner-meeting-calendar-pdf-and-closing-counts.md) for temporary physical-count assignments or owner-only financial-close confirmation.

## Context

PAGES requires employees and partners with independent grants for sale, purchase, inventory, expenses, reports, and invoice send. ADR 0003 removed those roles by mistake relative to the product page inventory. The owner confirmed restoration on 2026-10-26: financial-close confirmation stays with the owner; temporary count-only assignments remain; shop profile edits for name, phone, and owner name are in scope. Analytics, support contact, audit browser, shop-status notices, invoice message editor, onboarding, payment-method rename, reset, and retention stay out.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Restore invitation email flow only | Matches the 2026-09 staff commands | Phone/password Auth is the current login path; invitations conflict with ADR 0002/0010 |
| B. Owner creates staff Auth users with phone/password and grants (chosen) | Matches closing-staff creation pattern; one shop per Auth user | Requires Edge Function with service role; careful phone uniqueness |
| C. Shared owner credentials | No Auth changes | Breaks audit actor identity and revocation |

## Decision

- One owner per shop. One Auth user belongs to one shop. Roles: `owner`, `partner`, `employee`.
- Grants on `shop_member_grants`: `sale`, `purchase`, `inventory`, `expense`, `reports`, `invoice_send`. Owner has every grant implicitly. Full partner receives all six; limited partner or employee receives only selected grants.
- Owner-only (not grantable): staff management, shop profile edits, subscription redemption, financial-close confirmation, and review of temporary count tasks.
- Employee ledger shows only that employee’s submitted operations and rejects shop cash/gold balance reads used by the ledger home. Partner sees the shop ledger. Reports grant returns shop totals; employee report detail omits other actors’ operation rows.
- Customers, debts, repairs, traders, and daily notes remain owner-only in this slice. Sale and purchase may still record optional customer name and phone on the operation.
- Without `invoice_send`, confirmed invoices stay on the pending-send queue until the owner or a member with that grant confirms.
- Temporary count staff stay on `closing_staff_accounts` and never gain membership grants. Hiding UI is insufficient; every command checks the grant or owner gate. Expired shops stay read-only under D13. Revoked members lose access immediately.
- Shop profile: owner-only idempotent RPC updates `shops.name`, `shops.owner_display_name`, and canonical `shops.phone`, and updates the owner Auth phone in the same transaction. Issued invoice editions keep frozen identity.

## Data and compatibility impact

Additive migration restores `partner`/`employee` on `shop_memberships`, replaces the one-owner-per-shop unique constraint with a partial unique owner index, keeps one shop per user, recreates `shop_member_grants` and append-only grant audit, widens `private.is_active_shop_member` and `private.opening_require_reader_shop`, and adds `private.is_shop_owner` / `private.has_shop_permission`. Owner-authenticated Edge Function `shop-staff-create` creates staff Auth users. Old owner-only clients that hard-require `member_role = owner` must accept `partner`/`employee` and grants. Closing-staff tables and RPCs are unchanged.

## Verification

SQL/RLS: employee blocked from other actors’ operations, shop balances, close confirmation, profile, staff admin, and a second shop; limited partner blocked from ungranted commands; owner succeeds; revoked/expired fail closed; profile replay and duplicate phone fail cleanly. Flutter: grant navigation, staff form, profile form. Arabic RTL light/dark review of new screens. Development deploy to `xchapwvmvoefriqcxtvn` with preservation.

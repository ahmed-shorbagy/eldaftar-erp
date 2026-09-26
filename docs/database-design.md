# Database design and transaction model

## Egypt owner registration — implemented in development

[ADR 0002](adr/0002-egypt-password-auth.md) replaces verified-email authorization. The forward migration `supabase/migrations/20260926075930_egypt_owner_password_registration.sql` is applied only to development project `xchapwvmvoefriqcxtvn`. All three rollback-only SQL suites passed and left zero synthetic users, shops, memberships, entitlements, audit rows, and reservations. The reviewed Edge registration function and development Auth settings accompany the clients. The exact call sequence, error codes, and apply gates are in [milestone-1-validation.md](operations/milestone-1-validation.md).

Registration is two service-only RPCs. `begin_owner_registration` validates the profile and inserts one `private.owner_registration_reservations` row with a database-generated UUID v4 `reserved_user_id`. It accepts no password and no caller-supplied user id. The `owner-register` Edge Function calls `auth.admin.createUser` with that id, the canonical email, the phone digits without a leading plus, and the password, using `email_confirm: true` and `phone_confirm: true` so Auth does not send a message. Those Auth flags are not proof of ownership and are not read for authorization. If the Auth response is lost, the Edge retries `getUserById(reserved_user_id)` instead of allocating another id. `complete_owner_registration` then checks that this reserved user exists and that both contacts match, and in the same transaction inserts one shop, one owner membership, and one `owner_registered` audit row. It does not insert an entitlement or a trial. Any failure rolls the shop, membership, audit, and completion status back. The reservation stays `reserved` and can be retried. Auth may already exist with no membership; RLS still hides shop rows until an entitlement exists, and `list_my_shop_accounts` reports `pending`.

A reservation is not a membership, grant, or entitlement. `reserved_user_id` has no foreign key to `auth.users` because the id is reserved first. Uniqueness covers the reservation email, the reservation phone, existing `auth.users` contacts, and canonical shop email/phone. The same request key with the same normalized profile returns the same reserved id. A different profile for that key raises `request_key_reused`. Abandoned reservations are not deleted by this migration. Later maintenance must not delete `auth.users` merely to free a reservation.

`public.egypt_governorates` holds the 27 current ISO 3166-2:EG codes, Arabic labels, and a fixed `display_order`. `anon` and `authenticated` may select it and cannot write it. Shops gain nullable `email` and `governorate_code`. Legacy rows leave both null. A row that sets either must also have a canonical Egyptian mobile in `phone`, an owner name, and `time_zone = Africa/Cairo`. Canonical phone is `+201[0125]` plus eight digits. Auth's stored phone is compared by digits only, without requiring a leading plus.

`private.is_active_shop_member`, `public.list_my_shop_accounts`, and `public.is_platform_admin` no longer read `email_confirmed_at`. At this migration they still require a non-anonymous, non-deleted `auth.users` row, plus the membership, entitlement, and platform-admin rules then in force. If the JWT presents `session_id`, it must match a non-expired `auth.sessions` row for `auth.uid()`. A missing session claim remains valid for transaction-local SQL fixtures. User metadata does not grant access. `create_shop_account`, `create_staff_invitation`, and `accept_staff_invitation` are no longer executable by `anon`, `authenticated`, or `service_role`. The next section removes those staff commands entirely. Password recovery remains undesigned.

## Owner-only access — 2026-09-26

[ADR 0003](adr/0003-owner-only-shop-access.md) removes staff invitations and per-user grants. The applied forward migration `supabase/migrations/20260926120634_owner_only_access.sql` drops `shop_invitations`, `shop_member_grants`, the staff RPCs, `private.can_manage_staff`, and `private.has_shop_permission`. `shop_memberships.role` is constrained to `owner`, with one membership per shop and one shop per Auth user. `revoked_at` still suspends that owner. `list_my_shop_accounts` returns `member_role = owner`. Future shop commands authorize the signed-in, non-revoked owner through `private.is_active_shop_member` and `private.can_write_shop`; they do not consult a permission grant. Development evidence is recorded in [milestone-1-validation.md](operations/milestone-1-validation.md).

## Status and design principles

The financial model below is proposed. Identity migrations through the owner-only access revision are implemented and tested on the development Supabase project. Clean local and staging replay remain open. Validate the unresolved business rules in decisions.md before writing irreversible migrations. All authoritative cash, gold, quantity, obligation, and business-day effects are produced by server transactions. A successful client response is evidence of a committed operation; a timeout is an unknown outcome resolved by idempotency lookup. Each tenant-owned row carries shop_id and is protected by RLS.

Use integer minor currency units and integer milligrams, never binary floating point. For EGP, 1 pound is 100 minor units; 1 gram is 1,000 milligrams. Persist ISO currency code and currency exponent or enforce one approved shop currency. Conversions and display rounding are explicit at the boundary. PostgreSQL numeric can be used for derived rates/prices where needed, but final postings use integer units. Counts are integers. Karat is a constrained small integer in 14, 18, 21, 22, 24, with category restrictions.

## Implemented identity draft

The ordered migrations through `20260924141455_list_my_shop_accounts_status.sql` are the historical development identity draft: shops, memberships, staff grants, one entitlement per shop, invitations, identity audit, and a separate platform-admin check. Supabase Auth provides identity. An expired entitlement permits owner reads and denies shop writes. A new shop remains pending activation until an owner-controlled entitlement is provisioned; account setup does not invent a trial term. Those eight migrations were applied to development project `xchapwvmvoefriqcxtvn`; the earlier rollback-only scripts passed there on PostgreSQL 17.6. That run still enforced `email_confirmed_at` and is historical.

`20260926075930_egypt_owner_password_registration.sql` is the ninth applied development migration. With it, contact-confirmation timestamps stop authorizing access, legacy shop setup and both invitation RPCs stop being API-callable, and new owner profiles go through the reservation RPCs above.

`20260926120634_owner_only_access.sql` is the tenth applied identity migration. It removes the dormant invitation and grant surface and constrains each shop to one owner account. Financial groups below remain proposed; the worked posting examples are still unsigned. Clean local and staging replay remain unverified.

## Entity groups

Names are illustrative; migrations should choose stable naming once contracts are approved.

| Group | Proposed tables | Key relationships and constraints |
| --- | --- | --- |
| Tenancy and identity | shops, shop_settings, profiles, shop_memberships | one owner Auth user per shop and one shop per Auth user; `revoked_at` suspends that account; membership changes are audited |
| Business calendar | business_days, day_closures, count_sheets | shop_id plus day sequence unique; only one open day per shop unless explicitly approved; closure references frozen counts and discrepancies |
| Catalog | product_categories, products, product_variants, inventory_lots, bullion_denominations, coin_types | category defines allowed karats and tracking mode; lot belongs to shop/product/karat; no cross-shop FK |
| Operations | operations, operation_lines, operation_links, command_requests | operation has shop, type, state, business_day, actor, server sequence/time, document number and immutable payload hash; command_requests unique by shop/key, with actor and payload hash recorded as attributes, and stores outcome |
| Journal | ledger_accounts, journals, journal_postings | posting links operation and account; unit type is money, gold_mg, or count; per journal and unit/currency/karat the signed sum is zero |
| Trading | sale_details, purchase_details, tender_lines, return_details | one-to-one typed detail to operation; line item references lot/product; tender lines point to payment method account |
| Inventory | inventory_receipts, recognition_allocations, stock_counts, stock_adjustments | receipt can be held unrecognized, then linked once to stock/scrap/custody allocation; manual stock entry must link to receipt |
| Accounts | traders, trader_transactions, obligations, obligation_settlements, financing_sources | obligations carry direction, commodity/currency, counterparty, due state; settlements post through journal |
| Repairs | repairs, repair_events, repair_media | repair state and custody movement linked to customer and operation; delivery requires authorized transition |
| CRM | customers, customer_phones, customer_notes, customer_requests, contact_consents | unique normalized phone per shop only if approved; notes and contact data scoped to the owning shop |
| Documents | invoice_snapshots, invoice_render_jobs, invoice_dispatches, dispatch_attempts, attachments | invoice snapshot freezes confirmed transaction details; dispatch and media are separate state machines |
| Reports and messages | report_jobs, notification_jobs, delivery_attempts, projection_cursors | generated outputs reference the owning shop; retries have stable keys |
| Subscriptions and content | plans, subscription_codes, code_redemptions, subscriptions, entitlement_events, retention_cases, help_topics, help_articles, release_policies | subscription belongs to one shop and its single owner account; redemption is idempotent and audited; retention case tracks expiry, warning, restore, deletion eligibility |
| Audit and integration | audit_events, outbox_events, projection_versions, reconciliation_runs | append-only audit/outbox; outbox event references committed operation; projections record last sequence |

All tenant FKs should include or validate shop_id so a row cannot reference another shop's product, customer, day, or operation. UUID primary keys are convenient for distributed drafts, but a server-assigned monotonically increasing sequence per shop is required for ordered synchronization. Use generated document numbers scoped by shop and business day rather than relying on UUID sort order.

## Journal conventions and invariants

A ledger account has shop_id, account_kind, unit_kind, optional currency and karat, and owner/ref (cash method, lot, scrap bucket, trader obligation, customer obligation, external clearing, expense or revenue category). One journal contains two or more signed postings for the same homogeneous unit. Positive means an increase in that account's natural balance; negative means a decrease. For every journal grouped by unit_kind, currency and karat, signed posting amounts sum to zero. Account semantics and balance direction must be documented in code and tested; do not infer customer debt from a cash balance.

Example: a sale of 1.830 g of 21K jewelry for EGP 7,000 in cash creates a money journal with +700000 minor units to cash and -700000 to sales consideration clearing. A separate gold journal moves -1830 mg from saleable stock and +1830 mg to gold sold clearing. If the category tracks pieces, a third count journal moves -1 from saleable count and +1 to count sold clearing. The three units are never summed or converted to balance a journal. If the system later needs statutory accounting, map these operational postings to a separately defined general ledger with tax, revenue, cost and valuation policy.

For a cash-method transfer, debit/increase destination account and credit/decrease source account by the same minor units in one transaction. For a return, link the original operation and create compensating postings; never delete the sale. For an expense, cash decreases and an expense/clearing account increases in the same currency. For a stock adjustment, stock changes against an authorized adjustment account and requires a reason, actor, and audit event. Negative balance policy must be decided per account; if allowed for a special case, it must be visible and deliberate.

The server must enforce:
- every confirmed operation has its required typed detail and journal groups;
- every posting amount is a nonzero integer in the account's unit, with bounds checked before arithmetic;
- journal groups balance exactly and use allowed karats/currency;
- a lot and cash account belong to the same shop as the operation;
- no confirmed operation is updated or deleted; corrections use linked compensating operations;
- materialized balance projections equal the sum of postings through their recorded sequence;
- day close blocks or explicitly routes later posting to a new/reopened day through an audited owner command;
- one idempotency key unique within a shop plus payload hash yields one immutable outcome; actor_id is recorded but is not part of uniqueness or status lookup.

Use transaction-level locking on business-day state and affected accounts/lots, or equivalent serializable logic with retry. Define lock order to prevent deadlocks. Enforce invariants with constraints/triggers and protected server functions, not only application code. Each financial command is a versioned, narrowly granted PostgreSQL SECURITY DEFINER RPC with a fixed search_path, executing as one database transaction. Lock in a documented order, such as business day, cash accounts by ID, then inventory lots by ID, and retry only safe serialization/deadlock failures under the same idempotency key. An Edge Function that makes several independent API writes is insufficient.

## Transaction examples and edge cases

### Sale and mixed payment

The command validates each line's category/karat, count, weight, stock availability, unit price or invoice allocation rule, and the sum of cash/bank/wallet tender lines. It creates an operation, lines, invoice snapshot intent, account postings and audit/outbox rows. Split tenders increase their distinct cash-method accounts. A sale may link an existing customer or create one only if permitted. Invoice PDF rendering and dispatch follow asynchronously; they cannot roll back or duplicate the financial transaction.

### Purchase, outside financing and delayed recognition

The source explicitly allows a purchase with no cash paid and/or only part of the gold added to scrap or stock. Do not record the missing portion as if it vanished. The postings depend on who actually pays the customer and who owns and physically receives the gold. In the source's financier case, a third party may fund the customer in exchange for taking some or all gold; the shop must not automatically book that gold as its own stock or a generic customer payable. Approve a worked three-party example under D05 before designing obligations. Record any gold in shop custody but not yet owned or classified in a distinct custody/unallocated account. Store recognition allocations and provenance; allocated mg and count cannot exceed received mg and count, and a receipt line cannot be recognized twice. Partial recognition posts only the allocated amount; the remainder stays visible. The review screen must show payer, recipient, custody/ownership, paid now, obligation, recognized gold and unallocated gold.

### Trader goods and manual stock link

A trader receipt creates the appropriate trader gold/cash obligation and received-but-unrecognized goods record. Recognize later via an allocation command that links the receipt to an inventory lot and posts the movement once. If the user already entered the stock manually, an authorized reconciliation command links that existing confirmed stock operation to the receipt only after the owner confirms the explicit receipt_id and existing stock_operation_id pair and the shop, product, karat, weight and count match; it must not create a second stock movement. Identical-looking receipts are not interchangeable. A cosmetic “manually added” flag without a ledger link is insufficient.

### Day close

The day close command takes an expected day version and counted cash by method plus counted gold by bucket/karat, compares to authoritative projections, stores discrepancies and notes, and closes the day atomically. The owner can review and sign. A discrepancy should generate a separately approved adjustment operation, not silently overwrite balances. Closing a day after midnight uses its business_day_id and shop time zone. Reopening, if allowed, requires an explicit owner command and audit, with report versioning.

### Repair and debts

Repair intake moves customer goods into custody, not saleable stock, unless ownership changes through a later operation. Handover removes custody once, and any collected fee posts to cash and revenue/clearing only after explicit confirmation. A debt or trader obligation can be in money or gold by karat; partial settlement reduces the exact obligation unit and posts the corresponding cash/stock effect only when the user chose that effect. Reminder state is separate from obligation balance.

## RLS and authorization

[ADR 0003](adr/0003-owner-only-shop-access.md) replaces the earlier partner/employee grant matrix. The signed-in, non-revoked owner can read that shop when an entitlement row exists, and can write only while the entitlement is active. A revoked owner, another shop's owner, an anonymous session, and a platform administrator have no ordinary shop access. There is no second shop role to grant or deny.

All tenant tables enable RLS and deny by default. Auth helpers derive the owner membership from auth.uid(); they must avoid recursive policy evaluation and use a fixed search_path. Do not trust JWT user metadata as authorization. Policies filter both SELECT and any allowed INSERT/UPDATE; most financial writes are denied directly to clients and exposed only through protected RPCs. Test anonymous, revoked-owner, cross-shop, expired-read, expired-write, and platform-admin cases, including a crafted shop_id and nested FK attacks. Table access and storage object permissions must agree.

A platform role is assigned through protected server-side administration, not a client-editable profile field. Every admin action that changes entitlement, help content, release policy or retention state writes a separate platform audit event.

Audit rows are append-only: revoke UPDATE and DELETE from ordinary and platform application roles, protect administrative database access, and log any exceptional maintenance path. This prevents normal users from editing history; it does not by itself prove cryptographic immutability. If tamper evidence is required, assess a hash chain or external immutable log together with backup and legal-hold policy.

## Projection, indexes and query design

Create read models for business-day cards, cash balance by method, stock by product/karat/lot, scrap by karat, trader and customer balances, CRM weight summaries, operation metrics and subscription state. Open-day balance cards use a synchronous scoped view or same-transaction update so a confirmed operation appears immediately. Other projections record the latest applied shop sequence. Rebuild from confirmed journals and source records; compare checksums/totals in scheduled reconciliation. The UI should fetch a scoped snapshot then follow cursor events; event subscription alone is not complete sync.

Likely indexes include (shop_id, sequence), (shop_id, business_day_id, sequence), (shop_id, actor_id, sequence), (shop_id, customer_id, sequence), (shop_id, trader_id, sequence), (shop_id, product_id, karat), (shop_id, due_at), and unique (shop_id, idempotency_key). Add partial indexes for open days, pending invoice dispatch, unrecognized trader receipts, and active subscriptions. Validate choices with actual query plans and production-like synthetic data before retaining indexes.

## New-shop opening balances

For each new shop, start with zero balances or enter opening cash by payment method, stock grams and count by lot/karat, scrap by karat, and trader/customer obligations as a separately authorized opening operation before the first live day. Reconcile entered values to a signed physical or paper count, retain that evidence privately, and make the command idempotent. Never use a silent UPDATE to seed balances. D01 records the greenfield decision and the onboarding opening-balance policy; no legacy application import is required.

A mockup card called gross profit must not be derived as sales less purchases. Operational cash and gold journals do not contain valuation, cost of goods, tax or workmanship profit. Hide that card or show an explicitly defined net cash movement label until D26 approves a true formula.

## Retention, deletion and recovery

The stated product requirement is to retain expired subscription data for four months and warn 30 days before deletion, with restoration on renewal. Model subscription active -> grace/retained -> warned -> deletion eligible -> deleted, with server timestamps and idempotent scheduled jobs. Exact time calculation, user access during retention, charge disputes, legal hold, audit retention, backup expiry and deletion evidence require product/legal decisions. Never make “reset all data” a direct client-side table wipe. Use a protected, audited request and a defined scope, cooling/confirmation workflow, export option, and restoration policy. An immutable audit requirement may conflict with absolute erasure; resolve that before implementing deletion.

Backups must cover Postgres and R2 object references consistently enough to restore invoices and notes. Specify RPO/RTO, encryption, access control, retention and restore drills before production. A migration that changes posting semantics needs an explicit backfill and reconciliation report. Test migrations from an empty database and from the preceding production schema using synthetic data. No migration should silently rewrite confirmed postings.

## Contract and test strategy

Define command schemas and generated client types from the backend contract. Version incompatible request/response changes. Contract tests exercise each command's success, validation error, owner-access denial, timeout/idempotent replay, concurrent submission, closed-day race, and cross-shop reference. Property tests assert journal balance and projection equality over generated sequences. RLS tests run as real authenticated roles against an isolated database. Restore and retention tests use synthetic tenants. UI tests verify Arabic errors and pending/reconciliation states, with no mock-only claim of financial correctness.

See architecture.md for runtime boundaries and decisions.md for unresolved policy choices.

## Shop account selection contract

`public.list_my_shop_accounts()` is the non-revoked owner lookup used after Auth. Its result is shop id, name, `member_role = owner`, `subscription_expires_at`, and `entitlement_status`. PostgreSQL computes `pending` for no entitlement or a future start, `active` for `starts_at <= now() < expires_at`, and `expired` after expiry. This avoids using a client clock to decide shop access. The Flutter adapter rejects any role other than `owner` and treats a missing or unknown status as an invalid response. It closes the selected shop view on access failure. A presented JWT `session_id` must still be a live `auth.sessions` row. Staging and production rollout remain separate acceptance steps.

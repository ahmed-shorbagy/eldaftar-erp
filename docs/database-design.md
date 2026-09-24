# Database design and transaction model

## Status and design principles

This is a proposed PostgreSQL/Supabase model, not an implemented schema. Validate the unresolved business rules in decisions.md before writing irreversible migrations. All authoritative cash, gold, quantity, obligation, and business-day effects are produced by server transactions. A successful client response is evidence of a committed operation; a timeout is an unknown outcome resolved by idempotency lookup. Each tenant-owned row carries shop_id and is protected by RLS.

Use integer minor currency units and integer milligrams, never binary floating point. For EGP, 1 pound is 100 minor units; 1 gram is 1,000 milligrams. Persist ISO currency code and currency exponent or enforce one approved shop currency. Conversions and display rounding are explicit at the boundary. PostgreSQL numeric can be used for derived rates/prices where needed, but final postings use integer units. Counts are integers. Karat is a constrained small integer in 14, 18, 21, 22, 24, with category restrictions.

## Entity groups

Names are illustrative; migrations should choose stable naming once contracts are approved.

| Group | Proposed tables | Key relationships and constraints |
| --- | --- | --- |
| Tenancy and identity | shops, shop_settings, profiles, shop_memberships, roles, permissions, role_permissions, membership_overrides, invitations | memberships link auth.users to shops; one active owner minimum; unique active membership per user/shop; every grant change audited |
| Business calendar | business_days, day_closures, count_sheets | shop_id plus day sequence unique; only one open day per shop unless explicitly approved; closure references frozen counts and discrepancies |
| Catalog | product_categories, products, product_variants, inventory_lots, bullion_denominations, coin_types | category defines allowed karats and tracking mode; lot belongs to shop/product/karat; no cross-shop FK |
| Operations | operations, operation_lines, operation_links, command_requests | operation has shop, type, state, business_day, actor, server sequence/time, document number and immutable payload hash; command_requests unique by shop/key, with actor and payload hash recorded as attributes, and stores outcome |
| Journal | ledger_accounts, journals, journal_postings | posting links operation and account; unit type is money, gold_mg, or count; per journal and unit/currency/karat the signed sum is zero |
| Trading | sale_details, purchase_details, tender_lines, return_details | one-to-one typed detail to operation; line item references lot/product; tender lines point to payment method account |
| Inventory | inventory_receipts, recognition_allocations, stock_counts, stock_adjustments | receipt can be held unrecognized, then linked once to stock/scrap/custody allocation; manual stock entry must link to receipt |
| Accounts | traders, trader_transactions, obligations, obligation_settlements, financing_sources | obligations carry direction, commodity/currency, counterparty, due state; settlements post through journal |
| Repairs | repairs, repair_events, repair_media | repair state and custody movement linked to customer and operation; delivery requires authorized transition |
| CRM | customers, customer_phones, customer_notes, customer_requests, contact_consents | unique normalized phone per shop only if approved; notes and contact data scoped by permission |
| Documents | invoice_snapshots, invoice_render_jobs, invoice_dispatches, dispatch_attempts, attachments | invoice snapshot freezes confirmed transaction details; dispatch and media are separate state machines |
| Reports and messages | report_jobs, notification_jobs, delivery_attempts, projection_cursors | generated outputs reference scope and permission; retries have stable keys |
| Subscriptions and content | plans, subscription_codes, code_redemptions, subscriptions, entitlement_events, retention_cases, help_topics, help_articles, release_policies | admin mutations audited; retention case tracks expiry, warning, restore, deletion eligibility |
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
- day close blocks or explicitly routes later posting to a new/reopened day under controlled permission;
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

The day close command takes an expected day version and counted cash by method plus counted gold by bucket/karat, compares to authoritative projections, stores discrepancies and notes, and closes the day atomically. The owner or delegated closer can review and sign. A discrepancy should generate a separately approved adjustment operation, not silently overwrite balances. Closing a day after midnight uses its business_day_id and shop time zone. Reopening, if allowed, requires elevated permission and audit, with report versioning.

### Repair and debts

Repair intake moves customer goods into custody, not saleable stock, unless ownership changes through a later operation. Handover removes custody once, and any collected fee posts to cash and revenue/clearing only after explicit confirmation. A debt or trader obligation can be in money or gold by karat; partial settlement reduces the exact obligation unit and posts the corresponding cash/stock effect only when the user chose that effect. Reminder state is separate from obligation balance.

## RLS and authorization matrix

| Data or command | Shop owner | Partner | Employee | Platform admin |
| --- | --- | --- | --- | --- |
| Own shop configuration and grants | manage | explicit grant | normally none | no implicit shop access |
| Confirm sale/purchase | yes | per grant | per grant | no |
| Read operations | all own shop | per grant | own operations or explicitly granted scope | no |
| Inventory and aggregate balances | all own shop | per grant | per grant, possibly limited view | no |
| Close day, adjustment, return, reset | yes with step-up control | explicit elevated grant | only specifically delegated | no |
| CRM phone, invoices, dispatch | yes | per grant | distinct read and dispatch grants | no |
| Audit | read own shop | per grant | possibly own actions only | platform audit metadata only |
| Subscription/help administration | only own entitlement | no | no | scoped platform role |

All tenant tables enable RLS and deny by default. Auth helpers derive membership from auth.uid() and database grants; they must avoid recursive policy evaluation and use a fixed search_path. Do not trust JWT user metadata as the only source of mutable permissions. Policies filter both SELECT and any allowed INSERT/UPDATE; most financial writes are denied directly to clients and exposed only through protected RPCs. Test anonymous, revoked, cross-shop, expired subscription, employee, partner and owner cases, including crafted shop_id and nested FK attacks. Table access and storage object permissions must agree. Views used for employee dashboards must not leak owner totals through aggregates.

A platform role is assigned through protected server-side administration, not a client-editable profile field. Every admin action that changes entitlement, help content, release policy or retention state writes a separate platform audit event.

Audit rows are append-only: revoke UPDATE and DELETE from ordinary and platform application roles, protect administrative database access, and log any exceptional maintenance path. This prevents normal users from editing history; it does not by itself prove cryptographic immutability. If tamper evidence is required, assess a hash chain or external immutable log together with backup and legal-hold policy.

## Projection, indexes and query design

Create read models for business-day cards, cash balance by method, stock by product/karat/lot, scrap by karat, trader and customer balances, CRM weight summaries, employee metrics and subscription state. Open-day balance cards use a synchronous scoped view or same-transaction update so a confirmed operation appears immediately. Other projections record the latest applied shop sequence. Rebuild from confirmed journals and source records; compare checksums/totals in scheduled reconciliation. The UI should fetch a scoped snapshot then follow cursor events; event subscription alone is not complete sync.

Likely indexes include (shop_id, sequence), (shop_id, business_day_id, sequence), (shop_id, actor_id, sequence), (shop_id, customer_id, sequence), (shop_id, trader_id, sequence), (shop_id, product_id, karat), (shop_id, due_at), and unique (shop_id, idempotency_key). Add partial indexes for open days, pending invoice dispatch, unrecognized trader receipts, and active subscriptions. Validate choices with actual query plans and production-like synthetic data before retaining indexes.

## Opening balances and historical migration

Before the first live day, import or enter opening cash by payment method, stock grams and count by lot/karat, scrap by karat, and trader/customer obligations as a separately authorized opening operation. Reconcile each source total to the existing application or signed paper count. Preserve original source identifiers for traceability and make import idempotent. Never use a silent UPDATE to seed balances. D01 must establish the deployed-app parity and migration map before this schema is finalized.

A mockup card called gross profit must not be derived as sales less purchases. Operational cash and gold journals do not contain valuation, cost of goods, tax or workmanship profit. Hide that card or show an explicitly defined net cash movement label until D26 approves a true formula.

## Retention, deletion and recovery

The stated product requirement is to retain expired subscription data for four months and warn 30 days before deletion, with restoration on renewal. Model subscription active -> grace/retained -> warned -> deletion eligible -> deleted, with server timestamps and idempotent scheduled jobs. Exact time calculation, user access during retention, charge disputes, legal hold, audit retention, backup expiry and deletion evidence require product/legal decisions. Never make “reset all data” a direct client-side table wipe. Use a protected, audited request and a defined scope, cooling/confirmation workflow, export option, and restoration policy. An immutable audit requirement may conflict with absolute erasure; resolve that before implementing deletion.

Backups must cover Postgres and R2 object references consistently enough to restore invoices and notes. Specify RPO/RTO, encryption, access control, retention and restore drills before production. A migration that changes posting semantics needs an explicit backfill and reconciliation report. Test migrations from an empty database and from the preceding production schema using synthetic data. No migration should silently rewrite confirmed postings.

## Contract and test strategy

Define command schemas and generated client types from the backend contract. Version incompatible request/response changes. Contract tests exercise each command's success, validation error, permission denial, timeout/idempotent replay, concurrent submission, closed-day race, and cross-shop reference. Property tests assert journal balance and projection equality over generated sequences. RLS tests run as real authenticated roles against an isolated database. Restore and retention tests use synthetic tenants. UI tests verify Arabic errors and pending/reconciliation states, with no mock-only claim of financial correctness.

See architecture.md for runtime boundaries and decisions.md for unresolved policy choices.

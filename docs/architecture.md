# System architecture

## Architecture goal and present state

ElDafttar ERP is a greenfield, multi-tenant subscription service for many independent gold shops. Each shop is operated by exactly one owner account, and that account belongs to exactly one shop ([ADR 0003](adr/0003-owner-only-shop-access.md)). One subscription entitlement covers that shop and its owner under the revised D28. There is no staff invitation, partner, employee, or per-user permission grant. Flutter serves Android, iOS, and Windows. React serves platform administration. Supabase provides identity, PostgreSQL, row-level security (RLS), database transactions and server functions. Cloudflare R2 stores private binary attachments through server-authorized access. The architecture must favor correctness of cash and grams over apparent speed.

Today the repository has starter clients and connection checks only. Paths below are the target layout. No database schema, RLS, transaction RPC, or attachment endpoint should be assumed to exist.

## Runtime boundaries

~~~mermaid
flowchart LR
  F[Flutter Android iOS Windows] -->|JWT, reads, commands| S[Supabase API]
  A[React platform admin] -->|JWT, admin commands| S
  S --> P[(PostgreSQL + RLS)]
  S --> E[Edge Functions]
  E --> R[(Private R2 bucket)]
  E --> N[Notification and dispatch providers]
  W[Scheduled workers] --> P
  W --> N
  P --> Q[Scoped read models and realtime hints]
  Q --> F
  Q --> A
~~~

Each client uses only public project identifiers and user tokens. A service-role key remains server-side. RLS is a mandatory second boundary, even when an Edge Function or UI checks permission. All cash, stock, scrap, debt, and day-state mutations enter through versioned PostgreSQL command functions exposed as authenticated RPCs. A single protected SQL function owns each financial transaction and validates, authorizes, posts, audits, and returns a stable result. Edge Functions handle R2, PDF and provider integrations; they must not orchestrate multiple independent financial writes. Direct client inserts into authoritative posting tables are denied.

Admin is a separate trust domain. A platform administrator may manage subscriptions and help content but must not automatically gain access to a shop's customer or financial records. Subscriber contact/location data needed by platform administration belongs in a separate, narrowly authorized platform profile; it must not be joined to shop journal rows for ordinary admin access. Any support access requires a separately approved, time-limited, audited process.

## Domain boundaries

| Domain | Owns | Depends on |
| --- | --- | --- |
| Identity and tenancy | Shops and the single owner membership | Supabase Auth |
| Catalog and inventory | Categories, products, lots, saleable stock, scrap, counts | Identity, ledger posting contract |
| Trading and daily ledger | Sales, purchases, tenders, business day, quick actions, returns | Catalog, customers, posting engine |
| Accounts | Trader obligations, customer debt, external financing, settlements | Trading, posting engine |
| Repairs | Intake, custody, completion, handover, fees | Customers, catalog, posting engine |
| CRM and communication | Customers, contact methods, notes, requests, invoices, dispatch queue | Trading, permissions, R2 |
| Reports and analytics | Reconciled read models and exports | Confirmed operations/postings |
| Subscriptions and platform admin | Entitlements, codes, retention, notices, help content | Identity, scheduled jobs |
| Audit and operations | Append-only audit, reconciliation, monitoring, backup and restore | All mutation boundaries |

Avoid circular domain imports. Cross-domain coordination belongs in application use cases or server command orchestration. A read model can combine domains, but it must be derived and rebuildable.

## Proposed monorepo layout

~~~text
app/
  lib/src/
    app/                  bootstrap, routing, localization, session boundary
    core/
      design/              tokens, responsive rules, theme, RTL components
      domain/              exact units, errors, result types, identifiers
      data/                Supabase transport, local draft store, sync cursor
      security/            auth state and permission presentation
    features/
      onboarding/
      daily_ledger/
      sales/
      purchases/
      inventory/
      traders/
      repairs/
      debts/
      customers/
      invoices/
      reports/
      settings/
      help/
    shared/                reusable widgets with no business rules
  test/
    domain/ integration/ widget/ golden/
admin/
  src/
    app/                  routing, auth, localization, theme
    features/
      subscribers/ subscription_codes/ notifications/
      help_content/ release_policy/ support/
    shared/               UI components, contracts, transport
    test/
supabase/
  migrations/             ordered SQL, reviewed and reproducible
  functions/              authenticated Edge Functions
  tests/                  RLS, transaction, migration, retention tests
  seeds/                  synthetic development fixtures only
  contracts/              request/response schema and generated types
docs/
  adr/                    decisions that change contracts or persistence
  operations/             runbooks, backups, incidents, release checklists
~~~

The exact names can evolve through an architecture decision, but the dependency rule does not: Flutter presentation depends on use cases and domain interfaces; data adapters implement those interfaces; domain code does not import Flutter, Supabase, or local storage. React remains independent of Flutter. Both clients consume the same versioned backend contracts, enums and authorization semantics. Shared visual guidance is documented, not implemented by importing one client's UI code into the other.

A feature package should contain domain entities/value objects, use cases, repository interfaces, data DTOs/adapters, and presentation state/widgets. Domain types use integers for money minor units and gold milligrams. Parsing and formatting live at boundaries. No binary floating point reaches persistence or ledger calculations.

## Command boundary and example

A sale follows one state machine: local draft -> reviewed -> submitting -> confirmed, pending reconciliation, or rejected. The review shows item count, grams by karat, money by method, change, and stock/cash effects. The client sends a UUID idempotency key unique within the shop, expected business-day version and command payload to one protected PostgreSQL RPC. The function checks the JWT, membership and permission, validates all units and category-karat rules, locks the relevant day and balance/lot rows, checks stock and tender constraints, writes the immutable operation plus postings and audit event in one PostgreSQL transaction, and returns a stable result identifier. A repeat with the same key and identical payload returns the original result. The same key with a different payload is rejected.

A client timeout leaves the sale in pending reconciliation. The UI queries by idempotency key; it never submits a new sale key merely because the first response was lost. Realtime events are hints to refresh a server-scoped feed, not the source of truth. The client records a per-shop server sequence/cursor, re-fetches gaps after reconnect, and invalidates affected summaries. This also handles missed events on Windows or mobile sleep.

Purchases, returns, cash transfers, trader settlements, repair handovers, inventory adjustments and day close use the same command envelope and transaction discipline. Operations that require attachment upload can commit metadata and an upload intent, but the financial transaction never waits on an external R2 upload; it clearly reports the attachment as pending until confirmed.

## Business day and time

Store event and audit timestamps in UTC from the server. Each shop has an IANA time zone, a business-day identifier and an explicit open/closed state. A business day is not inferred from the device date: an owner can close the current day after midnight, and the next open day begins only according to an approved rule. Server commands reference a business-day ID and version; a stale close or post is rejected with a reconcilable response. Reports use the business-day assignment for ledger totals and UTC timestamps for ordering. Display localized dates/times in Arabic and the shop time zone.

## Security model

Supabase Auth proves identity. Shop membership and role/permission grants decide data access. RLS filters every tenant-owned table by shop ID and user entitlement. Server command functions recheck authorization and must not accept a caller-supplied actor ID. Employee row visibility is scoped to their own operations unless a distinct aggregate/report permission is granted. Platform admin claims are separate from shop roles. Sensitive customer phone numbers, invoices and media require explicit permissions.

Use narrow SECURITY DEFINER functions only for protected commands and authorization helpers; fix search_path, use qualified table names, and revoke public execute. Keep table policies simple enough to test. Ordinary clients cannot write postings, audit events, subscription entitlements, or dispatch evidence directly. Audit events capture actor, shop, command, before/after references, server time, and correlation ID. Database roles and backup controls should prevent ordinary users from editing audit history.

For R2, use a private bucket. An authenticated Edge Function validates the user and shop, attachment purpose, size/type, and record access, then issues a short-lived presigned upload/download URL. Persist metadata and object key in Postgres. Object keys must be opaque; they must not expose customer names or phone numbers. Complete upload by validating server-visible object metadata. Plan orphan cleanup and malware scanning according to chosen file types. Never put R2 secret keys in Flutter or Vite.

## Read models and performance

The operation/posting journal is authoritative. Shop/day summaries, customer weight statistics, employee metrics and inventory balance cards are derived read models. Open-day cash/gram cards must be computed from a synchronous scoped view or updated in the same transaction as postings, so a confirmed sale appears immediately. Slower analytics may use a transaction-safe outbox; label their freshness. Every projection has a rebuild procedure and reconciliation query. Index the tenant plus business day, created sequence, customer, trader, product and due-date access paths. Paginate feeds with server cursor, not client-side full-table loading.

Do not use a push notification as an accounting event. Notifications can be delayed or duplicated. Choose and document a concrete scheduler (Supabase-supported cron, Edge scheduled invocation, or a separately operated worker) before reminders and retention go live. Its jobs create reminder and subscription notices with idempotency and record delivery attempts. A forced app update policy needs a safe rollout and a minimum supported version per platform; it cannot silently block users from retrieving their own records during an outage.

## Invoice and communication path

Confirmed transactions produce a versioned invoice snapshot and Arabic PDF. Rendering may run asynchronously, with a visible pending state. The pending-send queue holds invoices whose creator cannot dispatch and any authorized user's unsent invoices. Dispatch permission is separate from sale permission. A WhatsApp deep link creates a handoff record; unless a provider callback or explicit authorized user attestation exists, mark the outcome as handed off or unverified, not delivered. Log who initiated or confirmed dispatch and when. Repeated attempts must not change the financial transaction.

## Operational design

Use separate development, staging and production Supabase/R2 environments under owner-controlled accounts. Migrations are forward-only and reviewed; destructive changes need a restore drill and data migration plan. Protect main with CI gates and secret scanning. Keep synthetic fixtures only. Before launch, establish backup frequency, point-in-time recovery eligibility, restore objectives, retention/deletion controls, alerting, and incident ownership. Never test retention deletion on production data without an approved dry run.

Record structured, privacy-minimized server events with correlation IDs and idempotency keys. Alert on failed commands, duplicate-key conflicts, projection drift, stuck pending uploads/dispatches, scheduled-job failures, and RLS denials. Avoid logging phone numbers, invoice contents, credentials, or raw request payloads. Reconciliation jobs compare account balances and stock counts against postings and surface discrepancies for owner review; they do not silently rewrite source entries.

## Evolution constraints

Use vertical releases through the real ledger flow before building broad screens. New modules must define their state machine, posting effects, permissions, audit event, sync behavior, tests and UI states before implementation. A feature flag may hide unfinished functionality but must not be the security boundary. The first sale command cannot ship before a minimum category, lot/count and scrap model can post its inventory effect atomically; richer inventory screens may follow. Use additive migrations, versioned command payloads, and tolerant clients for mobile release overlap. Backfills and projection rebuilds must be resumable and idempotent.

See database-design.md for the proposed relational model and delivery-plan.md for release gates.

# Long-term delivery plan

## Milestone 1 policy revision and bounded implementation queue — 2026-09-26

Follow [ADR 0002](adr/0002-egypt-password-auth.md) for the Egypt-only authentication policy. The bounded owner registration/password slice is implemented in the current work: the forward migration is applied to development and rollback-only SQL tests pass. The development Edge deployment, completed client review and gates, and exact evidence are tracked in [the validation record](operations/milestone-1-validation.md). Historical verified-email tests alone do not satisfy the revised policy.

1. Define and implement the protected registration contract: one Supabase Auth user can sign in with email/password or Egyptian phone/password; normalize and enforce unique identifiers; require owner name, business name, email, phone, governorate, and password. Validate Egyptian governorates, default the shop to `Africa/Cairo`, and keep passwords only in Auth. Design recovery from partial Auth/profile creation before calling registration complete.
2. Coordinate forward backend changes, Auth project configuration, Flutter adapters, and the React authentication gate. Remove email-confirmation prerequisites without weakening RLS, session expiry, membership revocation, or platform-admin checks. No email verification, OTP, or SMS confirmation is part of registration or login. Review compatibility with older clients before rollout. Explain any verified schema blocker before applying a migration.
3. Implement Arabic RTL Flutter login/signup with domain-owned interfaces, separate Supabase adapters and presentation. Reuse theme persistence and tokens. Keep one setup idempotency key across retries of the same request, disable duplicate submission, and show pending, confirmed, and failure states. Confirm success only after server confirmation. Preserve shop selection, pending activation without a trial, and expired read-only access. Review narrow mobile and Windows desktop in both themes.
4. Verify both login identifiers return the same user ID; wrong passwords, duplicate/invalid identifiers, missing signup fields, invalid governorates, partial registration failure, timeout/retry, session expiry, and membership loss. Prove no verification or OTP is required or sent. Re-run format, analysis, tests, Android/Windows builds and rollback-only backend authorization tests; record exact evidence in the requirements matrix and validation record.

Staff invitation/grant screens remain a following slice. Invitation binding and password recovery require their own reviewed design because unverified contacts cannot establish ownership. Financial posting remains outside this queue. Milestone 1 acceptance also retains its environment, staging, onboarding, prototype, and platform gates below.

## Planning rule

This is a dependency and acceptance plan, not a promise that all scope fits a fixed calendar. The agreement describes four broad stages over twelve work weeks: interactive design, transactional core, remaining modules/dashboard, and test/release. Keep those stages visible for stakeholder tracking. Estimate each milestone with the actual team, approved designs, new-shop onboarding policy, integration availability, and acceptance evidence. Do not mark a stage complete because its week ended.

The first production release should contain a trustworthy end-to-end vertical slice. Later releases expand breadth without weakening cash, gold, permission, audit or sync guarantees. Every release can be tested independently against synthetic shop data.

## Workstreams and dependencies

| Workstream | Foundation it needs | Shared deliverable |
| --- | --- | --- |
| Product and UX | source reconciliation, greenfield scope inventory, owner decisions | approved Arabic RTL flows, light/dark tokens, acceptance cases |
| Core platform | environments, Auth, tenancy, RLS, command envelope | authenticated clients and protected shop boundary |
| Financial engine | exact units, business-day rules, account model, idempotency | atomic operation/posting service and reconciliation |
| Inventory and connected accounts | financial engine, catalog/karat policy | stock, scrap, trader, debt and repair movements |
| Communication | confirmed invoice snapshots, permission model, R2 | PDF, pending-send queue, safe dispatch evidence |
| Platform administration | separate admin roles, subscriptions, content model | subscriber management, codes, help, notices |
| Reporting and reliability | stable postings and read models | analytics, exports, monitoring, backup and recovery |
| Release | all critical gates, owner accounts, store readiness | staged Android/iOS/Windows/admin rollout and support runbooks |

## Cross-milestone gates

| Gate | Evidence required before proceeding |
| --- | --- |
| G0 product meaning | Approved greenfield scope and onboarding/opening-balance policy, invoice numbering rule, and signed paper posting examples with money, mg, count, custody and obligations |
| G1 design | Interactive all-screens prototype approved in Arabic RTL light/dark, or explicit D12 deferral |
| G2 financial kernel | Minimum catalog/lots/scrap, opening balances and sale/purchase cash-stock journal effects in one RPC transaction |
| G3 reliability | Real-role RLS, concurrency, idempotent timeout/retry, weak-network and projection reconciliation tests green |
| G4 release | Arabic PDF/image and Windows print spike, iOS/macOS signing proof, backup restore and pilot reconciliation |

## Milestone 0 — discovery and baseline

The [Milestone 0 discovery packet](discovery/README.md) records the repository and source baseline, confirmed greenfield scope, local Word-file baseline, and unsigned worked examples. It is preparation for G0, not G0 approval.

Inventory the intended screens and workflows from the agreed three local Word files. The product owner confirmed that there is no deployed application or historical migration to plan. Define how a newly subscribed shop creates its account, invites staff, and enters verified opening balances when applicable. Compare the inventory with product-scope.md. Confirm which embedded mockups are approved design targets. Resolve the highest-impact decisions in decisions.md: currency/price/workmanship, custody and financing, business day, stock valuation/tracking, WhatsApp evidence and data deletion. Produce synthetic sample sales, purchases, trader receipts and close-day cases with expected cash and grams.

Acceptance: a signed scope matrix maps every requirement to an owner, screen, server command, permission and test. A screen-by-screen scope inventory assigns build, defer, or change, and a new-shop opening-balance process is designed. No private source document is copied to Git. A shop-domain expert signs worked examples for one sale, one three-party financed purchase, one trader receipt and one day close, showing cash by method, grams by karat, count, custody, ownership and obligations.

## Milestone 1 — platform and design foundation

Create development, staging and production environments in owner-controlled accounts. Add migration tooling, schema conventions, generated contracts, seed fixtures, RLS test harness, CI, secret scanning, telemetry and backup plan. Build Auth, shop membership, roles/grants, session expiry, account setup, and a per-shop entitlement boundary (D28) for the Arabic shell on all platforms. One shop subscription covers invited staff, but their access still follows individual grants. Establish shared design tokens and an interactive all-screens prototype for product approval, with approved captures for mobile, Windows and admin; implement light/dark persistence and RTL behavior. Treat the prototype as design evidence, not an operational ERP. Build a non-financial interactive onboarding path and Help resume entry.

Acceptance: anonymous/cross-shop/revoked access fails at the database; owner/partner/employee behavior is tested. All clients handle unavailable backend and session expiry. Visual baselines exist in both themes and the all-screens prototype is approved or explicitly deferred with D12. No shop data is shown before Auth. Arrange a macOS/iOS signing environment and owner accounts before the release window.

## Milestone 2 — transaction kernel and daily ledger

Implement integer money/gram/count value objects, a minimum catalog with category-karat rules, stock lots/counts, scrap buckets, stock constraints and opening balances, then business-day identity, account/posting model, command envelope, idempotency registry, audit/outbox and synchronous open-day balance cards. Deliver sale and purchase commands with multiple lines and tenders, customer/notes, review of effects, and reconciliation after timeout. Implement daily ledger feed, configurable summary visibility/order, actor/time display, quick cash transfer, expense and manual close after the product rules are approved.

Acceptance: simultaneous retries produce one confirmed operation; a lost response is reconciled by key; all cash, gram and required count postings balance and stock projections match; crafted permission bypass is denied. A confirmed sale changes cash and stock together. A failed purchase leaves no partial cash or stock changes. Network fault injection covers duplicate tap, timeout after commit and reconnect gap catch-up. Owner can close a selected open business day after midnight. Flutter and backend integration tests cover the real command boundary.

## Milestone 3 — stock, scrap and trader accounts

Expand the minimum catalog and lots from Milestone 2 into full instant inventory, scrap by karat, bullion/coin denominations, stock adjustments and returns. Add trader account receipts/settlements, unrecognized goods queue, manual stock linkage and reconciliation. Add purchase financing/unallocated goods only after custody and obligation policy is approved. Build inventory audit and report export. Run an early Arabic PDF/image and Windows print spike so rendering and device integration do not surprise the release.

Acceptance: stock and scrap reconcile to confirmed movements; the combined Milestone 2 and 3 slice satisfies the agreement's ledger, inventory and trader core before that stage is accepted; no trader receipt can be recognized twice; “already entered manually” requires a verified link; return/adjustment uses compensating operations. Role tests deny ungranted inventory edits. The owner can trace a displayed gram total back to operations.

## Milestone 4 — connected shop workflows

Deliver repairs with custody and handover, customer/trader debts and reminders, CRM contacts/notes/requests, invoice snapshots and PDFs, permission-controlled pending-send queue, and WhatsApp dispatch evidence. Add daily notes and private media through R2 presigned access. Expand interactive onboarding through these real controls and build searchable Help.

Acceptance: repair goods never appear as saleable stock until an explicit authorized transition; partial debt settlements reconcile; customer summaries derive from confirmed movements; a sales employee without dispatch permission cannot access/send another user's invoices. A failed upload or PDF render remains visible and retryable without replaying the financial transaction.

## Milestone 5 — administration, subscriptions and reporting

Complete independent React admin with subscriber management, codes and durations, notices, help content, version policy and platform audit. Build shop analytics and daily/weekly books from reconciled projections, with employee scope and PDF exports. Implement subscription expiry notices and retention state machine only after legal/product deletion rules are approved.

Acceptance: platform admins cannot read shop financial/CRM rows through ordinary admin access; code redemption is single-use/idempotent; reports equal authoritative totals; help edits appear without a client release; expiry/restore/deletion behavior passes synthetic timeline tests.

## Milestone 6 — integrated release

Run full functional, RLS, concurrency, offline/reconnect, Arabic accessibility, RTL and visual checks across Android, iOS, Windows and admin. Conduct stakeholder acceptance against the scope matrix and approved reference screens. Measure slow connections and large-ledger pagination. Perform schema migration and restore rehearsals, R2 access tests, observability drills and data export checks. Package releases using owner-controlled store and infrastructure accounts. Roll out to a small pilot, compare paper ledger totals daily, then expand only after discrepancy thresholds are met.

Acceptance: no unresolved critical financial/authorization defects; documented recovery steps work; pilot reconciles cash and grams; pending operations are visible and recoverable; owner accepts each feature through evidence, not a slideshow. Record exact shipped version and any deferred scope.

## Milestone 7 — operations and long-term evolution

After launch, monitor error rate, pending command age, projection drift, backup success, notification failures, subscription jobs and client version adoption. Review support tickets against the scope matrix. Run periodic restore drills and authorization regression tests. Use additive migrations and versioned command contracts to support older mobile builds during rollouts. Plan features such as advanced tax/accounting, multi-branch operations or automated WhatsApp only as separate approved decisions; do not silently change the original financial model.

## Definition of done for each feature

A feature is complete only when: the product rule and failure states are explicit; backend permission and RLS are tested; the transaction is atomic and idempotent if financial; audit and sync paths work; Arabic RTL, both themes, accessibility and responsive layouts are reviewed; domain, integration and critical UI tests pass; a staging demonstration uses real backend behavior; documentation and the scope matrix are updated; and no prototype control is presented as operational.

Before reporting a milestone complete, rerun the actual commands for affected packages. Current baseline from README.md: in app, flutter analyze, flutter test, flutter build windows, flutter build apk; in admin, npm run lint, npm test, npm run build; in supabase, connection checks exist but are network checks, not schema/RLS tests. Add database test/migration gates before the first financial release. iOS build requires a macOS signing environment and owner account; do not claim it passed from Windows.

## Risk register and controls

| Risk | Consequence | Control and early signal |
| --- | --- | --- |
| Initial requirements change during delivery | Missing or inconsistent promised behavior | Versioned scope matrix, owner decisions, and acceptance evidence before feature freeze |
| Incomplete accounting policy | Balanced-looking but economically wrong ledger | Paper examples approved by shop expert; invariant/property tests |
| Weak network and repeated taps | Duplicate or uncertain sale | Stable idempotency key, server lookup, pending reconciliation |
| RLS or admin role error | Cross-shop/customer exposure | Default deny, real-role policy tests, separate admin boundary |
| Inventory entered twice | Inflated grams | Recognition allocation and verified manual-entry linkage |
| WhatsApp handoff mistaken for delivery | Incorrect customer history | Separate handoff, user-confirmed and provider-confirmed states |
| Projection drift | Incorrect summary cards/reports | Sequence cursor, nightly reconciliation and rebuild runbook |
| Retention/reset conflict | Data loss or failure to honor policy | Written deletion scope/legal decision and restore drill |
| Cross-platform visual drift | Inconsistent Arabic RTL experience | Approved baselines, theme/size screenshot review |
| Third-party service or store access | Blocked release | Owner-controlled accounts and staging integration proof early |

## Roadmap governance

Keep a single backlog with a requirement ID, domain, priority, dependency, owner, acceptance evidence, and release target. Split work into vertical slices that deliver real value and complete data effects. Architecture decisions are reviewed before their first migration, not after code exists. Weekly demos use staging and synthetic data; the reviewer checks every visible action against implemented backend behavior. Update this plan when facts change and record the reason rather than silently deleting deferred scope.

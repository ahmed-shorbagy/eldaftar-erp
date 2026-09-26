# Architecture and product decisions

## How to use this register

These questions are deliberately open except where a row is explicitly marked accepted. They affect stored meaning, permissions or customer-facing behavior and should be answered by the product owner and a shop-domain expert before dependent implementation. Record the final answer as an ADR in docs/adr/, link the acceptance example and migration impact, then change this table to decided. A suggested direction below is an engineering proposal, not a product promise.

| ID | Decision required | Why it matters | Needed before | Suggested direction |
| --- | --- | --- | --- | --- |
| D01 | **Accepted 2026-09-24:** Greenfield build; no deployed application or legacy migration. Define how each new shop establishes its opening balances. | The product owner clarified the initial build and the local Word-file baseline | first financial migration | start at zero or use one authorized, idempotent opening operation backed by a signed count |
| D02 | What are the permitted shop currencies, price units, workmanship/tax/discount fields and rounding rules? | Determines invoice totals, minor units and revenue meaning | sale/purchase schema | use exact minor units; approve worked examples |
| D03 | Are item grams and integer count tracked per piece, lot or aggregate, and may stock go negative? | Determines count journals, lot schema, race control and reconciliation | catalog and postings | post count where tracking mode requires it; prohibit negative stock unless explicitly approved |
| D04 | How are bullion/coin nominal denominations distinguished from actual weighed grams and routed to stock or scrap? | Prevents duplicate grams, inaccurate stock and invalid karat defaults | purchase/inventory | category policy and denomination catalog; preserve actual measured mg separately |
| D05 | For three-party financed purchases, who pays the customer, owns and physically holds each gram, and who owes whom? | A financier may receive gold directly; shop stock or a generic payable could be false | purchase kernel | approve one worked customer/shop/financier posting example before any schema |
| D06 | What exactly constitutes a trader receipt, and how is manual stock already entered matched to it? | A status flag alone can hide duplicate inventory | trader workflow | verified allocation link with no second movement |
| D07 | How are customer/trader debts represented: money, grams by karat, or both, and are conversions allowed? | Changes settlement and report logic | obligations | keep units separate; require explicit conversion operation |
| D08 | What is the formal business-day open/close/reopen rule across midnight and time zones, including stale-day posts? | Determines ledger grouping, late operations and reports | day model | explicit server business-day ID; define reject versus route for a stale post and controlled reopen |
| D09 | What is the return and correction policy after close or invoice dispatch? | Editing confirmed records breaks audit and balance history | returns, close | compensating operation linked to original |
| D10 | Which roles see full day totals, other employees' operations, CRM phone numbers and reports? | Source says employees see their own operations, while dashboards need aggregate metrics | RLS and UI | distinct read scopes and grants, default least privilege |
| D11 | Is WhatsApp delivery a user handoff, manual confirmation, or provider-integrated receipt? | A deep link cannot prove sending or delivery | invoice dispatch | separate handoff/unverified/sent/delivered states |
| D12 | Which embedded mockups are approved pixel-level targets, and what are target device widths? | Reference images show ideas but no approval status or complete screen set | UI baselines | approve design system and representative screens |
| D13 | **Accepted 2026-09-24:** expiry blocks shop writes; existing authorized members may read and export within their grants until the separate D14 lifecycle applies. | Entitlements and retention are different policies | subscription RLS | implemented policy: read/export stays granted after expiry; shop writes require an active term |
| D14 | What are exact four-month retention start, 30-day warning, legal hold, audit retention and backup deletion rules? | Automatic deletion may conflict with audit and recovery duties | retention jobs | approve written lifecycle and deletion evidence |
| D15 | What does “reset the system” erase or archive, who can request it, and can it be undone? | A broad reset can destroy financial history | settings action | protected reset request with scoped preview and export |
| D16 | Are purchase goods physically received before inventory recognition, and where are unrecognized goods shown? | Distinguishes custody from saleable stock | purchase/trader data model | received/unallocated bucket with owner queue |
| D17 | How should refunds, exchanges, discounts and partial tender reversals be represented? | Affects invoice and cash corrections | sale/return contract | explicit linked operation types |
| D18 | Which reports are contractual, what is their exact grouping and PDF layout, and who may export them? | “Daily/weekly” and “analytics” leave many interpretations | report projections | approve examples with expected numbers |
| D19 | Which notification channels and support contact paths are required at launch? | Push, email, in-app and WhatsApp have different evidence and cost | notification service | prioritize in-app with an idempotent job record |
| D20 | Who owns and administers Supabase, R2, stores, signing keys and backups, and what are recovery objectives? | Release and restore cannot be safely completed without access policy | production setup | owner-controlled accounts and rehearsed recovery |
| D21 | What is the required approach to admin support access into a shop? | Platform staff must not inherit access to customer/ledger data | admin RLS | no implicit access; approved time-limited audited access |
| D22 | What constitutes acceptance of interactive onboarding without recording a fake financial transaction? | Guided real controls must not create misleading ledger data | onboarding | use safe practice/draft mode until a real submission |
| D23 | What is the invoice numbering/legal content policy per shop and business day? | Affects immutable snapshots and returns | invoice generation | server-assigned unique sequence; approved Arabic template |
| D24 | Are shop-level custom payment methods permitted to share a balance or be renamed after transactions? | Historical reports can change meaning if methods are deleted/renamed | cash accounts | immutable account ID, archived method and historical label snapshot |
| D25 | **Revised and accepted 2026-09-26:** Egypt-only; email/password or Egyptian phone/password on one Supabase Auth account; no email verification, OTP, or SMS confirmation. Owner signup requires owner name, business name, email, phone, governorate, and password. | Changes Auth, registration, profiles and invitation identity binding | Milestone 1 identity revision | [ADR 0002](adr/0002-egypt-password-auth.md); owner slice implemented in development, with [evidence and acceptance limits](operations/milestone-1-validation.md); recovery and staff invitation binding need separate design |
| D26 | Does the mockup's “gross profit” card represent net cash movement or true profit, and what valuation formula is approved? | Sales less purchases is not profit when gold moves | ledger UI and analytics | hide a profit claim until valuation is approved; if needed, label net cash movement accurately in Arabic |
| D27 | **Accepted working baseline 2026-09-24:** the three local Word files are the agreed initial requirements. Hosted annex comparison remains unverified. | A later annex version may affect the contract record, while engineering can proceed from the approved local baseline | contract record when available; not a development gate | compare a named annex revision privately if supplied; record any resulting scope change through the decision register and matrix |
| D28 | **Accepted 2026-09-24:** one subscription covers one shop account and its invited staff. | Entitlement is attached to a shop; membership and roles separately control each person's access | subscription schema and redemption | redeem a code for one shop; invited staff share its term but receive only their granted permissions; multiple shops require separate entitlements |
| D29 | **Accepted development arrangement 2026-09-24:** project xchapwvmvoefriqcxtvn is the current ElDafttar development database. The owner intends a clean data start on the same project before launch. | There are no separate development, staging or production projects yet; deletion and launch controls remain unresolved under D14, D15 and D20 | production cutover | keep migrations and test evidence, use only synthetic data during development, and approve a scoped reset and restore plan before any wipe |

## Decision record template

Create docs/adr/NNNN-short-title.md with:
- Status: proposed, accepted, superseded, or rejected.
- Date and owners.
- Context, source requirement IDs, and a concrete shop example.
- Options considered and consequences for money, grams, UX, security and migration.
- Decision and why.
- Schema/API impact, old-client compatibility and rollback/compensation.
- Acceptance tests and UI evidence.
- Links to the implementation and any superseding decision.

## First decision workshop

D01 and the local-source baseline in D27 are accepted. Prioritize D02 through D12, D23 through D26, and the agreed opening-balance example before building the first financial migration. A later annex comparison is a contract-record task and does not block the agreed working scope. Bring sample paper-ledger entries for one normal sale, a split-tender sale, a financed purchase with partial scrap recognition, a trader receipt recognized later, a repair handover, a partial debt settlement, and a day closed after midnight. Write expected cash by method, grams by karat, count, ownership/custody and liabilities after each example. Approve a specific three-party financier case. The team should not infer these values from screen mockups alone.

Resolve D14, D15 and D20 before production data or subscriptions are enabled; D13 is accepted. Retention, deletion and account ownership require stakeholder and legal review. The engineering documents can specify a safe implementation pattern but cannot settle commercial or legal meaning on their own.

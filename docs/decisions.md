# Architecture and product decisions

## How to use this register

These questions are deliberately open. They affect stored meaning, permissions or customer-facing behavior and should be answered by the product owner and a shop-domain expert before dependent implementation. Record the final answer as an ADR in docs/adr/, link the acceptance example and migration impact, then change this table to decided. A suggested direction below is an engineering proposal, not a product promise.

| ID | Decision required | Why it matters | Needed before | Suggested direction |
| --- | --- | --- | --- | --- |
| D01 | Which deployed functions and historical data must be preserved, and how are opening balances established? | PAGES is additive; a starter schema may not import existing stock, cash or invoices | scope freeze, first financial migration | inventory deployed app, approve keep/replace/migrate/drop matrix and reconciled opening entries |
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
| D13 | What happens to login, read/export and financial writes after subscription expiry? | Entitlements and retention are different policies | subscription RLS | define grace/read-only/restore behavior explicitly |
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
| D25 | Is the primary sign-in identifier phone, email, or both, and how are invitations verified? | Changes Auth, profile, recovery and admin subscriber identity | identity schema | approve verified identifier and recovery flow before memberships |
| D26 | Does the mockup's “gross profit” card represent net cash movement or true profit, and what valuation formula is approved? | Sales less purchases is not profit when gold moves | ledger UI and analytics | hide a profit claim until valuation is approved; if needed, label net cash movement accurately in Arabic |
| D27 | Does the externally hosted agreement annex match the local Word requirements? | A later annex version could change scope without appearing in this repository | scope sign-off | compare approved annex version privately and record differences without committing source files |

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

Prioritize D01 through D12, D23 through D26, and the agreed opening-balance example before building the first financial migration. D27 must be resolved before scope sign-off. Bring sample paper-ledger entries for one normal sale, a split-tender sale, a financed purchase with partial scrap recognition, a trader receipt recognized later, a repair handover, a partial debt settlement, and a day closed after midnight. Write expected cash by method, grams by karat, count, ownership/custody and liabilities after each example. Approve a specific three-party financier case. The team should not infer these values from screen mockups alone.

Resolve D13 through D15 and D20 before production data or subscriptions are enabled. Retention, deletion and account ownership require stakeholder and legal review. The engineering documents can specify a safe implementation pattern but cannot settle commercial or legal meaning on their own.

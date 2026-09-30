# Requirements tracking matrix

## Use

This matrix is the long-lived work register derived from the local source documents. Source codes are defined in product-scope.md. Status starts as planned because the repository is a starter; do not promote an item to verified without a link to implementation, policy tests and acceptance evidence. Milestone numbers refer to delivery-plan.md and may change after estimation. Record a decision ID where product behavior remains open. The product owner confirmed a greenfield launch and the three local Word files as the initial baseline; track later additions through decisions and this matrix.

| ID | Requirement | Source | Target milestone | Status / decision |
| --- | --- | --- | --- | --- |
| ID-01 | Authenticate before shop data using email/password or Egyptian phone/password, with no verification or OTP | PAGES, AGREEMENT; owner 2026-09-26 | 1 | Implemented, not accepted. Live two-identifier login, registration, session/revocation, and final device acceptance remain open. [Current assessment](operations/auth-ledger-assessment-2026-09-28.md), [historical evidence](operations/milestone-1-validation.md) |
| ID-02 | One owner account per shop; no partner, employee, invitation, or per-user permission grant | PAGES; owner 2026-09-26 | 1 | [ADR 0003](adr/0003-owner-only-shop-access.md). Migration `20260926120634_owner_only_access.sql` is applied to development and rollback-only tests pass. Flutter accepts only `member_role = owner`. See [validation](operations/milestone-1-validation.md) |
| ID-03 | Enforce tenant and row scope through RLS and command authorization | BASIC, PAGES | 1 | Identity and opening RLS/command tests passed on development and rolled back. Staging, live Auth, and device acceptance remain pending. [Evidence](operations/milestone-2-opening-validation.md) |
| ID-04 | Interactive skippable onboarding over real controls, resumable from Help | PAGES | 1, 4 | Partial: Flutter sign-in, owner signup, and opening-ledger guides use real field focus/refresh, persist step and allow skip/Help resume. Shop selection, first sale, inventory, CRM and a full Help entry remain open, D22. [Current evidence](reviews/onboarding-entry-2026-09-28/validation.md) |
| ONB-01 | Guided path through first sale, ledger, inventory, and CRM controls | PAGES; ADR 0003 | 1, 4 | Partial: auth and opening-ledger entry only. First-sale, inventory and CRM screens are not implemented, so their guided steps remain open, D22. [Evidence](reviews/onboarding-entry-2026-09-28/validation.md) |
| ONB-02 | First-operation guide must distinguish a safe practice draft from a real posting | PAGES | 1, 2 | Partial: opening-ledger guide says input is not saved before review and confirmation. Safe first-sale practice and real-posting distinction remain open with sale workflow, D22. [Evidence](reviews/onboarding-entry-2026-09-28/validation.md) |
| SET-01 | Owner signup: owner name, business name, email, required Egyptian phone, governorate, and password; default Africa/Cairo | PAGES; owner 2026-09-26 | 1 | Integrated signup and protected reservation/completion implemented; canonical unique contacts, 27 server governorates, Africa/Cairo, no entitlement/trial, and retry reconciliation tested. Forward migration applied only to development. [Evidence and acceptance limits](operations/milestone-1-validation.md); D13 preserved |
| SET-02 | Rename/archive payment methods while preserving historical identity | PAGES | 1, 2 | Planned, D24 |
| SET-03 | Invoice logo, slogan, address, color and template choices | LEDGER mockups, PAGES | 4 | Planned, D12 |
| SET-04 | Custom invoice/WhatsApp message text with validated placeholders | PAGES | 4 | Planned |
| NAV-01 | Home, ledger, customers, reports and more navigation in Arabic RTL | LEDGER mockups | 1 | Planned |
| ID-05 | Arabic RTL and complete light/dark themes on all clients | PAGES | 1 | Prior auth/opening evidence remains historical. New guided auth/ledger widget captures cover 320 and 1440 light/dark; guided auth also has Android emulator light/dark preview captures. Native splash light launch frame captured on Android; dark launch and iOS remain unverified. Live baselines and D12 remain open. [Current evidence](reviews/onboarding-entry-2026-09-28/validation.md), [opening evidence](operations/milestone-2-opening-validation.md) |
| LED-01 | Daily ledger by explicit business day and manual close | LEDGER, PAGES | 2 | Close/next-day commands and Flutter screens prepared under [ADR 0005](adr/0005-bounded-sale-and-close-rules.md). Connected-project rollback SQL gates passed on 2026-09-29; discrepancy correction and device acceptance remain open. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| LED-02 | Cash summary overall and by cash, card, instant transfer and wallet | LEDGER, PAGES | 2 | Version-two read model adds daily sale, purchase, expense totals and counts beside confirmed four-method cash balances; connected-project SQL gate passed. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| LED-03 | Sale/purchase grams and count by applicable karat, configurable card order/visibility | LEDGER | 2 | Version-two read model and Flutter view show sale and purchase milligrams, grams and piece counts by category and karat, plus exact selected-karat totals across categories. Daily movement/cash/gold/activity sections and individual sale/purchase/expense/gold cards can be shown, hidden and reordered per shop on this device. Connected-project SQL and 320/1440 RTL widget gates passed. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| LED-04 | Operation list with actor, time, invoice, and notes marker for the owning shop | LEDGER, PAGES; ADR 0003 | 2 | Version-two feed and detail view show confirmed operations, actor, time, sequence, items, tenders, note text and a note marker in the feed. Arabic PDF operation copies use the confirmed operation sequence; the owner-confirmed WhatsApp send queue is active. Connected-project SQL gate passed; legal invoice content remains open under D23. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| LED-05 | Daily text/image notes and quick actions | LEDGER, PAGES | 2, 4 | Planned |
| LED-06 | Define mockup profit/card formula; hide profit until approved valuation or label net cash movement accurately | LEDGER mockups | 2 | Partial. No profit claim is shown. Opening review and confirmed ledger now say «إجمالي النقد» for a cash balance, not movement. Valuation remains D26. [Assessment](operations/auth-ledger-assessment-2026-09-28.md) |
| CAT-01 | Category-specific allowed karats and stock tracking mode, including 14/22 where applicable | LEDGER, PAGES | 2 | Partial opening catalog under [ADR 0004](adr/0004-opening-balance-working-defaults.md): worked jewelry 14/18/21/22, bullion 24, coin 21, scrap 14/18/21/22/24. Initial sale/purchase aggregate bucket tracking approved in [ADR 0005](adr/0005-bounded-sale-and-close-rules.md); piece/lot detail and D04 remain open. [Evidence](operations/milestone-2-opening-validation.md) |
| QA-01 | Deduct scrap and add cash, including split cash methods, as one atomic quick action | LEDGER | 3 | Owner-only «بيع كسر وإضافة نقد» supports 14/18/21/22/24K, exact three-decimal gram deduction, split cash methods, net-effect review, protected idempotent retry and one audited server command. Connected-project rollback SQL gate covers balances, replay, invalid category and overdraft. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| EXP-01 | Owner records an expense using one or more cash methods | LEDGER, PAGES; ADR 0003 | 2 | Exact split-tender command and Arabic form prepared under [ADR 0005](adr/0005-bounded-sale-and-close-rules.md); connected-project SQL gate passed. |
| SALE-01 | Sale with multiple items, quantity, grams, category and karat | LEDGER, PAGES | 2 | Bounded sale command and mobile form prepared under [ADR 0005](adr/0005-bounded-sale-and-close-rules.md); connected-project SQL gate passed, aggregate bucket inventory remains a limit. |
| SALE-02 | Per-line or whole-invoice pricing and split tender | LEDGER, PAGES | 2 | Exact composer and server validation prepared under [ADR 0005](adr/0005-bounded-sale-and-close-rules.md). Connected-project SQL gate passed; tax/workmanship/discount/credit remain D02. |
| SALE-03 | Optional customer/phone and notes, net-effect confirmation | LEDGER | 2 | Local form and review prepared; photo notes remain open |
| SALE-04 | One atomic, idempotent server commit with clear outcome | BASIC, LEDGER | 2 | SQL command, protected client retry envelope and rollback-only connected-project SQL gate passed; live network fault tests remain open. |
| PUR-01 | Purchase with multiple items and split tender | LEDGER, PAGES | 2 | Shop-owned full and partial cash purchase command and form prepared under [ADR 0005](adr/0005-bounded-sale-and-close-rules.md) and [ADR 0007](adr/0007-purchase-ownership-and-custody.md); connected-project SQL gate passed. |
| PUR-02 | Partial/no cash payment and partial/no scrap or stock recognition | LEDGER, PAGES | 2, 3 | Shop-owned partial/zero cash purchase records one exact EGP payable; owner reviews price, payment and gold effect. Cash settlement posts without a second stock movement. Connected-project SQL gate passed; custody and gold-denominated obligations remain open under [ADR 0007](adr/0007-purchase-ownership-and-custody.md). |
| PUR-03 | Bullion at 24K and coins at 21K by category policy | LEDGER | 3 | Planned, D04 |
| PUR-04 | Split bullion/coin receipt between inventory and scrap | LEDGER | 3 | Planned, D04 |
| INV-01 | Instant inventory by product, count, grams, karat and scrap | PAGES | 3 | Planned, D03 |
| INV-02 | Bullion denominations and coin types with configurable catalog | LEDGER, PAGES | 3 | Planned, D04 |
| INV-03 | Authorized inventory edit/removal through audited correction | PAGES | 3 | Planned |
| INV-04 | Return, scrap deduction, scrap-to-stock and cash transfer quick actions | LEDGER | 2, 3 | Owner-only cash transfer, scrap-to-cash, same-karat scrap-to-stock, and full linked sale/purchase returns are deployed with exact balances, protected idempotent retry, reviewed effects and operation details. Purchase return reverses linked cash settlements and cancels the remaining payable. The connected-project rollback SQL gate passed with unchanged real-data counts. Partial returns, exchanges and discounts remain D17 scope. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| INV-05 | Trader gold shown separately with original and current total weight | PAGES | 3 | Planned |
| TRD-01 | Trader account cash/gold balances, search, settlement and PDF | PAGES | 3 | Planned, D07 |
| TRD-02 | Trader goods can be added to stock now or later; show pending count | PAGES | 3 | Planned, D06 |
| TRD-03 | Manual stock addition can be linked without a duplicate movement | PAGES | 3 | Planned, D06 |
| TRD-04 | Trader settlement can deduct scrap, cash and authorized inventory as selected | PAGES | 3 | Planned, D07 |
| REP-01 | Repair intake, status, delivery and confirmation prompts | PAGES | 4 | Planned |
| REP-02 | Optional fee collection and cash effect at delivery | PAGES | 4 | Planned |
| REP-03 | Intake/delete confirmation and editable fee at delivery with audit | PAGES | 4 | Planned |
| DEBT-01 | Amount/weight owed to or by shop and partial settlement | PAGES | 4 | Planned, D07 |
| DEBT-02 | Due reminders and debt PDF | PAGES | 4 | Planned, D19 |
| CRM-01 | Customer name, multiple phones, search, sorting and deletion policy | PAGES | 4 | Planned |
| CRM-02 | Per-karat bought/sold weight statistics, transaction counts and last activity | PAGES | 4 | Planned |
| CRM-03 | Notes, latest-note preview, open request and VIP/contact status | PAGES | 4 | Planned |
| CRM-04 | Owner call and WhatsApp contact actions scoped to the shop | PAGES; ADR 0003 | 4 | Planned |
| CRM-05 | Track whether customer number is saved on WhatsApp | PAGES | 4 | Planned |
| CRM-06 | Direct call control with phone permission and accessibility label | PAGES | 4 | Planned |
| DOC-01 | Confirmed immutable invoice snapshot and Arabic customizable PDF | LEDGER, PAGES | 4 | Arabic PDF customer copy is generated from the immutable confirmed operation payload and uses the confirmed operation sequence as its current identifier. Visual fixture reviewed; legal/tax fields and template customization remain open under D23 and SET-03/04. |
| DOC-02 | Owner pending-send queue for confirmed invoices | LEDGER, PAGES; ADR 0003 | 4 | Owner-scoped pending-send RPC and paginated Arabic queue prepared; records leave after owner confirmation. Connected-project SQL gate passed. [ADR 0006](adr/0006-owner-confirmed-whatsapp-dispatch.md) |
| DOC-03 | Honest dispatch status, actor and timestamp | LEDGER | 4 | Owner-confirmation RPC, append-only audit and client state prepared under [ADR 0006](adr/0006-owner-confirmed-whatsapp-dispatch.md); connected-project SQL gate passed. |
| DOC-04 | Render PDF or image and allow print, receipt and share after confirmation | LEDGER mockups | 4 | Local Arabic PDF generation and system share action prepared; rendered A4 fixture reviewed. Print and image export remain open. |
| RPT-01 | Daily/weekly books and PDF exports by selected period | PAGES | 5 | Planned, D18 |
| RPT-02 | Sales/purchases grams and money by period | PAGES; ADR 0003 | 5 | Planned, D18 |
| RPT-03 | Notes and expenses associated with a selected historical business day | PAGES | 5 | Planned, D08 |
| RPT-04 | Weekly PDF grouped by product category and karat | PAGES | 5 | Planned, D18 |
| HELP-01 | Searchable FAQ with categories/media, updated by admin | PAGES | 4, 5 | Planned |
| HELP-02 | In-app support contact or inquiry when Help has no answer | PAGES | 4, 5 | Planned |
| ADM-01 | Separate admin dashboard with subscriber directory and statistics | PAGES | 5 | Starter only |
| ADM-02 | Subscription codes for fixed/custom terms and redemption | PAGES | 5 | Planned |
| ADM-03 | Expiry, three-day renewal reminder and other notices | PAGES | 5 | Planned, D19 |
| ADM-04 | Minimum app version/forced update policy | PAGES | 5 | Planned |
| ADM-05 | Dynamic Help content management and user announcements | PAGES | 5 | Planned |
| ADM-06 | Broadcast message workflow for subscribers | PAGES | 5 | Planned, D19 |
| ADM-07 | Subscriber city/country and phone with platform-specific PII permission | PAGES | 5 | Planned |
| ADM-08 | Redeem a subscription code once for one shop and its single owner account | PAGES; owner 2026-09-26 | 5 | D28 revised by [ADR 0003](adr/0003-owner-only-shop-access.md); implementation planned |
| NTF-01 | Ongoing shop-status notices for cash, sales, purchases and scrap/sale weights | BASIC, PAGES | 5 | Planned, D19 |
| RET-01 | Four-month post-expiry data retention and warning 30 days before deletion | PAGES | 5 | Planned, D13, D14 |
| RET-02 | Renewal restores retained shop data | PAGES | 5 | Planned, D13 |
| RET-03 | Requested reset and account deletion with approved scope | PAGES | 5 | Planned, D15 |
| AUD-01 | Actor/time audit for changes, deletion requests and deductions | PAGES, AGREEMENT | 1 onward | Identity audit remains deployed. Opening writes one append-only `opening_balances_confirmed` event with the owner and server UTC time; rollback tests leave zero financial audit rows. Deletion and other financial audit stay pending. [Evidence](operations/milestone-2-opening-validation.md) |
| SYS-01 | Pending/success/failure feedback and safe retry/reconciliation | BASIC, PAGES | 1 onward | Registration and opening evidence remains in [Milestones 1](operations/milestone-1-validation.md) and [2](operations/milestone-2-opening-validation.md). Sale, purchase, expense, close, reopen, and cash-settlement flows use disabled in-flight controls, protected persisted idempotency keys, status reconciliation and confirmed refresh. Connected-project SQL gate passed; live network fault and device restart exercises remain open. [Review](reviews/daily-ledger-financial-2026-09-28/validation.md) |
| SYS-02 | Reconciled shop status notification and due reminders | BASIC, PAGES | 4, 5 | Planned |
| SYS-03 | Flutter Android, iOS and Windows, independent React admin | PAGES, AGREEMENT | 6 | Starters present |
| SYS-04 | Owner-controlled cloud/store accounts and source delivery | PAGES, AGREEMENT | 0, 6 | Planned, D20 |
| SYS-05 | Greenfield launch and optional verified opening balances for each new shop | PAGES; owner clarification | 0 onward | D01 scope stands. Active owner can confirm an explicit zero or the entered opening once; development SQL and Flutter tests passed with the limits in the note. Not full acceptance. [Evidence](operations/milestone-2-opening-validation.md) |
| SYS-06 | Weak-network fault tests: timeout after commit, duplicate tap, reconnect and gap catch-up | BASIC, AGREEMENT | 1 onward | Signup coverage stays in [Milestone 1](operations/milestone-1-validation.md). Opening flow, HTTP, and widget tests cover duplicate submissions, response timeout, durable pending restart, and status lookup after a dropped success. A real two-session race was not run. Reconnect and gap catch-up stay planned. [Evidence](operations/milestone-2-opening-validation.md) |
| SYS-07 | Flutter Clean Architecture enforced as feature implementation grows | PAGES, AGREEMENT | 1 onward | Auth/registration remains separated. The daily-ledger domain does not import Flutter, Supabase, or storage; the use case, HTTP adapter, and Arabic presentation are separate. [Evidence](operations/milestone-2-opening-validation.md) |
| DEBT-03 | Alarm-style due reminder behavior and retryable delivery | PAGES | 4 | Planned, D19 |

## Promotion rule

For each row, add a linked issue/PR or commit, server policy and command tests where relevant, UI evidence and product acceptance. “Implemented” means code exists; “verified” means the full acceptance path passed. If a requirement is deferred, keep it visible with a reason, owner and target release. Never remove it merely because a screen was redesigned.

# Requirements tracking matrix

## Use

This matrix is the long-lived work register derived from the local source documents. Source codes are defined in product-scope.md. Status starts as planned because the repository is a starter; do not promote an item to verified without a link to implementation, policy tests and acceptance evidence. Milestone numbers refer to delivery-plan.md and may change after estimation. Record a decision ID where product behavior remains open. The product owner confirmed a greenfield launch and the three local Word files as the initial baseline; track later additions through decisions and this matrix.

| ID | Requirement | Source | Target milestone | Status / decision |
| --- | --- | --- | --- | --- |
| ID-01 | Authenticate before any shop data | PAGES, AGREEMENT | 1 | Verified-email gate and shop selection wired in Flutter; widget session-expiry test passes; live session test pending |
| ID-02 | Shop membership and independent owner, partner, employee permissions | PAGES | 1 | SQL/RPC deployed and command tests passed on dev; staff UI pending, D10 |
| ID-03 | Enforce tenant and row scope through RLS and command authorization | BASIC, PAGES | 1 | Dev RLS and command tests passed; staging and client acceptance pending |
| ID-04 | Interactive skippable onboarding over real controls, resumable from Help | PAGES | 1, 4 | Planned, D22 |
| ONB-01 | Guided path through first sale, ledger, inventory, CRM and staff controls | PAGES | 1, 4 | Planned, D22 |
| ONB-02 | First-operation guide must distinguish a safe practice draft from a real posting | PAGES | 1, 2 | Planned, D22 |
| SET-01 | Shop name, phone, owner display name and time zone | PAGES | 1 | Flutter Arabic setup/selector implemented and widget-tested (pending, active, expired, failure, retry); server-status RPC applied and rollback-tested on development; live Flutter acceptance pending |
| SET-02 | Rename/archive payment methods while preserving historical identity | PAGES | 1, 2 | Planned, D24 |
| SET-03 | Invoice logo, slogan, address, color and template choices | LEDGER mockups, PAGES | 4 | Planned, D12 |
| SET-04 | Custom invoice/WhatsApp message text with validated placeholders | PAGES | 4 | Planned |
| NAV-01 | Home, ledger, customers, reports and more navigation in Arabic RTL | LEDGER mockups | 1 | Planned |
| ID-05 | Arabic RTL and complete light/dark themes on all clients | PAGES | 1 | Arabic sign-in and shop setup/selector reviewed at 320/1440 px in light/dark widget captures; live platform visual baselines and prototype approval pending, D12 |
| LED-01 | Daily ledger by explicit business day and manual close | LEDGER, PAGES | 2 | Planned, D08 |
| LED-02 | Cash summary overall and by cash, card, instant transfer and wallet | LEDGER, PAGES | 2 | Planned, D24 |
| LED-03 | Sale/purchase grams and count by applicable karat, configurable card order/visibility | LEDGER | 2 | Planned |
| LED-04 | Operation list with actor, time, invoice, notes marker and employee scope | LEDGER, PAGES | 2 | Planned, D10 |
| LED-05 | Daily text/image notes and quick actions | LEDGER, PAGES | 2, 4 | Planned |
| LED-06 | Define mockup profit/card formula; hide profit until approved valuation or label net cash movement accurately | LEDGER mockups | 2 | Planned, D26 |
| CAT-01 | Category-specific allowed karats and stock tracking mode, including 14/22 where applicable | LEDGER, PAGES | 2 | Planned, D03, D04 |
| QA-01 | Deduct scrap and add cash, including split cash methods, as one atomic quick action | LEDGER | 3 | Planned |
| EXP-01 | Expense using one or more cash methods with independent permission | LEDGER, PAGES | 2 | Planned |
| SALE-01 | Sale with multiple items, quantity, grams, category and karat | LEDGER, PAGES | 2 | Planned, D02 |
| SALE-02 | Per-line or whole-invoice pricing and split tender | LEDGER, PAGES | 2 | Planned, D02 |
| SALE-03 | Optional customer/phone and notes, net-effect confirmation | LEDGER | 2 | Planned |
| SALE-04 | One atomic, idempotent server commit with clear outcome | BASIC, LEDGER | 2 | Planned |
| PUR-01 | Purchase with multiple items and split tender | LEDGER, PAGES | 2 | Planned |
| PUR-02 | Partial/no cash payment and partial/no scrap or stock recognition | LEDGER, PAGES | 2, 3 | Planned, D05, D16 |
| PUR-03 | Bullion at 24K and coins at 21K by category policy | LEDGER | 3 | Planned, D04 |
| PUR-04 | Split bullion/coin receipt between inventory and scrap | LEDGER | 3 | Planned, D04 |
| INV-01 | Instant inventory by product, count, grams, karat and scrap | PAGES | 3 | Planned, D03 |
| INV-02 | Bullion denominations and coin types with configurable catalog | LEDGER, PAGES | 3 | Planned, D04 |
| INV-03 | Authorized inventory edit/removal through audited correction | PAGES | 3 | Planned |
| INV-04 | Return, scrap deduction, scrap-to-stock and cash transfer quick actions | LEDGER | 2, 3 | Planned, D09 |
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
| CRM-04 | Call and WhatsApp contact actions under data access permission | PAGES | 4 | Planned |
| CRM-05 | Track whether customer number is saved on WhatsApp | PAGES | 4 | Planned |
| CRM-06 | Direct call control with phone permission and accessibility label | PAGES | 4 | Planned |
| DOC-01 | Confirmed immutable invoice snapshot and Arabic customizable PDF | LEDGER, PAGES | 4 | Planned, D23 |
| DOC-02 | Pending-send queue and separate dispatch permission | LEDGER, PAGES | 4 | Planned, D11 |
| DOC-03 | Honest dispatch status, actor and timestamp | LEDGER | 4 | Planned, D11 |
| DOC-04 | Render PDF or image and allow print, receipt and share after confirmation | LEDGER mockups | 4 | Planned |
| RPT-01 | Daily/weekly books and PDF exports by selected period | PAGES | 5 | Planned, D18 |
| RPT-02 | Sales/purchases grams and money by employee and period | PAGES | 5 | Planned, D18 |
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
| ADM-08 | Redeem a subscription code once for one shop; invited staff share its entitlement subject to their permissions | PAGES; owner clarification | 5 | Scope confirmed, D28; implementation planned |
| NTF-01 | Ongoing shop-status notices for cash, sales, purchases and scrap/sale weights | BASIC, PAGES | 5 | Planned, D19 |
| RET-01 | Four-month post-expiry data retention and warning 30 days before deletion | PAGES | 5 | Planned, D13, D14 |
| RET-02 | Renewal restores retained shop data | PAGES | 5 | Planned, D13 |
| RET-03 | Requested reset and account deletion with approved scope | PAGES | 5 | Planned, D15 |
| AUD-01 | Actor/time audit for changes, deletion requests and deductions | PAGES, AGREEMENT | 1 onward | Identity audit deployed; financial and deletion audit pending |
| SYS-01 | Pending/success/failure feedback and safe retry/reconciliation | BASIC, PAGES | 2 onward | Planned |
| SYS-02 | Reconciled shop status notification and due reminders | BASIC, PAGES | 4, 5 | Planned |
| SYS-03 | Flutter Android, iOS and Windows, independent React admin | PAGES, AGREEMENT | 6 | Starters present |
| SYS-04 | Owner-controlled cloud/store accounts and source delivery | PAGES, AGREEMENT | 0, 6 | Planned, D20 |
| SYS-05 | Greenfield launch and optional verified opening balances for each new shop | PAGES; owner clarification | 0 onward | Scope confirmed, D01; workflow planned |
| SYS-06 | Weak-network fault tests: timeout after commit, duplicate tap, reconnect and gap catch-up | BASIC, AGREEMENT | 2 onward | Planned |
| SYS-07 | Flutter Clean Architecture enforced as feature implementation grows | PAGES, AGREEMENT | 1 onward | Planned |
| DEBT-03 | Alarm-style due reminder behavior and retryable delivery | PAGES | 4 | Planned, D19 |

## Promotion rule

For each row, add a linked issue/PR or commit, server policy and command tests where relevant, UI evidence and product acceptance. “Implemented” means code exists; “verified” means the full acceptance path passed. If a requirement is deferred, keep it visible with a reason, owner and target release. Never remove it merely because a screen was redesigned.

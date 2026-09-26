# Product scope and acceptance map

## Accepted Egypt registration policy — 2026-09-26

The product owner revised D25 in [ADR 0002](adr/0002-egypt-password-auth.md). The product is Egypt-only. Login accepts email and password or Egyptian phone and password on the same account, without email verification, OTP, or SMS confirmation. Owner signup requires owner name, business name, email, phone, Egyptian governorate, and password. The default shop time zone is `Africa/Cairo`.

Normalize Egyptian phone identifiers consistently and validate governorates against an Egyptian list. Passwords belong only to Supabase Auth. Contact identifiers are not proof of ownership and must not confer membership. New shops remain pending activation without a trial; expired shops retain owner read/export access and reject writes. Password recovery needs a separate design.

## Accepted owner-only access — 2026-09-26

The product owner removed staff invitations and permissions in [ADR 0003](adr/0003-owner-only-shop-access.md). One Supabase Auth user owns and operates one shop. There is no partner, employee, invitation, or per-user permission grant. Revocation suspends that owner account. Platform administrators remain a separate identity and do not inherit shop data.

This accepted scope change is implemented by the bounded owner-registration/password slice. See [Milestone 1 validation](operations/milestone-1-validation.md) for development evidence and remaining acceptance gaps; it does not mark the full milestone complete.

## Purpose and source key

This is the scope inventory for ElDafttar ERP. It is not a claim that any workflow already works. The three root Word files are abbreviated here as BASIC (core problems and goals), LEDGER (daily ledger detail and embedded UI concepts), and PAGES (page-by-page requirements). AGREEMENT means the technical scope in the root PDF, excluding its private and commercial details. If wording differs, preserve the original files for the product owner to decide; record the decision in decisions.md. The three local Word files are the agreed initial working requirements for this greenfield, multi-customer subscription service. The product owner confirmed there is no deployed legacy application to inventory or migrate. The agreement links to an external annex that has not been retrieved here; D27 tracks a private comparison for the contract record without blocking work from the agreed local files. Future additions or changes are recorded in decisions.md and the requirements matrix.

## Product outcomes

The system must let a gold shop replace its paper ledger without losing trust in cash or grams. A sale, purchase, stock move, debt settlement, or day close either commits all related effects or none. Every mutation shows pending, success, or a specific failure. Repeated taps and uncertain network responses must never duplicate financial effects. The daily ledger is the primary path and must be fast enough for a seller during an active transaction. Gold weight, karat, and item count must remain visible beside money.

Arabic copy and RTL layout apply to both clients. Light and dark themes are complete. Shop data requires authentication by the shop's single owner account. A shop must not see another shop's data. Server enforcement, audit history, and reconciliation are part of each feature, not later polish.

## Component inventory

| Area | Required behavior | Minimum acceptance evidence | Source |
| --- | --- | --- | --- |
| Identity and shop setup | Auth, shop creation, one owner membership, shop profile, payment methods, time zone, theme preference, and owner-account suspension | Cross-shop access denied by RLS; a revoked owner cannot read or mutate; a second owner or a second shop for the same account is rejected; settings persist | PAGES, AGREEMENT; ADR 0003 |
| Interactive onboarding and help | Guided interaction with actual controls, skip and resume; searchable FAQ and media; help managed from admin | User can finish or skip, resume from Help, and follow a real control without accidental financial submission | PAGES, AGREEMENT |
| Daily ledger | Selected business day, configurable summary cards/order, sales/purchases, cash by method, grams by karat, actor/time/notes, quick actions, manual close | Owner totals reconcile with postings; the owner sees that shop's ledger; close after midnight works against shop business day | LEDGER, PAGES, AGREEMENT; ADR 0003 |
| Sale | Multiple line items, category, quantity, weight to 0.001 g, applicable karat, per-line or invoice total, multiple tenders, optional customer and notes, confirmation of net effects | One server transaction creates document, postings, stock/cash effects, invoice state, audit event; retry returns same result | LEDGER, PAGES |
| Purchase | Multiple lines and tender methods; bullion and coins with fixed karat rules; optional partial/no cash movement and partial/no scrap recognition; customer and notes | Unpaid or externally financed amount and unallocated gold are explicit balances/states; no silent missing cash or stock | LEDGER, PAGES |
| Stock and instant inventory | Products, lots/items, count and weight, all supported karats, scrap, bullion denominations, coin types, adjustments and search | Every balance has source movements; count and grams reconcile; correction is authorized and audited | PAGES, AGREEMENT |
| Trader accounts | Trader search, gold and cash obligations, receipts/settlements, goods recognition now or later, unrecognized count, trader PDF | Recognition cannot duplicate an existing manual stock entry; obligations and stock remain separate until linked | PAGES, AGREEMENT |
| Repairs | Intake, status, return to customer, amount confirmation and optional collection, notes/images | Custody inventory and cash effects are explicit; delivery cannot happen twice | PAGES, AGREEMENT |
| Debts and reminders | Amount or weight owed to/by shop, partial settlement, due dates, reminders, PDF | Balance and due state reconcile; settlement asks whether stock/cash effects apply and records the choice | PAGES, AGREEMENT |
| CRM | Multiple phone numbers, contact search/sort, notes, special/open requests, VIP marker, weight summaries per karat, contact links | Access respects permission; summaries derive from confirmed transactions; sensitive phone exposure is limited | LEDGER, PAGES |
| Invoice and dispatch | Arabic PDF, shop template and message, pending-send queue, owner dispatch, WhatsApp handoff or provider flow, dispatch history | PDF generated from immutable confirmed document; pending/sent/failed states and actor/time are recorded honestly | LEDGER, PAGES; ADR 0003 |
| Employees and permissions | Removed on 2026-09-26. One owner account operates the shop. No partner, employee, invitation, or per-user grant | The database rejects non-owner memberships and removed staff RPCs; cross-shop and revoked access stay denied | PAGES, AGREEMENT; [ADR 0003](adr/0003-owner-only-shop-access.md) |
| Analytics and books | Period filters, gold weight and money metrics, daily/weekly reports, PDFs | Reports reconcile to confirmed postings and stay inside the owning shop | PAGES, AGREEMENT; ADR 0003 |
| Notifications | Shop status, operation outcomes, debt due dates, subscription expiry, update notices | Delivery channels and failures are visible; no notification substitutes for authoritative ledger state | BASIC, PAGES |
| Admin dashboard | Subscriber directory and counts, location, contact, subscription codes/durations, announcements, help content, operational metrics, forced update control | Platform admin authorization is independent of shop membership; all admin changes are audited | PAGES, AGREEMENT |
| Subscription and retention | One subscription covers one shop and its single owner account; codes for month, six months, year, or custom term; alerts including three-day reminder; four-month post-expiry retention with warning 30 days before deletion | Access state transitions are deterministic; restoration within retention works; deletion has approved legal/backup policy | PAGES, AGREEMENT; ADR 0003 |
| Reset and account deletion | Requested reset, account/data deletion, historical integrity and retention handling | Destructive scope is previewed and approved; financial/audit/legal constraints resolved before enabling controls | PAGES |
| Cross-platform delivery | Flutter Android, iOS, Windows and React admin; owner-controlled store and cloud accounts | Each target passes build, accessibility, RTL/theme and critical-flow checks before release | PAGES, AGREEMENT |

## Daily ledger detail

The ledger opens to the current open business day rather than a device-calendar day. A mockup includes a card labelled gross profit; sales less purchases is not profit while gold, workmanship and valuation are unresolved. Hide that claim until D26 approves a true formula, or label a separately defined net cash movement in Arabic. Owners can navigate past days. Summaries include total and per-method cash, sale and purchase totals, item counts, and grams grouped by karat. Users can choose which cards appear and their order without changing underlying totals. Sales and purchases show invoice/document number, actor, server time displayed in shop time zone, cash amount, weight, karat, tender method, and note indicator.

The fast sale path follows the embedded mockups: choose category and item, enter count/weight/karat, add another item as needed, add one or more tender methods, add optional customer and notes, then review the net cash and stock effects before submit. Defaults reduce taps but remain editable. The purchase path handles multiple items, scrap, bullion and coin routing, mixed payments, external financing, and deferred stock/scrap recognition. A confirmation view must show who actually paid the customer, who owns and holds each gram, any financing obligation, and any deferred or unallocated gold. A financier who takes the gold cannot be treated as though the shop gained saleable stock.

Quick actions include cash method transfer, scrap deduction, scrap-to-stock conversion, return, expense, and daily note. Each action has its own server command and permission. A return links the original transaction where available and reverses exact effects before any replacement entries. Notes may have text and private images. Day close requires owner or delegated permission, displays expected versus counted cash and gold, captures discrepancy reason, and seals the day with an auditable correction path. Closing after local midnight still closes the selected open business day.

## Inventory and unit rules

Supported karats are 14, 18, 21, 22, and 24 where a product category permits. The source examples default worked jewelry to 18 or 21, bullion to 24, and coins to 21; validate category rules in data and server commands rather than relying on UI defaults. Grams have three decimal places. Count is an integer. A product can be tracked by individual piece, lot, or aggregate class based on the approved inventory policy. Scrap is separate from saleable stock. The system must never convert grams across karats by simply adding raw weights; if fine-gold equivalents are needed, define and display their formula and rounding rule.

Purchase of bullion/coins can split quantity or weight between inventory and scrap. Trader goods can remain received-but-unrecognized, with a clear queue. Manual recognition must link to the trader receipt rather than merely toggling a flag. Transfers and adjustments record both sides of the movement and the approving actor.

## UX and communication acceptance

The embedded reference images show Arabic RTL light and dark ledger screens, compact summary cards, a step-by-step sale flow, success feedback, quick actions, invoice branding, PDF/image preview, printing, sharing and WhatsApp handoff. Treat them as design inputs pending product approval, not as proof of implemented behavior. Build a shared visual token specification and capture approved target screens before asking for pixel-level comparison. Test small mobile screens, larger phones, Windows desktop, and responsive admin widths. Screen-reader labels and validation messages remain Arabic.

Every mutation has a distinct draft, submitting, uncertain/pending reconciliation, confirmed, and failed state. A timeout does not mean failure. If the server committed but the reply was lost, retry with the same idempotency key and fetch the original result. Invoice dispatch is a separate action after financial confirmation. Opening WhatsApp cannot by itself prove the message was sent or delivered; define whether the product records user confirmation or uses a provider receipt.

## Scope boundaries and open product decisions

Do not infer detailed behavior from page titles. Decisions.md records required choices for: new-shop opening balances; exact cash and gold accounting conventions; sale pricing/tax/workmanship; negative stock and partial payments; purchase financing and unallocated goods; trader and manual-stock linking; return policy; business-day close and reopen; WhatsApp evidence; subscription expiry access; data reset/deletion; and retention. These decisions are prerequisites for the associated irreversible migrations or financial commands.

The contract's four delivery stages are useful as a baseline sequence: interactive design, ledger/database/inventory/trader core, remaining modules and dashboard, then integrated testing and release. The delivery plan expands that into verifiable engineering milestones and ongoing operation. It does not treat a calendar estimate as proof that all scope has been accepted or shipped.

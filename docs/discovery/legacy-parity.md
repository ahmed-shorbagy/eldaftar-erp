# Legacy parity inventory

This is the Milestone 0 inventory of source scope against the Git starter. It is an input to D01. The owner disposition column is unfilled. Deployed legacy status is **UNVERIFIED** on every row.

Three layers stay separate:

| Layer | What it is in this packet |
| --- | --- |
| Source scope | Behavior described by BASIC, LEDGER, PAGES, and the agreement body, as reconciled in [source reconciliation](source-reconciliation.md) |
| This Git repository | Files under `app/`, `admin/`, and `supabase/` inspected for this packet |
| Deployed legacy application | The live or previously shipped ElDafttar product that PAGES says already has features. It was not opened, exported, or demonstrated |

Drawings inside LEDGER and PAGES are design illustrations. They are not screenshots of the deployed application and they are not screenshots of this repository.

## Repository observation

Inspected source, not generated build output:

| Location | Present in Git | Absent from Git |
| --- | --- | --- |
| `app/` | Flutter app named `eldafttar`. Platforms created: Android, iOS, Windows. Arabic locale, RTL Material shell, light and dark themes, theme choice stored on device, public Supabase client created only when both public defines are present. Tests for theme, public config, startup, and the shell widget | Feature modules, sign-in, onboarding, ledger, inventory, CRM, permissions, PDF, any financial command. No macOS or Linux runner. Web is not a configured platform |
| `admin/` | Vite React TypeScript shell, Arabic RTL, Material UI, light and dark themes, theme choice stored in the browser, public Supabase client under the same both-values rule. Component and config tests | Sign-in, subscriber directory, codes, help editor, announcements, any shop data screen |
| `supabase/` | `verify-connections.mjs` and package scripts for an Auth health request and a bucket existence check | `migrations/`, RLS policies, SQL functions, Edge Functions, seed data, storage policies |

`app/lib/src/` contains `app.dart`, config, shell, and theme. It has no `features/` tree. The root [README](../../README.md) and [docs index](../README.md) describe the same starter boundary. This packet did not re-run analyze, test, or build, and it did not run the connection script.

Ignored local configuration files were not opened. Their presence or absence is not product evidence.

In [the matrix](../requirements-matrix.md), ID-05 and ADM-01 are “starter only”, SYS-03 is “starters present”, and SYS-05 is “unknown” under D01. Those four statuses match this inspection. Every other matrix row is still planned.

## How to use the inventory

- **Source scope** compresses the local documents. Where they disagree, the row says so and points at [source reconciliation](source-reconciliation.md).
- **In this Git repo** describes the starter only.
- **Deployed legacy** is UNVERIFIED until a named person demonstrates or exports that surface.
- **Owner disposition** accepts only: keep, replace, migrate, or retire. Engineering does not fill it.

Requirement IDs point at [the matrix](../requirements-matrix.md). Decision IDs point at [decisions](../decisions.md).

## Screen and feature inventory

| ID | Surface | Source scope, compressed | In this Git repo | Deployed legacy | Owner disposition (keep / replace / migrate / retire) |
| --- | --- | --- | --- | --- | --- |
| P-01 | Sign-in and session | Shop data is authenticated. Identifier (phone, email, or both) and invitation check are unspecified. Matrix ID-01, D25 | No sign-in screen and no session flow. Public client setup only | UNVERIFIED | |
| P-02 | Shop profile and settings | Shop name, phone, owner display name, time zone. Rename or remove payment-method labels, including use outside Egyptian rails. Invoice logo, slogan, address, color, template. Custom message text with placeholders. Matrix SET-01–SET-04, D12, D24 | Absent | UNVERIFIED | |
| P-03 | Interactive onboarding | Guided use of real controls: welcome, first sale, ledger, instant inventory, customers, add employee or partner. Skip anywhere. Resume from Help. A practice path must stay clear of a real posting. Matrix ID-04, ONB-01, ONB-02, D22 | Absent. Shell copy says onboarding is not available | UNVERIFIED | |
| P-04 | Daily ledger home | Opens on the shop’s open business day. Cards for sales, purchases, total cash, and cash by method (cash, card, instant transfer, wallet). Grams and counts by applicable karat. Card visibility and order are user choices and do not change totals. Operation list shows document, actor, time, amounts, weight, karat, tender, note marker. Employee sees own operations. Matrix LED-01–LED-04, NAV-01, D08, D10 | Absent. Shell has no navigation and no ledger | UNVERIFIED | |
| P-05 | Sale | Multi-line sale. Category, integer count defaulting to 1, weight, karat. Worked-jewelry narrative defaults to 18 with 21 as the other usual choice; bullion narrative defaults to 24; coin narrative defaults to 21. Per-line price or one invoice total. Several tenders. Optional customer name and phone. Optional notes. Review, then one commit. Matrix SALE-01–SALE-04, D02, D03 | Absent | UNVERIFIED | |
| P-06 | Purchase | Same multi-line and mixed-tender path as sale. Shop may pay by cash, wallet, or instant transfer. Optional partial or zero cash movement. Optional partial or zero scrap/stock recognition. Matrix PUR-01, PUR-02, D05, D16 | Absent | UNVERIFIED | |
| P-07 | Three-party financed purchase | LEDGER describes a financier who supplies money in exchange for gold when the shop cannot pay the customer. PAGES states the partial cash and partial scrap controls and does not name the financier. Agreement body does not restate the financier. Payer, owner, custodian, and obligations are open. Matrix PUR-02, D05. Paper alternatives: [worked examples](financial-worked-examples.md) case 3 | Absent | UNVERIFIED | |
| P-08 | Bullion and coin purchase routing | Bullion karat fixed at 24 in the narrative; coins at 21. Count and weight fields. Route all or part into denomination stock, or into 24K scrap (bullion) or 21K scrap (coins). Usual bullion pieces listed as 0.25, 0.5, 1, 2.5, 5, 10, 20, 31.1, 50, and 100 grams, plus shop-added pieces. Usual coins: quarter, half, and full, plus shop-added pieces. Nominal piece versus weighed grams is open. Matrix PUR-03, PUR-04, INV-02, D04 | Absent | UNVERIFIED | |
| P-09 | Ledger quick actions | Each action is its own operation: deduct scrap; deduct scrap and add cash, including a split across methods; move cash between methods; move scrap into a stock item (item, count, karat, weight); return (item, count, karat, weight, cash out of one or more methods); expense from one or more methods, with its own permission. Matrix QA-01, EXP-01, INV-04, D09, D17 | Absent | UNVERIFIED | |
| P-10 | Daily notes and private images | Text, images, or both, by a user allowed onto the ledger, available again during the day. Matrix LED-05 | Absent. No upload endpoint in the repository | UNVERIFIED | |
| P-11 | Manual day close | Owner closes, or delegates the close. Expected versus counted item counts and cash, then the next day opens a new ledger. Close can happen after midnight and still belongs to the open shop day. Discrepancy handling, reopen, and posts after the seal are open. Matrix LED-01, D08, D09, D10. Paper illustration: [worked examples](financial-worked-examples.md) case 5 | Absent | UNVERIFIED | |
| P-12 | Instant inventory | Products with count and weight for karats 14, 18, 21, 22, and 24 where the category allows. Scrap, including 14 and 22 when present. Bullion section by piece weight and count. Coin section by type, weight, and count. Delete an item through an authorized correction. Cash position visible beside inventory. Matrix INV-01, INV-03, CAT-01, D03 | Absent | UNVERIFIED | |
| P-13 | Trader weight on inventory | Trader gold shown apart from shop stock, with original total weight and current total weight. Matrix INV-05, D07 | Absent | UNVERIFIED | |
| P-14 | Trader accounts | Search by trader name. Record goods on the trader account without forcing an immediate stock add. Status per weight: not yet in stock, or in stock. Later add opens the stock screen. If the user already typed the stock by hand, a control updates that receipt’s status without typing the weight again. Count of weights still not in stock. Settlement can deduct scrap, stock, and cash as chosen. PDF per trader. Karats 14 and 22 when present. Matrix TRD-01–TRD-04, D06, D07. Paper illustration: [worked examples](financial-worked-examples.md) case 4 | Absent | UNVERIFIED | |
| P-15 | Repairs | Dialog on intake and on delete. Delivered versus not delivered. After handover, ask whether to add the stated amount to cash and whether to change that amount. Matrix REP-01–REP-03. Whether intake is custody rather than saleable stock is an engineering reading in [database design](../database-design.md), not a sentence in PAGES | Absent | UNVERIFIED | |
| P-16 | Notebook and debts | Money or weight owed to the shop, and money or weight the shop owes. Partial settlement. On settlement, ask whether stock or cash should move, and record the choice. Due reminders with alarm-style behavior. PDF of an account. Matrix DEBT-01–DEBT-03, D07, D19 | Absent | UNVERIFIED | |
| P-17 | Customers | Name, several phones, edit and delete, search, sort by name or last operation. Per-karat weight bought and weight sold to the shop, sale count, purchase count, last operation. Notes with history and a latest-note preview. Open request. VIP marker. Call and WhatsApp actions. Manual marker for whether the number is saved in WhatsApp. Matrix CRM-01–CRM-06, D10 | Absent | UNVERIFIED | |
| P-18 | Employees and permissions | Owner, partner, employee. Independent grants for sale, purchase, inventory, expense, day close, reports, invoice dispatch, and further actions named at implementation. Partner may be full or limited. Users without dispatch permission create invoices that wait in a pending-send list. Matrix ID-02, DOC-02, D10 | Absent | UNVERIFIED | |
| P-19 | Invoice, print, and WhatsApp handoff | After a confirmed sale or purchase, a user with dispatch permission can send. Others’ invoices wait for an authorized sender. Record sent versus not sent, sender, and time. PDF and image, print, and share. Shop-specific template and message. Matrix DOC-01–DOC-04, SET-03, SET-04, D11, D12, D23 | Absent | UNVERIFIED | |
| P-20 | Analytics | PAGES says the existing analytics page has errors and must be rebuilt. Add employee results (who sold and bought, by weight) and shop weight results for week, month, and year. PDF. The defect list is not in the source file. Matrix RPT-02, D18, D01 | Absent | UNVERIFIED | |
| P-21 | Books and period PDFs | PDF for a chosen period covering what happened. Weekly PDF of sales count and weight by category, and purchases by karat. Notes and expenses can be added to a selected past day. Matrix RPT-01, RPT-03, RPT-04, D08, D18 | Absent | UNVERIFIED | |
| P-22 | Help and in-app support | Searchable help by topic, with images or short video. Topics cover sale, purchase, employees, close, inventory, WhatsApp invoices, customers, and subscriptions. Admin can change articles without an app release. If search fails, the user can contact support inside the app. Matrix HELP-01, HELP-02, ADM-05 | Absent | UNVERIFIED | |
| P-23 | Audit history | A tamper-resistant record of each edit, delete, and deduction, with actor and time. Matrix AUD-01. How this survives subscription deletion and “reset” is open (D14, D15) | Absent | UNVERIFIED | |
| P-24 | Shop-status notices and operation results | Ongoing notice of cash, sales, purchases, and scrap or sale weights. A clear success or failure after each operation, including when the network is weak. Due reminders. Matrix NTF-01, SYS-01, SYS-02, DEBT-03, D19. Channels are unspecified | Absent | UNVERIFIED | |
| P-25 | Subscription, retention, and reset | Codes for a month, six months, a year, or a custom term, bound to one user. Notice before expiry, a three-day renewal reminder in PAGES, and a notice at expiry. Forced update when a release requires it. After expiry, keep data four months, warn 30 days before deletion, allow renewal to restore, then delete. Settings and the books page both offer a reset that clears figures and data. Access during the four months, legal hold, and reset scope are open. Matrix ADM-02–ADM-04, ADM-08, RET-01–RET-03, D13–D15 | Absent | UNVERIFIED | |
| P-26 | Platform admin | Separate dashboard: subscriber directory and counts, phones, city and country, subscription state, send messages, codes, notices, help content, forced-update policy. Admin authority is separate from shop membership. Matrix ADM-01, ADM-05–ADM-07, D21 | Admin starter shell only. Copy states that admin screens are not available | UNVERIFIED | |
| P-27 | Android, iOS, and desktop clients | Flutter clients for Android, iOS, and desktop. Clean Architecture as features grow. Store listings and cloud projects belong to the owner. Source is delivered to the owner. Matrix SYS-03, SYS-04, SYS-07, D20. Agreement says desktop; this repo’s desktop target is Windows | Android, iOS, and Windows project shells exist. No macOS desktop target. No store listing in the repo. iOS signing was not exercised here | UNVERIFIED | |
| P-28 | Weak-network integrity | An operation commits fully or not at all. The user can tell success from failure. Repeating a tap must not post twice. A sale or purchase that saves must still move cash and inventory. Deleting a duplicate must not corrupt totals. Matrix SYS-01, SYS-06, SALE-04. Agreement stage 2 includes this reliability with the ledger, inventory, and trader core | Absent | UNVERIFIED | |
| P-29 | Arabic RTL, light and dark | Both clients. Matrix ID-05. Drawings show both themes and are not an approved visual baseline (D12) | Present on the starter shells: Arabic RTL, light theme, dark theme, persisted choice. No ERP screens to theme | UNVERIFIED | |

## Drawings found in the Word files

These drawings were viewed for inventory. They were not copied into Git. Sample personal names, phone numbers, and a street address drawn on them are omitted here.

| Drawing | Where it appears | Surfaces it illustrates | Status |
| --- | --- | --- | --- |
| Light ledger home, sale steps, quick-action sheet, color and type notes | LEDGER | Ledger cards, sale wizard, payment lines, success state, quick actions, bottom navigation | Unapproved design input (D12) |
| Dark ledger home with a profit card and separate sale and purchase lists | LEDGER, also embedded in PAGES | Ledger summary, operation rows, navigation | Unapproved. Profit card conflicts with D26. Totals do not reconcile; see [source reconciliation](source-reconciliation.md) |
| Dark ledger home and the same sale wizard, plus a component sheet | LEDGER, also embedded in PAGES | Ledger, sale, quick actions | Unapproved. Gram cards on this drawing do not match its headline weights |
| Invoice and WhatsApp sequence, template editor, PDF and image preview | LEDGER, also embedded in PAGES | Post-sale confirmation, dispatch, shop invoice identity | Unapproved. Dispatch evidence remains D11. Numbering on the drawing is not a D23 rule |
| Customer list and customer detail | PAGES only | CRM search, per-karat totals, notes, requests, VIP, call and WhatsApp | Unapproved. Drawing shows 18, 21, and 24. PAGES also asks for 14 and 22, and for weight sold to the shop |

No drawing in these files shows inventory, trader accounts, repairs, the notebook, analytics, books, help, employees, settings, audit, subscription, or the admin dashboard. Absence of a drawing is not absence of a requirement.

Navigation is not stable across drawings: one bar is home, customers, ledger, reports, more; another is home, inventory, customers, reports, more. D12 includes choosing one information architecture.

## Evidence and data-export questions

Answers are part of D01. None were available in the repository.

1. What is the deployed product’s current version, and which store or sideload channel ships it?
2. Which of P-01–P-29 already exist in that build, and which exist only on paper?
3. PAGES says analytics is wrong. What is the visible defect, and which numbers disagree?
4. Can the owner produce a read-only export as of one moment: cash by method, saleable grams and counts by category and karat, scrap by karat, bullion and coin counts, trader gold and cash by direction, unrecognized receipts, customer debts, repair items still in custody, open business day, and last invoice number?
5. What file or screen produces that export, and who will run it?
6. Are historical documents required in the new ledger, or only opening balances plus a frozen archive?
7. How many shops are in the deployed data, and can one user belong to more than one shop?
8. Which payment-method names are actually in use, including any renamed methods?
9. What time zone does the shop close in, and how often does close happen after midnight?
10. Do financier purchases, trader receipts, repairs, and notebook debts exist in the deployed data today?
11. Is there already a user, role, and permission list to migrate?
12. Are photos already stored for notes, repairs, or invoices, and who can retrieve them?
13. What subscription state, expiry, and code history must move?
14. Which sample contacts on the drawings, if any, were copied from real customers? Real customer data stays out of Git either way.

## Opening-balance migration inputs

No opening figures are known. The value column stays blank until an export or a signed count exists. Units below match the proposed convention in [database design](../database-design.md): money in integer minor units, gold in integer milligrams, counts as integers, karats kept separate. That convention is still D02 and D03, not an accepted ADR.

When figures arrive, the import is a dedicated opening operation. Silent edits of balances are outside this design. Each source total has to equal the opening posting and the signed count for that same unit.

| Input | Unit | Blank value | Check once a value exists |
| --- | --- | --- | --- |
| As-of timestamp and shop time zone | shop-local instant | | One labeled moment for every row below |
| Currency and minor-unit exponent | ISO code and exponent | | One currency unless D02 allows more |
| Cash, per method, method id stable even if the label changes | minor units | | Sum of methods equals declared total cash |
| Saleable stock, per category, product or lot, karat, tracking mode | mg and integer count | | Count posted only where the tracking mode requires it |
| Shop-owned scrap, per karat | mg | | Kept apart from saleable stock |
| Bullion, per denomination and per actual weighed lot | integer piece count and mg | | Nominal label and weighed mg both kept (D04) |
| Coins, per type | integer count and mg | | Same split between label and weighed mg |
| Trader obligations, per trader, direction, karat or currency | mg by karat, or minor units | | Units stay unconverted (D07) |
| Unrecognized trader receipts | mg, count, karat, receipt identity | | Excluded from saleable stock until a later link (D06, D16) |
| Customer debts, direction | minor units and/or mg by karat | | Same unit rule as trader obligations |
| Repair goods still in custody | count, mg, karat, repair identity | | Excluded from saleable stock |
| Gold a financier already took | mg, karat, who holds it | | Excluded from shop-owned saleable stock and shop-owned scrap |
| Gold the shop holds for someone else | mg, karat, owner, custodian | | Custody quantity, not shop-owned stock |
| Open business day id and last closed day | day identity | | Close after midnight uses this id (D08) |
| Invoice sequence high-water mark | shop sequence | | New numbers continue under the rule from D23 |
| Existing user list and grants | membership records | | Re-checked against D10 before any grant is copied |
| Subscription expiry and retention clock | timestamps | | Informational until D13 and D14 are accepted |

Gold transferred directly to a financier is not an opening quantity of shop-owned inventory. Unrecognized trader goods are not saleable stock. Repair custody is not saleable stock. Raw milligrams of different karats are not added into one opening gram total.

## What would change a row from UNVERIFIED

A row leaves UNVERIFIED only when a named reviewer records the build they used, the date, and what they saw: the screen exists, it is missing, or it behaves differently from the source sentence. A drawing, a requirement paragraph, or this starter does not supply that record.

# Source reconciliation

The product owner confirmed that the three local Word files are the agreed initial working requirements for a greenfield build. The hosted agreement annex was not compared with them. D27 tracks a private comparison of any supplied named revision for the contract record; it does not block engineering from the agreed local baseline. Future scope changes use the decision register and requirements matrix.

## Method

| Label | Meaning in this file |
| --- | --- |
| Source fact | A behavior stated in BASIC, LEDGER, PAGES, or the agreement body |
| Match | The agreement body and the local Word set describe the same behavior at the level each one actually writes |
| Local addition | The Word files contain behavior the agreement body does not restate. The unread annex might still contain it. This is not a finding that the contract excludes it |
| Agreement specificity | The agreement body is more specific than the Word files |
| Conflict | Two statements assign different outcomes to the same situation |
| Ambiguous | The texts name a feature and leave the accounting or permission outcome open |
| Proposal | A rule in [product scope](../product-scope.md), [database design](../database-design.md), or [decisions](../decisions.md). A proposal is not a signed requirement |

Commercial terms, party names, contact details, identifiers, and the annex address are omitted. One page of the local PDF has no technical text. The page after it is the annex pointer (a title, a link, and a machine-readable code).

## Agreement body, technical scope

The body commits the build to the annex and also lists the following, described there as included.

**Mobile (Android and iOS) and desktop**

- Daily ledger: more than one item on an invoice; cash shown in total and by cash, card, instant transfer, and wallet; customer and note capture; karats 14, 18, 21, 22, and 24; mixed payment; manual day close.
- Instant inventory: those karats, scrap, bullion weights and counts, coins, trader weight, delete and edit.
- Trader accounts: settlement that can deduct scrap and cash; goods may enter inventory immediately or later; a visible indicator when they have not been added.
- Repairs: a dialog on intake or delete; on delivery, ask about adding or deducting cash.
- Notebook and alerts: debts in either direction, date reminders with an alarm-style behavior, PDF.
- Customers: full record, bought and sold weight by karat, notes, open requests, privacy, call and WhatsApp.
- Employees and permissions: owner, partner, employee; independent permission switches; a pending-invoice list for WhatsApp.
- Analytics: weights and sales by week, month, and year; per-employee sales and weights; PDF.
- Books: daily and weekly PDF; invoice appearance and WhatsApp message can be customized.
- Help: an interactive guide, in-context screens, and search.
- Audit: a reliable log of each delete, edit, or deduction, with the user and the time.

**Admin dashboard**

- Subscriber management, phone numbers, and subscription codes for different durations.
- Automatic notices before renewal, and a link to required updates.
- Keep data for four months after the subscription ends, then delete it.
- Help content edited from the dashboard without shipping a new app binary.

**Accounts and stages**

- Database and object-storage projects are created for the client, who is the direct owner. Store listings use the client’s own store accounts.
- Four stages over twelve work weeks: interactive prototype of the screens (two weeks); database plus ledger, inventory, and trader accounts, including accounting that stays reliable on a weak network (four weeks); remaining modules and dashboard, delivered as a test build (four weeks); integrated test, notes, and store release (two weeks).
- The preamble also requires a Flutter Clean Architecture implementation. The Word file PAGES states the same engineering constraint.

[The delivery plan](../delivery-plan.md) keeps those four stages as stakeholder tracking and expands them into Milestones 0–7. It already says a stage is not complete because its week ended. That reading matches this packet. The 2/4/4/2 split is the agreement body’s week outline; the delivery plan does not restate those week counts.

## Trace from the agreement body

| Agreement body item | BASIC | LEDGER | PAGES | Matrix | Relationship |
| --- | --- | --- | --- | --- | --- |
| Multi-item invoices | Atomic sale and purchase | Worked multi-item sale and purchase | Multi-item invoices | SALE-01, PUR-01 | Match |
| Cash total and four methods | Shop-status cash | Cash, instant transfer, wallet, card | Same four, including on purchase | LED-02 | Match. Rename/delete of method labels is a PAGES addition (D24) |
| Customer and notes on the operation | Operation log and trust | Optional name, phone, notes | Same, plus CRM | SALE-03, CRM-01 | Match |
| Karats 14, 18, 21, 22, 24 | — | Defaults by category; 14 and 22 appear in the card list | Sell/buy 14 and 22 and store them on the product | CAT-01, LED-03 | Match at the list level. Category limits conflict in wording; see Conflicts |
| Mixed payment | — | Several tenders on sale and purchase | Mixed payment, including shop paying the customer by wallet or instant transfer | SALE-02, PUR-01 | Match |
| Manual day close, including after midnight | — | Owner or delegated employee; counts and cash | Manual close because work can pass midnight | LED-01, D08 | Match on the existence of manual close. Effect of the count and of a late post is ambiguous |
| Inventory, scrap, bullion, coins, edit/delete | Inventory linked to sale and purchase | Denomination list and stock-or-scrap routing | Inventory page, scrap for 14 and 22, delete item | INV-01–INV-04, D04 | Match at page level. Denomination list and split routing are local additions relative to the body |
| Trader weight, settlement, add now or later, missing-stock indicator | Trader accounts must be linked | — | Full status model, manual-add control, pending count, PDF, search | TRD-01–TRD-04, INV-05 | Match at the body level. The body names scrap and cash in settlement. PAGES also names inventory as something settlement can deduct. Manual-add wording conflicts with the safe reading in database design; see Conflicts |
| Repairs: dialog and cash question | Repairs must be linked | — | Dialog on intake or delete; delivery question; delivered flag | REP-01–REP-03 | Match on the dialog and a cash question at delivery. The body says add or deduct cash. PAGES says ask whether to add the amount, and whether to edit it. Custody versus saleable stock is not spelled out |
| Debts both ways, reminders, PDF | Notebook must be linked | — | Partial pay, stock/cash question, alarm-style reminder, PDF | DEBT-01–DEBT-03 | Match. Unit conversion is ambiguous |
| CRM record, weights, notes, requests, call, WhatsApp | — | Customer capture feeds CRM | Full CRM page, including 14 and 22 and VIP | CRM-01–CRM-06 | Match. Drawing coverage is narrower than PAGES |
| Roles and independent permissions; pending WhatsApp list | — | Dispatch permission and pending list | Same, plus the permission examples | ID-02, DOC-02 | Match. Employee “own operations only” is in PAGES and is not restated in the agreement ledger bullet |
| Analytics by period and by employee, PDF | — | — | Same, plus “fix the current analytics page” | RPT-02, D01, D18 | Match on the new reports. The described earlier defect has no deployed app to verify; treat the requested analytics behavior as greenfield scope |
| Daily and weekly books, invoice template, WhatsApp text | — | Template and message drawings | Books page and settings text | RPT-01, RPT-04, SET-03, SET-04 | Match |
| Help, search, in-context guide, admin-edited articles | Users should learn without a visit | — | Full help center and support fallback | HELP-01, HELP-02, ONB-01, D22 | Match. Onboarding detail is a PAGES addition |
| Audit of edit, delete, deduction with actor and time | A log of operations | Actor on the ledger row | Tamper-resistant audit page | AUD-01 | Match. Tension with deletion and reset; see Conflicts |
| Admin subscribers, phones, codes, renewal notices, forced update, four-month retention, dynamic help | Subscription loss is a stated harm | — | Same, plus city/country, message broadcast, three-day reminder, restore-on-renew, and a user reset | ADM-01–ADM-08, RET-01–RET-03 | Match on the body list. Three-day timing, city/country, broadcast, and reset are local additions relative to the body |
| Client-owned database, object storage, and store accounts | — | — | Owner store accounts and source delivery | SYS-04, D20 | Agreement specificity: the body names the database product and the object store. PAGES names store accounts and source delivery. Engineering docs already use both |
| Twelve-week, four-stage outline, with weak-network reliability inside the ledger stage | Atomicity, no partial effects, no duplicate taps | Fast sale path | Clean Architecture, platforms | SYS-06, SYS-07 | Match on intent. Week counts are agreement specificity. See stage tension below |
| Clean Architecture | — | — | Required | SYS-07 | Match between PAGES and the agreement preamble |

BASIC does not list screens. It requires the operation families to move together: sale, purchase, inventory, cash, stocktake, repairs, notebook, and trader accounts. That goal matches the agreement stage that demands reliable accounting on a weak network. BASIC does not contradict the screen list.

## Conflicts

### C1 — Profit card versus cash and gold movement

One ledger drawing shows total profit equal to sales minus purchases (45,000 − 30,000 = 15,000 on that drawing). Other ledger drawings on the same files show sales, purchases, and cash with no profit card. No Word paragraph and no agreement clause define profit, workmanship, or valuation.

[Product scope](../product-scope.md) and D26 say sales minus purchases is not profit while gold is moving and no valuation formula exists. [Database design](../database-design.md) says the same. The drawing and the engineering baseline disagree. The card’s meaning is unresolved. The worked examples publish no profit figure.

### C2 — Trader “added manually” versus a second stock posting

PAGES says that if the user already added the goods from the inventory page, they can mark the trader receipt as added manually and update the status only, without typing the data again. The desired visible result is one stock quantity.

[Database design](../database-design.md) says a status flag without a checked link can hide a duplicate, and that the link has to match shop, product, karat, weight, and count and then post no second movement. LEDGER does not describe this control. The agreement body requires add-now-or-later and does not mention the manual flag.

Both readings want a single stock increase. They disagree on whether a status update alone is enough. D06 is the decision. Case 4 in [the worked examples](financial-worked-examples.md) shows the single-increase arithmetic and leaves the rule unsigned.

### C3 — Worked-jewelry karats versus the five-karat list

LEDGER says worked items come only in 18 or 21, bullion is 24, and coins are 21. PAGES and the agreement body require 14 and 22 as stored karats on sales, purchases, and inventory. Those statements can live together if 14 and 22 belong to specific categories and worked jewelry stays on 18 and 21. They cannot live together if every worked item may be 14 or 22. No category matrix is written down. D03 and D04.

### C4 — Immutable audit versus erase and reset

The agreement body and PAGES require a log that survives edits, deletes, and deductions. PAGES also resets “all figures and all data” from settings and from the books page, and it deletes shop data after the retention window. The agreement body requires that final deletion and does not describe the user reset. An append-only audit and a full erase cannot both be absolute. D14 and D15. This packet does not choose a legal outcome.

### C5 — Employee scope versus drawings of a shared day

PAGES says an employee sees their own operations, not the whole ledger. The agreement permissions bullet does not repeat that sentence. Ledger drawings show a day that includes several sellers’ rows and shop-wide totals. D10 has to say whether those totals are an owner view, a granted view, or a contradiction. The starter has neither view.

### C6 — Stage-1 prototype versus a documented deferral

The agreement body asks for an interactive prototype of the screens in stage 1. [The delivery plan](../delivery-plan.md) allows the design gate to pass by an explicit D12 deferral. A deferral is a process exception to the body text. It needs an owner decision if it is used. D12 also covers whether any current drawing is a pixel target. Several required screens have no drawing at all; see [greenfield scope inventory](greenfield-scope-inventory.md).

## Local additions relative to the agreement body

These are in the Word files and are not restated in the agreement body. These remain in the agreed local working scope. A later annex comparison may lead to a documented change.

| Addition | Where | Why it matters |
| --- | --- | --- |
| Financier narrative: a third party pays and takes gold | LEDGER purchase story | Changes ownership, custody, and obligations. PAGES has the partial cash and partial scrap controls without this story. D05 |
| Partial or zero cash, and partial or zero scrap, as separate purchase options | LEDGER and PAGES | The body says mixed payment and manual close, and it says trader goods can wait. It does not spell out this purchase split |
| Quick actions: scrap deduction, scrap-to-cash, cash transfer, scrap-to-stock, return, expense | LEDGER | PAGES has expenses, returns context, and notes. The body does not list the quick-action set |
| Bullion denomination list and coin types, including shop-added types, and a split between stock and scrap | LEDGER | Body says weights, counts, bullion, and coins, without the list or the split |
| Per-line price or a single invoice total | LEDGER | Body does not choose the pricing layout. D02 |
| Onboarding step list and a skip control | PAGES | Body’s help clause is the interactive guide and search |
| Analytics defects in the current product | PAGES | Historical wording has no deployed product to verify. Build the specified new analytics and agree expected figures under D18. |
| City and country on the subscriber record, broadcast messages, three-day reminder | PAGES | Body says phones, notices before renewal, and required updates, without these details |
| User-facing reset of all data | PAGES settings and books | Separate from the four-month retention delete |
| “Fine weight” label, defined in parentheses as the raw gram total of one chosen karat | LEDGER | See ambiguities. No purity formula is given |
| Daily notes with images, and ledger notes with a marker | LEDGER and PAGES | Body mentions notes. Images and the marker are more specific in the Word files |
| Books: add notes or expenses onto a selected past day | PAGES | Interacts with a closed day. D08, D09 |

## Agreement-body items more specific than the Word files

| Body item | Word coverage |
| --- | --- |
| Named client-owned database product and object store | PAGES requires owner-controlled store accounts and source delivery. It does not name the database or the object store. Engineering docs already specify both and keep object-storage keys server-side |
| Week counts 2, 4, 4, and 2 inside twelve work weeks | Word files have no schedule. The delivery plan records four stages and twelve weeks without repeating the split |
| Weak-network accounting called out inside the ledger/inventory/trader stage | BASIC states the failure modes. PAGES does not repeat the duplicate-tap and partial-post cases |
| Desktop, without naming Windows | PAGES says desktop. The repository’s desktop project is Windows. macOS desktop is not specified and is not in the repo |

## Ambiguous behavior

| Topic | What is written | What is open | Decision |
| --- | --- | --- | --- |
| Currency and rounding | Drawings use pounds. PAGES allows payment labels for non-Egyptian rails | Minor units, extra currencies, tax, workmanship, discount, rounding | D02 |
| Price entry | LEDGER allows a price on each line or one total | How a single total lands on lines, and whether lines must sum before save | D02 |
| Count and negative stock | Count is an integer field and defaults to 1 in the sale story | Piece, lot, or aggregate; whether a save can drive stock below zero | D03 |
| Nominal versus weighed bullion | Both a denomination and a weight field exist | Which quantity posts | D04 |
| Financier economics | Someone can fund the shop and receive gold; cash and scrap recognition can be partial | Who pays, who owns, who holds, what the shop owes, whether the shop earns anything | D05, D07, D16 |
| Trader direction | Goods sit on the trader account until stock is updated | Whether the shop owes gold, owes money, or both, before settlement | D06, D07 |
| Debt conversion | Money or weight can be owed and partly settled | No conversion rate or rounding rule | D07 |
| Business day | Close is manual and may be after midnight | Time zone, one open day or many, reopen, stale posts, whether the count sheet replaces the books | D08 |
| Past-day notes and expenses | Books can add them to a selected day | Whether a closed day accepts new postings | D08, D09 |
| Returns | Quick action returns item, count, karat, weight, and cash | Link to the original sale, partial quantity, effect after close or after dispatch | D09, D17 |
| WhatsApp result | Record sent or not sent, actor, and time. CRM also has a manual “number saved” marker | Whether opening the chat is “sent”, and whether a provider receipt exists | D11 |
| Invoice identity | A drawing shows a year-like prefix and a sequence | The legal rule, reset each day or not, voided numbers | D23 |
| Payment-method rename | PAGES allows rename and delete | Historical rows must keep a stable account and a frozen label if D24 follows the engineering proposal | D24 |
| Sign-in id | Settings edit a shop phone and an owner display name | Login identifier and recovery | D25 |
| Repair goods | Intake dialog and a delivery cash question | Whether those goods are saleable, and what delete does to custody | REP, D16 |
| Subscription access | Four-month retention, then delete; renew restores | Whether the shop can read, export, or post during those four months | D13, D14 |
| Notification channel | In-app success/failure is required; ongoing shop status is required | Push, email, SMS, or WhatsApp for reminders | D19 |
| Support access | Admin sees subscriber contact data | Any path from platform admin into a shop ledger | D21 |
| Practice onboarding | The guide drives real controls | How the first guided sale avoids a live posting | D22 |
| “Fine weight” | Parenthetical text says it is the raw total for one selected karat | The trade sense of the word is a purity conversion. No factor or rounding is stated | D26, and the no-cross-karat rule in product scope |
| Desktop | Agreement and PAGES say desktop | Windows is the repo target. Other desktop operating systems are unnamed | SYS-03 |

The prose purchase illustration is also ambiguous as arithmetic. It states a price of 21 thousand and tenders of instant transfer 20, cash 500, and wallet 500. Read as 20 pounds, the tenders sum to 1,020, which is not 21,000. Read as 20 thousand, they sum to 21,000. This packet does not choose a reading and does not use those figures as a posting case.

The financier story states 100 grams and 600 thousand, with no karat, no split between shop cash and financier cash, and no custodian. It is a scenario, not a balanced example. Case 3 uses separate synthetic figures.

## Drawing arithmetic that is not a fixture

The drawings were inspected. They disagree. None of these identities is an approved posting.

Headline sale weight on the light and dark homes is 21.250 g. One light breakdown shows 4.500 + 12.000 + 4.500 = 21.000 g, short of the headline by 0.250 g. The matching purchase breakdown shows 2.500 + 8.000 + 2.500 = 13.000 g against a headline of 12.750 g.

A dark home shows sale rows 4.500 + 12.000 + 0.000 = 16.500 g against the same 21.250 g headline, and purchase rows 2.500 + 8.000 + 0.000 = 10.500 g against 12.750 g.

A success state shows 3.08 g, which equals 1.83 + 1.25. Another invoice drawing on the same files shows 1.83 g and 2.56 g, which sum to 4.39 g, both next to a 7,000 pound total. The LEDGER prose multi-item example is a third set: 2.56 g, 1.25 g, and 0.5 g.

The four cash-method tiles 70,000 + 30,000 + 15,000 + 10,000 do sum to the 125,000 total-cash tile. That single card is internally additive. It still does not explain opening cash, and it is not an opening balance.

Sales 45,000 minus purchases 30,000 equals the 15,000 profit tile on the one drawing that shows it. That is drawing arithmetic only. See conflict C1.

Direction cues also differ: one drawing marks purchases upward, another marks them downward. Bottom navigation differs across drawings, as listed in [greenfield scope inventory](greenfield-scope-inventory.md).

## Repository cross-check

The starter described in [greenfield scope inventory](greenfield-scope-inventory.md) implements none of the agreement screen list. Arabic RTL and both color themes exist on empty shells. The product owner confirmed there is no deployed product. The starter is not a passed delivery stage.

The matrix records the starter state and the confirmed greenfield launch, while individual workflows remain planned. This file does not change the matrix.

## Recommendations

Not decisions:

- Use the three agreed local Word files for the initial scope. If a named annex revision is supplied later, compare it privately and record any approved changes.
- Treat C1–C6 as workshop items, not as defects to “fix” in code before the owner chooses.
- Keep drawing numbers out of tests and out of opening balances.
- Use [the worked examples](financial-worked-examples.md) for the numeric decisions, and expect the shop expert to replace the synthetic figures.

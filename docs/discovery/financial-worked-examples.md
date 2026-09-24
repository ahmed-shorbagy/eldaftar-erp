# Financial worked examples

These five cases are synthetic discussion sheets for the Milestone 0 workshop. They are not confirmed requirements. Every approval row is blank. A blank row means the case is unsigned.

No SQL, table definition, or migration is specified here. Account names are paper labels so a reader can see both sides of a movement. [Database design](../database-design.md) uses the same style of label and says the names are illustrative.

## Labels

| Label | Meaning |
| --- | --- |
| Source fact | Stated in BASIC, LEDGER, PAGES, or the agreement body |
| Proposal | Stated in [product scope](../product-scope.md), [database design](../database-design.md), or [decisions](../decisions.md), and not accepted as an ADR |
| Assumption | A number or rule chosen only so this sheet has a closed arithmetic example |
| Unresolved | A decision the sheet needs and does not make |

Shared proposals used by every case, all still open:

- Money is an integer of minor units. For the illustrated currency, 1.00 currency unit is 100 minor units. Display uses two decimal places. This is the EGP convention in database design. D02 has not accepted the currency or the exponent.
- Gold is an integer of milligrams. 1.000 g is 1,000 mg. The screen shows three decimal places. Product scope states the three-decimal gram rule. The Word examples sometimes write fewer decimals (for example 0.5).
- A count is an integer.
- Karat stays on the line. Milligrams of different karats are never added to balance a journal and are never converted to fine gold in these sheets.
- A paper journal for one unit family sums to zero. Positive increases that paper account. Negative decreases it. Money, milligrams, and counts are separate families.
- Sales minus purchases is not profit. These sheets report net cash movement and leave profit undefined (D26).

Source facts used by the set, without turning them into the numbers below:

- A sale or purchase can contain several lines, several tenders, a weight, a karat, and a count.
- A purchase can move no cash, or only some cash, and can recognize no scrap, or only some scrap.
- A financier, in the LEDGER story, supplies money and can receive gold.
- Trader goods can be recorded first and recognized into stock later. A manual stock entry must not be typed a second time.
- The business day can be closed after midnight by the owner or a delegated person.
- One committed operation is the whole effect. A repeated tap is still one commit (BASIC). Each case below is that single commit. Dispatch, PDF, and WhatsApp are outside the money and gold result.

The prose amounts in LEDGER (a 21-thousand purchase whose “20” tender is ambiguous, and a 100 gram / 600 thousand financier story with no karat or custodian) are not reused. Drawing totals are not reused. Those problems are documented in [source reconciliation](source-reconciliation.md).

Omitted on purpose, and therefore still unresolved: bullion denomination versus weighed grams (D04), tax, workmanship, and discounts (D02), returns (D09, D17), repair custody, debt settlement, and any shop fee.

## Case 1 — Simple sale

Decisions exercised: D02, D03, D24, D26.

### Source facts

The sale path asks for category, count, weight, and karat, then one or more tenders. Worked jewelry in the narrative defaults to 18, with 21 available. Count defaults to 1. Customer and notes are optional. The commit is atomic.

### Assumptions

1. Currency is the single shop currency, displayed as pounds, stored as minor units with exponent 2.
2. The line is piece-tracked, so count posts. If D03 later says this category is weight-only, the count journal drops out and the milligram journal stays.
3. The ring is shop-owned and in shop custody before the sale, inside a saleable 18K bucket that has enough weight and count. Negative stock is not involved.
4. Price is 4,200.00 on this single line, all of it tendered as cash. No workmanship line and no tax line exist in the example.
5. No customer record is attached.

### Unresolved

Per-line versus invoice-total pricing, the real price, rounding, and whether 18 is allowed for this category after the karat matrix exists. Invoice number is not assigned here (D23).

### Before

| Paper account | Karat | Amount | Display |
| --- | --- | --- | --- |
| Cash method “cash” | — | 1,000,000 minor | 10,000.00 |
| Card, instant transfer, wallet | — | 0 | 0.00 |
| Saleable ring, weight | 18 | 5,000 mg | 5.000 g |
| Saleable ring, count | 18 | 3 | 3 |
| Shop-owned scrap | 18 | 0 mg | 0.000 g |
| Money obligations | — | 0 | 0.00 |
| Gold obligations | — | 0 mg | 0.000 g |

### Event

Sell 1 ring, 1,830 mg (1.830 g), karat 18, for 420,000 minor (4,200.00), tendered entirely in cash.

### Journals

Money:

| Paper account | Signed minor units |
| --- | --- |
| Cash | +420,000 |
| Sales-consideration clearing | −420,000 |
| Sum | 0 |

Gold, 18K only:

| Paper account | Signed mg |
| --- | --- |
| Saleable ring | −1,830 |
| Gold-sold clearing | +1,830 |
| Sum | 0 |

Count, under assumption 2:

| Paper account | Signed count |
| --- | --- |
| Saleable ring count | −1 |
| Count-sold clearing | +1 |
| Sum | 0 |

### After

| Paper account | Karat | Amount | Display |
| --- | --- | --- | --- |
| Cash | — | 1,420,000 minor | 14,200.00 |
| Other cash methods | — | 0 | 0.00 |
| Saleable ring, weight | 18 | 3,170 mg | 3.170 g |
| Saleable ring, count | 18 | 2 | 2 |
| Shop-owned scrap | 18 | 0 mg | 0.000 g |
| Obligations | — | 0 | — |

| Question | Before | After |
| --- | --- | --- |
| Ownership of this ring | Shop | Buyer. The shop no longer owns it |
| Custody of this ring | Shop | Buyer. The shop no longer holds it |
| Shop money obligation | None | None |
| Shop gold obligation | None | None |

Net cash movement is +420,000 minor. Profit is undefined. The shop gave up 1,830 mg of 18K and gained cash. Those are different units.

### Consistency

- 1,000,000 + 420,000 = 1,420,000
- 5,000 − 1,830 = 3,170
- 3 − 1 = 2
- +420,000 − 420,000 = 0
- −1,830 + 1,830 = 0
- −1 + 1 = 0
- 1,830 mg displays as 1.830 g; 3,170 mg displays as 3.170 g
- 420,000 minor displays as 4,200.00

### Approval

| Field | Entry |
| --- | --- |
| Shop-domain reviewer | |
| Product owner | |
| Date | |
| ADR | |
| Accepted as the shop’s rule | |

## Case 2 — Mixed-tender, multi-item sale

Decisions exercised: D02, D03, D24, D26.

### Source facts

One invoice can hold several items, each with count, weight, and karat. The seller may price each line or enter one invoice total. Tenders may be split across cash, card, wallet, and instant transfer. The total tender is computed from the parts.

### Assumptions

1. Same currency and piece-tracking assumptions as case 1.
2. This sheet uses a price on each line. The invoice-total alternative is not calculated, because D02 has not said how to spread one total across lines.
3. Lines are three different saleable buckets, each with enough quantity. No scrap moves.
4. Customer and notes are left empty.
5. Instant transfer exists as a method and is unused on this invoice, so its balance stays put.

### Unresolved

Whether line prices must equal the tender sum before the server accepts the command, and what happens if the seller’s total is short. This sheet assumes they are equal because the source says the total is calculated from the tenders and the lines.

### Before

| Paper account | Karat | Amount | Display |
| --- | --- | --- | --- |
| Cash | — | 1,750,000 minor | 17,500.00 |
| Card | — | 500,000 minor | 5,000.00 |
| Wallet | — | 300,000 minor | 3,000.00 |
| Instant transfer | — | 100,000 minor | 1,000.00 |
| Earrings weight / count | 21 | 10,000 mg / 4 | 10.000 g / 4 |
| Chain weight / count | 18 | 8,000 mg / 5 | 8.000 g / 5 |
| Pendant weight / count | 18 | 3,000 mg / 6 | 3.000 g / 6 |
| Scrap 18 and scrap 21 | — | 0 mg | 0.000 g |
| Obligations | — | 0 | — |

Shop money before any tender: 1,750,000 + 500,000 + 300,000 + 100,000 = 2,650,000 minor (26,500.00).

### Event

| Line | Count | Weight | Karat | Line price |
| --- | --- | --- | --- | --- |
| Earrings | 1 | 2,560 mg (2.560 g) | 21 | 640,000 minor (6,400.00) |
| Chain | 1 | 1,250 mg (1.250 g) | 18 | 250,000 minor (2,500.00) |
| Pendant | 1 | 500 mg (0.500 g) | 18 | 110,000 minor (1,100.00) |
| Invoice money | 3 | see below | mixed | 1,000,000 minor (10,000.00) |

Tenders: cash 400,000; card 350,000; wallet 250,000. Instant transfer 0.

Raw milligrams moved are 2,560 of 21K and 1,750 of 18K. Those two numbers stay in different gold journals. Their 4,310 mg raw-weight sum may be shown only as a clearly labelled mixed-karat display total if the product owner approves it; it is not a journal balance or a fine-gold equivalent.

### Journals

Money:

| Paper account | Signed minor units |
| --- | --- |
| Cash | +400,000 |
| Card | +350,000 |
| Wallet | +250,000 |
| Sales-consideration clearing | −1,000,000 |
| Sum | 0 |

Gold 21K:

| Paper account | Signed mg |
| --- | --- |
| Saleable earrings | −2,560 |
| Gold-sold clearing 21K | +2,560 |
| Sum | 0 |

Gold 18K:

| Paper account | Signed mg |
| --- | --- |
| Saleable chain | −1,250 |
| Saleable pendant | −500 |
| Gold-sold clearing 18K | +1,750 |
| Sum | 0 |

Three count journals, one per bucket: saleable count −1 and count-sold clearing +1. Each sums to 0. The piece count of the invoice is 3 because 1 + 1 + 1 = 3. That is a report total of three journals, not one count account mixing products.

### After

| Paper account | Karat | Amount | Display |
| --- | --- | --- | --- |
| Cash | — | 2,150,000 minor | 21,500.00 |
| Card | — | 850,000 minor | 8,500.00 |
| Wallet | — | 550,000 minor | 5,500.00 |
| Instant transfer | — | 100,000 minor | 1,000.00 |
| Earrings weight / count | 21 | 7,440 mg / 3 | 7.440 g / 3 |
| Chain weight / count | 18 | 6,750 mg / 4 | 6.750 g / 4 |
| Pendant weight / count | 18 | 2,500 mg / 5 | 2.500 g / 5 |
| Scrap | 18 and 21 | 0 mg | 0.000 g |
| Obligations | — | 0 | — |

Shop money after: 2,150,000 + 850,000 + 550,000 + 100,000 = 3,650,000 minor (36,500.00).

| Question | After |
| --- | --- |
| Ownership | All three pieces belong to the buyer |
| Custody | All three pieces have left the shop |
| Obligations | None |
| Net cash movement | +1,000,000 minor, spread across cash, card, and wallet |
| Profit | Undefined |

### Consistency

- 640,000 + 250,000 + 110,000 = 1,000,000
- 400,000 + 350,000 + 250,000 = 1,000,000
- 2,650,000 + 1,000,000 = 3,650,000
- 1,750,000 + 400,000 = 2,150,000; 500,000 + 350,000 = 850,000; 300,000 + 250,000 = 550,000
- 10,000 − 2,560 = 7,440; 8,000 − 1,250 = 6,750; 3,000 − 500 = 2,500
- −1,250 − 500 + 1,750 = 0
- 1,250 + 500 = 1,750
- Counts 4 − 1 = 3, 5 − 1 = 4, 6 − 1 = 5
- Displays: 2.560 g, 1.250 g, 0.500 g, 7.440 g, 6.750 g, 2.500 g

### Approval

| Field | Entry |
| --- | --- |
| Shop-domain reviewer | |
| Product owner | |
| Date | |
| ADR | |
| Accepted as the shop’s rule | |

## Case 3 — Three-party financed purchase

Decisions exercised: D02, D05, D07, D16, D26. D04 is not exercised: the parcel is scrap-shaped, not a bullion denomination.

Source facts: the shop can record a purchase that deducts no cash or only some cash, and that adds no scrap or only some scrap. LEDGER describes a financier who provides money in exchange for receiving gold. The confirmation has to be able to say who paid, who owns, and who holds the gold. No source sentence gives the split, the karat, or the custodian for that story.

Two illustrations follow. They are alternatives, not two steps of one purchase. 3A is the direct handoff. 3B is the shop-holds alternative. 3B2 is an extra partial-cash branch of 3B and is equally unsigned.

### Case 3A — Financier takes the gold

#### Assumptions

1. The customer offers 10,000 mg (10.000 g) of 21K scrap. Count is not tracked for this scrap line.
2. The agreed money is 800,000 minor (8,000.00). The financier pays the customer that entire amount outside the shop tills.
3. The financier receives the gold directly. The shop never takes custody.
4. The shop charges no fee in this illustration. A fee would be a separate decision and a separate journal.
5. Starting ownership and custody of the parcel are the customer’s.

#### Unresolved

Whether the shop must store a zero-effect document at all, whether any commission exists, and whether the customer/financier payment belongs in the shop ledger. D05.

#### Shop books, before and after

| Paper account | Before | Delta | After |
| --- | --- | --- | --- |
| Cash (all methods) | 5,000,000 minor (50,000.00) | 0 | 5,000,000 minor (50,000.00) |
| Saleable stock 21K | 20,000 mg (20.000 g), count 8 | 0 | 20,000 mg (20.000 g), count 8 |
| Shop-owned scrap 21K | 2,000 mg (2.000 g) | 0 | 2,000 mg (2.000 g) |
| Custody / unallocated 21K | 0 mg | 0 | 0 mg |
| Shop money obligations | 0 | 0 | 0 |
| Shop gold obligations | 0 mg | 0 | 0 mg |

Shop-owned inventory after the event is the same 20.000 g saleable and the same 2.000 g scrap. The 10.000 g is not added to either.

No shop money journal and no shop gold journal are posted. There is no clearing pair that would increase saleable stock, scrap, or cash.

| Question | Before | After |
| --- | --- | --- |
| Ownership of the 10.000 g | Customer | Financier |
| Custody of the 10.000 g | Customer | Financier |
| Shop holds it | No | No |
| Shop owns it | No | No |
| Who paid the customer | — | Financier, 800,000 minor, outside shop cash |
| Shop obligation to financier | None | None, under assumption 4 |
| Shop obligation to customer | None | None. The illustrated payment covers the 800,000 |
| Profit | — | Undefined. No shop fee is recorded |

#### Consistency

- Every shop delta in the table is 0, so shop cash, shop-owned milligrams, and shop count are unchanged.
- 10,000 mg displays as 10.000 g and is absent from shop-owned accounts.
- 800,000 minor displays as 8,000.00 and is absent from shop cash.
- Shop-owned 21K grams after = 20,000 + 2,000 = 22,000 mg, same as before.

### Case 3B — Shop holds the gold

This is the alternative where the metal is on the premises and is still not shop-owned saleable stock or shop-owned scrap.

#### Assumptions

1. A different parcel from 3A: 12,500 mg (12.500 g), karat 18, scrap-shaped, count not tracked.
2. Agreed customer proceeds are 900,000 minor (9,000.00).
3. On this primary path the financier pays all 900,000 to the customer outside shop cash. Shop cash does not move.
4. The shop receives every milligram into a custody bucket. Ownership assumption: the financier owns it; the shop is the custodian.
5. Recognition into shop-owned scrap or saleable stock does not happen.

#### Unresolved

D05 (is financier ownership correct when the shop is holding the goods?), D07 (is the delivery duty a gold obligation account or only a custody memo?), D16 (the name and screen of the unallocated bucket). The journal below is a paper pattern that balances. It is not a schema.

#### Before

| Paper account | Amount | Display |
| --- | --- | --- |
| Cash | 5,000,000 minor | 50,000.00 |
| Other cash methods | 0 | 0.00 |
| Saleable jewelry 18K | 40,000 mg, count 8 | 40.000 g, count 8 |
| Shop-owned scrap 18K | 1,500 mg | 1.500 g |
| Custody held, not saleable, 18K | 0 mg | 0.000 g |
| Gold delivery obligation to financier, 18K | 0 mg | 0.000 g |
| Money obligations | 0 | 0.00 |

Shop-owned 18K grams before = 40,000 + 1,500 = 41,500 mg.

#### Journals for the primary path

Gold 18K:

| Paper account | Signed mg |
| --- | --- |
| Custody held, not saleable | +12,500 |
| External-receipt clearing | −12,500 |
| Sum | 0 |

No money journal. Saleable weight, saleable count, and shop-owned scrap have no lines.

Parallel obligation under assumption 4, with its journal mapping unresolved: the shop owes the financier delivery of 12,500 mg of 18K. The figure matches the custody figure. It is not a second addition to stock.

#### After

| Paper account | Amount | Display |
| --- | --- | --- |
| Cash | 5,000,000 minor | 50,000.00 |
| Saleable jewelry 18K | 40,000 mg, count 8 | 40.000 g, count 8 |
| Shop-owned scrap 18K | 1,500 mg | 1.500 g |
| Custody held, not saleable, 18K | 12,500 mg | 12.500 g |
| Gold delivery obligation to financier | 12,500 mg | 12.500 g |
| Money obligations | 0 | 0.00 |

| Question | After |
| --- | --- |
| Ownership of the 12.500 g | Financier, under assumption 4 |
| Custody | Shop, in the custody bucket |
| Shop-owned saleable and shop-owned scrap | Unchanged |
| Customer’s unpaid money | 0, because the financier paid the 900,000 outside the till |
| Profit | Undefined |

Physical grams on the premises after = shop-owned 41,500 mg + custody 12,500 mg = 54,000 mg. Only 41,500 mg of that is shop-owned.

#### Consistency

- 12,500 mg displays as 12.500 g
- +12,500 − 12,500 = 0
- Custody 12,500 = delivery obligation 12,500
- Saleable 40,000 and scrap 1,500 are unchanged
- Cash 5,000,000 is unchanged
- 40,000 + 1,500 = 41,500 shop-owned mg, before and after
- 41,500 + 12,500 = 54,000 mg physically present, of which the added 12,500 are not shop-owned

### Case 3B2 — Partial shop cash while the shop still only holds the gold

Unsigned branch. It exists because the source allows a partial cash deduction. It does not change 3B’s gold result.

#### Extra assumptions

- Shop pays 200,000 minor (2,000.00) from cash.
- Financier pays the customer the other 700,000 minor (7,000.00) outside the till.
- The offsetting paper account is a financier money receivable of 200,000: the shop advanced cash and, in this illustration, the financier owes that cash back.
- That receivable is an assumption of D05 and D07. Another workshop answer (a fee, a gift, or a different debtor) would replace the offset. The cash decrease still needs one opposite account so the money journal sums to zero.

Money journal:

| Paper account | Signed minor units |
| --- | --- |
| Cash | −200,000 |
| Financier money receivable | +200,000 |
| Sum | 0 |

Gold journals stay exactly as in 3B. Saleable and shop-owned scrap still do not increase.

Cash after = 5,000,000 − 200,000 = 4,800,000 minor (48,000.00). Customer proceeds 200,000 + 700,000 = 900,000, so the illustrated customer balance is 0. The receivable is not income and is not gold.

### Approval for case 3

The reviewer marks one alternative, or writes a replacement. Unsigned until then.

| Field | 3A | 3B | 3B2 |
| --- | --- | --- | --- |
| Shop-domain reviewer | | | |
| Product owner | | | |
| Date | | | |
| ADR | | | |
| Accepted as the shop’s rule | | | |

## Case 4 — Trader receipt recognized later

Decisions exercised: D03, D06, D07, D16.

### Source facts

A trader receipt can be saved without adding the goods to saleable inventory. Each weight shows whether it has been added. The user can add it later. If it was already typed on the inventory screen, the user can mark it added manually and skip retyping. A pending count of weights not yet in stock is required. Settlement is a later action and is not part of this case.

### Assumptions

1. The receipt is 2 chains, count 2, 4,250 mg (4.250 g), karat 21, piece-tracked.
2. No cash moves at receipt or at recognition.
3. Direction: until a settlement that this sheet does not illustrate, the shop owes the trader 4,250 mg of 21K. The opposite direction would be a different case.
4. Recognition moves the same milligrams and the same count from the unrecognized bucket into saleable stock once. The trader obligation stays at 4,250 mg because recognition is not settlement.
5. The obligation figure is shown as a subledger equal to the unrecognized weight at receipt, and equal to the still-unsettled weight after recognition. Whether that subledger is itself a second balanced gold journal is D07 and is not drawn as extra postings here. The journals that are drawn sum to zero.

### Unresolved

D06’s match rule, D07’s direction and currency, and whether recognition may be partial. This case recognizes the whole receipt.

### Before

| Paper account | Amount | Display |
| --- | --- | --- |
| Cash | 1,500,000 minor | 15,000.00 |
| Saleable chain 21K | 6,000 mg, count 2 | 6.000 g, count 2 |
| Unrecognized chain 21K | 0 mg, count 0 | 0.000 g |
| Trader gold obligation, shop owes trader, 21K | 0 mg | 0.000 g |
| Trader money obligation | 0 | 0.00 |

### Receipt, time T1

Gold 21K journal: unrecognized receipt +4,250 mg; receipt clearing −4,250 mg; sum 0.

Count journal: unrecognized count +2; count clearing −2; sum 0.

No money journal. Saleable stock has no line.

| Paper account | After T1 | Display |
| --- | --- | --- |
| Cash | 1,500,000 minor | 15,000.00 |
| Saleable chain 21K | 6,000 mg, count 2 | 6.000 g, count 2 |
| Unrecognized chain 21K | 4,250 mg, count 2 | 4.250 g, count 2 |
| Trader gold obligation | 4,250 mg | 4.250 g |
| Trader money obligation | 0 | 0.00 |

Ownership of the economic claim at T1, under assumption 3: the shop holds unrecognized goods and owes the trader that weight. The goods are not saleable. Custody: shop, in the unrecognized bucket, not on the saleable shelf.

### Recognition, time T2

Gold 21K journal: saleable chain +4,250 mg; unrecognized receipt −4,250 mg; sum 0.

Count journal: saleable count +2; unrecognized count −2; sum 0.

Obligation and cash have no lines.

| Paper account | After T2 | Display |
| --- | --- | --- |
| Cash | 1,500,000 minor | 15,000.00 |
| Saleable chain 21K | 10,250 mg, count 4 | 10.250 g, count 4 |
| Unrecognized chain 21K | 0 mg, count 0 | 0.000 g |
| Trader gold obligation | 4,250 mg | 4.250 g |
| Trader money obligation | 0 | 0.00 |

The saleable increase happened once. Ownership of the stock position is now the shop’s saleable inventory. The obligation to the trader remains until a settlement this sheet does not post. Custody of those chains is the shop, now in the saleable bucket.

### Manual-link counterexample

Suppose the shop already posted a manual stock increase of the same 4,250 mg and count 2, so saleable is already 10,250 mg and count 4, while the receipt is still unrecognized at 4,250 mg and count 2.

The link that matches this receipt to that existing stock operation ends at saleable 10,250 mg and count 4, with unrecognized at 0. It posts no further +4,250 mg and no further +2 count.

A second stock posting would finish at 6,000 + 4,250 + 4,250 = 14,500 mg (14.500 g) and count 2 + 2 + 2 = 6. That result is the duplicate the source is trying to avoid. It is shown here only as the figure to reject.

PAGES describes the user-visible control as a status update without retyping. The engineering proposal adds an explicit match of the two records before that status can change. This sheet’s arithmetic is the single-increase result. The match procedure remains D06 and is unsigned.

### Consistency

- 6,000 + 4,250 = 10,250
- 2 + 2 = 4
- 4,250 − 4,250 = 0 at recognition
- Obligation stays 4,250 from T1 through T2
- Cash stays 1,500,000
- Rejected double count: 10,250 + 4,250 = 14,500 mg, and 4 + 2 = 6
- 4,250 mg displays as 4.250 g; 10,250 mg displays as 10.250 g

### Approval

| Field | Entry |
| --- | --- |
| Shop-domain reviewer | |
| Product owner | |
| Date | |
| ADR | |
| Accepted as the shop’s rule | |

## Case 5 — Business day closed after midnight

Decisions exercised: D08, D09, D10, D24, D26.

### Source facts

The owner, or an employee the owner delegates, closes the day after checking counts and cash. Work can finish after midnight, and that close still belongs to the open shop day. A new ledger opens for the next day. Expected-versus-counted and a discrepancy reason are the proposal in product scope and database design; the Word text says the close checks counts and cash and does not say that a difference silently replaces the books.

### Assumptions

1. The shop has one configured time zone (SET-01). The illustrated close is shop-local 00:40 on 2026-04-03. The day being closed is the open shop day labeled 2026-04-02 (paper id BD-02). No UTC offset is assumed.
2. The device calendar date at that moment is 2026-04-03. The command still names BD-02.
3. Counted cash is short on the cash method only. The shortfall is an illustration, not a discovered loss.
4. The seal stores expected, counted, and variance. Book balances stay on the expected figures. A corrective operation is separate and is not posted in this case.
5. The next day, BD-03, opens with those same book balances. It does not open with the counted cash substituted in.
6. Who is allowed to close is the owner in this illustration. Delegation exists in the source and is not given a second actor here (D10).

### Unresolved

Reopen, whether a late sale is rejected or moved onto BD-03, and whether a variance may ever post inside the close command. D08 and D09. The discrepancy reason text is blank.

### Books before the seal (also the books after the seal)

| Paper account | Karat | Book amount | Display |
| --- | --- | --- | --- |
| Cash | — | 2,350,000 minor | 23,500.00 |
| Instant transfer | — | 800,000 minor | 8,000.00 |
| Wallet | — | 150,000 minor | 1,500.00 |
| Card | — | 0 | 0.00 |
| Saleable | 18 | 7,830 mg, count 4 | 7.830 g, count 4 |
| Saleable | 21 | 3,200 mg, count 2 | 3.200 g, count 2 |
| Shop-owned scrap | 21 | 1,000 mg, no count | 1.000 g |
| Custody, unrecognized, obligations | — | 0 | — |

Money book total = 2,350,000 + 800,000 + 150,000 + 0 = 3,300,000 minor (33,000.00).

Saleable piece count = 4 + 2 = 6. Scrap has no count in this illustration. Milligrams of 18K, 21K saleable, and 21K scrap are three controls, not one gram total.

### Count sheet at 00:40 shop-local on the next calendar date

| Control | Expected | Counted | Counted − expected |
| --- | --- | --- | --- |
| Cash minor | 2,350,000 | 2,330,000 | −20,000 |
| Instant transfer minor | 800,000 | 800,000 | 0 |
| Wallet minor | 150,000 | 150,000 | 0 |
| Card minor | 0 | 0 | 0 |
| Money total minor | 3,300,000 | 3,280,000 | −20,000 |
| Saleable 18K mg / count | 7,830 / 4 | 7,830 / 4 | 0 / 0 |
| Saleable 21K mg / count | 3,200 / 2 | 3,200 / 2 | 0 / 0 |
| Scrap 21K mg | 1,000 | 1,000 | 0 |

−20,000 minor displays as −200.00. Reason text: blank, for the owner. No profit and no loss account is posted for that 200.00.

### After the seal

| Record | State |
| --- | --- |
| BD-02 | Closed. Book balances equal the expected column, including cash at 2,350,000 minor |
| Count sheet | Stored beside the close, including counted cash 2,330,000 minor and variance −20,000 |
| BD-03 | Open. Carried cash methods and gold buckets equal the BD-02 books, not the count sheet |
| Corrective cash adjustment | Not posted |
| Grams | No milligram moved |
| Counts | No count moved |
| Ownership and custody | Unchanged by the seal |
| Obligations | Unchanged, and none were open in the before table |

A sale attempted against BD-02 after this seal is not given a posting. D08 still has to choose reject or route.

### Consistency

- 2,350,000 + 800,000 + 150,000 + 0 = 3,300,000
- 2,330,000 + 800,000 + 150,000 + 0 = 3,280,000
- 3,280,000 − 3,300,000 = −20,000
- Book cash after the seal remains 2,350,000, which is the expected figure
- 7,830 mg displays as 7.830 g; 3,200 mg as 3.200 g; 1,000 mg as 1.000 g
- Gold and count variances are 0
- 4 + 2 = 6 saleable pieces, scrap excluded
- No cross-karat gram total is used as a control

### Approval

| Field | Entry |
| --- | --- |
| Shop-domain reviewer | |
| Product owner | |
| Date | |
| ADR | |
| Accepted as the shop’s rule | |

## Decision coverage

| Case | Decisions the numbers depend on | Decisions named and not illustrated |
| --- | --- | --- |
| 1 Simple sale | D02, D03, D24, D26 | D23 |
| 2 Mixed tender | D02, D03, D24, D26 | D23 |
| 3 Financier | D02, D05, D07, D16, D26 | D04 |
| 4 Trader receipt | D03, D06, D07, D16 | D02, because no price is posted |
| 5 Midnight close | D08, D09, D10, D24, D26 | D02 pricing |

## Machine-checked identities

The identities below are the arithmetic of this file. They were evaluated as integer and decimal equalities when the file was written.

```text
1000000 + 420000 == 1420000
5000 - 1830 == 3170
3 - 1 == 2
420000 - 420000 == 0
1830 - 1830 == 0
1 + -1 == 0
1830 / 1000 == 1.830
3170 / 1000 == 3.170
420000 / 100 == 4200
1420000 / 100 == 14200
640000 + 250000 + 110000 == 1000000
400000 + 350000 + 250000 == 1000000
1750000 + 500000 + 300000 + 100000 == 2650000
2150000 + 850000 + 550000 + 100000 == 3650000
2650000 + 1000000 == 3650000
1750000 + 400000 == 2150000
500000 + 350000 == 850000
300000 + 250000 == 550000
10000 - 2560 == 7440
8000 - 1250 == 6750
3000 - 500 == 2500
1250 + 500 == 1750
-1250 + -500 + 1750 == 0
4 - 1 == 3
5 - 1 == 4
6 - 1 == 5
2560 / 1000 == 2.560
1250 / 1000 == 1.250
500 / 1000 == 0.500
7440 / 1000 == 7.440
6750 / 1000 == 6.750
2500 / 1000 == 2.500
10000 / 1000 == 10.000
800000 / 100 == 8000
20000 + 2000 == 22000
12500 / 1000 == 12.500
900000 / 100 == 9000
40000 + 1500 == 41500
41500 + 12500 == 54000
12500 - 12500 == 0
5000000 - 200000 == 4800000
200000 + 700000 == 900000
200000 - 200000 == 0
4800000 / 100 == 48000
6000 + 4250 == 10250
2 + 2 == 4
4250 - 4250 == 0
10250 + 4250 == 14500
4 + 2 == 6
4250 / 1000 == 4.250
10250 / 1000 == 10.250
14500 / 1000 == 14.500
2350000 + 800000 + 150000 + 0 == 3300000
2330000 + 800000 + 150000 + 0 == 3280000
3280000 - 3300000 == -20000
20000 / 100 == 200
3300000 / 100 == 33000
7830 / 1000 == 7.830
3200 / 1000 == 3.200
1000 / 1000 == 1.000
4 + 2 == 6
```

# Milestones 0–3 synthetic accounting examples

These are exact expected outcomes for the user-authorized working rules in [ADR 0009](../adr/0009-milestone-3-accounting-working-rules.md). They extend, and do not replace, the historical [discussion sheets](financial-worked-examples.md). No stakeholder signature has been supplied. Cases are implementation acceptance targets until matching backend/UI evidence exists.

Each case starts independently from the same baseline. Money vectors list cash/card/instant-transfer/wallet in integer piastres. Gold weights are integer milligrams; gram display divides by 1,000 with exactly three places. Counts are integers. Baseline custody and obligations are zero. Every baseline lot is shop-owned and held by the shop.

| Baseline account | Exact quantity |
| --- | --- |
| Money vector | 10,000,000 / 3,000,000 / 2,000,000 / 1,000,000 piastres |
| Worked jewelry, 18K | 40,000 mg (40.000 g), 10 pieces |
| Worked jewelry, 21K | 60,000 mg (60.000 g), 10 pieces |
| Scrap, 18K | 20,000 mg (20.000 g), no count |
| Scrap, 21K | 30,000 mg (30.000 g), no count |
| Scrap, 14/22/24K | 0 mg each |
| Bullion, 24K | 20,000 mg (20.000 g), 4 pieces |
| Coins, 21K | 16,000 mg (16.000 g), 2 pieces |

All accounts not explicitly changed in a case retain these exact baseline values. Journal offsets are mechanical clearing entries in the same unit/karat; they are not profit. Every journal sums to zero independently of other units.

| Case | Exact confirmed event | Money vector after | Gold/count after | Ownership, custody and remaining obligation |
| --- | --- | --- | --- | --- |
| 1 Normal sale | Sell 1,830 mg 18K, one piece, for 420,000 piastres cash | 10,420,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 18K jewelry 38,170 mg, 9 pieces | Buyer owns/holds the sold item; no obligation |
| 2 Split-tender sale | Sell 2,560 mg 21K, one piece, for 600,000: cash 100,000, card 200,000, wallet 300,000 | 10,100,000 / 3,200,000 / 2,000,000 / 1,300,000 | Owned 21K jewelry 57,440 mg, 9 pieces | Buyer owns/holds sold item; no obligation |
| 3 Fully paid purchase | Buy 3,000 mg 18K, one piece, for 2,100,000: instant 2,000,000, cash 50,000, wallet 50,000 | 9,950,000 / 3,000,000 / 0 / 950,000 | Owned 18K jewelry 43,000 mg, 11 pieces | Shop owns/holds acquired lot; no obligation |
| 4 Partially paid purchase | Buy 10,000 mg 21K, two pieces, price 6,000,000; cash now 2,000,000 | 8,000,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 21K jewelry 70,000 mg, 12 pieces | Shop owns/holds; EGP payable 4,000,000 piastres, no gold payable |
| 5 Unpaid purchase | Same goods and price as case 4; cash now zero | Baseline vector | Owned 21K jewelry 70,000 mg, 12 pieces | Shop owns/holds; EGP payable 6,000,000 piastres only |
| 6 Scrap purchase | Buy 5,000 mg 22K scrap, price 3,000,000, cash paid fully | 7,000,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 22K scrap 5,000 mg, no count | Shop owns/holds scrap; no obligation |
| 7 Scrap sale | Sell 2,000 mg 18K scrap, receive cash 500,000 and card 250,000 | 10,500,000 / 3,250,000 / 2,000,000 / 1,000,000 | Owned 18K scrap 18,000 mg | Buyer owns/holds sold scrap; no obligation |
| 8 Bullion receipt | Buy nominal 5 g bar, measured 4,998 mg, one piece, cash 3,000,000 | 7,000,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 24K bullion 24,998 mg, 5 pieces | Shop owns/holds; denomination 5 g retained separately; no obligation |
| 9 Coin routing | Buy two nominal half-coins, measured total 7,996 mg; one 3,998 mg piece to coin stock, 3,998 mg to scrap; cash 4,000,000 | 6,000,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 21K coins 19,998 mg, 3 pieces; 21K scrap 33,998 mg | Shop owns/holds all 7,996 mg exactly once; no obligation |
| 10 Trader custody | Receive trader-owned 10,000 mg 21K jewelry, two pieces; trader owns, shop holds | Baseline vector | Owned quantities unchanged; held trader lot 10,000 mg, 2 pieces | Custody return duty 10,000 mg of that linked lot; no purchase cash/gold payable |
| 11 Later ownership transfer | After case 10, acquire all held lot for 6,000,000; pay cash 2,000,000 | 8,000,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 21K jewelry 70,000 mg, 12 pieces; held trader remainder 0 | Shop owns/holds; EGP payable 4,000,000; custody duty cleared; no second physical receipt |
| 12 Explicit gold obligation | Acquire 5,000 mg 18K jewelry, one piece, for agreed obligation of 4,000 mg 18K; no cash price or movement | Baseline vector | Owned 18K jewelry 45,000 mg, 11 pieces | Shop owns/holds; gold payable 4,000 mg at 18K only, no EGP payable |
| 13 Partial cash settlement | After case 4, pay 1,000,000 cash against payable | 7,000,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 21K jewelry stays 70,000 mg, 12 pieces | EGP payable now 3,000,000; no second gold addition |
| 14 Partial gold settlement | After case 12, deliver 1,500 mg from owned 18K scrap | Baseline vector | Owned 18K jewelry stays 45,000 mg, 11 pieces; scrap 18,500 mg | Gold payable 2,500 mg at 18K; trader holds delivered scrap; no EGP movement |
| 15 Full linked sale return | After case 1, return exactly that item and refund 420,000 cash | Baseline vector | Baseline owned quantities | Original sale immutable; buyer no longer owns/holds item; linked compensating return |
| 16 Partial linked sale return | Sell 4,000 mg 21K, two pieces, for 1,000,000 cash; later return 1,500 mg, one piece, refund agreed 400,000 cash | 10,600,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 21K jewelry 57,500 mg, 9 pieces | Buyer retains 2,500 mg, one piece; remaining return ceiling 2,500 mg, one piece and 600,000 piastres |
| 17 Partial purchase return | After case 4, return 2,000 mg, one piece, agreed returned consideration 1,200,000; cancel payable first | Same as case 4 | Owned 21K jewelry 68,000 mg, 11 pieces | EGP payable 2,800,000; no cash refund yet; seller owns/holds returned item |
| 18 Audited correction | Owner counts 18K jewelry as 39,000 mg, 9 pieces and cash as 9,990,000, with required reason/current version | 9,990,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 18K jewelry 39,000 mg, 9 pieces | New adjustment operation: cash −10,000, gold −1,000 mg, count −1; original history preserved |
| 19 Exchange | After case 1, return sold item/refund 420,000 cash and sell 2,000 mg 21K, one piece, for 500,000 cash atomically | 10,500,000 / 3,000,000 / 2,000,000 / 1,000,000 | Baseline 18K jewelry; owned 21K jewelry 58,000 mg, 9 pieces | Buyer owns/holds replacement; original sale preserved; net exchange cash +80,000 relative to case 1 |
| 20 Explicit pricing | Sell 1,000 mg 18K, one piece; base 100,000 + workmanship 10,000 + named charge 2,000 − discount 5,000 = 107,000 cash | 10,107,000 / 3,000,000 / 2,000,000 / 1,000,000 | Owned 18K jewelry 39,000 mg, 9 pieces | All agreed price components preserved; no tax/legal compliance claim |

## Recognition and manual linkage

Receive a shop-owned 3,000 mg 21K lot, one piece, with recognition deferred. Baseline owned inventory remains 60,000 mg and 10 pieces; held pending recognition is 3,000 mg and one piece. Recognize it later: owned becomes 63,000 mg and 11 pieces, pending becomes zero. Replaying that command returns the same operation. A different key attempting the same quantity fails.

Alternative: if an audited manual addition already recognized that exact lot (owned 63,000 mg/11 pieces), a verified receipt-to-addition allocation clears pending recognition and keeps owned at 63,000 mg/11 pieces. A second manual allocation fails. Trader-owned custody is not eligible for this shortcut; case 11's explicit ownership transfer is required.

## Closing after midnight

A business day opened under server ID A on Cairo date 2026-09-30 stays open at Cairo 00:30 on 2026-10-01. A sale at that time belongs to A, while its UTC server timestamp determines operation order. An exact physical count closes A without moving any money, milligrams or pieces. A mismatch leaves A open; case 18's reviewed correction may be required before a fresh matching close. Opening the next day creates server ID B with the server-derived shop date. Changing the device time zone cannot reassign the persisted operation to B.

## Required failure examples

No posting on invalid category/karat, negative owned remainder, unknown fields, mixed obligation units, over-settlement, duplicate recognition/transfer/manual allocation, stale correction version, closed-day mutation, revoked/expired write, platform-admin shop access, cross-shop IDs or anonymous calls. A same-key changed payload fails; a same-key lost-response retry returns the original operation. Exchange failure rolls back both sides. Private notes cannot be read across shops. Concurrent recognition/settlement must serialize on the same shop/receipt locks and never exceed the remaining quantity.

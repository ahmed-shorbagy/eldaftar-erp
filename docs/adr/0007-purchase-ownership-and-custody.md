# ADR 0007: purchase ownership, custody, and one obligation unit

- Status: accepted product rule; shop-owned EGP payable path applied and rollback-tested on the connected project; custody and gold obligation paths pending.
- Date: 2026-09-29.
- Decision owner: product owner in the 2026-09-29 conversation.
- Scope: D05, D07, D16, PUR-02, trader and financier purchase paths.

## Decision

Physical receipt and shop ownership are separate. Gold enters shop-owned stock only when control transfers to the shop under the agreed purchase. Gold merely held for a trader or financier is a separate custody balance and is excluded from saleable owned stock and profit. A later ownership transfer moves the exact linked quantity from custody to owned stock once; it cannot repeat the original physical receipt as a second stock addition.

A partially paid purchase that transfers ownership immediately records all received owned gold, the cash actually paid, and one outstanding payable denominated in the agreed unit. A cash-denominated balance is not also a gold-denominated payable. A gold-denominated payable records karat and integer milligrams; conversion to cash requires a separately confirmed, audited conversion with an agreed rate. Custody return duty is distinct from a purchase payable.

## Worked cash-payable example

The shop buys 10.000 g of 21K gold for EGP 60,000. Ownership transfers now and the shop pays EGP 20,000 cash. The one confirmed operation adds 10,000 mg to owned stock, reduces cash by 2,000,000 piastres, and opens a 4,000,000-piastre payable to the seller. A later EGP 40,000 settlement reduces cash and clears that payable; it does not add stock again. If the parties instead agree to owe 6.000 g of 21K, the operation opens a 6,000 mg gold payable with no parallel EGP 40,000 payable. Its eventual gold settlement reduces the obligation and the gold account used to deliver it in one atomic command.

## Financier custody example

A financier pays the customer EGP 60,000 directly and owns the customer's 10.000 g of 21K gold. The shop physically holds the parcel. The shop records 10,000 mg in financier custody linked to the receipt and a return duty for that parcel. It records no shop cash movement, owned stock, purchase price, or payable to the customer. If the financier later sells that parcel to the shop for EGP 60,000, with EGP 20,000 paid then and EGP 40,000 owed, one confirmed transfer removes 10,000 mg from financier custody, adds 10,000 mg to owned stock, reduces shop cash by 2,000,000 piastres, and opens a 4,000,000-piastre payable to the financier. A separate settlement clears the payable without moving the same gold again.

## Implementation contract

Each receipt needs an immutable receipt ID, owner, custodian, counterparty, category, karat, integer milligrams, integer count when relevant, and server timestamp. Each transfer links that receipt and checks its untransferred remainder under a shop lock. Cash, owned stock, custody, obligations, audit, and idempotency are posted atomically. The review screen names who owns and holds the gold, what the shop pays now, and what remains owed in its exact unit. Reports show owned and held gold separately. The shop-owned EGP-payable purchase and cash-settlement path passed its rollback-only SQL gate on the connected project. Custody, gold-denominated debt and linked ownership transfer remain unimplemented.

This is a product bookkeeping model, not a determination of any party's legal title or tax treatment. The control-versus-custody distinction is consistent with the indicators in [IFRS 15 B77–B80](https://www.ifrs.org/content/dam/ifrs/publications/pdf-standards/english/2022/issued/part-a/ifrs-15-revenue-from-contracts-with-customers.pdf?bypass=on) and the asset concept for inventories in [IAS 2](https://www.ifrs.org/issued-standards/list-of-standards/ias-2-inventories/). The worked entries above are the approved application design, not text quoted from those standards.

# ADR 0009: exact lots, custody, obligations and compensating corrections

Status: working implementation rules authorized by the user's 2026-10-01 completion request. External shop-domain and legal acceptance remain open. This record is not a fabricated stakeholder signature.

Related decisions: D02, D03, D04, D06, D07, D08, D17, D22. Preserves ADRs 0003 and 0007. Extends the bounded scope of ADRs 0004 and 0005; their historical acceptance limits remain intact.

## Units and pricing

EGP piastres, measured gold milligrams, and piece counts are integers. JSON quantities are canonical integer strings checked against PostgreSQL bigint bounds. Intermediate sums use exact numeric arithmetic; each currency, karat and quantity family balances independently. No conversion between karats or between EGP and gold is inferred.

An invoice records base price, positive workmanship, positive other charges, and positive discount separately. Reviewed total is base plus workmanship plus other charges minus discount, and cannot be negative. A zero-price transfer is a separate inventory/custody command, not a sale. Other charges require a description. These fields express the owner's agreed price; they do not assert a tax rate or legal invoice compliance. Legacy price-only operations retain their original total and are not rewritten into invented components.

## Products, lots and denominations

Products identify name, category and allowed karat. Each acquisition/receipt creates a distinct immutable lot/receipt identity with exact measured milligrams, count where applicable, owner, custodian, originating confirmed operation and server UTC timestamp. Worked jewelry allows 14/18/21/22, scrap 14/18/21/22/24, bullion 24, and coins 21, following the existing category policy.

Bullion denominations and coin types are shop-configurable catalog identities. A nominal 5 g bar may weigh 4.998 g; stock uses 4,998 mg and one piece, never a derived nominal weight. Purchase routing partitions measured quantities between saleable lots and scrap at the same karat. The partitions must equal the actual receipt and cannot recognize the same milligrams twice.

Historical aggregate stock must be clearly labeled as a legacy aggregate lot, not a fabricated physical item or denomination. Assigning identity to already recognized stock creates no new journal movement. Existing postings remain immutable and traceable. New lot movements link confirmed operations; availability is the sum of confirmed allocations. Client pending quantities are visibly pending and excluded from confirmed owned totals. Old client commands remain readable and must participate in lot reconciliation rather than silently bypassing it.

## Custody and recognition

Physical receipt, shop ownership and catalog recognition are separate facts. Trader-owned gold held by the shop is excluded from shop-owned availability. A pending shop-owned receipt is held but not yet recognized into saleable stock. Recognition can occur immediately or later, exactly once per remaining quantity. Ownership transfer of trader gold requires a separate reviewed command naming the agreed cash/gold obligation and moving only the receipt's remaining quantity.

Manual linking is permitted only for a shop-owned receipt and a matching confirmed inventory addition. Match shop, product/category, karat, measured milligrams, count, source operation and unallocated remainder under the shop lock. Linkage creates no second stock posting. An unchecked “already entered” flag is insufficient. Trader-owned custody cannot be linked to shop-owned stock as a substitute for an explicit ownership transfer. No receipt quantity or manual addition quantity can be allocated twice.

## Obligations and settlements

Every balance has one direction and one unit: EGP cash, or milligrams at exactly one karat. Custody return duty is separate from a purchase payable. A cash payable never also creates a gold payable for the same consideration. Cash purchases already implemented remain readable through their existing payable contract.

Settlement cannot exceed the remaining obligation. An EGP obligation settles through selected EGP payment methods; a gold obligation settles through selected shop-owned scrap or authorized inventory at the obligation's karat. These actions update cash/gold, count, custody where relevant, remaining obligation, audit and outbox atomically. The review displays all effects. No mixed-unit settlement or automatic cash/gold conversion is offered. A separately agreed conversion is outside this working rule.

## Partial returns and exchanges

Confirmed original operations and postings are immutable. A return links the original and records exact returned item quantities and the owner-agreed returned consideration. Cumulative returned weight, count and consideration cannot exceed the original. There is no inferred proportional price allocation for an invoice-level price; the owner enters the explicit partial return amount and reviews it. Tender refund allocation is explicit and cannot refund more than cumulative cash paid, including confirmed purchase settlements.

For a purchase with an outstanding EGP payable, returned consideration first cancels up to that remaining payable; any excess is a reviewed cash refund received from the seller. This preserves the equation between original consideration, retained goods consideration, refunded cash and remaining payable. For a sale, the owner explicitly selects outgoing refund methods with sufficient balances. A full return after earlier partial returns reverses only the remaining quantities and consideration, never the original in full again.

An exchange posts the linked return and replacement sale/purchase within one server transaction under one idempotency envelope. Failure of either side rolls back both. The review displays each side and net cash, gold and count effects, rather than treating a price difference as a hidden edit. The original invoice remains a confirmed operation copy.

## Discrepancy and inventory corrections

A physical count difference remains visible. The owner supplies a required reason and confirms a new compensating operation against the current server day/version. Each cash-method, category/karat gold and piece delta posts against an explicit adjustment clearing account. Corrections cannot make owned balances negative or create weight without count for piece-tracked stock. Direct editing/deletion of balances, historical postings or operations remains forbidden.

Close-day still requires an exact count against a fresh server snapshot after correction. An open day retains its identity across midnight; UTC server ordering and the configured shop time zone determine display. Stale counts fail with a visible conflict and require review. Corrections to older operations post in the current open day; reopening a sealed historical day is not required or introduced by this scope.

## Safety and compatibility

All commands resolve the live signed-in owner and shop on the server, check entitlement and open day for new writes, acquire the shop lock before receipt/lot/request locks, reject unknown payload keys, and write one immutable operation, audit record and outbox event atomically. A committed same-key replay returns the original result; a changed payload fails. Expired owners may read/export under existing access; revoked owners, anonymous callers, platform admins and other shops receive no shop access.

Apply additive versioned migrations only after review. Catalog/lot metadata backfill must not post a second opening balance or alter historical journals. Versioned read contracts preserve old clients where practical. Every reported confirmed gram and count must trace to server-confirmed operations. Rollback-only synthetic SQL tests measure project row counts before and after; concurrent sessions require separate concurrency evidence, not a claim derived from a single transaction.

Verification targets are the [expanded worked examples](../discovery/milestones-0-3-worked-examples.md) and the [completion-run evidence](../operations/milestones-0-3-progress-2026-10-01.md). Implementation and verification status remain tracked there; writing this ADR alone does not complete any feature.

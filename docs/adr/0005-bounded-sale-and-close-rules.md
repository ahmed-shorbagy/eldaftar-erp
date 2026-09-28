# ADR 0005: bounded sale and manual close rules

- Status: accepted by product owner for bounded implementation; full financial acceptance remains open.
- Date: 2026-09-28.
- Decision owner: product owner, in the 2026-09-28 conversation.
- Scope: D02, D03, D08, D26, SALE-01–SALE-04, LED-01, and related purchase limits.

## Context

The opening balance uses EGP piastres and integer milligrams, but its ADR deliberately left sale and close behavior unsigned. The synthetic examples in [financial worked examples](../discovery/financial-worked-examples.md) remain discussion sheets, not signed shop-domain examples. The product owner approved the following bounded rules for a first sale posting and manual close. This acceptance does not approve tax, workmanship, discounts, credit, invoice-total price allocation, purchase custody, or a full inventory catalog.

## Decision

1. A first sale may use EGP in integer piastres, gold in integer milligrams, and integer counts. No binary floating point is permitted in a stored or transported quantity.
2. Reject a sale that would make shop-owned stock negative. Split tender must equal the invoice total exactly. Omit tax, workmanship, discounts, and credit sales until their rules are approved.
3. An open business-day ID remains open through midnight. The owner explicitly closes it. The server rejects new postings after close. The next business day opens only through an explicit owner action. A sealed day has no reopen action until a separate correction process is approved.
4. Defer irreversible purchase posting involving partial payment or unrecognized goods until D05 and D16 identify ownership, custody, and outstanding obligations through a worked example. This does not approve a financed purchase posting.
5. A first fully paid purchase may use the opening catalog's category/karat buckets. Recognize all received grams and counts into shop-owned stock or scrap in the same atomic posting. The outgoing split tender equals the price exactly and cannot overdraw any method. Partial payment, financier involvement, and unrecognized goods stay deferred.
6. An initial expense has a positive EGP amount, a required Arabic description, and one or more of the four cash methods whose piastres sum exactly to that amount. It has no stock or gold effect. The server rejects insufficient method balances and writes one audited atomic posting.
7. A sale may store one whole-invoice price without allocating it to items. The outgoing stock rows still retain their separate weight, count, category, and karat. Its split tender equals that invoice price exactly. Per-line prices may also be recorded; a whole-invoice price must never be misrepresented as per-line revenue.
8. Profit remains hidden until a valuation rule is approved. Any cash figure must say whether it is a balance or a movement.

## Consequences and remaining decisions

The approved rules narrow the first sale, fully paid purchase, expense, and close contracts; they do not complete the commands. D02 still needs rules for future tax, workmanship, discount, and credit behavior. D03 still needs a product-level tracking model beyond the opening aggregate catalog. D08 still needs the exact close discrepancy and correction workflow. D04, D05, and D16 remain open for bullion/coin denomination detail, financier, and unrecognized-goods purchases. The product owner did not sign the synthetic examples' blank approval rows. No schema or remote state was changed by this ADR.

Before a sale or close is exposed as operational, verify owner-only server authorization, exact arithmetic, balanced atomic postings, idempotent retry, concurrent attempts, UTC audit time, shop-day grouping, stale-session denial, reconciliation, and Arabic RTL pending/success/failure UI.

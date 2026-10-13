# Debt balances and settlement

Status: implemented working rule for DEBT-01. Development deployment and independent validation recorded; native owner acceptance remains open. [Validation](../reviews/debts-2026-10-13/independent-validation.md), [deployment](../reviews/debts-2026-10-13/deployment.md).
Date: 2026-10-13

A shop debt is one balance in one unit: money in piastres, or gold milligrams at one karat among 14, 18, 21, 22, and 24. There is no conversion between money and gold, and no conversion between karats. [ADR 0007](0007-purchase-ownership-and-custody.md) and [ADR 0009](0009-milestone-3-accounting-working-rules.md) stay in force.

## Authoritative balances

Confirmed `purchase_cash_payables` and `gold_obligations` stay the source of truth. The debt list and detail read them live. Nothing copies those rows into `shop_debts`, and nothing backfills their history. Existing purchase, purchase-settlement, purchase-return, gold-acquisition, and gold-settlement rows remain the history of those balances. Outstanding repair fees stay on the repair under [ADR 0012](0012-repair-custody-and-fees.md) and are not debts.

`shop_debts` holds only a standalone declaration of a historical or external balance. That declaration posts no journal, lot, receipt, custody row, payable, or gold obligation, and it does not require an open business day. The review states that cash, gold, custody, and saleable stock stay at zero.

Directions are `shop_owes` and `owed_to_shop`. Existing purchase payables and gold obligations are shop-owes only. Owed-to-shop exists only as a standalone declaration.

## Settlement

Every settlement records a reason and an explicit choice.

Source balances must move cash or gold. A no-ledger settlement of a payable or gold obligation is rejected, because the original journals already cleared through movement accounts. A second key that reuses the same settlement reference is `duplicate_reference` before the remaining-balance check. When the reviewed remaining and version still match, a larger amount is `settlement_exceeds_obligation`. Two concurrent settlements that both reviewed the same snapshot produce one success and one `stale_debt`. The second owner reloads before another amount is accepted.

Standalone no-ledger settlement is allowed. It requires the reason, stores `ledger_effect = none`, does not post a financial operation, and does not bump the business day. The owner reviews that cash, gold, custody, and saleable stock do not move.

Standalone settlement with `ledger_effect = move` uses the open business day and its expected version. Money uses the selected methods and must sum to the amount. Shop-owes money decreases those method balances and increases `movement_money_clearing`. Owed-to-shop money increases an existing cash method account. A missing method is rejected rather than created. Outgoing gold consumes named owned lots or scrap at the same karat, with a piece count for counted categories and no count for scrap. Incoming gold creates an owned available lot and an immediate shop-owned receipt. It is not custody and it is not a sale. Movement kinds stay inside the existing checks: outgoing gold uses `gold_settlement`, and incoming gold uses `receipt` / `manual`. The financial operation kind for that standalone move is `debt_settlement`, labeled سداد دين.

A source cash settlement calls `settle_purchase_cash_payable` after the debt command has locked the shop, the payable, and the open day. The posted kind stays `purchase_settlement`, and the stored detail keeps `purchase_operation_id` plus the tenders. A source gold settlement calls `post_gold_obligation_settlement_v1` the same way. The posted kind stays `gold_obligation_settlement`, and the stored detail keeps `obligation_operation_id`, the deliveries, and the reason. The legacy function updates the payable or obligation once and writes one financial operation. The debt command does not update that balance again and does not insert a second operation. `debt_command_requests` stores the original debt envelope. The legacy command registry stores the legacy payload under the same idempotency key. A debt replay is answered from `debt_command_requests` and does not call the legacy function again.

The server stores party, reason, and external reference exactly as sent and rejects untrimmed text. The client trims those three fields before it builds the payload. A phone must already be empty or match the digit pattern, with no surrounding spaces.

## Amounts

`settled_amount` is money or gold actually paid through a settlement. `cancelled_amount` is a separate canonical integer string on the list, the detail, and every command result. A purchase return increases `cancelled_amount` by the immutable `cancelled_payable_piastres` and does not increase `settled_amount`. Cancelling an unsettled standalone declaration sets `settled_amount` to zero, `remaining_amount` to zero, and `cancelled_amount` to the original amount. The invariant is `original_amount = settled_amount + cancelled_amount + remaining_amount`.

For a purchase payable, the original amount is the initial payable. Cash paid at the purchase itself is not part of it. Settled, cancelled, and remaining are derived from purchase-settlement tenders, purchase-return cancellation amounts, and the live `remaining_piastres`. The stored `initial_piastres` is not overwritten and is not copied into `shop_debts`. A gold obligation has no return cancellation; its cancelled amount is zero, and its settled amount is the sum of `gold_obligation_settlement` deliveries. Original is immutable `initial_milligrams`. Both source types read the immutable initial amount and reject inconsistent settlement/cancellation/remaining totals rather than inventing an original.

## History and contact

Every history entry has `actor_user_id` and `actor_display_name`, plus the amount and the cash, gold, count, and saleable effect. A debt event stores the actor name used at the time. A financial operation uses the shop's owner display name. Gold acquisition is labeled استلام ذهب مقابل التزام. Gold settlement is labeled سداد التزام ذهب. A missing label becomes عملية مرتبطة and is never the English kind identifier.

A new source settlement can have both a legacy financial operation and a debt event that point at that operation. Detail history shows the financial operation once and omits the duplicate settled event. Declaration, cancellation, and archive events stay. The contact phone on a source row is the immutable purchase detail `customer_phone` when it is present, otherwise the linked trader phone. Gold obligations have no phone on the acquisition payload, so only the trader phone is available. An empty phone stays null.

## Identity

Under the shop lock already taken for the command, a new standalone declaration is `duplicate_debt` when direction, unit, karat, amount, party, phone, reason, and external reference are exactly equal to an existing standalone row. Null references match each other, so an identical declaration with no reference is rejected under a fresh key. A different non-null external reference is a different obligation even when the other fields match. The same non-null reference with different fields remains `duplicate_reference`.

This is exact stored-field equality. It is not a semantic or fuzzy match: different wording, phone, or amount is another row, and the guard does not claim to find every real-world duplicate. A declaration whose external reference is an existing purchase-payable or gold-obligation id, or the `purchase_cash_payable:` / `gold_obligation:` key of that row, is also `duplicate_debt`. It does not create a second balance. Repair rows are not read and are not imported.

## Cancel and archive

Cancel is allowed only for a standalone debt that is still open and has settled amount zero. It requires a reason, sets status `cancelled`, remaining zero, and preserves the original amount. It posts no journal, lot, or custody change. Cancelling a source balance or a partly settled standalone debt is rejected.

Archive does not delete history and does not clear remaining. A standalone archive records the status it came from. A source archive is a mark only. It does not change the payable or the obligation, and it does not block a later settlement of that balance. The remaining filter still includes an archived balance whose remaining amount is greater than zero.

## Idempotency and access

`debt_declare`, `debt_settle`, `debt_cancel`, and `debt_archive` store the original key and payload. The same key and payload replay the stored result, including for an expired owner. A changed payload is `payload_mismatch`. A new write requires a live owner session. Direct table writes are denied. Success is the server result only. The client keeps an unknown command frozen and reconciles it by command kind and source id.

`shop_sync_signals.debt_revision` advances when a standalone debt or debt event changes. Payable changes remain ledger scope. Gold-obligation changes remain trader scope. The client also refreshes ledger, inventory, and trader routes after a confirmed debt command because a moving settlement can touch those books.

## Bounds that are not assumed

No due reminders, debt PDFs, CRM contacts, reports, or invoice customization. No repair-outstanding import. No unit conversion. Custody return duties remain in existing repair and trader-receipt workflows. Both reviewed migrations are deployed to development. Party and reason are required; contact phone and reference are optional. Historical/external declaration and no-ledger settlement are bounded working assumptions, not approval of every external accounting arrangement.

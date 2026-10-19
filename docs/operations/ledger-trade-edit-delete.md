# Current-day sale and purchase edit/delete

Server-owned review and post for an open business day's sale or purchase. The caller cannot choose inverse amounts. Money stays integer piastres and gold stays integer milligrams. Timestamps are `clock_timestamp()` UTC.

## Commands

`public.review_ledger_trade_change_v1(operation, action, replacement)` is read-only. It returns version 1, the shop, the source operation, `edit` or `delete`, the open day id and version, a 64-character source hash, a 64-character review token, the original canonical trade payload, and net effects. Delete requires a null replacement. Edit requires a canonical sale or purchase draft of the same kind, version 1 or version 2. Effects use signed decimal strings. Empty cash, stock, or scrap arrays are `[]`, and a zero payable delta is `"0"`.

`public.post_ledger_trade_change_v1` takes the idempotency key, source operation, action, replacement, expected day id and version, source hash, and review token. It returns `{ok, operation_id, replayed}` and, for edit only, `replacement_operation_id`. `operation_id` is the internal reversal. The parent `financial_command_requests` row uses that same reversal id, so `get_opening_status` reconciles an unknown retry to the reversal. A later `get_daily_ledger_operation` read shows `trade_change`.

Replay compares the rebuilt command payload and hash before day, eligibility, or write-entitlement checks. A stored command still replays after the shop entitlement expires. Revoked membership and an expired session fail at the reader gate. A payload or hash mismatch is `payload_mismatch`.

## One transaction

Post locks the shop, then the source. If a change row already exists, the loser gets `operation_replaced` before a stale-day error. The server builds a full `sale_return` or `purchase_return` and calls `private.post_linked_return_core` with day bumping off. Edit then posts the replacement through `public.post_daily_ledger_trade`. Delete bumps `business_days.day_version` itself. A failing replacement aborts the reversal with it.

The return core's immediate cash and purchase-stock prechecks are stricter than the net edit. While `eldaftar.trade_change_net` is `on`, those two prechecks are skipped. Payable cancellation, return bounds, and lot consumption stay in force. The setting is transaction-local and is turned off before the function continues, so a later statement in the same transaction does not skip those prechecks. Authenticated clients cannot call the return writers or the private core. Opening creates a zero-balance account for every cash method, so collecting into wallet is valid. `invalid_input` applies when that cash-method account row is absent. After both children, `private.trade_change_assert_final` rejects a negative ending balance. The deferred journal non-negative trigger still applies at commit.

Child idempotency keys use the salts `:trade-reversal` and `:trade-replacement`.

## What stays visible

`public.ledger_trade_changes` records the source, the hidden reversal, and the optional replacement. Active feed, day summary, compensation summary, pending invoice sends, customer statistics, and `get_ledger_date_v1` summary and feed skip the source and the reversal on every session of that business date, including a later reopening of the same date. The replacement stays visible. Legitimate returns, exchanges, and count corrections that are not part of this change stay visible. `get_ledger_operation_page.server_sequence` and the date feed's `server_sequence` stay the maximum sequence, including hidden rows, so a live snapshot can tell that the day changed. Walking `next_before_sequence` does not skip a visible row when hidden rows sit at the head, between visible rows, or at the low end of a page. Journal lines, audit rows, and the original payload stay.

A full reversal copies each source line's milligram and count text and, when the source has version 2 pricing, that pricing object. Line prices and `purchase_obligation_piastres` stay on the stored source. The replacement is the reviewed draft, including its line prices, exact weights, and purchase obligation. A JSON-null tender array is unpaid: effects and the internal reversal treat it as no payment, and the stored source keeps the null array. Net cash, stock, scrap, and payable effects are the replacement totals minus the source totals, with sale cash and stock signs reversed from purchase. After both children, account balances and tracked lots must still match.

`get_daily_ledger_operation` adds optional `trade_change`. On the source that is `{action, replacement_operation_id?}`. On the reversal it also includes `role: "reversal"` and `source_operation_id`. The replacement is not marked. The original payload and its journals stay.

Purchase debt is not a new status. The reversal cancels the unpaid obligation through the existing purchase-return figures. The open debt list drops a fully cancelled payable. The full list can still show it as `settled` with `cancelled_amount` and remaining `0`.

New WhatsApp confirmation and presentation revision inserts on an inactive source raise `trade_inactive`. Brand and message source reads do the same. Dispatch state adds `trade_change` and `sendable: false` only for an inactive source. Historical presentation reads stay available and do not raise `trade_inactive`.

## Eligibility

Edit and delete apply only to a sale or purchase on the current open day. Anything else is `trade_not_editable`. No open day is `day_closed`. Linked returns, exchanges, purchase settlements, invoice-send confirmation, debt archives, gold obligations, a payable whose remaining differs from its initial amount, and another operation consuming a purchase lot are `trade_has_followups`. Selling from opening stock is not a purchase-lot follow-up. A sale's own lots are not a follow-up, because sale reversal creates return lots.

Insufficient net cash or stock is `negative_owned_balance`. A resulting tracked stock pair of zero weight with pieces, or pieces with zero weight, is `stock_pair_mismatch`. A positive cash delta whose cash-method account row is absent is `invalid_input`. Opening normally creates all four methods at zero, so collecting into one of those is valid. A stale token, hash, day, or day version on a still-active source is `stale_trade_review`. Review of an already changed source is `trade_inactive`. Missing or other-shop operations are `not_found`.

## Privileges

Authenticated execute is revoked from `post_daily_ledger_return(uuid, uuid, text)`, `post_linked_return_v1(uuid, jsonb)`, and `post_exchange_v1(uuid, jsonb)`. Remainder, compensation summary, and count-correction writes stay granted. Historic SQL fixtures may grant those three writers inside a transaction that rolls back. Concurrency fixtures that commit do so only on their disposable databases. Those grants are not production privileges.

New tables enable row level security without forcing it, so security-definer inserts still run as the owner. Authenticated users may select their own shop's rows and cannot insert, update, or delete. Audit rows are append-only. There is no client service key and no anonymous execute on the new commands.


## Read consistency and cached pages

`20261019233000_ledger_trade_cache_revision.sql` adds `trade_change_sequence` to `get_daily_ledger_v2`. It is the maximum immutable reversal operation sequence for the authenticated shop, as a decimal string, or `"0"`. Flutter discards previously loaded feed pages when that revision increases, including deletions outside the current head page. Ordinary posts retain the normal incremental merge.

The wrapper takes a shared shop-row lock before the legacy volatile read and its revision query. Financial writers already lock that shop row exclusively, so a response cannot pair a pre-change feed with a post-change revision. Permission is checked again after waiting. The original reader wrapper is not callable by authenticated users. Historical date reads are `STABLE`, preserving one committed snapshot across summary and page statements. Sequence watermarks include hidden operations for change detection; visible rows exclude them.

The Flutter operation route requests an unchanged **edit** preview before opening the editor. Using a delete preview there would incorrectly reject a zero-net edit when current cash cannot cover a full deletion. Historical unpaid purchase tender nulls normalize to an empty replacement tender array without modifying the stored source. Final effects are always obtained again after the user finishes the draft.

[Independent validation and Arabic RTL captures](../reviews/owner-feedback-ledger-functions-2026-10-19/validation.md) record the tested contract and deployment limits.

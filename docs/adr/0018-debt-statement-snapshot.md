# ADR 0018: selected debt statement snapshot

Status: owner-confirmed D31; implemented, separately reviewed, independently validated and deployed to development. Native/device/owner acceptance remains open.
Date: 2026-10-14. Decision owner: product owner in this implementation conversation.
Scope: Milestone 4 slice 7, PDF portion of DEBT-02.

The owner confirmed both D31 choices before dependent implementation: one selected standalone debt, purchase cash payable or gold obligation; current server-confirmed original, actually settled, cancelled and remaining amounts with complete relevant history as of a server-generated UTC snapshot. This is a bookkeeping snapshot (كشف حساب دين), not an invoice, payment receipt, legal acknowledgement or period/running-balance report. Party aggregation, matching by name/phone, CRM/repair imports, conversion and reminders remain excluded.

For a purchase of 60,000 with 20,000 paid initially, this statement starts at the 40,000 initial payable. A later 10,000 payment and 5,000 return cancellation appear separately, leaving 25,000. Gold retains its one original karat and exactly three decimal grams. Archived records retain remaining and history; authorized expired owners may read/export under ADR 0003 and D13.

A narrow additive versioned read RPC must return shop/header identity, complete sanitized history, exact invariants, server snapshot time and content freshness identity from one stable PostgreSQL statement snapshot. Existing v1 reads, commands, receipts, RLS and financial history remain compatible. No financial/status/export audit writes, copied debts or backfill are authorized. Rollback is a local schema verification gate; hosted rollout is additive and limited to reviewed necessary read-only additions on development xchapwvmvoefriqcxtvn.

The owner reviews generated PDF bytes before choosing supported save/share/system-print actions. Fresh authorized re-read and matching content identity are required before each handoff. Session/account/shop changes, revisions and reconnect discard stale previews and late replies while retaining financial/edit drafts and pending commands. External dialog handoff does not establish delivery or physical printing.

Acceptance requires separate read-only implementation review, independent client/SQL/RLS/concurrency/preservation validation, actual PDF page rendering and Arabic RTL light/dark phone/desktop review. Synthetic adapters do not close native device, printer or owner acceptance.

[Submitted prompt](../operations/next-slice-prompt.md), [accounting contract](0013-debt-balances-and-settlement.md), [design guide](../design-system.md).

[Independent validation](../reviews/debt-statement-pdf-2026-10-14/independent-validation.md), [development deployment/preservation](../reviews/debt-statement-pdf-2026-10-14/deployment.md), [completion](../operations/debt-statement-pdf-completion-status-2026-10-14.md).

# ADR 0019: debt calendar due dates and in-app reminders

Status: owner-confirmed D19/D32; implemented, separately reviewed, independently validated and applied to development. Native/device/owner acceptance remains open.
Date: 2026-10-14. Decision owner: product owner in this implementation conversation.
Scope: Milestone 4 slice 8, due-date/in-app portion of DEBT-02.

The owner accepted all three recommended choices together before dependent implementation. One optional calendar date belongs to one standalone debt, purchase cash payable or gold obligation, in its supported direction and original unit/karat. Server time in the current shop time zone establishes upcoming, due-today and overdue; overdue starts the next shop-local date. Past dates are allowed. There is no time of day, recurrence, grace period, installment amount or party aggregation.

For example, a 21K obligation with 3.125 g remaining and a due date of October 14 is due today on the shop's October 14, then overdue on October 15. Partial settlement or partial purchase-return cancellation retains the date for the remaining balance. Full settlement, zero remaining, cancellation and archive remove it from the active list while retaining readable metadata and append-only audit. Archive does not forgive remaining. Only non-archived positive balances allow date add/change/clear. A missing or cleared date has no reminder.

D19 accepts an owner-only list visible while authenticated for this slice. Native alarm/local notification delivery remains DEBT-03. Background, sound, lock-screen, app-closed delivery, providers and notification permissions are outside this contract. The in-app list does not fulfill the source's alarm request.

Date metadata has zero cash, gold, stock, custody and invoice effect and needs no open ledger day. A separate source-keyed metadata/audit/request contract checks the reviewed source, metadata version, shop time zone and local date under the existing shop-before-source lock order. Atomic success includes date/version, owner/server-UTC audit, exact original request/result and debt sync revision. Retries retain their exact envelope/key through the shared durable locker. Expired authorized owners may read/reconcile confirmed requests; new writes require active entitlement. Revoked/session/anonymous/cross-shop/admin implicit access and direct table writes remain denied.

Versioned STABLE reads derive remaining/status and dates in one server snapshot. Deterministic paging binds query/filter/order, time zone/local date and current content identity; invalidated cursors require explicit restart. No balances, contacts or original financial payloads are copied to metadata. Old debt/CRM/history/statement APIs and frozen receipts remain unchanged; metadata history stays separate. No backfill or default deadline is inferred.

Alternatives deferred: exact instants need DST/UTC/rescheduling decisions; native delivery needs platform/permission/background/multiple-device acceptance; closed/archived actionable reminders would change the confirmed lifecycle. Local migration transaction rollback/reapply tests schema compatibility; hosted date/audit history must be preserved rather than destructively rolled back.

Acceptance requires separate read-only implementation review, independent client/SQL/RLS/race/round-trip/preservation gates and actual Arabic RTL captures in both themes at 320/390/1440 widths with enlarged text and keyboard controls. Synthetic evidence does not close native/device/owner acceptance. Necessary reviewed additive development migrations only are authorized by the [submitted prompt](../operations/debt-due-dates-submitted-prompt-2026-10-14.md). No commit, push, publishing or production/release build.

[Existing accounting](0013-debt-balances-and-settlement.md), [statement contract](0018-debt-statement-snapshot.md), [design guide](../design-system.md).

[Independent validation](../reviews/debt-due-dates-2026-10-14/independent-validation.md), [development preservation](../reviews/debt-due-dates-2026-10-14/deployment.md), [completion](../operations/debt-due-dates-completion-status-2026-10-15.md).

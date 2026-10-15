# Milestone 4 slice 8 — debt dates and in-app reminders

Date: 2026-10-15. Implemented, separately reviewed, independently validated and applied to development xchapwvmvoefriqcxtvn. Native/device/owner acceptance remains open. Owner decisions and implementation began 2026-10-14.

The owner confirmed all three [D19/D32 choices](../adr/0019-debt-calendar-due-dates.md) before implementation. Selected debt detail has a compact live date row and reviewed add/change/clear. The workspace has an Arabic upcoming/due-today/overdue list, search, filters, exact remaining and deterministic complete pagination; each row opens existing detail. Gold remains at its original karat and three decimals; money is labeled نقد. No mixed-unit totals.

Server snapshots establish shop-local date/status. Atomic metadata commands require source/date/time-zone freshness, exact version, active entitlement and owner/session authorization, then save date, separate audit, original request/result and debt revision. Partial balances retain dates; zero remaining/closed/archive hides the active reminder but preserves metadata/audit. No open day or financial movement. Shared recovery preserves exact key/payload, foreign/unknown requests and expired confirmed reconciliation; late account/token replies are discarded. Sync/resume/reconnect retains drafts; stale pagination requires explicit restart.

[Independent validation](../reviews/debt-due-dates-2026-10-14/independent-validation.md): 1167 Flutter tests, clean analysis/format, React lint/38 tests/TypeScript, 12 extra calendar probes, 144 actual RTL/theme/width/text-scale captures and local SQL/RLS/round-trip/race/snapshot gates. [Development preservation/retirement](../reviews/debt-due-dates-2026-10-14/deployment.md) records exact hashes/counts, zero retained fixtures and a preserved independent sale during the interrupted session. Pre-existing financial/history hashes and legacy functions remain identical; do not interpret concurrent aggregate growth as a metadata effect.

Existing ledger/stock/custody/repair/debt/CRM/saved-number/history/PDF workflows and immutable invoices remain. [Exact submitted prompt](debt-due-dates-submitted-prompt-2026-10-14.md), unchanged [next-slice pointer](next-slice-prompt.md), dated planning copy and historical evidence preserved.

DEBT-03 native alarms/background/sound/lock-screen/app-closed delivery, providers, exact reminder time, recurring/snooze/installment/bulk schedules, repair deadlines and party aggregation remain excluded/planned. In-app lists do not fulfill alarm delivery. No notifications/messages, commit, push, publishing, production/release build, reset/history deletion.


Final independent documentation/preservation review: 1419 baseline files checked, zero missing, only 11 necessary existing files changed. Ten documents and all 280 local links reviewed; exact 49-table counts/hashes, the equal post-sale gate pair, pre-existing-history proofs, all 37 prior migration mappings, deployed hashes and zero-fixture retirement independently match evidence. Submitted prompts, historical records, prior migrations, theme tokens, React and PDF source remain byte-identical. Privacy/consistency and git diff --check pass. Ignored evidence: tmp/debt-due/independent-final-doc-review.json and independent-deployment-doc-check.json.


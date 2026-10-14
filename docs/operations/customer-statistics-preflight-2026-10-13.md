# CRM-02 preflight and confirmed rules

Date: 2026-10-13. Scope: Milestone 4 slice 4, customer statistics. Implementation and deployment have not started. The [implementation prompt](next-slice-prompt.md) remains the execution contract; [CRM-01/03 decisions](../adr/0014-customer-directory-notes-and-links.md) and historical evidence remain intact.

The owner confirmed these answers in the implementation conversation before any dependent calculation was implemented:

- Weights are net of confirmed returns, separately for each karat and direction. A customer purchase of 10.000 g at 21k followed by a 4.000 g return displays 6.000 g bought at 21k. Returning the remaining 6.000 g displays 0.000 g.
- An exchange return follows the original operation's current explicit customer association. A replacement contributes only through its own explicit association. Returning 4.000 g at 21k and replacing it with 3.000 g at 18k subtracts 4,000 mg from the original linked customer's 21k total; the replacement adds 3,000 mg at 18k only to its separately linked customer. No name/phone inference or automatic replacement attribution is permitted.
- Each qualifying linked sale or purchase counts once, including after partial or full returns. Returns do not add a sale/purchase count. A separately linked replacement counts once. Confirmed returns qualify for last activity and its shop-local date/time.

Customer purchases correspond to shop sales; customer sales to the shop correspond to shop purchases. Current explicit links define the summary boundary, including returns to their linked originals. Unlink removes the original and its returns from the current summary; a reviewed relink attributes them to the new customer while retaining prior association/audit history. Archive preserves authorized summary reads. Totals describe linked activity, not inferred lifetime history. Integer milligrams and three-decimal gram display remain mandatory.

## Delegation availability and authorization boundary

The requested grok-delegate read-only availability probe used `C:/Users/Aqsa/.grok/bin/grok.exe`, Grok 1.0.50 (c58f321264ba), via its bundled relay. It ran from 2026-10-13T17:40:18.171Z to 17:40:24.252Z and failed with exit 1, HTTP 402, `Grok Build usage balance exhausted`. No final message, session ID or token usage was returned. `readOnlyViolation` is false; the five preexisting dirty paths are unchanged. Exact ignored evidence: `tmp/customer-statistics/grok-availability/result.json` and `events.jsonl`.

The prompt explicitly requires direct implementation authorization when delegation is blocked. That authorization was requested and is pending. No Codex fallback implementation, migration, deployment, synthetic-account activation, financial posting, commit, push, publishing or build has occurred in this preflight.

The connected Supabase plugin read the specified development project and its migration list: project status ACTIVE_HEALTHY, PostgreSQL 17.6.1.166, 34 hosted migrations, ending with `customers_crm` version 20261013164251. This is an inventory read, not a new source/hash reconciliation or a deployment. Existing [migration mappings](../reviews/customers-2026-10-13/migration-mappings.md) remain historical. No synthetic actor was activated; retirement is not applicable to this preflight.

Read the local PAGES customer text directly: five-karat bought/sold weights, sale/purchase counts, last operation/date, and grams ahead of prices. Applied ui-ux-pro-max's focused Flutter text-scaling search as preparation; existing shared themes remain authoritative. No application behavior changed, so application validation gates were not rerun. Documentation review passed: all three local links resolve, no credential-shaped values or trailing whitespace, and status is consistently preflight only. `git diff --check` passed.

## Subsequent implementation authorization

After this preflight, the owner answered “Authorize Codex to implement directly”. The pending boundary above is historical. Codex completed the authorized CRM-02 scope under the confirmed rules, with [validation](../reviews/customer-statistics-2026-10-13/independent-validation.md) and [development deployment/retirement](../reviews/customer-statistics-2026-10-13/deployment.md). The original Grok failure evidence remains intact.

# Customer statistics from explicit confirmed links

Status: owner-confirmed CRM-02 rules; implemented, independently validated and deployed to development; native owner acceptance remains open. Date: 2026-10-13.

The owner confirmed [the accounting examples](../operations/customer-statistics-preflight-2026-10-13.md) before implementation and authorized Codex to implement directly after Grok returned HTTP 402. [CRM-01/03](0014-customer-directory-notes-and-links.md) remains intact.

Bought means the customer's purchases (shop sales); sold means the customer's sales to the shop (shop purchases). Each karat has an independent integer-milligram net total: original measured lines minus confirmed returned quantities. No cash, price, profit or karat conversion is included. Purchase routing does not count receipt/stock and scrap allocations twice.

Current active explicit links are authoritative. Originals require shop, sale/purchase kind, immutable detail and matching confirmation audit evidence. Returns require the same shop, matching original/kind, detail and their own confirmation audit. Exchange returns follow the original's current link; replacements require separate explicit links. Parent exchange envelopes add no weight or count. Each original/replacement counts once even after full return; returns qualify for last activity without increasing counts. Equal timestamps use the server shop sequence. File-update time remains separate.

Unlink removes the original and its returns from the current summary. A reviewed relink assigns them to the new customer; old links and audit history survive. Archived files retain authorized reads. Zero weight with a retained count is distinct from no linked activity. Labels explicitly limit coverage to linked confirmed operations, not lifetime history.

Additive v2 list/detail RPCs preserve v1 reads, commands and immutable receipts. Summaries are computed live in the read transaction without a cache or background worker; line totals and operation counts are aggregated separately. The list remains one bounded server request. A return-reference index supports current-link reads. Private helpers have no client execution grants; v2 RPCs reuse the owner/session reader and grant authenticated execution only. Platform admins have no shop authority; expired entitlement reads remain allowed, revoked/lost sessions denied.

Customer association changes refresh through customer scope; confirmed financial events refresh through ledger scope. Location/subscription changes and reconnect also refetch authoritative summaries while preserving stale drafts and review blocking. Server UTC establishes ordering; shop-zone timestamps establish display. UI uses Arabic RTL, isolated numeric/date values, three-decimal grams, shared tokens, compact 18/21/24 bought summaries and full 14/18/21/22/24 detail.

[Independent validation](../reviews/customer-statistics-2026-10-13/independent-validation.md) and [deployment/retirement](../reviews/customer-statistics-2026-10-13/deployment.md) record the exact results. Versioned read functions use stable statement snapshots; a two-connection test proves consistency across an association correction and freshness on the next read.

# Milestone 0 discovery packet

Milestone 0 status: **open**. The product owner confirmed a greenfield, multi-customer subscription service and approved the three local Word files as the initial working requirements. They may evolve through recorded product decisions and requirements-matrix changes. No deployed legacy application or historical import is required. The external annex was not compared; that comparison is a contract-record follow-up, not a development gate.

## Packet contents

| File | Purpose |
| --- | --- |
| [Greenfield scope inventory](greenfield-scope-inventory.md) | Intended screens and features from the source files, compared with the starter repository |
| [Source reconciliation](source-reconciliation.md) | Agreement-body technical scope traced to the local Word files, with conflicts and open meaning |
| [Financial worked examples](financial-worked-examples.md) | Synthetic sale, financed purchase, trader receipt, and day-close posting cases awaiting shop-domain approval |

BASIC, LEDGER, and PAGES name the three agreed local Word files. AGREEMENT names the technical clauses of the local PDF. The original files, commercial details, party identity, and annex address remain outside Git. Drawings in the Word files are design inputs, not approved pixel targets. The repository currently contains Flutter and React shells and connection checks, without ERP workflows, migrations, RLS policies, financial commands, or upload endpoints.

## Confirmed and open

| Topic | State |
| --- | --- |
| Product start | **Confirmed:** build from scratch; no deployed app or legacy export |
| Customer model | **Revised 2026-09-26:** one subscription covers one shop and its single owner account. Staff invitations and per-user grants are removed ([ADR 0003](../adr/0003-owner-only-shop-access.md)). The 2026-09-24 invited-staff reading of D28 is historical |
| Working requirements | **Confirmed:** three local Word files; changes must update this guide and the requirements matrix |
| External annex | Uncompared; record a named revision privately if supplied, without blocking the agreed working scope |
| Financial examples | Draft; numerical and custody assumptions await a shop-domain expert's signature |
| New-shop opening | Decide zero start versus signed opening count and authorized opening operation |
| Invoice numbering | D23 open |
| Scope disposition | Assign build, defer, or change and target release to each inventory row |
| Source conflicts | C1-C6 in source reconciliation require product decisions before dependent financial/UI implementation |

## G0 acceptance checklist

- Approved scope matrix gives each launch requirement an owner, screen, server command, permission, acceptance test, and release.
- Greenfield inventory has build, defer, or change disposition and target release for every surface.
- New-shop opening policy and invoice numbering are approved.
- A shop-domain expert signs the sale, three-party financed purchase, trader receipt, and close-day worked examples, including cash by method, grams by karat, counts, custody, ownership, and obligations.
- Private source documents and customer data remain outside Git.

This packet prepares the decisions; the blank signatures and dispositions mean G0 is still open.

## Next workshop

Review the inventory for launch scope, then settle currency and pricing (D02), count and karat policy (D03-D04), financing and custody (D05-D07), day close and corrections (D08-D09), permission scopes (D10), mockup targets (D12), invoice numbering (D23), and the profit-card meaning (D26). Approve or correct the worked examples. Specify how a new shop subscriber and staff are invited and how a shop establishes opening balances. Record remaining answers in [decisions](../decisions.md) and [the requirements matrix](../requirements-matrix.md).

Engineering can start Milestone 1 identity, tenancy, RLS scaffolding, design tokens, and prototype work while financial-rule decisions are made. No financial posting behavior is claimed accepted until its examples and policies are approved.

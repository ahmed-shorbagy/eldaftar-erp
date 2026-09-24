# Milestone 0 discovery packet

Milestone 0 status: **open**. This packet is workshop evidence. It is not acceptance, and it does not complete Milestone 0.

G0 in [the delivery plan](../delivery-plan.md) still needs an approved legacy parity and import map, an invoice numbering rule, and signed paper posting examples. Those signatures are blank in [the worked examples](financial-worked-examples.md). The hosted agreement annex was not compared. Comparison status: **PENDING**.

## What this packet is for

The four files prepare the product-meaning gate before any financial migration:

| File | Job |
| --- | --- |
| [Legacy parity](legacy-parity.md) | Screen and feature inventory, Git starter versus source scope, deployed app marked UNVERIFIED, blank owner disposition, export questions, opening-balance inputs |
| [Source reconciliation](source-reconciliation.md) | Agreement technical scope traced to the local Word files and the requirements matrix, with conflicts, additions, and ambiguous behavior |
| [Financial worked examples](financial-worked-examples.md) | Synthetic sale, mixed-tender sale, financier purchase, later trader recognition, and a post-midnight close, with units that add up |
| This file | Evidence register, acceptance checklist, workshop agenda, and owner input |

Source roles follow [product scope](../product-scope.md): BASIC (core problems and goals), LEDGER (daily ledger behavior and embedded drawings), PAGES (page-by-page requirements), AGREEMENT (technical clauses in the root PDF). Commercial clauses, party identity, and the annex address are intentionally absent from Git.

## Evidence register

| Evidence | What this session did | Result |
| --- | --- | --- |
| [AGENTS.md](../../AGENTS.md), root [README.md](../../README.md), [docs index](../README.md) | Read | Repository rules and starter status confirmed |
| [Product scope](../product-scope.md), [requirements matrix](../requirements-matrix.md), [delivery plan](../delivery-plan.md), [database design](../database-design.md), [decisions](../decisions.md) | Read | Milestone 0 definition, requirement IDs, proposed journal units, open decisions D01–D27 |
| BASIC, LEDGER, PAGES | Read the local Word files, including embedded drawings | Screen and workflow statements captured below and in the sibling files. Drawings are design inputs |
| AGREEMENT | Read the local PDF technical clauses | Body scope, stage outline, and annex pointer captured in [source reconciliation](source-reconciliation.md). One PDF page has no technical text |
| Hosted annex named by the agreement | Not opened | **PENDING**. Not treated as equal to the local Word files or to the agreement body |
| `app/`, `admin/`, `supabase/` source | Inspected directories, client shells, manifests, and the connection script | Starter only. Detail in [legacy parity](legacy-parity.md) |
| Deployed or legacy ElDafttar application | Not observed | **UNVERIFIED** on every parity row |
| Ignored local secrets (`app/config/local.json`, `admin/.env.local`, `supabase/.env.local`) | Not read | Unused as evidence |
| Build and test commands | Not re-run | This pass is documentation. Existing test files are listed in legacy parity; their latest result is not claimed here |
| Live Supabase or R2 | Not contacted | Connection scripts remain network checks, not schema or product proof |

## Verified in this session

- The Git tree contains an Arabic RTL Flutter shell for Android, iOS, and Windows, an Arabic RTL React admin shell, and a Supabase/R2 connection script.
- Authoritative ERP behavior is absent from that tree: no shop workflows, authentication flow, migrations, RLS policies, financial commands, or upload endpoint.
- Local BASIC, LEDGER, PAGES, and the agreement body were available and were read.
- LEDGER and PAGES contain embedded screen drawings. Their sample totals do not agree with each other. They are not posting fixtures. The arithmetic is in [source reconciliation](source-reconciliation.md).
- The paper examples in [financial worked examples](financial-worked-examples.md) were written to balance in integer minor units, milligrams, and counts. Approval rows are blank.

## Pending

- Hosted annex version comparison (D27).
- A walkthrough or export of the deployed application (D01). Every deployed-app cell is UNVERIFIED.
- Owner disposition on each parity row: keep, replace, migrate, or retire.
- Signed worked examples and a shop-domain correction of any assumption marked in those examples.
- Opening balances from a real count. The input list exists; the figures do not.
- Decisions D01–D26. None are marked accepted in [decisions](../decisions.md).
- Invoice numbering rule (D23), profit-card meaning (D26), and category-karat rules (D03, D04).

## Acceptance checklist

Criteria are the Milestone 0 acceptance block in [the delivery plan](../delivery-plan.md).

| Criterion | Packet state | Met |
| --- | --- | --- |
| Signed scope matrix: every requirement has an owner, screen, server command, permission, and test | [Requirements matrix](../requirements-matrix.md) has stable IDs and milestone targets. It has no owners, commands, permissions, or passing tests. Repository commands for these workflows do not exist | No |
| Screen-by-screen parity matrix labeled keep, replace, migrate, or retire | Inventory is drafted. The disposition column is unfilled. Deployed behavior is UNVERIFIED | No |
| Reconciled opening balances designed | Units and input fields are listed. No source totals were supplied, so nothing is reconciled | No |
| Private source documents stay out of Git | This packet records behavior and decisions without copying the Word files, the PDF, party details, or the annex address | Yes, for this packet only |
| Shop-domain expert signs one sale, one three-party financed purchase, one trader receipt, and one day close | Drafts exist, including an extra mixed-tender sale. Signature fields are blank | No |

One satisfied row does not close the milestone.

## Workshop agenda

Audience: product owner and a shop-domain expert, with engineering recording the answers. Bring an anonymized paper day, a financier story the shop actually uses, and whoever can export or demonstrate the deployed app. Target about two hours. Stop when a decision is still unknown and mark it unresolved.

1. **Sources (10 minutes).** Confirm that the local Word files are the working set, that the hosted annex is still unread, and that this repository is a starter. Deployed behavior stays UNVERIFIED until someone demonstrates it.
2. **Parity pass (25 minutes).** Walk [legacy parity](legacy-parity.md). Fill keep, replace, migrate, or retire. Name the export path and the person who will produce it. List legacy screens that PAGES treats as already shipped, including the analytics defects PAGES says exist.
3. **Simple money and gold (20 minutes).** Review cases 1 and 2 in [the worked examples](financial-worked-examples.md). Accept or replace the currency minor unit, per-line prices, piece counts, and the refusal to publish a profit figure (D02, D03, D24, D26).
4. **Financier purchase (20 minutes).** Choose case 3A, case 3B, or a corrected variant. State who pays the customer, who owns each gram, who holds each gram, and who owes whom (D05, D07, D16).
5. **Trader receipt (15 minutes).** Review case 4. Decide whether “added manually” is only a status change or a checked link that must not post the grams twice (D06).
6. **Midnight close (15 minutes).** Review case 5. Decide whether counted cash replaces the books, who may close, and what happens to a post that arrives after the seal (D08, D09, D10).
7. **Carry-out (10 minutes).** Initial the rows that are actually accepted. Leave the rest blank. Schedule the annex comparison and the legacy export before G0 is declared.

## Owner input needed before G0

Answers below are empty on purpose.

| Input | Decision | Answer |
| --- | --- | --- |
| Where the deployed app runs, and who can give a read-only demonstration | D01 | |
| Export of cash by method, grams and counts by karat, scrap, trader balances, customer debts, repair custody, and unrecognized receipts, with the as-of moment | D01 | |
| Which parity rows are keep, replace, migrate, or retire | D01 | |
| Shop currency, minor-unit exponent, workmanship, tax, discount, and per-line versus invoice-total pricing | D02 | |
| Piece, lot, or aggregate tracking, and whether any balance may go negative | D03 | |
| Bullion and coin nominal weights versus weighed milligrams, and stock versus scrap routing | D04 | |
| Signed three-party purchase: payer, owner, custodian, obligations | D05 | |
| Trader receipt meaning, and the manual-stock link rule | D06 | |
| Debt and trader units, and whether money and grams ever convert inside one operation | D07 | |
| Business-day timezone, close, reopen, and posts after midnight or after seal | D08 | |
| Returns and corrections after close or after invoice dispatch | D09 | |
| Who sees shop totals, other employees' operations, and phone numbers | D10 | |
| What WhatsApp “sent” means | D11 | |
| Which drawings, if any, are pixel targets, and for which widths | D12 | |
| Invoice number format and legal lines | D23 | |
| Whether historical payment-method labels stay fixed after a rename | D24 | |
| Sign-in identifier and invitation check | D25 | |
| Profit formula, or an Arabic label for net cash movement, or no such card | D26 | |
| Confirmation that a named annex revision was compared in private, with differences recorded outside Git | D27 | |

D13–D15, D18–D22 also block later milestones. They are listed in [decisions](../decisions.md). They are not required to draft these paper examples, and they remain open.

## Recommendations

These are engineering recommendations for the workshop. They are not product decisions, and they do not fill the disposition or approval fields.

- Compare the hosted annex in private before anyone signs the scope matrix. Until that happens, treat agreement-body text and the local Word files as two inputs.
- Inventory the deployed application before freezing features. PAGES says the new work extends an existing application.
- Keep the profit card out of the ledger until D26 names a formula. One drawing’s sales-minus-purchases figure is not that formula.
- When a financier takes the gold, leave shop-owned saleable stock and shop-owned scrap unchanged, as case 3A illustrates.
- Use the worked examples as the discussion sheet. Replace any figure the shop expert rejects, and sign the replacement. An unsigned sheet is still a draft.
- Keep opening balances as a dedicated opening operation once the export exists. This packet does not invent those balances.

## Related baseline

- [Product scope](../product-scope.md)
- [Requirements matrix](../requirements-matrix.md)
- [Delivery plan](../delivery-plan.md)
- [Database design](../database-design.md)
- [Decisions](../decisions.md)

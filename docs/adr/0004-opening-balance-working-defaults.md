# ADR 0004: opening-balance working defaults

- Status: user-authorized working defaults for the Milestone 2 opening slice, dated 2026-09-26. Not a shop-domain signature. D02, D03, D04, D08, and G0 remain open.
- Date: 2026-09-26
- Decision owner: product owner authorization to proceed with recorded recommendations. No shop-expert signature.
- Supersedes: none. ADR 0003 still governs owner-only access.

## Context

D01 accepts a greenfield shop and asks how that shop establishes opening balances. Currency minor units, aggregate versus piece tracking, bullion and coin denominations, and the full open/close/reopen rule are still unsigned. The local Word files name the four cash methods, worked-item and bullion and coin examples, scrap beside saleable stock, and a manual day close because work can continue after midnight. They do not define piastres, integer milligrams, an opening catalog, or a time zone name. Three decimal gram places are required by AGENTS.md and product scope. `Africa/Cairo` is the shop time-zone default already stored by the registration migration. Balanced journals and the zero-or-one idempotent opening are proposals in database design; this slice adopts them as user-authorized recommendations, not as Word facts. Staff text in the Word files is superseded by ADR 0003.

The opening command cannot wait for a decision workshop. The user authorized recommended defaults on 2026-09-26 so the slice can proceed. The blank approval rows in the worked examples stay blank.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| Wait for signed examples | Closer to G0 | Blocks the first financial migration on open D02, D03, D04, and D08 |
| Store pounds and grams as binary floating point | Matches some drawings | Breaks exact cash and three-decimal gram identity |
| Integer piastres, integer milligrams, and the opening catalog in the contract | Exact units, one idempotent command, reversible later by a new ADR | Does not settle tax, valuation, denominations, or day close |

## Decision

For this slice only, use the contract in [opening-balance-contract.md](../operations/opening-balance-contract.md):

- One currency, EGP. Store piastres as `bigint`. Display two decimal places. No tax, workmanship, discount, or second currency in the opening command.
- Store gold as integer milligrams. Display three decimal gram places. Counts are integers. Scrap has no count.
- The opening catalog is worked jewelry at 14, 18, 21, and 22, bullion at 24, coins at 21, and scrap at 14, 18, 21, 22, and 24. This is an opening-only reading of conflict C3. It does not accept D03 or D04.
- The owner of an active shop confirms once, including an explicit all-zero confirmation. That confirmation opens one `Africa/Cairo` business day. Close and reopen stay outside the slice, so D08 stays open.
- Journals balance inside one unit family. Opening clearing is a mechanical offset, not profit or capital.
- Clients send and receive quantities as canonical integer strings. The UI converts pounds and grams before the call. The payload has no shop id. Ledger JSON carries `read_model_version` 1 so the client parses a versioned DTO. Balances are the sum of postings through a `security_invoker` view. `get_daily_ledger` is a third, read-only RPC.

These statements are recommendations. They do not mark D02, D03, D04, D08, or G0 accepted.

## Data and compatibility impact

A later additive migration creates the tables, the confirmation RPC, and the two read-only RPCs named in the contract. No historical migration changes. Existing shops, if any, have no financial rows until the owner confirms. Old clients gain no financial screen until the Flutter task ships. Rollback of a failed confirmation discards the key and every financial row of that attempt. A committed opening is not deleted by a client.

## Verification

Later tasks test the synthetic example, bigint overflow, RLS, replay, and the Cairo date rule. This ADR does not claim those tests have run. Shop-expert approval rows stay empty.

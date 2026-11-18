# ADR 0050: Weights are entered and shown with two decimals

Status: implemented in the Flutter client on 2026-11-18. No schema, RPC, or Edge Function change, so nothing was deployed. Owner acceptance is open. [Validation](../operations/owner-feedback-2026-11-17-validation.md).
Date: 2026-11-18
Owners: product owner and engineering reviewer
Related requirement IDs: LED-01, INV-01, REP-01. Source: owner voice notes of 2026-11-17 (FB-002) and the developer's approval of 2026-11-18 (plan, decision 1).
Supersedes: the display rule of [ADR 0004](0004-opening-balance-working-defaults.md) («Display three decimal gram places») and [ADR 0047](0047-owner-answers-2026-11-11.md) D7 («A stored third decimal stays visible»). Storage as integer milligrams stays as ADR 0004 defines it. The rule in `AGENTS.md` was changed in the same commit.

## Context

The owner weighs to two decimals and has said so four times. The old app shows every weight with two decimals. This app stored milligrams and showed them in three ways: two decimals on the ledger, three decimals in reports, statements, the invoice, repairs and inventory, and two decimals plus a milligram figure («1.26 جرام (1,255 ملليجرام)») on confirmations. Fields carried hints such as «ثلاث خانات، مثل 1.255» and «حتى منزلتين عشريتين». About twenty separate formatters produced this.

Example. A ring of 5.25 g is sold. The owner types 5.25 and reads 5.25 on the review, the ledger, the invoice, the report and the WhatsApp message. He never reads 5.250.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| Keep three decimals where «exact» mattered | No change to reports and invoices | The owner's rule stays broken in half the app |
| Change storage to centigrams | Storage matches display | A migration over every weight column and RPC; installed older builds send milligrams ([ADR 0044](0044-owner-answers-2026-11-10.md) C-D1) |
| Keep integer milligrams, enter and show two decimals everywhere | No migration; old builds keep working; one rule | Weights stored earlier with a third decimal need a display rule |

## Decision

1. **Display.** Every weight is written as grams with two decimals: screens, review and confirmation steps, PDFs, the invoice, and message text. No third decimal and no milligram figure is shown anywhere.
2. **Entry.** Every weight field accepts at most two decimals, with Arabic or ASCII digits. A third decimal cannot be typed or pasted, and the domain rejects it. A written third digit that is zero («1.830») is read as the same weight.
3. **No hints.** Fields carry no decimal-places hint.
4. **Storage.** Weights stay exact integer milligrams. Sums and conversions are computed in milligrams and rounded once for display, so a total may differ from the sum of its displayed rows by 0.01.
5. **Weights stored earlier with a third decimal.** They are not rewritten. They are shown rounded half away from zero (1.255 reads 1.26). The owner reads a recorded weight with two decimals, so entering what he reads means that weight itself: a field left as shown keeps the recorded weight, and a return, settlement, removal or count entered at the shown weight takes the whole recorded weight. A weight he really changes is stored as typed.
6. **Last piece ([ADR 0047](0047-owner-answers-2026-11-11.md) D1).** The banner is not shown when the difference is below what two decimals show. The server rule is unchanged.
7. **Catalog nominal weights** of coins and bullion are data, not entry, and keep their stored value even where it carries a third decimal. A suggested weight is shown with two decimals like any other.

One formatter and one input carry the rule. `twoDecimalGrams` in `app/lib/src/features/daily_ledger/domain/quantities.dart` does the rounding with integer arithmetic; `displayGrams`, `displayMilligrams` and `displayGoldEffect` in `app/lib/src/theme/amount_format.dart` are the display entry points; `GramInputFormatter`, `gramFieldText` and `readGramField` in `app/lib/src/theme/gram_input.dart` are the field entry points. The feature formatters (`customerGrams`, `signedGramsText`, `debtGold`, `statementGold`, `gramsOf`, `repairWeight`, `reportGrams`, and the private helpers in the operation, return, correction and invoice code) now delegate to them. `repairGramsExact` and the `exact:` switches are removed.

## Data and compatibility impact

- No schema, RPC, or Edge Function change. The wire still carries integer milligrams. Installed older builds keep working and may still send a third decimal; this build shows such weights rounded.
- On development `xchapwvmvoefriqcxtvn` on 2026-11-18, three shops created between 2026-09-27 and 2026-10-13 hold weights with a non-zero third decimal: 8 gold postings, 6 gold balances, 6 lot movements, 4 lots, 1 receipt, 6 repairs and 2 gold debts. The two test shops of 2026-11-18 hold none. Nothing was rewritten.
- A day close that counts a balance stored with a third decimal accepts the shown weight as that balance, so no 0.005 g difference is raised.
- The admin dashboard shows no weights and is unchanged.
- Rollback is a client rollback. No data is rewritten.

## Verification

- `app/test/two_decimal_weights_test.dart`: rounding, sign and grouping; every formatter gives the same two decimals; no milligram figure; entry of at most two decimals with Arabic digits; the field refuses a third decimal; a recorded third-decimal weight is kept when left as shown and replaced when changed; a source scan that fails on a three-decimal formatter, a milligram label, or a decimal-places hint in `app/lib`.
- `app/test/owner_answers_2026_11_11_test.dart`: no last-piece notice for a difference two decimals do not show.
- Existing tests that asserted three decimals or milligram text were changed to the rule. Counts, device proof and limits are in the validation record.

# ADR 0049: The daily ledger opens without an opening-balances form

Status: implemented in the Flutter client on 2026-11-18. Not committed. No schema, RPC, or Edge Function change, so nothing was deployed. Owner acceptance is open. [Validation](../operations/owner-feedback-2026-11-17-validation.md).
Date: 2026-11-18
Owners: product owner and engineering reviewer
Related requirement IDs: LED-01, INV-01. Source: owner voice notes of 2026-11-17 (FB-006, FB-022) and the developer's approval of 2026-11-18.
Supersedes: the client entry step of [ADR 0004](0004-opening-balance-working-defaults.md) («The owner of an active shop confirms once, including an explicit all-zero confirmation»). The opening command, its units, its idempotency, and the business day it opens stay as ADR 0004 defines them.

## Context

A new shop used to open on «إعداد الأرصدة الافتتاحية»: cash per payment method, stock by category and karat, scrap by karat, then a review and a confirmation. The owner rejected it on 2026-11-17: «أنا مش عاوز الدفتر اليومي أول ما أخش … يعمل لي حوار إن هو أدخل الحاجة». He wants the daily ledger to open as it does in the old app, which has no setup step. In the old app, cash and weights are entered from «جرد فوري» with «اضافة او تعديل نقدية» and «اضافة او تعديل وزنة».

The form also forced stock to be entered under the category «مشغولات» with no item name, which the owner rejects as a concept, and it produced the unnamed pooled lot «رصيد افتتاحي (بدون صنف)» on every new shop.

Example. A shop is activated today. Before: the owner must fill or zero the form before he can record a sale. After: the owner taps «الدفتر» and sees the daily ledger with zero cash and empty sale and purchase books, and can record a sale at once.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Keep the form and add a «تخطي» button | Smallest change | The setup screen is still the first thing the owner sees, and «مشغولات» stays in it |
| B. Remove the form. The owner's app confirms a zero opening by itself, through the existing command | No server change. Old installed builds keep working. One command, one stored key, as before | Starting cash and gold must be entered elsewhere; see «Data and compatibility impact» |
| C. Open the shop on the server at activation | No client step at all | A migration and a change to subscription redemption for the same visible result; a shop activated before the change still needs the client path |

## Decision

Option B.

- The opening-balances form, its review, and its «تأكيد أرصدة صفرية» button are removed from the app. No screen asks for opening balances.
- When the owner of an active shop reaches the daily ledger and the shop has no confirmed opening, the app sends the existing `confirm_opening_balances` command with every cash method at zero and no stock or scrap. Nothing is reviewed first, because the command changes no cash and no gold. The command keeps its stored idempotency key, so a lost reply is reconciled on the same key and the opening is never posted twice.
- While the command is in flight the ledger shows its loading bar. On success it shows the daily ledger. Nothing is presented as open until the server confirms it.
- If the attempt fails, the owner sees «تعذر فتح الدفتر» with «إعادة المحاولة». If the reply is unknown, he sees «جارٍ فتح الدفتر» with «إعادة المحاولة». The app tries by itself once per visit and does not repeat on every sync.
- Only the owner opens the shop. A partner or employee who arrives first sees «لم يفتح صاحب المحل الدفتر بعد.» and posts nothing. Their screen moves to the ledger on the next sync after the owner has opened it.
- An expired or pending shop is not opened. It shows «لم يُفتح دفتر هذا المحل بعد.».
- Where cash and gold are entered after opening is not decided here. See the open question below.
- Not yet seen by the owner: the automatic zero opening, and the wording of the waiting and retry states. They follow from his request but are engineering choices.

## Data and compatibility impact

- No schema, RPC, or Edge Function change. The command and the audit record are the ones a zero confirmation always produced: actor, server time, one business day opened.
- Shops that already confirmed an opening are unchanged, whatever their balances.
- Installed older builds still show their form and can still confirm an opening with balances. The server accepts both.
- A new shop no longer gets a pooled opening lot without an item name.
- **Open question for the owner.** Gold can be added today from «الجرد الفوري» with «إضافة مخزون». There is no simple way to enter starting cash: cash only changes through sales, purchases, expenses, transfers between methods, and the counted correction at day close. The owner asked for the form to go; he did not say where starting cash and gold should be entered instead. The old app's «اضافة او تعديل نقدية» is one answer, and `post_ledger_correction_v1` could carry it without a migration, but nothing is built until he answers.
- Rollback is a client rollback. No data is rewritten.

## Verification

- `app/test/ledger_opens_directly_test.dart`: the owner of a new shop reaches the open ledger; the payload is exactly a zero opening; an open shop is not opened again; staff and readers the server does not allow post nothing; an expired shop is not opened; a failed attempt is not repeated by itself; a lost reply is reconciled on the same key.
- `app/test/daily_ledger_widget_test.dart`: a new shop shows the ledger and nothing of the old form (no «الأرصدة الافتتاحية», «مشغولات», or «منازل» text and none of its fields); staff wait and then see the ledger; the retry opens the ledger on the same key.
- `app/test/daily_ledger_busy_test.dart`: a sync during the opening sends one command.
- Device run and gates are in the validation record.

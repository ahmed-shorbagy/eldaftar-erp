# ADR 0040: Trade entry, invoice PDF, and customer WhatsApp

Status: implemented in the Flutter client on 2026-11-08. Not committed. No schema, Edge Function, or R2 change, so nothing was deployed. Android, iOS, and Windows device acceptance remain open. [Validation](../operations/owner-feedback-2026-11-06-validation.md).
Date: 2026-11-08
Owners: product owner and engineering reviewer
Related requirement IDs: SALE-01, SALE-02, SALE-03, PUR-01, CAT-01, SET-04. Amends [ADR 0022](0022-invoice-message-templates.md) on Egypt-only WhatsApp numbers and text-only handoff. Keeps [ADR 0006](0006-owner-confirmed-whatsapp-dispatch.md): opening WhatsApp never marks the invoice sent.
Supersedes: none.

## Context

On 2026-11-06 the owner asked for the sale and purchase form to match how the shop works: purchased jewelry is scrap, karats are shown with 18 and 21 first, a line can have its own price, the invoice carries the shop name and not the internal note, and one button sends the PDF and the message to the customer’s WhatsApp. Customer phones need a country, defaulting to Egypt. Coin and bar counts stay locked after the picker. «أخرى» is a short list, and «صنف جديد» lives in الجرد الفوري.

## Decision

Purchased jewelry is booked as scrap at its karat. Coins and bars stay their own stock. Exchange replacements keep the category the owner chose. A historical purchase line that is still worked jewelry is not rewritten.

Choice lists show karats in the order 18, 21, 24, 22, 14, limited to the karats that category allows. Wire indexes, metric ids, and payload sorts stay as they were.

«سعر لكل صنف» is optional. The shop’s choice is remembered. Editing an operation that already has line prices turns the switch on for that screen and does not change the saved choice. All lines are priced or none are, and the sum must equal the invoice total.

Invoice PDFs print the shop name. They do not print the internal note. The counterparty box is labeled «العميل» for a sale and a purchase. The description still prints.

The invoice message default is the three-line Arabic template in the 2026-11-06 plan. The renderer version is 2. «المزيد» → «الفاتورة» includes «رسالة الفاتورة» for the owner. WhatsApp numbers are the digits of `normalizeCustomerPhone`, so Egypt and international numbers both work. A bare `2010…` without `+` is not a number.

One primary button, «إرسال الفاتورة PDF على واتساب», builds the same PDF as the print action and hands it to the platform share:

- Android shares the PDF into WhatsApp or WhatsApp Business with the customer `jid` when the number is known.
- iOS opens the system share sheet.
- Windows opens the chat and highlights the PDF under Documents\الدفتر\الفواتير for the owner to drag in.

If WhatsApp is missing, the system share sheet is the fallback. «نعم، أُرسلت» remains a separate owner confirmation.

Customer, debt, and trade phone fields use a country list that starts with Egypt. The stored value is E.164. Empty is allowed where the form already allowed an empty phone. Staff, shop-profile, and registration phones are unchanged.

After the coin or bar picker, the count is read-only and opens the picker again. Weight stays editable. The weight helper sentence is removed. The picker keeps the chosen quantities in a footer above the total.

«أخرى» is a dense grid of the thirteen default names, then the shop’s own products. «صنف جديد» is only on الجرد الفوري. «المزيد» shows the app version when the app has one.

## Data and compatibility impact

No migration, RPC, or Edge Function. Money and grams stay integer piastres and milligrams. The message renderer version moves from 1 to 2; a saved custom template is unchanged, and a null template uses the new default. Android adds a cache FileProvider for invoice PDFs. Opening WhatsApp still does not write a dispatch row.

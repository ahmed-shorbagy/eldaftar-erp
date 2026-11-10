# Owner answers, batch 2 (2026-11-10)

Source: ten voice notes from the owner, the last answers to the seven questions about the 2026-11-09 voice notes. No screenshots. The owner says every question is now answered and he is available for more. Batch 1: [owner-answers-2026-11-10-batch-1.md](owner-answers-2026-11-10-batch-1.md). Old app: [reference and screenshots](../reference/old-app-2026-11-10/README.md).

## Answers

| # | Owner said | Compared with the build on development | Work |
|---|---|---|---|
| B1 | Phone countries: Egypt, Libya, Sudan, the whole Gulf, Yemen, Jordan, most Arab countries. A customer's phone defaults to the country of the merchant's own registered number (a Saudi merchant gets Saudi). | Customer phone fields default to Egypt. The country list is whatever the registration contract supports. | Default the customer phone country to the shop owner's registered phone country. Make sure the list covers Egypt, Libya, Sudan, Saudi Arabia, UAE, Kuwait, Qatar, Bahrain, Oman, Yemen, Jordan, and the other Arab countries; keep the picker so a foreign number can still be entered. |
| B2 | Closing the day zeroes every table: sales, purchases, scrap bought, expenses, notes. Only available cash carries over. Scrap is tracked per day, so yesterday's scrap purchases stay apart from today's. | ADR 0042 A-D1 zeroes the day's flows and keeps cash, gold stock, and scrap balances visible on the home screen. | After a close, the daily ledger shows only the cash balance carried over; every daily figure and the scrap bought today start at zero. Stock and scrap balances stay in «الجرد الفوري», which is the physical shop and never resets. Record as an amendment to ADR 0042. |
| B3 | Repair money is collected after the repaired item is handed over. Call the section «مرمات», as in the old app, not «صيانة». | Money posts at handover or later through «تحصيل المتبقي»; nothing posts before handover. The section is «الصيانة» and the figure is «إيراد الصيانة». | Rename the section, menu entry, titles, and figure to «مرمات» / «إيراد المرمات». No change to when money is collected. |
| B4 | «رصيد افتتاحي» question: he did not follow it. A new shop shows the old app's basic items with zero count and zero weight in every karat. Merchants add their own items. | The item table lists only items with stock; opening stock is one unnamed row. | Show every basic item (batch 1, A4) in the item × karat table with zeros, and items with stock as now. Keep «إضافة صنف جديد». The unnamed opening row stays until the owner counts by item at a close. |
| B5 | Sales made before the app was used are not added to customers. | Matches B-D8 (no backfill). | None. |
| B6 | Customer data needs: an «تمت إضافته لجروب الواتساب» toggle (marketing), notes, VIP or not, the invoices made in the app, and a WhatsApp button that opens the chat. "All of this is in the PDF and the design." | Notes, VIP, linked invoices, and the WhatsApp button exist. There is no WhatsApp-group flag. | Add the «جروب الواتساب» flag to the customer (server field, owner-only command, audit event, shown on the card and detail, filter chip). Check the PDF requirement for any other customer field before building. |
| B7 | The WhatsApp button in the daily ledger does not open the number at all. | Not reproduced yet. His phone runs an old build that already fails to load the ledger (batch 1, A1). | Reproduce on a current build with a sale that has a customer phone. Fix if the current build also fails. |
| B8 | Purchased jewelry goes to scrap by karat, as built. Purchased coins and bullion go to their own stock, after a half-screen question: «هل تريد إضافتها لمخزون الجنيهات؟» (or السبائك). «لا» sends them to scrap at the karat he picks (24 or 21). | ADR 0041 routes purchased jewelry to scrap; coins and bullion go to their stock with no question. | Add the question after a coin or bullion line on a purchase: «نعم» keeps it in coin or bullion stock; «لا» turns that line into scrap at the chosen karat. The server already accepts a scrap line, so this is mostly the purchase screen. |
| B9 | The basic items are the old app's list; merchants add more. He sent the activation code for the old app so we can see the table and screens. | Batch 1, A4. | Same as A4. Capture the old app (below). |

## Decisions taken without asking again

- Coins or bullion declined into scrap: offer every karat the shop uses, with 24 and 21 first. The owner named 24 and 21 as examples.
- A customer phone keeps a country picker. The merchant's country is only the default.

## Work list for the next batch

1. Unblock the owner's ledger (batch 1, A1): a current build, or a server read older builds accept.
2. Basic items from the old app, shown with zeros in «الجرد الفوري» (A4, B4, B9).
3. Daily ledger after a close shows only carried cash (B2).
4. Rename «صيانة» to «مرمات» (B3).
5. Coin and bullion purchase question (B8).
6. Customer WhatsApp-group flag (B6).
7. Customer phone country from the merchant's country and the Arab country list (B1).
8. Reproduce the ledger WhatsApp button on a current build (B7).
9. Shop name on the test shop's invoices (A2) and the logo fallback check (A3).

## The old app

Needed: the layout and labels of «الجرد الفوري» (item × karat table, the karat buttons, the figure boxes), the item list, the page names, the customer screens, the closing count screen, and one invoice.

The old app is installed and activated on the user's phone. It can be captured from this workstation with `adb` (installed with the Android SDK) once the phone is connected by USB with USB debugging on, or paired with wireless debugging. Screens are captured with `adb exec-out screencap -p` and navigated with `adb shell input`. Customer names and numbers must not be saved into the repository.

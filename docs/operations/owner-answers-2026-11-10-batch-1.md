# Owner answers, batch 1 (2026-11-10)

Source: five voice notes and three screenshots from the owner, sent 2026-11-09 to 2026-11-10 in reply to the seven questions about the 2026-11-09 voice notes. The screenshots stay outside the repository; they show customer data. This record keeps only what matters for the product. More answers are expected in a second batch.

## Answers and what they mean

| # | Owner said | Finding | Action |
|---|---|---|---|
| A1 | The daily ledger shows «تعذر إتمام العملية. حاول مجددًا.» even with internet, also after logging out and in. Inventory and customers open. | **Caused by our 2026-11-09 development deployment.** The owner's phone runs a build from before batch A (its navigation still shows «الحساب»). That build's ledger parser rejects any unknown top-level key (`optionalV2 = {'feed_page', 'trade_change_sequence'}` at `361ad2e`). Batch A's `get_daily_ledger_home_v1` now returns `day_reset` and `last_closed_business_date`, so every home read fails on that build. Other pages use other RPCs. | Critical. Either ship the owner a current build (release build needs the user's go-ahead), or make the server read compatible with older builds (see "Open decisions"). Future read-model changes must not add keys that older builds reject. |
| A2 | The invoice header and footer show the account name, not the shop name; the seller's name is the same. | The invoice reads `shops.name` (`get_invoice_brand_source_v1`). The test shop was registered with a person's name as its shop name. This is data, not code. | Ask the owner to set the shop name in «المزيد ← بيانات المتجر» and send a new invoice. No code change unless the header still shows the wrong name afterwards. |
| A3 | The pixelated image: he thought it was the placeholder. If there is no image, show the Daftar logo; if there is one, show it. | This matches the current rule (no shop logo → app logo). The pixelated picture is most likely an image saved for the test shop at signup. | Confirm on the test shop: remove the logo in «المزيد ← لوجو المحل» and check the Daftar logo appears sharp. Fix only if the fallback is wrong or blurred. |
| A4 | The basic items should be the old app's list, not «بروش» or «ميدالية». The merchant adds any other item himself. | Old app list (screenshot): خواتم، حلقان، كوليهات، انسيلات، سلاسل، تعاليق، محابس، توينز، غوايش، اساور، دبل، جنيهات، سبائك، كسر. The new app's built-ins are singular (خاتم، حلق، سلسلة، تعليقة) and «أخرى» proposes extra names, including some he rejects. | Make the built-in jewelry items the old list's eleven jewelry names; جنيهات، سبائك، and كسر stay their own categories. Drop the proposed extras (بروش، ميدالية، كف، …). Keep «إضافة صنف جديد» for custom items. Decide singular vs plural wording with the owner (open decision 2). |
| A5 | He pointed to the old application for the instant-inventory table, page names, and the item table. | The old app is installed and activated on the user's phone. | Capture it as listed in "What we need from the old app". |

Questions still unanswered from the seven: «رصيد مجمع» screenshot, coins and bullion on purchase, karat order, price per item, foreign phone countries, day close and repairs, customer data scope. Expected in batch 2.

The two "needs clarification" items in the transcription tool's output (where the shop name is set, image compression) are answered here and are not sent to the owner.

## Open decisions

1. **Ledger outage (A1).** Fastest: a current build to the owner. Without a build, a server change can keep `get_daily_ledger_home_v1` in the old shape and move the new fields to a new read the current app calls. That needs a migration and a small app change, and is worth doing anyway so the next deployment cannot break an older phone.
2. **Item names (A4).** Use the old app's plural names (خواتم، حلقان…) everywhere, or keep singular names on sales lines (خاتم) and plural only in lists? Existing sales and lots already store singular names.

## What we need from the old app

Screenshots (or one screen recording) of, on the activated phone:

1. «الجرد الفوري» with stock in at least two karats, then with 14 and 22 shown, and the screen that changes the karat order.
2. The insight boxes at the top of the instant inventory and of the daily ledger, with real numbers.
3. The full item list when adding a sale, and the screen to add a new item.
4. Every page name in the menu and bottom bar, in order.
5. The customer list and one customer's page.
6. Day closing: the count screen.
7. One sale invoice as the customer receives it.

Blur or crop customer names and phone numbers before sharing them in the project. Only the layout and labels are needed.

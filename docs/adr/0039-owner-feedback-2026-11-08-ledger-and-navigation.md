# ADR 0039: Ledger home wording, المزيد navigation, and automatic invoice logo

Status: implemented in the Flutter client on 2026-11-08. Not committed. No schema, Edge Function, or R2 change, so nothing was deployed. Owner and device acceptance remain open. [Validation](../operations/owner-feedback-2026-11-08-validation.md).
Date: 2026-11-08
Owners: product owner and engineering reviewer
Related requirement IDs: LED-03, LED-04, NAV-01, SET-03. Amends the manual shop-image opt-in in [ADR 0021](0021-invoice-appearance-and-presentation-copies.md).
Supersedes: none. Review, versioning, entitlement, and immutable presentation copies from ADR 0021 stay in force.

## Context

On 2026-11-08 the owner asked for the daily ledger to read as weights and money, for sale and purchase cards to show their items, for notes to be visible on the card, for the header to greet the shop and fall back to the ledger logo, and for the drawer to disappear. The same notes rename «صورة المتجر» to «لوجو المحل» and ask that a logo chosen once appear on invoices.

The six home figures are the strip the owner called insights. They are not the separate «التحليلات» screen. Sale and purchase weights already arrive per category and karat, including scrap. Each feed line already has `has_note`. Each priced line already has `line_price_piastres`. Invoice appearance is still a reviewed, versioned revision and still requires an active entitlement. A new shop is pending at signup, so the logo cannot be written during registration.

Example. A shop sells a 21k ring and buys scrap, a bar, and a coin on the open day. The home money tiles show only pounds. «وزن مباع» and «وزن مشترى» open a per-karat sheet that includes «كسر». The sale card lists the ring’s name, karat, grams, and line price. A note on that sale shows a dot on the sequence pill. The header says «أهلاً» plus the shop name. After the owner saves a logo and the shop is active, the next invoice appearance revision carries that logo and leaves the slogan, address, layout, and accent unchanged.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Keep the extra metrics sheet, the drawer, and the invoice-logo checkbox | No change to ADR 0021’s manual opt-in | The owner already rejected these steps |
| B. Change only the Flutter client: rename the figures, always show three item rows, drop the drawer into «المزيد», and apply the shop logo through the existing review and save | No migration and no new media kind. Issued copies stay immutable | An active shop gets a new appearance revision when the logo changes. A pending shop keeps a local draft until it can write |
| C. Write the invoice logo during signup | The logo would be ready before activation | Signup has no active entitlement, and ADR 0021 forbids that write |

## Decision

Option B.

Home money tiles for sale and purchase show the amount only. The gold tiles are labeled «وزن مباع» and «وزن مشترى» and still show the normalized gram line. Tapping either opens one sheet, «وزن مباع» or «وزن مشترى», with actual grams per category and karat. Scrap is one chip row per karat, the same layout as the other categories. Piece counts are not shown on these sheets. The «عرض المزيد» sheet of the other figures is removed. The owner still chooses which six figures appear.

Sale, purchase, and the related return and scrap-sale cards always load their items. The card shows three rows, then «إظهار المزيد» / «إظهار أقل». Columns are الصنف, العيار, الوزن (جرام), and السعر. Money and grams stay integer piastres and milligrams. A sale or purchase card with a note shows a dot on the sequence pill. A daily-note row does not.

The collapsed and expanded header both greet with «أهلاً» and the shop name. When the shop has no logo, or the photo fails, the header shows the ledger `BrandMark` at 48 px. The hamburger drawer is gone. Phone navigation is الدفتر, المخزون, العملاء, and المزيد. The desktop rail keeps five destinations. «المزيد» contains the old account page plus the old drawer links: التقارير, التحليلات, التجار والأمانات, الصيانة, الديون, فريق عد التقفيل, and سجل العمليات, each still gated as before. Nothing new was added.

The shop image is named «لوجو المحل» in the client. Signup no longer asks whether the photo is also the invoice logo. If the owner chose a photo, registration always stores the local invoice draft. The first active owner workspace applies that draft once, through the same upload, confirm, review, and idempotent save the appearance screen already uses. Saving a new logo from «لوجو المحل» does the same when the owner’s entitlement is active. Clearing the shop logo does not change invoice appearance. A pending or expired shop sends nothing; the draft waits. A transport failure retries the same idempotency key, so the server records one appearance revision. Slogan, address, layout, and accent are copied from the saved revision. Issued presentation copies are not rewritten.

Three product choices are fixed here so later work does not reopen them: scrap in the purchase sheet is per karat; the card preview is three items; «المزيد» is the old drawer plus the old account page.

## Data and compatibility impact

No schema, RPC, Edge Function, or R2 kind. Postgres still stores appearance revisions and verified logo metadata only. Clients that have not updated keep the drawer, the checkbox, and the old labels. A new client talking to the current development project uses the existing appearance commands. Rollback is a client rollback. There is no backfill. Privacy is unchanged: the logo bytes still move only through the existing presigned upload.

## Verification

Flutter tests cover the money tiles, both weight sheets including scrap without piece counts, the three-row item preview and price column, the note dot, the header greeting and fallback logo, the «المزيد» links and the absent drawer, the «لوجو المحل» strings, registration always saving the draft, and automatic application: other appearance fields kept, same sha skipped, inactive entitlement refused, and one revision on retry. `invoice_appearance_screen_test.dart` still passes. React and SQL gates are unaffected. Device review and owner acceptance stay open until recorded in the validation note.

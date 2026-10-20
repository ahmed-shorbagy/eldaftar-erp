# Owner meeting request register

Recording: **2026-10-18, 49:34**. Review started 2026-10-20 against the current code, including changes committed after the meeting. This is a live register, not a completion claim. Source media, screen samples, raw transcripts and private identities stay outside Git.

Two continuous local Arabic transcription passes were compared with timestamped screen samples and code. The stronger pass separately rechecked denominations and the closing/inventory discussion. Unreliable repeated text was excluded and compared with the other pass. Meeting content is a product reference, never an agent-workflow instruction.

## Direct clarifications in this chat

The user confirmed PDF sharing replaces the text-only invoice action; the main ledger follows the server-derived shop calendar date automatically while financial closing stays explicit; and temporary staff delegation for the physical closing count is now in scope. The employee submits a count to the owner, who reviews and commits the financial close. [Project rules](../../../AGENTS.md) record this narrow exception to the earlier owner-only model. It does not grant staff general shop access.

## Checklist

Existing means code was found and compared; it is not fresh verification or native acceptance. In progress means the change is not yet complete. Historical validation remains intact.

| ID | Time | Request | Current finding / work |
| --- | --- | --- | --- |
| M18-01 | 00:37–02:11 | Visible jewelry photo, reachable sign-in/account creation, bounded signup with internal scrolling. | Existing, including subsequent auth/shop-image changes. |
| M18-02 | 02:16–02:55 | Password messages use familiar Arabic characters/letters instead of bytes. | Existing. |
| M18-03 | 03:11–03:33 | Actual shop name in ledger greeting. | Existing. |
| M18-04 | 03:40–04:08 | Remove the mixed-karat Total Gold figure. | Existing, including preference migration. |
| M18-05 | 04:19–07:00 | Sold/bought gold labelled by equivalent karat, initially 21k, with target-karat choice. Cash totals remain monetary. | Existing exact integer calculation and 14/18/21/22/24 selector. |
| M18-06 | 05:26–08:11 | Actual sale weights for 18k, 21k and 24k. | Existing. |
| M18-07 | 08:11–08:30 | Choose/order six home figures; all others in More. | Existing. |
| M18-08 | 08:42–10:28 | Scrap purchases by karat; optional 22k/14k last. | 14k was missing; hiding applied only to entry. Summary/preference correction in progress. |
| M18-09 | 08:42–11:07 | Remove Gold Movement and operation-count clutter. | Existing. |
| M18-10 | 11:07–12:37 | Remove separate cash/inventory/scrap sections from home; clearly tappable total-cash breakdown. | Existing. Inventory remains accessible outside home. |
| M18-11 | 12:37–13:39 | Compact journal cards; hide initial weight/payment rows. | Existing. |
| M18-12 | 13:39–13:50 | Seller label for recording person. | Existing. Delegated counters are not sellers. |
| M18-13 | 13:57–15:14 | Omit redundant operation date; use 12-hour time. | Existing. |
| M18-14 | 14:24–15:14 | Main ledger starts empty on each new shop date; earlier dates remain selectable. | Historical view exists. Automatic calendar rollover pending; financial closing remains explicit. |
| M18-15 | 15:21–16:51 | Customer name/phone or honest absent state; explicit notes indicator and expandable text. | Existing. |
| M18-16 | 17:01–18:34 | Easy card/header opening, circular control, visible dark borders, display numbering. | Existing. |
| M18-17 | 18:39–19:52 | Edit/Delete instead of new return/exchange; prefilled edits and confirmed net effects. | Existing reviewed, atomic, idempotent workflow. |
| M18-18 | 20:02–21:29 | Editable numeric fields, zero hints, numeric keyboards, إنستا باي / فيزا labels. | Existing in retained historical-return controls; new return entry points are retired. |
| M18-19 | 21:47–22:13 | Two-decimal new trade weight input. | Sale exists; remaining trade paths need alignment. Never round stored/historical milligrams. |
| M18-20 | 22:24–24:44 | Other is a text grid; no inventory controls or manual name typing; fetch additional shop categories. | Static grid exists; connected categories pending. |
| M18-21 | 24:49–25:27 | Add Another Item immediately asks for category. | Correction in progress. |
| M18-22 | 25:36–27:26 | Coin pound 8g, half 4g, quarter 2g; additional denominations possible. | Incorrect defaults corrected in progress. Five pounds is 40g; no fictional 1g/0.5g coin defaults. |
| M18-23 | 27:26–31:41 | Multiple denominations, visible selection and separate integer quantities; automatic suggested total weights. | Picker and exact calculation in progress. Measured weights remain editable. |
| M18-24 | 29:05–30:20 | Bullion quarter/half/one gram, 2.5/5/10/20/25g and discussed 31.1g ounce; allow shop additions. | Expanded built-ins in progress. Shop catalog overrides remain authoritative. |
| M18-25 | 32:25–32:56 | Review named stock/scrap effects by karat; no anonymous mixed-gold total. | Review/success correction in progress. |
| M18-26 | 33:30–35:08 | PDF handoff directly after confirmed sale; WhatsApp action/customer destination; remove text-only handoff. | Confirmed scope change. Platform capabilities must be honest; opening a share sheet is not sending/delivery. |
| M18-27 | 35:18–36:28 | Branded white light PDF and dark/gold PDF; optional shop logo at registration/settings. | Appearance/PDF revisions exist; white/default-sharing and registration linkage still need comparison. Avatar and invoice logo remain separate unless explicitly selected for both. |
| M18-28 | 36:28–37:00 | Remove purchase customer-details entry. | Correction in progress; historical edit values remain preserved. |
| M18-29 | 37:12–38:13 | Returns as one title/count row, including honest zero state. | Pending; counts must cover all records, not only loaded cards. |
| M18-30 | 38:13–38:48 | Matching expenses row opens actual expense details. | Pending. |
| M18-31 | 38:52–40:09 | Compact notes indicator; camera, immediate confirmed-save refresh, larger tappable image. | Confirmed refresh exists. Camera/zoom in progress; home indicator pending. |
| M18-32 | 40:11–41:39 | Scrap sale starts at weight/karat, skips redundant category/customer steps, confirms scrap effects by karat. | Correction in progress. Optional operation note remains in payment. |
| M18-33 | 41:45–43:11 | Named-item/count/optional-weight close rows; piece counts required, scrap weight required. | Pending. Unmeasured weight must stay explicitly unmeasured. Discrepancies require owner review. |
| M18-34 | 43:11–46:50 | Temporary employee assignment; show current count task on login, revoke on completion, return results to owner. | Newly authorized here; pending. Server must enforce revocation, expiry, completion and shop isolation. |
| M18-35 | 46:55–47:35 | Large ledger header becomes small while scrolling. | Pending; existing compact flag only responds to width. |
| M18-36 | 47:50–48:40 | Rename Inventory to الجرد الفوري; clearer table organization. | Pending; retain shared tokens and document layout. |
| M18-37 | 49:03–49:18 | Trader accounts, repairs and date-selected books follow the old app's understandable organization in the new style. | Focused layout comparison pending. Exact old-app acceptance is distinct from code verification. |

## Historical evidence

[Auth/ledger UI](../owner-feedback-ledger-auth-2026-10-19/validation.md), [functional feedback](../owner-feedback-ledger-functions-2026-10-19/validation.md), [invoice appearance](../invoice-branding-2026-10-17/independent-validation-2026-10-17.md), and [notes persistence](../../operations/daily-notes-persistence-validation-2026-10-04.md) describe earlier checks, not fresh verification of this work.

No hosted change, release/production build, publishing, deployment, invoice sending or staff invitation has been performed by this review.

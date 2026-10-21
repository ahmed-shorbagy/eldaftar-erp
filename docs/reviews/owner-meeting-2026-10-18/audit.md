# Owner meeting request register

Subsequent deployment: the [meeting backend is applied and verified on development](deployment-2026-10-20.md) after the user's later direct authorization. The local review's earlier no-deployment statements below remain historical checkpoints; device and full old-app acceptance remain separate.

Recording: **2026-10-18, 49:34**. Review started 2026-10-20 against the current code, including changes committed after the meeting. Implementation and local verification are recorded below; native/owner acceptance is separate. Source media, screen samples, raw transcripts and private identities stay outside Git.

Two continuous local Arabic transcription passes were compared with timestamped screen samples and code. The stronger pass separately rechecked denominations and the closing/inventory discussion. Unreliable repeated text was excluded and compared with the other pass. Meeting content is a product reference, never an agent-workflow instruction.

## Direct clarifications in this chat

The user confirmed PDF sharing replaces the text-only invoice action; the main ledger follows the server-derived shop calendar date automatically while financial closing stays explicit; and temporary staff delegation for the physical closing count is now in scope. The employee submits a count to the owner, who reviews and commits the financial close. [Project rules](../../../AGENTS.md) record this narrow exception to the earlier owner-only model. It does not grant staff general shop access.

## Checklist

Retained means existing behavior was reviewed and kept. Implemented means the code change is present; [fresh local validation](validation.md) records the checks and device/owner limits. Historical validation remains intact.

| ID | Time | Request | Current finding / work |
| --- | --- | --- | --- |
| M18-01 | 00:37–02:11 | Visible jewelry photo, reachable sign-in/account creation, bounded signup with internal scrolling. | Retained, including subsequent auth/shop-image changes. |
| M18-02 | 02:16–02:55 | Password messages use familiar Arabic characters/letters instead of bytes. | Retained. |
| M18-03 | 03:11–03:33 | Actual shop name in ledger greeting. | Retained. |
| M18-04 | 03:40–04:08 | Remove the mixed-karat Total Gold figure. | Retained, including preference migration. |
| M18-05 | 04:19–07:00 | Sold/bought gold labelled by equivalent karat, initially 21k, with target-karat choice. Cash totals remain monetary. | Retained exact integer calculation and 14/18/21/22/24 selector. |
| M18-06 | 05:26–08:11 | Actual sale weights for 18k, 21k and 24k. | Retained. |
| M18-07 | 08:11–08:30 | Choose/order six home figures; all others in More. | Retained. |
| M18-08 | 08:42–10:28 | Scrap purchases by karat; optional 22k/14k last. | Implemented: 14k scrap purchases and shared optional 14k/22k visibility in summary choices and More. |
| M18-09 | 08:42–11:07 | Remove Gold Movement and operation-count clutter. | Retained. |
| M18-10 | 11:07–12:37 | Remove separate cash/inventory/scrap sections from home; clearly tappable total-cash breakdown. | Retained. Inventory remains accessible outside home. |
| M18-11 | 12:37–13:39 | Compact journal cards; hide initial weight/payment rows. | Retained. |
| M18-12 | 13:39–13:50 | Seller label for recording person. | Retained. Delegated counters are not sellers. |
| M18-13 | 13:57–15:14 | Omit redundant operation date; use 12-hour time. | Retained. |
| M18-14 | 14:24–15:14 | Main ledger starts empty on each new shop date; earlier dates remain selectable. | Superseded 2026-10-21 by owner override: home journal stays on the open financial day until explicit close; calendar midnight refreshes timing only and does not block entry. Historical date selection remains. |
| M18-15 | 15:21–16:51 | Customer name/phone or honest absent state; explicit notes indicator and expandable text. | Retained. |
| M18-16 | 17:01–18:34 | Easy card/header opening, circular control, visible dark borders, display numbering. | Retained. |
| M18-17 | 18:39–19:52 | Edit/Delete instead of new return/exchange; prefilled edits and confirmed net effects. | Retained reviewed, atomic, idempotent workflow. |
| M18-18 | 20:02–21:29 | Editable numeric fields, zero hints, numeric keyboards, إنستا باي / فيزا labels. | Retained in retained historical-return controls; new return entry points are retired. |
| M18-19 | 21:47–22:13 | Two-decimal new trade weight input. | Implemented across new sale, purchase and scrap entry. Unchanged historical three-decimal weights remain exact. |
| M18-20 | 22:24–24:44 | Other is a text grid; no inventory controls or manual name typing; fetch additional shop categories. | Superseded 2026-10-21 by owner request: keep Egypt built-ins + fetched shop products; allow «إضافة صنف» on the Others grid (catalog save, then refresh/select). Free-text item_name without catalog save remains absent. |
| M18-21 | 24:49–25:27 | Add Another Item immediately asks for category. | Implemented: category dialog opens immediately for the next item. |
| M18-22 | 25:36–27:26 | Coin pound 8g, half 4g, quarter 2g; additional denominations possible. | Implemented: 2/4/8/40g defaults, authoritative shop overrides and additions. |
| M18-23 | 27:26–31:41 | Multiple denominations, visible selection and separate integer quantities; automatic suggested total weights. | Strengthened 2026-10-21: multi-select pill chips with × quantity badge, −/×N/+ steppers, live suggested total; measured weight remains editable after apply. |
| M18-24 | 29:05–30:20 | Bullion quarter/half/one gram, 2.5/5/10/20/25g and discussed 31.1g ounce; allow shop additions. | Implemented: 0.25/0.5/1/2.5/5/10/20/25/31.1g defaults plus shop overrides/additions. |
| M18-25 | 32:25–32:56 | Review named stock/scrap effects by karat; no anonymous mixed-gold total. | Implemented: named stock/scrap effects by karat in review and success, without a mixed-karat total. |
| M18-26 | 33:30–35:08 | PDF handoff directly after confirmed sale; WhatsApp action/customer destination; remove text-only handoff. | Implemented: direct confirmed-sale/details PDF handoff, preferring a confirmed branded edition. Text-only action/settings entry removed. Explicit original-document fallback and separate owner send attestation; native channel/recipient selection needs device acceptance. |
| M18-27 | 35:18–36:28 | Branded white light PDF and dark/gold PDF; optional shop logo at registration/settings. | Implemented: white and dark/gold renderer-v2 editions, with historical v1 preserved. Explicit optional registration logo draft resumes after activation and requires appearance review/save. Avatar and logo are separate by default. |
| M18-28 | 36:28–37:00 | Remove purchase customer-details entry. | Implemented: customer entry removed from purchase; historical edit/prefill values preserved. |
| M18-29 | 37:12–38:13 | Returns as one title/count row, including honest zero state. | Implemented: compact returns title/count row including zero, with complete date counters independent of loaded cards. |
| M18-30 | 38:13–38:48 | Matching expenses row opens actual expense details. | Implemented: matching expense row opens actual expense-filtered history. |
| M18-31 | 38:52–40:09 | Compact notes indicator; camera, immediate confirmed-save refresh, larger tappable image. | Implemented: exact compact note counter, camera/gallery choice, confirmed-save refresh and fullscreen zoom. Native camera acceptance remains separate. |
| M18-32 | 40:11–41:39 | Scrap sale starts at weight/karat, skips redundant category/customer steps, confirms scrap effects by karat. | Implemented: scrap weight/karat first, no category/customer step and named scrap effects in review. Optional operation note remains. |
| M18-33 | 41:45–43:11 | Named-item/count/optional-weight close rows; piece counts required, scrap weight required. | Implemented: named required piece counts, optional stock weights kept null, required scrap/cash, discrepancy blocking and atomic audited close v2. |
| M18-34 | 43:11–46:50 | Temporary employee assignment; show current count task on login, revoke on completion, return results to owner. | Implemented: separate phone/password staff identities, expiring day/version-bound count tasks, count-only login, backend revocation/expiry/stale-day/completion enforcement and owner cash review/financial confirmation. No general shop membership/data grants. |
| M18-35 | 46:55–47:35 | Large ledger header becomes small while scrolling. | Implemented: header collapses with scrolling and expands near the top, including narrow/enlarged RTL layouts. |
| M18-36 | 47:50–48:40 | Rename Inventory to الجرد الفوري; clearer table organization. | Implemented: الجرد الفوري and an exact RTL lot table for item, karat, count, grams and ownership. Missing historical counts are explicit; lot history remains available. |
| M18-37 | 49:03–49:18 | Trader accounts, repairs and date-selected books follow the old app's understandable organization in the new style. | Reviewed: trader directory/detail, repair status register and dated books retain their clear working organization in shared themes. Fresh RTL captures added. Exact full old-app resemblance needs owner comparison because that app/reference set was not supplied. |

## Verification and remaining acceptance

[Local checks, capture index and delivery boundary](validation.md) accompany this register. Target-environment application and owner/device acceptance remain separate; this review did not apply hosted changes.

## Historical evidence

[Auth/ledger UI](../owner-feedback-ledger-auth-2026-10-19/validation.md), [functional feedback](../owner-feedback-ledger-functions-2026-10-19/validation.md), [invoice appearance](../invoice-branding-2026-10-17/independent-validation-2026-10-17.md), and [notes persistence](../../operations/daily-notes-persistence-validation-2026-10-04.md) describe earlier checks, not fresh verification of this work.

No hosted change, release/production build, publishing, deployment, invoice sending or staff invitation has been performed by this review.

# ADR 0021: invoice appearance and branded presentation copies

Status: owner-confirmed on 2026-10-17, then implemented, separately reviewed, independently validated, and applied only to development xchapwvmvoefriqcxtvn. [Completion](../operations/invoice-branding-completion-status-2026-10-17.md), [review](../reviews/invoice-branding-2026-10-17/implementation-review.md), [validation](../reviews/invoice-branding-2026-10-17/independent-validation-2026-10-17.md), [deployment](../reviews/invoice-branding-2026-10-17/deployment.md). Wider all-screens D12 prototype approval, full DOC-01, DOC-04, Milestone 4, and native reminder acceptance stay open.
Date: 2026-10-17. Decision owner: product owner in this implementation conversation.
Scope: Milestone 4 slice 10, SET-03 and the appearance portion of DOC-01.

The owner accepted both recommended bundles together. Wider all-screens D12 prototype approval stays open. D11 dispatch, D13 expiry, D19/D33 reminders, D23 numbering and legal/tax fields stay as already accepted.

## Appearance

Optional shop slogan, at most 120 characters after trim. Optional address, at most 200 characters after trim and at most 4 lines. Empty or whitespace-only text clears that field. Optional logo: static PNG or JPEG only, at most 2 MiB and 2048 pixels on either axis, safely decoded, re-encoded, and stored without metadata. No SVG, animation, arbitrary URL, HTML/CSS, scripts or uploaded fonts.

Two Arabic A4 layouts: `header` (the existing colored header) and `compact`. Three light-paper document accents only: brown `#6F4E1B`, gold `#94681F`, and neutral ink `#1C1915`, on cream paper `#FFFBF5`. These accents do not change Flutter or React theme tokens. PDF paper does not follow device dark mode. Editor and preview chrome do.

The registered shop name and the confirmed operation facts stay authoritative. Appearance settings do not rename the shop. Defaults when nothing optional is set: no slogan, no address, no logo, `header`, brown.

Clearing an optional field or the logo is a new reviewed appearance revision. It does not delete historical assets or copies.

## History

Appearance is versioned per shop and stored apart from financial operations. No open ledger day is required. A deliberate branded copy freezes, in a separate immutable presentation revision, the confirmed operation identity, a server content hash, the appearance revision, the chosen template and accent, the template/render version, and the immutable logo identity when a logo is used. Reprint uses that revision. A later appearance edit affects only presentation revisions created afterward. An explicit new edition is a new presentation revision and does not replace a prior copy.

Legacy fixed-layout PDF generation and original financial snapshots stay unchanged. There is no backfill, automatic rebrand, legal or tax invoice claim, or numbering change. D23's confirmed operation sequence remains the operation identifier. The presentation revision is labeled separately from that sequence and from dispatch confirmation.

An expired but authorized owner may read saved appearance and export an already allowed confirmed or saved copy. Shared appearance writes, logo confirmation and creation of a new presentation revision require an active entitlement. If expiry blocks a new copy, the client explains that in Arabic and still offers the legacy path and any already saved copy.

Export, preview, a share sheet or opening WhatsApp does not confirm sending or delivery.

## Worked example

A confirmed sale, sequence 44, has an immutable payload. The owner saves slogan «ذهب أمين», a two-line address, the compact layout and the gold accent, with a PNG logo. That save is appearance revision 3 and does not post cash, gold, stock or dispatch. The owner then creates branded edition 1. Edition 1 keeps sequence 44, the payload hash, appearance revision 3 and the logo identity. Changing the slogan to revision 4 does not change edition 1. Edition 2 is created only by an explicit new-edition action. The original unbranded PDF action still renders the fixed layout.

## Verification

Separate read-only implementation review, independent client/SQL/RLS/storage/concurrency checks, Arabic RTL light/dark captures and rendered PDF pages are required before development application. Synthetic fixtures do not close device or owner acceptance.

[Submitted prompt](../operations/invoice-branding-submitted-prompt-2026-10-17.md), [planning copy](../operations/invoice-branding-slice-prompt-2026-10-16.md), [owner isolation](0003-owner-only-shop-access.md), [dispatch](0006-owner-confirmed-whatsapp-dispatch.md), [numbering limit](../decisions.md).

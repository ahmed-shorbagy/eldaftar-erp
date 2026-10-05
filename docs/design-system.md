# ElDafttar UI theme contract

## Current direction

The owner's 2026-10-05 feedback establishes a simpler Arabic RTL experience for authentication and the daily ledger. Neutral cream and charcoal surfaces, restrained gold controls, compact figures and short business forms replace the earlier chart-heavy home and guide cards. The explicit request removes onboarding, training entry points and guides. Three signup steps collect required account data; they do not introduce a product tour. Historical review records remain unchanged.

Flutter `app/lib/src/theme/app_tokens.dart` and React `admin/src/theme/tokens.ts` are the shared token sources. Map those roles through each client's theme; do not add component-level hex colors. The [owner feedback review](reviews/owner-feedback-2026-10-05/validation.md) records reference coverage and verification limits.

## Color roles

| Role | Light | Dark |
| --- | --- | --- |
| Brown seed for derived Material roles | #6F4E1B | #6F4E1B |
| Page surface | #FFFBF5 | #0C0D0D |
| Main text | #1C1915 | #EFEFEF |
| Primary action/accent | #94681F | #D4AF37 |
| Text on primary action | #FFFBF5 | #0C0D0D |
| Success / Flutter tertiary | #206638 | #86D99F |
| Dark neutral card | — | #161616 |
| Primary container | Material seed-derived | #3A2C18 |
| React primary container | #F3E6D0 | #3A2C18 |
| React divider | #D9CBB8 | #343434 |

Flutter derives remaining outline, error, disabled and light container roles through `ColorScheme.fromSeed`. React uses MUI semantic roles. Their derived colors may differ slightly; review contrast and visual intent together. Gold is now an action and brand accent, as requested; avoid large solid gold dashboard backgrounds. Financial success must remain distinct from the gold primary action.

## Brand and entry

The mark is a small open ledger with a diamond above it, inspired by the owner's reference. Neutral backgrounds and gold strokes have separate light and dark variants. Flutter draws it in `BrandMark`, React in `BrandMark.tsx`; matching SVGs and generated native splash images live under `app/assets/brand/`. Android and iOS launch screens use these variants. Android, iOS and Windows launcher icons use the same light vector-painter export with safe margins; reproduce their sizes with `app/tool/generate_brand_icons.py` after the opt-in brand export test.

Login places a full-bleed decorative jewelry photo behind the brand and form. The image fades into the page surface so the form card sits over it. The photo is excluded from semantics. Signup uses the same atmosphere. Fresh installations default to dark. Theme selection remains available and persisted; saved light and system choices are respected. The brand tagline is “دفتر لإدارة محلات الذهب والمجوهرات”. Signup uses account → shop → review with explicit back navigation and a single next/create button. Collect email and phone separately, with short labels for name and shop name. The `phone_form_field` control shows the country flag and dial code, Arabic country search and automatic recognition when an international number is pasted. Restrict choices to countries supported by the registration contract. Phone digits use LTR inside the Arabic layout. Regions use the available Egyptian catalog; other countries and unavailable catalogs use a labelled manual region field.

After a successful sign-in the owner enters the daily ledger for their shop directly. There is no shop-selection step because each owner account belongs to one shop. Empty membership, pending activation, and load failures still show explicit Arabic states.

## Layout and typography

Both clients use Arabic copy and RTL navigation with logical start/end spacing. Both clients bundle Cairo under the SIL Open Font License. Flutter registers it as Cairo; React loads its local font face with a Tahoma/Arial fallback. The license accompanies each bundled font. The common wide breakpoint is 840 logical pixels and main content measure is 720; auth uses a narrower 480-pixel form. Use at least 16-pixel phone gutters, 48-pixel targets, soft card corners around 22 logical pixels, pill action chips, and persistent labels. Avoid truncating mixed Arabic text and phone/cash values. Respect text scaling, keyboard insets and reduced motion.

## Daily ledger and transactions

The daily ledger opens under a premium curved app bar: brand mark medallion, title, shop name, optional work-day line, and stadium-shaped icon actions. Soft gold-tinted gradient and a rounded bottom edge separate it from the page body.

Six compact metrics appear first: cash, sales, purchases, gold, gold sold and gold purchased. Each metric uses an icon badge and a soft surface tile rather than a plain number card. Sale figures lean on the success/tertiary accent and purchase figures on the error accent so cash and gold stay visually distinct from gold primary actions. “عرض المزيد” reveals expenses and operation count. Every metric, including cash and gold, can be hidden or moved individually. Sections, metric order/visibility and return-journal visibility are saved per shop on the device. Gold always retains three decimal places. Money displays use comma grouping, suppress unnecessary `.00` and omit currency labels. Gold-coin item names remain. Compact million summaries are presentation only; full details preserve exact cents using integer/string arithmetic.

A gold floating action button opens the supported business actions in a bottom sheet. It can be dragged within the safe viewport; its normalized position is saved per shop. The sheet also offers four corner-position buttons as a keyboard/tap alternative. The button clears the workspace navigation and yields to subsequently opened routes. Unsupported actions remain absent.

The main journals are sales, purchases and returns. Returns appear only when loaded return records exist and the owner has enabled them. Other confirmed movements remain accessible through a separate sheet. Cash methods appear as short accent-flag tiles. Gold-by-karat uses compact karat badges. Expanded stock and scrap group by category with colored flags and piece tiles (karat badge, weight, count) instead of concatenated text rows. Those sections can be hidden or reordered. Journal cards show the recording owner, item summary/count, party, total, weight, karat, payment and shop-local server time where provided, and open the full operation detail. The server bounds item-summary text while the full operation retains every item. Older servers may omit new summaries; do not invent values.

Sale and purchase entry follows category → items → payment → optional details → review. Standard item selection offers twelve choices, including bangles, bands and anklets; purchases additionally offer scrap. Known choices supply their item name and financial category automatically, without a naming field or duplicate category selector. “أخرى” permits an optional custom name/category. Expense starts at payment. Customer details are optional for sales and all purchases, including unpaid purchases. An unnamed purchase payable remains tied to its own operation; “عميل بدون اسم” is a display label, never a shared customer identity. Review reads like an invoice: business totals/items/customer/payment first, then exact net cash and gold effects, then confirmation. Show success only after backend confirmation, with a return-to-ledger button. Unknown outcomes keep their original pending key and payload for reconciliation; never offer another submission as a fresh transaction. Refresh the ledger after returning from entry, including system back navigation after a confirmed save.

## Verification rules

1. Read this guide and both token files before changing UI. Use semantic theme roles for text, surfaces, controls, borders, errors, pending and success.
2. Update both clients' tokens and this guide together for shared visual changes.
3. Review Arabic RTL in light and dark modes at narrow phone and desktop widths, including populated, error, pending, success, text-scale and keyboard states as relevant.
4. Compare key screens to the owner's references for spacing, hierarchy, states and simplicity. Record intentional differences such as retaining existing backend-supported actions instead of displaying unsupported reference actions.
5. Preserve precision, authentication boundaries, server-confirmed writes, idempotent retries and existing financial contracts when simplifying presentation.

See the current [completion review](reviews/owner-feedback-2026-10-05/completion.md). The earlier [implementation review](reviews/owner-feedback-2026-10-05/validation.md) and [audit](reviews/owner-feedback-2026-10-05/feedback-audit.md) are historical snapshots. Earlier [entry](reviews/onboarding-entry-2026-09-28/validation.md), [auth](reviews/auth-redesign-2026-09-27/validation.md), [ledger](reviews/daily-ledger-ui-2026-09-28/validation.md) and [milestone](reviews/milestones-0-3-2026-10-04/validation.md) reviews describe historical versions, not the current guide policy or home layout.

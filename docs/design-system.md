# ElDafttar UI theme contract

## Current direction

The owner's 2026-10-05 feedback establishes a simpler Arabic RTL experience for authentication and the daily ledger. Neutral cream and charcoal surfaces, restrained gold controls, compact figures and short business forms replace the earlier chart-heavy home and guide cards. The explicit request removes onboarding, training entry points and guides. Three signup steps collect required account data; they do not introduce a product tour. Historical review records remain unchanged.

Flutter `app/lib/src/theme/app_tokens.dart` and React `admin/src/theme/tokens.ts` are the shared token sources. Map those roles through each client's theme; do not add component-level hex colors. The [owner feedback review](reviews/owner-feedback-2026-10-05/validation.md) records reference coverage and verification limits.

## Color roles

| Role | Light | Dark |
| --- | --- | --- |
| Brown seed for derived Material roles | #6F4E1B | #6F4E1B |
| Page surface | #FFFBF5 | #141210 |
| Main text | #1C1915 | #F6F1E8 |
| Primary action/accent | #94681F | #E6C36A |
| Text on primary action | #FFFBF5 | #141210 |
| Success / Flutter tertiary | #206638 | #86D99F |
| Dark neutral card | — | #1C1915 |
| Primary container | Material seed-derived | #3A2C18 |
| React primary container | #F3E6D0 | #3A2C18 |
| React divider | #D9CBB8 | #4A433A |

Flutter derives remaining outline, error, disabled and light container roles through `ColorScheme.fromSeed`. React uses MUI semantic roles. Their derived colors may differ slightly; review contrast and visual intent together. Gold is now an action and brand accent, as requested; avoid large solid gold dashboard backgrounds. Financial success must remain distinct from the gold primary action.

## Brand and entry

The mark is a small open ledger with a diamond above it, inspired by the owner's reference. Neutral backgrounds and gold strokes have separate light and dark variants. Flutter draws it in `BrandMark`, React in `BrandMark.tsx`; matching SVGs and generated native splash images live under `app/assets/brand/`. Android and iOS launch screens use these variants. Android, iOS and Windows launcher icons use the same light vector-painter export with safe margins; reproduce their sizes with `app/tool/generate_brand_icons.py` after the opt-in brand export test.

Login places a full-bleed decorative jewelry photo behind the brand and form. The image fades into the page surface so the form card sits over it. The photo is excluded from semantics. Signup uses the same atmosphere. Theme selection remains available and persisted. Signup uses account → shop → review with explicit back navigation and a single next/create button. Collect email and phone separately, with short labels for name and shop name. The `phone_form_field` control shows the country flag and dial code, Arabic country search and automatic recognition when an international number is pasted. Restrict choices to countries supported by the registration contract. Phone digits use LTR inside the Arabic layout. Regions use the available Egyptian catalog; other countries and unavailable catalogs use a labelled manual region field.

After a successful sign-in the owner enters the daily ledger for their shop directly. There is no shop-selection step because each owner account belongs to one shop. Empty membership, pending activation, and load failures still show explicit Arabic states.

## Layout and typography

Both clients use Arabic copy and RTL navigation with logical start/end spacing. Flutter uses bundled Noto Sans Arabic under its existing SIL license. React retains the Segoe UI/Tahoma/Arabic font fallback stack. The common wide breakpoint is 840 logical pixels and main content measure is 720; auth uses a narrower 480-pixel form. Use at least 16-pixel phone gutters, 48-pixel targets, 12-pixel card/button corners and persistent labels. Avoid truncating mixed Arabic text and phone/cash values. Respect text scaling, keyboard insets and reduced motion.

## Daily ledger and transactions

The two confirmed cash/gold totals remain visible. Display them side by side when their measured width permits; stack only at very narrow measures. Thousands separators and optional million abbreviations improve summary readability. Full details retain exact money strings, and gold always retains three decimal places. Amount formatting uses integer/string arithmetic.

The main quick actions are sale, purchase and expense. Additional supported actions live in a collapsible panel. The remaining home uses compact daily movement cards, cash-method chips, gold-by-karat chips, collapsible inventory/scrap details and separate sale/purchase journals. Returns and other movement lists are initially collapsed except an initial opening record. The owner can show, hide and reorder home sections and movement subcards; save these preferences per shop on the device. Journal cards show type, party, total, weight, karat, payment and shop-local server time where available, and open the full operation detail. Older servers may omit the new summary fields; do not invent values.

Sale and purchase entry follows category → items → payment → optional details → review. Expense starts at payment. Review reads like an invoice: business totals/items/customer/payment first, then exact net cash and gold effects, then confirmation. Show success only after backend confirmation, with a return-to-ledger button. Unknown outcomes keep their original pending key and payload for reconciliation; never offer another submission as a fresh transaction. Refresh the ledger after returning from entry, including system back navigation after a confirmed save.

## Verification rules

1. Read this guide and both token files before changing UI. Use semantic theme roles for text, surfaces, controls, borders, errors, pending and success.
2. Update both clients' tokens and this guide together for shared visual changes.
3. Review Arabic RTL in light and dark modes at narrow phone and desktop widths, including populated, error, pending, success, text-scale and keyboard states as relevant.
4. Compare key screens to the owner's references for spacing, hierarchy, states and simplicity. Record intentional differences such as retaining existing backend-supported actions instead of displaying unsupported reference actions.
5. Preserve precision, authentication boundaries, server-confirmed writes, idempotent retries and existing financial contracts when simplifying presentation.

See the current [feedback review](reviews/owner-feedback-2026-10-05/validation.md). Earlier [entry](reviews/onboarding-entry-2026-09-28/validation.md), [auth](reviews/auth-redesign-2026-09-27/validation.md), [ledger](reviews/daily-ledger-ui-2026-09-28/validation.md) and [milestone](reviews/milestones-0-3-2026-10-04/validation.md) reviews describe historical versions, not the current guide policy or home layout.

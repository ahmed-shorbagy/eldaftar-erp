# ElDafttar UI theme contract

## Current direction

The owner's 2026-10-05 feedback establishes a simpler Arabic RTL experience for authentication and the daily ledger. Neutral cream and charcoal surfaces, restrained gold controls, compact figures and short business forms replace the earlier chart-heavy home and guide cards. The explicit request removes onboarding, training entry points and guides. Three signup steps collect required account data; they do not introduce a product tour. Historical review records remain unchanged.

Flutter `app/lib/src/theme/app_tokens.dart` and React `admin/src/theme/tokens.ts` are the shared token sources. Map those roles through each client's theme; do not add component-level hex colors. The [current owner feedback review](reviews/owner-feedback-2026-10-06/validation.md) records reference coverage and verification limits.

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
| Table border | #8F6B2E | #9A7B45 |

Flutter derives remaining outline, error, disabled and light container roles through `ColorScheme.fromSeed`. React uses MUI semantic roles. Their derived colors may differ slightly; review contrast and visual intent together. Gold is now an action and brand accent, as requested; avoid large solid gold dashboard backgrounds. Financial success must remain distinct from the gold primary action.

## Brand and entry

The mark is a small open ledger with a diamond above it, inspired by the owner's reference. Neutral backgrounds and gold strokes have separate light and dark variants. Flutter draws it in `BrandMark`, React in `BrandMark.tsx`; matching SVGs and generated native splash images live under `app/assets/brand/`. Android and iOS launch screens use these variants. Android, iOS and Windows launcher icons use the same light vector-painter export with safe margins; reproduce their sizes with `app/tool/generate_brand_icons.py` after the opt-in brand export test.

Login places a full-bleed decorative jewelry photo behind the brand and form. The image fades into the page surface so the form card sits over it. The photo is excluded from semantics. Signup uses the same atmosphere. Fresh installations default to dark. Theme selection remains available and persisted; saved light and system choices are respected. The brand tagline is “دفتر لإدارة محلات الذهب والمجوهرات”. Signup uses account → shop → review with explicit back navigation and a single next/create button. Collect email and phone separately, with short labels for name and shop name. The `phone_form_field` control shows the country flag and dial code, Arabic country search and automatic recognition when an international number is pasted. Restrict choices to countries supported by the registration contract. Phone digits use LTR inside the Arabic layout. Egypt requires a catalog governorate from `egypt_governorates`, ordered by `display_order`, with an explicit loading, failure, and retry state. Other supported countries require a non-empty city/region stored as `CC:label`. Changing the phone country clears a stale region. Historical empty `CC:` and `EG:text` profiles remain stored and replayable; new requests reject them. Place the sign-in card high enough that Sign In and Create New Account are visible at 320-logical-pixel phone heights without searching. After sign-in, pending and expired shops open an Arabic activation dialog with a 32-character code field, activate/retry, pending/success/failure copy, frozen unknown retries, and an explicit control after dismiss. Confirmed shops refresh ledger, inventory, traders, invoices, and open detail routes from RLS-protected `shop_sync_signals` revisions; page-top reload buttons stay absent.

After a successful sign-in the owner enters the daily ledger for their shop directly. There is no shop-selection step because each owner account belongs to one shop. Empty membership, pending activation, and load failures still show explicit Arabic states.

## Layout and typography

Both clients use Arabic copy and RTL navigation with logical start/end spacing. Both clients bundle Cairo under the SIL Open Font License. Flutter registers it as Cairo; React loads its local font face with a Tahoma/Arial fallback. The license accompanies each bundled font. The common wide breakpoint is 840 logical pixels and main content measure is 720; auth uses a narrower 480-pixel form. Use at least 16-pixel phone gutters, 48-pixel targets, soft card corners around 22 logical pixels, pill action chips, and persistent labels. Avoid truncating mixed Arabic text and phone/cash values. Respect text scaling, keyboard insets and reduced motion.

The shared type scale is 12/14/16/20/24 logical pixels for captions, supporting text, body/fields, section headings and figures. Headings use 700, labels 600, and body text 400. Cairo remains the common family. Tabular figures stabilize numeric layout; monetary text stays LTR inside the RTL interface. Use 1.5 line height and zero added tracking for Arabic text. The global Flutter input theme and React outlined-input theme share 14-pixel corners, 16-pixel field text, generous internal padding, semantic borders and a visible focus state. Authentication retains its photo-overlay surface treatment while sharing size and corner tokens.

## Daily ledger and transactions

The daily ledger opens under a premium curved app bar: brand mark medallion, title, shop name, optional work-day line, and stadium-shaped icon actions. Soft gold-tinted gradient and a rounded bottom edge separate it from the page body.

The ledger summary stays at the top as a compact horizontal strip. Eight figures are available: confirmed cash, total gold, daily sales, purchases, gold sold, gold bought, expenses and operation count. Show the first five preferred visible figures on narrow phones or enlarged text, and six otherwise. Saved figure order and visibility remain per shop. Tiles grow to keep full amounts readable; the strip scrolls horizontally. Sales and purchases include their gold weight as a supporting line. Sale figures use success/tertiary and purchases use the error accent.

“عرض المزيد” opens full daily metrics and movement details. Paired cash and inventory links open dedicated breakdowns. The ledger shows separate sales and purchase journals with at most three recent operations each. A smaller returns journal shows one card when enabled and nonempty; it is absent when there are no loaded returns. Each book has its own “عرض الكل” action opening that book's history. “عرض حركة الدفتر” also opens the complete confirmed history with all/sale/purchase/return/other filters and older-record loading. Other movements stay in the history surface. Return filters appear only when enabled and loaded returns exist; confirmed returns remain available in the complete history. Detail views use a bottom sheet below 840 logical pixels and a centered dialog above it, with one scroll area, a persistent title and an explicit close button. The transaction detail page retains the full invoice and audit information.

Customization opens in its own detail surface. All eight figures can be hidden or reordered; other sections retain their visibility and order preferences. The summary remains pinned above them. Hiding a balance shortcut leaves its breakdown accessible through daily details. Preferences stay local to the shop. Detail views update after pagination without losing their filter and close when their owning ledger disappears or the shop changes. Ordinary ledger, journal and confirmed-detail gold displays round to exactly two decimals with integer arithmetic. Stored quantities, editable measured grams and immutable invoice precision retain three decimals. Financial confirmation also shows exact milligrams when rounding to two decimals would hide a difference. Money always displays full comma-grouped numbers, preserves cents, suppresses unnecessary `.00`, and omits currency labels; million abbreviations are removed.

Sales and purchases have an explicit add button above their respective tables. Journals are separated by 24 logical pixels. Structured confirmed item rows show name, karat, weight and count horizontally; show two initially with “عرض المزيد” for additional rows. Customer and shop date remain collapsed behind “عرض التفاصيل”. Missing item reads expose a retry, and summaries never become invented item records. Journal previews and history support oldest/newest order using server sequences, with persisted UTC instants for legacy histories lacking sequences. Sorting covers loaded records; older-record loading remains explicit.

A gold floating action button opens supported business actions in a bottom sheet: expense, scrap sale, cash transfer, scrap-to-stock, linked returns, invoice sends, daily notes and day opening/closing as available. Sale and purchase belong above their tables and are absent from this menu. The button remains draggable with saved per-shop position and four corner buttons as a keyboard/tap alternative. It clears workspace navigation and yields to subsequent routes. Returns require supported commands and current owner write access, select an original confirmed transaction, and retain the existing review workflow. Unsupported actions remain absent.

Within detail views, cash methods use accent-flag tiles and gold-by-karat uses compact karat badges. Expanded stock and scrap group by category with piece tiles showing karat, weight and count. Journal rows show the recording owner, item summary/count, party, exact total, weight, karat, payment and shop-local server time where provided, and open the full operation detail. The server bounds item-summary text while the full operation retains every item. Older servers may omit new summaries; do not invent values.

Sale and purchase entry opens a constrained slide-up sheet, at most 84% of available height above the keyboard and 720 logical pixels wide. Category, measured items and payment share one entry form followed by net-effect review and confirmation. Customer and optional pricing live in disclosures. Distinct vector icons identify rings, earrings, necklaces, pendants, coins and bullion. Known choices supply their name/category; less-used jewelry choices remain reachable in a compact disclosure. “أخرى” offers the connected shop product table, pagination, manual entry and access to Instant Inventory. Editable nominal suggestions are bullion 0.250 g and coins 1.000/0.500 g, quarter 1.000 g, half 2.500 g, pound 10.000 g and five-pound 20.000 g; active shop catalog values with matching names replace these owner-supplied suggestions. They do not establish physical standards or override measured stock quantities. Expense, scrap and exchange retain their established flows. Unnamed and unpaid purchases remain operation-specific. Success follows backend confirmation, then offers return to ledger and supported sale invoice dispatch through the existing WhatsApp/PDF and owner-confirmation workflow. Unknown outcomes keep their original key and payload frozen. Refresh on return, including system back.

The workspace opens at the ledger without a Home/Start destination. Light/dark toggle remains visible in the header and persisted by the shared theme controller; logout is in More. There is no ledger profile-image upload. Daily note images remain in their own feature.

## Compensation workflow layout

Correction entry stays inside a physical-count mismatch and shows the required Arabic reason, counted values and exact signed cash/gold/piece differences before confirmation. Confirmed correction discards that count route; the next close requires a fresh server snapshot and new physical count. The original confirmed operation opens partial/full remaining return review with selectable item rows, measured grams/counts, explicit consideration and split refund-method fields. A remaining-full action fills quantities and price components only; the owner still enters refund allocation.

Exchange replacement uses the accepted category → items → payment → optional details → review form. Its final review appends the linked return, replacement and exact net cash by method and category/karat gold/count effects. Unknown requests remain frozen for reconciliation. Both forms retain the 720-pixel content measure, semantic theme roles, Cairo, RTL, currency-free money and three-decimal grams; signed values use LTR isolation in Arabic effect labels. [Widget/native synthetic review and limits](reviews/ledger-compensation-2026-10-06/validation.md).

## Verification rules

1. Read this guide and both token files before changing UI. Use semantic theme roles for text, surfaces, controls, borders, errors, pending and success.
2. Update both clients' tokens and this guide together for shared visual changes.
3. Review Arabic RTL in light and dark modes at narrow phone and desktop widths, including populated, error, pending, success, text-scale and keyboard states as relevant.
4. Compare key screens to the owner's references for spacing, hierarchy, states and simplicity. Record intentional differences such as retaining existing backend-supported actions instead of displaying unsupported reference actions.
5. Preserve precision, authentication boundaries, server-confirmed writes, idempotent retries and existing financial contracts when simplifying presentation.

The [compact ledger review](reviews/compact-ledger-2026-10-05/validation.md) records the latest simplification and shared typography checks. See the earlier [completion review](reviews/owner-feedback-2026-10-05/completion.md). The earlier [implementation review](reviews/owner-feedback-2026-10-05/validation.md) and [audit](reviews/owner-feedback-2026-10-05/feedback-audit.md) are historical snapshots. Earlier [entry](reviews/onboarding-entry-2026-09-28/validation.md), [auth](reviews/auth-redesign-2026-09-27/validation.md), [ledger](reviews/daily-ledger-ui-2026-09-28/validation.md) and [milestone](reviews/milestones-0-3-2026-10-04/validation.md) reviews describe historical versions, not the current guide policy or home layout.

The [Batch 1 review](reviews/owner-feedback-batch1-2026-10-11/validation.md) records required location, compact sign-in, subscription activation and automatic synchronization checks.

The [Batch 2 review](reviews/owner-feedback-batch2-2026-10-12/validation.md) records compact metrics, horizontal journals, constrained buy/sell entry, navigation cleanup and verification limits.

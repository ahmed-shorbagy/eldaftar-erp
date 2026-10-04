# ElDafttar UI theme contract

## Status and scope

This is the required visual baseline for new or edited Flutter and React UI. AGENTS.md requires future work to use the current theme. The Flutter and React token files are the implementation sources; this guide records the shared values and review rules. The source mockups inform screen layout and interaction, but they do not replace these tokens unless the user explicitly approves a palette change.

## Core colors

| Role | Light mode | Dark mode | Implementation |
| --- | --- | --- | --- |
| Primary seed | #6F4E1B | #6F4E1B | Flutter ColorScheme seed; React MUI primary |
| Surface/background | #FFFBF5 | #141210 | Page and app-bar background |
| Main text/on surface | #1C1915 | #F6F1E8 | Primary content and icons |
| Primary container | #F3E6D0 | #3A2C18 | React token; Flutter uses generated Material 3 container role |
| On primary container | #1C1915 | #F6F1E8 | React token; Flutter uses generated Material 3 role |
| Outline/divider | #D9CBB8 | #4A433A | React token; Flutter uses generated Material 3 outline role |

Flutter currently defines the five core seed/surface/text values in app/lib/src/theme/app_tokens.dart and derives other roles through ColorScheme.fromSeed in app/lib/src/theme/app_theme.dart. React defines the core plus container/outline values in admin/src/theme/tokens.ts and maps them into MUI in admin/src/theme/theme.ts. Derived Flutter colors and explicit React container/outline values are not guaranteed to be numerically identical; align visual intent and contrast when adding a shared component pattern.

## Brand mark

The product mark is an open cream ledger with a gold ingot on the brown seed field. Android and iOS native launch screens use the centered mark and system light/dark backgrounds through `flutter_native_splash`; the earlier delayed Flutter opening view is no longer shown. Flutter login and signup use a compact 40px mark beside the name/tagline, with help and theme in that same header row, so the form and actions remain visible on narrow phones. Sign-in and registration share one segmented switch above the fields, and the fields sit on a quiet surface panel. Shop and admin bars use a small mark. The drawing is `app/assets/brand/mark.svg`, repeated as `admin/public/favicon.svg` and the generated native splash PNG. Flutter paints it in `BrandMark`; React draws it in `admin/src/theme/BrandMark.tsx`. See the [current entry review](reviews/onboarding-entry-2026-09-28/validation.md); older auth splash records are historical.

The gold `#E6C36A` (`brandGold`) is used only inside that mark, on the brown field. It is not a text or status color. The page, spine, and field use the existing surface, dark primary container, and seed tokens.

## Layout and typography baseline

Both clients use Arabic copy and RTL layout. The current wide breakpoint is 840 logical pixels and content maximum width is 720 pixels in both token files. React uses the Segoe UI, Tahoma, Noto Naskh Arabic, Noto Sans Arabic, Arial fallback stack. Flutter uses the bundled Noto Sans Arabic font across the app. React font metrics may differ until both clients share a bundled font.

Flutter uses the bundled Noto Sans Arabic variable font under the SIL Open Font License (`app/assets/fonts/OFL.txt`). The authentication form measure is 480 logical pixels, with 16px phone gutters, 48px minimum controls, 12px corners, and persistent labels. React retains its typography and shared layout tokens. Auth controls/status colors continue to come from the existing `ColorScheme`; the new synchronized gold token is confined to the brand illustration. See [auth review](reviews/auth-redesign-2026-09-27/validation.md) for rendered evidence and verification limits.

Use logical start/end spacing, alignment and icon direction. Ensure numbers, customer names and phone numbers remain readable within mixed Arabic/Latin content. Preserve theme choice and respect system preference until the user makes a choice.

Both clients now expose `minControlSize = 48` in their shared token files. Flutter button/icon-button themes and React MUI button/icon-button themes apply this minimum globally. Feature forms must preserve that target and accessible Arabic names; a visible field caption must be linked to its text-field semantics. Signed-out React owners can also change and persist the theme. The [2026-10-04 review](reviews/milestones-0-3-2026-10-04/validation.md) covers the recovery and workspace additions.

## Rules for every UI change

1. Read this guide and both client token files before designing the screen. Reuse theme roles from ThemeData/ColorScheme in Flutter and MUI theme/tokens in React. Do not place raw hex values or ad hoc Color literals in feature widgets or components.
2. Define a missing semantic role centrally, with a light and dark value and contrast review. If the role is shared, map it in both clients and update this guide. Status colors for success, pending, failure and financial effects need deliberate semantic tokens; they must not be guessed separately per screen.
3. Keep backgrounds, surfaces, cards, text, borders, controls, focus, disabled, error and success states legible in both themes. Test mobile and desktop widths and Arabic RTL before completion.
4. Compare important screens to approved design references for spacing, typography, hierarchy and states. A reference image's color does not silently override the current palette. If a reference conflicts, record the discrepancy and obtain a product decision before changing global theme colors.
5. A palette change requested by the user updates Flutter tokens, React tokens, this guide and affected UI in the same work item. Review screenshots in both modes across both clients and report any intentional visual differences.

## Review evidence

For a new or substantially edited screen, capture or inspect representative light and dark states at a narrow phone width and a desktop width; include hover/focus or keyboard state where relevant. Check readable contrast, Arabic labels, overflow, empty/loading/pending/error/success states, and persisted theme choice. Keep the screen's color decisions traceable to the token role used. The design review is incomplete when only one theme or one platform width has been checked.

## Confirmed daily ledger layout

The confirmed Flutter ledger presents server-confirmed gold weight and cash total first. Quick actions sit in one panel under those totals: sale is the primary control, purchase and expense share the next row when the panel is at least 420 logical pixels wide and stack on narrower widths, and cash transfer, scrap sale, scrap-to-stock, day close, and pending invoices stay in that same panel. The default section order then shows a gold-by-karat donut and a cash-method bar chart, followed by daily movement, inventory and scrap details, and the confirmed activity feed. Gold movement chips scroll in one row, and the detail list shows only the selected karat. A saved section order on the device is kept. At widths below 480 logical pixels, the two totals stack; on wider screens they sit side by side inside the existing 720-pixel content measure. Inside the gold card, the donut sits above its legend until the card is at least 420 logical pixels wide, then the legend sits beside the ring. Cards, bars, icons, text, and borders use Material `ColorScheme` roles derived from the shared brown and cream tokens. Donut slices use `primary`, `tertiary`, `secondary`, `onSurfaceVariant`, and `onSurface` in that order. Cash bars stay on `primary` and scale against the largest confirmed balance, with a 6-logical-pixel minimum when the balance is above zero. Both charts show the exact amount and that item’s share of the total. Shares use integer tenths of a percent and sum to 100.0%; the remainder is added to the largest amount. Chart geometry is display-only. Tapping a row highlights that item. The entrance lasts 700ms and is skipped when reduced motion is requested.

The owner may show, hide, and reorder the daily movement, cash, gold, and activity sections. Within daily movement, the sale, purchase, expense and gold cards have their own visibility and order controls. These layout preferences are stored per shop on the current device. The two confirmed totals always remain visible. Daily movement includes exact sale and purchase gold totals by selected karat, then category details. The view reads server balances and activity through `get_daily_ledger_v2`, with a `get_daily_ledger` fallback for older schemas. Sale, shop-owned full or partial cash purchase, expense, cash transfer, scrap-to-cash, same-karat scrap-to-stock, and day controls appear only when the financial day-state command succeeds. A confirmed sale or purchase detail exposes a full linked return review when the return contract is available. Quick-action review screens use the same 720-pixel centered content measure and solid primary-container effect card in both themes; messages appear before long mobile forms so validation remains visible without scrolling to the end.

The 2026-09-28 ledger refinement uses the existing `ColorScheme.primary` as a solid surface for the confirmed gold total and `onPrimary` for its content. Cash remains a bordered neutral card. The later home charts replace that day’s thin comparison bars: the gold donut and the primary cash bars described above. On narrow phones, refresh remains in the app bar while shop selection, theme, and sign-out are grouped under an accessible overflow menu. The opening form groups cash, stock, and scrap in separate surfaces; review first summarizes exact gold and cash effects before the detailed rows. Ledger form fields use a filled outline on `ColorScheme.surface` with 12-pixel corners. Related fields sit side by side from 440 logical pixels and stack below that width. See the [ledger UI review](reviews/daily-ledger-ui-2026-09-28/validation.md) for captures and limits.

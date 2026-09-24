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

## Layout and typography baseline

Both clients use Arabic copy and RTL layout. The current wide breakpoint is 840 logical pixels and content maximum width is 720 pixels in both token files. React uses the Segoe UI, Tahoma, Noto Naskh Arabic, Noto Sans Arabic, Arial fallback stack. Flutter currently uses platform Material typography; choose and license a consistent Arabic typeface before treating the mockup typography as an exact production target.

Use logical start/end spacing, alignment and icon direction. Ensure numbers, customer names and phone numbers remain readable within mixed Arabic/Latin content. Preserve theme choice and respect system preference until the user makes a choice.

## Rules for every UI change

1. Read this guide and both client token files before designing the screen. Reuse theme roles from ThemeData/ColorScheme in Flutter and MUI theme/tokens in React. Do not place raw hex values or ad hoc Color literals in feature widgets or components.
2. Define a missing semantic role centrally, with a light and dark value and contrast review. If the role is shared, map it in both clients and update this guide. Status colors for success, pending, failure and financial effects need deliberate semantic tokens; they must not be guessed separately per screen.
3. Keep backgrounds, surfaces, cards, text, borders, controls, focus, disabled, error and success states legible in both themes. Test mobile and desktop widths and Arabic RTL before completion.
4. Compare important screens to approved design references for spacing, typography, hierarchy and states. A reference image's color does not silently override the current palette. If a reference conflicts, record the discrepancy and obtain a product decision before changing global theme colors.
5. A palette change requested by the user updates Flutter tokens, React tokens, this guide and affected UI in the same work item. Review screenshots in both modes across both clients and report any intentional visual differences.

## Review evidence

For a new or substantially edited screen, capture or inspect representative light and dark states at a narrow phone width and a desktop width; include hover/focus or keyboard state where relevant. Check readable contrast, Arabic labels, overflow, empty/loading/pending/error/success states, and persisted theme choice. Keep the screen's color decisions traceable to the token role used. The design review is incomplete when only one theme or one platform width has been checked.

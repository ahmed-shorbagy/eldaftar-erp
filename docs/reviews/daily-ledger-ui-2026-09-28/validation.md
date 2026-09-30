# Daily ledger UI review — 2026-09-28

The attached daily-ledger DOCX was used as a product reference. Its requested rapid sale, purchase, cash transfer, scrap, expense, invoice, notes, and close-day workflows remain outside this UI increment because the corresponding atomic server commands are not implemented. Owner-only access takes precedence over the document's employee permission examples. No inactive financial action is presented as usable.

## Changes reviewed

- The confirmed server figures lead with gold weight and cash. The gold card uses the existing solid primary color role, while the cash card uses a bordered surface. Charts use one primary color and print exact values beside their bars.
- The opening form separates cash, stock, and scrap. Review shows the exact combined weight and cash effect before the owner confirms. Pending and server-confirmed states retain their existing financial flow.
- At 320 logical pixels, refresh stays visible and shop selection, theme, and sign-out move into an overflow menu. The wider app bar retains its direct controls.

## Rendered checks

The synthetic Flutter captures below were inspected in Arabic RTL. They cover light and dark phone states and light and dark desktop states. The 320-pixel review was also checked with the maximum supported cash value. No visible clipping or overflow was observed in those captures. These are widget renders, not physical-device evidence.

| State | Light | Dark |
| --- | --- | --- |
| Confirmed, 320 | [Image](confirmed-top-light-320.png) | [Image](confirmed-top-dark-320.png) |
| Confirmed, 1440 | [Image](confirmed-top-light-1440.png) | [Image](confirmed-top-dark-1440.png) |
| Opening form, 320 | [Image](uninitialized-top-light-320.png) | [Image](uninitialized-top-dark-320.png) |
| Review, 320 | [Image](review-top-light-320.png) | [Image](review-top-dark-320.png) |

`dart format` and `dart analyze` passed. The `flutter analyze --no-pub` wrapper produced no output and did not finish on this host; direct `dart analyze` reported no issues and exited successfully when its writable telemetry home was set under `app/build`. The serial full Flutter suite passed 139 tests. React lint, 34 React tests, and `npx tsc -b` passed. SQL, RLS, and atomicity behavior did not change, so no database suite was run. No release build or deployment was performed.

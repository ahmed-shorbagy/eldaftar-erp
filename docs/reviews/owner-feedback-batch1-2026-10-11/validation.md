# Owner feedback Batch 1 validation — 2026-10-11

Implemented locally; hosted rollout pending. Grok Build implemented the scoped batch, and Codex reviewed and corrected the diff before independently rerunning the final gates.

## Delivered behavior

| Owner feedback | Implementation and verification |
| --- | --- |
| Sign-in placement | Compact layout on short screens, safe-area spacing, and a visible create-account action; Arabic RTL captures at 320, 390 and 1440 pixels, both themes. |
| Required location | New registrations reject an empty location at Flutter, Edge Function and SQL boundaries. Egypt requires one of the 27 catalog governorates; other currently supported countries require a manual city/region. |
| Country-aware signup | Egyptian local/international phone recognition selects Egypt and the ordered governorate dropdown; other supported calling codes select their country and manual location. Existing supported-country scope is retained. |
| Pending/expired subscription | Authenticated shell presents a scrollable Arabic activation dialog instead of indefinite loading. Confirmed activation, rejected codes, uncertain outcomes, retries, and account changes have explicit states. |
| Automatic updates | Top reload controls removed. Confirmed local operations refresh their views; shop revision signals invalidate ledger, cash, inventory, trader, invoice, day and catalog views across sessions. Reconnect/resume catches up; a 45-second fallback poll handles missed events. |

Historical registration values remain stored and pre-existing requests remain replayable. New requests must satisfy the required-location contract. Financial table access remains entitlement-gated by RLS; pending owners receive only their minimal sync metadata.

## Final independent gates

- Flutter: `flutter test` — **494 passed**, including signup, activation, account-switch cleanup, reconnect, in-flight updates and actual Supabase channel lifecycle regressions.
- Static analysis: `dart analyze` — **no issues**. `flutter analyze` cannot start because this installed SDK lacks `analysis_server.dart.snapshot`; the direct Dart analyzer is the recorded substitute.
- Scoped Dart formatting: 47 changed/new files checked, zero changes required.
- React: `npm run lint`, `npm run test -- --run` (**37 passed**) and `npx tsc -b` passed.
- Registration Edge Function: Deno formatting and lint passed; **24 tests passed**; `deno check --frozen index.ts` passed from the function directory, using its dependency configuration.
- Fresh isolated PostgreSQL 17: every migration applied; the new migration applied, rolled back and reapplied; all **14 SQL/RLS suites passed**, including subscription issuance/redemption, invalid-attempt persistence, replay, ownership boundaries, sync triggers and existing atomic financial gates.
- `git diff --check` passed. No release or React production builds were requested or run.

A redirected PostgreSQL launcher held its output pipe open on one attempt. That disposable server was stopped, and the complete isolated SQL gate passed on a subsequent run. This was a runner issue, not a SQL failure.

## Visual review and limits

Flutter widget captures reviewed in Arabic RTL and both themes at phone and desktop widths include login, signup, pending/expired activation, unknown outcomes, increased text scale and simulated keyboards. Focus/visibility checks cover safe areas and the create-account action. Existing semantic brown/cream/dark colors are retained; shared spacing tokens were added to both clients. Images remain ignored local review evidence rather than committed product/source material.

These are synthetic widget/SDK and disposable database checks, not a native-device or hosted cross-session acceptance test. Supabase project inspection was read-only. No hosted migration, Edge Function deployment, subscription issuance, real-user mutation, push or publication occurred. Production activation and cross-session Realtime require the migration and updated owner-register function to be deployed together, followed by hosted acceptance checks.

Review repairs included persisted activation throttling, subscription-scoped cleanup, stale-owner response protection, serialized refreshes with retained in-flight signals, reconnect catch-up, and small-screen signup visibility.

## Contracts

- [Decision](../../adr/0011-required-location-subscription-sync.md)
- [Subscription operator workflow](../../operations/subscription-codes.md)
- [Shared design system](../../design-system.md)

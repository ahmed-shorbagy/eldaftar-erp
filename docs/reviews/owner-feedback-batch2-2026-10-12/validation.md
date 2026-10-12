# Owner feedback Batch 2 — daily ledger

Date: 2026-10-12. Scope: the owner's pasted Batch 2 feedback, existing requirements and shared design guide. No older-version screenshot was provided; the implementation follows the requested layout and existing palette.

## Delivered behavior

| Feedback | Implementation |
| --- | --- |
| Dark table boundaries | Shared subtle gold table-border tokens in Flutter and React, with contrast coverage. |
| Statistics and formatting | Summary pinned at the top; saved metric selection/order shows five preferred figures on narrow or enlarged-text screens and six otherwise. Full comma-grouped money and two-decimal gold use integer arithmetic. Storage, measured input and immutable invoices retain exact precision. Confirmation includes exact milligrams when rounding would conceal a difference. |
| Buy/sell journals | Add buttons above the respective tables; remaining supported business operations in Quick Actions. Horizontal item details, two initially visible items, Show More, optional customer/date details, spacing and oldest/newest sorting. Sorting uses server sequence or persisted UTC instants and covers loaded records. |
| Fast transaction entry | Constrained slide-up sale/purchase sheet with category icons, editable nominal suggestions, real shop product selection and Instant Inventory access. Items/payment share one form; customer/pricing stay in disclosures. Net-effect review remains required. Collapsing pricing preserves entered charges. Confirmed sales expose existing invoice dispatch. |
| Navigation | Ledger opens first; visible persisted theme toggle; logout inside More; no Home/Start destination or ledger profile-image upload. |

Existing owner authorization, atomic commands, audit records, exact payloads, duplicate-submission guards and frozen unknown-request reconciliation remain in place. Actual structured operation items populate journals; summary text never becomes fabricated items. Unsupported actions remain absent.

## Review and validation

Grok Build implemented scoped changes without committing or pushing. Codex reviewed the diff, repaired form state, financial precision display, responsive boundaries, item-read races and UTC sorting, and ran independent checks. Existing financial assertions were retained while navigation and presentation expectations were updated.

- Scoped Dart formatting and direct `dart analyze`: clean. The installed `flutter analyze` launcher fails because its analysis-server snapshot is missing; direct analysis is the working substitute.
- Full Flutter regression suite: all 525 tests passed. Coverage includes exact amounts/payloads, optional pricing, catalog presets, stale reads/retry, sheet bounds, unknown outcomes, navigation and invoice availability.
- React lint, all 38 tests and `npx tsc -b`: passed. No production build was requested.
- Fresh local PostgreSQL 17 database: migrations and all 14 SQL/RLS suites passed, including authorization, atomic trades, pricing, inventory, synchronization, idempotency and compensation. Existing migration rollback roundtrip also passed.
- Arabic RTL widget captures reviewed in both themes at 320/390/1440 logical pixels, including sale/purchase entry, keyboard, review, success, enlarged-text unknown states and populated ledger journals. Tests assert no overflow. Synthetic captures use test fixtures; private shop/customer data is not included.
- Documentation consistency/privacy and `git diff --check`: checked before commit. Historical validation records remain intact.

Capture artifacts are ignored local files under `tmp/batch2/captures/` and `app/build/batch2/`; they are not committed product data.

## Acceptance limits

The shorter flow is implemented and tested; a five-second completion guarantee depends on owner input and network latency and has not been measured on a real device. Native-platform visual acceptance remains outstanding. Invoice dispatch uses the existing owner-confirmed WhatsApp/PDF workflow; this work does not claim automatic delivery.

Supabase plugin inspection was read-only and confirmed existing contracts. This batch adds no backend migration and makes no hosted database change. Nothing was pushed, deployed or published. Release builds were not requested or run.

# Borderless ledger follow-up — 2026-10-13

The owner's new screenshot identifies excessive horizontal padding and requests a borderless ledger. This supersedes the enclosing journal/operation/table frames from the earlier refinement. Gold summary-card frames remain requested.

The previous layout stacked page gutters (16 on narrower phones, 24 on wider phones), 12 inside the journal card and another 12 inside each operation. Item-table space therefore lost 40–48 logical pixels per side. Journals and operations now sit directly on the page without enclosing cards or inset padding. All phone widths below 840 use one shared 12-pixel ledger gutter. Desktop retains the existing 720-pixel content measure and 24-pixel gutters. Flutter and React expose the matching `ledgerPhoneGutter` token; React screens are unchanged.

Tables no longer have an outer frame or vertical cell borders. A restrained header tint, subtle gold horizontal rules and a neutral separator between operations preserve grouping. Add/details/history actions, gold summary frames, journal separation, exact amounts, item disclosure, sorting and supported quick actions remain available.

## Validation

- Scoped Dart formatting and direct Dart analysis passed. The installed Flutter analyzer launcher limitation is recorded in the earlier review.
- All 35 scoped Flutter tests passed, covering ledger captures, structured item disclosure/read failures, dashboard, navigation and owner-feedback paths.
- Ten Arabic RTL capture scenarios passed: both themes at 320/390/430/1440 logical pixels and 320 at 1.6 text scale. Populated journals, details and Quick Actions were visually reviewed. A width regression now checks the single phone gutter, including wider phones above 400 pixels, and that ordinary item tables use the whole journal width.
- React lint, all 38 tests and `npx tsc -b` passed.
- Documentation consistency, links, privacy and `git diff --check` reviewed. Earlier review records remain unchanged.

Synthetic screenshots use ignored `app/build/borderless-ledger/`. No source requirements or private customer/shop data are included. These are widget captures; no fresh native-device review or release build was run. No backend/SQL contract, financial calculations or mutation behavior changed, so SQL gates were not rerun. No commit, push or deployment was performed.

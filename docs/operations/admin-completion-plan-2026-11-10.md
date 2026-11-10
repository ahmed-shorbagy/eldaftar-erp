# Admin dashboard completion plan — 2026-11-10

Status: accepted by the owner on 2026-11-10 with phase order 1–4; all five owner decisions are answered (see Owner decisions). Record D-A2 and D-A3 in an ADR when Phase 4 begins. Each phase still starts only when the owner selects it. Delivered admin slices keep their own records: [ADR 0027](../adr/0027-admin-subscriber-directory.md), [ADR 0028](../adr/0028-admin-subscription-code-issuance.md), [ADR 0030](../adr/0030-app-version-forced-update.md), [ADR 0031](../adr/0031-help-content-and-announcements.md), [ADR 0032](../adr/0032-admin-subscriber-contact-reveal.md), [ADR 0036](../adr/0036-support-inquiries.md).

## Current state (examined 2026-11-10)

The React admin (`admin/`) has these operational areas behind the platform-admin gate: subscriber directory with counts and detail (ADM-01), contact reveal (ADM-07), code issuance and history (ADM-02), forced-update policy (ADM-04), Help FAQ plus one announcement (ADM-05), and the support mailbox (HELP-02). Routine gates on 2026-11-10: `npm run lint` 0 errors and 4 `set-state-in-effect` warnings, `npx tsc -b` clean, `npm test` 166/166. Backends are development-deployed on `xchapwvmvoefriqcxtvn`. Owner acceptance and frontend publication are pending for every slice.

Gaps against the [requirements matrix](../requirements-matrix.md), [product scope](../product-scope.md) and Milestone 5 of the [delivery plan](../delivery-plan.md):

| Gap | Source | Blocked on |
|---|---|---|
| Navigation without routes; four-button row cramped at phone widths; refresh loses location | UX review | nothing |
| No overview home with platform figures (expiring soon, new registrations, open support) | ADM-01 "statistics", product scope "operational metrics" | nothing |
| No platform audit browser for admin actions | Delivery plan Milestone 5 "platform audit", product scope "all admin changes are audited" | nothing; audit coverage must be verified first |
| Codes: no month/year plans, no revocation, no bulk send | ADM-02 | month/year meaning (D-A2) |
| Broadcast messages to subscribers | ADM-06 | owner decisions D-A3 |
| Help video/images | HELP-01 | new R2 media kind under [ADR 0024](../adr/0024-cloudflare-r2-media-storage.md) |
| Reset and account deletion | RET-03 | D14, D15, D29 in [decisions](../decisions.md) |
| Audited support access into a shop | D21 | D21 |
| Owner acceptance, hosting and publication | Milestone 6 | D20 |

The matrix row for ADM-06 cites D19, which is the accepted debt-reminder decision. ADM-06 needs its own decision record; correct the matrix reference when Phase 4 is scoped.

## Phase 1 — navigation and responsive shell (no new backend)

Status 2026-11-10: implemented locally. URL routes for every area, including `/subscribers/<shop id>`; a section rail from 1200 pixels and a menu drawer below it (the 840-pixel breakpoint squeezed the directory table); the four `set-state-in-effect` lint warnings fixed by moving state updates into settled promise callbacks and adjusting topic fields during render. Gates: `npm run lint` clean (0 warnings), `npx tsc -b` clean, `npm test` 176/176 (10 new routing and navigation tests). Visual review used a gitignored synthetic harness (`admin/tmp/phase1-nav`, fake data) in Arabic RTL at 320, 375, 900 and 1240 pixels in light and dark; a signed-in review against development data followed the same day.

Signed-in review 2026-11-10 (development `xchapwvmvoefriqcxtvn`, platform-admin session, read-only; no codes issued, no contact reveal, no saves) at 375 and 1240 pixels in light and dark covered subscribers list and deep-linked detail, app version, Help and support. Defects fixed with regression tests:
- Every dialog and drawer laid out left-to-right: the theme's `body { direction: rtl }` was mirrored to `ltr` by `stylis-plugin-rtl`, so Arabic dates in the subscriber detail showed the day number at the end of the line. The rule is removed; `<html dir="rtl">` sets the direction.
- The support «آخر تحديث» time showed UTC inside a `dir="ltr"` span (day number at the end). It now uses the viewer's time zone in a `<bdi>`; inquiry rows keep the shop's time zone.
- Changing section kept the previous scroll offset; it now starts at the top.

Gates after fixes: lint clean, `npx tsc -b` clean, `npm test` 177/177. Polish noted for a later pass, not fixed: each date cell repeats the full time-zone name; pending rows repeat «لا توجد مدة اشتراك» three times; the directory lists oldest registrations first; the support search label uses the English word "UUID"; «إلغاء الإلزام» is enabled on a platform with no minimum. Not committed. The original scope follows.

- Replace the button row with URL routes for each area (subscribers, subscriber detail, codes, app version, Help, support, and later audit) so refresh, back and shared links work. Unknown routes return to the overview.
- Use a right-side navigation rail on desktop and a drawer or bottom navigation on narrow screens. Keep the brown, cream and dark tokens from `docs/design-system.md`; no palette change.
- Keep the access-loss behavior: any route clears content when admin access is lost.
- Resolve the four lint warnings without changing behavior.
- Acceptance: routing and access-loss tests; Arabic RTL review in light and dark at 320, 390 and 1440 widths and enlarged text, signed in as a development platform admin.

## Phase 2 — overview home

Status 2026-11-10: implemented, locally verified and deployed to development under [ADR 0045](../adr/0045-admin-overview.md) ([validation and deployment](../reviews/admin-overview-2026-11-10/validation.md)). Windows are rolling 3/7/30-day durations from the server snapshot. The directory gained `expiring_3/7/30` filters via `/subscribers?status=…`. Not committed. The original scope follows.

- Add an «نظرة عامة» landing page: active, pending and expired subscription counts; shops expiring in the next 3, 7 and 30 days; new registrations this week and month; open support inquiries by status; current forced-update minimums; the published announcement.
- Serve it from one admin-gated read RPC with a single server snapshot time, exact integer-string counts and shop-local boundaries as in ADR 0027. No shop financial, CRM or contact data.
- Each figure links to the filtered list behind it. The directory gains an "expires within N days" filter.
- Acceptance: SQL boundary tests (anonymous, owner, revoked admin fail), day-boundary and time-zone tests, React state tests, visual review.

## Phase 3 — platform audit browser

- First verify which admin mutations write audit rows today. Code issuance writes `identity_audit_events`; contact reveal, version policy, Help edits and support status changes need checking against their migrations.
- Fill any gap with append-only audit rows (actor, server UTC time, action, target, safe summary) that no client can edit.
- Add a read-only «سجل الإدارة» browser with keyset paging, filters by action family, admin and date range. PII values never appear in summaries.
- Acceptance: SQL tests for audit writes on every admin mutation and for read restrictions; React paging and empty-state tests.

## Phase 4 — subscription management extensions and broadcasts

Needs owner decisions before implementation; record them in a new ADR.

- **Codes (ADM-02):** presets for 1, 3, 6 and 12 months at 30 days per month (D-A2); revoke an unredeemed code with an audited reason; copy and share a single issued code. Bulk send waits for ADM-06 channels.
- **Broadcasts (ADM-06):** admin composes an Arabic message for all subscribers or a status or expiry segment; in-app delivery with durable per-shop read state; optional schedule and expiry; a sent history with counts. External channels (WhatsApp, email, push) are out of scope unless the owner adds them. Reuse the announcement banner component in Flutter.
- Acceptance: idempotent send, segment snapshot taken on the server, owner-only reads per shop, Flutter and React tests, visual review in both clients.

## Phase 5 — Help media

- Add a `help_media` R2 kind (key prefix, size and type limits, registry kind, tests, documentation) under ADR 0024, then admin upload and owner viewing for images and short videos. No Supabase Storage and no bytes in Postgres.

## Phase 6 — decision-gated work

- **RET-03 reset and deletion:** after D14, D15 and D29 are approved, build an owner request with a scoped preview and export, an admin review queue, and audited execution. No automatic deletion before legal review.
- **D21 support access:** only if the owner wants it: owner-approved, time-limited, read-only, audited access. Not part of ordinary admin access.

## Phase 7 — acceptance and publication

- Owner walkthrough of every admin area on development, with findings fixed or recorded.
- Host the admin dashboard on Vercel after development is finished (D-A5); the domain and account owner are confirmed at that point under D20. The production build (`npm run build`) and any deployment beyond development need the owner's explicit request.

## Owner decisions

Answered by the owner on 2026-11-10 unless marked otherwise.

| ID | Question | Decision |
|---|---|---|
| D-A1 | Phase order | **Accepted:** 1, 2, 3, then 4 |
| D-A2 | Does a "month" code mean 30 days or one calendar month from activation? | **Accepted:** one month = 30 days. Presets: 1 month = 30, 3 = 90, 6 = 180 days. The 12-month preset is 360 days (confirmed; may be revisited later). The existing custom day count (1–3660) stays. |
| D-A3 | ADM-06: channels, segments, scheduling, read tracking | **Accepted:** the broadcast recommendation below, approved as written. |
| D-A4 | Are there several admin roles (for example content-only or support-only)? | **Accepted:** no. One platform-admin role plus the existing per-admin contact-reveal flag. |
| D-A5 | Where is the admin dashboard hosted and who owns that account (D20)? | **Accepted:** Vercel, set up only after development is finished. No hosting work before Phase 7. |

## Broadcast contract (D-A3, approved 2026-11-10)

- **Channel:** in-app only. The app has no push service, WhatsApp Business API or verified email list, and each would add cost, consent and delivery-failure handling. Add an external channel later as its own decision.
- **Recipients:** shop owners only, matching the announcement and notice rules. Partners and employees do not see broadcasts.
- **Segments:** all shops; by subscription status (active, pending, expired); expiring within N days; one exact shop. The server freezes the recipient list when the message is sent; shops that register later do not receive it.
- **Content:** Arabic title (up to 80 characters), body (up to 1000), optional https link. No images or files in the first slice. A sent message cannot be edited; the admin may withdraw it, and the withdrawal is audited.
- **Timing:** send now or at a chosen time; optional end date after which it stops showing (default 30 days). Times are server UTC and shown in the admin's locale.
- **Owner experience:** a «الرسائل» inbox in «المزيد» with an unread count, and a banner for the newest unread message. Opening a message marks it read for that shop.
- **Admin reporting:** sent history with recipient, delivered and read counts per message. No per-person tracking beyond the shop.
- **Safety:** idempotent send keyed by the admin request; a confirmation step shows the recipient count before sending; reads are limited to the recipient shop's owner.

## Gates for every phase

Run React `npm run lint`, `npm test` and `npx tsc -b`; Flutter format, analyze and test when Flutter changes; meaningful SQL, RLS and atomicity tests for new RPCs; Arabic RTL visual review in both themes at mobile and desktop widths. Deploy tested Supabase changes to development `xchapwvmvoefriqcxtvn` under the standing authorization with a deployment record. No release builds, production deployment, commit or push without a direct request.

# ADR 0045: Admin overview home

Status: accepted (owner approved phase order 1–4 of the [admin completion plan](../operations/admin-completion-plan-2026-11-10.md) on 2026-11-10)
Date: 2026-11-10
Owners: product owner and engineering reviewer
Related requirement IDs: ADM-01 (statistics), product scope "operational metrics"
Supersedes: none

## Context

The platform-admin client opened straight into the subscriber directory. ADM-01 asks for statistics, and the product scope lists operational metrics. An administrator starting the day needs to see quickly how many shops are active, which subscriptions end soon, how many shops registered recently, and whether support inquiries are waiting. Example: an owner whose term ends in two days should be visible from the home page, one click away from the list behind it.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Compute figures in the browser from directory pages | No backend change | Needs every page; counts drift between requests; leaks more rows than needed |
| B. One admin-gated read RPC returning counts only | One snapshot, exact counts, no shop rows | One additive migration |

## Decision

Option B. `public.admin_get_overview_v1()` reuses `private.admin_subscriber_gate()` (live session, unbanned, confirmed platform admin) and returns one statement snapshot:

- subscription counts with the ADM-01 pending/active/expired rule;
- active shops whose term ends within rolling 3, 7 and 30 days of the snapshot (3 days matches the 72-hour ADM-03 renewal notice);
- shops registered within the last rolling 7 and 30 days;
- support inquiries in `new`, `in_progress` and `answered`;
- each platform's forced-update minimum (or none) and whether an announcement is published.

Windows are rolling durations from the server snapshot, not calendar weeks, so no shop time zone is needed and the server clock alone decides. Counts are exact decimal strings. No shop id, name, contact, location, Auth, financial, media, inquiry text or audit field is returned.

`admin_list_subscribers_v1` accepts `expiring_3`, `expiring_7` and `expiring_30` statuses with the same rule, so each subscription and expiring figure opens the list behind it (`/subscribers?status=…`). Existing statuses, ordering, cursors and fields are unchanged.

The React client makes «نظرة عامة» the home route `/` and the first navigation item. Figures that have a list are links; registrations and support figures are plain tiles, and support links to the mailbox. Loading, Arabic retry, refresh, revalidate-on-return and access loss follow the directory's behavior.

## Data and compatibility impact

Migration `20261110110000_admin_overview.sql` is additive: one private payload function, one public wrapper (execute for `authenticated` only, revoked from `anon`, `public` and `service_role`), and `create or replace` of the two directory functions with the extra statuses. Older admin clients keep working because existing parameters and responses are unchanged. Rollback is the previous directory function bodies plus dropping the two new functions; no data is written.

## Verification

- `supabase/tests/admin_overview.sql` (local, rollback-only): grants and function shape, every denied role (anonymous, missing user, ordinary owner with spoofed metadata, revoked, anonymous-user, deleted, banned admin, expired session), exact figures for eight synthetic shops including the 3-day and 7-day window edges, support and version figures, announcement state, no row leaks, directory expiring filters with order and search, `invalid_status`, and no state change. The ADM-01 suite still passes with this migration applied.
- `supabase/tests/admin_overview_hosted.sql`: rollback-only deltas around synthetic shops on development, agreement between the overview and the expiring list.
- React: strict parser and error mapping tests, overview page tests (figures, links, filtered list, shared filtered link, retry, access loss), routing tests.
- Visual: signed-in Arabic RTL review on development at 375 and 1240 pixels, light and dark.
- [Validation and deployment record](../reviews/admin-overview-2026-11-10/validation.md).

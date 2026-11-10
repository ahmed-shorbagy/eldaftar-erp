# ADR 0046: Platform-admin action history

Status: accepted (Phase 3 of the [admin completion plan](../operations/admin-completion-plan-2026-11-10.md), phase order approved by the owner on 2026-11-10)
Date: 2026-11-10
Owners: product owner and engineering reviewer
Related requirement IDs: delivery plan Milestone 5 "platform audit"; product scope "all admin changes are audited"; AUD-01 (shop-side history stays separate)
Supersedes: none

## Context

The product scope says every admin change is audited, and Milestone 5 lists a platform audit. Before this change, three admin actions already left history (code issuance, contact reveals, support status changes) but three did not: forced-update policy, Help topics and articles, and the platform announcement only kept "last updated by" on the current row. There was no screen to read any of it. Example: if Android users are suddenly forced to update, an administrator needs to see who raised the minimum, when, and from which version.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Add audit inserts inside each admin RPC | Explicit | Rewrites four reviewed functions; a future write path could forget |
| B. Row triggers on the content/policy tables, plus one merged read | Catches every write path; no RPC rewrite; unchanged saves write nothing | Actor comes from `auth.uid()`, so operator SQL is recorded with no actor |
| C. Copy every source into one new table | Single source | Duplicates existing append-only history |

## Decision

Option B, with option C rejected.

- New `public.platform_admin_audit_events` (append-only by trigger, RLS on, no client grants). After-insert/update/delete row triggers on `app_version_policies`, `help_topics`, `help_articles` and `platform_announcements` append one event per real change: actor `auth.uid()`, server time, family, action, target and a safe summary. Update triggers compare old and new rows, and the admin RPCs already skip identical payloads, so an unchanged save records nothing. Summaries keep platform and minimum (with the previous minimum), Help and announcement titles (first 120 characters) and published state. Bodies, messages and URLs are never copied.
- `public.admin_list_audit_events_v1(p_family, p_actor, p_cursor, p_page_size)`, behind `private.admin_subscriber_gate()`, merges newest first: code issuance (not owner redemption), contact reveals, admin support status changes (not owner submissions), and the new table. Each row has the admin's id and email, the shop id and name when the action concerns a shop, and the safe summary. Filters: family and admin. Keyset paging by `(occurred_at, event_key)`, 1–50 rows. The response also lists current platform admins for the filter.
- Admin emails are shown deliberately: the history must say who acted, and only platform admins can read it. Inquiry text, replies, revealed phone or location, code secrets and hashes, and shop contact or financial fields are never selected.
- The React client adds «سجل الإدارة» at `/audit`: family chips, an admin picker, one card per action (Arabic action, local time, summary, shop link to `/subscribers/<id>`, admin) and «تحميل المزيد». Empty, error/retry, stale-cursor reset and access loss follow the other admin pages.

## Data and compatibility impact

Migration `20261110120000_platform_admin_audit.sql` is additive: one table, five trigger functions, eight triggers, one private payload and one public read. Existing RPCs and responses are unchanged; older clients are unaffected. History starts at deployment: earlier forced-update, Help and announcement changes cannot be reconstructed. A date-range filter is not included. Rollback drops the triggers, functions and table; the table must be exported first if its history is to be kept.

## Verification

- `supabase/tests/admin_audit.sql` (local, rollback-only): table and function grants, append-only update/delete rejection, denied roles, real RPC writes producing exactly one event per change and none for unchanged saves (forced update set/clear, topic create/update, article create, announcement publish/update/clear), merged list of all six families newest first, owner redemption and owner submission excluded, no body or message text, actor and admin emails, family and admin filters, complete paging without duplicates, and invalid family/cursor/page size. A deliberately wrong expectation was confirmed to fail. The overview, app-version, Help and support suites pass with this migration applied.
- `supabase/tests/admin_audit_hosted.sql`: rollback-only publish/clear on development, recorded and listed with the admin email and without the body.
- React: strict parser, summaries and error mapping tests; page tests for rows and shop links, filters, paging, empty, retry and access loss.
- Visual: signed-in development review (empty history and admin picker) and a synthetic populated review at 375 pixels in light and dark.
- [Validation and deployment record](../reviews/admin-audit-2026-11-10/validation.md).

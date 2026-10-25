# ADR 0031: Help content and platform announcement

Status: implemented, locally verified and development-deployed for the bounded ADM-05 slice on 2026-10-25. [Validation](../reviews/help-content-2026-10-25/validation.md), [deployment/preservation](../reviews/help-content-2026-10-25/deployment.md). HELP-02 support contact, ADM-06 broadcasts, video, soft optional-update banners, in-context guides (ADR 0010/D22) and ADM-07 PII remain separate. Frontend publication and owner acceptance remain pending.

Related requirement IDs: ADM-05, HELP-01
Supersedes: none. Reuses `private.admin_subscriber_gate()` from [ADR 0027](0027-admin-subscriber-directory.md). Does not change [ADR 0024](0024-cloudflare-r2-media-storage.md) media kinds.

## Context

PAGES requires a searchable Help center that platform admins can update without an app-store release, plus user announcements. Ordinary owners must not gain admin or financial access. Guides and practice entry points stay removed.

## Decision

Platform-global Arabic FAQ: `help_topics` and `help_articles` with publish flags. One singleton `platform_announcements` row holds at most one published announcement (title, body, optional https link). RLS on; no table grants to `anon`/`authenticated`.

Authenticated owners read published catalog via `list_help_catalog_v1()` and the active announcement via `get_platform_announcement_v1()`. Unpublished rows are omitted. No shop, contact or financial columns. Expired authorized readers may read the same published content.

Platform admins manage content through security-definer RPCs gated by `admin_subscriber_gate()`: list all rows, upsert topic/article, set or clear the announcement. Publishing requires non-empty Arabic title and body; link must be https or null. Identical payloads are idempotent.

Flutter exposes Help from «المزيد» with client-side title/body filter. The workspace shows an announcement banner with **session-local** dismiss only (no durable dismiss table). Text-only: no Help R2 media kind.

## Data and compatibility impact

Migration `20261025110000_help_content_and_announcements.sql` is additive.

## Verification

SQL, Flutter and React gates cover admin-only writes, published-only owner reads, clear announcement and session-safe admin UI. Development deployment is separate.

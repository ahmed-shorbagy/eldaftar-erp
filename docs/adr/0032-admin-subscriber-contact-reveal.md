# ADR 0032: Admin subscriber contact reveal

Status: implemented, locally verified and development-deployed for the bounded ADM-07 slice on 2026-10-25. [Validation](../reviews/admin-subscriber-contact-2026-10-25/validation.md), [deployment/preservation](../reviews/admin-subscriber-contact-2026-10-25/deployment.md). Email and owner display name stay hidden. Directory list/get allowlists stay contact-free. D21 shop ledger access, grant-management UI, HELP-02 and ADM-06 remain separate. Frontend publication and owner acceptance remain pending.

Related requirement IDs: ADM-07
Supersedes: none. Extends [ADR 0027](0027-admin-subscriber-directory.md) with an explicit PII capability.

## Context

PAGES asks for subscriber city/country and phone under a platform-specific PII permission. ADM-01 deliberately omitted those columns. Admins must not gain them through table SELECT or by widening the directory payloads.

## Decision

Add `can_view_subscriber_contact boolean not null default false` on `public.platform_admins`. Existing platform-admin rows are set to `true` in the migration so the current operator can reveal without a grant UI.

`private.admin_subscriber_contact_gate()` requires `admin_subscriber_gate() = 'ok'` and the flag. `public.admin_get_subscriber_contact_v1(shop_id)` returns only `shop_id`, `phone`, `country_code` and `location_display_ar` (Egypt governorate Arabic name, otherwise `region_name`). Each successful reveal inserts an append-only row into `public.admin_subscriber_contact_reveals`.

React subscriber detail shows masked placeholders and an Arabic reveal action. Forbidden when the flag is false. Session replacement discards late replies like other admin RPCs.

## Verification

SQL denies reveal without the flag; list/get function definitions still omit phone/email/governorate; React covers reveal success and forbidden. Development deployment is separate.

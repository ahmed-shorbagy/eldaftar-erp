# ADM-03 subscription expiry notices — local validation — 2026-10-25

Bounded in-app notices under [ADR 0029](../../adr/0029-subscription-expiry-notices.md). Outbound dispatch, contact/location, retention/deletion and financial access were not included. Frontend publication and owner acceptance remain pending.

## Agreed product rules exercised

- `renewal_due` while active and within 72 hours of `expires_at`.
- `expired` when `now() >= expires_at`.
- One durable dismiss per owner, shop, kind and current entitlement expiry.
- Dismissing the reminder does not hide the later expiry notice.
- D13 write block and the permanent read-only banner remain after the expiry notice is dismissed.

## Backend

Migration [20261025093000_subscription_expiry_notices.sql](../../../supabase/migrations/20261025093000_subscription_expiry_notices.sql) adds `public.subscription_notice_dismissals`, `private.subscription_notice_kind`, `private.subscription_notice_owner_session`, `public.list_my_subscription_notices_v1` and `public.dismiss_subscription_notice_v1`. `list_my_shop_accounts` is unchanged.

Local disposable PostgreSQL runner [subscription_expiry_notices_local_runner.ps1](../../../supabase/tests/subscription_expiry_notices_local_runner.ps1):

- Migration rollback removed the new table and RPCs and left `list_my_shop_accounts` fingerprint unchanged: `SUBSCRIPTION_EXPIRY_NOTICES_MIGRATION_ROLLBACK_PASSED`.
- Fixture [subscription_expiry_notices.sql](../../../supabase/tests/subscription_expiry_notices.sql): 73-hour silence, 72-hour `renewal_due`, dismiss then expiry notice, expired-owner dismiss without restoring writes or mutating the entitlement, renewed `expires_at` notice pair, foreign/stale/anonymous/pending rejection: `SUBSCRIPTION_EXPIRY_NOTICES_SQL_PASSED`.

## Flutter

`dart analyze` on shop accounts and workspace: no issues.

`flutter test test/shop_accounts_gate_test.dart`: 15 passed, including renewal dismiss, failed-dismiss retry copy, expired notice dismiss leaving the read-only access banner and renew control, and Arabic RTL light/dark review at 320 and 1440.

## Limits

No native device, two-session or owner acceptance run. No push/email/WhatsApp/OS notification claim. Development application and hosted rollback verification are recorded in [deployment.md](deployment.md). Independent review and owner acceptance remain separate.

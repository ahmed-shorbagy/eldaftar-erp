# ADR 0038: Four-month retention clock and the 30-day warning

Status: accepted by the product owner on 2026-11-01, implemented, locally verified, and development-deployed on `xchapwvmvoefriqcxtvn` (migration `20261101120000`). [Validation](../reviews/subscription-retention-2026-11-01/validation.md), [deployment](../reviews/subscription-retention-2026-11-01/deployment.md). Deletion and account reset stay out.
Related requirement IDs: RET-01, RET-02. RET-03 remains open.
Supersedes: none. Reuses D13 read-only expiry and the notice dismissal table from [ADR 0029](0029-subscription-expiry-notices.md). Renewal stays [ADR 0028](0028-admin-subscription-code-issuance.md).

## Context

PAGES asks for four months of retention after a subscription expires, a warning 30 days before the end, and restoration if the shop renews. D14 and D15 still have no approved deletion or reset scope. The owner approved this slice on 2026-11-01: start the clock at expiry, warn once during the last 30 days, and let an existing code redemption restore writing. Nothing is deleted.

Example. A shop in `Africa/Cairo` expires at 2026-01-31 00:00 in that zone. Retention ends at 2026-05-31 00:00 in that zone. The warning is visible from 2026-05-01 00:00 until, but not including, 2026-05-31 00:00. Renewing before that instant extends `expires_at`. The ledger rows stay where they are.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Delete shop data at the retention end | Matches a literal reading of the source | D14 and D15 are still open. Automatic deletion can destroy audit history |
| B. Count four calendar months in the shop zone, warn for the last 30 local days, and delete nothing | One server clock, durable dismissal, renewal already restores writes | After the warning window the shop stays read-only with its data. A later deletion decision is still required |
| C. Show the warning from a device clock | No schema change | The device date can open or hide the warning early |

## Decision

Option B.

Retention ends at the entitlement `expires_at` plus four calendar months, computed in `private.shop_display_zone(shops.time_zone)`. An invalid zone uses `Africa/Cairo`. The warning starts 30 shop-local days before that end and stops at the end instant. It is shown only while the shop is already expired (`now() >= expires_at`). Active and pending shops do not see it.

The warning is a third notice kind, `retention_ending`, on the existing dismissal table. The owner, including an expired reader, may dismiss it once for the current `expires_at`. Dismissing `expired` or `renewal_due` does not hide it. A new `expires_at` from code redemption starts a new pair of keys. Partners, employees, and every non-owner session receive no row.

The Arabic banner names the shop-local end date. It says renewal before that date restores writing, and that this notice does not delete data. «إخفاء التنبيه» and «تجديد الاشتراك» behave as the other notices. The permanent read-only state remains after dismissal and after the window closes. During the window the server returns `retention_ending` instead of `expired`, so the owner sees one notice. After the window, an undismissed `expired` notice can appear again.

`redeem_subscription_code` is unchanged. Extending `expires_at` into the future is what restores writing. The command does not rebuild or wipe books. There is no reset control and no admin path into the shop ledger.

## Data and compatibility impact

Migration `20261101120000_subscription_retention_warning.sql` widens the dismissal kind check and replaces the notice kind, list, and dismiss functions. The list gains `retention_ends_at` and `retention_ends_on`. Both are null except for `retention_ending`, where `retention_ends_on` is `YYYY-MM-DD` in the shop zone. No backfill and no delete. Rollback restores the previous three-argument kind function and the previous list. Old clients that reject an unknown kind keep the last notice and do not enter the shop ledger through this failure.

## Verification

SQL covers the 31 January to 31 May calendar step, the instant the warning opens, the instant it closes, an invalid zone falling back to Cairo, owner list and one dismissal, a stale `expired` dismiss during the warning, unchanged financial-operation and shop counts, write denial during the warning, write restoration after `expires_at` moves forward, and an employee seeing nothing. Flutter covers the date, the no-deletion sentence, dismiss, and the read-only state that remains. Owner and device acceptance stay open.

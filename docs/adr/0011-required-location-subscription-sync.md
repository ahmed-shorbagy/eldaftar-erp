# Required location, subscription codes, and shop sync

Status: accepted product direction; deployed to development after explicit owner authorization
Date: 2026-10-11
Supersedes: optional-region clauses in ADR 0010 for new registrations only

New owner registration requires a location. Egypt must send an ISO catalog governorate. Other supported countries must send a non-empty `CC:label`. Stored historical `CC:` and `EG:text` values remain valid for table checks and confirmed-registration replay.

Subscription access uses hashed single-use codes issued by platform admin or service-role operators. Owners redeem through a dialog. Failed attempts persist by returning typed statuses. Raw codes are never stored. Pending owners may read sync revision rows only.

Shop clients drop page-top reload controls and follow `shop_sync_signals` plus a modest poll. Open trader, invoice, and catalog routes listen to the same ticks so a pushed route does not go stale.

No hosted migration or production issuance is authorized by this decision.

The subsequent owner-authorized [development deployment](../reviews/owner-feedback-batch1-2026-10-11/deployment.md) applies this contract to xchapwvmvoefriqcxtvn. No application distribution or production code issuance occurred.

# Release and recovery runbook

This is a preparation checklist, not evidence that production infrastructure exists. Assign named owners and approved recovery objectives before launch.

## Before every release

1. Confirm scope, ADRs, migration review and synthetic staging acceptance. Record app/admin/backend versions and contract compatibility.
2. Confirm automated tests, RLS role matrix, concurrent idempotency and financial reconciliation checks passed. Compare Arabic RTL light/dark screens with approved references.
3. Verify production backup status and perform a recent staging restore. Check R2 object references and protected access with synthetic data.
4. Check migration plan, lock duration, backfill, old-client overlap and rollback/compensation. Define a stop condition for projection drift or command failures.
5. Prepare Arabic release notes, support guidance and pilot shops. Use owner-controlled store/cloud accounts; publish only with direct authorization.

## During rollout

Monitor command success/failure and pending reconciliation age, idempotency conflicts, RLS denials, projection sequence lag, cash/gold reconciliation, R2 upload failures, invoice dispatch queue, subscription jobs and app-version adoption. Keep correlation IDs without recording customer payloads. Pilot financial changes and compare each shop's expected cash and grams to independent counts.

## Incident response

1. Identify affected shops, command versions and time range. Preserve logs, operation IDs and backup state.
2. If journal integrity is at risk, stop new financial commands while keeping status lookup and authorized read/export available where feasible. Do not edit confirmed postings directly.
3. Reconcile the authoritative journal, balance projections and external payment/dispatch evidence. Determine whether requests committed or remained pending.
4. Repair via approved compensating operations or a tested projection rebuild. Test against a staging copy first. Audit the actor and reason.
5. Communicate confirmed user impact in Arabic through approved channels, then write a post-incident decision and regression tests.

## Restore rehearsal

Restore Postgres and referenced R2 objects to staging from a named backup. Validate shop isolation, owner access, counts of operations/postings, cash by method, grams by karat, invoice/attachment availability and a sample day close. Measure actual recovery time and data loss window against approved targets. Do not overwrite production as a routine test.

## Subscription retention and deletion

Run a dry-run report of cases entering warning or deletion eligibility. Verify exact expiry and warning time, legal hold, renewal, backups and audit policy. Require approved deletion semantics before enabling the final purge worker. Keep deletion evidence without retaining forbidden customer content.

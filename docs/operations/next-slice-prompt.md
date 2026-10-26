# Current task pointer — 2026-10-26

The bounded shop staff grants and shop profile slice is implemented, locally verified and development-deployed: [ADR 0033](../adr/0033-shop-staff-grants-and-profile.md), [validation](../reviews/shop-staff-2026-10-26/validation.md), [deployment/preservation](../reviews/shop-staff-2026-10-26/deployment.md). Partner/employee memberships use server grants; owner-only profile edits and `shop-staff-create` are live on development. Owner-only financial close and temporary count assignments remain under ADR 0023. Next proposed bounded feature is not selected; candidates remain HELP-02, ADM-06, DOC-04 native invoice-output harness, month/year analytics, and Milestone 4/5 acceptance.

## Previous pointer — 2026-10-25

The bounded ADM-07 subscriber contact/location PII reveal slice is implemented, locally verified and development-deployed: [ADR 0032](../adr/0032-admin-subscriber-contact-reveal.md), [validation](../reviews/admin-subscriber-contact-2026-10-25/validation.md), [deployment/preservation](../reviews/admin-subscriber-contact-2026-10-25/deployment.md).

## Previous pointer — 2026-10-25 (ADM-05)

The bounded ADM-05 Help FAQ and platform announcement slice is implemented, locally verified and development-deployed: [ADR 0031](../adr/0031-help-content-and-announcements.md), [validation](../reviews/help-content-2026-10-25/validation.md), [deployment/preservation](../reviews/help-content-2026-10-25/deployment.md).

## Previous pointer — 2026-10-25 (ADM-04)

The bounded ADM-04 minimum-version / forced-update slice is implemented, locally verified and development-deployed: [ADR 0030](../adr/0030-app-version-forced-update.md), [validation](../reviews/app-version-forced-update-2026-10-25/validation.md), [deployment/preservation](../reviews/app-version-forced-update-2026-10-25/deployment.md).

## Previous pointer — 2026-10-25 (ADM-03)

The bounded ADM-03 in-app subscription-expiry notices slice is implemented, locally verified and development-deployed: [ADR 0029](../adr/0029-subscription-expiry-notices.md), [validation](../reviews/subscription-notices-2026-10-25/validation.md), [deployment/preservation](../reviews/subscription-notices-2026-10-25/deployment.md). Owner-confirmed thresholds are a 72-hour `renewal_due` reminder while the term is active and a separate `expired` notice after the server clock passes `expires_at`. Each notice dismisses once for the current entitlement expiry; the permanent read-only banner and renewal action remain. Outbound dispatch, contact/location, retention/deletion and financial access stay excluded. Frontend publication and owner acceptance remain pending.

## Previous pointer — 2026-10-22

The bounded ADM-02/ADM-08 issuance and history slice is implemented: [ADR 0028](../adr/0028-admin-subscription-code-issuance.md), [implementer validation](../reviews/admin-subscription-codes-2026-10-22/validation.md). Independently reviewed and verified; backend deployed and rollback-verified on development `xchapwvmvoefriqcxtvn`. Frontend publication and owner acceptance remain pending. [Independent validation](../reviews/admin-subscription-codes-2026-10-22/independent-validation.md), [development deployment/preservation](../reviews/admin-subscription-codes-2026-10-22/deployment.md).

The bounded ADM-01 directory slice remains independently verified and development-deployed: [ADR 0027](../adr/0027-admin-subscriber-directory.md), [final review](../reviews/admin-subscribers-2026-10-22/independent-validation.md), [deployment/preservation](../reviews/admin-subscribers-2026-10-22/deployment.md). Contact/location permissions, owner acceptance, DOC-04 native reliability and Milestone 5 remain open.

The paragraph below is the historical recommendation that selected this directory. It is not a statement that the directory is still unbuilt.

Recommended next real feature: **ADM-01 subscriber directory and subscription overview in React admin**. Deliver protected metadata reads, server-derived subscription counts/status, search/filter/paging and read-only detail. [Feature plan](admin-subscribers-plan-2026-10-22.md), [ready-to-paste implementation prompt](admin-subscribers-prompt-2026-10-22.md). This is a recommendation prepared for selection, not an implementation performed by the documentation task. Subscription mutations, contact/location permissions and shop financial access remain separate.

Weekly Reports is locally verified and applied on development: [validation](../reviews/weekly-reports-2026-10-22/validation.md), [deployment](../reviews/weekly-reports-2026-10-22/deployment.md), [follow-up examination](../reviews/weekly-reports-2026-10-22/follow-up-review.md). Native/owner acceptance and Milestones 4/5 stay open. The DOC-04 harness remains [acceptance/reliability backlog](../reviews/stabilization-2026-10-21/acceptance.md). The earlier task pointers below are historical context, not the current next-task recommendation.

## Previous pointer — 2026-10-21

Latest continuation: weekly Reports is implemented locally under [ADR 0026](../adr/0026-weekly-financial-reports.md). The owner explicitly deferred checks and verification to continue feature implementation. [Local status and deferred work](../reviews/weekly-reports-2026-10-21/implementation.md) tracks the pending weekly migration, shared daily code regression needs and later development deployment. Do not treat earlier daily test/deployment evidence as verification of this weekly source. No later implementation feature or admin dashboard was selected in this continuation.

The owner subsequently selected and authorized the first Reports implementation slice. The selected financial-day report and Arabic PDF contract is [ADR 0025](../adr/0025-selected-financial-day-reports.md); [validation](../reviews/reports-2026-10-21/validation.md) and [development deployment](../reviews/reports-2026-10-21/deployment.md) are its current pointers. Weekly Reports is now selected and locally implemented in the continuation above; admin dashboards remain unselected. The native invoice-output acceptance recommendation below remains open and separate. No commit, push, application publication or release/production build is part of Reports delivery.

October 21 stabilization and Milestone 4 reconciliation supersede the slice-11-only pointer below. See [validation and implementation fixes](../reviews/stabilization-2026-10-21/validation.md), [development reconciliation](../reviews/stabilization-2026-10-21/development-reconciliation.md), and [remaining acceptance plus one next-task recommendation](../reviews/stabilization-2026-10-21/acceptance.md). Milestone 4 remains open. PDF/image output exists; text-only invoice messaging/settings are retired from current navigation. Device/owner acceptance and legal invoice content are separate.

## Historical Milestone 4 slice 11 pointer

The owner explicitly confirmed the entire D35 bundle on 2026-10-18. The reviewed [dated plan](invoice-messaging-slice-prompt-2026-10-18.md) and byte-identical [submitted archive](invoice-messaging-submitted-prompt-2026-10-18.md) remain historical sources.

See [current bounded completion and acceptance status](invoice-messaging-completion-status-2026-10-18.md). The owner subsequently directly authorized the [reviewed development application](../reviews/invoice-messaging-2026-10-18/deployment-2026-10-19.md), now applied with preservation checks. That authorization does not authorize publication or select a later feature. No next implementation slice is selected. DOC-01 beyond appearance, DOC-04, Milestone 4, wider design approval and native/owner acceptance remain open.

# Next slice — Customers (العملاء)

Recommended on 2026-10-13: Milestone 4 slice 3, the customer directory and notes workflow, CRM-01 and CRM-03. This is planned scope, not implementation or accepted product behavior. Preparing this prompt performs no deployment or application change. The previous opening-balance prompt is [historical](opening-balances-slice-prompt-2026-09-26.md).

Repairs and DEBT-01 are implemented and deployed to development; native owner acceptance remains open. The debt record also retains an SDK `flutter analyze` launcher limitation and the initial hosted ledger failure repaired by the second migration. Before expanding scope, repair/check that SDK gate and complete a focused debt HTTP ledger-read regression. Do not repeat already-passed suites without a change or unresolved failure. [Debt validation](../reviews/debts-2026-10-13/independent-validation.md), [deployment and migration mappings](../reviews/debts-2026-10-13/deployment.md).

Choose customers next because the basic directory supplies explicit identities for later statistics/contact actions. Debt reminders DEBT-02/03 still depend on due-date, notification-channel and platform-delivery rules under D19. Debt PDFs can be a separate bounded export task. None of these is silently included here. Existing transaction names/phones are snapshots, not a customer directory; do not identify or merge parties by name alone.

Documentation review on 2026-10-13: delivery plan, matrix, docs index, current prompt and preserved historical prompt checked for consistency/privacy; all 114 local links resolve and no credential-shaped values were found. `git diff --check` passed. This documentation-only task ran no application tests/builds and made no remote changes. Historical validation records remain untouched.

## Implementation prompt

Implement Milestone 4 slice 3: Customers (العملاء), bounded requirements CRM-01 and CRM-03, in D:\Eldaftar ERP.

Follow AGENTS.md. Before editing, read docs/design-system.md, delivery-plan.md, requirements-matrix.md, product-scope.md, the relevant customer requirements/source reconciliation, ADRs 0003, 0007, 0009, 0010 and 0013, current debt validation/deployment records, and existing transaction party snapshots, owner authorization, command recovery and shop-sync contracts. Inspect the actual code/schema; historical discovery inventory is not the current implementation state.

Use grok-delegate for small sequential implementation tasks, ui-ux-pro-max for UI, and the connected Supabase plugin for backend inspection and deployment. Grok must not commit, push or mutate the remote project. Codex reviews every diff and validates independently. Preserve existing uncommitted work and unrelated configuration edits.

Deliver one complete owner workflow:
1. Create and edit a customer with an Arabic display name and multiple validated phone numbers; choose a primary number. Prevent duplicate normalized phone numbers within one customer and conflicting ownership within the shop. Handle customers without a phone if source requirements allow; document the working rule. Do not collect device contacts or silently import ledger, repair or debt parties.
2. Provide searchable, paginated Arabic lists and details, sort by name or last explicitly linked confirmed transaction, and show phone numbers with LTR isolation. Customers without activity must have an honest empty state. Keep customer-updated time distinct from transaction time.
3. Add immutable dated notes, show latest-note preview, and edit VIP and open-request status with audit history. Do not replace or erase previous note/audit entries.
4. Let the owner explicitly associate an existing confirmed sale/purchase with the customer after reviewing party/operation identity. Store an audited association separately from immutable financial payloads and invoice snapshots. Reject cross-shop/nonconfirmed associations and duplicate links; any correction to an association preserves history. Never infer a financial relationship from a matching name/phone. Show linked history and actual last activity without posting money, gold, custody, stock or debt effects.
5. Provide reviewed archive/restore as the working deletion policy so linked financial history survives. Do not hard-delete customer-linked finance or rewrite original party snapshots. Record this as a bounded working assumption unless documentation already specifies the policy.

Enforce owner-only authorization and RLS; no platform-admin access to shop CRM. Commands must be atomic, audited, idempotent and version-checked. Disable duplicate submission, preserve unknown requests for reconciliation, show success only after server confirmation and synchronize customer changes across active sessions. Expired/revoked and cross-shop behavior must follow existing contracts. Persist server UTC timestamps and display the configured shop locale/time zone.

Use Flutter Clean Architecture, Arabic RTL, shared tokens, both themes and responsive phone/desktop layouts. Preserve Batch 1/2, repairs, debts, ledger, immutable invoices and existing stock/account behavior. Resolve ordinary choices from documentation and record necessary working assumptions. Do not show unfinished controls as operational.

Exclude CRM-02 weight/statistical summaries, CRM-04/05/06 calling/WhatsApp/contact-permission features, automatic contact import, merges, reminders, PDFs, reports, invoice customization and new financial operations. Do not infer delivered/saved WhatsApp state.

Add meaningful normalization, permissions/RLS, cross-shop links, optimistic concurrency, atomic rollback, retry/reconciliation, synchronization and critical UI tests. Repair/check the documented Flutter analysis SDK limitation without masking it. Run required scoped gates once, with additional checks only for new changes/failures; review phone/desktop Arabic RTL in both themes. First verify the repaired debt ledger read through authenticated hosted HTTP with synthetic actors and no unnecessary financial posting; record remaining native-device acceptance honestly.

This implementation request authorizes Codex to deploy reviewed additive CRM migrations only to development Supabase project xchapwvmvoefriqcxtvn through the connected plugin. Reconcile the documented local/hosted migration mappings; do not blindly db push or rewrite prior history. Verify hosted commands, RLS, retries and Realtime with synthetic actors; retire their sessions/memberships/entitlements while preserving audit evidence. No real customer data in tests or documentation.

Update the matrix, delivery plan, design/contract decisions and exact validation/deployment records. Preserve historical evidence. No commit, push, application publishing, Auth policy changes or release/production builds. Finish concisely with delivered behavior, exact results and remaining acceptance limits.

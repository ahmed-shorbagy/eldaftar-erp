# Next feature plan: ADM-01 subscriber directory — 2026-10-22

Status update 2026-10-22: the owner selected this slice and Grok delegation. The bounded directory is independently verified and development-deployed: [review](../reviews/admin-subscribers-2026-10-22/independent-validation.md), [deployment/preservation](../reviews/admin-subscribers-2026-10-22/deployment.md), [ADR 0027](../adr/0027-admin-subscriber-directory.md). The original examination/planning text below remains historical; owner acceptance and wider admin scope remain open.

Status: proposed next implementation slice following weekly Reports completion. The owner's current request authorizes examination and documentation, not implementation of this feature. [Weekly follow-up review](../reviews/weekly-reports-2026-10-22/follow-up-review.md), [ready-to-paste feature prompt](admin-subscribers-prompt-2026-10-22.md).

## Why this feature

Daily and weekly shop Reports are implemented and development-verified. The independent React administration client still provides authentication, theme controls and a prototype shell: `admin/src/shell/HomeShell.tsx` has no subscriber directory. ADM-01 in the [requirements matrix](../requirements-matrix.md) requires a directory and statistics. Existing `public.shops`, `public.shop_entitlements` and `public.is_platform_admin()` provide a bounded starting point without introducing new financial rules or granting platform staff access to shop operations.

## Proposed first-slice behavior

- An authenticated platform administrator opens «المشتركون» and sees persisted shops, including those pending activation. A row contains only shop identifier/name, server registration time, entitlement start/expiry when present, and derived subscription status. Do not return owner contacts, location, Auth identity records or any financial/CRM data in this slice. A shop's subscription status is not a claim that its owner's account is enabled.
- Search by shop name or exact shop identifier, filter by subscription status, and page on the server with deterministic ordering by registration time and identifier. Use a bounded page size, reset paging when filters change, and handle empty results and invalid/stale cursors. No download/export or disabled mutation controls are needed.
- Retain current entitlement semantics from `list_my_shop_accounts`: pending when absent or not started; active when `starts_at <= server_now < expires_at`; expired otherwise. A future term remains pending; missing dates display clearly. One persisted shop is one subscriber for this overview. Do not silently exclude shops because ownership or a subscription is revoked/expired.
- Show global counts for all shops and active/pending/expired subscriptions, with an explicit server snapshot time. Label the filtered result count separately. Derive a response's rows/counts/status from one consistent server snapshot. Transport exact counts as integer strings; use exact client parsing. Refresh updates status at boundaries without trusting the browser clock as the accounting source.
- Provide a read-only subscription detail panel for the selected shop using the same allowlisted metadata. Loading, refresh, retry, access loss, empty state and late-response disposal must be Arabic and truthful. Recheck access on requests and resume/refresh, clear content when admin access is lost, and retain valid search/filter state on a successful refresh.

The first layout follows existing React MUI components and `docs/design-system.md`: RTL search/filter toolbar, summary cards, desktop table and narrow-screen cards, with an accessible detail panel. Reuse the brown/cream/dark semantic tokens and persisted theme. Review Arabic light/dark at 320/390/1440 widths and ordinary/enlarged text. No Flutter screen or palette change is proposed.

## Authorization and data boundary

Introduce only narrow admin-checked read contracts, with no broad SELECT grant or weakening of owner RLS. Use the existing live platform-admin identity/session check on every call; user-editable metadata cannot grant access. Anonymous callers, ordinary owners, temporary count staff, revoked admins and invalid/expired sessions must fail. Admin access must still fail against ledger, customer, invoice and report APIs. Do not add support impersonation, general staff roles, owner administration or grant-management UI.

The read path has zero financial, entitlement, dispatch and business-audit effects. Backend schema additions should be limited to the reviewed read API and necessary indexes; no subscription mutation, contact/PII permission system or code lifecycle is required for this first slice. Record the bounded contract in an ADR when implementation begins, with status matching the submitted scope.

## Delivery and subsequent work

1. Inspect current schema/session checks, record the read contract, and add meaningful rollback-only authorization/paging/status tests.
2. Implement the operational Arabic React directory, statistics and detail states against real protected reads; remove prototype framing only from the delivered area.
3. Run scoped formatting, Flutter analysis/tests, React lint/tests/`npx tsc -b`, affected fresh SQL/RLS/preservation checks, and actual Arabic responsive/theme review. Any known analyzer fallback must be reported precisely. No release/production builds.
4. Reconcile development `xchapwvmvoefriqcxtvn`, deploy only missing tested task changes under standing authorization, verify hosted real-role boundaries with rollback fixtures, and record preservation of financial data, existing entitlements and migration history.
5. Update evidence and current pointers. ADM-01 progresses only for the delivered subset; ADM-07 PII and native/owner acceptance stay separate. No application publication, commit or push.

After this first directory slice, propose subscription-code issuance/redemption (ADM-02/ADM-08) with an explicit term, activation/renewal and retry contract. Contact/location permissions (ADM-07), notifications, Help content, forced updates and retention/deletion remain separate feature slices. The DOC-04 native invoice-output harness and other device acceptance remain visible backlog; they do not replace this next product-feature recommendation.

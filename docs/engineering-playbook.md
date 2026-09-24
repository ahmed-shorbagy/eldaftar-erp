# Engineering playbook

## How to start a change

Read AGENTS.md, the relevant scope row, architecture.md, database-design.md and existing code. Identify the user-visible behavior, exact server effect, role, audit event, synchronization state, and failure response before changing UI. Check decisions.md; if a pending decision changes stored meaning, settle it before a migration. Work in a small vertical slice and keep unrelated cleanup separate. Source documents and agreement details remain local, outside Git.

For every financial feature, write a short operation contract first: input, value units, preconditions, affected accounts/stock buckets, shop-scoped idempotency identity, expected version, audit event, output, reconciliation lookup, and compensating action. Include ownership and physical custody when a financier or repair is involved. Use at least one realistic worked example with expected money minor units and milligrams. Product and backend reviewers approve that example before implementation.

## Client implementation conventions

Flutter follows Clean Architecture per feature. Domain value objects validate grams, money, karat, count and identifiers without importing Flutter, Supabase or storage. Use cases own application flow and depend on repository interfaces. Data adapters parse versioned DTOs and map server errors into domain outcomes. Presentation state has explicit draft, loading, pending reconciliation, success and failure states. Widgets do not calculate authoritative balances or bypass use cases to write Supabase tables.

React admin uses independent feature modules and API adapters. It never imports Flutter code. It needs its own platform-admin session boundary and safe handling of token expiry. Shared contracts should be generated from a reviewed backend schema where possible; generated code is committed only when reproducible and reviewed.

Keep Arabic strings in localization resources or a coherent copy module, including errors, accessibility labels, empty states and exports. Use RTL-aware layout and logical paddings/alignment. Store theme preference and honor it in both clients. Use the shared token specification while allowing platform-native interaction patterns. UI defaults can speed sale entry but cannot change domain validation.

## Backend command checklist

1. Authenticate the caller and derive actor/shop permissions on the server.
2. Parse versioned payload into exact integer units; reject malformed/overflow values and unsupported karats.
3. Check shop-scoped idempotency key plus payload hash before creating effects; actor is an audit attribute, not part of key uniqueness.
4. Check expected business-day/record version and lock affected rows in a consistent order.
5. Validate category/karat rules, the minimum lot and scrap model, stock count and mg, cash/debt constraints and same-shop references. Never ship a sale that cannot atomically post its stock effect.
6. Write operation, typed details, balanced journal postings, audit and outbox within one transaction.
7. Return the existing stable outcome on an identical retry; reject key reuse with different input.
8. Provide a status lookup by key for timeout reconciliation.
9. Expose a scoped read model with sequence/cursor and test RLS against real authenticated roles.

Implement each financial command as one versioned, narrowly granted PostgreSQL RPC with fixed search_path. Never make a sequence of client API writes masquerade as one transaction. Never report “saved” before the server confirms. Do not delete or edit a confirmed journal to fix a mistake; create an authorized reversal/correction linked to the original. A business-day close and an inventory edit need elevated permission beyond generic transaction entry.

## Synchronization and offline behavior

Local storage may contain drafts and pending command metadata, encrypted when customer or invoice information is present. It is not an authoritative ledger. Persist the original idempotency key with a queued command and never generate a new key for retry. On reconnect, query command status, then re-fetch the shop feed from the last acknowledged server sequence. If the cursor is too old, fetch a scoped snapshot and continue from its sequence. Show pending items separately from confirmed totals; projected “what if submitted” values must be labeled as estimates in Arabic.

Realtime subscription delivers invalidation hints. Mobile sleep, Windows offline use and dropped websocket events require cursor catch-up. Resolve stale edits with server version conflicts and a user-visible review of current values. Never silently use last-write-wins for cash, gold or permissions. A confirmed mutation can be shown optimistically only after the server result is known.

## UI and accessibility review

Start from an approved design reference and list target viewports. The supplied images illustrate the daily ledger, sale wizard, light/dark themes and WhatsApp invoice path; confirm whether they are final before using pixel comparison as an acceptance gate. Check spacing, type, icon meaning, focus order, touch target size, contrast, dynamic text, keyboard use on Windows, loading and empty/error states. Validate Arabic number/date display without altering stored numeric meaning. Test mixed Arabic/Latin names, phone numbers and invoice identifiers for bidirectional text behavior.

Capture representative screenshots for phone, larger mobile/desktop and admin widths in both themes. Verify rights to ship the chosen Arabic fonts and test PDF/image invoice output, receipt layout and local Windows printing with Arabic glyphs. Compare with approved baselines and document intentional platform differences. Automated golden tests should cover stable, high-value layouts; manual review catches clipped Arabic text and responsive defects. Do not create a clickable prototype control for an absent backend action unless it is plainly labeled in Arabic as demo content.

## Test pyramid and gates

| Layer | What it proves | Examples |
| --- | --- | --- |
| Domain unit/property | exact arithmetic and invariant rules | 1.830 g stays 1830 mg; mixed tender sums; journal balance; karat restriction |
| SQL/integration | atomicity and authorization | failure rollback; concurrent retry; cross-shop FK; RLS role matrix; day-close race |
| Contract | clients agree with server payloads and errors | command versioning, pending lookup, generated types |
| Widget/component | Arabic interaction and state transitions | multi-item sale, permission-hidden action plus server denial, pending/retry |
| End-to-end | real client to staging database | sale -> ledger -> inventory -> invoice; three-party financed purchase -> custody and obligation |
| Visual/accessibility | design and usability | RTL light/dark, phone/desktop, screen reader labels, keyboard focus |
| Operational | recovery and lifecycle | migration/backfill strategy, backup restore, retention warning, R2 orphan cleanup |

Meaningful tests exercise a rule or failure mode; do not add tests that merely restate a widget tree or implementation branch. Add a regression test when fixing a defect. Use synthetic shops and customers. RLS tests should impersonate real auth identities and include negative assertions. Concurrency tests should run actual parallel commands. Inject lost response after commit, delayed response, dropped connection, duplicate tap and missed realtime event. Check that a reconciling client never shows an unconfirmed operation in authoritative totals. Define and measure a live-ledger response and refresh budget on representative low-bandwidth devices before pilot. Property tests are valuable for posting balance and projection equality.

Current package commands are listed in README.md. Run Flutter formatting/checks, flutter analyze, flutter test, flutter build windows and flutter build apk where the toolchain is available. Run npm run lint, npm test and npm run build in admin. The Supabase package currently has connectivity checks only; do not treat those as database, RLS or transaction tests. Add schema lint, migration reset and policy/command test commands before financial code ships. Network credential checks should run only in authorized environments and must not print secrets. iOS build and signing need macOS and owner-controlled credentials. Prepare store privacy disclosures and account-deletion/support URLs before submission.

For documentation-only work, check links, consistency with source and current code, privacy, and Git diff. Report which application gates were skipped because no executable behavior changed, rather than implying they passed.

## Migration and release routine

Use migration files in order and review the generated schema diff. Changes to financial tables require backfill, reconciliation, old-client compatibility and rollback/restore plan. Test from an empty schema and from the previous release's synthetic dataset. Snapshot production before a destructive migration and verify restore in staging. Apply production migration before a compatible client rollout, with feature flags only for exposure, never for authorization. Track minimum supported app versions and keep commands backward compatible over the rollout window.

Create staging release notes in Arabic for user-facing changes. Pilot a financial feature with a small shop cohort and compare daily paper/cash/gold results. Define alert thresholds and owner for each incident. A failed release can stop new commands while leaving read/export and pending-status lookup available when feasible. Do not deploy, publish, or use owner store accounts without direct authorization.

## Security, privacy and review

Never commit .env.local, service-role keys, R2 credentials, raw contracts, customer lists, phone numbers or production exports. Keep private uploads in R2 and issue short-lived scoped URLs. Review access to log events, analytics and support tooling because they can leak sensitive data even when tables have RLS. Use least-privilege server secrets and rotate them if exposed. A support/admin override needs a separate auditable process.

Review each change against the scope contract, dependency direction, transaction effects, RLS, idempotency, Arabic copy, RTL themes, and test evidence. Grok may implement a scoped task when authorized, but it does not commit or push. Codex reviews the diff and reruns relevant gates before any commit. Neither agent publishes or deploys without direct authorization.

## Documentation discipline

Update product-scope.md when a feature moves from planned to verified, and link the test or acceptance evidence. Update database-design.md before or alongside a schema migration. Record a decision in docs/adr/ if a choice affects stored data, policy, external integration or public behavior. Keep runbooks under docs/operations/ and rehearse them. A guide that says a feature exists must point to the implementation and verification; otherwise label it proposed.

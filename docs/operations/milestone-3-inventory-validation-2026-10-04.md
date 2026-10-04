# Inventory backend validation — 2026-10-04

Codex reviewed Grok's filtered implementation and independently ran all nine SQL suites on a fresh local PostgreSQL 17.11 database. The suites cover identity, commands, Egyptian owner registration, opening balances/RLS, existing trades, explicit pricing, inventory and inventory RLS. They passed on `eldafttar_m3r_41a6bf44`. A second disposable database, `eldafttar_m3r_5ba38715`, passed real `authenticated` two-connection races for competing receipt recognition, same-key replay and gold settlement. Each database was removed only after this run created it; existing databases were preserved.

The development preflight reported zero invalid owned quantity buckets. The additive inventory migration was applied as `20261004081229_milestone_3_inventory_contract`; a subsequent advisor finding led to `20261004081347_inventory_sync_operation_index`. Backfill added eleven explicitly labeled legacy aggregate lots/products/movements and eighteen synchronization markers. It added no financial operation or journal and changed no existing money or gold posting.

Hosted `milestone_3_inventory.sql` and `milestone_3_inventory_rls.sql` both returned their passing markers inside synthetic rollback-only transactions. The following exact row counts were identical immediately before and after those tests:

| Table | Before | After |
| --- | ---: | ---: |
| auth.users | 2 | 2 |
| shops | 1 | 1 |
| shop_memberships | 1 | 1 |
| shop_entitlements | 1 | 1 |
| business_days | 2 | 2 |
| financial_operations | 18 | 18 |
| financial_operation_details | 17 | 17 |
| financial_command_requests | 18 | 18 |
| financial_audit_events | 18 | 18 |
| financial_outbox | 18 | 18 |
| ledger_accounts | 33 | 33 |
| journals | 54 | 54 |
| journal_postings | 113 | 113 |
| purchase_cash_payables | 3 | 3 |
| invoice_dispatch_confirmations | 0 | 0 |
| inventory_products | 11 | 11 |
| inventory_lots | 11 | 11 |
| inventory_lot_movements | 11 | 11 |
| inventory_lot_sync | 18 | 18 |
| inventory_receipts | 0 | 0 |
| receipt_quantity_allocations | 0 | 0 |
| traders | 0 | 0 |
| gold_obligations | 0 | 0 |

These are current measurements, not the older October 1 baseline. Hosted tests do not commit synthetic records. Concurrent committed fixtures exist only inside isolated disposable local databases.

Security advisors identify the intentionally authenticated, owner-checked `SECURITY DEFINER` RPC boundary. New functions use an empty search path and private helper execution is revoked. Existing default-deny tables and the pre-existing disabled leaked-password protection remain documented findings. Performance review found the new synchronization composite foreign key lacked a covering index; the follow-up migration covers it. Existing unrelated foreign-key and membership-primary-key findings remain open; unused new indexes are retained.

The fresh advisor read at 08:47 UTC after the index migration reported 40 authenticated definer-function warnings, three intentional default-deny tables, and one existing leaked-password-protection warning. Performance reported seven existing unindexed foreign keys, one existing membership table without a primary key, and 23 unused-index notices. `inventory_lot_sync` was no longer in the unindexed findings. Counts describe individual findings inside the grouped advisor response. Remediation references: [definer RPC access](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [default-deny policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [foreign-key indexes](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [primary keys](https://supabase.com/docs/guides/database/database-linter?lint=0004_no_primary_key), and [unused indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index). New protective indexes remain because this small development dataset does not represent future usage.

This verifies the backend slice. Flutter inventory/trader integration, compensation, private notes and final combined validation remain separate work. It is not device acceptance, legal approval or a release.

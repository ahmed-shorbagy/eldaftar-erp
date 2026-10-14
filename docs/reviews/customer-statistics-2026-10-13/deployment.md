# CRM-02 — development deployment, preservation and retirement

Date: 2026-10-13. Authorized development target xchapwvmvoefriqcxtvn only, connected Supabase plugin. [Validation](independent-validation.md), [confirmed contract](../../adr/0015-customer-statistics.md).

| Reviewed additive source | Hosted version | Trimmed / CR-normalized SHA-256 |
| --- | --- | --- |
| [20261013175048_customer_statistics.sql](../../../supabase/migrations/20261013175048_customer_statistics.sql) | 20261013181844 | 2dd0590e8e17e880c07ddde9672fceec0bfcaa5bc68e912a70eb45886e104505 |

Raw local file SHA-256: 108dabca0711aa9831089e2e51bd5239365fd72ad27aadd73538ec055a031734. Applied individually with apply_migration after independent local SQL/RLS/consistency/round-trip review and client gates. Hosted normalized source hash matches exactly. The migration adds three private helpers, two authenticated owner-checked stable v2 read RPCs and a partial return-reference index; it changes no financial write, Auth policy, table data, v1 RPC or prior migration.

Before application, all 34 hosted names/versions/hashes matched the previous [complete mapping](../customers-2026-10-13/migration-mappings.md). Thirty-two current local normalized source hashes match; the same two documented comment/whitespace-only differences remain. The empty historical preparation marker remains undeployed. No db push, history rewrite or old migration reapplication.

Hosted customer_statistics.sql passed every assertion in an explicit rollback: real synthetic sale/purchase/return/exchange commands, audit evidence, all five karats, retained counts, correction, archive, UTC/time-zone boundaries and authorization. No financial fixture, Auth identity/session, fault trigger or temporary function remained.

The authenticated HTTP/Realtime retry harness passed ten checks: exact zero/no-history reads; one bounded v2 list and detail agree with real remaining line weights and one count; cross-shop/anonymous/direct-link-write denial; correction preserves immutable detail and old association evidence; reconnect and archived reads; ledger-only invalidation; restoration of the original synthetic association/archive state; expired reads; live-token revocation denial; global sign-out. Real production Dart codecs decoded those captured responses successfully.

The ledger-only Realtime probe deliberately advanced only the existing synthetic shop's sync signal via private.bump_shop_sync: ledger revision 103 → 104, customer revision unchanged at 63. It posted no financial operation. Confirmed-return/exchange revision and net-total correctness were separately exercised by the rollback-only hosted SQL suite. This combination does not claim a persistent hosted financial-event or native-device demonstration.

The first HTTP run stopped because no unused operation candidate remained; it had created two zero-history synthetic files. Both accounts were globally signed out and retired immediately. Failed-run manifest/failure evidence remains under tmp/customer-statistics/. A retry harness initially had a package path error before fixture activation; that path was corrected. The successful retry reused the already linked synthetic confirmed purchase, corrected attribution through two new synthetic files, then restored the original association and archive state. All four new synthetic files are archived; immutable command/link/correction audits survive. No persistent financial posting was needed.

Workflow actor 63aba2d9-00bc-4569-95b6-f587b218f19a / shop b52195a1-004f-44e9-9778-a7616e1a5e9b and isolation actor 7c9d837f-3903-4e8f-a153-5bc54fa43378 / shop 77c24239-4381-450a-aca6-77030fef5970 were temporarily re-enabled only for the probe. Random passwords/tokens remained in runner memory; no service-role key was read. Both globally signed out, banned for 100 years, passwords replaced with server-generated random hashes, memberships revoked and entitlements expired. Readback proves each has zero sessions, zero active memberships and zero active entitlements. Existing Auth identities and financial actor references remain. Final manifest records databaseRetirementConfirmed=true.

All sixteen protected groups have identical before/after counts and complete JSON SHA-256 digests. Exact ignored evidence: tmp/customer-statistics/hosted-preservation-before.json and hosted-preservation-after.json. These checks include original financial details, invoices, repairs/debts and day boundaries:

| Protected relation | Count before = after | SHA-256 before = after |
| --- | --- | --- |
| financial_operations | 35 | 6488f20d7ff0f80a10bbd2456288d009f99f330bc425d771c7208cb4be7443d6 |
| financial_audit_events | 35 | ac79485ba58c8688414f2a061e3f8cd1cd4c13b123f6465d48143cdd415459f7 |
| journals | 84 | 9b82f345dbc024f51e1e94bcc6d874002ce75ed06cb01e1ad01c0fa9e8a34cf2 |
| journal_postings | 177 | f4c8b5ffc7f724df5e75d1fd3c7f6afe318cbacdb8f4966e28a4f91db14fcdd2 |
| inventory_lots | 18 | 4f58aaab9b571ecb5baf531c5d59cc9d6b6cf8928741508a679d05441175bc4a |
| inventory_lot_movements | 24 | 6caeda8c0d1fd53fab2482c0288196a4ff40553e9dd0c1ecd95f653e056b4b7d |
| inventory_receipts | 1 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 |
| repairs | 6 | d12a5677e808be8940a6bd4e77628d5ca421bf358d2d60b42416857809dc15a2 |
| repair_events | 23 | 21333ad5335ae1abf4bb44e12a941f26ebd5867a9253429f91d442490e762931 |
| shop_debts | 6 | f88e3b552f0e5df6de3b2436c5b36a1acb3a390d9f00939d978df82329641180 |
| debt_events | 16 | 7e0737194b88a69acc1a8a135f03315790eceedc375b7390a369437c64281dd1 |
| purchase_cash_payables | 4 | 9afcbbe7dd3e35eb6a0e3dea08087c337b1a1d2ee11e917bbd12fd0948f94994 |
| gold_obligations | 1 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 |
| financial_operation_details | 32 | 65d29d15841a33e78c00312b57384d28599541f4c4b48560f4307bcb6f94ada3 |
| invoice_dispatch_confirmations | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| business_days | 4 | 85d7fea9e82c0e2d2e7853edeb7ed219f13eb2e9a53cffd038b5695769a0bb1a |

Security advisors: authenticated SECURITY DEFINER notices increase from 81 to 83 for the two intentionally owner/session-checked v2 RPCs. No new RLS table/policy issue. Seven preexisting internal/audit tables without policies and one leaked-password notice remain; no Auth setting changed. Performance counts remain six unindexed foreign keys, one membership table without primary key and 24 unused-index notices. [Function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [index advisory](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Exact summaries: advisors-before.json and advisors-after.json.

Development deployment and synthetic retirement complete. Native owner/device and native-to-hosted network/restart acceptance remain open. No commit, push, application publishing, release/production build, paid environment, reset or history deletion.


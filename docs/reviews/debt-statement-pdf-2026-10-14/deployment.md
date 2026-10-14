# DEBT-02 PDF — development deployment and preservation

Date: 2026-10-14. Authorized project xchapwvmvoefriqcxtvn only; connected Supabase plugin. [Validation](independent-validation.md), [confirmed D31](../../adr/0018-debt-statement-snapshot.md).

| Reviewed additive source | Hosted version | Trimmed / CR-normalized UTF-8 SHA-256 |
| --- | --- | --- |
| [20261014115601_debt_statement_snapshot.sql](../../../supabase/migrations/20261014115601_debt_statement_snapshot.sql) | 20261014123235 | b7fbaaa60f90756165023cc2dad65263cae7da52fa4d73dc58aaf23b011e019f |

Raw local SHA-256: 7bbbb2021cd2c4f31e932134034c62dde531abbd2f7f469f6149df4ff4f0133b. Applied individually with apply_migration after separate read-only review and independent local gates. Stored normalized source hash matches exactly. Before applying, all 36 prior hosted versions/names/hashes matched recorded mappings: 35 older hashes matched CRM-05 pre-deployment inspection; current CRM-05 matched its published deployment. Existing local/hosted mappings, two historical comment/whitespace differences and undeployed empty marker remain. No blind db push or prior-history/source rewrite.

One private STABLE projection and one public owner/session/shop-checked STABLE read RPC give a consistent calling-query MVCC snapshot of shop header, exact figures and full sanitized history. Complete content is hashed for freshness, excluding the server snapshot timestamp. Private helper execute denied; authenticated owner read RPC only. Expired reads retained. No table, financial command/migration, financial read grant, backfill, old read/receipt, RLS policy or Auth setting changed. Existing public/private function definitions and ACL SHA-256 fingerprint remained identical after excluding the two additions.

Full hosted debt and statement supplemental SQL passed in explicit rollback. The first fault probe hit managed PostgreSQL's prohibition on disabling RI system triggers; changing the synthetic test to DISABLE TRIGGER USER left FK checks active and passed. Both attempts left protected counts/digests unchanged. No persistent synthetic actor was enabled; final readback found zero fixture users, sessions, memberships, entitlements or fault triggers. No retirement mutation or retained financial test data was needed. Native/device/owner acceptance remains open.

All 35 protected relations have identical complete row-JSON SHA-256 digests/counts before/after application and final hosted testing. No raw customer/shop rows, contacts, credentials, tokens or source documents exported. Ignored evidence: tmp/debt-statement/hosted-preservation-before.json, hosted-preservation-after.json, hosted-deployment.json, hosted-retirement.json, hosted-functions-before-after.json and hosted-gate-final.json.

Advisors: intentional authenticated owner/session-checked SECURITY DEFINER count 87 → 88 for the new read RPC. Seven existing internal/audit no-policy notices, one leaked-password notice, six unindexed FKs, one membership table without primary key and 26 unused-index notices remain. No new table/FK/index. [Function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [index advisory](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Concise evidence: advisors-summary.json. Current [PostgreSQL snapshot guidance](https://www.postgresql.org/docs/current/xfunc-volatility.html) and Supabase function/RLS guidance consulted.

Development delivery/preservation complete. No application publishing, release/production build, commit, push, paid environment, call/message, reset or history deletion.

| Protected relation | Count before = after | SHA-256 before = after |
| --- | --- | --- |
| business_days | 4 | 4ddbc1604ec1f87c8c2afed16798cd151e21a42a898423627384a23fdee93af9 |
| customer_command_requests | 29 | db4193ae7c7059f923909c96c53086917a13de3463848585f35251f8480036a5 |
| customer_events | 29 | 33ad633a1fe185841b90d4c468041992cb244077394cd4246050d01ba22cf931 |
| customer_notes | 2 | 87f29d67c644de434e2376d6e45782b70091391e2ad685ab8c51162263b101ec |
| customer_number_declarations | 2 | 10ab35b01a84f351c641f26fa51135871dc3e79bc94c3f5f8ef909a919eb1b28 |
| customer_number_events | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_operation_links | 5 | f6cac379a3a90592efd42a54a0ef0025c7049b5ec8da4f61d2b3e34910de4c9e |
| customer_phones | 2 | 653161f8d849cce331fb77d13309acfc947f11bf0e8790a8add1b5d2b858b122 |
| customers | 6 | c39a25dcec151c7569c2259054b4b1c9fb5aeb5e87eb9e492285fe5ac7625deb |
| debt_command_requests | 16 | f038d8954030d1365b949a942e924d87a574e1cee75b0a76d6e9b50962d0598c |
| debt_events | 16 | 7e0737194b88a69acc1a8a135f03315790eceedc375b7390a369437c64281dd1 |
| debt_settlement_references | 8 | 29c7f287b87bef351f46ab40a29c4dad04cb138d286c204621392348653c0c27 |
| debt_source_archives | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| financial_audit_events | 42 | 7f7dc54ca444061412d20d8b852d268e9b5c547f80ac10602c83a6db72ec3605 |
| financial_command_requests | 42 | 6ba5ceab161a4a7c1c63f421c86cf2cec74d6170a455f5f785c2165b7ccc1108 |
| financial_operation_details | 39 | dfd855e4e0c7fcdfbd29c3162e07df656c1f2d6dcb0bc540d3e2bb26e237603c |
| financial_operations | 42 | 99a923ab9eb154b0f48b02048f5bf6b1af7071839b29ccb3e1174e958e501754 |
| gold_obligations | 1 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 |
| inventory_lot_movements | 33 | 418f0da276ecfd857c2eb2cc46784b3332797ef87d8ae688eaee2c94f4cea5ec |
| inventory_lots | 21 | 744006d2df27859a41e6431194c48bb959126d84625d8897a92b8651e7d2dfee |
| inventory_receipts | 1 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 |
| invoice_dispatch_confirmations | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| journal_postings | 227 | 598b27bd20f58ab0b46af3de4da4d185197dd99f9794a351d4fc7d07a3eec595 |
| journals | 108 | c39b0ef9b7d069350d41fe0faea2898ed96a0ad2a90816990fbef2d26dc217a3 |
| ledger_accounts | 61 | 9b5067c895c4ed5a9f70bf84e8af45c0c2415ffe0e5a2aa9de69b10c6be5c19d |
| purchase_cash_payables | 5 | 8525f58f49f0f8bf2c631267a8bbf39d576ed61071f3655ac6a4e98ff607a638 |
| receipt_quantity_allocations | 1 | 5f39cd32e402f2080b27e00000eb975e9d8e99429a98457af901b6fbb5c74e1c |
| repair_custody_events | 12 | 267a5b9fb001a0b53b9a3f403d815cd74ced9a67a6ab67e6a74ac11004a6bcd1 |
| repair_events | 23 | 21333ad5335ae1abf4bb44e12a941f26ebd5867a9253429f91d442490e762931 |
| repairs | 6 | d12a5677e808be8940a6bd4e77628d5ca421bf358d2d60b42416857809dc15a2 |
| shop_debts | 6 | f88e3b552f0e5df6de3b2436c5b36a1acb3a390d9f00939d978df82329641180 |
| shop_entitlements | 5 | edb2fece2f95a839685704ffbea70eed0b8e30be3e6e391760554444f054b2cd |
| shop_memberships | 11 | ee85b1684f884b31802cabcff9927cb7fea88b5e6c710d75198419d26c8abdee |
| shops | 11 | 25bad11011c5581a076b29f4de0626eb5f653d21adf36794f58a91d01a9bcdbe |
| traders | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |

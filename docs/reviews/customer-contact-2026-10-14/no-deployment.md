# CRM-04/CRM-06 — no deployment, preservation and retirement

Date: 2026-10-14. Development project xchapwvmvoefriqcxtvn, connected Supabase plugin. [Validation](independent-validation.md), [confirmed contract](../../adr/0016-customer-contact-handoff.md).

No migration or hosted mutation was needed. Contact uses the existing owner/session-protected get_customer_v2 before selection and launch. Existing v1/v2 reads, commands, financial authority and Auth policy remain unchanged. No contact-attempt table, CRM-05 field, invoice confirmation or financial operation was added.

Read-only inspection found the existing 35 hosted migrations, ending in customers_crm (20261013164251) and customer_statistics (20261013181844), consistent with the [historical deployment](../customer-statistics-2026-10-13/deployment.md). No application, db push or history rewrite occurred; no new deployment hash exists.

All 22 relations below have matching complete row-JSON SHA-256 digests and counts before/after this slice’s hosted inspection. Starting counts are current 2026-10-14 observations, not replacements for earlier historical counts. Ignored evidence: tmp/customer-contact/hosted-preservation-before.json and hosted-preservation-after.json. Raw rows/customer numbers were not exported.

| Protected relation | Count before = after | SHA-256 before = after |
| --- | --- | --- |
| financial_operations | 42 | 99a923ab9eb154b0f48b02048f5bf6b1af7071839b29ccb3e1174e958e501754 |
| financial_audit_events | 42 | 7f7dc54ca444061412d20d8b852d268e9b5c547f80ac10602c83a6db72ec3605 |
| journals | 108 | c39b0ef9b7d069350d41fe0faea2898ed96a0ad2a90816990fbef2d26dc217a3 |
| journal_postings | 227 | 598b27bd20f58ab0b46af3de4da4d185197dd99f9794a351d4fc7d07a3eec595 |
| inventory_lots | 21 | 744006d2df27859a41e6431194c48bb959126d84625d8897a92b8651e7d2dfee |
| inventory_lot_movements | 33 | 418f0da276ecfd857c2eb2cc46784b3332797ef87d8ae688eaee2c94f4cea5ec |
| inventory_receipts | 1 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 |
| repairs | 6 | d12a5677e808be8940a6bd4e77628d5ca421bf358d2d60b42416857809dc15a2 |
| repair_events | 23 | 21333ad5335ae1abf4bb44e12a941f26ebd5867a9253429f91d442490e762931 |
| shop_debts | 6 | f88e3b552f0e5df6de3b2436c5b36a1acb3a390d9f00939d978df82329641180 |
| debt_events | 16 | 7e0737194b88a69acc1a8a135f03315790eceedc375b7390a369437c64281dd1 |
| purchase_cash_payables | 5 | 8525f58f49f0f8bf2c631267a8bbf39d576ed61071f3655ac6a4e98ff607a638 |
| gold_obligations | 1 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 |
| financial_operation_details | 39 | dfd855e4e0c7fcdfbd29c3162e07df656c1f2d6dcb0bc540d3e2bb26e237603c |
| invoice_dispatch_confirmations | 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| business_days | 4 | 4ddbc1604ec1f87c8c2afed16798cd151e21a42a898423627384a23fdee93af9 |
| customers | 6 | c39a25dcec151c7569c2259054b4b1c9fb5aeb5e87eb9e492285fe5ac7625deb |
| customer_phones | 2 | 653161f8d849cce331fb77d13309acfc947f11bf0e8790a8add1b5d2b858b122 |
| customer_notes | 2 | 87f29d67c644de434e2376d6e45782b70091391e2ad685ab8c51162263b101ec |
| customer_events | 29 | 33ad633a1fe185841b90d4c468041992cb244077394cd4246050d01ba22cf931 |
| customer_operation_links | 5 | f6cac379a3a90592efd42a54a0ef0025c7049b5ec8da4f61d2b3e34910de4c9e |
| customer_command_requests | 29 | db4193ae7c7059f923909c96c53086917a13de3463848585f35251f8480036a5 |

No hosted synthetic actor was enabled or session created. Read-only verification of the two prior CRM actors returned zero sessions, zero active memberships and zero active entitlements; no retirement mutation was needed. Local fixtures ran in a new disposable cluster that was stopped. Audit/association history and financial actor references remain intact.

Native/device/owner acceptance remains open. The local Android debug APK was not installed/published. No calls, messages, release/production builds, commits, pushes, publishing, deletion or reset occurred.

# Debt due dates — development deployment and preservation

Implementation/application on 2026-10-14 UTC; final verification recorded 2026-10-15 in Africa/Cairo. Authorized project xchapwvmvoefriqcxtvn only, connected Supabase plugin. [Validation](independent-validation.md), [D19/D32](../../adr/0019-debt-calendar-due-dates.md).

| Reviewed source | Hosted version | Trimmed / CR-normalized UTF-8 SHA-256 |
| --- | --- | --- |
| [20261014133347_debt_due_dates.sql](../../../supabase/migrations/20261014133347_debt_due_dates.sql) | 20261014142241 | 90632e727ae775017816ad2984cf6f12e4f0e039cbcda5cb3469841a512b0740 |

Raw local SHA-256: 7fffd27bbb04677375bc566cda2fe4a943c5c07717e0911c39360622c72238c2. Applied individually after separate review and independent client/SQL/RLS/atomicity/race/round-trip gates. All 37 prior hosted versions/names/normalized hashes matched historical mappings immediately before application. The same two prior comment/whitespace differences and undeployed empty marker remain. No history/source rewrite or blind db push.

Three additive tables store source-keyed date/version, append-only metadata audit and exact request/result. Four owner/session-checked RPCs read dates/reminders, commit reviewed metadata and reconcile the exact envelope. Three private helpers are not client-executable. No existing helper replacement, financial migration, Auth change, date backfill or financial grant. Existing public/private function definitions and ACL fingerprint, excluding the seven additions, stayed exactly 1b85e8e6b1b3f5a937e31c3a52df0c141456c366a99f4f78ef074642538f691a. Old debt/CRM/history/PDF APIs, frozen receipts and immutable source snapshots remain.

Full hosted debts + statement + due suites passed in explicit rollback. The first connector call expired during an interrupted session; readback found no retained fixtures, then a fresh identical call passed. No persistent synthetic account/session/membership/entitlement enabled. Final counts: zero fixture users, sessions, memberships, entitlements and fault triggers; all three new tables empty. No retirement mutation or retained financial test data was needed.

Preservation spans all 49 prior public tables except permitted shop_sync_signals. During the interrupted session, an independent existing-shop sale was appended at 2026-10-14T21:05:48.44611Z. It is preserved. Consequently aggregate financial counts are 42 → 43, audits/requests/outbox 42 → 43, details 39 → 40, journals 108 → 111, postings 227 → 234, lot movements 33 → 34 and lot sync 42 → 43. The associated day version advanced once. Every other protected table has identical counts/full-row hashes.

Read-only filtered hashes prove every pre-existing operation/audit/request/detail/outbox/journal/posting/lot-movement/sync row remains byte-equivalent in canonical row JSON, including null-linked historical lot movements. A read-only projection subtracting that sale's one day-version increment reproduces the original business-day digest; no row was modified for that check. After the sale, all 49 counts/digests are identical before versus after the successful hosted rollback gate. This record does not falsely claim unchanged overall financial counts across concurrent activity. No raw customer/contact rows, tokens, credentials or source documents exported.

Advisors: intentional owner/session-checked authenticated SECURITY DEFINER RPCs 88 → 92 for the four additions; seven existing no-policy notices, one leaked-password warning, six unindexed FKs and one table without primary key unchanged. Unused-index notices end at 28. New tables have RLS/read policies, revoked writes and indexed FKs. [Function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [FK indexes](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).

Ignored evidence under tmp/debt-due: hosted-migration-before.json, migration-preflight.json, hosted-preflight-summary.json and hosted-preservation-final.json (before/after/pre-existing/retirement/advisor/hosted-gate results). Development PostgreSQL 17.6.1.166. No new paid environment, application publishing, commit, push, release/production build, provider sending, reset/history deletion. Native/device/owner acceptance remains open.

The exact aggregate before/after table below includes the preserved independent sale.

| Protected relation | Count before → after | SHA-256 before | SHA-256 after |
| --- | --- | --- | --- |
| bullion_denominations | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| business_days | 4 → 4 | 4ddbc1604ec1f87c8c2afed16798cd151e21a42a898423627384a23fdee93af9 | d8467e0271be44a563e10ce098c4c2a1594def7a2dff702eed65ca41262b4283 |
| coin_types | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_command_requests | 29 → 29 | db4193ae7c7059f923909c96c53086917a13de3463848585f35251f8480036a5 | db4193ae7c7059f923909c96c53086917a13de3463848585f35251f8480036a5 |
| customer_events | 29 → 29 | 33ad633a1fe185841b90d4c468041992cb244077394cd4246050d01ba22cf931 | 33ad633a1fe185841b90d4c468041992cb244077394cd4246050d01ba22cf931 |
| customer_notes | 2 → 2 | 87f29d67c644de434e2376d6e45782b70091391e2ad685ab8c51162263b101ec | 87f29d67c644de434e2376d6e45782b70091391e2ad685ab8c51162263b101ec |
| customer_number_declarations | 2 → 2 | 10ab35b01a84f351c641f26fa51135871dc3e79bc94c3f5f8ef909a919eb1b28 | 10ab35b01a84f351c641f26fa51135871dc3e79bc94c3f5f8ef909a919eb1b28 |
| customer_number_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_operation_links | 5 → 5 | f6cac379a3a90592efd42a54a0ef0025c7049b5ec8da4f61d2b3e34910de4c9e | f6cac379a3a90592efd42a54a0ef0025c7049b5ec8da4f61d2b3e34910de4c9e |
| customer_phones | 2 → 2 | 653161f8d849cce331fb77d13309acfc947f11bf0e8790a8add1b5d2b858b122 | 653161f8d849cce331fb77d13309acfc947f11bf0e8790a8add1b5d2b858b122 |
| customers | 6 → 6 | c39a25dcec151c7569c2259054b4b1c9fb5aeb5e87eb9e492285fe5ac7625deb | c39a25dcec151c7569c2259054b4b1c9fb5aeb5e87eb9e492285fe5ac7625deb |
| daily_note_attachments | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_command_requests | 16 → 16 | f038d8954030d1365b949a942e924d87a574e1cee75b0a76d6e9b50962d0598c | f038d8954030d1365b949a942e924d87a574e1cee75b0a76d6e9b50962d0598c |
| debt_events | 16 → 16 | 7e0737194b88a69acc1a8a135f03315790eceedc375b7390a369437c64281dd1 | 7e0737194b88a69acc1a8a135f03315790eceedc375b7390a369437c64281dd1 |
| debt_settlement_references | 8 → 8 | 29c7f287b87bef351f46ab40a29c4dad04cb138d286c204621392348653c0c27 | 29c7f287b87bef351f46ab40a29c4dad04cb138d286c204621392348653c0c27 |
| debt_source_archives | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| egypt_governorates | 27 → 27 | 6e08f2dd2c8d3f5adbd32247126e2ca4c694532c671ec212f9fdce6137a1cfe7 | 6e08f2dd2c8d3f5adbd32247126e2ca4c694532c671ec212f9fdce6137a1cfe7 |
| financial_audit_events | 42 → 43 | 7f7dc54ca444061412d20d8b852d268e9b5c547f80ac10602c83a6db72ec3605 | c038fe5aba27902c761044411da7b015a87d2fccbbe4cb1945a95797c57d6620 |
| financial_command_requests | 42 → 43 | 6ba5ceab161a4a7c1c63f421c86cf2cec74d6170a455f5f785c2165b7ccc1108 | cfe15539f684b8c1abd1dac4740f4c9eddabc2e2047cc04fc3234cd2aae82f01 |
| financial_operation_details | 39 → 40 | dfd855e4e0c7fcdfbd29c3162e07df656c1f2d6dcb0bc540d3e2bb26e237603c | 7fab0de0b817c868b7d545170d8af68438ffe0374a587e4c3d1f354faa3e609c |
| financial_operations | 42 → 43 | 99a923ab9eb154b0f48b02048f5bf6b1af7071839b29ccb3e1174e958e501754 | 518ec534ed4c0468ca2994308269b15b0142c98f6d05ca74a04f05ae4be8a4c4 |
| financial_outbox | 42 → 43 | 91f4d0173abddf0d6fa94aa7c6adff837fa6fb27d63c4ba88dd9bced99b911ba | 788a38528beb7c5e89a91347f5c83d7ed81decc5c7b0a7bc3cd18e0eb9d6a660 |
| gold_obligations | 1 → 1 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 |
| identity_audit_events | 11 → 11 | 61dda3c595442d843611bf66d69b4353943448e0bd0fe2820ca803f3e1218eac | 61dda3c595442d843611bf66d69b4353943448e0bd0fe2820ca803f3e1218eac |
| inventory_catalog_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_catalog_requests | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_command_envelopes | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_explicit_plans | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_lot_movements | 33 → 34 | 418f0da276ecfd857c2eb2cc46784b3332797ef87d8ae688eaee2c94f4cea5ec | 0b10bf65f312d7fe6b0e069479d736e61bcbb2b98f85b14be05c998f9f94a9b9 |
| inventory_lot_sync | 42 → 43 | 40e940f77ba5926efd24a3607f27f8b1ce472e185aab21ec83cc4970e69fefdb | 28ab6083e04ce0f551f994c3bae39f3e0ba033e3eb822f6047c13b62ea30c38d |
| inventory_lots | 21 → 21 | 744006d2df27859a41e6431194c48bb959126d84625d8897a92b8651e7d2dfee | 744006d2df27859a41e6431194c48bb959126d84625d8897a92b8651e7d2dfee |
| inventory_products | 21 → 21 | 86c01a22459e6f189a1ac1f1d4536e4550c652494e6656ee759ad11fdf07b59c | 86c01a22459e6f189a1ac1f1d4536e4550c652494e6656ee759ad11fdf07b59c |
| inventory_receipts | 1 → 1 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 |
| invoice_dispatch_confirmations | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| journal_postings | 227 → 234 | 598b27bd20f58ab0b46af3de4da4d185197dd99f9794a351d4fc7d07a3eec595 | 8fadd2c444dd923c1c5cf52e8ecb9a934fc9263bfd4f5697231e46934fd2956c |
| journals | 108 → 111 | c39b0ef9b7d069350d41fe0faea2898ed96a0ad2a90816990fbef2d26dc217a3 | ee371ed00f6925f04bdf0beaa7dfcb02773f00280ea20b1c033ecf33ef1228b6 |
| ledger_accounts | 61 → 61 | 9b5067c895c4ed5a9f70bf84e8af45c0c2415ffe0e5a2aa9de69b10c6be5c19d | 9b5067c895c4ed5a9f70bf84e8af45c0c2415ffe0e5a2aa9de69b10c6be5c19d |
| platform_admins | 1 → 1 | 62da0fcd1d79d2876d801f99a55bb31faa2099da7b3c6529ebba48b5bda97cd5 | 62da0fcd1d79d2876d801f99a55bb31faa2099da7b3c6529ebba48b5bda97cd5 |
| purchase_cash_payables | 5 → 5 | 8525f58f49f0f8bf2c631267a8bbf39d576ed61071f3655ac6a4e98ff607a638 | 8525f58f49f0f8bf2c631267a8bbf39d576ed61071f3655ac6a4e98ff607a638 |
| receipt_quantity_allocations | 1 → 1 | 5f39cd32e402f2080b27e00000eb975e9d8e99429a98457af901b6fbb5c74e1c | 5f39cd32e402f2080b27e00000eb975e9d8e99429a98457af901b6fbb5c74e1c |
| repair_command_requests | 23 → 23 | 65e1a52f8964619969bffca4434f88cdbd243fc7b1c2973d55c1fecd36194749 | 65e1a52f8964619969bffca4434f88cdbd243fc7b1c2973d55c1fecd36194749 |
| repair_custody_events | 12 → 12 | 267a5b9fb001a0b53b9a3f403d815cd74ced9a67a6ab67e6a74ac11004a6bcd1 | 267a5b9fb001a0b53b9a3f403d815cd74ced9a67a6ab67e6a74ac11004a6bcd1 |
| repair_events | 23 → 23 | 21333ad5335ae1abf4bb44e12a941f26ebd5867a9253429f91d442490e762931 | 21333ad5335ae1abf4bb44e12a941f26ebd5867a9253429f91d442490e762931 |
| repairs | 6 → 6 | d12a5677e808be8940a6bd4e77628d5ca421bf358d2d60b42416857809dc15a2 | d12a5677e808be8940a6bd4e77628d5ca421bf358d2d60b42416857809dc15a2 |
| shop_debts | 6 → 6 | f88e3b552f0e5df6de3b2436c5b36a1acb3a390d9f00939d978df82329641180 | f88e3b552f0e5df6de3b2436c5b36a1acb3a390d9f00939d978df82329641180 |
| shop_entitlements | 5 → 5 | edb2fece2f95a839685704ffbea70eed0b8e30be3e6e391760554444f054b2cd | edb2fece2f95a839685704ffbea70eed0b8e30be3e6e391760554444f054b2cd |
| shop_memberships | 11 → 11 | ee85b1684f884b31802cabcff9927cb7fea88b5e6c710d75198419d26c8abdee | ee85b1684f884b31802cabcff9927cb7fea88b5e6c710d75198419d26c8abdee |
| shops | 11 → 11 | 25bad11011c5581a076b29f4de0626eb5f653d21adf36794f58a91d01a9bcdbe | 25bad11011c5581a076b29f4de0626eb5f653d21adf36794f58a91d01a9bcdbe |
| traders | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |

Shared client changes are additive: the durable locker recognizes and validates the new debt_due envelope; ledger recovery routes that kind to Debts instead of financial/opening status; the HTTP adapter implements the separate versioned date interface. Existing debt command maps/decoders are unchanged. Debt sync ticks also advance on location/subscription invalidation so a time-zone/access change cannot leave a date review fresh. Existing scope counters and old receipts remain compatible, covered by the 1167-test full regression and independent late-session/foreign-command probes. The backend reuses the existing metadata-only debt sync helper without replacing it.

The cached exact 49-table post-sale/pre-successful-gate snapshot and matching post-gate snapshot are paired in tmp/debt-due/hosted-post-sale-gate-pair.json; all_49_equal is true. These are readbacks bracketing the successful rollback test, separate from the original preflight pair that includes the independent sale.

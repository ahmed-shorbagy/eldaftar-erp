# Native debt reminders — development deployment and preservation

Date: 2026-10-16, Africa/Cairo. Authorized development project xchapwvmvoefriqcxtvn only, connected Supabase plugin. Applied individually after [separate implementation review](implementation-review.md) and [final independent validation](independent-validation-2026-10-16.md). No application distribution or release build.

| Reviewed source | Hosted version | Trimmed / CR-normalized UTF-8 SHA-256 |
| --- | --- | --- |
| [20261015065930_debt_native_reminders.sql](../../../supabase/migrations/20261015065930_debt_native_reminders.sql) | 20261016090329 | 81570fa8c42bc358fc418fcfd8e9122ce1e84b668171ac7d3575f91bbc91a9fd |

Raw local SHA-256: 4eb1e4f27acc3b8e473425f1a60af433b986b3dcf5213cdce98302fc18650e1d. All 38 prior hosted versions/names/normalized hashes matched the recorded mapping immediately before application and remain unchanged afterward. The two historical local comment/whitespace differences (daily_ledger_trades and inventory_sync_operation_index) and undeployed empty marker were preserved. No blind db push or migration-history rewrite.

Three additive tables store source-keyed intent/version, immutable owner/server-UTC audit and original command/result. Five public owner/session-checked versioned RPCs and two private helpers provide read/review/queue/command/status and UTC conversion. Queue items contain exactly source_kind/source_id/native_freshness/trigger_at/time_valid. No party/contact/balance data enters the scheduler. Existing date/debt/CRM/financial/PDF APIs and receipts are unchanged. No existing function replacement, financial or Auth-policy migration, financial grant, date/time backfill or paid environment.

The combined hosted debt fixture, native supplemental SQL and independent all-five-RPC real-role authorization gate passed inside one explicit transaction ending in rollback. It exercises precision/source identities, DST/UTC, pagination/privacy, stale/version/idempotency, atomic failure, zero financial/date effects and owner/other-shop/anonymous/revoked/expired/admin boundaries. It schedules no notification. Readback found zero synthetic users, sessions, shops, memberships, entitlements and fault triggers; all three native tables remain empty. No persistent fixture or retirement mutation was needed, and no real audit/history row was erased.

All 52 protected pre-existing public table counts/full-row canonical JSON SHA-256 digests are identical immediately before versus after application and the hosted rollback gate; permitted shop_sync_signals is excluded. Existing public/private function definitions and grants, excluding the seven additions, remain exactly bdc43669309dc3c6332a3383b718ce121299e9849be870056a1db61f6ea5ed6f.

Between the initial 2026-10-15 inspection and this final preflight, independent activity had already changed business-day state, added two note attachments and increased financial operations/audits/requests/outbox 43→51, details 40→48, journals 111→140, postings 234→295, lot movements 34→46, lot sync 43→51, lots 21→26 and products 21→25. Task hosted calls up to that point were read-only. That activity is preserved in the fresh equal before/after pair below. No reset to yesterday's aggregate was attempted; this record does not claim those earlier totals stayed unchanged.

Security advisors: intentional authenticated SECURITY DEFINER notices 92→97 correspond to the five owner/session-checked RPC additions; seven existing no-policy notices and one leaked-password warning are unchanged. Performance: six unindexed FKs and one table without primary key unchanged; unused-index notices 28→29. New metadata tables have RLS, owner read policies, revoked direct writes and indexed FKs. [Function advisory](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [FK advisory](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [unused-index advisory](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index), [password advisory](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Existing notices are not claimed resolved.

Ignored aggregate evidence: tmp/debt-native/hosted-baseline.json, hosted-before-final.json, hosted-immediate-before.json, migration-preflight-final.json and hosted-preservation-final.json. No raw customer/contact rows, tokens, credentials or source requirements were exported to repository evidence. Local manifests and synthetic captures are distinct from OS delivery proof; [platform/device acceptance](platform-capabilities.md) remains open. No commit, push, publishing, release/production build, provider message, real-customer notification, reset or financial-history deletion.

## Exact protected aggregate pair

The SHA-256 column is equal on both sides; counts are equal on both sides. Canonical row JSON is ordered and joined with a literal backslash-n delimiter before SHA-256. Only aggregate hashes/counts are retained.

| Relation | Count before → after | SHA-256 before = after |
| --- | --- | --- |
| bullion_denominations | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| business_days | 4 → 4 | a3e39ee85230027df1b8141d3e7cc446fe598a1d4e231903b85641213698552d |
| coin_types | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_command_requests | 29 → 29 | 747650caa526ddb9215bb648d95c274490c13c1fb5d683b120de0f1b610d11fc |
| customer_events | 29 → 29 | d782b4bf6fc4a34e1e296bdbe2de7ff9ae8fbf93ab2d10c4a04385e416885f9a |
| customer_notes | 2 → 2 | 28ddbe8c6d73e0c9251fcd48b23ce4dccb2053cb350cfccd3629be1bea42806c |
| customer_number_declarations | 2 → 2 | c89a7388a050763e4ca4f870b9f7109780f382c78942a0d1b9388bd7753179f7 |
| customer_number_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_operation_links | 5 → 5 | 6d3fdaf045b56ffe17bf40e4606415d6011442013662798c9c848171ff197130 |
| customer_phones | 2 → 2 | 8e57c4c58659cb64a77d15717c7d90f28fcf2adc152932968acc9e071d23880d |
| customers | 6 → 6 | 86b14fda1d90eca307cf3da6c2793cc0eb792b6c1e45a1df1cc28987d878a391 |
| daily_note_attachments | 2 → 2 | 75891abcdf94b05ac015e1e8b36ab0ad140b27ee5ca2baf7fa4b726d4fdb34b0 |
| debt_command_requests | 16 → 16 | ec81492da8d0164931d868ce7ecb92cc7deb6c737d884cae5dee3a214f51e9d8 |
| debt_due_dates | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_due_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_due_requests | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_events | 16 → 16 | b5284b20308609199270d243c71adf0c6243a1db1b1cd0b33d0f365727c5f815 |
| debt_settlement_references | 8 → 8 | 80227bf50dda42755782f463ffe737c1fcf49ffca7cc80453740ddd718addfad |
| debt_source_archives | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| egypt_governorates | 27 → 27 | ee3bcf351827299741fb3d9609f3eecb73a2f6989bb8d444043d967598bee06a |
| financial_audit_events | 51 → 51 | b4f0b7482f0862357c08f428e9231ddcd021d5e1ffa57860bafc2d9a2c0aa0e9 |
| financial_command_requests | 51 → 51 | 4480373f2e9fb8f79c1c955fb20874fa57d5d95dc2109c654c163b04daae29ae |
| financial_operation_details | 48 → 48 | 818b897752579ed0f75ad08bab7e007e71f29d85535520308b21fbf055f3513f |
| financial_operations | 51 → 51 | 9db2f0272f8c891a461780ed3286eb410fdd39a7121aade1883894f12cdea504 |
| financial_outbox | 51 → 51 | 1c77f1104e5cc78264009aaba67fce1bea290b8c4fe8935eab066fafbfe026db |
| gold_obligations | 1 → 1 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 |
| identity_audit_events | 11 → 11 | 9c7828ce8b72881e45307b42e253cb2e463edfa11e0ee3b11f64a47b2973c0a4 |
| inventory_catalog_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_catalog_requests | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_command_envelopes | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_explicit_plans | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_lot_movements | 46 → 46 | 2dd4de2aec0b330a74285f31b2e38667ea2289dc953568810ba1d7a3a2feb00c |
| inventory_lot_sync | 51 → 51 | 64ea8100e31ae77d52e7335f2067b93634538c1bfba1bef372c7b6520726e081 |
| inventory_lots | 26 → 26 | 1780a65447b3214dc2f264fff324d707e0e567bdd7224b46370f0ce95f7fca02 |
| inventory_products | 25 → 25 | d118ba0c7f5e7e0bc5803f854b26ded0d9d7060cb6ddaae065f75a3a496fda3c |
| inventory_receipts | 1 → 1 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 |
| invoice_dispatch_confirmations | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| journal_postings | 295 → 295 | d2893e4488d28f25554e77ac9fe787529a31422fb9b4cd2dd48c8e5b8c4c7af3 |
| journals | 140 → 140 | a6820655dedd17639b2cd23e56997eadd42e80d0b479f6c2f1b349ae13a5375f |
| ledger_accounts | 61 → 61 | f16ed318e9b6d1779f763b6e0565d2676883567010f0b47e49e22d30cacc8075 |
| platform_admins | 1 → 1 | 62da0fcd1d79d2876d801f99a55bb31faa2099da7b3c6529ebba48b5bda97cd5 |
| purchase_cash_payables | 5 → 5 | 693b6b95618ff20f729b38e660900cb1c777e16c8d6419b5fe43bfd275ef4b8c |
| receipt_quantity_allocations | 1 → 1 | 5f39cd32e402f2080b27e00000eb975e9d8e99429a98457af901b6fbb5c74e1c |
| repair_command_requests | 23 → 23 | b95ab0b93d07373bfdaa4370f2a687730baa32dca5d0984de16e6bafbdd66e87 |
| repair_custody_events | 12 → 12 | d534f1b07604ac1edaa16f0afbb38f930cce1d87858b5f3cb279ce7e0f844b13 |
| repair_events | 23 → 23 | b9ae5b2d2f27017c2c0f6228ef49e7c56d6297511dd3fddfe80f16ee97e3c526 |
| repairs | 6 → 6 | 7ebba30e2d67605524d579da613f03cb0829f9f5e44d22aaba48961ff7c1534c |
| shop_debts | 6 → 6 | c2f8677f315ab7d71b454ca3d9abfa9696b64e6dc68c8d8d7e5f2788ac2e2f62 |
| shop_entitlements | 5 → 5 | 7b27a933c21218bc29da679490622839b90a8ad93b3a735b32a0f168dc4d38b7 |
| shop_memberships | 11 → 11 | 0aa1500d9a4dd3039a4163da021d1302e0fbee9955286de6b52b903e70f73e01 |
| shops | 11 → 11 | bd0615ce39ed89023018004d4e89f9287396ff93367ed4349e28b3b08731fa14 |
| traders | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |

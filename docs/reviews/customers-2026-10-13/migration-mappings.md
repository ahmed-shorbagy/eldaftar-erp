# Local / hosted migration reconciliation

Date: 2026-10-13. Connected development project xchapwvmvoefriqcxtvn. All 34 hosted names map to local sources. Thirty-two trimmed/CR-normalized SHA-256 hashes match exactly. The preexisting daily_ledger_trades and inventory_sync_operation_index sources differ only in full-line comments and whitespace; SQL tokens match after that normalization. The empty local 20261001124245 preparation marker remains undeployed, as documented in the historical owner-feedback deployment. No old migration was reapplied, renamed, repaired or rewritten.

| Local source | Hosted version | Hosted normalized SHA-256 |
| --- | --- | --- |
| [20260924130019_shops.sql](../../../supabase/migrations/20260924130019_shops.sql) | 20260924130019 | 765e346fc27768c73abcc0419e9505d3364b4a6afb6473fcbed110120aebb125 |
| [20260924130035_shop_access.sql](../../../supabase/migrations/20260924130035_shop_access.sql) | 20260924130035 | bfc58aec0febbccecc7f8329711d4c05bcdb291e021e212d36b435ac2262b44d |
| [20260924130052_verified_access.sql](../../../supabase/migrations/20260924130052_verified_access.sql) | 20260924130052 | 434c42d9e5c8dfdf7bf03546a89b0e8a40ff855cc3bcef4084f97ae559b36524 |
| [20260924130108_account_setup.sql](../../../supabase/migrations/20260924130108_account_setup.sql) | 20260924130108 | a10bfce758348faa6f0a2ae50882c88b05ac755dc0f403c8e6f5f6affddefa5a |
| [20260924130123_staff_commands.sql](../../../supabase/migrations/20260924130123_staff_commands.sql) | 20260924130123 | 73aeeb84783c7f2077ab54d989f22ca60512487e8de3c6f5285ef8b9605933d0 |
| [20260924130136_platform_admin.sql](../../../supabase/migrations/20260924130136_platform_admin.sql) | 20260924130136 | 39da95b380c6a33f961ddcaa24b102fbf29e8916b11389acd063756a167cc8dc |
| [20260924130348_policy_auth_cache.sql](../../../supabase/migrations/20260924130348_policy_auth_cache.sql) | 20260924130348 | 6cd6cac3eff457a778a8167f1cfee5fd40e47e81e04afce82b4e3f08319cf3d4 |
| [20260924141455_list_my_shop_accounts_status.sql](../../../supabase/migrations/20260924141455_list_my_shop_accounts_status.sql) | 20260924141455 | bc7e27727ea906187fcf31db9d1081e043198e5f7192b9f36e0df5e736d6a3ac |
| [20260926075930_egypt_owner_password_registration.sql](../../../supabase/migrations/20260926075930_egypt_owner_password_registration.sql) | 20260926075930 | f64bc79e94ffd15dd719720305b5892e7197bc894a937beb279d2c39f26ff158 |
| [20260926120634_owner_only_access.sql](../../../supabase/migrations/20260926120634_owner_only_access.sql) | 20260926120634 | 21e7320c94fc0b465fa0afee01f02e5257210985d96c3c5a625525cc610f7956 |
| [20260927065414_opening_balances.sql](../../../supabase/migrations/20260927065414_opening_balances.sql) | 20260927065414 | eaae9d8215365f8649520ba5895463d38a0d70de573e6f47ec5be47bff5d231f |
| [20260927070108_opening_balance_indexes.sql](../../../supabase/migrations/20260927070108_opening_balance_indexes.sql) | 20260927070108 | 1fe52426ac9c70217336b2cd30e34f366c86e3f15ccd74af551bd2c15cfd58f0 |
| [20260929115012_daily_ledger_trades.sql](../../../supabase/migrations/20260929115012_daily_ledger_trades.sql) | 20260929115012 | f38ef68a399597e9957aba1572ab485620061f02791df9a18fedfec6d823668d |
| [20260929115026_invoice_dispatch_confirmation.sql](../../../supabase/migrations/20260929115026_invoice_dispatch_confirmation.sql) | 20260929115026 | 574bd049d9f03948aec302997a0b9c359c6f36a851b4aa95c9bc97be5e311597 |
| [20260929115032_purchase_cash_settlement.sql](../../../supabase/migrations/20260929115032_purchase_cash_settlement.sql) | 20260929115032 | 023d4acc1a159e49b5b62872193bed6287b14944ccedb21086fca37871503f78 |
| [20260929123543_daily_ledger_cash_transfer.sql](../../../supabase/migrations/20260929123543_daily_ledger_cash_transfer.sql) | 20260929123543 | dd5c6be4951afa3af42e323f3ea6b7a84f04bf17d24c5ae04d87d63011a5f06b |
| [20260929124544_daily_ledger_scrap_sale.sql](../../../supabase/migrations/20260929124544_daily_ledger_scrap_sale.sql) | 20260929124544 | c0e8c77c64393dba761356ace65347b9e40ee4ad0bd3c3a229502b200b7c4833 |
| [20260930063913_daily_ledger_scrap_to_stock.sql](../../../supabase/migrations/20260930063913_daily_ledger_scrap_to_stock.sql) | 20260930063913 | 573d6d29a2244f89219ea909bff5a4790040fd2b542c7d7a5c351d933938e413 |
| [20260930072025_daily_ledger_linked_returns.sql](../../../supabase/migrations/20260930072025_daily_ledger_linked_returns.sql) | 20260930072025 | 81f307bfd8d1f170ff16f02e187444229903bb25456a53ff31ee5839173a8621 |
| [20261001133047_explicit_invoice_price_components.sql](../../../supabase/migrations/20261001133047_explicit_invoice_price_components.sql) | 20261001133047 | 99380385ae0449d3be903131fe471892b50c392d88666b9535079316d7042a0e |
| [20261004081229_milestone_3_inventory_contract.sql](../../../supabase/migrations/20261004081229_milestone_3_inventory_contract.sql) | 20261004081229 | 44d3095e517c4aef5f48cc613274c1f8644ff9a71ebd351c322bef4aacdce53b |
| [20261004081347_inventory_sync_operation_index.sql](../../../supabase/migrations/20261004081347_inventory_sync_operation_index.sql) | 20261004081347 | 1763f24345ced99ba4aed6be9271cf8af4dee69d9f983c39683dc675bc6846d6 |
| [20261004090000_daily_notes_and_ledger_pagination.sql](../../../supabase/migrations/20261004090000_daily_notes_and_ledger_pagination.sql) | 20261004120509 | f1e51dfc27803606ee5143bcedab2ce582e450b8d7aa04502c619c58cb800950 |
| [20261005071930_owner_feedback_registration_and_ledger.sql](../../../supabase/migrations/20261005071930_owner_feedback_registration_and_ledger.sql) | 20261006072226 | 20829f644ebca1384379dc7015ef08abf644676e090230b7ad331c4a22d6bc34 |
| [20261005091822_complete_owner_feedback.sql](../../../supabase/migrations/20261005091822_complete_owner_feedback.sql) | 20261006072242 | b591229ebc55b5352bd8252a2c7990624b25dc6ec46770c65bfcc06c6c6f8787 |
| [20261006063258_optional_owner_registration_region.sql](../../../supabase/migrations/20261006063258_optional_owner_registration_region.sql) | 20261006072259 | 8efdc6b06eb259b5bc6022b07638f3f2ec586b6f3aece77e1912a14d9cbb4bda |
| [20261006080053_ledger_compensation.sql](../../../supabase/migrations/20261006080053_ledger_compensation.sql) | 20261006083846 | 326d2a90ced3b7025bd37c843f674208e8d5be1d65b73624c10421958c769f23 |
| [20261006123700_ledger_return_refund_allocation.sql](../../../supabase/migrations/20261006123700_ledger_return_refund_allocation.sql) | 20261006124322 | e1eb13b58d568feee41bed8e77bf02e3c1d161ee876e9133289116a58238c8b3 |
| [20261011120249_required_location_subscription_sync.sql](../../../supabase/migrations/20261011120249_required_location_subscription_sync.sql) | 20261011140005 | 1a6f478d0e255e4357eb0ccdc569afffbbc778d6c63126e8a30b0985a30bed70 |
| [20261012153000_repairs_custody_and_fees.sql](../../../supabase/migrations/20261012153000_repairs_custody_and_fees.sql) | 20261012134320 | 68ef8c1f10932901a413f3d611d088e00ab7687bece8698403adebb457d67f94 |
| [20261012153001_repairs_foreign_key_indexes.sql](../../../supabase/migrations/20261012153001_repairs_foreign_key_indexes.sql) | 20261012135737 | 012a52eb641ac72c1c1cd744c1198d964c64489e038f9d89e3da1476266046c8 |
| [20261013092829_debt_records.sql](../../../supabase/migrations/20261013092829_debt_records.sql) | 20261013110548 | 5f100f59a21c35cf8ffbd5abcaf4c967ef9baddc08112805e3c43126301dd95b |
| [20261013111200_debt_ledger_optional_arrays.sql](../../../supabase/migrations/20261013111200_debt_ledger_optional_arrays.sql) | 20261013111157 | 18904d4afd2db82b62f790ddd20aa7a387d0bf5a829e0093f10b0d2fb9a7a5dc |
| [20261013114617_customers_crm.sql](../../../supabase/migrations/20261013114617_customers_crm.sql) | 20261013164251 | 0a4bc3cdb1e9e2a6a69a6cee18ae4e27d391165cbbdd98884ceeec1d8b62e9bb |

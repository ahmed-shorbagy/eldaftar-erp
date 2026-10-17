# Invoice appearance — development deployment and preservation

Date: 2026-10-17, Africa/Cairo. Authorized development project xchapwvmvoefriqcxtvn only. Applied after [separate implementation review](implementation-review.md) and the local gates in [independent validation](independent-validation-2026-10-17.md). The closing read-only proofs below were repeated after application. No application distribution or release build.

| Reviewed source | Hosted version | Name | Raw SHA-256 | Trimmed / CR-normalized UTF-8 SHA-256 |
| --- | --- | --- | --- | --- |
| [20261017140000_invoice_appearance.sql](../../../supabase/migrations/20261017140000_invoice_appearance.sql) | 20261017140000 | invoice_appearance | 9dd047d0d0c01823b805faad5f22e331453db81995137a00daa2034d6e8ea777 | 01f0ce01eb4c422db6e3cdd3710fbd3fe56768ecc1f605659c574bfd24b08fc3 |

The normalized hash decodes the file as UTF-8, turns CR and CRLF into LF, strips leading and trailing whitespace, and hashes those bytes. The file on disk was last written at 17:17:11, immediately before the disposable-database pass at 17:17:31. Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` on this migration path, then `npx supabase migration repair --linked --project-ref xchapwvmvoefriqcxtvn --status applied --yes 20261017140000`. Repair reported `[20261017140000] => applied`. This record does not authorize running either command again.

Live readback after repair: 40 migration rows, latest version `20261017140000`, zero null `statements` arrays. Version `20261016090329` is still named `debt_native_reminders` and still has one statement. Version `20261017140000` is named `invoice_appearance` and has 99 statement-array elements, which is how repair stored the file. Statement text was not printed. No other history row was rewritten. No blind `db push`.

The migration adds appearance and presentation revisions, audits, and requests, private logo-asset rows, and `appearance_revision` on `shop_sync_signals`. It replaces `private.bump_shop_sync` and `private.shop_sync_touch` with the previous customer-sync behavior plus one appearance scope. Appearance tables are named in `shop_sync_touch` and have no sync trigger, so a save bumps sync once. Logo confirmation does not bump sync. The private bucket `eldafttar-private-invoice-logos` is not public, limits objects to 2097152 bytes, and allows `image/png` and `image/jpeg`.

## What stayed unchanged

Fifty-five pre-existing public base tables have the same count and the same full-row SHA-256 immediately before and after application. `shop_sync_signals` stays at 11 rows. Its full-row digest changed because `appearance_revision` was added. Hashing each row after removing that key equals the before digest `c5af424abc106e8dcc3abd5db7e3e243d05f5788b15b657fa0287d69f68c1b5f`.

The public/private function fingerprint that already excluded `bump_shop_sync` and `shop_sync_touch` moved from `a9599c3da1f68926c4d39544d51cf27b0cf03c76cd4784281cbd19d3232faffa` to `0f4702fec698a5358e1b85d0543481540818e7c84924574d22a587473bf6ed07` because the new appearance functions are inside the second hash. Excluding those new names as well returns the original fingerprint. Excluded new names: `invoice_logo_asset_guard`, `invoice_appearance_revision_guard`, `invoice_presentation_revision_guard`, `invoice_optional_text`, `invoice_logo_facts`, `invoice_appearance_fields`, `invoice_current_appearance`, `invoice_operation_facts`, `get_invoice_appearance_v1`, `review_invoice_appearance_v1`, `post_invoice_appearance_v1`, `get_invoice_appearance_status_v1`, `confirm_invoice_logo_v1`, `get_invoice_brand_source_v1`, `invoice_presentation_fields`, `post_invoice_presentation_v1`, `get_invoice_presentation_status_v1`, `get_invoice_presentations_v1`, `get_invoice_presentation_v1`, `invoice_logo_storage_insert_allowed`.

Storage before application: bucket `eldafttar-private-notes` only, public false, limit 5242880, MIME jpeg/png/webp, object count 2. After application that bucket and its object count are unchanged. The new logo bucket has no objects. No object name is listed here.

This snapshot is every public base table around this apply: 56 before, 62 after. It is a new pair. Slice 9's 52-table pair is an earlier record. Some counts match that older pair, including 51 financial operations and 295 postings, while several digests differ. Activity between the two snapshots is left as it was. Nothing was reset to the older pair. No customer row was exported.

Six new tables are empty. Their digest is the SHA-256 of an empty aggregate, `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`:

| Relation | Count |
| --- | --- |
| invoice_appearance_audits | 0 |
| invoice_appearance_requests | 0 |
| invoice_appearance_revisions | 0 |
| invoice_logo_assets | 0 |
| invoice_presentation_requests | 0 |
| invoice_presentation_revisions | 0 |

No hosted synthetic fixture, logo upload, or retirement delete was run. Ignored local evidence stays outside the repository: the before/after aggregate JSON and the disposable SQL log under the user temp directory. No commit, push, publishing, release or production build, reset, or history deletion.

## Exact protected aggregate pair

The SHA-256 column is equal on both sides. Counts are equal on both sides. Canonical row JSON is ordered and joined with a literal newline before SHA-256. Only aggregate hashes and counts are retained. `shop_sync_signals` is excluded here and proved separately above.

| Relation | Count before → after | SHA-256 before = after |
| --- | --- | --- |
| bullion_denominations | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| business_days | 4 → 4 | 02ae4222473ddf4024e6f63c8b09caf32e9aa1a20cdae6e2b9c4e48709bf2909 |
| coin_types | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_command_requests | 29 → 29 | db4193ae7c7059f923909c96c53086917a13de3463848585f35251f8480036a5 |
| customer_events | 29 → 29 | 33ad633a1fe185841b90d4c468041992cb244077394cd4246050d01ba22cf931 |
| customer_notes | 2 → 2 | 87f29d67c644de434e2376d6e45782b70091391e2ad685ab8c51162263b101ec |
| customer_number_declarations | 2 → 2 | 10ab35b01a84f351c641f26fa51135871dc3e79bc94c3f5f8ef909a919eb1b28 |
| customer_number_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| customer_operation_links | 5 → 5 | f6cac379a3a90592efd42a54a0ef0025c7049b5ec8da4f61d2b3e34910de4c9e |
| customer_phones | 2 → 2 | 653161f8d849cce331fb77d13309acfc947f11bf0e8790a8add1b5d2b858b122 |
| customers | 6 → 6 | c39a25dcec151c7569c2259054b4b1c9fb5aeb5e87eb9e492285fe5ac7625deb |
| daily_note_attachments | 2 → 2 | cc2fc9b0e15f5d3b59d4bdab1f5cda1f3a9d6c7e370a5f6124f5a77f45a7344e |
| debt_command_requests | 16 → 16 | f038d8954030d1365b949a942e924d87a574e1cee75b0a76d6e9b50962d0598c |
| debt_due_dates | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_due_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_due_requests | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_events | 16 → 16 | 7e0737194b88a69acc1a8a135f03315790eceedc375b7390a369437c64281dd1 |
| debt_native_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_native_intents | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_native_requests | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| debt_settlement_references | 8 → 8 | 29c7f287b87bef351f46ab40a29c4dad04cb138d286c204621392348653c0c27 |
| debt_source_archives | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| egypt_governorates | 27 → 27 | 6e08f2dd2c8d3f5adbd32247126e2ca4c694532c671ec212f9fdce6137a1cfe7 |
| financial_audit_events | 51 → 51 | 246065bb39b62c8766aad230200eb73083472202ce6a7416986539f28e4faba8 |
| financial_command_requests | 51 → 51 | 42ac290cea54617fc760536618ef48676a637355e2d827c8c27504c80ec8663d |
| financial_operation_details | 48 → 48 | 0b59a39a1be2d1931c595ad254534db4e4a8154512e24b97cc2611744b3378c6 |
| financial_operations | 51 → 51 | 6868ef7dedd53bc72d0db9b05d943eaaff5b3224473bc61845410db341219ff2 |
| financial_outbox | 51 → 51 | 988b8041f85ce960b0e725c8c49e1366c2df424566707ac84ddb25ca4cd45f36 |
| gold_obligations | 1 → 1 | eb7839468cffef14616f6dd68678d0e8f1ab746d5c141592e761afc97aa36280 |
| identity_audit_events | 11 → 11 | 61dda3c595442d843611bf66d69b4353943448e0bd0fe2820ca803f3e1218eac |
| inventory_catalog_events | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_catalog_requests | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_command_envelopes | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_explicit_plans | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| inventory_lot_movements | 46 → 46 | e03a14bcccb44dd0425789e2914588e8adb6838e0c7ba8e37dbca71309b08df1 |
| inventory_lot_sync | 51 → 51 | 9e7f954fc890c800862dd550018a144e1fd82437f66c6e8d03aade7261acfef2 |
| inventory_lots | 26 → 26 | 5c63800ab42d03735295e6f080c4e81c1ab8b2c07599507339e7de9204412ab2 |
| inventory_products | 25 → 25 | 72a0b90d7d6ca35c60b871a810a4c0064e718059c52ae40c6169d368655a8642 |
| inventory_receipts | 1 → 1 | 9d0e566905379d072944ae2057289b974edffbaeff985e8f040237fd8122d5f3 |
| invoice_dispatch_confirmations | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |
| journal_postings | 295 → 295 | 33b30ffc28295fd81592f4ce0e61c4acec52a67171b1adfbfe03afedb907bfea |
| journals | 140 → 140 | 06ea420d5faadf1a4d313cd7325311d328eebc34650eb5892be4aa45012de8d4 |
| ledger_accounts | 61 → 61 | 9b5067c895c4ed5a9f70bf84e8af45c0c2415ffe0e5a2aa9de69b10c6be5c19d |
| platform_admins | 1 → 1 | 62da0fcd1d79d2876d801f99a55bb31faa2099da7b3c6529ebba48b5bda97cd5 |
| purchase_cash_payables | 5 → 5 | 8525f58f49f0f8bf2c631267a8bbf39d576ed61071f3655ac6a4e98ff607a638 |
| receipt_quantity_allocations | 1 → 1 | 5f39cd32e402f2080b27e00000eb975e9d8e99429a98457af901b6fbb5c74e1c |
| repair_command_requests | 23 → 23 | 65e1a52f8964619969bffca4434f88cdbd243fc7b1c2973d55c1fecd36194749 |
| repair_custody_events | 12 → 12 | 267a5b9fb001a0b53b9a3f403d815cd74ced9a67a6ab67e6a74ac11004a6bcd1 |
| repair_events | 23 → 23 | 21333ad5335ae1abf4bb44e12a941f26ebd5867a9253429f91d442490e762931 |
| repairs | 6 → 6 | d12a5677e808be8940a6bd4e77628d5ca421bf358d2d60b42416857809dc15a2 |
| shop_debts | 6 → 6 | f88e3b552f0e5df6de3b2436c5b36a1acb3a390d9f00939d978df82329641180 |
| shop_entitlements | 5 → 5 | edb2fece2f95a839685704ffbea70eed0b8e30be3e6e391760554444f054b2cd |
| shop_memberships | 11 → 11 | ee85b1684f884b31802cabcff9927cb7fea88b5e6c710d75198419d26c8abdee |
| shops | 11 → 11 | 25bad11011c5581a076b29f4de0626eb5f653d21adf36794f58a91d01a9bcdbe |
| traders | 0 → 0 | e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 |

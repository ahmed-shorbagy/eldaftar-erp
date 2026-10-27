# Payment methods rename/archive — development deployment — 2026-10-27

Target: **xchapwvmvoefriqcxtvn**. Applied only `20261027140000_payment_method_labels` after local Flutter codec/analyze gates, then repaired migration history to `applied`. No reset, broad `db push`, Edge Function change, commit, or app publish.

Migration:

| Version | SHA-256 |
| --- | --- |
| `20261027140000_payment_method_labels` | `1C4FDA4F55A43E55A26867C89B81C791D33D755C7C20A8B61B022AADA4645AE3` |

Before: 70 migrations, latest `20261027120000`. After repair: 71 rows, latest `20261027140000`.

Preservation: shops/entitlements/memberships/auth users/financial operations counts and membership role MD5 unchanged. Columns `display_label_ar` / `archived_at` present; RPCs `list_shop_payment_methods_v1` and `save_shop_payment_methods_v1` present; 12 cash-method rows labeled; tender sum allows `label_ar`; ledger v2 relabels. See [preservation.json](preservation.json).

Flutter: owner «المزيد ← وسائل الدفع» rename/archive for the four methods; live ledger labels; entry dropdowns hide archived. Native/owner acceptance remain open.

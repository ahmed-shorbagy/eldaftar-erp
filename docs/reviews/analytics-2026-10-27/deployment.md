# Shop analytics (week/month/year + staff) — development deployment — 2026-10-27

Target: **xchapwvmvoefriqcxtvn**. Applied only `20261027120000_financial_period_analytics` after local Flutter analytics gates, then repaired migration history to `applied`. No reset, broad `db push`, Edge Function change, commit, or app publish.

Migration:

| Version | SHA-256 |
| --- | --- |
| `20261027120000_financial_period_analytics` | `43248454822E7483EF930786F1EA7AB80BEDFB636127B490869734090D947F65` |

Before: 69 migrations, latest `20261026130000`. After repair: 70 rows, latest `20261027120000`.

Preservation: shops/entitlements/memberships/auth users/financial operations counts and membership role MD5 unchanged. RPCs `get_financial_period_analytics_v1` and `confirm_financial_period_analytics_pdf_v1` present. See [preservation.json](preservation.json).

Flutter: «المزيد ← التحليلات» with period controls, shop summaries, owner-only staff weights, R2 `report_pdf` export. Native/owner acceptance remain open.

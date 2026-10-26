# Shop staff grants and profile — development deployment — 2026-10-26

Target: **xchapwvmvoefriqcxtvn**. Applied only the three ADR 0033 migrations after local gates, then repaired migration history to `applied`. Deployed Edge Function `shop-staff-create` with `--use-api`. No reset, broad `db push`, commit, or app publish.

Migrations:

| Version | SHA-256 |
| --- | --- |
| `20261026120000_shop_staff_grants_and_profile` | `682B7BA78FC1E45958F8E413B1FA94AE3A98F2670DA97EBBA8884C04322F9C89` |
| `20261026120100_shop_staff_commands` | `E39657D6557DF1BBB051F534CFDE4A923508B97FDC5AD1786413D1FE5DA04070` |
| `20261026120200_shop_staff_grant_enforcement` | `0E69C32D44091A06C105C790026AAB64DC327B4A93A23B2ED03909F1A10DAE96` |

Before: 65 migrations, latest `20261025120000`. After repair: 68 rows, latest `20261026120200`.

Preservation: shops/entitlements/memberships/auth users/financial operations counts and membership role MD5 unchanged; grant table empty until an owner creates staff. Profile and staff list RPCs present; trade wrapper includes `allow_member_permission`. See [preservation.json](preservation.json).

Limitations: Deno handler unit tests not executed locally; native owner/staff acceptance and React publication remain open. Temporary closing-count staff remain under ADR 0023.

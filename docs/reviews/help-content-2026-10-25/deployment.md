# ADM-05 development deployment — 2026-10-25

Target: **xchapwvmvoefriqcxtvn**. Applied only `20261025110000_help_content_and_announcements` after local gates. No reset, broad push, commit or publish.

SHA-256: `2F551A0B9BD92B6A70804C943DC706330B13F64DFC6F4423030B170E6CB219E3`.

Before: 63 migrations, latest `20261025100000`. After repair: 64 rows, latest `help_content_and_announcements`.

Hosted rollback fixture exit 0. Preservation: shops/entitlements/memberships/auth/financial counts and `list_my_shop_accounts` MD5 unchanged; help topics/articles start at 0; announcement unpublished; authenticated can execute catalog read; table SELECT denied. See [preservation.json](preservation.json).

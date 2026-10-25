# ADM-07 development deployment — 2026-10-25

Target: **xchapwvmvoefriqcxtvn**. Applied only `20261025120000_admin_subscriber_contact_reveal` after local gates. No reset, broad push, commit or publish.

SHA-256: `701F4AC4B6D3D33E46274E6617A8ECBD365488777841D8BDF41101FB5157E60F`.

Before: 64 migrations, latest `20261025110000`. After repair: 65 rows, latest `admin_subscriber_contact_reveal`.

Hosted rollback fixture exit 0. Preservation: shops/ledger/auth/help counts and `list_my_shop_accounts` MD5 unchanged; one platform admin has the PII flag; reveal audit empty after fixture rollback; authenticated can execute reveal RPC; audit table SELECT denied. See [preservation.json](preservation.json).

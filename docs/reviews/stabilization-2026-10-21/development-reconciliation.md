# Development reconciliation — 2026-10-21

Target: the established development project `xchapwvmvoefriqcxtvn`, healthy on PostgreSQL 17.6.1.166. The standing authorization in [AGENTS.md](../../../AGENTS.md) covers this task's tested development reconciliation. No production or other project was used.

## Installed state and history

The initial hosted history contained 53 migrations. Their normalized source fingerprints matched the corresponding local sources, including the five previously documented meeting timestamp mappings. A fresh local application of every repository migration provided an independent schema reference.

The [read-only catalog manifest](../../../supabase/tests/stabilization_schema_manifest.sql) matched development for all **396 public/private function definitions and anonymous/authenticated execute grants**, media/shop columns and constraints, media-table RLS/direct grants, and legacy Storage insert policies. The home function was already volatile and already preferred the open financial day. The R2 registry and required media RPCs were already installed. There was no pending product-schema fix to replay.

Four installed migrations lacked history entries. Supabase CLI 2.118.0 repaired only these entries as applied, pinned with `--linked --project-ref xchapwvmvoefriqcxtvn`:

| Version | Local source |
| --- | --- |
| `20261020101500` | `shop_image` |
| `20261020143000` | `shop_image_r2` |
| `20261020160000` | `r2_media_everywhere` |
| `20261020170000` | `ledger_home_volatile` |

Final history contains 57 entries. The original 53 rows, including their full statement arrays, are unchanged. The additional local `20261001124245_ledger_pagination_and_corrections.sql` is empty and has no executable migration to apply; it was left unchanged. No blind database push, schema replay, historical rewrite or reset occurred. Installed-schema manifests before and after history repair are equal.

`owner-register` remains active v4, `r2-media` active v2, and `closing-staff-create` active v1. No Edge Function needed redeployment.

## Fresh hosted verification

Each behavior gate used synthetic fixtures inside its own transaction ending in rollback. Only the loopback/database-name guard was omitted for the three locally guarded sources, with the connected tool pinned to the authorized development project. All authorization, accounting, precision and replay assertions remained intact.

| Source | Result / scope |
| --- | --- |
| [Calendar/home and counts](../../../supabase/tests/ledger_calendar_home.sql) | Passed: open financial day survives calendar midnight, date-wide counters/paging, preserved balances, Cairo DST/time-zone boundaries, owner named-count close/replay/audit and isolation. |
| [Staff delegation](../../../supabase/tests/staff_closing_delegation.sql) | Passed: count-only identity, service-only provisioning boundary, no general membership/data access, submission/revocation/expiry/stale-day access loss, owner discrepancy review and owner-only financial close/audit. |
| [Invoice appearance](../../../supabase/tests/invoice_appearance.sql) | Passed: verified logo reference, owner isolation, immutable editions, renderer history, replay and no source-financial/dispatch effect. |
| [Exact pricing](../../../supabase/tests/invoice_price_components.sql) | Passed: exact integer components/tender totals, mismatch rejection and replay. |
| [Notes and pagination](../../../supabase/tests/daily_notes_pagination.sql) | Passed: verified R2-only new attachments, registry ownership/type/hash contract, safe note retry/status, more than 500 disjoint history pages, zero financial effect, cross-shop/revoked/expired boundaries and read-only legacy Storage. |
| [Trade/dispatch commands](../../../supabase/tests/daily_ledger_trades.sql) | Passed: exact trades/rollback, pending invoice scope, explicit owner send confirmation, idempotency and unauthorized actor rejection. Historical return grants are restored only inside the rolled-back fixture. |

The notes denial assertions now accept either insufficient privilege or zero rows affected by RLS; any modified/deleted row still fails. This handles hosted Storage's broader table grants without adding a write policy or changing product schema.

Before/after full-row fingerprints and counts are unchanged across **all 72 public tables**. No synthetic shop, account, note, invoice dispatch, staff task or close was committed by these gates. Transaction rollback does not reverse consumed sequence values or service logging. Raw manifests, credentials and execution logs remain outside Git; this record contains no customer data or source requirement documents.

## Delivery boundary

This task repaired development migration tracking and verified installed behavior. Flutter source fixes are local until an updated app is run or separately distributed. There was no commit, push, release/production build, app publication, paid resource, customer handoff or message. Hosted SQL is not a native client-to-Auth/R2/share-sheet acceptance test; see [remaining acceptance](acceptance.md).

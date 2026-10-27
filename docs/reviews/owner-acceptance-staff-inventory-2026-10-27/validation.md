# Implementer pre-acceptance validation — 2026-10-27

## Already verified (prior slices)

| Gate | Evidence |
| --- | --- |
| Staff/profile SQL + Flutter grants | [shop-staff-2026-10-26/validation.md](../shop-staff-2026-10-26/validation.md) |
| Staff/profile hosted deploy | [shop-staff-2026-10-26/deployment.md](../shop-staff-2026-10-26/deployment.md) |
| Inventory/traders Flutter + hosted summaries | [inventory-traders-2026-10-26/validation.md](../inventory-traders-2026-10-26/validation.md) |

## This package

| Gate | Result |
| --- | --- |
| Owner checklist authored | [acceptance.md](acceptance.md) |
| Platform matrix | [platform-notes.md](platform-notes.md) |
| Deno `shop-staff-create` handler tests | **Not run** — Deno CLI still unavailable on the Windows agent host |
| Hosted function-def check for inventory/trader summary RPCs | Covered in inventory-traders preservation (`has_original_held`, `has_trader_pending`) |
| Flutter inventory widget/domain tests | Passed in inventory-traders slice; re-run before owner device day if sources change |
| Synthetic RTL captures | Prefer existing `test/inventory_capture_test.dart` and staff/profile widget coverage; full pixel matrix remains optional and is not owner acceptance |

## Limits

- No physical Android / iOS / Windows owner run in this package.
- Closing Deno gap requires installing Deno or CI with Deno.
- Local pgTAP needs a Postgres with pgtap; hosted preservation already checked summary RPC bodies.

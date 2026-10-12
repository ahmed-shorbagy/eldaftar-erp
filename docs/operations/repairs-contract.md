# Repair custody contract

Local contract for REP-01/02/03. This file records the implemented rules and examples. It is not final owner acceptance. [Codex independent validation](../reviews/repairs-2026-10-12/validation.md) records reviewed corrections, gate results and remaining limits.

## Scope

The Flutter owner app registers a repair contact on the repair itself: name, optional phone, item, measured grams to three decimals, karat 14/18/21/22/24, issue, and intake notes. An estimated fee is optional integer piastres. There is no customer table, debt table, reminder, report, or invoice template in this slice. React admin has no shop repair module.

Navigation is an operational More entry, الصيانة. It is writable for an active owner when the gateway is available, read-only when the entitlement is expired, and unavailable with the sentence الصيانة غير متاحة في هذا الاتصال when the gateway or user is missing. Pending shops do not open the workspace.

## Effects

| Step | Custody | Saleable stock | Cash | Outstanding |
| --- | --- | --- | --- | --- |
| Intake | +measured mg once | 0 | 0 | 0 |
| Received to in progress, then ready | unchanged | 0 | 0 | 0 |
| Handover, collect all or part | release once | 0 | +collected once | final − collected |
| Handover, collect none | release once | 0 | 0 | final |
| Cancel active repair | release once | 0 | 0 | 0 |
| Archive delivered or cancelled | unchanged | 0 | 0 | unchanged |

Collected cash uses the open business day and existing cash methods. `0 <= collected <= final`. `all` requires collected = final and final > 0. `part` requires `0 < collected < final`. `none` requires collected 0, empty tenders, and no day keys. A closed or stale day rolls the custody release back with the fee.

## Example payloads

Intake, 1.255 g = 1255 mg, estimate 15000 piastres:

```json
{"version":1,"kind":"repair_intake","customer_name":"عميل الإصلاح","customer_phone":"01001234567","item_description":"خاتم مفصص","measured_milligrams":"1255","karat":21,"issue":"مفصص","intake_notes":"ملاحظة","estimated_fee_piastres":"15000"}
```

Partial handover:

```json
{"version":1,"kind":"repair_handover","repair_id":"<uuid>","expected_version":"3","final_fee_piastres":"20000","collection":"part","collected_piastres":"8000","tenders":[{"method":"cash","piastres":"8000"}],"expected_day_id":"<uuid>","expected_day_version":"<day version>"}
```

Unpaid handover omits the day keys and sends `"collection":"none"`, `"collected_piastres":"0"`, `"tenders":[]`.

Cancel sends `"confirm_return":true` and a reason. Archive sends `"confirm_archive":true`. Neither sends a cash amount.

## Authority and retries

The client saves the envelope before sending. A storage failure does not send. A timeout keeps the same key and payload. Cleanup after a known commit or rejection may fail; the known outcome is kept and the stored command remains for the next reconcile. Repair reconciliation calls `get_repair_command_status`, not `get_opening_status`.

Lists and detail refresh when the repair, ledger, or day sync scope changes. A confirmed collection also refreshes the ledger. Shop-local timestamps are server conversions. The original intake payload and custody events are immutable.

## Error codes

`invalid_input`, `payload_mismatch`, `stale_repair`, `repair_not_ready`, `repair_not_active`, `repair_not_terminal`, `stale_day`, `day_closed`, `tender_mismatch`, `shop_not_active`, `shop_unavailable`, `session_expired`, `unauthenticated`, `forbidden`, `not_found`.

Rollback tests install a transaction-local failure trigger on the disposable database only; production commands contain no test failure switch.

## Not in this slice

Disposal, transfer of ownership, consumed repair metal, taxes, accrual, and settling the outstanding fee as a customer debt. Those need a later decision. Cancelling an active repair is an explicit zero-fee return so custody is not orphaned.

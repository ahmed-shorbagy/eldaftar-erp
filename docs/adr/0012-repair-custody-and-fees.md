# Repair custody and fees

Status: implemented working rule for REP-01/02/03; independently validated and deployed to development. [Deployment](../reviews/repairs-2026-10-12/deployment.md). [Validation](../reviews/repairs-2026-10-12/validation.md).
Date: 2026-10-12

Customer gold received for repair is custody. It is not saleable stock, scrap, a catalog product, or a lot. Intake increases custody once and posts no cash. Delivery, cancellation, and archive never hard-delete the record.

## Commands

The signed-in owner is the only actor. Writes go through `post_repair_intake_v1`, `post_repair_status_v1`, `post_repair_handover_v1`, `post_repair_cancel_v1`, and `post_repair_archive_v1`. Each command stores its original payload in `repair_command_requests` only after success. `get_repair_command_status` is the custody registry. `get_opening_status` does not prove an intake or an unpaid handover.

Money and weight stay integer piastres and milligrams. A collected fee posts once through the existing cash journal, open day, day version, and `financial_command_requests` row, with kind `repair_fee` and label أجرة إصلاح. The offset account is the existing `movement_money_clearing` account. Outstanding equals final fee minus collected and stays on the repair. No debt, gold obligation, or payable row is written.

## Worked examples

Intake of 1.255 g is 1255 mg at 21K with an optional estimate of 15000 piastres. Lists show 1.26 g. Confirmation also shows 1,255 ملليجرام. Stock and cash stay unchanged.

Partial handover: final 20000, collect 8000 cash, outstanding 12000. One money journal is +8000 cash and −8000 clearing. The day version increases by one. Custody releases once.

Unpaid handover: final 20000, collect 0. Custody releases once. No journal, no day bump, no obligation. Outstanding 20000 remains on the repair.

Full handover: final 20000 split 12000 cash and 8000 wallet. One journal, outstanding 0.

Cancellation of an active repair asks the owner to confirm return to the customer and requires a reason. Custody releases once. No fee is posted because collection happens only at handover. Archive is allowed only from delivered or cancelled. It does not reverse cash or forgive outstanding. The outstanding filter still finds an archived balance.

## Bounds that are not assumed

No disposal, ownership transfer, repair loss, material consumption, tax, accrual, or later debt settlement. Repair images and a general customer file are outside this slice. A zero-fee return is the cancellation path, so custody is not left without a release. Duplicate handover with the same or a different key cannot release or post twice.

The source migration `20261012153000_repairs_custody_and_fees.sql` is deployed to development as `20261012134320`; its covering-index follow-up is deployed as `20261012135737`. The sync read remains compatible before deployment by selecting the protected revision row and treating an absent repair revision as zero. The repair RPCs are now available in the development project.

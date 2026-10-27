# Owner / device acceptance — staff, profile, inventory, traders — 2026-10-27

Implementer package only. Checking boxes after **real** runs on development `xchapwvmvoefriqcxtvn` closes native/owner acceptance for this bundle. Synthetic captures and SQL gates do **not** count as owner acceptance.

Evidence already on hand: [shop-staff validation](../shop-staff-2026-10-26/validation.md), [shop-staff deployment](../shop-staff-2026-10-26/deployment.md), [inventory-traders validation](../inventory-traders-2026-10-26/validation.md), [inventory-traders deployment](../inventory-traders-2026-10-26/deployment.md), [ADR 0033](../../adr/0033-shop-staff-grants-and-profile.md).

## Platforms

| Device | OS / app build | Date | Tester | Result |
| --- | --- | --- | --- | --- |
| | Android | | | |
| | Windows | | | |
| | iOS | | | |

## A. Shop profile (owner only)

- [ ] «المزيد ← بيانات المتجر» opens; Arabic RTL readable in light and dark
- [ ] Edit shop name, owner display name, phone; review shows effects; confirm saves
- [ ] Pending / success / failure Arabic states; duplicate tap while in flight does nothing
- [ ] Reconnect / session refresh still shows confirmed values
- [ ] Issued invoice identity (shop/owner on already-issued editions) unchanged after profile save

## B. Staff grants (owner + second session)

- [ ] Create **موظف** with subset of grants; create **شريك** with different grants
- [ ] Second session: employee cannot open customers, debts, repairs, traders, profile, staff, closing team, appearance
- [ ] Employee «المزيد» has no shop cash/gold totals
- [ ] Employee with inventory grant reaches الجرد الفوري; denied sale/purchase commands show honest Arabic errors (not UI-only hide)
- [ ] Partner with inventory sees الجرد; still cannot open التجار والأمانات
- [ ] Toggle grants; second session reflects change after refresh/reconnect
- [ ] Revoke staff; second session loses shop access promptly
- [ ] Owner alone still confirms financial close; temporary count staff remain ADR 0023 (out of this checklist)

## C. Instant inventory (owner; optional staff with inventory grant)

- [ ] Totals show نقدي / انستا / محفظة / فيزا beside stock buckets
- [ ] أمانة تاجر current + وزنة التجار الأصلية visible when data exists
- [ ] Jewelry-by-karat / scrap / سبائك / جنيهات sections match stock
- [ ] Addition, removal, correction still review exact cash/gold effects before confirm
- [ ] RTL at ~320 / 390 / 1440; light and dark; enlarged text readable

## D. Traders / abouniyat (owner only)

- [ ] Pending banner when weights not yet in stock; row badges show counts
- [ ] Per-receipt chips: لم تُضف / أُضيفت
- [ ] Tap pending custody → ownership transfer; deferred → recognition
- [ ] «تمت إضافتها يدويًا» opens manual link without duplicate stock posting
- [ ] Cash payable and gold obligation open settlement from trader detail
- [ ] كشف أمانة PDF shares; no claim of printer/WhatsApp delivery

## Sign-off

| Role | Name | Date | Notes |
| --- | --- | --- | --- |
| Owner | | | |

After sign-off, update ID-02 / INV-01 / INV-05 / TRD-01–03 in [requirements-matrix.md](../../requirements-matrix.md) and the ADR 0033 status line. Do **not** mark Milestone 4 complete from this checklist alone.

## Explicit exclusions

Invoice DOC-04 harness, ADR 0023 closing-count two-device flow, TRD-04 combined multi-picker, React admin publication, HELP-02, ADM-06, analytics month/year (separate Phase 2).

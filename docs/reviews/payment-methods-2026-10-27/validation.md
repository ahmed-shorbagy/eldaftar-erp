# Payment methods rename/archive (SET-02 / D24) — local validation — 2026-10-27

- ADR: [0035](../../adr/0035-payment-method-rename-archive.md)
- SQL: migration `20261027140000_payment_method_labels` applied on development; definition/presence checks in [preservation.json](preservation.json); pgTAP [payment_method_labels.sql](../../../supabase/tests/payment_method_labels.sql) authored for local Postgres with pgtap
- Flutter: `dart analyze` on payment-methods feature + ledger wiring — clean; `flutter test test/payment_methods_codec_test.dart` — passed (custom labels + archived entry filter)

Limits: native RTL theme review on «وسائل الدفع», owner acceptance, and custom payment methods remain open.

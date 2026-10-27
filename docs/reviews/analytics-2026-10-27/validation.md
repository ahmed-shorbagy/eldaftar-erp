# Shop analytics — local validation — 2026-10-27

- ADR: [0034](../../adr/0034-shop-analytics-month-year-staff.md)
- SQL: migration applied on development; definition/presence checks in preservation; pgTAP [financial_period_analytics.sql](../../../supabase/tests/financial_period_analytics.sql) authored for local Postgres with pgtap
- Flutter: `dart analyze` on analytics + wiring — clean; `flutter test test/analytics_codec_test.dart test/analytics_widget_test.dart` — 4 passed (owner staff section vs non-owner)

Limits: native RTL theme review, share/print sheets, and owner acceptance remain open. Daily/weekly books screens unchanged.

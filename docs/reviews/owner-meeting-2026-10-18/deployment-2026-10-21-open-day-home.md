# Deployment 2026-10-21 — open financial day home journal

2026-10-21, Africa/Cairo. Owner override: keep the main ledger on the open financial day until explicit close; calendar midnight must not force a new day or block entry.

## Applied

| Local migration | Hosted | Notes |
| --- | --- | --- |
| `20261021101500_ledger_home_open_day.sql` | repaired as applied | `get_daily_ledger_home_v1` prefers the open `business_days` date; calendar date only when no day is open |

Application used `npx supabase db query --linked --project-ref xchapwvmvoefriqcxtvn --file` on that migration, then `migration repair --status applied 20261021101500`. No blind `db push`. Existing data preserved. Hosted readback confirmed the function body references `v_open_date`.

Flutter removes the calendar-match write gate. Sale/purchase/expense remain allowed while the financial day is open.

## Validation run

- `flutter test test/meeting_calendar_rollover_test.dart test/meeting_calendar_and_count_test.dart test/confirmed_ledger_dashboard_test.dart`
- Local SQL runner for `ledger_calendar_home.sql` not re-run in this turn; the regression source was updated for the open-day expectation.

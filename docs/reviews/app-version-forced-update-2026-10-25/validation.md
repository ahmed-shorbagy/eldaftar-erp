# ADM-04 minimum version / forced update — local validation — 2026-10-25

Bounded slice only: platform-admin minimum version per Android/iOS/Windows, public policy read, Flutter full-screen Arabic blocker above Auth, React «تحديث التطبيق» admin form. Soft optional banners, Help, broadcasts, retention and ADM-07 stay out.

## SQL

- Runner: [app_version_forced_update_local_runner.ps1](../../../supabase/tests/app_version_forced_update_local_runner.ps1) against disposable `eldaftar_app_version_adm04_20261025`.
- Results: `APP_VERSION_FORCED_UPDATE_MIGRATION_ROLLBACK_PASSED`, `APP_VERSION_FORCED_UPDATE_SQL_PASSED`.
- Covered: table privilege denial for anon/authenticated; semver compare `1.0.0`/`1.0.1`/equal/higher; invalid short version rejected; anon `get_app_version_policy_v1`; owner set forbidden; empty message and http URL rejected; admin set + idempotent unchanged; public read of minimum; clear nulls minimum.

## Flutter

- `dart analyze` on `lib/src/features/app_version`, `lib/src/app.dart`, `lib/main.dart`: no issues.
- `flutter test test/app_version_gate_test.dart`: 6 passed (compare, evaluate, below-min blocker hides app, equal opens app, fetch-failure retry banner without inventing a minimum, phone/desktop light/dark RTL).

## React admin

- `npx tsc -b`: clean.
- `npm test -- --run src/appVersion`: 12 passed (gateway parse/session-loss/forbidden/invalid; panel save/clear/validation/in-flight disable/load retry/session loss).
- Shell regression: signed-in admin still sees «المشتركون» and the new «تحديث التطبيق» nav.

## Limits

No app-store release build, React production publish, soft-update banners, store URL auto-detection, or owner acceptance. Development deployment is recorded separately.

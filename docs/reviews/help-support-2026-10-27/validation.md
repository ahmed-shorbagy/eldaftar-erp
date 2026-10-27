# HELP-02 support inquiries — validation — 2026-10-27

Scope: bounded HELP-02 per [help-support-plan-2026-10-27](../../operations/help-support-plan-2026-10-27.md) and the submitted [prompt](../../operations/help-support-prompt-2026-10-27.md): owner-only text support inquiries (Flutter), platform-admin triage mailbox (React), backend migration + RPCs, development deployment. No commit/push, no release builds, no publishing.

## Local gates

| Gate | Result |
| --- | --- |
| Migration applies cleanly on a fresh local database (runner run02/run03, PG 17.11, port 55476) | `SUPPORT_INQUIRIES_MIGRATION_ROLLBACK_PASSED`, `SUPPORT_INQUIRIES_DO_BLOCK_PASSED`, `SUPPORT_INQUIRIES_SQL_PASSED` |
| Rollback round trip of [20261027150000_support_inquiries.sql](../../../supabase/migrations/20261027150000_support_inquiries.sql) | passed (fixtures + objects drop, re-apply succeeds) |
| SQL/RLS behavior matrix [support_inquiries.sql](../../../supabase/tests/support_inquiries.sql) | passed (owner/expired/pending owner, partner/employee/anonymous/revoked/expired-session denials, body 10–1000 + newline-only control rule, category enum, rate limit at 10 open, idempotent replay + `payload_mismatch`, `stale_cursor`, admin gate/list/exact-search/transition/replay, append-only audit trigger, shape CHECK) |
| Flutter analysis | `dart analyze` — **No issues found!** (see launcher note) |
| Flutter tests | `flutter test` — **1644 passed, 0 failed** (full suite; includes 13 support-screen tests, 2 help-entry tests, 14 capture tests) |
| React lint | `npm run lint` — warnings only, all pre-existing `set-state-in-effect` pattern in untouched panels; no support-module findings |
| React TypeScript | `npx tsc -b` — clean |
| React tests | `npm test` — **166 passed (21 files)**; includes 19 support gateway + 12 support panel tests |
| Hosted verification and preservation | see [deployment.md](deployment.md) — `SUPPORT_INQUIRIES_HOSTED_DO_BLOCK_PASSED`, preservation counts unchanged |

## Flutter analyze launcher failure (recorded as required)

`flutter analyze` crashes on this machine with a Flutter SDK AOT snapshot error (`analysis_server.dart.snapshot is an AOT snapshot and should be run with 'dartaotruntime'`; full crash report in `app/flutter_18.log` — crash logs removed from the working tree after recording, this file is intentionally not committed). The substitute gate is **`dart analyze`**, which is what `flutter analyze` runs internally against the same analysis options; it completed with no issues. `flutter test` works normally, so test evidence is unaffected. SDK settings were not changed.

## Synthetic captures (not device proof)

**17 captures** under [captures/](captures/) via [support_capture_test.dart](../../../app/test/support_capture_test.dart), with the Cairo font loaded the same way as the other capture suites (`FontLoader` in `setUpAll` — the first capture run without it rendered tofu boxes and was regenerated):

- Support screen (form + category chips + list) × 320/390/1440 × light/dark × text scale 1.0/1.7 — 12 images.
- Filled form state at 390 in both themes — 2 images.
- Help screen no-match view with the emphasized «تواصل مع الدعم» entry card in both themes — 2 images.
- Workspace more menu with the owner-only support link at 390 light — 1 image.

Review findings: all-correct Arabic RTL layout; shared brown/cream/dark tokens in both themes with readable contrast; dates and inquiry IDs render LTR digits inside RTL text; category chips wrap cleanly at 320/1.7 with no horizontal overflow; submit is disabled below 10 characters; answered rows show the saved reply block. No defects found.

## Pre-existing test fixes (recorded, out of scope of HELP-02 behavior)

Commit `c6ddce6` removed the `workspace-*-unavailable` fallback tiles from the more menu (links now hide when their builder is absent) without updating four tests that asserted the old rows; these four pre-dated this slice and were updated to the current product behavior (assert the hidden link without a gateway, use a conditional `scrollUntilVisible` for the lazy ListView when the gateway is provided):

- `app/test/debt_widget_test.dart` — «workspace more menu opens debts from the provided gateway».
- `app/test/repair_widget_test.dart` — «more navigation opens repairs when a gateway is provided».
- `app/test/invoice_appearance_screen_test.dart` — appearance-state test updated the same way.
- `admin/src/subscribers/SubscriberDirectory.test.tsx` — "shows global counts…" asserted the absence of the help nav button, which legitimately exists since the help slice; now asserts the other panels' **content** is absent instead (appVersion/help/support titles).

`app/test/payment_methods_codec_test.dart` — unused import dropped during analysis cleanup.

## Documentation

Contract [support-inquiry-v1.md](../../../supabase/contracts/support-inquiry-v1.md) (owner list `time_zone`, admin rows `shop_created_at`/`shop_time_zone`), [ADR 0036](../../adr/0036-support-inquiries.md), requirements matrix (HELP-02 delivered subset), delivery plan, decisions log, next-slice prompt, and docs README pointers updated.

## Limitations

No device run: owner acceptance on a real Android/iOS/Windows client, admin publication, and production deployment remain open. Native `flutter analyze` unavailable on this machine (see above). React production build intentionally not run (opt-in only).

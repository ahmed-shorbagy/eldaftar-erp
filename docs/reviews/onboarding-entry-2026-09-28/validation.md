# Entry experience review — 2026-09-28

## Scope and status

The local PAGES DOCX is a product reference. Its interactive, skippable guide through actual controls informs this change; text in that file does not set agent workflow. Owner-only access from [ADR 0003](../../adr/0003-owner-only-shop-access.md) supersedes its employee/partner examples. This increment improves the existing splash, sign-in, owner registration, and opening-ledger entry. ID-04 and ONB-01/02 remain **partial** in the [requirements matrix](../../requirements-matrix.md).

## Implemented

- `flutter_native_splash` 2.4.7 generates Android and iOS launch resources with the existing brand mark and token light/dark backgrounds. The 800 ms Flutter splash delay was removed. Version 2.4.8 did not resolve with this Flutter SDK because its `flutter_test` pins `meta` 1.17.0 while 2.4.8 requires `meta` 1.18.0 or newer.
- Sign-in and owner registration show a compact, Arabic RTL guide on first entry. Its actions focus actual form fields and the real submit control. The guide can be skipped and reopened through the Help icon; its step is stored locally and resumes after restart. It never submits credentials or registration itself.
- The opening-ledger guide points to the real refresh control, then explains that entered balances require review and server confirmation. Its state is scoped to user and shop. Help resumes it. The existing pending/failure/reconciliation flow remains responsible for financial confirmation.
- Auth guide spacing was tightened after the first 320×640 render showed the primary login action below the viewport. The final narrow light/dark renders and emulator preview keep the login action visible without removing Arabic labels.

## Visual evidence

- [Widget captures](widget/) contain 12 synthetic Flutter renders: guided sign-in, registration, and opening ledger at 320×640 and 1440×900 in light and dark. They show Arabic RTL, token-based colors and no observed overflow. Registration remains scrollable to its later fields and submit action. These are **widget captures, not device proof**.
- [Android emulator captures](device/) are from Android 16, 1080×2400. `native-splash-light.png` is an actual Android native launch frame. `guide-login-light.png`, `guide-login-dark.png`, and `guide-focus-dark.png` show the clearly labeled fake-auth debug preview, including a tap that focused the actual contact field. `unconfigured-entry-dark.png` shows the production entry when no public Supabase configuration is passed; it is not a dark splash capture or authenticated flow.
- The emulator showed a hardware-keyboard toolbar while the contact field was focused. A full software keyboard frame for this new guide was not established. The earlier auth review has separate native keyboard evidence for the underlying form; it does not prove this guide's keyboard layout. No iOS device or dark native launch frame was reviewed.

## Checks and limits

`dart format` on edited Dart files, `flutter analyze --no-pub`, and full `flutter test --no-pub` passed (135 tests). The debug Android app and fake-auth preview launched successfully. `git diff --check` passed. React and SQL/RLS contracts were untouched, so their gates were not rerun for this UI increment. No release build, deployment, push, production setting change, or remote Auth setting change was made. This run did not establish live email/phone authentication because the debug production entry was launched without public Supabase configuration.

Historical auth and opening-ledger validation files remain intact. The auth capture harness now writes old scenarios only under ignored `app/build/auth-review/`; this increment's evidence is saved separately here.

## Open work, in priority order

1. Build approved first-sale, inventory, and CRM controls, then extend onboarding through those real workflows. Define a safe practice draft versus real financial posting for first sale; do not imply an unimplemented action is usable.
2. Provide a complete Help destination for resuming the cross-feature tour; current Help controls resume the guide on their own screens. Include shop selection in the guided path.
3. Review the new guide with a full on-screen keyboard, screen reader, and physical keyboard on a configured device; validate native dark splash and iOS launch. Obtain an approved all-screen visual baseline under D12.
4. Complete separate live Auth acceptance evidence (email/phone, registration, expiry and revocation) under the [auth/ledger assessment](../../operations/auth-ledger-assessment-2026-09-28.md).

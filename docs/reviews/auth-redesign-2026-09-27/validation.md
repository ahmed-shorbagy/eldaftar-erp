# Flutter authentication redesign review — 2026-09-27

## Result and scope

Grok implemented most of the redesign and its tests. Codex reviewed the diff and rendered evidence, corrected the narrow-phone layout, accessibility, physical back behavior and typography, and independently ran the checks. The user subsequently included the workspace's automatic identifier detection and shared branding edits in this task. These add the ledger mark to Flutter and React, platform splash backgrounds and shell titles; ledger business behavior, backend contracts and remote Auth settings remain unchanged. No release build, push, publication or deployment was performed.

The direction is a restrained Arabic form on the existing cream/brown/dark palette: compact branding, a clear heading, a short introduction, outlined controls with persistent labels, and a full-width primary action. The auth column is capped at 480 logical pixels. Gutters are 16; spacing follows 8/16/24/32; controls are at least 48; corners are 12. All colors use existing ColorScheme roles. The dark gold primary role is derived from the existing seed.

Login detects email or Egyptian phone from one contact field, labels the detected type, and preserves the password while editing the identifier. Registration accepts email and phone in either contact field and rejects duplicate types near the inputs. Standard 320×640 login keeps both the submit and registration actions on screen. At larger text sizes the page scrolls. Registration stays one form with owner/business, contact, and credentials sections, preserving simultaneous six-field validation. The visible back control and Android back return to login without discarding the draft. Governorate loading and failure/retry remain; the redundant happy-path refresh is removed. Branding is a compact 40px mark beside the name/tagline on auth; the large mark belongs to the opening splash, whose delay is skipped for reduced motion.

Fields retain paste, autofill and next/done actions. The combined contact fields use a keyboard that can enter email and phone; content/password is LTR within Arabic RTL layout. Password visibility has Arabic labels. Field labels and detected contact types are exposed to screen readers. Failed submission focuses/reveals the first invalid input. Inline errors update after attempted validation, and server feedback uses a live region. Loading prevents duplicate requests. Reduced motion retains static progress and status text.

Uncertain registration still locks the original normalized payload and idempotency key for retry. Progress or an early session event does not claim success. The existing AuthGate handoff occurs after confirmed registration/session, including pending shop activation; its regression tests remain intact.

## References and design reasoning

Research used official product descriptions and platform guidance, rather than claims of access to signed-in product screens. These are interaction references; the repository theme remains authoritative.

- [Revolut login](https://www.revolut.com/blog/post/revolut-login/): make the identifier and credential task explicit and easy to find. Applied as one detected identifier field, password and one primary action.
- [Revolut account opening](https://www.revolut.com/blog/post/how-to-open-revolut-account/): group account setup into intelligible tasks. Applied as three registration sections; no OTP or identity-verification flow was copied.
- [N26 login guidance](https://support.n26.com/en-it/security/passwords-codes/how-to-log-in-with-two-factor-authentication): retain a familiar email/password sequence and an explicit progress state. Its additional authentication methods are outside this app's behavior.
- [Wise account setup](https://wise.com/help/articles/2897226/what-is-a-wise-account): distinguish contact credentials from account/business details. Applied to grouping and a clear return to existing-account login; no new account types were added.
- [Apple text fields](https://developer.apple.com/design/human-interface-guidelines/text-fields) and [password autofill](https://support.apple.com/en-mide/guide/iphone/iphf9219d8c9/ios): visible field purpose and password-manager support. Applied through persistent labels, AutofillGroup and login/new-password hints.

The ui-ux-pro-max searches used `form validation focus keyboard --domain ux`, `inline validation error clarity --domain ux`, `Arabic typography readable form --domain typography`, and `form autofill keyboard accessibility --stack flutter`. They informed focus, error placement, Semantics and Arabic type selection. Their palette suggestions did not replace the design contract.

## Typography and license

Auth alone bundles [Noto Sans Arabic from Google Fonts](https://github.com/google/fonts/tree/main/ofl/notosansarabic), with its SIL Open Font License in `app/assets/fonts/OFL.txt`. This fixes the difference between the initial Windows Tahoma captures and Android's platform face. The font is an offline asset, with no runtime font download or package dependency. Other workflows and React retain their typography. The shared design guide documents this scoped choice. The included brand mark uses a synchronized `brandGold` token confined to its ingot illustration; form and status colors retain the original semantic palette.

Font SHA-256: `63111b5b2e074dd48cc67692e0a2726d86ee94c1c37fe8598257b7b4e87e869e`.

## Rendered evidence

[Before captures](before/) contain 32 original frames: login email/phone and registration top/lower, light/dark at 320×640, 390×844, 430×932 and 1440×900. The original 320/1440 files were preserved; 390/430 were captured before implementation. Concrete problems were long introductory/disclaimer text, two large radio rows, tiny floating labels and underlines, an ungrouped registration form, unconditional refresh, and missing password visibility/autofill. Registration required scrolling to the action.

[After captures](after/) contain 120 final synthetic widget-rendered frames at those same sizes and both themes: email/phone login, registration top/lower, registration submitting/uncertain retry, keyboard inset field/action, long login errors, 2× text, login pending, governorate loading, empty registration validation and confirmed account/pending shop activation. Auth captures load the actual bundled font; the existing post-auth pending screen uses Windows Tahoma in this harness, matching the ledger capture convention. Focus settles before top captures. These are real Flutter widget renders at pixel ratio 1, **not device proof**. Review included a contact-sheet sweep of the matrix and full-size inspection of narrow, dark, keyboard, large-text, error and pending states. No horizontal overflow or clipped non-scrollable action was accepted.

[Intermediate method-switch evidence](intermediate-method-switch/) preserves the earlier 112 widget frames, six native frames and their validation note before the user included automatic detection/branding. [React evidence](react/) contains login and shell renders at 320 and 1440 in light/dark from a temporary local fake-gateway fixture, which was removed after review. [Flutter shell evidence](brand-shell/) verifies the included title mark at 320 and 1440 in both themes; financial behavior was not edited.

[Device evidence](device/) is separate:

- `auth-*.png`: five intermediate Grok app-surface frames from the initial Android integration pass, before the final typography corrections. Retained as intermediate evidence, not the final appearance.
- `native-login-light.png`, `native-login-dark.png`, `native-registration-light.png`, `native-registration-dark.png`: final normal-debug-preview screenshots, including OS chrome.
- `native-keyboard-light.png`, `native-keyboard-dark.png`: final full-device screenshots with Gboard open and the password field and login action reachable above it.

Native review used one Android 16 emulator, 1080×2400 at density 420 (about 411 logical pixels wide). `tool/auth_preview.dart` is a separate fake-gateway entry point, visibly labeled in Arabic as a demo; production main never imports it. Actual taps, scrolling, theme switching and physical back were exercised. The emulator's hardware-keyboard toolbar initially suppressed an inset keyboard. Its secure keyboard setting was temporarily enabled and restored to `0`; Gboard's “Show on-screen keyboard” action exposed the full IME for final captures. The test harness itself did not establish native-keyboard proof, so that check moved to a normal debug run.

An earlier normal preview reported a foundation exception ending in `_StretchController`; its full assertion was truncated. Grok's follow-up native reproduction did not recover that assertion and stopped when its usage balance was exhausted. The final auth scroll configuration disables only the animated edge effect, retaining platform scrolling/scrollbars. Codex completed an Android fling/back/draft/disposal regression and repeated native keyboard/theme/edge-scroll/back navigation, then quit the preview without the exception. This is a defensive mitigation and successful final check, not a claim that the original assertion's exact root cause was established.

All captured identifiers/names/passwords are synthetic. No source requirements, real customer details, credential configuration or user data are included.

## Validation

- Scoped `dart format`: passed, final check reports no changes.
- `flutter analyze --no-pub`: no issues after replacing the deprecated test API.
- `flutter test --no-pub`: **125 passed**, including **25 auth interaction tests** and the expanded capture matrix. Original auth/idempotency/session assertions remain; added tests cover detected identifiers, swapped registration contacts, field semantics, physical back/edge scrolling, splash handoff and initial 320px action reachability.
- Initial Grok gates: 117 Flutter tests and analyzer passed before Codex's review corrections. Its Android fake-gateway integration run passed on the intermediate implementation. Flutter recovered from insufficient emulator storage by reinstalling that debug package.
- Final Android `flutter test integration_test/auth_review_test.dart -d emulator-5554 --no-pub`: passed against the automatic identifier UI. It uses fake gateways; normal preview screenshots supply the separate native keyboard proof. Flutter again recovered from insufficient emulator storage by reinstalling the same debug package.
- React `npm run lint`: passed; `npm run test`: **34 passed across 8 files**; `npx tsc -b`: passed for the included branding/token changes.
- `git diff --check`: passed. Documentation links, theme consistency, font license and synthetic-data/privacy scope reviewed.
- SQL/RLS/atomicity gates were not relevant: no backend, policy, data adapter, financial or authorization behavior changed. Domain/gateway tests ran in the Flutter suite. No production build was run.

## Limits

The exact 320/390/430/1440 matrix and 2× text/reduced-motion/state cases are widget evidence. Native evidence is one Android emulator; no physical phone, iOS or Windows native runtime matrix was tested. Native launch art was not visually verified on every platform/Android version. Screen-reader field semantics were exercised in tests, but TalkBack/VoiceOver narration and a real password-manager fill/paste were not manually verified. The OS and keyboard chrome follow the emulator's English locale; app-owned auth copy is Arabic. Confirmed registration was tested with fake gateways; no live shop or account was created.

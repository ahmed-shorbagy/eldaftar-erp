# Native debt reminders — final independent validation

Milestone 4 slice 9; final continuation on 2026-10-16, Africa/Cairo. This continues the preserved [2026-10-15 independent record](independent-validation.md), [owner-confirmed ADR 0020](../../adr/0020-native-debt-reminders.md), and [separate implementation review](implementation-review.md). The validator edited no application/backend source or tracked tests, mutated no hosted data, scheduled no OS notification, and ran no release/production build, commit or push.

## Final client gates

| Gate | Exact command and result |
| --- | --- |
| Scoped Dart formatting | From repository root, derive the union of `git diff --name-only -- '*.dart'` and `git ls-files --others --exclude-standard -- '*.dart'`; run `dart format --output=none --set-exit-if-changed` on those paths. Exit 0: 23 files, zero changed. Evidence: `tmp/debt-native/independent-final-format.log`. |
| Flutter analysis | From `app/`, `flutter analyze --no-pub`: exit 0, no issues, 39.8 seconds. Evidence: `tmp/debt-native/independent-final-analyze.log`. |
| Complete Flutter suite | From `app/`, `flutter test --no-pub --reporter expanded`: exit 0, 1,405 passed, 1 minute 57 seconds. Includes domain/application/HTTP/locker/widget/native-facade coverage, four Grok lifecycle regressions, and final native RTL captures. Evidence: `tmp/debt-native/independent-final-flutter-tests.log`. |
| Capture integrity | `python tmp/debt-native/independent-capture-integrity.py`: exit 0; all 168 expected PNGs decode, no missing/unexpected/blank images. Fourteen states × light/dark × 320/390/1440 × text scales 1.0/1.7; each height 1000. Exact hash/dimension manifest: `tmp/debt-native/independent-capture-integrity.json`. |

The first final analysis exposed an unsupported `WidgetTester.ensureVisible` argument in the capture helper. The implementer changed it to `Scrollable.ensureVisible`, formatted the file, and passed a targeted capture rerun before the final independent analysis/full suite above. Initial read-only formatting also identified the newly added capture assertion's formatting; the implementer corrected it. These corrections affect verification code, with no backend or financial effect.

The earlier independent React gates remain valid without source changes: `npm run lint`, `npm test`, and `npx tsc -b` exited 0; 38 tests in nine files. The final migration remains raw SHA-256 `4eb1e4f27acc3b8e473425f1a60af433b986b3dcf5213cdce98302fc18650e1d`. The preserved record contains the final independent fresh-apply/rollback-fingerprint/reapply, native SQL/RLS/atomicity/privacy/idempotency, all-five-RPC real-role authorization, source-race and forced snapshot checks. Passed unchanged SQL/React gates were not repeated.

## Arabic RTL visual review

The validator read `docs/design-system.md` and ui-ux-pro-max accessibility/layout guidance and inspected actual PNGs, including final pending 320 at 1.7 scale in both themes; unsupported 320 light, 390 light/dark and 1440 dark; pending 390 light/1440 dark; confirmed 1440 light; review 320 light; permission 390 dark; and keyboard 320 dark. The preserved earlier record covers additional representative review/permission/unsupported/pending views across all widths and both themes.

The pending confirmation banner and original-request retry are now fully visible below the app bar at 320/1.7 in both themes. The final capture tests assert the banner starts below the app bar. Unsupported setup hides enable and system-settings actions while retaining truthful reconciliation. The review/confirmed synthetic appointment correctly shows Cairo 17:00 as UTC 14:00. Cairo, Arabic RTL, digit isolation, wrapping, semantic brown/cream/dark colors and visible gold keyboard focus remain readable. All captured outlined controls satisfy the 48-pixel minimum assertions. No hard-coded component color literals were found in the two new native reminder presentation files.

## Grok contribution audit

The owner explicitly requested grok-delegate during continuation. Independent parsing of `tmp/debt-native/grok-lifecycle/events.jsonl` finds exactly one edit call: creation of `app/test/debt_native_lifecycle_regression_test.dart`. Three execution calls contain only scoped formatting/testing (including a corrected working-directory retry) and read-only Git status/diff. The relay's whole-working-tree dirty-file list is not an edit list. No hosted action, commit, push, deployment or notification command appears.

The four cases meaningfully cover cold restart taps after fired requests leave pending, discarding an in-flight tap source read after account/token change, a durable pre-registration write failure with safe retry, and retrying failed cancellation on restart without enable/metadata writes. Codex separately reviewed and reran these four; the independent complete suite above includes them.

## Evidence limits and final documentation

The client/SQL validation has no remaining blocking finding in the reviewed bounded scope. OS registration, synthetic adapters and debug compilation do not establish actual notification delivery. Android/iOS/Windows physical-device permission/settings, process death/reboot/force-stop, sound/Focus/Do Not Disturb, Arabic OS surfaces and authenticated cold/warm tap acceptance remain open as detailed in the [platform matrix](platform-capabilities.md). iOS compilation is unavailable on this Windows host. No actual device notification QA was performed or implied.

The parent implementer applied the reviewed additive migration after review and independent validation. The final independent documentation and preservation audit below verifies the retained aggregate evidence; the validator performed no hosted mutation.

## Final documentation and preservation audit

The independent validator compared all 1,439 files in the pre-task baseline manifest with the current workspace: zero missing; 22 existing files changed, comprising 16 necessary application/native/dependency integrations and six current documentation/pointer files. Every other baseline file remains byte-identical, including old migrations, prior slice reviews and immutable requirement/planning archives. The exact submitted slice 9 archive SHA-256 equals the original next-slice pointer's baseline SHA-256. The pointer changed only after preserving that archive. This checks preservation against the captured working tree, including its pre-existing work, rather than assuming HEAD was the starting state.

Final local-link checking covered 13 current/ADR/review/completion/pointer documents and 323 local links: zero missing. Consistency review confirms accepted D19/D33, bounded scope, implemented/development status and open platform/owner acceptance agree across the ADR, matrix, delivery plan, scope, decisions, design guide, completion, pointer and deployment record. Credential/JWT/secret/email pattern scanning found no matches in these documents; manual review found only synthetic fixture descriptions, aggregate counts/hashes and public technical identifiers, with no raw customer/contact records or credentials. `git diff --check` exited 0; Git's generated-CMake CRLF warning is informational.

The retained `tmp/debt-native/hosted-preservation-final.json` independently compares equal across all 52 protected pre-existing table count/full-row SHA-256 pairs, with the permitted sync signal excluded. Every one of the 52 table rows printed in [deployment](deployment.md) matches that JSON exactly. The old public/private function-definition/grant fingerprint is equal before/after, and all 38 prior migration mappings remain equal. The sole added hosted migration is `20261016090329` / `debt_native_reminders`; independently computed raw local SHA-256 remains `4eb1e4f27acc3b8e473425f1a60af433b986b3dcf5213cdce98302fc18650e1d`, and CR-normalized/trimmed UTF-8 SHA-256 equals hosted `81570fa8c42bc358fc418fcfd8e9122ce1e84b668171ac7d3575f91bbc91a9fd`. This agrees with the final exact preflight and deployment record.

The hosted rollback-gate result is recorded passed; retained fixture user/session/shop/membership/entitlement/fault-trigger counts and all three native table counts are zero. No retirement deletion was needed after the explicit rollback. The final fresh preservation pair retains legitimate activity since the earlier 2026-10-15 read-only baseline, including 51 financial operations and 295 postings; it does not falsely claim yesterday's 43/234 totals remained fixed. Advisory deltas are accurately retained as five new authenticated SECURITY DEFINER notices and one new unused-index notice, alongside unchanged existing findings. No reset, history rewrite or source/financial mutation was used to restore yesterday's totals.

No blocking implementation or validation finding remains in the reviewed bounded local-notification scope. This record and the [completion record](../../operations/debt-native-reminders-completion-status-2026-10-16.md) leave actual Android/iOS/Windows device and owner acceptance open.

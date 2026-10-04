# Daily-note local persistence integrity — 2026-10-04

Only this bounded persistence-integrity subtask is complete. LED-05 and milestones 0–3 remain open. The [hosted SQL/Storage evidence](daily-notes-pagination-validation.md) and [restart restoration evidence](milestones-0-3-progress-2026-10-04.md#bounded-daily-note-restart-restoration--complete) remain the baseline. No backend change or hosted operation was needed.

## Independent audit and reproduced defects

The actual `SecureNoteDraftStore`, `ApplicationNoteImageFileStore`, `DailyNoteSubmission` and screen persistence/restoration/confirmation call sites were read before repairs. Tests use those adapters, Flutter secure-storage's mock platform, temporary filesystem directories, paused storage calls and injected partial encrypted-file writes. Synthetic owner IDs, UUIDs, note text and byte lists only are used.

| Exercise | Before repair | Minimal repair and regression result |
| --- | --- | --- |
| Old clear paused at secure-storage deletion while another adapter saves a newer key | Newer draft was erased; read returned null | Owner/shop-scoped queue holds the whole conditional clear, save and read across adapter instances. Both clear/save and save/read/clear interleavings preserve the newer key |
| Strict draft envelope | An extra unknown sixth field was accepted; attachment size validation was absent | Exact allowed fields; canonical IDs, text and attachment metadata checked on read and save. Size must be a canonical decimal string in 1..5242880; invalid metadata fails closed |
| Partial encrypted replacement writes 12 bytes then throws | Previously decryptable image was truncated and read failed | Flush encrypted bytes to a sibling `.pending` file, then rename to the live filename. On failure the previous live image remains decryptable; cleanup removes the failed staging file |
| Delayed completed status after a newer draft reuses the same attachment object | Old cleanup deleted the newer draft's image | Application-owned optional cleanup contract lets the real secure adapter hold its draft queue during conditional image cleanup and envelope removal. Both submission and restoration use the shared helper; a different newer key retaining that object keeps its image |
| First image write fails during submission with an older recoverable draft present | Submission had already replaced the older envelope with a reference to the unavailable image | Submission and screen picking write image bytes before publishing the envelope. Failed image persistence retains the old envelope and returns local failure without upload/post |

The first isolated run had **1 pass / 2 failures** (clear race and permissive envelope). After adding the injected partial-write seam, **1 pass / 3 failures** included replacement corruption. Adding delayed completed cleanup produced **1 pass / 4 failures**. After those repairs, the first-image failure regression independently failed (**7 passes / 1 failure**) with the old draft replaced; it passed after persistence ordering was repaired. The original assertions remain in the final suite.

## Protections verified without redesign

- Existing screen `_runAction` locks synchronously before asynchronous status checks; restoration blocks editing and submission until the read/status result is resolved. Existing generation guards discard delayed owner/shop/day responses. The full suite retains the original 16 restart regressions and eight notes widget tests; call-site guards were not replaced with a new submission workflow.
- The existing shared pending-key future already serializes key initialization across image-store instances. A paused actual secure-storage key write and two object writes produce one 32-byte key and both images decrypt. No key-management redesign was made.
- AES-256-GCM still uses a fresh 12-byte nonce, 16-byte tag and owner/shop/object AAD. Existing tamper, missing/corrupt-key, size-limit, traversal and fresh-nonce tests remain. New ciphertext-copy tests deliberately share the key across foreign owner/shop/object scopes to prove that AAD rejects the copied ciphertext, rather than relying only on different encryption keys. Deleting those foreign copies leaves the original image readable.
- Draft reads reject copied owner envelopes. Missing foreign owner/shop slots return null. Signed-URL/session/credential rejection remains in the adapter and its existing regressions; persisted envelopes contain only request identifiers, text and canonical attachment metadata. Local encrypted files contain magic, nonce, tag and ciphertext, never the key or session credentials.
- Image read/write/delete across instances share a file-scoped queue, preventing competing operations from consuming partial staging bytes or colliding on the staging filename. A paused replacement followed by read/delete/new write returns complete replacement bytes and leaves the final newer image decryptable.
- An injected secure-storage write failure before mutation preserves the prior canonical request. Unknown-status submission retains the original owner, shop, day, key, payload and attachment bytes and performs no upload/post. Completed reconciliation with secure-storage cleanup failure stays confirmed on two attempts and performs zero posts/uploads. Existing lost-response, retry, closure and server-confirmation coverage remains intact.

The application/domain boundary has no Flutter, secure-storage or filesystem imports added. The queue is a data-layer helper. No UI layout, theme, visible copy, controls or accessibility behavior changed; the screen edits are persistence call ordering and cleanup routing only. No new visual acceptance claim is made.

## Exact validation commands and results

Commands ran from `D:\Eldaftar ERP` unless a different working directory is given. All final required checks exited 0.

```powershell
# Scoped formatter check, repository root
C:/flutter/bin/cache/dart-sdk/bin/dart.exe format --output=none --set-exit-if-changed app/lib/src/features/daily_notes/application/note_draft_store.dart app/lib/src/features/daily_notes/application/daily_note_submission.dart app/lib/src/features/daily_notes/data/secure_note_draft_store.dart app/lib/src/features/daily_notes/data/note_image_file_store.dart app/lib/src/features/daily_notes/data/note_persistence_queue.dart app/lib/src/features/daily_notes/presentation/daily_notes_screen.dart app/test/daily_note_persistence_integrity_test.dart
# 7 files; zero changes; 0.04 seconds

# Working directory: D:\Eldaftar ERP\app
flutter test test/daily_note_persistence_integrity_test.dart --reporter expanded
# Initial failing reproductions as recorded above
flutter test test/daily_note_persistence_integrity_test.dart test/daily_note_storage_test.dart test/daily_note_submission_test.dart test/daily_notes_restore_test.dart test/daily_notes_widget_test.dart --reporter expanded
# First repaired scope: all 38 passed (before the later initial-write/extra regressions)
flutter test test/daily_note_persistence_integrity_test.dart test/daily_note_submission_test.dart --reporter expanded
# All 17 passed (before adding the two final unknown/completed regressions)
flutter analyze
# Final: no issues; 4.4 seconds
flutter test --reporter expanded
# All 388 passed; final reporter time 47 seconds; 13 new integrity tests

# Working directory: D:\Eldaftar ERP\admin
npm run lint
# Passed
npm test -- --run
# 35 tests / 9 files passed; 9.39 seconds
npx tsc -b
# Passed; no diagnostics

# Repository root
git diff --check
# Passed; existing LF/CRLF informational warnings only
```

Initial sandboxed `dart format app/lib/src/features/daily_notes app/test/daily_note_persistence_integrity_test.dart` and `flutter analyze` launchers stalled without output and were interrupted. The direct SDK formatter completed; its initial sandboxed check printed zero changes but reported a denied telemetry-cache modification. Final scoped formatting and analysis used permitted SDK/cache access and completed cleanly. The first completed analysis found one `unnecessary_underscores` style diagnostic in the new queue; that was corrected before the clean final analysis. No behavior was changed by that style fix; the full 388-test run includes all functional repairs and final regressions.

Final `git -c core.safecrlf=false diff --check` also passed with exit 0 and no output. The explicit check below passed for all 12 scoped files:

```powershell
@'
from pathlib import Path
import re
files=[Path('app/lib/src/features/daily_notes')/p for p in ['application/note_draft_store.dart','application/daily_note_submission.dart','data/secure_note_draft_store.dart','data/note_image_file_store.dart','data/note_persistence_queue.dart','presentation/daily_notes_screen.dart']]
files += [Path('app/test/daily_note_persistence_integrity_test.dart')]
files += [Path('docs/operations')/p for p in ['daily-notes-persistence-validation-2026-10-04.md','daily-notes-persistence-next-task.md','daily-notes-pagination-validation.md','milestones-0-3-progress-2026-10-04.md']]
files += [Path('docs/requirements-matrix.md')]
for p in files:
    text=p.read_text(encoding='utf-8')
    assert text.endswith('\n') and not text.endswith('\n\n'), f'EOF: {p}'
    assert all(line == line.rstrip() for line in text.splitlines()), f'whitespace: {p}'
    if p.suffix=='.md':
        for link in re.findall(r'\]\(([^)]+)\)',text):
            if '://' in link or link.startswith('#'): continue
            target=link.split('#')[0]
            assert (p.parent/target).exists(), f'link: {p}: {link}'
print(f'PASS: scoped whitespace (including untracked files), EOF and documentation file links: {len(files)} files')
'@ | python
```

Final whitespace checks also explicitly include the scoped untracked Dart/documentation files because `git diff --check` does not cover them. Documentation links, current-state consistency and privacy were reviewed. Historical records were appended to, not erased. Existing unrelated checkout work remains intact.

## Changed files and boundaries

Implementation: `app/lib/src/features/daily_notes/application/note_draft_store.dart`, `application/daily_note_submission.dart`, `data/secure_note_draft_store.dart`, `data/note_image_file_store.dart`, new `data/note_persistence_queue.dart`, and `presentation/daily_notes_screen.dart`. Regression file: new `app/test/daily_note_persistence_integrity_test.dart`.

Current records: this file, `daily-notes-persistence-next-task.md`, `daily-notes-pagination-validation.md`, `milestones-0-3-progress-2026-10-04.md` and `docs/requirements-matrix.md`.

No Supabase schema/RPC/RLS/Storage policy changed, so SQL/RLS/atomicity gates were not rerun. Existing scoped development approval remains unused for this local task. No inventory, corrections, payment settings, financial pending-store, general orphan cleanup or key-management integration was performed. No commit, push, deployment, release build or React production build ran.

## Remaining acceptance limits

The queues coordinate instances in the current Dart isolate; they do not establish cross-process or multi-isolate mutual exclusion. These tests use mocked secure storage and temporary Windows host files. They do not establish Android/iOS/Windows native secure-storage durability or platform failure semantics, OS power-loss durability, a real process kill/restart, native file picking, device-to-hosted acceptance or signed-URL expiry. A native secure-storage write that commits and then throws is not simulated as an OS durability guarantee. The encrypted-file partial-write injection is a deterministic interruption model, not device acceptance.

Native-device/app-to-hosted acceptance and actual signed-URL expiry remain separate exercises with their existing fixture/cleanup requirements. LED-05 and every milestone remain open. There is no outstanding required routine gate for this bounded adapter-integrity subtask.

# Next bounded task — daily-note persistence integrity

Selected on 2026-10-04 after independent hosted daily-notes validation. This is a proposed next task, not work already executed. Secure local draft/image integrity should be reviewed before attempting native device and app-to-hosted acceptance. Backend validation and restart reconciliation evidence are already complete for their recorded scope; LED-05 and milestones remain open.

## Ready-to-use prompt

```text
Finish one bounded task in D:\Eldaftar ERP: independently review and repair daily-note local persistence integrity.

Read AGENTS.md, docs/operations/milestones-0-3-progress-2026-10-04.md, docs/operations/daily-notes-pagination-validation.md, and docs/operations/daily-notes-persistence-next-task.md first. If any UI changes are necessary, also read docs/design-system.md before editing.

Scope:
- app/lib/src/features/daily_notes/application/note_draft_store.dart
- app/lib/src/features/daily_notes/data/secure_note_draft_store.dart
- app/lib/src/features/daily_notes/data/note_image_file_store.dart
- Their notes submission/restoration call sites and meaningful regression tests
- Current progress, validation and LED-05 evidence documentation

Treat the completed hosted SQL/Storage validation and restart-reconciliation work as the baseline. Do not repeat or redesign those slices without a demonstrated defect.

Audit the real persistence adapters and their call sites before editing. Verify owner/shop/object isolation, strict persisted-envelope validation, canonical attachment metadata, AES-256-GCM key/nonce/AAD handling, and exclusion of session credentials and signed URLs. Verify failures preserve recoverable drafts and attachments without reporting an unconfirmed operation as saved.

Exercise interrupted or failed image writes and replacement, overlapping draft save/read/clear, concurrent key initialization across store instances, and delayed cleanup after a newer draft has been saved. An old idempotency key must never clear a newer draft or delete another owner's/shop's image. Prove whether existing call-site serialization already prevents each race before adding synchronization. Do not infer a defect merely from inspection.

Preserve the original owner, shop, day, idempotency key and canonical request while status is unknown. Confirm completed reconciliation never reposts, and local cleanup failure cannot turn confirmed success into a duplicate operation. Keep Flutter domain rules independent of storage and widgets.

Make only minimal repairs for reproduced failures and add regressions using the actual adapters where practical, including temporary directories and injected storage failures. Preserve existing tests, unrelated work and historical records. Do not broaden into financial pending stores, inventory, corrections, payment settings, orphan cleanup or key-management redesign.

Run scoped formatting, Flutter analysis and the full Flutter suite, React lint/tests and npx tsc -b, plus relevant SQL/RLS/atomicity gates only if backend behavior changes. For UI changes, review Arabic RTL in both themes at mobile/desktop widths using the existing tokens. No UI change means no new visual acceptance claim.

Existing Supabase approval remains available for scoped synthetic development validation on xchapwvmvoefriqcxtvn; do not request it again. Prefer local reproductions for this task. If hosted validation is necessary, review the target-guarded fixture and cleanup package first, preserve real data, use rollback-only SQL where possible, record counts and clean synthetic objects through the APIs. Never apply local Auth/Storage bootstraps or weaken their guards.

Update records with exact commands, results, changed files and limitations. Mark only this persistence-integrity subtask complete if its checks pass. Keep LED-05 and milestones open; mocked storage, temporary-file tests and captures do not prove Android/iOS/Windows secure storage, native file picking, actual process restart, app-to-hosted acceptance or signed-URL expiry.

Do not commit, push, deploy applications, run release/production builds or integrate corrections/payment settings. Report any remaining blockers precisely.
```

## Follow-on work

After this task, prepare a separate synthetic native-device/app-to-hosted acceptance exercise and actual signed-URL expiry evidence. Device availability and cleanup of committed append-only note/audit records must be resolved before that exercise; do not quietly repurpose real shop data or assume the rollback-only backend harness establishes client/device acceptance.

## Execution result — persistence integrity complete

Only this persistence-integrity subtask is complete. Five demonstrated defect categories were repaired in the local adapters and persistence/cleanup call sites, with 13 new actual-adapter regressions. Final scoped formatting and Flutter analysis passed; all 388 Flutter tests, React lint, all 35 React tests in nine files and `npx tsc -b` passed. No backend behavior changed or Supabase operation ran. [Exact commands, reproduction evidence, repairs and limitations](daily-notes-persistence-validation-2026-10-04.md).

Earlier proposed-task and approval checkpoints above are historical. LED-05 and milestones 0–3 remain open; native secure storage, native picking/restart, device-to-hosted acceptance and signed-URL expiry remain unverified. No commit, push, deployment, release/production build or unrelated slice integration ran.

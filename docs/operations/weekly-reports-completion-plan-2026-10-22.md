# Next-work plan — 2026-10-22

Completion follow-up: this plan is now a historical preparation snapshot. The [weekly validation](../reviews/weekly-reports-2026-10-22/validation.md), [deployment](../reviews/weekly-reports-2026-10-22/deployment.md) and [follow-up examination](../reviews/weekly-reports-2026-10-22/follow-up-review.md) supersede its pending-work statements. The next feature recommendation is [ADM-01 subscriber directory](admin-subscribers-plan-2026-10-22.md); the original plan below remains preserved.

This is a documentation-only recommendation requested by the owner. It prepares the next task; it does not run previously deferred verification, deploy anything or select a new feature. The October 21 implementation and validation records remain historical evidence.

## Evidence baseline

The working tree was clean at `7c0ae7a` when this review began. That commit contains the weekly implementation; the earlier daily implementation is at `7f73458`. Source being committed does not establish verification or deployment.

| Scope | Recorded state | Remaining work |
| --- | --- | --- |
| Selected financial-day Reports | Implemented, locally verified and applied to development. [Validation](../reviews/reports-2026-10-21/validation.md), [deployment](../reviews/reports-2026-10-21/deployment.md). | Regression checks for the later shared-code changes; native save/share, actual app-to-R2 round trip and owner acceptance. |
| Weekly Reports | Implemented locally under [ADR 0026](../adr/0026-weekly-financial-reports.md). [Implementation/deferred gates](../reviews/weekly-reports-2026-10-21/implementation.md). | Automated and SQL checks, Arabic UI/PDF review, development reconciliation/application and hosted verification. No weekly deployment record exists in the reviewed repository. |
| Milestone 4 | Bounded implementations with separate local/hosted evidence. [Acceptance checklist](../reviews/stabilization-2026-10-21/acceptance.md). | Native/device/owner acceptance, including invoice output and temporary staff counts. Milestone 4 remains open. |
| Wider Milestone 5 | Daily and weekly are the selected Reports scope. | Admin management, wider reporting periods and subscription/retention extensions remain planned; no new scope is selected here. |

The pending migration recorded by the weekly implementation is `supabase/migrations/20261021133552_financial_week_reports.sql`. Hosted state has not been inspected in this planning task; reconcile it afresh before applying anything. Earlier daily test counts and deployment hashes are evidence for their recorded revision only.

## Recommended sequence

1. **Complete weekly Reports and protect daily Reports.** Review the existing implementation, add meaningful missing weekly tests, repair defects within ADRs 0025/0026, and run the scoped client and fresh SQL/RLS gates. Keep server-authoritative dates, complete detail sets, exact integers, owner-only access and zero financial effects. Exercise the shared renderer, transaction details and R2 helper against both daily and weekly reports.
2. **Review Arabic screens and PDFs.** Inspect 320/390/1440 widths in light/dark and ordinary/enlarged text; render and inspect every page of representative empty, long and multi-day PDFs. Record actual results separately from unavailable native checks.
3. **Finish authorized development delivery.** Once relevant checks pass, reconcile migration history and installed definitions on `xchapwvmvoefriqcxtvn`, capture preservation baselines, apply only this task's missing reviewed changes, run rollback-only hosted fixtures and compare preservation evidence. Reuse `report_pdf`; the current weekly design needs no Edge Function change. If already applied, verify matching definitions/history instead of replaying it.
4. **Keep native acceptance visible.** Record device/owner gaps for Reports and Milestone 4. The existing DOC-04 native invoice-output harness is the next recommended implementation task after weekly completion, with Android/Windows execution and an explicit iOS checklist where hardware is unavailable. It remains a separate task to select. Wider admin/report features need their own bounded scope and unresolved product decisions.

## Handoff and completion criteria

Use the [ready-to-paste completion prompt](weekly-reports-completion-prompt-2026-10-22.md). It executes the previously deferred work when submitted as the next task; this plan itself leaves those checks deferred.

The follow-up should produce a dated weekly validation record, a development deployment/preservation record, reviewed synthetic UI/PDF evidence and updated current pointers. A missing tool or native environment must be reported precisely, with unaffected work completed. Local implementation, local verification, hosted verification and owner/device acceptance must remain separate statuses. No broader milestone is closed by these records.

This planning change requires documentation link, consistency and privacy review plus `git diff --check`. Application tests, builds and hosted operations are outside this documentation task.

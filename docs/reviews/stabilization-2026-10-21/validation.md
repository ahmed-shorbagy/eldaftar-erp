# October 21 stabilization and Milestone 4 status

Date: 2026-10-21, Africa/Cairo. Starting point: clean working tree at `f46e83d`. The numeric-field, count-row, denomination-picker, notes and invoice appearance/output work described as unfinished was already committed in the recent history. All baseline work was preserved; this task leaves its fixes uncommitted.

The project rules, shared design contract, delivery plan, requirements matrix, decisions, meeting audit and latest validation/deployment records were reviewed. Historical records are unchanged. Current pointers now distinguish implementation, local verification, development-hosted verification and device/owner acceptance. **Milestone 4 is not fully accepted.**

## Reviewed fixes

| Defect / trigger | Correction and regression evidence |
| --- | --- |
| Localized digits/decimal separators reached strict ASCII parsers in owner/staff count and denomination controls. | Canonicalize entry without floating point; shared gram/count fields have precision-aware default formatters. Tests preserve exact `١٫٥٠٠` as 1,500mg, localized counts and denomination totals, reject excess entry precision, and retain historical milligrams. New trade entry remains two-decimal; closing/invoice storage remains three-decimal. |
| Duplicate owner count types reached generic mismatch handling; removing an earlier row could transfer dropdown state after index-based keys. | Reject duplicate category/karat/type rows and inconsistent measured count/weight pairs before review. Stable row identities retain the remaining name/count when another row is removed. Missing optional stock weight remains null. |
| A camera/gallery failure could freeze an otherwise editable local note and imply an uncertain server save. | Picker errors now retain the editable draft and show a specific Arabic unsaved-image error. Save failures retain the original frozen command/recovery behavior. Camera failure/change/retry tests cover this boundary. |
| Native sharing could treat an unavailable result as a completed handoff, and a later cancellation cleared prior handoff feedback. | Only a successful native result enables a new handoff; cancellation/unavailability never confirms dispatch. A later cancel keeps the earlier handoff and explains that owner attestation applies to the earlier copy. PNG no longer falls through a PDF-only sharing adapter when image sharing is unimplemented. The separate PDF action remains. |
| Quantity steppers lacked clear Arabic accessibility names. | Native semantic icon buttons expose increase/decrease labels with the existing token colors and 48-pixel targets. |
| Enlarged summary actions overflowed; cash-transfer validation could fall outside the lazily built visible form. | Constrain the summary action inside its row; keep mutation/validation feedback beside the cash-transfer submit control in a live region. Existing exact-cash and validation regressions cover both. |
| The staff scrap label clipped on narrow/enlarged screens. | Show karat above a short gram field label, with an explicit required helper; local count tests and the complete capture matrix cover the result. |
| October 21 left an unused midnight-blocking flag/import and obsolete pagination-test taps. | Remove dead code without changing server-driven refresh. Center partially visible pagination/detail targets in tests while retaining exact date/cursor assertions. |
| Captured PostgreSQL startup could stall on Windows; some SQL assertions assumed a different feed/Storage representation. | Isolate `pg_ctl` output and wait for that process only. Expand the existing safe local gate to date feeds, R2 notes, pricing, trade/dispatch and edit/delete checks. Accept null/absent missing-party fields and zero-row RLS denial, while still failing any leaked party value or modified media row. |

The requested `grok-delegate` skill was used through its installed relay with the workspace-only profile. Grok produced implementation and tests but stopped with `402 Payment Required: Grok Build usage balance exhausted`; its run is not represented as successful validation. Codex reviewed the actual diff, corrected the share-state regression and row-key/semantic details, completed the additional fixes and independently reran gates. No paid resource or account top-up was requested. Raw relay artifacts stay in private temporary storage.

## Verification

| Gate | Fresh result |
| --- | --- |
| Scoped Dart formatting | Passed for changed Dart source/tests; final verification reports zero changes. |
| Flutter static analysis | `flutter analyze --no-pub` was attempted and hit the previously recorded SDK launcher error: the AOT analysis-server snapshot is invoked with the wrong runtime. Direct bundled `dart analyze` passed with no issues. No SDK/global configuration was changed. |
| Complete Flutter suite | **1,561 passed, zero failures.** Fresh PDF samples were directed to ignored build output to preserve prior review artifacts. |
| Focused final behavior | 32 cash-transfer, enlarged-cash, historical-date, sharing and trade/close regressions passed. A separate 12-test final share/numeric/midnight/owner-close group passed. Staff-label/delegation and capture checks were rerun after visual review. |
| React | `npm run lint`, `npm test -- --maxWorkers=1` and `npx tsc -b` passed: 9 test files / 38 tests. React source/themes were unchanged. No production build ran. |
| Edge Functions | `r2-media`: 21 handler/signing tests passed. `closing-staff-create`: 6 handler/retry-verifier tests passed. Deno formatting and entrypoint checks passed using the installed cached Deno executable. These are isolated adapters, not live Auth/R2/native tests. |
| Fresh local SQL | The expanded [local runner](../../../supabase/tests/ledger_calendar_home_local_runner.ps1), using fresh dedicated `eldaftar_owner_meeting_stabilize_20261021g`, passed all migrations, meeting migration rollback, calendar/home, historical date feeds, R2 notes/pagination, exact pricing, trade/dispatch, trade edit/delete, staff delegation, appearance and FK coverage. The independent two-connection retry race produced one close and one audit. Its own loopback cluster was stopped. |
| Hosted development | [Reconciliation and rollback verification](development-reconciliation.md) passed; four installed-but-unrecorded migrations were marked applied, with no schema replay or function redeployment. All 72 public table counts/full-row fingerprints are unchanged. |
| Arabic RTL visuals | Fresh 320/390/1440, light/dark, 1.0/1.7 text-scale matrix: 12 combinations × 22 states = **264 captures**. Supplementary notes, cash-transfer and rendered document samples are indexed below. Contact sheets and representative original-size images were inspected. |
| Documentation/privacy | Relative links, current-pointer consistency, artifact provenance and `git diff --check` passed. Synthetic fixtures/captures only; no source meeting media, transcripts, requirement DOCX/PDF, customer details or credentials were added. |

The first broad run exposed the cash-feedback/summary overflow defects and missed pagination taps; the corrected full run passed. Initial local startup and hosted notes-denial assumptions were corrected before final passing gates. Those intermediate failures are not counted as passed checks.

## Visual evidence

All [matrix captures](captures/) use `{320|390|1440}-{light|dark}-{1.0|1.7}.png`. Examples:

- [Denominations](captures/denominations-320-dark-1.7.png), [owner closing rows](captures/close-count-390-light-1.0.png), [staff count](captures/staff-count-320-dark-1.7.png), [owner review](captures/staff-owner-review-390-light-1.7.png).
- [Invoice handoff](captures/pdf-share-390-dark-1.7.png), [shop-image opt-in off](captures/invoice-shop-image-off-320-light-1.7.png), [opt-in on](captures/invoice-shop-image-on-390-dark-1.7.png), [notes preview](captures/notes-preview-390-light-1.0.png).
- [Cream image output](pdf/design-header-image-page-1.png), [dark A4](pdf/design-dark-print-page-1.png), [long names](pdf/long-names-page-1.png), [all-karat continuation](pdf/karats-page-2.png), [legacy continuation](pdf/legacy-karats-page-2.png). The 15 rasterized pages also cover many items, missing/transparent logos and partial purchase. PDF weights retain three decimals; displayed Arabic and digit runs were reviewed.
- [Notes form/image/retry/error samples](notes/) cover 320/1440 in both themes; [cash-transfer samples](transfer/) cover the same widths/themes. These supplement the matrix and behavior assertions, not native permissions or screen-reader acceptance.

Capture tests can target a new output directory using `OWNER_MEETING_CAPTURE_DIR` and `INVOICE_PDF_CAPTURE_DIR`. The notes preview capture explicitly waits for image decoding. Historical capture directories were preserved.

## Acceptance and next task

The [acceptance checklist and one scoped next-task recommendation](acceptance.md) cover actual native sharing/printing, camera and R2 round trips, midnight/reconnect, staff/owner two-device behavior, wider design approval and earlier-slice native reminders. No unavailable device check is claimed passed. No commit, push, publish, release/production build or application distribution was performed.

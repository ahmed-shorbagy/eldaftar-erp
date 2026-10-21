# Remaining acceptance — 2026-10-21

Milestone 4 remains open. [Validation](validation.md) and [development evidence](development-reconciliation.md) establish bounded implementation and test results, not owner or hardware acceptance.

| Workflow | Remaining acceptance |
| --- | --- |
| Open financial day | On native Android, iOS and Windows, leave a synthetic day open across shop midnight, resume/reconnect, confirm earlier entries remain visible and new entry is allowed; owner close/open alone changes the financial day. Repeat with a changed shop time zone and stale session. |
| Exact trade entry | Owner checks localized keyboards/paste, multiple coin/bullion denominations and counts, measured-weight override, two-decimal new trade weights and unchanged historical three-decimal edits against paper examples. |
| Invoice output | On each supported device, share the same confirmed branded edition as PNG and PDF; inspect Arabic joining/digits, long names, all karats, logo and exact totals in the receiving app. Check missing recipient, target selection, cancellation, unavailable share handler, interruption/access loss and duplicate taps. Confirm send only after the owner actually sends. Verify supported system printing; thermal-receipt layout and D23 legal/tax fields remain separate open scope. |
| Appearance | Owner accepts cream/gold and dark/gold output against the reference. Verify shop-image opt-in uploads/validates/saves a logo revision, off uses the mark, and changing the avatar does not rewrite issued editions. |
| Notes/R2 | On native devices, accept/deny camera/gallery permission, preview/change/remove an image, save through actual presigned R2 upload/verification, refresh on another session, open/zoom, expire the read URL and retry. Interrupt upload/save and restart; retain pending status and the same command without duplicate notes. |
| Staff count | Real owner and assigned staff use two native sessions: staff sees only the count form with no expected counts/cash; submit once, then lose access. Repeat revoke/expiry/stale-day cases. Owner separately enters cash, resolves discrepancies and alone confirms the audited financial close. |
| Earlier slices | Complete the existing repairs/debts/CRM owner scripts and native reminder permission/delivery/restart/DST checks on Android/iOS/Windows. Existing historical evidence remains valid only for its recorded scope. |
| Wider scope | Searchable Help/support remains planned. General daily/weekly report exports belong to Milestone 5. Wider all-screen design approval, legal invoice content and final integrated release acceptance remain open. Removed tours and text-only invoice messaging are not pending UI work. |

No new physical-device, iOS, printer, camera, WhatsApp recipient/delivery or two-device native-to-hosted check was performed in this stabilization task.

## One recommended next implementation task

Complete a bounded **DOC-04 native invoice-output integration harness** for Android and Windows, with an explicit iOS execution checklist for a macOS/device environment. Cover PNG `image/png` and PDF `application/pdf`, unavailable/cancelled handoff, temporary-file lifetime/cleanup, access loss during rendering, and supported system-print completion/cancellation. Reuse the current confirmed edition and existing injected adapters; preserve separate owner send attestation. Deliver runnable integration tests, capability states and device evidence where available. Do not add automated WhatsApp sending, provider delivery claims, tax fields, receipt layouts or reporting in that task. This is a recommendation for a separately selected task, not authorization to publish an app.

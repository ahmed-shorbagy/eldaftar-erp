# ADM-01 — independent review and final verification

Date: 2026-10-22, Africa/Cairo. The owner selected the prepared directory task and explicitly requested Grok delegation. Grok Build 1.0.50 implemented the feature; Codex reviewed the source, requested a bounded correction pass and independently verified the final work. The [earlier local validation](validation.md), including its original 51-test run and later 67-test correction run, remains historical evidence.

## Delivered behavior and review

The React administration client now provides a real Arabic RTL subscriber directory: global and filtered subscription counts, literal name/exact-identifier search, status filters, bounded server paging and read-only subscription detail. It uses the existing palette and persisted themes, a 1120-pixel admin measure, a desktop table and mobile cards. Counts remain exact strings/BigInt. Subscription status comes from the server; display dates use the configured browser time zone. Each response is a consistent snapshot; a cursor does not freeze later pages.

Reviewed corrections cover the detail parser, session/account replacement and late replies, one bounded retry after a same-user token refresh, reuse of the existing server admin guard with ban denial, canonical cursors, safe UUID search conversion, semantic field labels and large-count wrapping. No existing authorization assertion was relaxed. The ready-admin shell test now expects the delivered directory; missing/failed startup still expects the existing fallback.

Codex found that an enlarged detail dialog could not be scrolled by keyboard while focus stayed on its close button. Its content is now a named, focusable region with a semantic focus outline. An actual 320-pixel, 1.7-text browser check scrolled from 0 to about 741 pixels and reached the final fields. Tab/Shift-Tab, Escape and focus restoration were also checked. Sign-out now hides subscriber content while pending, prevents duplicate requests, and exposes Arabic failure/retry instead of an unhandled rejection.

## Independent gates

| Gate | Final result |
| --- | --- |
| React | From admin: npm run lint, npx tsc -b --pretty false, npm test -- --maxWorkers=1. All exit 0; **12 files / 68 tests passed**. The new deferred sign-out test initially needed its fake subscription callback signature corrected; the complete final gates passed afterward. |
| Flutter | From app: flutter analyze --no-pub reproduced the known AOT analysis-server launcher failure. Direct dart analyze passed with no issues. flutter test --reporter compact passed **1,591 tests**; invoice samples and captures were redirected to ignored build output. No SDK/global setting or Flutter source was changed for ADM-01. |
| Fresh SQL and migration round trip | pwsh -NoProfile -File supabase/tests/admin_subscribers_local_runner.ps1 -Database eldaftar_admin_subscribers_codex_20261022a passed. All migrations applied, the new migration rolled back/reapplied, and both admin_subscribers.sql and admin_subscribers_hosted.sql passed. The dedicated loopback cluster stopped. The runner refuses an existing database. |
| Hosted behavior and preservation | [Development deployment](deployment.md): the rollback-only hosted fixture passed, all **76** tracked table fingerprints match, and all original **59** migration rows are unchanged. |
| Existing work | **98** pre-existing implementation/evidence files, including weekly Reports source/tests/captures, its ADR/planning/prompt and the calendar runner, matched their pre-delegation SHA-256 values. Existing migrations and staged work were not replaced. |

The SQL fixtures cover actual authenticated/anonymous roles, owner and count-staff denial, revoked/banned/deleted/anonymous administrators, session expiry, exact start/expiry and missing/future terms, global versus filtered counts, literal wildcard characters, UUID search, complete keyset paging, and continued denial of shop report/customer APIs. The hosted fixture retains existing rows and terms, adds only synthetic transaction-local actors/shops, and rolls back.

## Arabic browser evidence

**43 synthetic captures** under [captures](captures/): directory/detail × 320/390/1440 × light/dark × 1.0/1.7 text; empty/loading/failure/access-loss and exact large-count cases; pending/failed sign-out at mobile/desktop; and the keyboard-scroll regression. Contact sheets and representative original-size images were inspected. All directory widths and the large-count case had no page-level horizontal overflow. Long dialog content remains vertically scrollable with a reachable close control.

Representative views: [desktop dark](captures/adm01-directory-1440-dark-1.0.png), [narrow light enlarged](captures/adm01-directory-320-light-1.7.png), [enlarged detail](captures/adm01-detail-390-dark-1.7.png), [keyboard-reached final fields](captures/adm01-detail-keyboard-scroll-320-light-1.7.png), [sign-out failure](captures/adm01-signout-failure-390-light.png). [Viewport checks](captures/adm01-browser-checks.json) and [interaction checks](captures/adm01-functional-checks.json) record the synthetic harness results. Search, paging, filter reset, dialog keyboard behavior and sign-out clearing were exercised against the actual components with an injected gateway.

## Acceptance boundary

This establishes source review, independent local gates, browser layout/interaction evidence and development-hosted role/behavior verification. The browser harness does not establish a real platform-admin login through the published frontend to hosted RPCs; the frontend is local source and has not been published. Owner acceptance, broader ADM-01/ADM-07, subscription mutations, Milestones 4/5 and earlier native acceptance remain open. No release/production build, commit or push was performed.

Final documentation review passed: **611 local links across 22 current/added Markdown files**, scope consistency, privacy and git diff --check. Captures contain synthetic data only; credentials, source requirements and real customer/contact records were not added. The temporary browser viewport was reset and the local review services were stopped after verification.

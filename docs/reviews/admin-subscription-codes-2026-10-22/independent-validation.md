# ADM-02/ADM-08 independent final validation — 2026-10-22

Codex independently reviewed the Grok diff and reran the relevant gates. Grok implemented the slice and correction passes; Codex made the final narrow review fixes. No commit, push, frontend publication, production/release build or real customer issuance. Owner acceptance remains pending. Historical implementer records remain intact and are superseded only for current status by this record and [deployment](deployment.md).

## Behavior and review

Arabic RTL issuance lives in selected subscriber detail, using existing MUI and semantic tokens. Integer duration is 1–3660 days; code validity is 1–365 days, default 30. Review names the selected shop, duration, validity and estimated expiry, explicitly stating that owner redemption alone activates/extends. The response gives the exact server expiry. The secret appears once in transient session-bound memory; copy is explicit and live-authorized. Dismissal, navigation/pagehide, shop changes, unmount, session replacement/expiry and access loss clear it. Nothing writes the secret to storage, logs, analytics, URLs or audit payloads.

The required origin lease is checked immediately before writing and after awaits. In-flight duplicates are disabled. UUID-v4 envelopes remain frozen on unknown/timeout outcomes; manual retry uses the same key. Replay returns no secret and never triggers new issuance. History is shop-bound, capped/keyset-paged, metadata-only, with server unused/expired/redeemed status. No new financial, customer, contact, media or general shop access, revocation, entitlement editing, dispatch or bulk issuance.

Reviewed SQL preserves the existing issue/redeem signatures, hash-only storage, owner/shop binding, single use, atomic renewal, committed invalid attempts and replay-before-throttle. Current identity/ban/session and membership checks repeat after contended locks. Renewal and expiry use server time after the entitlement lock. D13 expired-owner read/export/redemption rules remain. The original Flutter contract is unchanged.

Independent review corrected pending-copy dismissal/session races through Grok, then directly fixed timezone-offset seconds and a probe-only token-refresh expiry timer, with regression tests. Independent SQL rerun exposed a flaky test barrier: its polling query matched itself before the holder acquired the lock. The barrier now excludes its own backend and waits for the holder's post-lock PgSleep. The failed disposable database/log is preserved; no production logic was changed to satisfy that test.

## Exact final checks

| Gate | Independent result |
| --- | --- |
| React lint | `npm run lint` from `admin/`; exit 0. |
| TypeScript | `npx tsc -b --pretty false`; exit 0. |
| React behavior | `npm test -- --maxWorkers=1`; **14 files, 116 tests passed**, exit 0. |
| SQL/RLS/atomicity | `pwsh -NoProfile -File supabase/tests/admin_subscription_codes_local_runner.ps1 -Database eldaftar_admin_subscription_codes_codex_verified_20261022`; exit 0. Migration rollback/reapply, original owner redemption, issuance authorization/bans/sessions/parameter mismatch/ranges/expiry/history paging, hosted-shape fixtures, prior directory, identity RLS/commands and sync passed. |
| Real concurrency | Same-key issuance: issued/replayed. Same-key redemption: activated/replayed. Different-key same-code: activated/reused_code; exactly one extension. Committed invalid-attempt throttle and replay passed. Revocation/session expiry during lock waits and entitlement-lock membership/session/code/term expiry passed. |
| Flutter regression | `flutter test --no-pub --reporter compact --dart-define=INVOICE_PDF_CAPTURE_DIR=build/admin-codes-review/pdf`; **1591 tests passed**, exit 0. No Flutter source changes. |
| Dart analysis | `flutter analyze --no-pub` hit the existing Windows SDK AOT/dartaotruntime launcher error. Direct `C:\flutter\bin\cache\dart-sdk\bin\dart.exe analyze` from `app/` passed: no issues. No SDK/global setting changed. |
| Browser | Chromium/Vite synthetic harness, widths **320/390/1440**, light/dark, text scale **1/1.7**: **76 PNGs, 97 checks**, no page errors or horizontal overflow. Review, issued, paging, pending/failure/unknown/conflict/access loss/timeout/replay, clipboard, Tab containment, content scrolling, Escape/focus restoration passed. |

[Browser check data](captures/browser-checks.json), [contact sheet](captures/independent-contact-sheet.jpg). Codex visually inspected enlarged mobile both themes and desktop review/history. Text wraps, secret remains LTR and wraps, long Arabic shop names remain readable; content scrolls and action rows remain reachable. Existing cream/brown/dark roles are preserved. Keyboard focus is visible. Synthetic display text is deliberately invalid and cannot activate a shop.

Independent browser probes also confirmed: copy after dismissal = 0; writes after silent session replacement = 0/access_lost; microsecond order accepted; offset-equivalent cursor accepted; probe-only refreshed lease expires at its new deadline.

Scoped React formatting follows existing style with lint and whitespace review; no formatter is configured in admin. No dependency changes. Final link/privacy/whitespace and preservation checks are recorded with deployment. The initial worktree was clean. The 3034-file initial tracked fingerprint manifest and all previous evidence were preserved. Both independent disposable databases, including the failed timing-barrier run, remain in place; the loopback PostgreSQL server was stopped. Temporary artifacts are under `%TEMP%/eldaftar-admin-codes-20261022`; earlier Grok databases/evidence remain untouched.

## Limits and next bounded feature

Backend is development-only. Frontend source is local/unpublished; owner acceptance and real-device end-to-end delivery remain open. Native analyzer launcher limitation is explicit above. No commercial month/year plans were invented. Milestone 5 is not complete.

Next proposed bounded feature: **ADM-03 server-timed in-app subscription-expiry notices**, with thresholds and read/dismiss semantics agreed before implementation. Keep outbound dispatch, contact/location permissions, retention/deletion and financial access separate.

Final preservation/consistency review: the 3034 tracked-file baseline has 14 intended source/current-document changes, 3020 matching hashes, no missing files, no historical review or migration changes, and an empty index. Current-document link scan checked 514 links with no missing targets; the separate new-review/ADR scan checked 12 links with no missing targets. New text files have no trailing-whitespace issues; git diff --check passed. Privacy scan found no logging, storage, analytics or URL write in the code-issuance path. Vite and the disposable PostgreSQL server were stopped; no Grok process remains. No commit or push.

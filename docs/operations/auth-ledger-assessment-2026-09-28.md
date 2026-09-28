# Authentication and daily ledger assessment — 2026-09-28

This is a current assessment. The historical [Milestone 1](milestone-1-validation.md), [opening balance](milestone-2-opening-validation.md), and [authentication redesign](../reviews/auth-redesign-2026-09-27/validation.md) records remain unchanged. Evidence in those notes must be read with its stated date and environment; passing tests there does not prove the whole feature.

## Authentication acceptance

| Criterion | Current state | Evidence still required |
| --- | --- | --- |
| Email/password and Egyptian phone/password login | Implemented; both identifiers succeeded in live development HTTP tests using canonical `+20` phone, and a wrong password failed | Repeat through a native app session, test session restoration and password-manager input |
| Owner registration, duplicate/failed attempt, safe retry | Live development signup succeeded; same-key replay returned the same shop; duplicate contact was rejected | Interrupted create/completion response and same-key reconciliation through live Auth, plus UI handling on device |
| Owner-only pending/active/expired access | Live development RPCs returned pending, active, and expired against one synthetic owner/shop | Two-client refresh and native app transition proof |
| Session expiry/revocation | Deleting the synthetic Auth session made `get_daily_ledger` return `session_expired` with the old token; Flutter gateway checks expiry | Natural token expiry, revoked shop-list result and native refresh/reconnect proof |
| Arabic RTL light/dark and accessibility | Widget matrix and prior Android emulator review are recorded in the redesign note; the 2026-09-28 fake-gateway Android integration test passed | Final real Auth path on an available native device, TalkBack/VoiceOver and password-manager/keyboard checks; distinguish widget frames from device proof |
| Clean replay and environment acceptance | Development migrations and rollback-only SQL tests previously passed | Clean migration replay, separate staging when available, and documented fixture cleanup |

Authentication is **open**. It is not promoted to done by the local tests or historical screenshots.

## Daily ledger acceptance

| ID | Current state | Evidence still required |
| --- | --- | --- |
| LED-01 | Opening creates one business day; owner approved bounded manual-close rules in [ADR 0005](../adr/0005-bounded-sale-and-close-rules.md) | Close and explicit next-day commands, discrepancy/correction decision, concurrent and midnight tests |
| LED-02 | Four method opening balances; current Flutter increment adds an exact overall confirmed cash display | Full posting-backed daily balance and movement summaries, multi-session reconciliation |
| LED-03 | Opening stock by category/karat/count only | Posted sale and purchase summaries, configurable card order/visibility, category rules |
| LED-04 | Opening feed has actor and server-derived time | Sale/purchase/expense/close feed rows, invoice identity, notes marker |
| LED-05 | Not implemented | Daily text/image notes, approved quick actions, storage and access tests |
| LED-06 | No profit claim is shown | Approved profit valuation or explicit net movement design and tests |
| SALE-01–04 | Owner approved bounded sale arithmetic, whole-invoice total without per-item allocation, and tender rules in ADR 0005; no sale command is present | Product model, atomic command, UI, concurrency/RLS/retry tests |
| PUR-01–04 | First fully paid recognition into approved aggregate buckets is approved but unimplemented; partial-payment and unrecognized-goods effects expressly deferred | Initial atomic purchase command and tests; D04/D05/D16 worked example and custody/obligation decision for remaining cases |
| EXP-01 | Bounded positive split-tender expense is approved but unimplemented | Atomic command, exact balance/retry tests, and UI evidence |

The daily ledger is **open**. The opening balance is a foundation, not acceptance of the complete ledger.

## 2026-09-28 increment and limits

- A shop-list response started under an old owner/gateway is ignored after the owner changes. A regression test starts one owner's response, changes owner and gateway, and then completes the old response. The new owner keeps the correct empty state.
- The confirmed opening ledger displays «إجمالي النقد» calculated from integer piastres across the four server balances. The opening review now uses the same accurate label instead of «صافي النقد». An exact-arithmetic test uses a value above JavaScript's safe integer range. This is a cash **balance**, not profit or daily net movement.
- Grok Build 1.0.41 was invoked for a bounded auth task, but returned HTTP 402 `Grok Build usage balance exhausted` before changing source. Codex made and reviewed this increment directly. No remote Auth setting, migration, deployment, release build, or production state changed.
- Eight committed synthetic widget captures show the confirmed ledger at [320 light](../reviews/ledger-cash-2026-09-28/confirmed-light-320.png), [320 dark](../reviews/ledger-cash-2026-09-28/confirmed-dark-320.png), [1440 light](../reviews/ledger-cash-2026-09-28/confirmed-light-1440.png), and [1440 dark](../reviews/ledger-cash-2026-09-28/confirmed-dark-1440.png), plus the opening review at [320 light](../reviews/ledger-cash-2026-09-28/review-light-320.png), [320 dark](../reviews/ledger-cash-2026-09-28/review-dark-320.png), [1440 light](../reviews/ledger-cash-2026-09-28/review-light-1440.png), and [1440 dark](../reviews/ledger-cash-2026-09-28/review-dark-1440.png). Codex inspected all eight: the Arabic total is readable without overflow. These are Flutter widget renders, not native ledger device proof.

## Validation results

- `C:\flutter\bin\dart.bat format lib test`: 55 files, no changes on the final run.
- `C:\flutter\bin\flutter.bat analyze --no-pub`: no issues after the final ledger parser change.
- `C:\flutter\bin\flutter.bat test --no-pub --reporter compact`: 127 passed, including the owner-switch race, exact total above JavaScript safe integer precision, aggregate overflow rejection, and existing auth/ledger widget paths.
- `C:\flutter\bin\flutter.bat test integration_test/auth_review_test.dart -d emulator-5554 --no-pub`: passed on an Android 16 Pixel 7 emulator using fake gateways. It produced a debug APK only. It is native interaction proof for the mocked auth path, not live Auth proof.
- Live development HTTP against project `xchapwvmvoefriqcxtvn`: owner registration HTTP 200; same-key replay HTTP 200 with the same shop; duplicate contact HTTP 409 `identifier_taken`; wrong password HTTP 400; email and canonical Egyptian phone password token HTTP 200; pending shop list HTTP 200 with the same shop; after a temporary entitlement, active and expired lists HTTP 200 and `get_daily_ledger` read HTTP 200; after the exact synthetic session row was removed, `get_daily_ledger` returned HTTP 400 `session_expired`. The first raw phone probe sent a local `010…` string directly to Auth and failed; the Flutter contract canonicalizes it to `+20…`, which succeeded. All three synthetic Auth users and shops created by these probes, their reservation/audit/entitlement rows, and the temporary session were deleted with exact-ID guards; post-cleanup counts for those IDs were zero. Unrelated pre-existing development rows were preserved. No credential or access token was written to this note.
- Rollback-only development SQL: `identity_rls.sql`, `identity_commands.sql`, `opening_balances.sql`, and `opening_rls.sql` each returned its `*_passed` marker. `egypt_owner_registration.sql` failed at its early empty-database assertion, `invalid registration persisted a profile`. At that time the development project contained one unrelated reservation, one registered shop, and two Auth users. This test assumes a globally empty database in several later assertions, so it was not edited or rerun against those rows. It needs isolated clean replay or baseline-safe fixture scoping before it can pass on this development state. The failed transaction rolled back its own fixture.
- No SQL schema or policy was changed in this increment. Clean local migration replay remains unverified: this workstation still has no local `psql`, Supabase CLI, Docker, or Podman runtime configured for that gate. A true two-session financial race remains untested. React source was untouched, so React lint, tests, and TypeScript checking were not required for this increment. No release or React production build ran.
- `git diff --check`, link, theme-token, synthetic-data, and privacy review: pass on the final diff. Historical validation notes were left intact.

## Priority gap list

1. Build and verify atomic sale, fully paid purchase, expense, close, and explicit next-day commands using [ADR 0005](../adr/0005-bounded-sale-and-close-rules.md), with server audit, idempotency, RLS, concurrent retries, reconciliation, and owner UI. The existing schema constrains operation kinds and days to opening only; it cannot be treated as a general ledger yet.
2. Resolve the remaining D03/D04/D05/D08/D16/D26 product rules before piece/lot tracking, partial/financed purchases, denomination routing, close discrepancy correction, or profit display. Initial aggregate buckets and a blocked discrepant close are approved in ADR 0005. Implement LED-03–LED-05 and full LED-04 operation details only against approved contracts.
3. Make `egypt_owner_registration.sql` safe on a nonempty development baseline or replay all migrations in a clean isolated database. Repeat SQL and two-session race gates before a financial migration is accepted.
4. Complete live native Auth and two-client expiry/revocation checks, final accessibility narration, and interrupted registration reconciliation. Keep authentication open until those results are recorded.

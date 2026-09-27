# Milestone 2 opening-balance validation

Status: development evidence for the opening-balance slice only. This note does not accept G0, Milestone 1 as a whole, or Milestone 2 as a whole. [ADR 0004](../adr/0004-opening-balance-working-defaults.md) records user-authorized working defaults dated 2026-09-26. Those defaults are recommendations. D02, D03, D04, and D08 stay unsigned. The approval rows in the financial worked examples stay blank. Sale, purchase, expense, close, invoice dispatch, and onboarding remain planned.

Validation date: 2026-09-27. Branch: `codex/opening-balances`. Grok Build 1.0.41 with `grok-4.7` drafted the bounded tasks and did not commit, push, apply a migration, or change Auth. Codex reviewed each diff, reran the gates below, applied the two additive migrations only to development project `xchapwvmvoefriqcxtvn`, and created the local commits. The user authorized that development-only application. No staging, production, push, pull request, publication, Edge deploy, Auth setting change, or release build was performed.

| Task | Commit | What landed |
| --- | --- | --- |
| Contract and ADR | `0176740` | Opening contract and ADR 0004. Defaults dated 2026-09-26. |
| Domain | `2e0e7f4` | Exact money, milligram, count, karat, and draft rules. The Flutter suite at that commit was 52 tests, the whole app suite. |
| Migration and SQL | `20d4a7d` | `20260927065414_opening_balances.sql`, applied on 2026-09-27 to development only. |
| Forward indexes | `ffaed49` | `20260927070108_opening_balance_indexes.sql`, reviewed and applied to development only. The original applied migration file was not edited. |
| Flutter ledger | `43b9eaa` | Confirm, status lookup, Arabic RTL ledger, and widget captures. |

## What the slice implements

`confirm_opening_balances` is the only writer. The payload has no shop id. An active owner confirms once, including an explicit all-zero opening. Replay of the same key and canonical payload returns the original operation. A different payload on a stored key returns `payload_mismatch` and posts nothing. Failed validation does not keep the key. The server opens one `Africa/Cairo` business day from the confirmation `timestamptz`. Midnight does not close it. There is no close or reopen function.

Journals balance inside one unit family. Opening clearing is a mechanical offset. The owner ledger hides it. The confirmed feed is one row, «رصيد افتتاحي», with the owner name and Cairo time. There is no profit card, fine-weight card, or invoice number. Pending shops have no financial read. An expired entitlement can read and cannot confirm. Sale, purchase, expense, transfer, close-day, dispatch, and reset controls are absent.

`get_opening_status` and `get_daily_ledger` are read-only. The ledger is a synchronous view of confirmed postings. Refresh is an explicit full read. It is not a websocket subscription. Admin source did not change, so the React dashboard gained no shop-ledger behavior and no admin lint, test, or typecheck gate was required.

The layout uses the existing theme tokens: centered content at the shared 720-pixel maximum, 20-pixel horizontal padding, stacked scrolling sections for cash, net cash, stock, scrap, and count, and `titleMedium` for narrow titles. Widget captures are the intended layout under those tokens. They are not a signed visual baseline.

Implementation references: [contract](opening-balance-contract.md), [main migration](../../supabase/migrations/20260927065414_opening_balances.sql), [forward indexes](../../supabase/migrations/20260927070108_opening_balance_indexes.sql), [opening command tests](../../supabase/tests/opening_balances.sql), [opening RLS tests](../../supabase/tests/opening_rls.sql), [coordinator](../../app/lib/src/features/daily_ledger/application/opening_flow.dart), [HTTP adapter](../../app/lib/src/features/daily_ledger/data/http_opening_gateway.dart), [screen](../../app/lib/src/features/daily_ledger/presentation/daily_ledger_screen.dart), and [capture harness](../../app/test/daily_ledger_capture_test.dart).

## Migration identity

| File | Role | Raw file SHA-256 |
| --- | --- | --- |
| `supabase/migrations/20260927065414_opening_balances.sql` | Main additive schema and functions | `710fb55c0ef6b2bfdd910a536fff856bf64a9e2f3e7fee45fd1c598df02a60af` |
| `supabase/migrations/20260927070108_opening_balance_indexes.sql` | Eleven forward indexes | `64991d11c2395c3679e51f18556dcc0e02feb1553d73ce6a43ae7fce6f240eba` |

The initial local filename used version `20260926132851`. After applying the reviewed SQL to development, Codex aligned the local filename with the generated remote version `20260927065414` before committing. After trimming a trailing CRLF, the local SQL text and the remote applied SQL hash are the same: `eaae9d8215365f8649520ba5895463d38a0d70de573e6f47ec5be47bff5d231f`. The index migration clears all eleven financial foreign-key advisor findings. Audit corrections inside the main migration include explicit non-null guards that close PostgreSQL CHECK-null holes, a posting-to-operation composite foreign key, an amount length guard, an exact bucket check, and a scalar JSON guard. The SQL tests also strengthen the feed assertion and exercise a negative balance on an existing zero account.

## Development SQL gates Codex ran

Codex executed the reviewed files through Supabase `execute_sql`, one connection per file, each inside `BEGIN` / `ROLLBACK`:

- `identity_rls_passed`
- `identity_commands_passed`
- `egypt_owner_registration_passed`
- `opening_balances_passed`
- `opening_rls_passed`

After the index migration, Codex repeated `opening_balances.sql` and `opening_rls.sql`. Both passed again. No synthetic fixture was committed on the hosted database.

Assertions cover integer precision and fractions, a huge 140,000-digit overflow, transport above JavaScript's safe integer range, aggregate overflow, the opening catalog, atomic row counts, the explicit zero opening, replay, payload mismatch, status lookup, expiry, live fixture `auth.sessions` rows, owner and platform-admin isolation, cross-shop denial, constraints, and the `Africa/Cairo` zone database date when the UTC date differs. A later calendar day leaves the same business day open.

Follow-up counts, all zero: Auth users, Auth sessions, shops, memberships, entitlements, identity audit, registration reservations, business days, operations, accounts, journals, postings, command requests, financial audit, and outbox. That is fifteen counts. The rollback-only runs created no persistent fixture or Auth user.

`node --check supabase/run-rls-tests.mjs` passed. From `supabase/`, `npm run test:rls` exits 1 because `SUPABASE_TEST_DATABASE_URL` is unset. This workstation has no `psql` and no Docker database runtime. Clean local migration replay and CI were not executed. A real race of two independent sessions was not executed. The single-threaded SQL tests are not a concurrency proof. Shop-row locking and unique keys are the designed invariant; the two-session race gate stays open.

## Advisors on development after the index migration

Security advisor, four warnings, intentional authenticated `SECURITY DEFINER` functions: `confirm_opening_balances`, `get_opening_status`, and the existing `is_platform_admin` and `list_my_shop_accounts`. The new functions require a live Auth session, the current owner, an entitlement, and the same shop, use a fixed empty `search_path`, and are not granted to `anon`. Linter note: [Supabase linter documentation](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable).

Three pre-existing informational findings, RLS enabled and no policy, for tables that stay unreadable by clients: identity audit, platform admins, and private owner-registration reservations. Linter note: [Supabase linter documentation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

No SQL security errors were reported.

Performance advisor, final: three pre-existing informational unindexed foreign keys (identity governorate and reservations), one existing membership table without a separate primary key, and seventeen unused indexes on the empty development schema observed after the new indexes and before test usage. Linter notes: [Supabase linter documentation](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys), [Supabase linter documentation](https://supabase.com/docs/guides/database/database-linter?lint=0004_no_primary_key), and [Supabase linter documentation](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Flutter gates Codex ran on `43b9eaa`

From `app/`, `dart format lib test` and the final scoped formatting check passed, `flutter analyze` reported no issues, and `flutter test` passed 107 tests. That count is the entire app suite, not a domain-only subset. The earlier domain commit's 52 tests were also the entire suite at that time.

Review fixes covered by those tests: a durable validation restart with the unknown outcome frozen, requiring the caller owner id and checking the current owner before HTTP bearer dispatch, lifecycle and expiry guards, response-body timeout, a malformed DTO, an acknowledged commit or read failure that stays pending rather than a false financial failure, and a regression proving that confirmation during a busy refresh sends no RPC and leaves the review unlocked for a later submission. Access denial hides previously shown figures.

`http` 1.6.0 moved to a runtime dependency. Its version did not change. No `flutter build apk`, `flutter build windows`, or iOS release build was run for this slice.

## Visual evidence and its limit

Codex inspected all 46 PNGs under ignored `app/build/opening-review/` through six contact sheets and representative full mobile and desktop frames. Widget captures are not device proof and not a live Auth session.

The 28 primary frames are the four combinations of 320×640 and 1440×900 with light and dark, for uninitialized top and lower, review top and lower, confirmed top and lower, and pending activation.

The 18 extra frames are expired empty, expired confirmed top and lower, and in-flight pending, each at both widths and both themes (16), plus the BigInt review top at 320 in light and dark (2).

The review and confirmed captures use an additional synthetic visual fixture with four cash methods, five stock rows (bullion 24 and worked jewelry 14, 18, 21, and 22), and two scrap rows (18 and 24). That fixture is not the SQL worked example. Arabic RTL holds in both themes. The confirm control is disabled while the copy says «بانتظار تأكيد الخادم». Explicit zero is distinct from uninitialized. Expired copy is read-only and omits confirmation controls. Windows-only visual tests skip when Tahoma or Material Icons are missing; on this workstation they ran. Capture cleanup removed only the managed filenames and left other build files in place.

## Still open

Live Auth, device rendering, session revocation, two-client refresh, and realtime acceptance were not demonstrated. Local migration replay, staging, and iOS acceptance remain open. Interactive onboarding and Help resume remain planned, as does prototype approval D12. Sale, purchase, expense, close and reopen, reset, and invoice dispatch are not implemented. The next financial slice is the first atomic sale. A later deployment still needs a direct authorization.

## Documentation gate for this note

This file and the partial rows in [the requirements matrix](../requirements-matrix.md) are documentation only. The gate is `git diff --check`, a check that relative links in the changed Markdown resolve, and a consistency and privacy review. No application build or test is part of this documentation change. Codex independently checked every relative file link, reviewed consistency against the implementation and recorded results, and checked privacy. These documentation checks passed; the note is committed separately from the financial code.

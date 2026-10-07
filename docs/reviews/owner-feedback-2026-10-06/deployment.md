# Development deployment and verification — 2026-10-06

This is a later deployment run, authorized directly by the owner for **development project `xchapwvmvoefriqcxtvn` only**. It supplements [the earlier local review](validation.md); the earlier validation, screenshots and approval history remain intact. No application distribution, release/production build, commit, push, reset or unrelated feature work occurred.

## Deployed versions

| Reviewed source migration | Actual hosted version | Source SHA-256 |
| --- | --- | --- |
| `20261005071930_owner_feedback_registration_and_ledger.sql` | `20261006072226` | `3D76CFE273F0A7FE8BAF39C93EB15CB5BA000B479EE63BC3426F191F2927A519` |
| `20261005091822_complete_owner_feedback.sql` | `20261006072242` | `ACFE0BA225A32F538B967C47032D75AED68CAB6C43B2F7CDA9158B561214C840` |
| `20261006063258_optional_owner_registration_region.sql` | `20261006072259` | `252108AB176531946C435DC8D99AB41FF926DF0E27C42A67FAF2EED6440F3F16` |

All three were absent at preflight and applied individually, in the authorized order, through Supabase `apply_migration`. That tool assigns hosted timestamps; the source filenames were not renamed and migration history was not repaired to imitate them. Readback of each stored migration statement exactly matched its local SQL source. Do not blindly run `db push`: the existing history also has an empty local `20261001124245` marker and a local pagination source `20261004090000` deployed historically as `20261004120509`.

`owner-register` is **ACTIVE, version 2**, deployed through CLI 2.119.0 with `--project-ref xchapwvmvoefriqcxtvn --use-api --no-verify-jwt`. Bundle SHA-256: `ff9939a98c08ba988347fcf24f4ba0f1530066f12bc2c363b2340efd60cc7927`. Readback matched all seven runtime/configuration files: `index.ts`, `boundary.ts`, `http.ts`, `flow.ts`, `errors.ts`, `validate.ts`, and `deno.json`. The local dependency graph and pinned `@supabase/supabase-js@2.117.1` were included. The local lock was checked with `deno check --frozen index.ts`; the hosted unbundled source does not include a lockfile.

JWT verification remains disabled because registration precedes a session, matching the original deployed configuration. The function validates the supplied publishable key and rejects secret callers; SQL registration RPCs remain service-only. No project Auth settings or secrets were changed.

## Compatibility and preservation

The checkout was already dirty; existing Flutter, tests, documentation and optional-region work were preserved. Hosted PostgreSQL was 17.6. Hosted registration, trade and pagination function bodies matched their expected local predecessor definitions, including the differently timestamped pagination migration. Required tables/helpers, old constraints/indexes and one-owner uniqueness were present. There were no conflicting new helpers/columns, incompatible registered profiles or duplicate phone values for the new index. The original hosted function was version 1, and only its validator differed from the reviewed runtime files.

The current Supabase changelog and function authorization/configuration documentation were checked. No relevant SDK/runtime migration was needed. During verification, the connector temporarily returned `FGA Authentication Error. Unauthorized`, and SQL calls then returned an internal protocol error. The user opened/signaled the signed-in dashboard; migration inventory was independently visible there. Database connector execution subsequently recovered. CLI direct database fallback could not connect over this network's IPv6 path; no database password or connection settings were changed.

## Hosted verification

All ten suites passed **on the specified hosted development database**, using explicit transactions ending in `ROLLBACK`, fixture collision guards, synthetic identities and no local Auth/Storage bootstrap:

- `identity_rls.sql`, `identity_commands.sql`.
- `egypt_owner_registration.sql`, `owner_feedback_registration.sql`.
- `opening_balances.sql`, `opening_rls.sql`.
- `daily_ledger_trades.sql`, `invoice_price_components.sql`.
- `milestone_3_inventory.sql`, `milestone_3_inventory_rls.sql`.

A focused dashboard SQL rollback check additionally exercised optional/manual region and national-phone normalization contracts for **all 22 supported countries**. These are hosted SQL results, not GoTrue registration proof for all countries.

The trade suite verifies two unnamed unpaid purchases remain separate operation-specific payables, exact amounts/weights, isolated settlement/returns, owner/item/count journal facts, and original-payload replay without duplicate cash/stock/payable/audit effects. Changed-payload retries and cross-shop commands fail. Identity/RLS suites verify owner-only membership, one shop per owner, pending/expired/revoked/session boundaries and immutable audit restrictions.

Real HTTP checks against **Edge version 2 and hosted Supabase Auth** passed for Saudi Arabia with `SA:` and Egypt with `EG:منطقة اختبار يدوية`:

- Registration returned completed, real owner/shop UUIDs.
- An identical request replay returned exactly the same owner and shop; changed business data returned HTTP 409.
- Email/password and phone/password authenticated the same owner UUID.
- Authenticated `list_my_shop_accounts` returned one shop with `member_role = owner`.
- Financial access remained denied for these pending, unentitled shops.

The first HTTP probe using the current legacy anon key returned HTTP 401 `invalid_credentials` before registration. The client uses a modern `sb_publishable_…` key; the same key format passed all real checks. Legacy-key registration compatibility is a remaining gap; no key configuration was changed to conceal it.

## Fixture cleanup and retained audit evidence

Cleanup was planned before real HTTP registration: sign out globally, ban each synthetic Auth actor, revoke only its exact membership, give no entitlement, and retain immutable registration audit records and their referenced rows. Financial checks used rollback-only fixtures, so **no persistent synthetic financial operations** were created. Deleting the referenced shop/membership/auth rows would undermine the audit trail; those inactive synthetic registration records remain intentionally.

| Synthetic profile | Owner UUID | Shop UUID | Registration request |
| --- | --- | --- | --- |
| `SA:` | `a801e026-1f4a-443e-a4c7-080367399167` | `6f236943-89d1-498e-815a-34f5987fce84` | `7c60aa1f-740a-4099-b6a2-cbe0ec089d52` |
| Egypt manual region | `be078f87-3c9a-4032-80f1-f5425b9287b7` | `58e64b8b-214c-486a-b739-4811f359cb73` | `06d83fe6-234c-4551-825b-91f58905f69a` |

Cleanup queries checked the fixture request/name/identity markers before changing exact memberships. Final verification: two banned actors, two revoked memberships, zero fixture sessions, zero fixture entitlements, two preserved `owner_registered` audit events, and zero fixture financial operations. Test passwords and API keys were held in memory only and were not written into repository artifacts.

Counts before/after were shops 1→3, Auth users 2→4, memberships 1→3, reservations 1→3 and identity audits 1→3, entirely explained by those two retained registration fixtures. Financial counts stayed operations **18**, financial audits **18**, journals **54**, postings **113**. Rollback SQL checks left the original registration counts unchanged before the real HTTP tests. No real account was used for sign-in or posting.

## Client and native checks

- Changed Dart formatting: 30 files checked, zero changed. `flutter analyze --no-pub`: no issues. Full `flutter test --no-pub`: **426 passed**.
- React `npm run lint`, `npm test`: **37 tests across 9 files passed**. `npx --offline tsc -b`: passed. React source/tokens remained unchanged.
- Edge `deno test --allow-env`: **24 passed**; `deno check --frozen index.ts` and scoped `deno lint`: passed. An initial Deno lint command from the repository root inappropriately scanned browser React files; it was corrected to function scope without changing those files.
- Fresh disposable PostgreSQL **17.11**, localhost port **55438**: all local migrations replayed and the same ten core suites passed. The extra `daily_notes_pagination.sql` gate initially refused the new disposable database name; its temporary copy was guarded to that exact name and then passed. Only this new task-owned cluster was started/stopped; existing data/clusters were not reset. The cluster is stopped.
- An actual hosted `get_daily_ledger_v2` and `get_ledger_operation_page` response was captured inside a synthetic trade transaction that rolled back. The **current client codecs** decoded all 11 entries and preserved confirmed state, exact amount/gram strings, optional party, owner, item, quantity and shop time fields. This is captured-hosted-contract verification, **not** a running native client making financial API calls.
- Android emulator `emulator-5554`: `flutter test integration_test/ledger_feedback_review_test.dart -d emulator-5554 --no-pub` and the corresponding `auth_review_test.dart` both passed. These debug/native harnesses use synthetic in-memory gateways; they are **not hosted Auth or financial acceptance**.
- Native Arabic RTL authentication/shop and dark/light ledger pixels were reviewed. Regenerated 320/390/1440 widget captures retain the shared brown/cream/dark palette, separate journals, all eight metric controls, currency-free amounts and optional names. Desktop separate journals and narrow customization were inspected in both themes. Dark startup and saved theme behavior remain covered by regression tests. No tours, guide cards, employee roles or shop selector were added.

[New Android synthetic screenshots](deployment-native) supplement the historical [widget screen evidence](screens).

## Advisors and acceptance gaps

Security advisor returned no ERROR-level findings. It reports 45 intentional authenticated SECURITY DEFINER RPC warnings, three deny-by-default RLS tables without policies, and disabled leaked-password protection. The owner RLS/command tests passed; warnings are recorded, not silently cleared. [SECURITY DEFINER advisor guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [RLS no-policy guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance advisor reports only INFO findings: five unindexed foreign keys, one table without a primary key, and 19 unused indexes. No unrelated schema/security changes were deployed.

Known failed compatibility probe: legacy anon-key registration returned HTTP 401; the configured modern publishable-key path passed. Still unverified: real HTTP registration in the other 20 supported countries; updated native client→hosted financial success/reconciliation across sessions and restarts; real timeout-after-commit/network races; Windows/iOS native execution; fresh OS dark splash; physical-device behavior; final owner visual acceptance and separately authorized application distribution. The Android synthetic harnesses, SQL fixtures and captured-response parser check do not close these gaps. Release and React production builds were deliberately not run because they were not requested.

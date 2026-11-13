# Admin Phase 4: code presets and revocation, and subscriber broadcasts — validation and development deployment — 2026-11-13

Scope: [ADR 0048](../../adr/0048-subscription-code-presets-revocation-and-broadcasts.md), Phase 4 of the [admin completion plan](../../operations/admin-completion-plan-2026-11-10.md). Owner decisions D-A2 (30-day month, 360-day year) and D-A3 (in-app broadcast contract) of 2026-11-10. No release build, production deployment, app publication or Edge Function change.

## What changed

| Area | Change |
| --- | --- |
| Codes (ADM-02) | Issue form presets شهر/3 أشهر/6 أشهر/سنة (30/90/180/360 days) beside the manual 1–3660 field. Revoke an unused, unexpired code with a reason (`admin_revoke_subscription_code_v1`). History v2 shows the `revoked` status, time and reason. Web Share «مشاركة الرمز» where the browser supports it. |
| Broadcasts (ADM-06) | `platform_broadcasts` and `platform_broadcast_recipients`, RPCs for preview, send, withdraw, admin history, owner inbox and read marking. Dashboard «الرسائل» section with composer, review (frozen recipient count), sent history (recipients, delivered, read) and withdrawal. «إرسال رسالة لهذا المتجر» on the subscriber detail opens the composer for that shop. |
| Owner app | «الرسائل» in «المزيد» for owners, with the unread count. The inbox opens a message in full and marks it read. The newest unread message shows as a workspace banner; «إخفاء» marks it read. |
| Audit (AUD-01) | «سجل الإدارة» lists `subscription_code_revoked` (codes family, with reason) and a new «الرسائل» family (`broadcast_sent`, `broadcast_withdrawn`). Message bodies, links and recipient lists are never in the summaries. |
| Dashboard theme | Toggle groups (audit families, directory filters, presets, composer choices) keep a full border on each wrapped button. |

Revocation ends code validity at the revocation time. The unchanged `redeem_subscription_code` then returns `expired_code`, so the Flutter activation dialog needs no new status. Entitlements are never touched.

## Gates

| Gate | Result |
| --- | --- |
| Admin `npx tsc -b` | clean |
| Admin `npm run lint` (oxlint) | clean |
| Admin `npm test` | 30 files, 244 tests passed (34 new) |
| Flutter `dart format --set-exit-if-changed lib test` | 0 changed |
| Flutter `dart analyze --fatal-infos` | no issues |
| Flutter `flutter test` | 1,900 passed (16 new in `broadcast_inbox_test.dart`) |
| SQL dry run on development: both migrations plus `subscription_code_revocation_hosted.sql` and `platform_broadcasts_hosted.sql` in one transaction, rolled back | passed; afterwards no new object existed |
| Mutation check: unread count expected `2` instead of `1` | failed with `inbox_a`, as intended |

No local disposable PostgreSQL was available on this machine. The local runners' binaries are absent from TEMP, so SQL ran only as rolled-back transactions on development.

The SQL suites cover:
- grants;
- anonymous, owner, partner, banned-admin and expired-session denial;
- revoke validation, replay and key reuse;
- revoked, redeemed and expired outcomes;
- redemption of a revoked code returning `expired_code`, with no entitlement created and a redeemed term unchanged;
- history v1 and v2 shapes;
- the audience rule for every segment, with ownerless shops excluded;
- `audience_changed` and `empty_audience`, with no write;
- send replay and key reuse;
- the frozen recipient list;
- a scheduled message hidden until it starts;
- owner-only inbox and read scope;
- delivered and read stamping;
- admin counts and states;
- keyset paging;
- withdrawal;
- table immutability;
- audit rows without bodies or links.

## Development deployment

Target: **xchapwvmvoefriqcxtvn** only, under the standing authorization in AGENTS.md.

| Version | Name | SHA-256 |
| --- | --- | --- |
| `20261113100000` | `subscription_code_revocation` | `3DF6F8DB54CABD1C2C6DE980592133A038AE92FA42B0171E8FA1D7718C52E702` |
| `20261113110000` | `platform_broadcasts` | `E4F66DA579874B634FC7D577CA11DE41BCFED2DF6CDBCA3A6BA248D0A3D44394` |

Order of events:
1. The first apply command failed before running any SQL: the CLI resolved the file path from the repository root. The deployment loop still ran `migration repair --status applied` for both versions.
2. About a minute later, both files were applied in version order with the corrected path. Each succeeded.
3. Object checks confirmed `admin_revoke_subscription_code_v1`, `platform_broadcasts` and `list_my_broadcasts_v1`.

For that interval, history showed both versions applied while their objects were absent. No client depends on them yet, and no data changed.

After deployment, these rolled-back hosted suites passed:
- `subscription_code_revocation_hosted.sql`;
- `platform_broadcasts_hosted.sql`;
- `admin_audit_hosted.sql`;
- `admin_subscription_codes_hosted.sql`;
- `admin_overview_hosted.sql`;
- `help_content_announcements_hosted.sql`.

## Preservation

| Measure | Before (12:43:29 UTC) | After (12:45:45 UTC) |
| --- | --- | --- |
| Migration rows / latest | 106 / `20261112092000` | 108 / `20261113110000` |
| Shops / entitlements / memberships / Auth users | 12 / 5 / 12 / 14 | 12 / 5 / 12 / 14 |
| Financial operations / `financial_audit_events` / `identity_audit_events` | 87 / 97 / 12 | 87 / 97 / 12 |
| Subscription codes / code events / `platform_admin_audit_events` | 0 / 0 / 0 | 0 / 0 / 0 |
| Broadcasts / recipients | — | 0 / 0 |
| Entitlement digest | `9ab14b7bca184a7235740541616fd5e6` | same |
| Membership digest | `2008882b19296de7d61bbd9d6f220efd` | same |

## Visual review

Dashboard: gitignored synthetic harness `admin/tmp/phase4` with fake data, in Arabic RTL.
- Messages list and composer review at 1240 pixels, dark.
- Messages list, subscriber detail code history (unused with «إلغاء الرمز», revoked with reason), issue dialog presets, and «سجل الإدارة» with the new actions at 375 pixels, light.
- No horizontal overflow.

Three defects were fixed during review:
- Start and end shared one field. They are now separate «يبدأ الظهور في» and «يتوقف الظهور في» fields.
- The three counts shared one label. They are now separate fields.
- `https://` in the link hint was reordered by bidi. It is now isolated in an LTR `<bdi>`.

The wrapped toggle buttons' joined borders were also fixed in the theme.

App: widget captures in `app/build/broadcast-review` at 320, 390 and 1440 pixels in light and dark show the banner, the «الرسائل» entry with the unread count, the inbox and the message detail. Times are shop-local and the layout is right to left.

## Limitations

- No signed-in review against development data: there is still no platform-admin test account in this environment.
- Owner acceptance, frontend publication and device review of the inbox are pending.
- Web Share availability varies by browser. Copy remains the fallback.
- Recipient lists freeze at confirmation, including for scheduled sends. A shop that registers before a scheduled start does not receive the message, as ADR 0048 states.
- Long dates in the dashboard still repeat the full time-zone name, a known polish item from Phase 1.

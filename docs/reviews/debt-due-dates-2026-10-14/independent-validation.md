# Debt due dates and in-app reminders — independent validation

Implementation began 2026-10-14; final delivery recorded 2026-10-15 (shop/client time zone). Milestone 4 slice 8. [Confirmed D19/D32](../../adr/0019-debt-calendar-due-dates.md), [exact submitted prompt](../../operations/debt-due-dates-submitted-prompt-2026-10-14.md), [development preservation](deployment.md).

Codex implemented directly. A separate read-only agent reviewed backend, recovery routing, session/source identity and actual Arabic captures. A different agent independently validated without editing production source or tracked tests. Grok was not used. Final review has no remaining actionable findings.

| Independent gate | Exact result / ignored evidence under tmp/debt-due |
| --- | --- |
| Scoped formatting | 16 Dart files, zero changes, exit 0; independent-format-final-delivery.log. |
| Flutter analysis | No issues, 6.0 seconds, exit 0; independent-analyze-final-delivery.log. |
| Full Flutter regression | 1167 passed, exit 0, 1m47s; independent-flutter-final-delivery.log. |
| Focused/calendar | Corrected tracked calendar regression: one pass, two seconds. Independent 12 probes at 320/390/1440 × both themes × 1.0/1.7, 640-pixel height: date validation/day selection, full scaling, rendered buttons at least 48 pixels. Month navigation is covered by the corrected tracked regression. Earlier root scoped run: 234 passed before the last calendar probe. |
| React | Lint and npx tsc -b exit 0; 38 tests in nine files, 28.36 seconds. Admin source/tokens unchanged. |
| SQL/RLS/round trip | Fresh apply/transaction rollback/schema-ACL-policy-index-trigger fingerprint/reapply; debt, statement, due, compensation, CRM-05 and sync suites pass. independent-sql-final.log; db-7ac48b13-d60d-4fa4-9111-6babca34fae0-sql.log; cluster stopped. |
| Real local races/snapshots | Legacy debt races; duplicate-key replay, competing date versions; source-first standalone settlement/archive, gold settlement/archive, partial/full purchase return; forced mid-read detail/list metadata commits. Complete old snapshot during commit, complete new snapshot afterward. |
| Extra backend | Actual standalone cancellation and purchase partial/full return retain dates/audit. All four RPCs deny expired JWT session/revoked/anonymous/admin/lost JWT; real anon lacks execute grants. Cross-shop detail/send not found, list empty, status absent; expired owner exact replay/read/reconcile; append-only UPDATE/DELETE and direct-write denial. independent-auth.sql/log, independent-local-return.log. |
| Arabic RTL captures | All 144 PNGs decoded: 12 states × 320/390/1440 × light/dark × 1.0/1.7, Cairo/icons loaded. app/build/debt-due; independent-capture-integrity.json. Actual representative states reviewed by both agents and root. Final 12 calendar images regenerated after label padding. |
| Hosted | Full debt + statement + due suites passed through connected Supabase in explicit rollback after reviewed application. First connector request expired; readback verified outcome before retry. Zero fixture users/sessions/memberships/entitlements/fault triggers/date/audit/request rows remain. |
| Whitespace/docs | git diff --check passes; final links/privacy/consistency/baseline review recorded at completion. |

Coverage includes three source identities, both standalone directions, exact money/all five gold karats, optional/add/change/clear/past/today/future dates, leap days/invalid calendars, Cairo midnight/New York DST gap/fold, shop-zone changes, stale source/version/filter/cursor, complete paging, partial/full settlement/cancellation/archive, zero financial effect and old history/PDF compatibility. Client consistency checks use the server-returned shop-local date, never device time.

Shared-locker tests cover financial/foreign/unknown preservation, secure restart, frozen key/payload, unknown replies, malformed receipts/wrappers, mismatch, cleanup failure, duplicate taps, delayed old-account locker reads and late token/account/logout changes. Original pending source takes precedence over another selection. Polls compare content/session freshness; sync/reconnect/resume invalidate reviews without erasing drafts. Access loss clears exposed data.

The Arabic calendar has full-size day rows on phones/enlarged text and a days-of-month grid where 48-pixel controls fit. Full text scaling, keyboard/escape/date input remain. Cairo, semantic brown/cream/dark roles, LTR figures/dates, three-decimal gold and Arabic money-unit labels remain. No guides or alarm controls.

Initial evidence remains: nullable cursor, rejection provenance and intermediate session boundaries corrected after separate review; Ahem captures regenerated with Cairo; lazy scrolling/overlay capture corrected; native calendar clipping/small cells replaced by the accessible selector; floating label fixed with viewport padding. Initial full run had 1166 passes and one new calendar fixture failure from tapping before scroll layout settled. Corrected with settling/hit-testable selection, independently passed focused and full reruns. Initial lint infos and connector expiry remain in logs.

Native Android/iOS/Windows owner/device, screen-reader and real native-to-hosted network/restart acceptance remain open. Synthetic runtime/adapters/local connections and hosted rollback tests do not establish these. DEBT-03 alarm/background/sound/app-closed delivery remains planned. No real notifications/messages/provider sending, commit, push, publishing, reset/history deletion, release/production builds or React production build.


Final independent documentation/preservation review: 1419 baseline files checked, zero missing, only 11 necessary existing files changed. Ten documents and all 280 local links reviewed; exact 49-table counts/hashes, the equal post-sale gate pair, pre-existing-history proofs, all 37 prior migration mappings, deployed hashes and zero-fixture retirement independently match evidence. Submitted prompts, historical records, prior migrations, theme tokens, React and PDF source remain byte-identical. Privacy/consistency and git diff --check pass. Ignored evidence: tmp/debt-due/independent-final-doc-review.json and independent-deployment-doc-check.json.


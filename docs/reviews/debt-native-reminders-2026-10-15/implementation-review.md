# Native debt reminders: separate implementation review

Implementation began 2026-10-15; final continuation 2026-10-16. A separate read-only Codex reviewer inspected the submitted prompt, owner-confirmed ADR 0020, additive migration, source/date/version/session contracts, HTTP and shared-locker recovery, scheduler/store/clock interfaces, authentication/shop lifecycle, Arabic UI and Android/iOS/Windows setup. The reviewer edited no application/test files, mutated no hosted data and scheduled no notification.

Final reviewed migration raw SHA-256: 4eb1e4f27acc3b8e473425f1a60af433b986b3dcf5213cdce98302fc18650e1d. Queue projection contains exactly source_kind/source_id/native_freshness/trigger_at/time_valid; live source eligibility is checked on the server. Existing due-date and financial contracts remain unchanged.

Actionable findings were returned to the implementer and corrected before development application:

- Fired one-shot routes were previously lost when removed from the pending manifest. A bounded encrypted opaque route history now survives firing, requires fresh authorization and clears on account change; cold/restarted route behavior is tested.
- Monotonic time previously counted snapshot network latency twice. A final-response anchor now advances the server snapshot without inventing missed triggers.
- New native HTTP error codes were absent from the typed whitelist, which could freeze definite stale rejections as unknown. The whitelist and real HTTP regression tests now distinguish rejection from uncertain outcomes.
- Historic tap routes may reuse one stable OSID with different tokens. The durable decoder now requires request-ID uniqueness only for pending requests, while preserving unique historical tokens.
- Audit events now carry server-derived current-shop wall time; UI labels the current display zone separately from the appointment zone recorded at save.
- Unsupported enable/settings actions are hidden. Native save confirmation, permission and OS registration remain separate Arabic states.
- Android's default boot handler could re-register missed cached one-shots. The pinned bridge filters owned past requests without altering foreign JSON fields, excludes every plugin repeat field, and restores future requests. Private API/cache dependence is documented against exact 22.3.2.
- Strict queue decoding requires the exact five keys, including nullable trigger_at; source ordering, complete paging, content invalidation and no-private-field evidence are tested.

Static re-review found no remaining blocking implementation finding in the reviewed scope. Independent SQL/RLS/atomicity/race/snapshot/migration gates and final client validation are recorded separately. Native device notification delivery, physical reboot/force-stop, sound/Do Not Disturb and owner acceptance remain open; source inspection and adapter/JVM/debug checks do not close them.

The owner requested grok-delegate during continuation. Grok's later contribution is restricted to one additional synthetic lifecycle regression test file; its actual result, Codex diff review and independent rerun are recorded in the validation/completion evidence. Grok is forbidden from committing, pushing, deploying, reading/mutating hosted data or scheduling notifications. No release/production build, publishing, reset or financial-history deletion is authorized.

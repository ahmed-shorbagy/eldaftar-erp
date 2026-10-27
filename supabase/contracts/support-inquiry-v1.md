# Support inquiry v1

Owner-selected HELP-02 / [ADR 0036](../../docs/adr/0036-support-inquiries.md). Implemented and development-deployed on 2026-10-27: [validation](../../docs/reviews/help-support-2026-10-27/validation.md), [deployment/preservation](../../docs/reviews/help-support-2026-10-27/deployment.md). Owner/device acceptance and React publication remain open.

This contract is an explicit narrow audited support path consistent with the [D21](../../docs/decisions.md) approval rule — platform staff read and triage inquiries the owner deliberately wrote for support. It does **not** implement the general D21 shop-data access mechanism, and it grants no read of ledger, stock, customer, invoice, report, R2 or entitlement rows. Text-only: no new R2 media kind ([ADR 0024](../../docs/adr/0024-cloudflare-r2-media-storage.md)). Zero financial, dispatch or business-audit effect.

## Tables

`public.support_inquiries`: one row per inquiry — `shop_id`, `owner_user_id` (enforced to the `shop_memberships` pair), nullable `category` (`subscription`, `technical`, `financial_question`, `other`), `body_ar`, `status` (`new`, `in_progress`, `answered`, `closed`), nullable `reply_ar`, `idempotency_key` unique per `(shop_id, idempotency_key)`, server-UTC `created_at`/`updated_at`/`answered_at`/`closed_at`. The shape constraint binds reply/timestamps to status. RLS is on with no policies; all privileges are revoked from `anon`/`authenticated`.

`public.support_inquiry_events`: append-only audit (`inquiry_id`, `from_status`, `to_status`, `reply_ar`, `actor_user_id`, `idempotency_key` unique per `(inquiry_id, idempotency_key)`, server UTC). An append-only trigger rejects update/delete.

## Owner RPCs

`private.support_owner_session()` requires a non-anonymous, non-deleted, non-banned `auth.users` row with an accepted session. `private.support_owner_shop()` returns the caller's unrevoked owner shop; no membership is `unauthorized`. There is **no entitlement check**: pending and expired owners can submit and read.

`create_support_inquiry_v1(p_idempotency_key, p_category, p_body_ar)`:
- Validates the body through `private.support_inquiry_text(text, 10, 1000)`: no CR/Tab (newline is the only accepted control character), Unicode trim, `char_length` 10–1000 Unicode scalars. Unknown/extra category failures are `invalid_input` (`22023`). Definitive validation failures do not consume the key.
- Existing `(shop_id, idempotency_key)` row with identical normalized payload returns it with `result_status: "replayed"`; changed category or body fails `payload_mismatch`.
- More than 9 non-closed inquiries for the shop fail `inquiry_limit`.
- Success inserts one `new` inquiry plus one `new` audit event keyed by the same idempotency key and returns the row shape below with `result_status: "saved"`.

`list_my_support_inquiries_v1(p_cursor_at, p_cursor_id, p_page_size)` returns `{inquiries, next_cursor_at, next_cursor_id, open_count, open_limit: 10, time_zone, snapshot_at}` from one statement snapshot: the owner's own rows ordered `created_at desc, id desc`, keyset cursor to the last row, page size clamped 1–50 (default 20), missing cursor row fails `stale_cursor`. Rows carry `{id, shop_id, shop_name: null, category, body_ar, status, reply_ar, created_at, updated_at, answered_at, closed_at}`. `time_zone` is the shop's configured zone so clients can render shop-local dates; the `open_count` hint is read in the same statement and is a display aid, not an authority over the create-time check.

## Admin RPCs

Both are gated by `private.admin_subscriber_gate()` ([ADR 0027](../../docs/adr/0027-admin-subscriber-directory.md)) re-checked at every call; revoked/lost admin rights never return rows or apply a write.

`admin_list_support_inquiries_v1(p_status, p_search, p_cursor_at, p_cursor_id, p_page_size)`: optional status filter; search is the exact shop identifier only (any other text selects nothing); keyset paging to the last row with `stale_cursor` on a missing cursor row. Rows carry the owner row shape plus `shop_name`, `shop_created_at` (registration date) and `shop_time_zone` — and nothing else: no owner identity, contact, location, financial or CRM fields, matching the [ADM-01](../../docs/adr/0027-admin-subscriber-directory.md) boundary.

`admin_update_support_inquiry_status_v1(p_id, p_to_status, p_reply_ar, p_idempotency_key)`: transitions are exactly `new → in_progress` (no reply), `in_progress → answered` (reply required, 10–1000 validated text), `answered → closed` (reply must be null; the saved reply remains immutable). Anything else fails `invalid_transition` (`P0001`); unknown inquiry fails `not_found` (`P0002`). Repeated key with the same transition/reply returns the current row with `result_status: "replayed"`; changed transition or reply fails `payload_mismatch`. Each applied transition appends one audit event with the acting admin, key, and server UTC before/after statuses. Max page size 50 counts and lengths travel as plain integers here (no money or gold values exist in this feature).

## Errors

`invalid_input` (`22023`), `payload_mismatch`, `inquiry_limit` (`22023`), `unauthorized`/`unauthenticated`/`session_expired`/`forbidden` (`42501`), `stale_cursor` (`P0001`), `invalid_transition` (`P0001`), `not_found` (`P0002`), `append_only` (audit immutability). Role grants: owner RPCs `authenticated`; admin RPCs `authenticated` with in-function gate; helpers and the gate are ungranted; `service_role` is revoked when that role exists.

# Opening balance contract

Status: design for the Milestone 2 opening slice. This document is the command contract and the migration design. It does not add a SQL file, apply a migration, or make a financial action operational.

Date of the user-authorized working defaults: 2026-09-26. Those defaults are recommendations recorded in [ADR 0004](../adr/0004-opening-balance-working-defaults.md). They are not shop-domain signatures. D02, D03, D04, D08, and G0 stay open. The blank approval rows in [financial-worked-examples.md](../discovery/financial-worked-examples.md) stay blank. [milestone-1-validation.md](milestone-1-validation.md) is unchanged.

The next migration is created later with the Supabase CLI (`migration new`). Its timestamp must sort after `supabase/migrations/20260926120634_owner_only_access.sql`. This task does not add that file and does not invent its timestamp. Historical migrations are not edited. The financial tables below are not applied.

## Provenance

A source fact is behavior stated in the local basics document (BASIC), the daily-ledger document (LEDGER), the page-by-page document (PAGES), the agreement body as reconciled in [source-reconciliation.md](../discovery/source-reconciliation.md), or an accepted ADR. A recommended default is authorized for this slice only.

| Topic | Provenance |
| --- | --- |
| Whole operation succeeds or fails with a visible reason; a repeated tap does not post twice; success is shown only after server confirmation | Source fact, BASIC |
| Daily ledger is the main screen and shows shop figures, the actor, and the time | Source fact, LEDGER. Showing the opening result after confirmation, and an explicit uninitialized state before it, is a recommended default |
| Four cash methods: total context plus cash, instant transfer (انستا), wallet (محفظة), and card (فيزا) | Source fact, LEDGER, PAGES, and the agreement body. Stable codes `cash`, `instant_transfer`, `wallet`, `card` are a recommended default. Rename and delete stay with D24 |
| One shop currency, EGP; store piastres; 100 piastres = 1 pound; display two decimal places; no tax, workmanship, discount, or second currency in this command | Recommended default. D02 is unsigned. Drawings use pounds and do not define minor units |
| Gold in milligrams; 1,000 mg = 1.000 g; three decimal gram places; karats 14, 18, 21, 22, and 24 where the source allows them | Three decimal display places are a repository rule (AGENTS.md and product scope), not a Word storage format. The karat set is a source fact where PAGES and the agreement body allow 14, 18, 21, 22, and 24. Integer milligrams are a recommended default |
| Piece-tracked buckets have an integer count; scrap has no count | Recommended default. LEDGER uses an integer count and, in the sale story, defaults it to 1. D03 is unsigned |
| Opening catalog below | Recommended default for opening only. It does not close D03 or D04. Conflict C3 stays open outside opening |
| One scrap bucket per karat 14, 18, 21, 22, and 24; scrap is not saleable stock | Source fact that scrap sits beside saleable stock, including 14 and 22 when present. One aggregate bucket per karat is a recommended default |
| New shop has no financial rows until the owner confirms all zeros or the entered balances, once | Greenfield with no legacy import is accepted D01. Zero balances or one idempotent opening, and the ban on a silent balance update, are database-design proposals adopted by the user-authorized recommendation. Explicit owner confirmation is part of that recommendation |
| Only an active shop confirms. Pending cannot read or write shop financial tables. Expired can read and cannot confirm or change | Source fact, ADR 0003 and accepted D13, applied to this command |
| On success the server opens exactly one business day from `timestamptz` in `Africa/Cairo`. Midnight does not close it. Close and reopen are later | Source fact: the owner closes the day manually because work can continue after midnight (LEDGER and PAGES). `Africa/Cairo` is the applied shop default in the registration schema, not a Word sentence. Server UTC timestamps are a repository rule. Deriving one open day at confirmation is a recommended default. D08 stays open for close, reopen, and stale-day posts |
| Owner actor and server UTC time on the operation and an append-only audit event. The feed shows the owner name and Cairo time | Source fact, ADR 0003 and AGENTS.md |
| Balanced journals per unit family. Opening clearing is a mechanical offset, not profit, tax, capital, or valuation, and is hidden on the owner ledger | The balanced-journal shape and the zero-or-one-opening policy in database design are proposals. This slice adopts them by the user-authorized recommendation. They are not source facts from the Word files. The opening-clearing name and the hide rule are part of that recommendation |
| `confirm_opening_balances` is the only writer. The payload has no shop id. RLS denies table writes | Source fact, database design and AGENTS.md |
| No staff, invitations, roles, or grants | Source fact, ADR 0003, which supersedes staff text in PAGES and LEDGER |
| Synthetic numbers in this contract | Recommended default. Drawing totals and the ambiguous prose purchase amount are not fixtures |

## Invariants

- Persist EGP as integer piastres and gold as integer milligrams. Counts are integers. Reject values outside PostgreSQL `bigint` (`-9223372036854775808` through `9223372036854775807`) before arithmetic. Opening inputs are non-negative, so a negative input fails validation.
- JSON requests and responses carry money, milligrams, and counts as canonical integer decimal strings. SQL parses those strings into checked `bigint` values. It does not scale pounds and it does not normalize pound text. Karat and payload version remain small JSON integers. No binary floating point and no cast of a quantity through a JSON number.
- Reject a negative cash amount, milligram amount, or count. Reject a fractional piastre on the wire, a fractional milligram, and scientific notation. The UI and domain boundary convert a pound entry before the call: `1.25` EGP becomes the piastre string `125`. SQL receives `125`, never `1.25`. A fourth gram decimal is rejected at that same boundary and never becomes a milligram string.
- Reject a payload whose cash methods, or whose same-karat milligrams, or whose counts, sum outside `bigint`. The transaction rolls back.
- Every non-zero journal sums to zero inside its own unit family. A gold journal contains one bucket and one karat. A count journal contains one piece-tracked bucket. Scrap milligrams are not netted against saleable milligrams. Counts of different buckets are not added together.
- A posting amount is a non-zero integer. The explicit zero opening has no postings.
- Shop-owned cash, saleable, scrap, and piece-count accounts stay at or above zero. Borrowed gold, customer gold, trader gold, repair custody, financier gold, and unrecognized goods have no fields in this command.
- The server is the source of truth. The client stays pending until the command response or `get_opening_status` returns the committed outcome.
- One shop confirms once. Replay of the successful key returns the original operation and does not add balances. The same key with a different canonical payload returns `payload_mismatch` and adds nothing.
- Failed validation does not insert a command row, so the key is not consumed. `payload_mismatch` applies only after a successful opening stored that key.
- The shop is derived from the authenticated owner. Unknown JSON fields are rejected.
- A presented JWT `session_id` must match a live `auth.sessions` row for `auth.uid()`. An expired, missing, or other-user session fails. Transaction-local SQL fixtures may impersonate with `request.jwt.claim.sub` when no session id is presented, matching `private.caller_session_accepted()`.
- Confirmation timestamps and user metadata do not grant access.

## Opening catalog

Recommended catalog for this slice. One aggregate bucket per category and karat. No product names, bullion denomination rows, or coin-type rows. Weighed milligrams are the gold quantity.

| Category code | Arabic label | Karats | Quantity |
| --- | --- | --- | --- |
| `worked_jewelry` | مشغولات | 14, 18, 21, 22 | milligrams and count |
| `bullion` | سبائك | 24 | milligrams and count |
| `coin` | جنيهات | 21 | milligrams and count |
| `scrap` | كسر | 14, 18, 21, 22, 24 | milligrams only |

Reject any other category or karat pair. Reject a count on scrap. Every supplied piece-tracked row requires positive milligrams and a positive count. Omit empty rows. Reject zero-weight pieces and weight without pieces. Scrap rows require positive milligrams. Reject two rows with the same category and karat. Bullion 21, coin 24, and worked jewelry 24 are invalid.

One jewelry category, with 18 as the UI default and 14, 21, and 22 available, is the recommended resolution of conflict C3 for opening only.

Cash method codes and Arabic labels: `cash` نقدي, `instant_transfer` انستا, `wallet` محفظة, `card` فيزا.

## Decimal transport

Every cash, milligram, and count string on the wire matches `^(0|[1-9][0-9]*)$`. No decimal point, sign, space, exponent, or leading zero. A fractional wire piastre is `invalid_input`. SQL does not interpret the string as pounds and does not rewrite it.

The UI and domain boundary own display units. Pounds with at most two decimal places become piastre strings (`1.25` EGP becomes `125`). Grams with at most three decimal places become milligram strings (`1.830` g becomes `1830`). A fourth gram decimal or a fractional piastre never leaves that boundary as a payload field.

Canonical payload version 1, built by the server before hashing:

- `version` is the JSON integer `1`.
- `cash` always contains `cash`, `instant_transfer`, `wallet`, and `card`. An omitted key is filled with `0`. The only canonical zero is `0`. `cash.cash` of `1000000` is 1,000,000 piastres, displayed as 10,000.00 EGP.
- `stock` is sorted by category code, then karat ascending. `milligrams` and `count` are canonical integer strings. `karat` is a JSON integer.
- `scrap` is sorted by karat ascending. `milligrams` is a canonical integer string.
- No other keys. A null idempotency key is `invalid_input`.

Object key order inside a JSON object is not semantic. Two payloads that fill the same cash keys and sort to the same stock and scrap arrays are equal as PostgreSQL `jsonb`. The stored hash is SHA-256 of PostgreSQL's own canonical `jsonb` text (`payload_canonical::text`), not of the client's key order and not of a client-compacted byte string. The unique key is `(shop_id, idempotency_key)`. The actor is an audit column and is not part of the unique key.

Example shape after the server fills omitted cash keys and sorts the arrays. PostgreSQL may store object keys in its own order; that order is not part of the contract.

```json
{"version":1,"cash":{"cash":"0","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"5000","count":"3"}],"scrap":[{"karat":21,"milligrams":"1000"}]}
```

## Worked example

Recommended synthetic example, not a signed fixture. Confirming it posts the following buckets.

| Bucket | Stored amount | Display strings |
| --- | --- | --- |
| نقدي | 1,000,000 piastres | pounds `10000.00` |
| انستا | 0 | pounds `0.00` |
| محفظة | 250,000 piastres | pounds `2500.00` |
| فيزا | 0 | pounds `0.00` |
| مشغولات 18 | 5,000 mg, count 3 | grams `5.000`, count `3` |
| مشغولات 21 | 2,560 mg, count 1 | grams `2.560`, count `1` |
| مشغولات 14 | 1,250 mg, count 1 | grams `1.250`, count `1` |
| سبائك 24 | 8,000 mg, count 2 | grams `8.000`, count `2` |
| جنيهات 21 | 8,000 mg, count 1 | grams `8.000`, count `1` |
| كسر 21 | 1,000 mg | grams `1.000` |
| كسر 14 | 500 mg | grams `0.500` |

Canonical cash strings for this example are the piastre integers `1000000`, `0`, `250000`, and `0`.

Money journal, unit `money`, currency `EGP`: نقدي +1000000, محفظة +250000, opening-money clearing −1250000. Sum 0. Zero methods have accounts at 0 and no posting.

Gold journals, each two postings summing to zero, each on its own bucket, against an opening-gold clearing account of the same karat: مشغولات 18 +5000; مشغولات 21 +2560; مشغولات 14 +1250; سبائك 24 +8000; جنيهات 21 +8000; كسر 21 +1000; كسر 14 +500. The two 21K saleable buckets and the 21K scrap bucket stay on separate accounts and separate journals. Their 21K clearing postings share the 21K opening-gold clearing account and are not netted against each other inside one journal.

Count journals, each summing to zero against that bucket's opening-count clearing account: +3, +1, +1, +2, and +1. Scrap has no count journal.

An explicit zero payload is all four cash strings canonical `0`, empty `stock`, and empty `scrap`. It stores the operation, the four cash accounts at 0, no metal accounts, no clearing accounts, no postings, and the open business day. That confirmed zero is different from uninitialized, which has no operation and no business day.

Overflow example that must fail: the piastre strings `4611686018427387904` on each of two cash methods. Each value fits in `bigint`. Their sum does not. The command returns `overflow` and leaves no rows. A value above `bigint` max, sent as an integer string, is also `overflow`.

## Commands

Both functions are PostgreSQL `SECURITY DEFINER`, `search_path` fixed empty, granted to `authenticated`, and not granted to `anon` or `public`. Each call runs as one transaction. They take no shop id.

### `public.confirm_opening_balances(p_idempotency_key uuid, p_payload jsonb)`

Success JSON. Quantities are strings. `replayed` is false on the first commit and true when the stored key is returned again.

```json
{"ok":true,"operation_id":"uuid","business_day_id":"uuid","business_date":"YYYY-MM-DD","replayed":false}
```

Failure is `RAISE EXCEPTION` with message exactly the stable code and no extra text. The adapter maps that message. The transaction rolls back.

| Code | When | Arabic client copy |
| --- | --- | --- |
| `unauthenticated` | `auth.uid()` is null | يلزم تسجيل الدخول |
| `session_expired` | A presented session id is missing, expired, or not the caller's live `auth.sessions` row | انتهت الجلسة |
| `forbidden` | Anonymous, revoked owner, platform admin, or a caller who is not this shop's owner | غير مسموح |
| `shop_unavailable` | No entitlement row (pending). Also used when the owner membership cannot see financial data | بيانات المحل غير متاحة |
| `shop_not_active` | Entitlement exists and is not in the active window, and this call is a new write | الاشتراك غير نشط |
| `invalid_input` | Null idempotency key, malformed JSON, unknown field, bad version, string outside `^(0|[1-9][0-9]*)$`, fractional wire piastre or milligram, scrap count, zero-weight piece, weight without pieces, empty required row, or shop `time_zone` other than `Africa/Cairo` | البيانات المدخلة غير صالحة |
| `negative_amount` | A cash, milligram, or count value is negative | لا يُقبل مبلغ سالب |
| `overflow` | A parsed integer or a required sum is outside `bigint` | القيمة خارج الحد المسموح |
| `unsupported_category_karat` | Category and karat are not in the catalog | العيار أو الصنف غير مدعوم |
| `duplicate_bucket` | Two stock rows or two scrap rows resolve to the same bucket | تكرار نفس الصنف والعيار |
| `opening_already_confirmed` | This shop already has an opening operation under a different key, including a later retry of a key that lost the race and was rolled back | تم تأكيد الأرصدة الافتتاحية من قبل |
| `payload_mismatch` | This key is already stored for a successful opening whose canonical hash differs | المفتاح لا يطابق البيانات المحفوظة |

`shop_not_active` is the expired-write code from the prompt. Pending stays `shop_unavailable` because pending cannot read or write financial tables.

Procedure inside the transaction. Canonicalize and validate before any hash comparison. Do not change `private.is_active_shop_member` or `private.can_write_shop`.

1. If `auth.uid()` is null, raise `unauthenticated`. If `p_idempotency_key` is null, raise `invalid_input`.
2. If `private.caller_session_accepted()` is false, raise `session_expired`.
3. Require a non-anonymous, non-deleted `auth.users` row for `auth.uid()`. Otherwise raise `forbidden`.
4. Resolve the shop from the caller's non-revoked `owner` membership. No such membership is `forbidden`. Do not read a shop id from the payload.
5. Apply the opening financial-read guard: `private.is_active_shop_member(shop_id)` is true and that shop's entitlement has `starts_at <= now()` on the server clock. No entitlement row, or a future `starts_at`, is pending and raises `shop_unavailable`. Expired entitlements still pass this read guard.
6. Lock `public.shops` for that id with `FOR UPDATE`. Recheck steps 2 through 5 after the lock. A membership, session, user, or entitlement that changed while waiting fails with the same code.
7. If `shops.time_zone` is not `Africa/Cairo`, raise `invalid_input`. Do not rewrite the zone.
8. Canonicalize and validate the payload, including cash fill and array sort. Any validation error raises one of the input codes and does not insert a command row. Build `payload_canonical` as `jsonb` and its SHA-256 from that value's PostgreSQL text form.
9. Lock the existing `financial_command_requests` row for `(shop_id, p_idempotency_key)` with `FOR UPDATE` when it exists. Compare the stored `jsonb` and hash with the canonical value from step 8. A match returns the original success with `replayed` true and does not require `private.can_write_shop`, so an expired shop can still read the committed outcome. A different canonical value raises `payload_mismatch` and writes nothing.
10. If no stored request matches and an opening operation already exists for the shop, raise `opening_already_confirmed` and do not insert this key.
11. Otherwise this call is a new mutation. If `private.can_write_shop(shop_id)` is false, raise `shop_not_active`.
12. Insert the business day, operation, accounts, journals, postings, audit event, outbox row, and command request.
13. Commit only if every insert succeeds. Any failure rolls the transaction back, including the command key.

Lock order: the shop row first; then the command-request row by primary key when it exists; then existing `ledger_accounts` for the shop `ORDER BY id`; then new rows. The second concurrent attempt waits on the shop row. Identical canonical payloads under one key return one operation id. Two different keys for the same uninitialized shop produce one success and one `opening_already_confirmed`, with no partial rows from the loser. Because the loser rolls back, its key is not stored. A later retry of that key returns `opening_already_confirmed`. A retry of the winning key returns the original success.

There is no server-side half-posted state.

### `public.get_opening_status(p_idempotency_key uuid)`

Uses the opening financial-read guard: valid session, non-anonymous non-deleted user, non-revoked owner, `private.is_active_shop_member`, and entitlement `starts_at <= now()`. A missing entitlement and a future `starts_at` are pending and return `shop_unavailable`. Expired entitlements may read. The function reveals nothing about another shop. An expired session raises `session_expired` and does not return the outcome. After the owner signs in again, the same key resolves. A null key is `invalid_input`.

```json
{"status":"absent"}
```

```json
{"status":"completed","operation_id":"uuid"}
```

`absent` means this shop has no stored command for that key. It does not mean the shop is uninitialized: another key may already have confirmed. The client treats `absent` after a lost response as permission to retry the same key and the same canonical payload.

### `public.get_daily_ledger()`

This is a third RPC. It is read-only. `confirm_opening_balances` is the only function that writes. `get_opening_status` does not write. Adding this read RPC is the minimal recommendation so clients receive versioned decimal strings without selecting financial tables directly.

The function reads `public.ledger_account_balances`, a `security_invoker` view. The view sums confirmed `journal_postings` joined to their journals and accounts. It does not read a cached balance column. Pound and gram strings are formatted in SQL from those integer sums: pounds always have two decimal places; grams always have three. No floating numeric casts. The summary matches as soon as `confirm_opening_balances` commits because the postings are in the same transaction.

Read guard matches `get_opening_status`. Expired shops receive the snapshot and `"can_confirm": false`. Pending is `shop_unavailable`.

Uninitialized, same version:

```json
{"read_model_version":1,"state":"uninitialized","entitlement_status":"active","can_confirm":true,"business_day":null,"cash":[],"stock":[],"scrap":[],"feed":[]}
```

`read_model_version` is the JSON integer `1`. Clients parse this object only when that version is 1. A later incompatible shape uses a new integer and a new DTO. Field names and types below belong to version 1.

`can_confirm` is true only when the read guard passes and `private.can_write_shop` is true and no opening operation exists.

Confirmed shape, quantities as strings:

```json
{
  "read_model_version": 1,
  "state": "confirmed",
  "entitlement_status": "active",
  "can_confirm": false,
  "business_day": {"id": "uuid", "business_date": "YYYY-MM-DD", "opened_at": "timestamptz"},
  "cash": [
    {"method": "cash", "label_ar": "نقدي", "piastres": "1000000", "pounds": "10000.00"}
  ],
  "stock": [
    {"category": "worked_jewelry", "label_ar": "مشغولات", "karat": 18, "milligrams": "5000", "grams": "5.000", "count": "3"}
  ],
  "scrap": [
    {"karat": 21, "label_ar": "كسر", "milligrams": "1000", "grams": "1.000"}
  ],
  "feed": [
    {"kind": "opening_balances_confirmed", "label_ar": "رصيد افتتاحي", "operation_id": "uuid", "actor_display_name": "owner name", "occurred_at": "timestamptz", "occurred_at_cairo": "YYYY-MM-DDTHH:MM:SS"}
  ]
}
```

Cash always lists the four methods. Stock and scrap list only accounts that exist. Opening-clearing accounts are omitted. Confirmed zero returns four cash rows at `0` / `0.00`, empty stock and scrap, one feed row, and a business day. `occurred_at` is the server UTC timestamp. `occurred_at_cairo` is that instant formatted in `Africa/Cairo` without relying on the device clock. The feed for this slice is that single opening row: no profit card, no fine-weight card, and no invoice number.

## Migration design

One additive migration. It does not edit historical migrations and does not deploy an Edge Function.

### Tables

All tenant tables have `shop_id uuid not null` referencing `public.shops(id)`. Enable RLS. Revoke direct privileges from `public`, `anon`, and `authenticated`. Grant `SELECT` on the tables and on `public.ledger_account_balances` to `authenticated` only. `SELECT` uses a new helper, `private.opening_financial_visible(shop_id)`, defined as `private.is_active_shop_member(shop_id)` and `shop_entitlements.starts_at <= now()`. That helper does not replace or weaken `private.is_active_shop_member` or `private.can_write_shop`. Expired shops can read. A shop with no entitlement, and a shop whose entitlement has not started, cannot. No `INSERT`, `UPDATE`, or `DELETE` policy is created for `anon` or `authenticated`. Only `confirm_opening_balances` writes. `get_opening_status` and `get_daily_ledger` are read-only. Do not grant the functions to `anon`. Do not revive staff grants or `email_confirmed_at` checks. Platform admins receive no financial policy. The view is `security_invoker`, so the caller's RLS still applies.

`public.business_days`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` primary key | `gen_random_uuid()` |
| `shop_id` | `uuid` | |
| `business_date` | `date` | `(opened_at AT TIME ZONE 'Africa/Cairo')::date` |
| `opened_at` | `timestamptz` | `clock_timestamp()` at confirmation, stored UTC |
| `status` | `text` | `open` for the day this command creates |

Partial unique index on `(shop_id)` where `status = 'open'`. That is the one-open-day rule. The table itself is not unique on `shop_id`, so a later close slice can keep closed history without replacing a whole-table unique constraint. No `closed_at`, no close function, no scheduler, and no reopen path in this slice. The open day remains the sole open day across later midnights.

`public.financial_operations`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` primary key | |
| `shop_id` | `uuid` | |
| `shop_sequence` | `bigint` | `1` for this first operation; unique `(shop_id, shop_sequence)` |
| `kind` | `text` | `opening_balances` for this command |
| `business_day_id` | `uuid` | same shop |
| `actor_user_id` | `uuid` | `auth.uid()` at confirmation |
| `created_at` | `timestamptz` | server clock |

`public.financial_command_requests`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` primary key | |
| `shop_id` | `uuid` | |
| `idempotency_key` | `uuid` | unique `(shop_id, idempotency_key)` |
| `payload_canonical` | `jsonb` | the canonical object |
| `payload_sha256` | `bytea` | 32 bytes |
| `operation_id` | `uuid` | the successful operation |
| `created_at` | `timestamptz` | |

Insert this row only in the successful transaction. Uniqueness does not include `actor_user_id`.

Partial unique index on `financial_operations (shop_id)` where `kind = 'opening_balances'`. Later operation kinds are not blocked by a unique constraint on every row of the shop.

`public.ledger_accounts`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` primary key | |
| `shop_id` | `uuid` | |
| `account_kind` | `text` | `cash_method`, `saleable_metal`, `saleable_count`, `scrap_metal`, `opening_money_clearing`, `opening_gold_clearing`, `opening_count_clearing` |
| `unit_kind` | `text` | `money`, `gold_mg`, or `count` |
| `currency_code` | `text` | `EGP` for money, otherwise null |
| `karat` | `smallint` | null for money and for money clearing |
| `category_code` | `text` | null for cash and for karat-level gold clearing |
| `method_code` | `text` | cash methods only |

No cached balance columns. The authoritative quantity is the sum of `journal_postings.amount` for that account. Cash, saleable, and scrap projections must stay `>= 0`. That check is a deferred constraint on the posting projection, not a stored cache. Clearing projections may be negative and are hidden from the ledger JSON. Unique account identity per shop: method for cash; `(category_code, karat)` for saleable metal and for saleable count; `karat` for scrap and for opening-gold clearing; one opening-money clearing per shop; `(category_code, karat)` for opening-count clearing.

`public.ledger_account_balances` is a `security_invoker` view. Its columns are `shop_id`, `account_id`, `account_kind`, `unit_kind`, `currency_code`, `karat`, `category_code`, `method_code`, and `amount` (`bigint`, the sum of postings, or 0 when the account has no posting). Every view in this migration is `security_invoker`. There is no `security_definer` view.

`public.journals`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` primary key | |
| `shop_id` | `uuid` | |
| `operation_id` | `uuid` | |
| `unit_kind` | `text` | |
| `currency_code` | `text` | |
| `karat` | `smallint` | |
| `bucket_key` | `text` | stable identity of the single bucket in this journal |

`public.journal_postings`

| Column | Type | Notes |
| --- | --- | --- |
| `id` | `uuid` primary key | |
| `shop_id` | `uuid` | |
| `journal_id` | `uuid` | |
| `account_id` | `uuid` | same shop |
| `operation_id` | `uuid` | |
| `amount` | `bigint` | non-zero; positive increases the account |

Same-shop composite foreign keys: each child row references the parent through `(shop_id, parent_id)`, and each parent has a unique `(shop_id, id)`. Postings, journals, operations, accounts, and the business day cannot point at another shop.

A deferred constraint trigger rejects the transaction unless every journal has at least two postings, those postings sum to zero, and each posting's account matches the journal's `unit_kind`, `currency_code`, and `karat`. Metal and count accounts must also match the journal's bucket; the same-karat gold clearing account is the mechanical exception to bucket identity, while money journals may contain multiple cash methods. The explicit zero opening creates no journal. SQL tests assert the view sums equal the postings.

`public.financial_audit_events`

Append-only for `anon`, `authenticated`, and `service_role`: revoke `UPDATE` and `DELETE`. One row per success, action `opening_balances_confirmed`, `actor_user_id`, `shop_id`, `operation_id`, `created_at` default `now()`, and a `jsonb` details object with the business date and operation id. No secrets and no customer data.

`public.financial_outbox`

One row in the same transaction: `event_type = 'opening_balances_confirmed'`, `shop_id`, `operation_id`, `created_at`, `delivered_at` null. The command does not call an external service. A later worker may read the row. This slice does not add that worker.

### Business day

Create the business day in the confirmation transaction. `opened_at` is `timestamptz`. `business_date` is PostgreSQL `(opened_at AT TIME ZONE 'Africa/Cairo')::date`. Tests use a fixed `timestamptz` whose UTC date and Cairo date differ, and they read the zone database rather than a hard-coded offset. If the shop zone is not `Africa/Cairo`, the command fails and writes nothing.

### Catalog checks

A `CHECK` or a private immutable SQL function rejects category and karat pairs outside the catalog. Scrap rows cannot carry a count. The function is the authority; the check documents the same matrix.

## Client integration

Minimum Flutter behavior for the later task. Domain types stay integers or decimal strings and do not import Flutter, Supabase, or storage.

- Keep one idempotency key across a definitive validation failure. Codes `invalid_input`, `negative_amount`, `overflow`, `unsupported_category_karat`, and `duplicate_bucket` do not consume the key. The owner corrects the draft and retries that same key. A new key is not required just because the canonical payload changed after one of those failures.
- An unknown outcome is different. While the response is missing, freeze that payload and that key. Do not edit the draft until `get_opening_status` reconciles it. `completed` loads `get_daily_ledger`. `absent` sends the same frozen payload with the same key. Only after reconciliation may the owner edit.
- Disable the confirm control while the request is in flight. Copy: «بانتظار تأكيد الخادم».
- Do not show success before the success JSON or a `completed` status lookup.
- On a mapped error, keep the draft and show the Arabic copy.
- Parse quantity fields only as decimal strings. Reject a JSON number for money, milligrams, or count.
- Uninitialized active shop: «لم يتم تأكيد الأرصدة الافتتاحية», the entry form, and a separate «تأكيد أرصدة صفرية».
- Review: «مراجعة الأرصدة الافتتاحية».
- Success: «تم تأكيد الأرصدة الافتتاحية», then the summary and the feed row «رصيد افتتاحي».
- Pending shop: existing pending-activation state, no form and no financial read.
- Expired shop: «الاشتراك منتهٍ. العرض للقراءة فقط.» Summary and feed render when an opening exists. Confirmation controls are absent.
- Sale, purchase, expense, transfer, close-day, dispatch, and reset are not offered as working actions.

The React admin dashboard gains no shop-ledger screen in this design. Platform admins cannot read these rows.

## Verification expected of later tasks

SQL tests roll back synthetic fixtures and prove precision, overflow, transport of decimal strings beyond JavaScript's safe integer range, the catalog, conservation, atomic rollback with no command row, replay, mismatch, the business-day zone rule, and the RLS cases in the next-slice prompt. Widget tests cover the Arabic states. This document's gate is a documentation review only.

## Privacy

This contract uses synthetic amounts and stable codes. It does not copy private agreement parties, credentials, or customer data.

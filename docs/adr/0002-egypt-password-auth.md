# Egypt password sign-in without verification

Status: accepted
Implementation: see [Milestone 1 validation](../operations/milestone-1-validation.md) for the subsequent owner-registration slice and its current evidence. Statements below marked planned describe the state when this ADR was accepted; they are not the current delivery status.
Date: 2026-09-26
Owners: product owner
Related decision IDs: D25 (revised), D13 (preserved), D28 (preserved), D10 (preserved as default deny)
Supersedes: D25 only, in [ADR 0001](0001-email-and-expired-shop-access.md)

Staff, partner, invitation, and per-user grant statements in this record are superseded by [ADR 0003](0003-owner-only-shop-access.md). That decision closes D10 and revises D28 to one owner account per shop. The D25 sign-in rule in this record remains accepted. Password recovery is still undesigned. Staff-invitation binding is cancelled, not deferred.

## Context

ElDafttar ERP is an Egypt-only product. Shop users authenticate with Supabase Auth. The backend authorizes shop data with row-level security and role grants. Hiding a control in the Flutter or React client is not authorization.

On 2026-09-24, ADR 0001 accepted D25: owner and staff sign in with a verified email, and an invitation is accepted only by that verified email. The product owner replaces that sign-in rule. Sign-in is a password check against one Supabase Auth user that holds both an Egyptian phone number and an email address. The product does not send email verification, a one-time code, or an SMS confirmation. The phone and the email are login identifiers. They are not proof that the person owns the handset or the mailbox.

ADR 0001 remains in force for everything except D25. D13 still blocks shop writes after subscription expiry and still allows existing authorized members to read and export within grants they already hold. D28 still attaches one subscription entitlement to one shop, shared by invited staff, with individual grants. D10 stays undecided, and visibility stays default deny. D14 retention and deletion stay separately undecided. This record does not set session duration, refresh lifetime, or any other auth timing.

How a person recovers a password, and how a staff invitation binds to a person, are not decided here. Those flows need a later design. This record does not implement them.

Shop example. A gold shop in Giza is created by an owner who submits an owner name, a business name, an email, an Egyptian phone number, the governorate Giza, and a password. The shop is stored with time zone Africa/Cairo, has no trial, and stays pending activation until a separate activation step. The owner later signs in with the same phone and password, or with the same email and password. Both paths resolve to the same Supabase Auth user. The password is held by Supabase Auth only. Shop tables do not store it. Because neither identifier was verified, a successful login does not prove that this person controls that phone or that email. When the subscription later expires, D13 still applies: shop writes stop, and existing authorized members can still read and export within their grants. Staff invitation and password recovery are out of scope until a later ADR.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| D25 as accepted in ADR 0001. Verified email only | One confirmed mailbox for sign-in, recovery, and invitation acceptance. | Rejected on 2026-09-26. It blocks phone-and-password sign-in and requires email verification the owner no longer wants. |
| Phone and password only, email as a contact field | Matches shops that lead with a mobile number. | Drops email-and-password sign-in, which the owner requires on the same account. |
| Egyptian phone plus password, or email plus password, on one Supabase Auth user, with no email verification, OTP, or SMS | Matches the owner decision: Egypt-only, two login identifiers, one account, no confirmation messages. | Identifiers are unverified. Login does not prove ownership of the phone or the mailbox. Recovery and staff-invitation binding are unsolved and must not be improvised in clients. |
| Either identifier, with SMS or email OTP before the session | Stronger claim that the person controls the identifier. | The owner forbids OTP and SMS confirmation as well as email verification. |

D13, D28, and D10 were not reopened. Their ADR 0001 options stay as decided or still undecided there.

## Decision

Accepted by the product owner on 2026-09-26. Nothing in this record is implemented by writing this ADR.

**D25, revised.** Owner sign-in accepts either an Egyptian phone number plus password or an email address plus password. Both identifiers belong to one Supabase Auth user. Submitting one identifier with the password must resolve to that same user as submitting the other. The product does not require or send email verification, a one-time code, or an SMS confirmation. A successful password check is authentication only. It never establishes that the user owns, controls, or is legally entitled to the phone number or the email address. Copy, audit text, admin labels, and support notes must not describe the identifier as verified, confirmed, or proof of ownership.

**Owner signup, planned.** Creating an owner account requires all of: owner name, business name, email, Egyptian phone, Egyptian governorate, and password. Missing any field fails the signup and creates no shop. The password is sent only to Supabase Auth. No shop table, profile table, or client store keeps the password or a password hash. The new shop has no trial period and remains pending activation. Pending activation is not an active entitlement and does not grant shop writes. The default shop time zone is Africa/Cairo. Server-generated timestamps stay UTC, consistent with project rules. Display of shop dates uses that shop time zone. This record does not define session length.

**Normalization and uniqueness, planned.** Phone values are normalized to one canonical Egyptian form before uniqueness checks and before they are stored as the Auth phone identifier: country code +20, national significant digits, with accepted phone formats defined and tested in the implementation contract, no spaces or punctuation in the stored identifier. Equivalent local spellings of the same phone number (leading zero, +20, 0020) map to that same canonical value. Email values are trimmed and compared case-insensitively for uniqueness. The canonical phone, the canonical email, and the Supabase Auth user id are each unique. A second signup that reuses either identifier fails and must not attach a second Auth user or a second shop to the existing identifier. Shop profile stores owner name, business name, the canonical phone, the canonical email, and the governorate as profile data, not as a second credential store.

**Governorate, planned.** The governorate is one of the Egyptian governorates and is persisted on the shop profile through a protected write path. Clients do not update it by writing the column directly. Changing it later, if a later decision allows a change, goes through that same protected path. A signup governorate outside Egypt is rejected.

**Preserved decisions.** D13 from ADR 0001 stands: after expiry, shop writes are rejected for every member, and existing authorized members may read and export within grants they already hold. Login remaining available under D13 is still login to an existing membership; it does not verify the identifier and does not create a trial. D28 stands: one entitlement per shop, shared by invited staff, with individual grants. D10 stands as undecided with default deny for full day totals, other employees' operations, customer phone numbers, and reports. Staff invitation identity binding is not specified and must not treat an unverified phone or email as acceptance of an invitation. Password recovery is not specified.

**Failure and retry, planned.** Signup and login show success, pending, or failure. A failed or duplicate submission creates no second Auth user and no second shop. Retries use an idempotency key so a repeated signup does not create duplicate shops. Authorization remains in row-level security and server functions.

**Rollout, planned and not started.** Backend Auth and shop-profile behavior, both clients, and Supabase Auth project configuration (email confirmation off, phone OTP and SMS confirmation off, password sign-in on, Egyptian phone accepted) ship together. A client that still requires verified email, or a project that still sends confirmation mail or SMS, does not match this decision. No migration, credential, or customer data change is part of accepting this ADR.

## Data and compatibility impact

- Planned identity shape: one `auth.users` row with both email and Egyptian phone set, password stored only by Supabase Auth. Shop and profile tables store names, canonical email, canonical phone, governorate, Africa/Cairo as the default time zone, pending activation, and no trial. They do not store passwords.
- Planned uniqueness: one Auth user per canonical email and per canonical Egyptian phone. Signup conflict fails closed.
- Planned shop row: created only after Auth user creation succeeds; if shop persistence fails, the compensating path must not leave a usable shop, and a retry must not create a second shop. Exact compensation is part of the later implementation design.
- D13, D28, and default-deny D10 policies are unchanged. Pending activation is not an entitlement and does not open shop writes.
- There is no production schema to migrate in this task (D01). Rollback of the sign-in rule is a superseding ADR plus coordinated Auth configuration, not a data backfill.
- Privacy: phone and email are account identifiers. They are unverified. Do not commit real people's addresses or numbers in fixtures. Do not log passwords. This ADR adds no customer data.

## Verification

The following tests are planned. They are not implemented and were not run for this record.

- Normalization: `010xxxxxxxx`, `+2010xxxxxxxx`, and `002010xxxxxxxx` for the same Egyptian mobile resolve to one canonical phone and one Auth user. A different phone must not alias the original identifier. Email uniqueness is case-insensitive.
- Same-user login: phone plus correct password and email plus correct password return the same Auth user. The wrong password fails on both identifiers. No email verification, OTP, or SMS is sent or required.
- Signup rejects a missing owner name, business name, email, phone, governorate, or password, and rejects a non-Egyptian phone or a non-Egyptian governorate. The created shop has time zone Africa/Cairo, no trial, and pending activation. Shop tables contain no password.
- Profile and governorate writes that bypass the protected path fail, including a crafted `shop_id`.
- Failure and retry: an in-flight duplicate signup does not create two users or two shops. A failed request surfaces failure and leaves no partial usable shop. Idempotent retry reconciles to the single created shop.
- Preserved behavior stays covered by the ADR 0001 tests: expired shop rejects writes and allows granted reads and exports (D13); one entitlement per shop (D28); unresolved employee visibility remains default deny until D10 is accepted.
- Login success is not asserted as ownership of the phone or email. Recovery and staff-invitation binding have no tests in this ADR because they have no design yet.
- Rollout check, when implementation exists: backend, Flutter, React, and Supabase Auth settings match this decision together. Until then, clients must not present this sign-in as operational.
- Acceptance owner: product owner for the D25 replacement and for preserving D13, D28, and D10 default deny. Engineering writes the tests when implementation is scheduled. No session duration is in scope.

## Files

This decision and its synchronized scope, delivery plan, engineering guidance, database plan, requirements matrix, and validation record are documentation only. Executable code, migrations and remote project settings are unchanged.

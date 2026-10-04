# ADR 0008: email password recovery working rule

- Status: user-authorized working rule for the Flutter email recovery slice, dated 2026-10-01. Not a product-owner or shop-domain signature.
- Date: 2026-10-01
- Decision owner: user authorization to implement this slice. No stakeholder signature is recorded.
- Supersedes: the statements that password recovery is undesigned, in ADR 0002, ADR 0003, and the decision register's D25 note, for this slice only.

## Context

ADR 0002 accepts Egypt-only email/password or Egyptian phone/password sign-in and forbids email verification, OTP, and SMS confirmation. It left password recovery undecided because neither identifier is proof of ownership. The user authorized a bounded email-link recovery implementation. SMS and phone OTP stay out of scope. Login and signup stay as they are.

Shop example. The Giza owner cannot remember the password. The app asks for the account email and always shows the same Arabic acknowledgement, whether or not that mailbox exists. Supabase sends one recovery link to `eldafttar://auth/recovery`. Opening that link on the same installation creates a recovery session. The shop stays closed until a new password is saved and that session is ended. An expired or foreign link does not open the shop.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| Leave recovery undesigned | No new mail or session behavior | The owner cannot regain a forgotten password |
| SMS or phone OTP | Reaches the handset already stored on the account | The accepted sign-in rule forbids SMS and OTP |
| Email link through `resetPasswordForEmail`, shop closed until the password is saved | Uses the installed Supabase Auth client and does not add a second credential store | The mailbox is still unverified. PKCE requires the same installation that requested the mail. The hosted redirect allow-list is an operator step |

## Decision

This slice uses email recovery only.

- The client calls `resetPasswordForEmail` with the fixed redirect `eldafttar://auth/recovery`. No caller-supplied redirect is accepted.
- A syntactically valid email always produces the same acknowledgement, including `user_not_found`. Transport and rate-limit failures use one generic Arabic failure. Copy does not say the mailbox was verified.
- The new password is sent only to Supabase Auth from an authenticated recovery session. Shop tables and application stores do not keep the password, the recovery access token, or the refresh token.
- While that session exists, shop data stays closed. Saving the password signs the recovery session out. The owner then signs in with the new password. A repeated save without a recovery session does not call Auth again.
- Expired, invalid, and non-recovery callbacks do not open the shop. Abandoning the screen signs the recovery session out.
- Android, iOS, and Windows accept only that callback scheme and path. Windows registers `eldafttar` for the current user and the running executable.

This rule does not change registration, login, RLS, or financial workflows. It does not prove the person controls the mailbox.

## Data and compatibility impact

No schema migration and no remote Auth change is part of this record. Hosted and local Supabase projects must allow exactly `eldafttar://auth/recovery` and must be able to send recovery mail while signup confirmation, phone OTP, and SMS stay off. Old clients keep login and signup and simply have no recovery control. Rollback is a superseding ADR plus removing that redirect URL. The PKCE code verifier remains in the Auth client's own storage on the requesting installation; another device cannot exchange the code.

## Verification

Local HTTP and widget tests cover the acknowledgement, the fixed redirect, the shop lock, expired and untrusted links, and a repeated save. Synthetic 320 and 1440 light/dark captures are widget renders under `app/build/recovery-review`, not device proof. This ADR does not claim a hosted mailbox, a real device link, or stakeholder acceptance.

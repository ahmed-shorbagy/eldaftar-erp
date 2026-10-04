# Email password recovery configuration

This is the operator checklist for the Flutter recovery slice in [ADR 0008](../adr/0008-email-password-recovery.md). Writing this file does not change a hosted project, send a message, or prove that a mailbox received a link.

## Required Auth settings

Keep the ADR 0002 sign-in settings:

- Email confirmation for signup stays off.
- Phone OTP and SMS confirmation stay off.
- Email/password and Egyptian phone/password sign-in stay on.

Recovery is a separate Auth email. The project must have a working Auth mail path (hosted SMTP or the local mail catcher). Signup confirmation being off does not by itself send the recovery message.

In Authentication URL configuration, allow exactly:

```text
eldafttar://auth/recovery
```

Do not add a wildcard, a second mobile scheme, or an open web redirect. The local CLI file `supabase/config.toml` lists that same URL under `additional_redirect_urls`. On 2026-10-04, after the user's dashboard sign-in and explicit approval, the exact callback was saved and verified for development project `xchapwvmvoefriqcxtvn`; the site URL remained unchanged. [Configuration evidence](../reviews/milestones-0-3-2026-10-04/validation.md).

The Flutter client sends that URL as `redirectTo` on `resetPasswordForEmail` and ignores every other callback. The installed client uses the PKCE flow. The code verifier stays in the Auth client's storage on the installation that requested the message, so the link has to be opened on that same Android, iOS, or Windows installation. A link opened elsewhere fails as an invalid callback and does not open the shop.

## Client callback wiring

- Android: `eldafttar` / host `auth` / path `/recovery` on the main activity.
- iOS: URL scheme `eldafttar` in `CFBundleURLTypes`.
- Windows: on launch, the running executable registers the current-user protocol `eldafttar` and forwards a later link to the existing window. The command is `"<this executable>" "%1"`.

No application store receives the password or the recovery tokens. The Auth SDK may still persist an ordinary password session. A session whose access token `amr` method is `recovery` is not persisted by the app wrapper and cannot open shop data before the new password is saved.

## What remains unverified

SMTP delivery, a real device deep link, and a restarted Windows protocol handler were not exercised here. Local client tests and widget captures are not that evidence. Hosted redirect configuration is verified separately above.

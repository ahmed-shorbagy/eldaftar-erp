# ADR 0030: Minimum app version and forced update

Status: implemented, locally verified and development-deployed for the bounded ADM-04 slice on 2026-10-25. [Validation](../reviews/app-version-forced-update-2026-10-25/validation.md), [deployment/preservation](../reviews/app-version-forced-update-2026-10-25/deployment.md). Soft optional-update banners, Help, broadcasts, retention and ADM-07 contact/location remain separate. Frontend publication and owner acceptance remain pending.

Related requirement IDs: ADM-04
Supersedes: none. Reuses `private.admin_subscriber_gate()` from [ADR 0027](0027-admin-subscriber-directory.md).

## Context

PAGES requires that when an update is required, the user must download it. Platform administrators need a way to set a minimum Flutter client version per Android, iOS and Windows without shipping a new backend release for every policy change. Ordinary shop owners must not gain admin or financial access through this path. Soft “please update” banners are out of scope for this slice.

## Options considered

| Option | Benefits | Costs and risks |
| --- | --- | --- |
| A. Hard-code minimums in each client binary | No server round-trip | Cannot raise the floor without a store release that old clients may refuse |
| B. Server policy with blocking full-screen gate | Admins can raise the floor immediately; PAGES “يلزم” is satisfied | Needs careful pre-login read and fail-open rules when the policy cannot be fetched |
| C. Soft in-app banner only | Less disruptive | Does not meet the forced-download requirement |

## Decision

Option B.

Platforms are `android`, `ios` and `windows`. Comparison uses semantic `major.minor.patch` from the client build name. Build numbers are displayed but not compared. A client strictly below the platform minimum is blocked with a non-dismissible Arabic full-screen screen and must not reach Auth shop data, ledger or staff count. Equal or newer versions pass with no notice. A missing policy row or a null minimum means no forced update for that platform.

`public.app_version_policies` stores one row per platform: `min_version`, required Arabic `message_ar` when a minimum is set, optional HTTPS `update_url`, `updated_at` and `updated_by`. RLS is enabled with no table grants to `anon` or `authenticated`.

`public.get_app_version_policy_v1()` is a security-definer read granted to `anon` and `authenticated` so the gate works before login. It returns only platform, min version, message and update URL. `public.admin_get_app_version_policy_v1()` and `public.admin_set_app_version_policy_v1(...)` require `private.admin_subscriber_gate()`. Setting a minimum requires a non-empty Arabic message and an optional https URL. Clearing uses a null minimum and empty message so blocked clients can be unblocked without a client release. Identical set payloads are idempotent.

Fetch failure policy: if no prior successful policy decision exists, fail open into the normal shell with an Arabic retry control (do not invent a minimum). Once a successful response says the client is blocked, stay blocked until a successful response says clear.

## Data and compatibility impact

Migration `20261025100000_app_version_forced_update.sql` is additive. Old clients ignore the RPCs. No shop entitlement or financial function changes.

## Verification

SQL covers compare edges, admin-only writes, anon read, clear, and table privilege denial. Flutter covers below-min blocker, equal pass, URL open and RTL themes. React covers save/clear/validation/session loss. Development deployment is recorded in [deployment.md](../reviews/app-version-forced-update-2026-10-25/deployment.md). Owner acceptance remains separate.

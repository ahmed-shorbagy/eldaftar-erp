-- Shops, memberships, entitlements, member grants, invitations, and identity audit. Schema only.
-- RLS is enabled and table privileges are revoked from anon and authenticated.
-- No policies are defined, so this migration does not grant row access.

create table public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

alter table public.shops enable row level security;

revoke all on table public.shops from anon, authenticated;

create table public.shop_memberships (
  shop_id uuid not null references public.shops (id),
  user_id uuid not null references auth.users (id),
  role text not null,
  revoked_at timestamptz,
  joined_at timestamptz not null default now(),
  constraint shop_memberships_role_check check (role in ('owner', 'partner', 'employee')),
  constraint shop_memberships_shop_id_user_id_key unique (shop_id, user_id)
);

create index shop_memberships_user_id_idx on public.shop_memberships (user_id);

create table public.shop_entitlements (
  shop_id uuid primary key references public.shops (id),
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  constraint shop_entitlements_expires_after_starts check (expires_at > starts_at)
);

create index shop_entitlements_expires_at_idx on public.shop_entitlements (expires_at);

alter table public.shop_memberships enable row level security;
alter table public.shop_entitlements enable row level security;

revoke all on table public.shop_memberships from anon, authenticated;
revoke all on table public.shop_entitlements from anon, authenticated;

create table public.shop_member_grants (
  shop_id uuid not null references public.shops (id),
  user_id uuid not null,
  permission text not null,
  constraint shop_member_grants_permission_check check (
    permission in (
      'sale',
      'purchase',
      'expense',
      'close_day',
      'inventory_edit',
      'invoice_dispatch',
      'report_view',
      'staff_manage',
      'shop_settings'
    )
  ),
  constraint shop_member_grants_membership_fkey
    foreign key (shop_id, user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint shop_member_grants_pkey primary key (shop_id, user_id, permission)
);

create table public.shop_invitations (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  invited_email text not null,
  role text not null,
  token_hash text not null,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  inviter_user_id uuid not null,
  constraint shop_invitations_role_check check (role in ('owner', 'partner', 'employee')),
  constraint shop_invitations_invited_email_normalized check (
    char_length(invited_email) between 3 and 320
    and invited_email = lower(btrim(invited_email))
    and invited_email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  ),
  constraint shop_invitations_token_hash_check check (token_hash ~ '^[0-9a-f]{64}$'),
  constraint shop_invitations_token_hash_key unique (token_hash),
  constraint shop_invitations_terminal_state_check check (num_nonnulls(accepted_at, revoked_at) <= 1),
  constraint shop_invitations_inviter_membership_fkey
    foreign key (shop_id, inviter_user_id)
    references public.shop_memberships (shop_id, user_id)
);

-- One outstanding invitation per shop and normalized email.
-- Accepted or revoked rows are not in the index, so the address can be invited again.
-- expires_at is omitted: now() is not immutable and cannot be used in an index predicate.
create unique index shop_invitations_active_email_key
  on public.shop_invitations (shop_id, invited_email)
  where accepted_at is null and revoked_at is null;

create index shop_invitations_shop_id_inviter_user_id_idx
  on public.shop_invitations (shop_id, inviter_user_id);

create function public.identity_audit_events_stamp_created_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.created_at := clock_timestamp();
  return new;
end;
$$;

revoke all on function public.identity_audit_events_stamp_created_at() from public, anon, authenticated;

create table public.identity_audit_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  actor_user_id uuid not null,
  action text not null,
  subject_user_id uuid,
  created_at timestamptz not null default now(),
  correlation_id uuid not null,
  details jsonb not null default '{}'::jsonb,
  constraint identity_audit_events_action_check check (
    char_length(btrim(action)) > 0
    and char_length(action) <= 80
  ),
  constraint identity_audit_events_details_object check (jsonb_typeof(details) = 'object'),
  constraint identity_audit_events_details_no_secrets check (
    details::text !~* '"(password|passwd|token|token_hash|secret|access_token|refresh_token|api_key|authorization|cookie|set_cookie|otp|invitation_token|service_role_key|private_key)"[[:space:]]*:'
  ),
  constraint identity_audit_events_actor_membership_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint identity_audit_events_subject_membership_fkey
    foreign key (shop_id, subject_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create trigger identity_audit_events_stamp_created_at
  before insert on public.identity_audit_events
  for each row
  execute function public.identity_audit_events_stamp_created_at();

create index identity_audit_events_shop_id_created_at_idx
  on public.identity_audit_events (shop_id, created_at);

create index identity_audit_events_shop_id_actor_user_id_idx
  on public.identity_audit_events (shop_id, actor_user_id);

create index identity_audit_events_shop_id_subject_user_id_idx
  on public.identity_audit_events (shop_id, subject_user_id);

create index identity_audit_events_correlation_id_idx
  on public.identity_audit_events (correlation_id);

alter table public.shop_member_grants enable row level security;
alter table public.shop_invitations enable row level security;
alter table public.identity_audit_events enable row level security;

revoke all on table public.shop_member_grants from anon, authenticated;
revoke all on table public.shop_invitations from anon, authenticated;
revoke all on table public.identity_audit_events from anon, authenticated;

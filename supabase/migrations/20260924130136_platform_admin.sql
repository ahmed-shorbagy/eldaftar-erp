-- Platform administration is a separate trust boundary from shop membership.
create table public.platform_admins (
  user_id uuid primary key references auth.users(id),
  granted_at timestamptz not null default now()
);
alter table public.platform_admins enable row level security;
revoke all on table public.platform_admins from anon, authenticated;

create function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and exists (
      select 1 from auth.users as identity
      where identity.id = auth.uid()
        and identity.email_confirmed_at is not null
    )
    and exists (
      select 1 from public.platform_admins as admin
      where admin.user_id = auth.uid()
    );
$function$;

revoke all on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

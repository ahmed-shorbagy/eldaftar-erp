-- TEST ONLY: minimal Auth schema for a disposable local PostgreSQL instance.
-- This validates SQL policies/commands, not GoTrue, HTTP or hosted Auth behavior.
-- Never apply this file to a Supabase project or a database containing real data.
do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() <> 'eldafttar_test' then
    raise exception 'local_disposable_database_required';
  end if;
  if to_regclass('auth.users') is not null or to_regclass('public.shops') is not null then
    raise exception 'empty_test_database_required';
  end if;
end;
$guard$;

do $roles$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end;
$roles$;

create schema auth;
create table auth.users (
  id uuid primary key,
  instance_id uuid,
  aud text,
  role text,
  email text,
  phone text,
  encrypted_password text,
  email_confirmed_at timestamptz,
  phone_confirmed_at timestamptz,
  raw_user_meta_data jsonb,
  raw_app_meta_data jsonb,
  is_anonymous boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);
create table auth.sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id),
  created_at timestamptz,
  updated_at timestamptz,
  not_after timestamptz
);
create function auth.uid() returns uuid language sql stable as $fn$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid;
$fn$;
create function auth.jwt() returns jsonb language sql stable as $fn$
  select coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
$fn$;
grant usage on schema auth, public to anon, authenticated, service_role;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to service_role;
alter default privileges in schema public grant all on sequences to service_role;

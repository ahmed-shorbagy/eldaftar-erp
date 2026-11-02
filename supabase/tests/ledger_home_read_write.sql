-- Home RPC must stay volatile. A stable mark makes PostgREST open a
-- read-only transaction, and the shop FOR SHARE then fails with 25006.
-- Fixtures roll back. Never run against hosted data.
begin;
do $guard$ begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_home_lock_[a-z0-9_]+$' then
    raise exception 'dedicated loopback test database required';
  end if;
  if (select provolatile from pg_catalog.pg_proc
      where oid = 'public.get_daily_ledger_home_v1()'::regprocedure)
      is distinct from 'v' then
    raise exception 'home rpc is not volatile';
  end if;
end; $guard$;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values (
  'd1900000-0000-4000-8000-000000000001',
  '00000000-0000-0000-0000-000000000000',
  'authenticated', 'authenticated', 'home-lock@example.test', false, now(), now()
);
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('d2900000-0000-4000-8000-000000000001', 'متجر القفل', 'مالك القفل', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('d2900000-0000-4000-8000-000000000001', 'd1900000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('d2900000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '10 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'd1900000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);

do $home$
declare
  v_home jsonb;
begin
  -- An uninitialized shop still takes the shop share lock inside
  -- get_daily_ledger_v2. A stable home RPC would raise 25006 here.
  v_home := public.get_daily_ledger_home_v1();
  if v_home ->> 'state' is distinct from 'uninitialized'
    or v_home ->> 'read_model_version' is distinct from '1'
    or v_home ->> 'entitlement_status' is distinct from 'active'
    or v_home ->> 'can_confirm' is distinct from 'true'
    or v_home -> 'cash' is distinct from '[]'::jsonb
    or v_home -> 'feed' is distinct from '[]'::jsonb then
    raise exception 'volatile home read drifted %', v_home;
  end if;
end;
$home$;
rollback;

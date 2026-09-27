-- Opening-balance RLS and session tests. Synthetic fixtures roll back with the transaction.
begin;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, deleted_at, created_at, updated_at)
values
  ('81818181-8181-4181-8181-818181818181', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'open-owner@example.test', null, false, null, now(), now()),
  ('82828282-8282-4282-8282-828282828282', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'other-owner@example.test', null, false, null, now(), now()),
  ('83838383-8383-4383-8383-838383838383', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'revoked-owner@example.test', null, false, null, now(), now()),
  ('84848484-8484-4484-8484-848484848484', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'anon-owner@example.test', null, true, null, now(), now()),
  ('85858585-8585-4585-8585-858585858585', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'deleted-owner@example.test', null, false, now(), now(), now()),
  ('86868686-8686-4686-8686-868686868686', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'admin-owner@example.test', now(), false, null, now(), now()),
  ('87878787-8787-4787-8787-878787878787', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pending-owner@example.test', null, false, null, now(), now()),
  ('88888888-8888-4888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'future-owner@example.test', null, false, null, now(), now()),
  ('89898989-8989-4989-8989-898989898989', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'expired-owner@example.test', null, false, null, now(), now()),
  ('8a8a8a8a-8a8a-4a8a-8a8a-8a8a8a8a8a8a', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'stamp-owner@example.test', now(), false, null, now(), now()),
  ('8b8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'readonly-owner@example.test', null, false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone)
values
  ('a1818181-8181-4181-8181-818181818181', 'متجر المالك', 'مالك المتجر', 'Africa/Cairo'),
  ('a2828282-8282-4282-8282-828282828282', 'متجر الآخر', 'مالك الآخر', 'Africa/Cairo'),
  ('a3838383-8383-4383-8383-838383838383', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('a4848484-8484-4484-8484-848484848484', 'متجر مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('a5858585-8585-4585-8585-858585858585', 'متجر محذوف', 'مالك محذوف', 'Africa/Cairo'),
  ('a7878787-8787-4787-8787-878787878787', 'متجر معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('a8888888-8888-4888-8888-888888888888', 'متجر لاحق', 'مالك لاحق', 'Africa/Cairo'),
  ('a9898989-8989-4989-8989-898989898989', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo'),
  ('ab8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', 'متجر القراءة', 'مالك القراءة', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at)
values
  ('a1818181-8181-4181-8181-818181818181', '81818181-8181-4181-8181-818181818181', 'owner', null),
  ('a2828282-8282-4282-8282-828282828282', '82828282-8282-4282-8282-828282828282', 'owner', null),
  ('a3838383-8383-4383-8383-838383838383', '83838383-8383-4383-8383-838383838383', 'owner', now()),
  ('a4848484-8484-4484-8484-848484848484', '84848484-8484-4484-8484-848484848484', 'owner', null),
  ('a5858585-8585-4585-8585-858585858585', '85858585-8585-4585-8585-858585858585', 'owner', null),
  ('a7878787-8787-4787-8787-878787878787', '87878787-8787-4787-8787-878787878787', 'owner', null),
  ('a8888888-8888-4888-8888-888888888888', '88888888-8888-4888-8888-888888888888', 'owner', null),
  ('a9898989-8989-4989-8989-898989898989', '89898989-8989-4989-8989-898989898989', 'owner', null),
  ('ab8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', '8b8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  ('a1818181-8181-4181-8181-818181818181', now() - interval '1 day', now() + interval '30 days'),
  ('a2828282-8282-4282-8282-828282828282', now() - interval '1 day', now() + interval '30 days'),
  ('a3838383-8383-4383-8383-838383838383', now() - interval '1 day', now() + interval '30 days'),
  ('a4848484-8484-4484-8484-848484848484', now() - interval '1 day', now() + interval '30 days'),
  ('a5858585-8585-4585-8585-858585858585', now() - interval '1 day', now() + interval '30 days'),
  ('a8888888-8888-4888-8888-888888888888', now() + interval '1 day', now() + interval '10 days'),
  ('a9898989-8989-4989-8989-898989898989', now() - interval '1 day', now() + interval '30 days'),
  ('ab8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', now() - interval '10 days', now() - interval '1 day');

insert into public.platform_admins (user_id)
values ('86868686-8686-4686-8686-868686868686');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after)
values
  ('d1818181-8181-4181-8181-818181818181', '81818181-8181-4181-8181-818181818181', now(), now(), now() + interval '1 day'),
  ('d1818181-8181-4181-8181-818181818182', '81818181-8181-4181-8181-818181818181', now(), now(), now() - interval '1 minute'),
  ('d2828282-8282-4282-8282-828282828282', '82828282-8282-4282-8282-828282828282', now(), now(), now() + interval '1 day');

create function pg_temp.expect_opening_error(p_key uuid, p_payload jsonb, p_code text)
returns void
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  begin
    perform public.confirm_opening_balances(p_key, p_payload);
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception using message = 'expected_' || p_code;
      elsif sqlerrm is distinct from p_code then
        raise exception using message = 'expected_' || p_code || '_got_' || sqlerrm;
      end if;
  end;
end;
$fn$;

set constraints all deferred;

do $test$
begin
  if has_function_privilege('anon', 'public.confirm_opening_balances(uuid,jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_opening_status(uuid)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_daily_ledger()', 'EXECUTE')
    or has_table_privilege('anon', 'public.journal_postings', 'SELECT')
    or has_table_privilege('authenticated', 'public.journal_postings', 'INSERT')
    or has_table_privilege('authenticated', 'public.financial_audit_events', 'UPDATE')
    or has_table_privilege('authenticated', 'public.financial_audit_events', 'DELETE') then
    raise exception 'financial privileges were too wide';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'business_days', 'financial_operations', 'ledger_accounts', 'journals',
        'journal_postings', 'financial_command_requests', 'financial_audit_events', 'financial_outbox'
      )
      and cmd <> 'SELECT'
  ) then
    raise exception 'a client write policy exists';
  end if;
end;
$test$;

set local role anon;
do $test$
begin
  begin
    perform public.confirm_opening_balances(
      'c1818181-8181-4181-8181-818181818181',
      '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb
    );
    raise exception using message = 'call_succeeded';
  exception
    when insufficient_privilege then
      null;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'anon executed confirm';
      end if;
      raise exception 'anon confirm failed unexpectedly: %', sqlerrm;
  end;
end;
$test$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claim.session_id', '', true);
select pg_temp.expect_opening_error(
  'c1818181-8181-4181-8181-818181818181',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'unauthenticated'
);

select set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
select set_config('request.jwt.claim.session_id', 'd9999999-9999-4999-8999-999999999999', true);
select pg_temp.expect_opening_error(
  'c1818181-8181-4181-8181-818181818181',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'session_expired'
);
select set_config('request.jwt.claim.session_id', 'd1818181-8181-4181-8181-818181818182', true);
select pg_temp.expect_opening_error(
  'c1818181-8181-4181-8181-818181818181',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'session_expired'
);
select set_config('request.jwt.claim.session_id', 'd2828282-8282-4282-8282-828282828282', true);
select pg_temp.expect_opening_error(
  'c1818181-8181-4181-8181-818181818181',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'session_expired'
);

select set_config('request.jwt.claim.session_id', '', true);
select set_config('request.jwt.claim.sub', '83838383-8383-4383-8383-838383838383', true);
select pg_temp.expect_opening_error(
  'c3838383-8383-4383-8383-838383838383',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'forbidden'
);
select set_config('request.jwt.claim.sub', '84848484-8484-4484-8484-848484848484', true);
select pg_temp.expect_opening_error(
  'c4848484-8484-4484-8484-848484848484',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'forbidden'
);
select set_config('request.jwt.claim.sub', '85858585-8585-4585-8585-858585858585', true);
select pg_temp.expect_opening_error(
  'c5858585-8585-4585-8585-858585858585',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'forbidden'
);
select set_config('request.jwt.claim.sub', '86868686-8686-4686-8686-868686868686', true);
do $test$
begin
  if not public.is_platform_admin() then
    raise exception 'platform admin fixture was not recognized';
  end if;
end;
$test$;
select pg_temp.expect_opening_error(
  'c6868686-8686-4686-8686-868686868686',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'forbidden'
);
select set_config('request.jwt.claim.sub', '8a8a8a8a-8a8a-4a8a-8a8a-8a8a8a8a8a8a', true);
select pg_temp.expect_opening_error(
  'ca8a8a8a-8a8a-4a8a-8a8a-8a8a8a8a8a8a',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'forbidden'
);
select set_config('request.jwt.claim.sub', '87878787-8787-4787-8787-878787878787', true);
select pg_temp.expect_opening_error(
  'c7878787-8787-4787-8787-878787878787',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'shop_unavailable'
);
select set_config('request.jwt.claim.sub', '88888888-8888-4888-8888-888888888888', true);
select pg_temp.expect_opening_error(
  'c8888888-8888-4888-8888-888888888888',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'shop_unavailable'
);
select set_config('request.jwt.claim.sub', '8b8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', true);
select pg_temp.expect_opening_error(
  'cb8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'shop_not_active'
);

do $test$
declare
  v_ledger jsonb;
begin
  v_ledger := public.get_daily_ledger();
  if v_ledger ->> 'state' is distinct from 'uninitialized'
    or v_ledger ->> 'entitlement_status' is distinct from 'expired'
    or v_ledger ->> 'can_confirm' is distinct from 'false' then
    raise exception 'expired uninitialized read failed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
select set_config('request.jwt.claim.session_id', 'd1818181-8181-4181-8181-818181818181', true);
do $test$
declare
  v_result jsonb;
begin
  v_result := public.confirm_opening_balances(
    'c1818181-8181-4181-8181-818181818181',
    '{"version":1,"cash":{"cash":"100"},"stock":[],"scrap":[]}'::jsonb
  );
  if v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'live session confirm failed';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '82828282-8282-4282-8282-828282828282', true);
select set_config('request.jwt.claim.session_id', '', true);
do $test$
begin
  if exists (select 1 from public.financial_operations)
    or exists (select 1 from public.journal_postings)
    or (public.get_opening_status('c1818181-8181-4181-8181-818181818181') ->> 'status') is distinct from 'absent' then
    raise exception 'other shop read the opening';
  end if;
end;
$test$;
select set_config('request.jwt.claim.sub', '8b8b8b8b-8b8b-4b8b-8b8b-8b8b8b8b8b8b', true);
do $test$
begin
  if exists (select 1 from public.financial_operations)
    or exists (select 1 from public.ledger_accounts) then
    raise exception 'expired owner saw another shop ledger';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '86868686-8686-4686-8686-868686868686', true);
do $test$
begin
  if exists (select 1 from public.ledger_accounts)
    or exists (select 1 from public.financial_audit_events) then
    raise exception 'platform admin read shop finance';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '87878787-8787-4787-8787-878787878787', true);
do $test$
begin
  if exists (select 1 from public.business_days) then
    raise exception 'pending shop read a business day';
  end if;
end;
$test$;

do $test$
begin
  insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
  values (
    'a1818181-8181-4181-8181-818181818181',
    'b1818181-8181-4181-8181-818181818181',
    'b1818181-8181-4181-8181-818181818182',
    'b1818181-8181-4181-8181-818181818183',
    1
  );
  raise exception 'authenticated insert was accepted';
exception
  when insufficient_privilege then
    null;
end;
$test$;

reset role;
set constraints all immediate;

do $test$
declare
  v_journal uuid;
  v_account uuid;
  v_op uuid;
  v_denied boolean := false;
begin
  select operation.id, posting.journal_id, posting.account_id
    into v_op, v_journal, v_account
  from public.financial_operations as operation
  join public.journal_postings as posting
    on posting.operation_id = operation.id
   and posting.shop_id = operation.shop_id
  where operation.shop_id = 'a1818181-8181-4181-8181-818181818181'
  limit 1;
  begin
    insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
    values ('a2828282-8282-4282-8282-828282828282', v_journal, v_account, v_op, 1);
  exception
    when foreign_key_violation then
      v_denied := true;
  end;
  if not v_denied then
    raise exception 'cross-shop posting was accepted';
  end if;
end;
$test$;

do $test$
declare
  v_denied boolean := false;
begin
  begin
    update public.financial_audit_events
    set action = 'tamper'
    where shop_id = 'a1818181-8181-4181-8181-818181818181';
  exception
    when others then
      if sqlerrm = 'audit_append_only' then
        v_denied := true;
      else
        raise exception 'audit update failed unexpectedly: %', sqlerrm;
      end if;
  end;
  if not v_denied then
    raise exception 'audit update was accepted';
  end if;
end;
$test$;

set constraints all deferred;
set local role authenticated;
select set_config('request.jwt.claim.sub', '89898989-8989-4989-8989-898989898989', true);
select set_config('request.jwt.claim.session_id', '', true);
select public.confirm_opening_balances(
  'c9898989-8989-4989-8989-898989898989',
  '{"version":1,"cash":{"cash":"50"},"stock":[],"scrap":[]}'::jsonb
);
reset role;
update public.shop_entitlements
set expires_at = now() - interval '1 minute'
where shop_id = 'a9898989-8989-4989-8989-898989898989';
set local role authenticated;
select set_config('request.jwt.claim.sub', '89898989-8989-4989-8989-898989898989', true);
do $test$
declare
  v_ledger jsonb;
  v_status jsonb;
begin
  v_status := public.get_opening_status('c9898989-8989-4989-8989-898989898989');
  v_ledger := public.get_daily_ledger();
  if v_status ->> 'status' is distinct from 'completed'
    or v_ledger ->> 'entitlement_status' is distinct from 'expired'
    or v_ledger ->> 'can_confirm' is distinct from 'false'
    or (v_ledger -> 'cash' -> 0 ->> 'piastres') is distinct from '50' then
    raise exception 'expired read of a confirmed opening failed';
  end if;
end;
$test$;
select pg_temp.expect_opening_error(
  'c9898989-8989-4989-8989-898989898999',
  '{"version":1,"cash":{"cash":"1"},"stock":[],"scrap":[]}'::jsonb,
  'opening_already_confirmed'
);
reset role;

set constraints all immediate;
select 'opening_rls_passed' as test_result;
rollback;

-- Opening-balance command tests. Synthetic fixtures, one transaction, ROLLBACK.
-- This session is a single connection. It does not claim a concurrent race.
begin;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at)
values
  ('71717171-7171-4171-8171-717171717171', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'retry-owner@example.test', null, false, now(), now()),
  ('72727272-7272-4272-8272-727272727272', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'example-owner@example.test', null, false, now(), now()),
  ('73737373-7373-4373-8373-737373737373', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zero-owner@example.test', null, false, now(), now()),
  ('74747474-7474-4474-8474-747474747474', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'transport-owner@example.test', null, false, now(), now()),
  ('75757575-7575-4575-8575-757575757575', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'empty-owner@example.test', null, false, now(), now()),
  ('76767676-7676-4676-8676-767676767676', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'zone-owner@example.test', null, false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone)
values
  ('a1717171-7171-4171-8171-717171717171', 'متجر التصحيح', 'مالك التصحيح', 'Africa/Cairo'),
  ('a2727272-7272-4272-8272-727272727272', 'متجر المثال', 'مالك المثال', 'Africa/Cairo'),
  ('a3737373-7373-4373-8373-737373737373', 'متجر الصفر', 'مالك الصفر', 'Africa/Cairo'),
  ('a4747474-7474-4474-8474-747474747474', 'متجر النقل', 'مالك النقل', 'Africa/Cairo'),
  ('a5757575-7575-4575-8575-757575757575', 'متجر بلا أرصدة', 'مالك بلا أرصدة', 'Africa/Cairo'),
  ('a6767676-7676-4676-8676-767676767676', 'متجر المنطقة', 'مالك المنطقة', 'UTC');

insert into public.shop_memberships (shop_id, user_id, role)
values
  ('a1717171-7171-4171-8171-717171717171', '71717171-7171-4171-8171-717171717171', 'owner'),
  ('a2727272-7272-4272-8272-727272727272', '72727272-7272-4272-8272-727272727272', 'owner'),
  ('a3737373-7373-4373-8373-737373737373', '73737373-7373-4373-8373-737373737373', 'owner'),
  ('a4747474-7474-4474-8474-747474747474', '74747474-7474-4474-8474-747474747474', 'owner'),
  ('a5757575-7575-4575-8575-757575757575', '75757575-7575-4575-8575-757575757575', 'owner'),
  ('a6767676-7676-4676-8676-767676767676', '76767676-7676-4676-8676-767676767676', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values
  ('a1717171-7171-4171-8171-717171717171', now() - interval '1 day', now() + interval '30 days'),
  ('a2727272-7272-4272-8272-727272727272', now() - interval '1 day', now() + interval '30 days'),
  ('a3737373-7373-4373-8373-737373737373', now() - interval '1 day', now() + interval '30 days'),
  ('a4747474-7474-4474-8474-747474747474', now() - interval '1 day', now() + interval '30 days'),
  ('a5757575-7575-4575-8575-757575757575', now() - interval '1 day', now() + interval '30 days'),
  ('a6767676-7676-4676-8676-767676767676', now() - interval '1 day', now() + interval '30 days');

create function pg_temp.opening_row_counts()
returns jsonb
language sql
security invoker
set search_path = ''
as $fn$
  select jsonb_build_object(
    'operations', (select count(*) from public.financial_operations),
    'postings', (select count(*) from public.journal_postings),
    'accounts', (select count(*) from public.ledger_accounts),
    'journals', (select count(*) from public.journals),
    'days', (select count(*) from public.business_days),
    'audit', (select count(*) from public.financial_audit_events),
    'commands', (select count(*) from public.financial_command_requests),
    'outbox', (select count(*) from public.financial_outbox)
  );
$fn$;

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

-- Fixed instant: Cairo calendar date comes from pg_timezone_names, not a hard-coded offset.
do $test$
declare
  v_at timestamptz := timestamptz '2026-01-15 23:30:00+00';
  v_cairo date;
  v_utc date;
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = 'Africa/Cairo') then
    raise exception 'cairo time zone is not installed';
  end if;
  v_cairo := private.cairo_business_date(v_at);
  v_utc := (v_at at time zone 'UTC')::date;
  if v_cairo = v_utc then
    raise exception 'fixed instant did not separate Cairo and UTC dates';
  end if;
  if v_cairo is distinct from (v_at at time zone 'Africa/Cairo')::date then
    raise exception 'cairo business date drifted from the zone database';
  end if;
end;
$test$;

do $test$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'ledger_accounts'
      and column_name in ('balance', 'cached_balance')
  ) then
    raise exception 'cached balance column exists';
  end if;
  if to_regprocedure('public.close_business_day()') is not null then
    raise exception 'close function was added in this slice';
  end if;
end;
$test$;

set constraints all deferred;

create temp table opening_baseline as
select pg_temp.opening_row_counts() as counts;

set local role authenticated;
select set_config('request.jwt.claim.sub', '71717171-7171-4171-8171-717171717171', true);
select set_config('request.jwt.claim.session_id', '', true);

select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"1.25","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"0"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1.830","count":"1"}],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"1e3"},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"shop_id":"a1717171-7171-4171-8171-717171717171","cash":{},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":null},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":1830,"count":"1"}],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"-1"},"stock":[],"scrap":[]}'::jsonb,
  'negative_amount'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1"},{"category":"worked_jewelry","karat":18,"milligrams":"500","count":"1"}],"scrap":[]}'::jsonb,
  'duplicate_bucket'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":24,"milligrams":"1000","count":"1"}],"scrap":[]}'::jsonb,
  'unsupported_category_karat'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"bullion","karat":21,"milligrams":"1000","count":"1"}],"scrap":[]}'::jsonb,
  'unsupported_category_karat'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"coin","karat":18,"milligrams":"1000","count":"1"}],"scrap":[]}'::jsonb,
  'unsupported_category_karat'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[],"scrap":[{"karat":21,"milligrams":"1000","count":"1"}]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"0","count":"1"}],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"0"}],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1000"}],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"9223372036854775808"},"stock":[],"scrap":[]}'::jsonb,
  'overflow'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  jsonb_build_object(
    'version', 1,
    'cash', jsonb_build_object('cash', repeat('9', 140000)),
    'stock', '[]'::jsonb,
    'scrap', '[]'::jsonb
  ),
  'overflow'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[null],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[18],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[],"scrap":[null]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[],"scrap":["21"]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1818181-8181-4181-8181-818181818181',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1"},{"category":"bullion","karat":21,"milligrams":"1000","count":"1"}],"scrap":[]}'::jsonb,
  'unsupported_category_karat'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"4611686018427387904","wallet":"4611686018427387904"},"stock":[],"scrap":[]}'::jsonb,
  'overflow'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"4611686018427387904","count":"1"},{"category":"coin","karat":21,"milligrams":"4611686018427387904","count":"1"}],"scrap":[]}'::jsonb,
  'overflow'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1","count":"4611686018427387904"},{"category":"worked_jewelry","karat":14,"milligrams":"1","count":"4611686018427387904"}],"scrap":[]}'::jsonb,
  'overflow'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":1,"cash":{"cash":"01"},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  '{"version":"1","cash":{},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
select pg_temp.expect_opening_error(
  'c1717171-7171-4171-8171-717171717171',
  null,
  'invalid_input'
);

do $test$
declare
  v_status jsonb;
begin
  v_status := public.get_opening_status('c1717171-7171-4171-8171-717171717171');
  if v_status ->> 'status' is distinct from 'absent' then
    raise exception 'failed key was stored';
  end if;
  v_status := public.get_opening_status('c1818181-8181-4181-8181-818181818181');
  if v_status ->> 'status' is distinct from 'absent' then
    raise exception 'valid row then invalid pair consumed the key';
  end if;
  if exists (
    select 1 from public.financial_command_requests
    where idempotency_key = 'c1818181-8181-4181-8181-818181818181'
  ) then
    raise exception 'valid row then invalid pair stored a command';
  end if;
end;
$test$;

reset role;
set constraints all immediate;
do $test$
begin
  if pg_temp.opening_row_counts() is distinct from (select counts from opening_baseline) then
    raise exception 'validation failure left financial rows';
  end if;
end;
$test$;
set constraints all deferred;

set local role authenticated;
select set_config('request.jwt.claim.sub', '76767676-7676-4676-8676-767676767676', true);
select pg_temp.expect_opening_error(
  'c6767676-7676-4676-8676-767676767676',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb,
  'invalid_input'
);
reset role;
do $test$
begin
  if (select time_zone from public.shops where id = 'a6767676-7676-4676-8676-767676767676') is distinct from 'UTC' then
    raise exception 'non-Cairo zone was rewritten';
  end if;
  if exists (
    select 1 from public.financial_operations
    where shop_id = 'a6767676-7676-4676-8676-767676767676'
  ) then
    raise exception 'rejected zone wrote an operation';
  end if;
end;
$test$;
update public.shops
set time_zone = 'Africa/Cairo'
where id = 'a6767676-7676-4676-8676-767676767676';

set local role authenticated;
select set_config('request.jwt.claim.sub', '71717171-7171-4171-8171-717171717171', true);
do $test$
declare
  v_result jsonb;
  v_ledger jsonb;
begin
  v_result := public.confirm_opening_balances(
    'c1717171-7171-4171-8171-717171717171',
    '{"version":1,"cash":{"cash":"125"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"1830","count":"1"}],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' or v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'corrected retry did not commit';
  end if;
  v_ledger := public.get_daily_ledger();
  if v_ledger ->> 'state' is distinct from 'confirmed'
    or (v_ledger -> 'cash' -> 0 ->> 'piastres') is distinct from '125'
    or (v_ledger -> 'cash' -> 0 ->> 'pounds') is distinct from '1.25'
    or (v_ledger -> 'stock' -> 0 ->> 'milligrams') is distinct from '1830'
    or (v_ledger -> 'stock' -> 0 ->> 'grams') is distinct from '1.830'
    or (v_ledger -> 'stock' -> 0 ->> 'count') is distinct from '1'
    or jsonb_typeof(v_ledger -> 'stock' -> 0 -> 'milligrams') is distinct from 'string' then
    raise exception 'precision display mismatch';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '75757575-7575-4575-8575-757575757575', true);
do $test$
declare
  v_ledger jsonb;
begin
  v_ledger := public.get_daily_ledger();
  if v_ledger ->> 'state' is distinct from 'uninitialized'
    or v_ledger ->> 'can_confirm' is distinct from 'true'
    or v_ledger -> 'business_day' is distinct from 'null'::jsonb
    or v_ledger -> 'cash' is distinct from '[]'::jsonb
    or (v_ledger ->> 'read_model_version') is distinct from '1' then
    raise exception 'uninitialized ledger was not explicit';
  end if;
  if exists (select 1 from public.business_days where shop_id = 'a5757575-7575-4575-8575-757575757575') then
    raise exception 'uninitialized shop has a business day';
  end if;
end;
$test$;

select set_config('request.jwt.claim.sub', '73737373-7373-4373-8373-737373737373', true);
do $test$
declare
  v_result jsonb;
  v_ledger jsonb;
begin
  v_result := public.confirm_opening_balances(
    'c3737373-7373-4373-8373-737373737373',
    '{"version":1,"cash":{"cash":"0","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
  );
  if v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'zero opening was replayed';
  end if;
  v_ledger := public.get_daily_ledger();
  if v_ledger ->> 'state' is distinct from 'confirmed'
    or jsonb_array_length(v_ledger -> 'cash') is distinct from 4
    or jsonb_array_length(v_ledger -> 'stock') is distinct from 0
    or jsonb_array_length(v_ledger -> 'scrap') is distinct from 0
    or (v_ledger -> 'cash' -> 0 ->> 'pounds') is distinct from '0.00'
    or jsonb_array_length(v_ledger -> 'feed') is distinct from 1
    or v_ledger -> 'business_day' is null then
    raise exception 'confirmed zero ledger mismatch';
  end if;
end;
$test$;
reset role;
do $test$
begin
  if (select count(*) from public.ledger_accounts where shop_id = 'a3737373-7373-4373-8373-737373737373') <> 4
    or exists (
      select 1 from public.ledger_accounts
      where shop_id = 'a3737373-7373-4373-8373-737373737373'
        and account_kind <> 'cash_method'
    )
    or exists (select 1 from public.journals where shop_id = 'a3737373-7373-4373-8373-737373737373')
    or exists (select 1 from public.journal_postings where shop_id = 'a3737373-7373-4373-8373-737373737373')
    or (select count(*) from public.financial_operations where shop_id = 'a3737373-7373-4373-8373-737373737373') <> 1
    or (select count(*) from public.business_days where shop_id = 'a3737373-7373-4373-8373-737373737373' and status = 'open') <> 1
    or (select count(*) from public.financial_audit_events where shop_id = 'a3737373-7373-4373-8373-737373737373') <> 1
    or (select count(*) from public.financial_outbox where shop_id = 'a3737373-7373-4373-8373-737373737373' and delivered_at is null) <> 1
    or (select count(*) from public.financial_command_requests where shop_id = 'a3737373-7373-4373-8373-737373737373') <> 1 then
    raise exception 'zero opening shape mismatch';
  end if;
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '72727272-7272-4272-8272-727272727272', true);
do $test$
declare
  v_first jsonb;
  v_replay jsonb;
  v_ledger jsonb;
  v_postings bigint;
begin
  v_first := public.confirm_opening_balances(
    'c2727272-7272-4272-8272-727272727272',
    jsonb_build_object(
      'version', 1,
      'cash', jsonb_build_object('wallet', '250000', 'cash', '1000000'),
      'stock', jsonb_build_array(
        jsonb_build_object('category', 'worked_jewelry', 'karat', 21, 'milligrams', '2560', 'count', '1'),
        jsonb_build_object('category', 'coin', 'karat', 21, 'milligrams', '8000', 'count', '1'),
        jsonb_build_object('category', 'worked_jewelry', 'karat', 18, 'milligrams', '5000', 'count', '3'),
        jsonb_build_object('category', 'bullion', 'karat', 24, 'milligrams', '8000', 'count', '2'),
        jsonb_build_object('category', 'worked_jewelry', 'karat', 14, 'milligrams', '1250', 'count', '1')
      ),
      'scrap', jsonb_build_array(
        jsonb_build_object('karat', 21, 'milligrams', '1000'),
        jsonb_build_object('karat', 14, 'milligrams', '500')
      )
    )
  );
  v_postings := (select count(*) from public.journal_postings where shop_id = 'a2727272-7272-4272-8272-727272727272');
  v_replay := public.confirm_opening_balances(
    'c2727272-7272-4272-8272-727272727272',
    '{"version":1,"cash":{"card":"0","cash":"1000000","instant_transfer":"0","wallet":"250000"},"stock":[{"category":"bullion","karat":24,"milligrams":"8000","count":"2"},{"category":"coin","karat":21,"milligrams":"8000","count":"1"},{"category":"worked_jewelry","karat":14,"milligrams":"1250","count":"1"},{"category":"worked_jewelry","karat":18,"milligrams":"5000","count":"3"},{"category":"worked_jewelry","karat":21,"milligrams":"2560","count":"1"}],"scrap":[{"karat":14,"milligrams":"500"},{"karat":21,"milligrams":"1000"}]}'::jsonb
  );
  if v_replay ->> 'replayed' is distinct from 'true'
    or v_replay ->> 'operation_id' is distinct from (v_first ->> 'operation_id')
    or (select count(*) from public.journal_postings where shop_id = 'a2727272-7272-4272-8272-727272727272') <> v_postings then
    raise exception 'canonical replay changed the opening';
  end if;
  if public.get_opening_status('c2727272-7272-4272-8272-727272727272')
      is distinct from jsonb_build_object('status', 'completed', 'operation_id', v_first ->> 'operation_id') then
    raise exception 'status did not return the stored operation';
  end if;
  if (public.get_opening_status('c0000000-0000-4000-8000-000000000099') ->> 'status') is distinct from 'absent' then
    raise exception 'unknown key was not absent';
  end if;
  begin
    perform public.confirm_opening_balances(
      'c2727272-7272-4272-8272-727272727272',
      '{"version":1,"cash":{"cash":"1000000","wallet":"250001"},"stock":[],"scrap":[]}'::jsonb
    );
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'payload_mismatch' then
        if sqlerrm = 'call_succeeded' then
          raise exception 'mismatch was accepted';
        end if;
        raise exception 'expected payload_mismatch got %', sqlerrm;
      end if;
  end;
  begin
    perform public.confirm_opening_balances(
      'c7727272-7272-4272-8272-727272727272',
      '{"version":1,"cash":{"cash":"1"},"stock":[],"scrap":[]}'::jsonb
    );
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'opening_already_confirmed' then
        if sqlerrm = 'call_succeeded' then
          raise exception 'second key was accepted';
        end if;
        raise exception 'expected opening_already_confirmed got %', sqlerrm;
      end if;
  end;
  if (select count(*) from public.financial_command_requests where shop_id = 'a2727272-7272-4272-8272-727272727272') <> 1 then
    raise exception 'rejected key was stored';
  end if;
  v_ledger := public.get_daily_ledger();
  if (select value ->> 'pounds' from jsonb_array_elements(v_ledger -> 'cash') as value where value ->> 'method' = 'cash') is distinct from '10000.00'
    or (select value ->> 'pounds' from jsonb_array_elements(v_ledger -> 'cash') as value where value ->> 'method' = 'instant_transfer') is distinct from '0.00'
    or (select value ->> 'pounds' from jsonb_array_elements(v_ledger -> 'cash') as value where value ->> 'method' = 'wallet') is distinct from '2500.00'
    or (select value ->> 'pounds' from jsonb_array_elements(v_ledger -> 'cash') as value where value ->> 'method' = 'card') is distinct from '0.00'
    or (select value ->> 'grams' from jsonb_array_elements(v_ledger -> 'stock') as value where value ->> 'category' = 'worked_jewelry' and (value ->> 'karat') = '18') is distinct from '5.000'
    or (select value ->> 'grams' from jsonb_array_elements(v_ledger -> 'stock') as value where value ->> 'category' = 'worked_jewelry' and (value ->> 'karat') = '21') is distinct from '2.560'
    or (select value ->> 'grams' from jsonb_array_elements(v_ledger -> 'stock') as value where value ->> 'category' = 'worked_jewelry' and (value ->> 'karat') = '14') is distinct from '1.250'
    or (select value ->> 'count' from jsonb_array_elements(v_ledger -> 'stock') as value where value ->> 'category' = 'bullion') is distinct from '2'
    or (select value ->> 'grams' from jsonb_array_elements(v_ledger -> 'stock') as value where value ->> 'category' = 'coin') is distinct from '8.000'
    or (select value ->> 'grams' from jsonb_array_elements(v_ledger -> 'scrap') as value where (value ->> 'karat') = '21') is distinct from '1.000'
    or (select value ->> 'grams' from jsonb_array_elements(v_ledger -> 'scrap') as value where (value ->> 'karat') = '14') is distinct from '0.500'
    or v_ledger::text like '%opening_money_clearing%'
    or v_ledger::text like '%opening_gold_clearing%'
    or v_ledger::text like '%opening_count_clearing%'
    or (v_ledger -> 'feed' -> 0 ->> 'kind') is distinct from 'opening_balances_confirmed'
    or (v_ledger -> 'feed' -> 0 ->> 'label_ar') is distinct from 'رصيد افتتاحي'
    or (v_ledger -> 'feed' -> 0 ->> 'actor_display_name') is distinct from 'مالك المثال' then
    raise exception 'synthetic ledger projection mismatch';
  end if;
end;
$test$;

reset role;
set constraints all immediate;
do $test$
declare
  v_shop uuid := 'a2727272-7272-4272-8272-727272727272';
begin
  if exists (
    select 1
    from public.journals as journal
    join public.journal_postings as posting on posting.journal_id = journal.id
    where journal.shop_id = v_shop
    group by journal.id
    having count(*) < 2 or sum(posting.amount) <> 0
  ) then
    raise exception 'journal did not conserve';
  end if;
  if (
    select count(*) from public.journals
    where shop_id = v_shop and unit_kind = 'gold_mg' and karat = 21
  ) <> 3 then
    raise exception '21k buckets were netted together';
  end if;
  if (
    select count(distinct bucket_key) from public.journals
    where shop_id = v_shop and unit_kind = 'gold_mg' and karat = 21
  ) <> 3 then
    raise exception '21k journals share a bucket';
  end if;
  if (
    select count(*) from public.journals
    where shop_id = v_shop and unit_kind = 'count' and bucket_key like 'count:scrap:%'
  ) <> 0
    or (select count(*) from public.journals where shop_id = v_shop and unit_kind = 'count') <> 5 then
    raise exception 'count journals were not per piece bucket';
  end if;
  if (
    select count(*) from public.ledger_accounts
    where shop_id = v_shop and account_kind = 'opening_gold_clearing' and karat = 21
  ) <> 1
    or (
      select amount from public.ledger_account_balances
      where shop_id = v_shop and account_kind = 'opening_gold_clearing' and karat = 21
    ) <> -11560 then
    raise exception 'shared 21k gold clearing mismatch';
  end if;
  if exists (
    select 1
    from public.ledger_accounts as account
    left join public.journal_postings as posting
      on posting.shop_id = account.shop_id
     and posting.account_id = account.id
    join public.ledger_account_balances as balance
      on balance.account_id = account.id
    where account.shop_id = v_shop
    group by account.id, balance.amount
    having coalesce(sum(posting.amount), 0) <> balance.amount
  ) then
    raise exception 'view diverged from postings';
  end if;
  if exists (
    select 1
    from public.journal_postings as posting
    join public.ledger_accounts as account on account.id = posting.account_id
    where account.shop_id = v_shop
      and account.method_code in ('instant_transfer', 'card')
  ) then
    raise exception 'zero cash method was posted';
  end if;
  if (
    select amount from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'opening_money_clearing'
  ) <> -1250000 then
    raise exception 'money clearing mismatch';
  end if;
  if exists (
    select 1
    from public.business_days as day
    where day.shop_id = v_shop
      and (
        day.business_date is distinct from private.cairo_business_date(day.opened_at)
        or day.status is distinct from 'open'
      )
  ) or (
    select count(*) from public.business_days where shop_id = v_shop and status = 'open'
  ) <> 1 then
    raise exception 'business day was not the Cairo date of opened_at';
  end if;
  if (
    select actor_user_id from public.financial_operations where shop_id = v_shop
  ) is distinct from '72727272-7272-4272-8272-727272727272'::uuid
    or (
      select actor_user_id from public.financial_audit_events where shop_id = v_shop
    ) is distinct from '72727272-7272-4272-8272-727272727272'::uuid then
    raise exception 'actor was not the owner';
  end if;
  update public.business_days
  set opened_at = opened_at - interval '2 days',
      business_date = private.cairo_business_date(opened_at - interval '2 days')
  where shop_id = v_shop;
  if (select count(*) from public.business_days where shop_id = v_shop and status = 'open') <> 1 then
    raise exception 'a later calendar day closed the open day';
  end if;
end;
$test$;

do $test$
begin
  begin
    insert into public.journals (shop_id, operation_id, unit_kind, currency_code, karat, bucket_key)
    select shop_id, id, 'money', 'EGP', null, 'money'
    from public.financial_operations
    where shop_id = 'a3737373-7373-4373-8373-737373737373';
    set constraints all immediate;
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm = 'call_succeeded' or sqlerrm is distinct from 'journal_imbalance' then
        raise exception 'empty journal was accepted: %', sqlerrm;
      end if;
  end;
end;
$test$;
set constraints all deferred;

do $test$
declare
  v_journal uuid;
  v_account uuid;
  v_clear uuid;
  v_op uuid;
begin
  select id into v_op
  from public.financial_operations
  where shop_id = 'a1717171-7171-4171-8171-717171717171';
  select id into v_account
  from public.ledger_accounts
  where shop_id = 'a1717171-7171-4171-8171-717171717171'
    and account_kind = 'cash_method'
    and method_code = 'instant_transfer';
  select id into v_clear
  from public.ledger_accounts
  where shop_id = 'a1717171-7171-4171-8171-717171717171'
    and account_kind = 'opening_money_clearing';
  begin
    set constraints all deferred;
    insert into public.journals (shop_id, operation_id, unit_kind, currency_code, karat, bucket_key)
    values ('a1717171-7171-4171-8171-717171717171', v_op, 'money', 'EGP', null, 'money')
    returning id into v_journal;
    insert into public.journal_postings (shop_id, journal_id, account_id, operation_id, amount)
    values
      ('a1717171-7171-4171-8171-717171717171', v_journal, v_account, v_op, -1),
      ('a1717171-7171-4171-8171-717171717171', v_journal, v_clear, v_op, 1);
    set constraints all immediate;
    raise exception using message = 'call_succeeded';
  exception
    when others then
      if sqlerrm = 'call_succeeded' or sqlerrm is distinct from 'negative_owned_balance' then
        raise exception 'negative stock was accepted: %', sqlerrm;
      end if;
  end;
end;
$test$;
set constraints all deferred;

set local role authenticated;
select set_config('request.jwt.claim.sub', '74747474-7474-4474-8474-747474747474', true);
do $test$
declare
  v_ledger jsonb;
  v_wide text := '9007199254740993';
begin
  perform public.confirm_opening_balances(
    'c4747474-7474-4474-8474-747474747474',
    jsonb_build_object(
      'version', 1,
      'cash', jsonb_build_object('cash', v_wide),
      'stock', jsonb_build_array(jsonb_build_object(
        'category', 'worked_jewelry',
        'karat', 18,
        'milligrams', v_wide,
        'count', v_wide
      )),
      'scrap', '[]'::jsonb
    )
  );
  v_ledger := public.get_daily_ledger();
  if (v_ledger -> 'cash' -> 0 ->> 'piastres') is distinct from v_wide
    or (v_ledger -> 'cash' -> 0 ->> 'pounds') is distinct from '90071992547409.93'
    or (v_ledger -> 'stock' -> 0 ->> 'milligrams') is distinct from v_wide
    or (v_ledger -> 'stock' -> 0 ->> 'grams') is distinct from '9007199254740.993'
    or (v_ledger -> 'stock' -> 0 ->> 'count') is distinct from v_wide
    or jsonb_typeof(v_ledger -> 'cash' -> 0 -> 'piastres') is distinct from 'string' then
    raise exception 'wide integer transport was corrupted';
  end if;
end;
$test$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '76767676-7676-4676-8676-767676767676', true);
select public.confirm_opening_balances(
  'c6767676-7676-4676-8676-767676767676',
  '{"version":1,"cash":{},"stock":[],"scrap":[]}'::jsonb
);
reset role;

do $test$
declare
  v_shop uuid := 'a1717171-7171-4171-8171-717171717171';
  v_op uuid;
  v_journals bigint;
begin
  select id into v_op
  from public.financial_operations
  where shop_id = v_shop;

  begin
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code, karat, category_code, method_code
    ) values (
      v_shop, 'saleable_metal', 'gold_mg', null, null, 'worked_jewelry', null
    );
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'null karat saleable sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'null karat saleable was accepted';
      end if;
      raise exception 'expected check_violation for null karat saleable got % %', sqlstate, sqlerrm;
  end;
  if exists (
    select 1 from public.ledger_accounts
    where shop_id = v_shop
      and account_kind = 'saleable_metal'
      and category_code = 'worked_jewelry'
      and karat is null
  ) then
    raise exception 'null karat saleable remained';
  end if;

  begin
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code, karat, category_code, method_code
    ) values (
      v_shop, 'cash_method', 'money', null, null, null, 'cash'
    );
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'null currency cash sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'null currency cash was accepted';
      end if;
      raise exception 'expected check_violation for null currency cash got % %', sqlstate, sqlerrm;
  end;
  if exists (
    select 1 from public.ledger_accounts
    where shop_id = v_shop
      and account_kind = 'cash_method'
      and currency_code is null
  ) then
    raise exception 'null currency cash remained';
  end if;

  begin
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code, karat, category_code, method_code
    ) values (
      v_shop, 'opening_gold_clearing', 'gold_mg', null, null, null, null
    );
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'null karat gold clearing sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'null karat gold clearing was accepted';
      end if;
      raise exception 'expected check_violation for null karat gold clearing got % %', sqlstate, sqlerrm;
  end;
  if exists (
    select 1 from public.ledger_accounts
    where shop_id = v_shop
      and account_kind = 'opening_gold_clearing'
      and karat is null
  ) then
    raise exception 'null karat gold clearing remained';
  end if;

  begin
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'gold_mg', null, null, 'gold:worked_jewelry:18'
    );
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'null karat gold journal sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'null karat gold journal was accepted';
      end if;
      raise exception 'expected check_violation for null karat gold journal got % %', sqlstate, sqlerrm;
  end;
  if exists (
    select 1 from public.journals
    where shop_id = v_shop
      and unit_kind = 'gold_mg'
      and karat is null
      and bucket_key = 'gold:worked_jewelry:18'
  ) then
    raise exception 'null karat gold journal remained';
  end if;

  begin
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'gold_mg', null, 18, 'gold:worked_jewelry:18:'
    );
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'trailing colon bucket sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'trailing colon bucket was accepted';
      end if;
      raise exception 'expected check_violation for trailing colon bucket got % %', sqlstate, sqlerrm;
  end;

  begin
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values (
      v_shop, v_op, 'gold_mg', null, 21, 'gold:bullion:21'
    );
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'invalid category karat bucket sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'invalid category karat bucket was accepted';
      end if;
      raise exception 'expected check_violation for invalid category karat bucket got % %', sqlstate, sqlerrm;
  end;

  v_journals := (select count(*) from public.journals where shop_id = v_shop);
  begin
    insert into public.journals (
      shop_id, operation_id, unit_kind, currency_code, karat, bucket_key
    ) values
      (v_shop, v_op, 'gold_mg', null, 18, 'gold:worked_jewelry:18'),
      (v_shop, v_op, 'gold_mg', null, 21, 'gold:bullion:21');
    raise exception using message = 'call_succeeded';
  exception
    when check_violation then
      if sqlstate is distinct from '23514' then
        raise exception 'mixed journal insert sqlstate %', sqlstate;
      end if;
    when others then
      if sqlerrm = 'call_succeeded' then
        raise exception 'valid journal followed by invalid pair was accepted';
      end if;
      raise exception 'expected check_violation for mixed journal insert got % %', sqlstate, sqlerrm;
  end;
  if (select count(*) from public.journals where shop_id = v_shop) is distinct from v_journals then
    raise exception 'invalid pair kept the preceding journal row';
  end if;
  if exists (
    select 1 from public.journals
    where shop_id = v_shop
      and bucket_key in ('gold:worked_jewelry:18:', 'gold:bullion:21')
  ) then
    raise exception 'malformed bucket remained';
  end if;
end;
$test$;

set constraints all immediate;
select 'opening_balances_passed' as test_result;
rollback;

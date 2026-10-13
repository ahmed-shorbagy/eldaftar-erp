-- CRM-01 / CRM-03. Synthetic rows roll back. Customer commands must not post
-- cash, stock, debt, or business-day changes, and must not rewrite invoices.
begin;

create function pg_temp.customer_fail_after_write() returns trigger
language plpgsql as $failure$
begin
  if current_setting('eldafttar.customer_fail_after_write', true) = '1' then
    raise exception 'customer_test_failure';
  end if;
  return new;
end;
$failure$;
create trigger customer_test_failure after insert on public.customer_command_requests
for each row execute function pg_temp.customer_fail_after_write();

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, deleted_at, created_at, updated_at
) values
  ('c1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-owner@example.test', false, null, now(), now()),
  ('c2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-other@example.test', false, null, now(), now()),
  ('c3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-revoked@example.test', false, null, now(), now()),
  ('c4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-anon@example.test', true, null, now(), now()),
  ('c5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-admin@example.test', false, null, now(), now()),
  ('c6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-pending@example.test', false, null, now(), now()),
  ('c7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated', 'customer-expired@example.test', false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('c1222222-2222-4222-8222-222222222222', 'متجر العملاء', 'مالك العملاء', 'Africa/Cairo'),
  ('c2222222-2222-4222-8222-222222222222', 'متجر عملاء آخر', 'مالك آخر', 'Africa/Cairo'),
  ('c3222222-2222-4222-8222-222222222222', 'متجر عملاء موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('c4222222-2222-4222-8222-222222222222', 'متجر عملاء مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('c6222222-2222-4222-8222-222222222222', 'متجر عملاء معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('c7222222-2222-4222-8222-222222222222', 'متجر عملاء منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('c1222222-2222-4222-8222-222222222222', 'c1111111-1111-4111-8111-111111111111', 'owner', null),
  ('c2222222-2222-4222-8222-222222222222', 'c2111111-1111-4111-8111-111111111111', 'owner', null),
  ('c3222222-2222-4222-8222-222222222222', 'c3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('c4222222-2222-4222-8222-222222222222', 'c4111111-1111-4111-8111-111111111111', 'owner', null),
  ('c6222222-2222-4222-8222-222222222222', 'c6111111-1111-4111-8111-111111111111', 'owner', null),
  ('c7222222-2222-4222-8222-222222222222', 'c7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('c1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c4222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('c7222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

insert into public.platform_admins (user_id)
values ('c5111111-1111-4111-8111-111111111111');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('c1818181-8181-4181-8181-818181818181', 'c1111111-1111-4111-8111-111111111111', now(), now(), now() + interval '1 day'),
  ('c1818181-8181-4181-8181-818181818182', 'c1111111-1111-4111-8111-111111111111', now(), now(), now() - interval '1 minute');

create function pg_temp.crm_entitlement(p_expired boolean) returns void language sql security definer set search_path='' as $f$
 update public.shop_entitlements set expires_at=case when p_expired then now()-interval '1 minute' else now()+interval '30 days' end where shop_id='c1222222-2222-4222-8222-222222222222';
$f$;
create temp table customer_ops (
  name text primary key,
  operation_id uuid,
  payload jsonb
);

grant select, insert on customer_ops to authenticated;

create function pg_temp.expect_code(p_sql text, p_code text)
returns void language plpgsql security invoker set search_path = '' as $fn$
begin
  begin
    execute p_sql;
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

create function pg_temp.create_payload(
  p_name text, p_phones jsonb, p_vip boolean, p_open boolean
) returns jsonb language sql immutable as $fn$
  select pg_catalog.jsonb_build_object(
    'version', 1, 'kind', 'customer_create', 'display_name', p_name,
    'phones', p_phones, 'is_vip', p_vip, 'has_open_request', p_open
  );
$fn$;

create function pg_temp.phone(p_number text, p_primary boolean)
returns jsonb language sql immutable as $fn$
  select pg_catalog.jsonb_build_object('number', p_number, 'is_primary', p_primary);
$fn$;

do $norm$
begin
  if private.customer_normalize_phone('٠١٠١١١١١١١١') is distinct from '+201011111111'
    or private.customer_normalize_phone('۰۱۰۱۱۱۱۱۱۱۱') is distinct from '+201011111111'
    or private.customer_normalize_phone('01011111111') is distinct from '+201011111111'
    or private.customer_normalize_phone('01111111111') is distinct from '+201111111111'
    or private.customer_normalize_phone('01211111111') is distinct from '+201211111111'
    or private.customer_normalize_phone('01511111111') is distinct from '+201511111111'
    or private.customer_normalize_phone('+20 10 1111 1111') is distinct from '+201011111111'
    or private.customer_normalize_phone('00201011111111') is distinct from '+201011111111'
    or private.customer_normalize_phone('(010) 1111-1111') is distinct from '+201011111111'
    or private.customer_normalize_phone('0223456789') is distinct from '+20223456789'
    or private.customer_normalize_phone('+33123456789') is distinct from '+33123456789' then
    raise exception 'phone_normalization_mismatch';
  end if;
  if private.customer_name('"محمد علي"'::jsonb) is distinct from 'محمد علي'
    or private.customer_name('"Mona منى"'::jsonb) is distinct from 'Mona منى' then
    raise exception 'arabic_name_rejected';
  end if;
end;
$norm$;

select pg_temp.expect_code(
  $$select private.customer_normalize_phone('0123')$$, 'invalid_phone'
);
select pg_temp.expect_code(
  $$select private.customer_normalize_phone('201011111111')$$, 'invalid_phone'
);
select pg_temp.expect_code(
  $$select private.customer_normalize_phone('+201399999999')$$, 'invalid_phone'
);
select pg_temp.expect_code(
  $$select private.customer_normalize_phone('abc')$$, 'invalid_phone'
);
select pg_temp.expect_code(
  $$select private.customer_name('"Ahmed"')$$, 'invalid_name'
);
select pg_temp.expect_code(
  $$select private.customer_name('" محمد"')$$, 'invalid_input'
);

do $sync$
declare
  v_shop uuid := 'c1222222-2222-4222-8222-222222222222';
  v_customer bigint;
  v_ledger bigint;
  v_debt bigint;
  v_repair bigint;
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shop_sync_signals'
      and column_name = 'customer_revision' and is_nullable = 'NO'
  ) or not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'shop_sync_signals'
      and column_name = 'debt_revision'
  ) then
    raise exception 'customer_revision_missing';
  end if;
  select customer_revision, ledger_revision, debt_revision, repair_revision
    into v_customer, v_ledger, v_debt, v_repair
  from public.shop_sync_signals where shop_id = v_shop;
  perform private.bump_shop_sync(v_shop, 'ledger');
  if (select customer_revision from public.shop_sync_signals where shop_id = v_shop) <> v_customer
    or (select ledger_revision from public.shop_sync_signals where shop_id = v_shop) <> v_ledger + 1
    or (select debt_revision from public.shop_sync_signals where shop_id = v_shop) <> v_debt
    or (select repair_revision from public.shop_sync_signals where shop_id = v_shop) <> v_repair then
    raise exception 'ledger_bump_touched_customer_scope';
  end if;
  perform private.bump_shop_sync(v_shop, 'customer');
  if (select customer_revision from public.shop_sync_signals where shop_id = v_shop) <> v_customer + 1
    or (select ledger_revision from public.shop_sync_signals where shop_id = v_shop) <> v_ledger + 1
    or (select debt_revision from public.shop_sync_signals where shop_id = v_shop) <> v_debt then
    raise exception 'customer_bump_touched_other_scope';
  end if;
end;
$sync$;

do $priv$
begin
  if has_function_privilege('anon', 'public.post_customer_create_v1(uuid, jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_customer_list_v1(text, text, text, integer, text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_customer_v1(uuid, integer, text, integer, text, integer, text)', 'EXECUTE')
    or has_function_privilege('public', 'public.post_customer_link_v1(uuid, jsonb)', 'EXECUTE')
    or has_table_privilege('anon', 'public.customers', 'SELECT')
    or has_table_privilege('authenticated', 'public.customers', 'INSERT')
    or has_table_privilege('authenticated', 'public.customers', 'UPDATE')
    or has_table_privilege('authenticated', 'public.customers', 'DELETE')
    or has_table_privilege('authenticated', 'public.customer_phones', 'INSERT')
    or has_table_privilege('authenticated', 'public.customer_phones', 'DELETE')
    or has_table_privilege('authenticated', 'public.customer_notes', 'INSERT')
    or has_table_privilege('authenticated', 'public.customer_events', 'UPDATE')
    or has_table_privilege('authenticated', 'public.customer_command_requests', 'INSERT')
    or has_table_privilege('authenticated', 'public.customer_operation_links', 'INSERT')
    or has_table_privilege('authenticated', 'public.customer_operation_links', 'UPDATE')
    or has_table_privilege('authenticated', 'public.customer_operation_links', 'DELETE') then
    raise exception 'customer_privileges_were_too_wide';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename in (
        'customers', 'customer_phones', 'customer_notes', 'customer_events',
        'customer_command_requests', 'customer_operation_links'
      )
      and cmd <> 'SELECT'
  ) then
    raise exception 'customer_client_write_policy';
  end if;
end;
$priv$;

set local role anon;
do $anon$
begin
  begin
    perform public.get_customer_list_v1('', 'name', 'active', 20, null);
    raise exception 'anon_list_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'anon_list_unexpected: %', sqlerrm;
  end;
end;
$anon$;
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_code(
  $$select public.get_customer_list_v1('', 'name', 'active', 20, null)$$,
  'unauthenticated'
);

select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","session_id":"c1818181-8181-4181-8181-818181818182","is_anonymous":false}', true);
select pg_temp.expect_code(
  $$select public.get_customer_list_v1('', 'name', 'active', 20, null)$$,
  'session_expired'
);

select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select set_config('request.jwt.claim.sub', 'c3111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code(
  $$select public.get_customer_list_v1('', 'name', 'active', 20, null)$$, 'forbidden'
);
select set_config('request.jwt.claim.sub', 'c4111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code(
  $$select public.get_customer_v1('c3000000-0000-4000-8000-000000000099', null, null, null, null, null, null)$$,
  'forbidden'
);
select set_config('request.jwt.claim.sub', 'c5111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code(
  $$select public.get_customer_list_v1('', 'name', 'all', 20, null)$$, 'forbidden'
);
select set_config('request.jwt.claim.sub', 'c6111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code(
  $$select public.get_customer_link_candidates_v1('', 20, null)$$, 'shop_unavailable'
);

select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', true);
select public.confirm_opening_balances(
  'c3000000-0000-4000-8000-000000000001',
  '{"version":1,"cash":{"cash":"500000","wallet":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"20000","count":"5"}],"scrap":[{"karat":21,"milligrams":"3000"}]}'::jsonb
);

insert into customer_ops (name, operation_id, payload)
select 'sale_old', (public.post_daily_ledger_trade(
  'c3000000-0000-4000-8000-000000000011',
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم قديم","line_price_piastres":null}],"description":"","customer_name":"طرف جديد","customer_phone":"01033333333","note":"قديم"}'::jsonb
) ->> 'operation_id')::uuid,
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم قديم","line_price_piastres":null}],"description":"","customer_name":"طرف جديد","customer_phone":"01033333333","note":"قديم"}'::jsonb;

insert into customer_ops (name, operation_id, payload)
select 'sale_mid', (public.post_daily_ledger_trade(
  'c3000000-0000-4000-8000-000000000012',
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم أوسط","line_price_piastres":null}],"description":"","customer_name":"طرف جديد","customer_phone":"01033333334","note":"أوسط"}'::jsonb
) ->> 'operation_id')::uuid,
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم أوسط","line_price_piastres":null}],"description":"","customer_name":"طرف جديد","customer_phone":"01033333334","note":"أوسط"}'::jsonb;

insert into customer_ops (name, operation_id, payload)
select 'sale_new', (public.post_daily_ledger_trade(
  'c3000000-0000-4000-8000-000000000013',
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم جديد","line_price_piastres":null}],"description":"","customer_name":"طرف قديم","customer_phone":"01033333335","note":"الأحدث"}'::jsonb
) ->> 'operation_id')::uuid,
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم جديد","line_price_piastres":null}],"description":"","customer_name":"طرف قديم","customer_phone":"01033333335","note":"الأحدث"}'::jsonb;

insert into customer_ops (name, operation_id, payload)
select 'purchase', (public.post_daily_ledger_trade(
  'c3000000-0000-4000-8000-000000000014',
  '{"version":1,"kind":"purchase","total_piastres":"4000","tenders":[{"method":"cash","piastres":"4000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"سوار الاختبار","line_price_piastres":null}],"description":"","customer_name":"تاجر اللقطة","customer_phone":"01022222222","note":"شراء"}'::jsonb
) ->> 'operation_id')::uuid, null;

insert into customer_ops (name, operation_id, payload)
select 'expense', (public.post_daily_ledger_trade(
  'c3000000-0000-4000-8000-000000000015',
  '{"version":1,"kind":"expense","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[],"description":"مصروف اختبار","customer_name":"","customer_phone":"","note":""}'::jsonb
) ->> 'operation_id')::uuid, null;

select set_config('request.jwt.claim.sub', 'c2111111-1111-4111-8111-111111111111', true);
select public.confirm_opening_balances(
  'c3000000-0000-4000-8000-000000000021',
  '{"version":1,"cash":{"cash":"500000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"2"}],"scrap":[]}'::jsonb
);
insert into customer_ops (name, operation_id, payload)
select 'other_sale', (public.post_daily_ledger_trade(
  'c3000000-0000-4000-8000-000000000022',
  '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"1000","count":"1","item_name":"خاتم المتجر الآخر","line_price_piastres":null}],"description":"","customer_name":"سارة","customer_phone":"01044444444","note":"متجر آخر"}'::jsonb
) ->> 'operation_id')::uuid, null;

reset role;
insert into public.financial_operations (
  shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
)
select
  'c1222222-2222-4222-8222-222222222222',
  coalesce(max(operation.shop_sequence), 0) + 1,
  'sale',
  (select day.id from public.business_days as day
    where day.shop_id = 'c1222222-2222-4222-8222-222222222222' and day.status = 'open'
    order by day.opened_at desc limit 1),
  'c1111111-1111-4111-8111-111111111111',
  pg_catalog.clock_timestamp()
from public.financial_operations as operation
where operation.shop_id = 'c1222222-2222-4222-8222-222222222222';
insert into customer_ops (name, operation_id)
select 'unconfirmed', id from public.financial_operations
where shop_id = 'c1222222-2222-4222-8222-222222222222'
  and id not in (select operation_id from customer_ops where operation_id is not null)
order by created_at desc limit 1;
insert into public.financial_operation_details (operation_id, shop_id, payload, created_at)
select operation_id, 'c1222222-2222-4222-8222-222222222222',
  '{"version":1,"kind":"sale","customer_name":"غير مؤكد","customer_phone":"","note":""}'::jsonb,
  pg_catalog.clock_timestamp()
from customer_ops where name = 'unconfirmed';

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"c1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

do $owner$
declare
  v_shop uuid := 'c1222222-2222-4222-8222-222222222222';
  v_other uuid := 'c2222222-2222-4222-8222-222222222222';
  v_ahmed jsonb;
  v_sara jsonb;
  v_mohammad jsonb;
  v_adam jsonb;
  v_note jsonb;
  v_status jsonb;
  v_link jsonb;
  v_unlink jsonb;
  v_relink jsonb;
  v_page jsonb;
  v_detail jsonb;
  v_candidates jsonb;
  v_cursor text;
  v_sale_old uuid;
  v_sale_new uuid;
  v_purchase uuid;
  v_expense uuid;
  v_other_sale uuid;
  v_unconfirmed uuid;
  v_payload jsonb;
  v_payload_after jsonb;
  v_ops bigint;
  v_postings bigint;
  v_debts bigint;
  v_lots bigint;
  v_audits bigint;
  v_day bigint;
  v_cash bigint;
  v_ledger bigint;
  v_debt_rev bigint;
  v_repair_rev bigint;
  v_customer_rev bigint;
  v_long text := 'ملاحظة ' || repeat('ط', 200);
begin
  select operation_id into v_sale_old from customer_ops where name = 'sale_old';
  select operation_id into v_sale_new from customer_ops where name = 'sale_new';
  select operation_id into v_purchase from customer_ops where name = 'purchase';
  select operation_id into v_expense from customer_ops where name = 'expense';
  select operation_id into v_other_sale from customer_ops where name = 'other_sale';
  select operation_id into v_unconfirmed from customer_ops where name = 'unconfirmed';
  select detail.payload into v_payload
  from public.financial_operation_details as detail
  where detail.operation_id = v_sale_old;
  v_ops := (select count(*) from public.financial_operations where shop_id = v_shop);
  v_postings := (select count(*) from public.journal_postings where shop_id = v_shop);
  v_debts := (select count(*) from public.shop_debts where shop_id = v_shop);
  v_lots := (select count(*) from public.inventory_lots where shop_id = v_shop);
  v_audits := (select count(*) from public.financial_audit_events where shop_id = v_shop);
  v_day := (select day_version from public.business_days where shop_id = v_shop and status = 'open');
  v_cash := (
    select coalesce(sum(posting.amount), 0)
    from public.journal_postings as posting
    join public.ledger_accounts as account
      on account.shop_id = posting.shop_id and account.id = posting.account_id
    where posting.shop_id = v_shop and account.account_kind = 'cash_method'
  );
  select ledger_revision, debt_revision, repair_revision, customer_revision
    into v_ledger, v_debt_rev, v_repair_rev, v_customer_rev
  from public.shop_sync_signals where shop_id = v_shop;

  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000101',
      pg_temp.create_payload('Ahmed', '[]'::jsonb, false, false)
    ),
    'invalid_name'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000102',
      pg_temp.create_payload('محمد', '[]'::jsonb, false, false) || '{"extra":true}'::jsonb
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000103',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_create', 'display_name', 'محمد',
        'phones', '[]'::jsonb, 'is_vip', 'true', 'has_open_request', false
      )
    ),
    'invalid_input'
  );
  if (select count(*) from public.customers where shop_id = v_shop) <> 0 then
    raise exception 'rejected_create_persisted';
  end if;

  v_ahmed := public.post_customer_create_v1(
    'c3000000-0000-4000-8000-000000000110',
    pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
  );
  if v_ahmed ->> 'ok' is distinct from 'true'
    or v_ahmed ->> 'replayed' is distinct from 'false'
    or v_ahmed ->> 'status' is distinct from 'active'
    or v_ahmed ->> 'record_version' is distinct from '1'
    or v_ahmed ->> 'locale' is distinct from 'ar'
    or v_ahmed ->> 'time_zone' is distinct from 'Africa/Cairo'
    or v_ahmed ->> 'last_operation_at' is not null
    or jsonb_array_length(v_ahmed -> 'phones') <> 0
    or v_ahmed ->> 'customer_id' is null then
    raise exception 'empty_phone_customer_failed %', v_ahmed;
  end if;
  if (public.post_customer_create_v1(
      'c3000000-0000-4000-8000-000000000110',
      pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
    ) ->> 'replayed') is distinct from 'true'
    or (select count(*) from public.customers where shop_id = v_shop and display_name = 'أحمد') <> 1
    or (select count(*) from public.customer_events
        where customer_id = (v_ahmed ->> 'customer_id')::uuid) <> 1 then
    raise exception 'create_replay_duplicated';
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000110',
      pg_temp.create_payload('أحمد مختلف', '[]'::jsonb, false, false)
    ),
    'payload_mismatch'
  );
  v_status := public.get_customer_command_status_v1(
    'c3000000-0000-4000-8000-000000000110',
    'customer_create', null,
    pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
  );
  if v_status ->> 'status' is distinct from 'completed'
    or v_status ->> 'customer_id' is distinct from v_ahmed ->> 'customer_id' then
    raise exception 'create_status_unbound %', v_status;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.get_customer_command_status_v1(%L::uuid, %L, %L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000110', 'customer_create',
      v_ahmed ->> 'customer_id',
      pg_temp.create_payload('أحمد مختلف', '[]'::jsonb, false, false)
    ),
    'payload_mismatch'
  );
  perform pg_temp.expect_code(
    format(
      'select public.get_customer_command_status_v1(%L::uuid, %L, null, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000110', 'customer_edit',
      pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.get_customer_command_status_v1(%L::uuid, %L, %L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000110', 'customer_create',
      'c3000000-0000-4000-8000-000000000099',
      pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
    ),
    'payload_mismatch'
  );
  if (public.get_customer_command_status_v1(
      'c3000000-0000-4000-8000-000000000199', 'customer_create', null,
      pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
    ) ->> 'status') is distinct from 'absent' then
    raise exception 'missing_status_not_absent';
  end if;

  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000111',
      pg_temp.create_payload(
        'مكرر',
        pg_catalog.jsonb_build_array(
          pg_temp.phone('01011111111', true),
          pg_temp.phone('+201011111111', false)
        ),
        false, false
      )
    ),
    'duplicate_phone'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000112',
      pg_temp.create_payload(
        'بلا أساسي',
        pg_catalog.jsonb_build_array(pg_temp.phone('01055555555', false)),
        false, false
      )
    ),
    'primary_required'
  );

  v_sara := public.post_customer_create_v1(
    'c3000000-0000-4000-8000-000000000120',
    pg_temp.create_payload(
      'سارة',
      pg_catalog.jsonb_build_array(
        pg_temp.phone('٠١٠١١١١١١١١', true),
        pg_temp.phone('+33123456789', false)
      ),
      false, false
    )
  );
  if v_sara -> 'phones' -> 0 ->> 'normalized' is distinct from '+201011111111'
    or v_sara -> 'phones' -> 0 ->> 'is_primary' is distinct from 'true'
    or v_sara -> 'phones' -> 1 ->> 'normalized' is distinct from '+33123456789'
    or v_sara ->> 'display_name' is distinct from 'سارة' then
    raise exception 'sara_phones %', v_sara -> 'phones';
  end if;
  v_mohammad := public.post_customer_create_v1(
    'c3000000-0000-4000-8000-000000000121',
    pg_temp.create_payload('محمد', '[]'::jsonb, false, false)
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_edit_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000122',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_edit',
        'customer_id', v_mohammad ->> 'customer_id',
        'expected_version', '1', 'display_name', 'محمد',
        'phones', pg_catalog.jsonb_build_array(pg_temp.phone('+20 10 1111 1111', true))
      )
    ),
    'phone_conflict'
  );
  v_adam := public.post_customer_create_v1(
    'c3000000-0000-4000-8000-000000000123',
    pg_temp.create_payload(
      'آدم',
      pg_catalog.jsonb_build_array(pg_temp.phone('0223456789', true)),
      false, false
    )
  );
  if v_adam -> 'phones' -> 0 ->> 'normalized' is distinct from '+20223456789' then
    raise exception 'landline_not_normalized %', v_adam -> 'phones';
  end if;

  v_note := public.post_customer_note_v1(
    'c3000000-0000-4000-8000-000000000130',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_note',
      'customer_id', v_sara ->> 'customer_id',
      'expected_version', v_sara ->> 'record_version',
      'body', 'طلب أول'
    )
  );
  v_note := public.post_customer_note_v1(
    'c3000000-0000-4000-8000-000000000131',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_note',
      'customer_id', v_sara ->> 'customer_id',
      'expected_version', v_note ->> 'record_version',
      'body', 'طلب ثان'
    )
  );
  v_note := public.post_customer_note_v1(
    'c3000000-0000-4000-8000-000000000132',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_note',
      'customer_id', v_sara ->> 'customer_id',
      'expected_version', v_note ->> 'record_version',
      'body', v_long
    )
  );
  if v_note ->> 'latest_note_preview' is distinct from left(v_long, 120)
    or v_note ->> 'latest_note_at' is null
    or v_note ->> 'updated_at' = v_note ->> 'last_operation_at' then
    raise exception 'note_preview_failed %', v_note;
  end if;
  v_detail := public.get_customer_v1(
    (v_sara ->> 'customer_id')::uuid, 2, null, 20, null, 20, null
  );
  if jsonb_array_length(v_detail -> 'notes' -> 'items') <> 2
    or v_detail -> 'notes' ->> 'next_cursor' is null
    or v_detail -> 'notes' -> 'items' -> 0 ->> 'body' is distinct from v_long
    or (select count(*) from public.customer_notes
        where customer_id = (v_sara ->> 'customer_id')::uuid and body = 'طلب أول') <> 1 then
    raise exception 'note_page_failed %', v_detail -> 'notes';
  end if;
  if jsonb_array_length(public.get_customer_v1(
      (v_sara ->> 'customer_id')::uuid, 2, v_detail -> 'notes' ->> 'next_cursor',
      20, null, 20, null
    ) -> 'notes' -> 'items') <> 1 then
    raise exception 'note_second_page_failed';
  end if;
  perform pg_temp.expect_code(format('select public.get_customer_v1(%L::uuid,2,%L,20,null,20,null)',v_sara ->> 'customer_id','not-a-cursor'),'invalid_cursor');

  v_status := public.post_customer_status_v1(
    'c3000000-0000-4000-8000-000000000140',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_status',
      'customer_id', v_sara ->> 'customer_id',
      'expected_version', v_note ->> 'record_version',
      'is_vip', true, 'has_open_request', false
    )
  );
  if v_status ->> 'is_vip' is distinct from 'true'
    or v_status ->> 'has_open_request' is distinct from 'false' then
    raise exception 'vip_status_failed %', v_status;
  end if;
  perform public.post_customer_status_v1(
    'c3000000-0000-4000-8000-000000000141',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_status',
      'customer_id', v_mohammad ->> 'customer_id',
      'expected_version', v_mohammad ->> 'record_version',
      'is_vip', false, 'has_open_request', true
    )
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_status_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000142',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_status',
        'customer_id', v_mohammad ->> 'customer_id',
        'expected_version', '1',
        'is_vip', true, 'has_open_request', true
      )
    ),
    'stale_customer'
  );
  if (select record_version::text from public.customers
      where id = (v_mohammad ->> 'customer_id')::uuid) is distinct from '2'
    or (select is_vip from public.customers
        where id = (v_mohammad ->> 'customer_id')::uuid) then
    raise exception 'stale_status_applied';
  end if;

  if jsonb_array_length(public.get_customer_link_candidates_v1('سارة', 20, null) -> 'items') <> 0
    or exists (
      select 1 from public.customer_operation_links where shop_id in (v_shop, v_other)
    ) then
    raise exception 'name_match_inferred_a_link';
  end if;
  v_candidates := public.get_customer_link_candidates_v1('طرف جديد', 1, null);
  if jsonb_array_length(v_candidates -> 'items') <> 1
    or v_candidates -> 'items' -> 0 ->> 'party_name' is distinct from 'طرف جديد'
    or v_candidates -> 'items' -> 0 ->> 'label_ar' is distinct from 'بيع'
    or v_candidates -> 'items' -> 0 ->> 'shop_sequence' is null
    or v_candidates -> 'items' -> 0 ->> 'operation_created_at' is null
    or v_candidates ->> 'next_cursor' is null then
    raise exception 'candidate_page_failed %', v_candidates;
  end if;
  v_cursor := v_candidates ->> 'next_cursor';
  perform pg_temp.expect_code(format('select public.get_customer_link_candidates_v1(%L,20,%L)','طرف قديم',v_cursor),'invalid_cursor');
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_link_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000150',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_link',
        'customer_id', v_mohammad ->> 'customer_id',
        'expected_version', '2', 'operation_id', v_other_sale
      )
    ),
    'cross_shop'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_link_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000151',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_link',
        'customer_id', v_mohammad ->> 'customer_id',
        'expected_version', '2', 'operation_id', v_expense
      )
    ),
    'wrong_operation_kind'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_link_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000152',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_link',
        'customer_id', v_mohammad ->> 'customer_id',
        'expected_version', '2', 'operation_id', v_unconfirmed
      )
    ),
    'operation_not_confirmed'
  );
  v_link := public.post_customer_link_v1(
    'c3000000-0000-4000-8000-000000000153',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_link',
      'customer_id', v_sara ->> 'customer_id',
      'expected_version', v_status ->> 'record_version',
      'operation_id', v_sale_new
    )
  );
  if v_link ->> 'last_operation_at' is null
    or v_link ->> 'updated_at' is null
    or v_link ->> 'last_operation_at' = v_link ->> 'updated_at'
    or v_link ->> 'operation_id' is distinct from v_sale_new::text then
    raise exception 'link_times_not_distinct %', v_link;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_link_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000154',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_link',
        'customer_id', v_mohammad ->> 'customer_id',
        'expected_version', '2', 'operation_id', v_sale_new
      )
    ),
    'duplicate_link'
  );
  v_link := public.post_customer_link_v1(
    'c3000000-0000-4000-8000-000000000155',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_link',
      'customer_id', v_mohammad ->> 'customer_id',
      'expected_version', '2', 'operation_id', v_sale_old
    )
  );
  v_unlink := public.post_customer_unlink_v1(
    'c3000000-0000-4000-8000-000000000156',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_unlink',
      'customer_id', v_mohammad ->> 'customer_id',
      'expected_version', v_link ->> 'record_version',
      'operation_id', v_sale_old
    )
  );
  v_relink := public.post_customer_link_v1(
    'c3000000-0000-4000-8000-000000000157',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_link',
      'customer_id', v_ahmed ->> 'customer_id',
      'expected_version', '1', 'operation_id', v_sale_old
    )
  );
  select detail.payload into v_payload_after
  from public.financial_operation_details as detail
  where detail.operation_id = v_sale_old;
  if v_payload_after is distinct from v_payload
    or (select count(*) from public.customer_operation_links
        where operation_id = v_sale_old) <> 2
    or (select count(*) from public.customer_operation_links
        where operation_id = v_sale_old and status = 'active') <> 1
    or (select customer_id from public.customer_operation_links
        where operation_id = v_sale_old and status = 'active')
        is distinct from (v_ahmed ->> 'customer_id')::uuid
    or (select status from public.customer_operation_links
        where operation_id = v_sale_old and customer_id = (v_mohammad ->> 'customer_id')::uuid)
        is distinct from 'unlinked' then
    raise exception 'link_correction_lost_history';
  end if;
  v_detail := public.get_customer_v1(
    (v_mohammad ->> 'customer_id')::uuid, 20, null, 20, null, 20, null
  );
  if jsonb_array_length(v_detail -> 'links' -> 'items') <> 1
    or v_detail -> 'links' -> 'items' -> 0 ->> 'link_status' is distinct from 'unlinked'
    or v_detail -> 'links' -> 'items' -> 0 ->> 'party_name' is distinct from 'طرف جديد'
    or v_detail -> 'links' -> 'items' -> 0 ->> 'party_phone' is distinct from '01033333333'
    or (select count(*) from jsonb_array_elements(v_detail -> 'history' -> 'items') as entry(value)
        where entry.value ->> 'event_type' = 'unlinked') <> 1 then
    raise exception 'unlink_history_missing %', v_detail;
  end if;
  perform public.post_customer_link_v1(
    'c3000000-0000-4000-8000-000000000158',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_link',
      'customer_id', v_mohammad ->> 'customer_id',
      'expected_version', v_unlink ->> 'record_version',
      'operation_id', v_purchase
    )
  );

  v_page := public.get_customer_list_v1('', 'name', 'active', 1, null);
  if jsonb_array_length(v_page -> 'items') <> 1
    or v_page -> 'items' -> 0 ->> 'display_name' is distinct from 'آدم'
    or v_page ->> 'next_cursor' is null then
    raise exception 'name_sort_failed %', v_page;
  end if;
  v_cursor := v_page ->> 'next_cursor';
  if public.get_customer_list_v1('', 'name', 'active', 1, v_cursor)
      -> 'items' -> 0 ->> 'display_name' is distinct from 'أحمد' then
    raise exception 'name_second_page_failed';
  end if;
  v_page := public.get_customer_list_v1('', 'last_operation', 'active', 10, null);
  if v_page -> 'items' -> 0 ->> 'display_name' is distinct from 'محمد'
    or v_page -> 'items' -> 1 ->> 'display_name' is distinct from 'سارة'
    or v_page -> 'items' -> 2 ->> 'display_name' is distinct from 'أحمد' then
    raise exception 'last_operation_sort_failed %', v_page -> 'items';
  end if;
  perform pg_temp.expect_code($sql$select public.get_customer_list_v1('','name','active',10,'@@@')$sql$,'invalid_cursor');
  if jsonb_array_length(public.get_customer_list_v1('٠١٠١١١١١١١١', 'name', 'active', 20, null) -> 'items') <> 1
    or public.get_customer_list_v1('٠١٠١١١١١١١١', 'name', 'active', 20, null)
      -> 'items' -> 0 ->> 'display_name' is distinct from 'سارة'
    or public.get_customer_list_v1('', 'name', 'vip', 20, null)
      -> 'items' -> 0 ->> 'display_name' is distinct from 'سارة'
    or public.get_customer_list_v1('', 'name', 'open_request', 20, null)
      -> 'items' -> 0 ->> 'display_name' is distinct from 'محمد' then
    raise exception 'search_or_badge_filter_failed';
  end if;

  v_adam := public.post_customer_archive_v1(
    'c3000000-0000-4000-8000-000000000160',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_archive',
      'customer_id', v_adam ->> 'customer_id',
      'expected_version', v_adam ->> 'record_version'
    )
  );
  if v_adam ->> 'status' is distinct from 'archived'
    or (select count(*) from public.customer_phones
        where customer_id = (v_adam ->> 'customer_id')::uuid) <> 1
    or jsonb_array_length(public.get_customer_list_v1('', 'name', 'active', 20, null) -> 'items') <> 3
    or public.get_customer_list_v1('', 'name', 'archived', 20, null)
      -> 'items' -> 0 ->> 'display_name' is distinct from 'آدم' then
    raise exception 'archive_filter_failed %', v_adam;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000161',
      pg_temp.create_payload(
        'بديل',
        pg_catalog.jsonb_build_array(pg_temp.phone('+20223456789', true)),
        false, false
      )
    ),
    'phone_conflict'
  );
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_link_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000162',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_link',
        'customer_id', v_adam ->> 'customer_id',
        'expected_version', v_adam ->> 'record_version',
        'operation_id', (select operation_id from customer_ops where name = 'sale_mid')
      )
    ),
    'customer_archived'
  );
  v_adam := public.post_customer_edit_v1(
    'c3000000-0000-4000-8000-000000000163',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_edit',
      'customer_id', v_adam ->> 'customer_id',
      'expected_version', v_adam ->> 'record_version',
      'display_name', 'آدم', 'phones', '[]'::jsonb
    )
  );
  if jsonb_array_length(v_adam -> 'phones') <> 0 then
    raise exception 'archived_phone_not_released';
  end if;
  perform public.post_customer_create_v1(
    'c3000000-0000-4000-8000-000000000164',
    pg_temp.create_payload(
      'بديل',
      pg_catalog.jsonb_build_array(pg_temp.phone('0223456789', true)),
      false, false
    )
  );
  v_adam := public.post_customer_restore_v1(
    'c3000000-0000-4000-8000-000000000165',
    pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'customer_restore',
      'customer_id', v_adam ->> 'customer_id',
      'expected_version', v_adam ->> 'record_version'
    )
  );
  if v_adam ->> 'status' is distinct from 'active' then
    raise exception 'restore_failed %', v_adam;
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_restore_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000166',
      pg_catalog.jsonb_build_object(
        'version', 1, 'kind', 'customer_restore',
        'customer_id', v_adam ->> 'customer_id',
        'expected_version', v_adam ->> 'record_version'
      )
    ),
    'invalid_state'
  );
  if (public.get_customer_v1((v_ahmed ->> 'customer_id')::uuid, 20, null, 20, null, 20, null)
      ->> 'last_operation_at') is null
    or (public.get_customer_v1((v_ahmed ->> 'customer_id')::uuid, 20, null, 1, null, 20, null)
      -> 'history' ->> 'next_cursor') is null then
    raise exception 'ahmed_history_page_failed';
  end if;

  if (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select count(*) from public.journal_postings where shop_id = v_shop) <> v_postings
    or (select count(*) from public.shop_debts where shop_id = v_shop) <> v_debts
    or (select count(*) from public.inventory_lots where shop_id = v_shop) <> v_lots
    or (select count(*) from public.financial_audit_events where shop_id = v_shop) <> v_audits
    or (select day_version from public.business_days where shop_id = v_shop and status = 'open') <> v_day
    or (
      select coalesce(sum(posting.amount), 0)
      from public.journal_postings as posting
      join public.ledger_accounts as account
        on account.shop_id = posting.shop_id and account.id = posting.account_id
      where posting.shop_id = v_shop and account.account_kind = 'cash_method'
    ) <> v_cash
    or (select ledger_revision from public.shop_sync_signals where shop_id = v_shop) <> v_ledger
    or (select debt_revision from public.shop_sync_signals where shop_id = v_shop) <> v_debt_rev
    or (select repair_revision from public.shop_sync_signals where shop_id = v_shop) <> v_repair_rev
    or (select customer_revision from public.shop_sync_signals where shop_id = v_shop) <= v_customer_rev
    or (select payload from public.financial_operation_details where operation_id = v_sale_old)
      is distinct from v_payload then
    raise exception 'customer_commands_changed_finance';
  end if;

  perform set_config('eldafttar.customer_fail_after_write', '1', true);
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000180',
      pg_temp.create_payload('فشل متأخر', '[]'::jsonb, false, false)
    ),
    'customer_test_failure'
  );
  perform set_config('eldafttar.customer_fail_after_write', '0', true);
  if exists (
      select 1 from public.customers where display_name = 'فشل متأخر'
    )
    or exists (
      select 1 from public.customer_command_requests
      where idempotency_key = 'c3000000-0000-4000-8000-000000000180'
    )
    or exists (
      select 1 from public.customer_notes as note
      join public.customers as customer on customer.id = note.customer_id
      where customer.display_name = 'فشل متأخر'
    )
    or (select count(*) from public.financial_operations where shop_id = v_shop) <> v_ops
    or (select customer_revision from public.shop_sync_signals where shop_id = v_shop)
      <= v_customer_rev then
    raise exception 'injected_failure_did_not_roll_back';
  end if;

  perform pg_temp.crm_entitlement(true);
  if public.get_customer_list_v1('', 'name', 'all', 20, null) -> 'items' is null then
    raise exception 'expired_read_denied';
  end if;
  if (public.post_customer_create_v1(
      'c3000000-0000-4000-8000-000000000110',
      pg_temp.create_payload('أحمد', '[]'::jsonb, false, false)
    ) ->> 'replayed') is distinct from 'true' then
    raise exception 'expired_replay_failed';
  end if;
  perform pg_temp.expect_code(
    format(
      'select public.post_customer_create_v1(%L::uuid, %L::jsonb)',
      'c3000000-0000-4000-8000-000000000181',
      pg_temp.create_payload('بعد الانتهاء', '[]'::jsonb, false, false)
    ),
    'shop_not_active'
  );
  perform pg_temp.crm_entitlement(false);
end;
$owner$;

do $direct$
begin
  begin
    insert into public.customers (
      shop_id, status, record_version, display_name, is_vip, has_open_request,
      created_at, updated_at, created_by
    ) values (
      'c1222222-2222-4222-8222-222222222222', 'active', 1, 'مباشر', false, false,
      pg_catalog.clock_timestamp(), pg_catalog.clock_timestamp(),
      'c1111111-1111-4111-8111-111111111111'
    );
    raise exception 'direct_insert_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'direct_insert_got_%', sqlerrm;
  end;
  begin
    delete from public.customer_notes;
    raise exception 'direct_note_delete_allowed';
  exception
    when insufficient_privilege then null;
    when others then raise exception 'direct_note_delete_got_%', sqlerrm;
  end;
end;
$direct$;

reset role;
do $append$
begin
  begin
    update public.customer_notes set body = 'محذوف';
    raise exception 'note_update_allowed';
  exception
    when others then
      if sqlerrm = 'note_update_allowed' or sqlerrm is distinct from 'audit_append_only' then
        raise exception 'note_update_got_%', sqlerrm;
      end if;
  end;
  begin
    delete from public.customers;
    raise exception 'customer_delete_allowed';
  exception
    when others then
      if sqlerrm = 'customer_delete_allowed' or sqlerrm is distinct from 'audit_append_only' then
        raise exception 'customer_delete_got_%', sqlerrm;
      end if;
  end;
end;
$append$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c2111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims',
  '{"sub":"c2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $cross$
begin
  if (select count(*) from public.customers) <> 0
    or jsonb_array_length(public.get_customer_list_v1('', 'name', 'all', 20, null) -> 'items') <> 0 then
    raise exception 'cross_shop_customers_visible';
  end if;
end;
$cross$;

rollback;

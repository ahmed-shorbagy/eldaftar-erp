-- Historical ledger date reads. Synthetic fixtures roll back. Local SQL only.
begin;

do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() !~ '^eldaftar_(ledger_date|trade_change|owner_meeting_)[a-z0-9_]*$' then
    raise exception 'refusing ledger date test outside a named local disposable test database';
  end if;
end;
$guard$;

insert into auth.users (
  id, instance_id, aud, role, email, is_anonymous, created_at, updated_at
) values
  ('a1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-cairo@example.test', false, now(), now()),
  ('a1100000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-kiri@example.test', false, now(), now()),
  ('a1100000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-pago@example.test', false, now(), now()),
  ('a1100000-0000-4000-8000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-revoked@example.test', false, now(), now()),
  ('a1100000-0000-4000-8000-000000000005', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-anon@example.test', true, now(), now()),
  ('a1100000-0000-4000-8000-000000000006', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-pending@example.test', false, now(), now()),
  ('a1100000-0000-4000-8000-000000000007', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ledger-date-expired-sub@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1100000-0000-4000-8000-000000000001', 'متجر التاريخ', 'المالك التاريخي', 'Africa/Cairo'),
  ('b1100000-0000-4000-8000-000000000002', 'متجر كيريتيماتي', 'مالك كيريتيماتي', 'Pacific/Kiritimati'),
  ('b1100000-0000-4000-8000-000000000003', 'متجر باجو', 'مالك باجو', 'Pacific/Pago_Pago'),
  ('b1100000-0000-4000-8000-000000000004', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('b1100000-0000-4000-8000-000000000005', 'متجر مجهول', 'مالك مجهول', 'Africa/Cairo'),
  ('b1100000-0000-4000-8000-000000000006', 'متجر مؤجل', 'مالك مؤجل', 'Africa/Cairo'),
  ('b1100000-0000-4000-8000-000000000007', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('b1100000-0000-4000-8000-000000000001', 'a1100000-0000-4000-8000-000000000001', 'owner', null),
  ('b1100000-0000-4000-8000-000000000002', 'a1100000-0000-4000-8000-000000000002', 'owner', null),
  ('b1100000-0000-4000-8000-000000000003', 'a1100000-0000-4000-8000-000000000003', 'owner', null),
  ('b1100000-0000-4000-8000-000000000004', 'a1100000-0000-4000-8000-000000000004', 'owner', now()),
  ('b1100000-0000-4000-8000-000000000005', 'a1100000-0000-4000-8000-000000000005', 'owner', null),
  ('b1100000-0000-4000-8000-000000000006', 'a1100000-0000-4000-8000-000000000006', 'owner', null),
  ('b1100000-0000-4000-8000-000000000007', 'a1100000-0000-4000-8000-000000000007', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1100000-0000-4000-8000-000000000001', now() - interval '2 days', now() + interval '30 days'),
  ('b1100000-0000-4000-8000-000000000002', now() - interval '2 days', now() + interval '30 days'),
  ('b1100000-0000-4000-8000-000000000003', now() - interval '2 days', now() + interval '30 days'),
  ('b1100000-0000-4000-8000-000000000004', now() - interval '2 days', now() + interval '30 days'),
  ('b1100000-0000-4000-8000-000000000005', now() - interval '2 days', now() + interval '30 days'),
  ('b1100000-0000-4000-8000-000000000006', now() + interval '1 day', now() + interval '30 days'),
  ('b1100000-0000-4000-8000-000000000007', now() - interval '10 days', now() - interval '1 day');

insert into public.business_days (
  id, shop_id, business_date, opened_at, closed_at, status, day_version
) values
  ('d1100000-0000-4000-8000-0000000000a1', 'b1100000-0000-4000-8000-000000000001',
    date '2020-01-15', timestamp '2020-01-15 10:00:00' at time zone 'Africa/Cairo',
    timestamp '2020-01-15 12:00:00' at time zone 'Africa/Cairo', 'closed', 1),
  ('d1100000-0000-4000-8000-0000000000b2', 'b1100000-0000-4000-8000-000000000001',
    date '2020-01-15', timestamp '2020-01-15 16:00:00' at time zone 'Africa/Cairo',
    timestamp '2020-01-15 18:00:00' at time zone 'Africa/Cairo', 'closed', 1),
  ('d1100000-0000-4000-8000-0000000000c3', 'b1100000-0000-4000-8000-000000000001',
    date '2020-01-16', timestamp '2020-01-16 10:00:00' at time zone 'Africa/Cairo',
    timestamp '2020-01-16 11:00:00' at time zone 'Africa/Cairo', 'closed', 1),
  ('d1100000-0000-4000-8000-0000000000d4', 'b1100000-0000-4000-8000-000000000001',
    date '2019-01-01', timestamp '2019-01-01 10:00:00' at time zone 'Africa/Cairo',
    timestamp '2019-01-01 11:00:00' at time zone 'Africa/Cairo', 'closed', 1),
  ('d2100000-0000-4000-8000-0000000000e5', 'b1100000-0000-4000-8000-000000000002',
    date '2020-01-15', timestamp '2020-01-15 09:00:00' at time zone 'Africa/Cairo',
    timestamp '2020-01-15 09:30:00' at time zone 'Africa/Cairo', 'closed', 1);

insert into public.financial_operations (
  id, shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
) values
  ('e1100000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001', 1, 'sale',
    'd1100000-0000-4000-8000-0000000000a1', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 11:15:30' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000002', 'b1100000-0000-4000-8000-000000000001', 2, 'scrap_sale',
    'd1100000-0000-4000-8000-0000000000b2', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 16:10:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000003', 'b1100000-0000-4000-8000-000000000001', 3, 'purchase',
    'd1100000-0000-4000-8000-0000000000a1', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 11:20:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000005', 'b1100000-0000-4000-8000-000000000001', 5, 'expense',
    'd1100000-0000-4000-8000-0000000000a1', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 11:30:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000006', 'b1100000-0000-4000-8000-000000000001', 6, 'purchase',
    'd1100000-0000-4000-8000-0000000000b2', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 16:20:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000007', 'b1100000-0000-4000-8000-000000000001', 7, 'sale',
    'd1100000-0000-4000-8000-0000000000b2', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 16:30:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000008', 'b1100000-0000-4000-8000-000000000001', 8, 'debt_settlement',
    'd1100000-0000-4000-8000-0000000000b2', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 16:40:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000012', 'b1100000-0000-4000-8000-000000000001', 12, 'scrap_sale',
    'd1100000-0000-4000-8000-0000000000a1', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 11:40:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000040', 'b1100000-0000-4000-8000-000000000001', 40, 'sale',
    'd1100000-0000-4000-8000-0000000000b2', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 17:45:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000050', 'b1100000-0000-4000-8000-000000000001', 50, 'sale',
    'd1100000-0000-4000-8000-0000000000a1', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 10:30:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000060', 'b1100000-0000-4000-8000-000000000001', 60, 'sale_return',
    'd1100000-0000-4000-8000-0000000000a1', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-15 10:05:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000100', 'b1100000-0000-4000-8000-000000000001', 100, 'sale',
    'd1100000-0000-4000-8000-0000000000c3', 'a1100000-0000-4000-8000-000000000001',
    timestamp '2020-01-16 10:15:00' at time zone 'Africa/Cairo'),
  ('e2100000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000002', 1, 'sale',
    'd2100000-0000-4000-8000-0000000000e5', 'a1100000-0000-4000-8000-000000000002',
    timestamp '2020-01-15 09:10:00' at time zone 'Africa/Cairo');

insert into public.financial_operation_details (operation_id, shop_id, payload, created_at) values
  ('e1100000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"خاتم"}],"customer_name":"عميل أ","customer_phone":"01012345678","note":"ملاحظة بيع"}'::jsonb,
    timestamp '2020-01-15 11:15:30' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000002', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"scrap_sale","total_piastres":"2000","tenders":[{"method":"cash","piastres":"1000"},{"method":"card","piastres":"1000"}],"items":[{"category":"scrap","karat":21,"milligrams":"300","count":null,"item_name":"كسر"}],"customer_name":"","note":"اختبار كسر"}'::jsonb,
    timestamp '2020-01-15 16:10:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000003', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"purchase","total_piastres":"1000","tenders":[{"method":"cash","piastres":"1000"}],"items":[{"category":"scrap","karat":21,"milligrams":"500","count":null,"item_name":"كسر شراء"}],"customer_name":"","note":""}'::jsonb,
    timestamp '2020-01-15 11:20:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000005', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"expense","total_piastres":"500","tenders":[{"method":"cash","piastres":"500"}],"items":[],"customer_name":"","note":""}'::jsonb,
    timestamp '2020-01-15 11:30:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000006', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"purchase","total_piastres":"8000","tenders":[{"method":"cash","piastres":"8000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"2500","count":"2","item_name":"سلسلة"}],"customer_name":"تاجر","note":""}'::jsonb,
    timestamp '2020-01-15 16:20:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000007', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"sale","total_piastres":"42","tenders":null,"items":null,"customer_name":"دائن","note":"ملاحظة دين"}'::jsonb,
    timestamp '2020-01-15 16:30:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000008', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"debt_settlement","items":null,"tenders":null,"customer_name":"طرف الدين","note":"ملاحظة سداد"}'::jsonb,
    timestamp '2020-01-15 16:40:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000012', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"scrap_sale","total_piastres":"70","tenders":[{"method":"cash","piastres":"70"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"50","count":"1","item_name":"جزء"}],"customer_name":"","note":""}'::jsonb,
    timestamp '2020-01-15 11:40:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000040', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"sale","total_piastres":"1","tenders":[{"method":"cash","piastres":"1"}],"items":[{"category":"worked_jewelry","karat":22,"milligrams":"2","count":"1","item_name":"قطعة"}],"customer_name":"","note":""}'::jsonb,
    timestamp '2020-01-15 17:45:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000050', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"sale","total_piastres":"9007199254740993","tenders":[{"method":"cash","piastres":"9007199254740993"}],"items":[{"category":"worked_jewelry","karat":22,"milligrams":"9007199254740993","count":"1","item_name":"سبيكة"}],"customer_name":"","note":""}'::jsonb,
    timestamp '2020-01-15 10:30:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000060', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"sale_return","total_piastres":"123456789","tenders":[{"method":"cash","piastres":"123456789"}],"items":[{"category":"worked_jewelry","karat":24,"milligrams":"999999","count":"4","item_name":"مرتجع"}],"customer_name":"مرتجع","note":""}'::jsonb,
    timestamp '2020-01-15 10:05:00' at time zone 'Africa/Cairo'),
  ('e1100000-0000-4000-8000-000000000100', 'b1100000-0000-4000-8000-000000000001',
    '{"version":1,"kind":"sale","total_piastres":"999","tenders":[{"method":"cash","piastres":"999"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"10","count":"1","item_name":"يوم آخر"}],"customer_name":"يوم آخر","note":""}'::jsonb,
    timestamp '2020-01-16 10:15:00' at time zone 'Africa/Cairo'),
  ('e2100000-0000-4000-8000-000000000001', 'b1100000-0000-4000-8000-000000000002',
    '{"version":1,"kind":"sale","total_piastres":"777","tenders":[{"method":"cash","piastres":"777"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"7","count":"1","item_name":"متجر آخر"}],"customer_name":"متجر آخر","note":""}'::jsonb,
    timestamp '2020-01-15 09:10:00' at time zone 'Africa/Cairo');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after)
values (
  '51100000-0000-4000-8000-000000000099',
  'a1100000-0000-4000-8000-000000000001',
  now(), now(), transaction_timestamp() - interval '2 minutes'
);

do $test$
declare
  v_main uuid := 'b1100000-0000-4000-8000-000000000001';
  v_kiri uuid := 'b1100000-0000-4000-8000-000000000002';
  v_pago uuid := 'b1100000-0000-4000-8000-000000000003';
  v_owner uuid := 'a1100000-0000-4000-8000-000000000001';
  v_day_a uuid := 'd1100000-0000-4000-8000-0000000000a1';
  v_day_b uuid := 'd1100000-0000-4000-8000-0000000000b2';
  v_checks integer := 0;
  v_shapes integer := 0;
  v_pages integer := 0;
  v_boundary integer := 0;
  v_def text;
  v_args text;
  v_proc oid;
  v_page jsonb;
  v_other jsonb;
  v_ref jsonb;
  v_by_id jsonb;
  v_item jsonb;
  v_seen bigint[] := '{}';
  v_ids uuid[] := '{}';
  v_before text;
  v_ops bigint;
  v_days bigint;
  v_journals bigint;
  v_revision bigint;
  v_ops_after bigint;
  v_days_after bigint;
  v_journals_after bigint;
  v_revision_after bigint;
  v_server date;
  v_utc date;
  v_kiri_date date;
  v_pago_date date;
  v_cairo date;
  v_day uuid;
  v_gold jsonb;
  v_keys text[];
begin
  v_proc := 'public.get_ledger_date_v1(date,text,integer)'::regprocedure;
  v_def := pg_catalog.pg_get_functiondef(v_proc);
  v_args := pg_catalog.pg_get_function_arguments(v_proc);
  if v_args not like 'p_business_date date DEFAULT NULL%'
    or v_args not like '%p_before_sequence text DEFAULT NULL%'
    or v_args not like '%p_limit integer DEFAULT 100%'
    or pg_catalog.pg_get_function_identity_arguments(v_proc)
      is distinct from 'p_business_date date, p_before_sequence text, p_limit integer' then
    raise exception 'signature drifted: %', v_args;
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc as proc
    where proc.oid = v_proc and proc.prosecdef and proc.provolatile = 's'
      and proc.proconfig::text like '%search_path=%'
      and proc.proconfig::text not like '%public%'
  ) then
    raise exception 'definer or search_path drifted';
  end if;
  if v_def not like '%private.parse_optional_sequence%'
    or v_def not like '%private.ledger_operation_label%'
    or v_def not like '%private.opening_require_reader_shop%'
    or v_def not like '%private.shop_display_zone%'
    or v_def ilike '%ledger_accounts%'
    or v_def ilike '%journal_postings%'
    or v_def ilike '%::float%'
    or v_def ilike '%double precision%' then
    raise exception 'definition drifted from the read contract';
  end if;
  if exists (
    select 1
    from pg_catalog.pg_proc as proc
    cross join lateral pg_catalog.aclexplode(proc.proacl) as acl
    where proc.oid = v_proc
      and acl.privilege_type = 'EXECUTE'
      and (acl.grantee = 0 or acl.grantee = 'anon'::regrole)
  ) or not has_function_privilege('authenticated', v_proc, 'EXECUTE')
    or has_function_privilege('anon', v_proc, 'EXECUTE') then
    raise exception 'execute grants drifted';
  end if;
  if (
    select count(*) from pg_catalog.pg_proc as proc
    where proc.proname = 'get_ledger_date_v1'
  ) <> 1 then
    raise exception 'unexpected ledger date overloads';
  end if;
  if (
    select count(*) from pg_catalog.pg_indexes
    where schemaname = 'public' and tablename = 'business_days'
      and indexdef like '%(shop_id, business_date%'
  ) <> 1 or exists (
    select 1 from pg_catalog.pg_index as idx
    join pg_catalog.pg_class as rel on rel.oid = idx.indexrelid
    where rel.relname = 'business_days_shop_business_date_idx' and idx.indisunique
  ) then
    raise exception 'business date index is missing, duplicated, or unique';
  end if;
  if not (
    select bool_and(rel.relrowsecurity)
    from pg_catalog.pg_class as rel
    where rel.oid in (
      'public.business_days'::regclass,
      'public.financial_operations'::regclass,
      'public.financial_operation_details'::regclass
    )
  ) then
    raise exception 'ledger tables lost row level security';
  end if;
  v_checks := v_checks + 6;

  select count(*) into v_ops from public.financial_operations where shop_id = v_main;
  select count(*) into v_days from public.business_days where shop_id = v_main;
  select count(*) into v_journals from public.journals where shop_id = v_main;
  select revision into v_revision from public.shop_sync_signals where shop_id = v_main;
  select (pg_catalog.now() at time zone private.shop_display_zone(shop.time_zone))::date
    into v_cairo
  from public.shops as shop
  where shop.id = v_main;

  perform set_config('request.jwt.claim.sub', '', true);
  perform set_config('request.jwt.claim.session_id', '', true);
  begin
    perform public.get_ledger_date_v1(null);
    raise exception 'unauthenticated_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'unauthenticated' then
        raise exception 'expected unauthenticated got %', sqlerrm;
      end if;
  end;
  v_checks := v_checks + 1;

  execute 'set local role anon';
  begin
    perform public.get_ledger_date_v1(null);
    raise exception 'anon_succeeded';
  exception
    when insufficient_privilege then null;
  end;
  execute 'reset role';
  v_checks := v_checks + 1;

  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.session_id', '', true);

  v_page := public.get_ledger_date_v1();
  v_other := public.get_ledger_date_v1(null, null, 100);
  if v_page is distinct from v_other then
    raise exception 'defaults diverged from explicit null date and limit 100';
  end if;
  if (v_page ->> 'business_date') is distinct from pg_catalog.to_char(v_cairo, 'YYYY-MM-DD')
    or (v_page ->> 'server_date') is distinct from (v_page ->> 'business_date')
    or (v_page ->> 'business_date') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or jsonb_array_length(v_page -> 'day_ids') <> 0
    or (v_page ->> 'shop_id') is distinct from v_main::text
    or (v_page ->> 'read_model_version') is distinct from '1'
    or jsonb_typeof(v_page -> 'read_model_version') is distinct from 'number' then
    raise exception 'null date did not resolve the Cairo server date: %', v_page;
  end if;
  v_server := (v_page ->> 'server_date')::date;
  v_checks := v_checks + 2;

  select coalesce(array_agg(key order by key), '{}') into v_keys
  from jsonb_object_keys(v_page) as key;
  if v_keys is distinct from array[
    'business_date', 'day_ids', 'day_summary', 'feed_page',
    'read_model_version', 'server_date', 'shop_id'
  ]::text[] or v_page ?| array['cash', 'stock', 'scrap', 'balance', 'balances'] then
    raise exception 'top-level keys drifted: %', v_keys;
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_keys
  from jsonb_object_keys(v_page -> 'day_summary') as key;
  if v_keys is distinct from array[
    'expense_count', 'expense_piastres', 'gold_by_bucket', 'purchase_count',
    'purchase_piastres', 'sale_count', 'sale_piastres'
  ]::text[] then
    raise exception 'summary keys drifted: %', v_keys;
  end if;
  select coalesce(array_agg(key order by key), '{}') into v_keys
  from jsonb_object_keys(v_page -> 'feed_page') as key;
  if v_keys is distinct from array[
    'day_id', 'direction', 'has_more', 'items', 'limit', 'next_after_sequence',
    'next_before_sequence', 'server_sequence', 'shop_id', 'snapshot_sequence'
  ]::text[]
    or jsonb_typeof(v_page -> 'feed_page' -> 'day_id') is distinct from 'null'
    or (v_page -> 'feed_page' ->> 'direction') is distinct from 'desc'
    or jsonb_typeof(v_page -> 'feed_page' -> 'next_after_sequence') is distinct from 'null' then
    raise exception 'feed page keys drifted: %', v_page -> 'feed_page';
  end if;
  v_checks := v_checks + 3;

  v_page := public.get_ledger_date_v1(date '2020-01-15', null, 100);
  if (v_page ->> 'business_date') is distinct from '2020-01-15'
    or (v_page ->> 'server_date') is distinct from pg_catalog.to_char(v_server, 'YYYY-MM-DD')
    or jsonb_array_length(v_page -> 'day_ids') <> 2
    or (v_page -> 'day_ids' ->> 0) is distinct from v_day_a::text
    or (v_page -> 'day_ids' ->> 1) is distinct from v_day_b::text
    or (v_page -> 'day_summary' ->> 'sale_piastres') is distinct from '9007199254748106'
    or (v_page -> 'day_summary' ->> 'purchase_piastres') is distinct from '9000'
    or (v_page -> 'day_summary' ->> 'expense_piastres') is distinct from '500'
    or (v_page -> 'day_summary' ->> 'sale_count') is distinct from '6'
    or (v_page -> 'day_summary' ->> 'purchase_count') is distinct from '2'
    or (v_page -> 'day_summary' ->> 'expense_count') is distinct from '1'
    or jsonb_typeof(v_page -> 'day_summary' -> 'sale_count') is distinct from 'number'
    or jsonb_typeof(v_page -> 'day_summary' -> 'sale_piastres') is distinct from 'string'
    or (v_page -> 'feed_page' ->> 'server_sequence') is distinct from '60'
    or (v_page -> 'feed_page' ->> 'snapshot_sequence') is distinct from '60'
    or jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 11
    or (v_page -> 'feed_page' ->> 'has_more') is distinct from 'false'
    or (v_page -> 'feed_page' -> 'items' -> 0 ->> 'shop_sequence') is distinct from '60'
    or (v_page -> 'feed_page' -> 'items' -> 0 ->> 'occurred_at')
      > (v_page -> 'feed_page' -> 'items' -> 2 ->> 'occurred_at') then
    raise exception 'selected date aggregate drifted: %', v_page -> 'day_summary';
  end if;
  v_gold := jsonb_build_array(
    jsonb_build_object('kind', 'purchase', 'category', 'scrap', 'karat', 21, 'milligrams', '500', 'count', '0'),
    jsonb_build_object('kind', 'purchase', 'category', 'worked_jewelry', 'karat', 18, 'milligrams', '2500', 'count', '2'),
    jsonb_build_object('kind', 'sale', 'category', 'scrap', 'karat', 21, 'milligrams', '300', 'count', '0'),
    jsonb_build_object('kind', 'sale', 'category', 'worked_jewelry', 'karat', 18, 'milligrams', '1050', 'count', '2'),
    jsonb_build_object('kind', 'sale', 'category', 'worked_jewelry', 'karat', 22, 'milligrams', '9007199254740995', 'count', '2')
  );
  if v_page -> 'day_summary' -> 'gold_by_bucket' is distinct from v_gold then
    raise exception 'gold buckets drifted: %', v_page -> 'day_summary' -> 'gold_by_bucket';
  end if;
  select item.value into v_item
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value)
  where item.value ->> 'shop_sequence' = '1';
  if v_item ->> 'occurred_at_shop' is distinct from '2020-01-15T11:15:30'
    or v_item ->> 'label_ar' is distinct from 'بيع'
    or v_item ->> 'party_name' is distinct from 'عميل أ'
    or v_item ->> 'party_phone' is distinct from '01012345678'
    or v_item ->> 'has_note' is distinct from 'true'
    or v_item ->> 'actor_display_name' is distinct from 'المالك التاريخي' then
    raise exception 'sale feed fields drifted: %', v_item;
  end if;
  select item.value into v_item
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value)
  where item.value ->> 'shop_sequence' = '2';
  if v_item ->> 'kind' is distinct from 'scrap_sale'
    or v_item ->> 'label_ar' is distinct from 'بيع كسر'
    or v_item ->> 'payment_label' is distinct from 'فيزا + كاش'
    or v_item ->> 'party_name' is not null
    or v_item ->> 'party_phone' is not null then
    raise exception 'scrap sale feed drifted: %', v_item;
  end if;
  select item.value into v_item
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value)
  where item.value ->> 'shop_sequence' = '50';
  if v_item ->> 'weight_grams' is distinct from '9007199254740.993'
    or v_item ->> 'total_pounds' is distinct from '90071992547409.93' then
    raise exception 'huge weight wire drifted: %', v_item;
  end if;
  select item.value into v_item
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value)
  where item.value ->> 'shop_sequence' = '7';
  if v_item ->> 'party_name' is distinct from 'دائن'
    or v_item ->> 'total_pounds' is distinct from '0.42'
    or jsonb_typeof(v_item -> 'piece_count') is distinct from 'null'
    or jsonb_typeof(v_item -> 'weight_grams') is distinct from 'null'
    or jsonb_typeof(v_item -> 'payment_label') is distinct from 'null' then
    raise exception 'null array sale drifted: %', v_item;
  end if;
  select item.value into v_item
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value)
  where item.value ->> 'shop_sequence' = '8';
  if v_item ->> 'label_ar' is distinct from 'سداد دين'
    or v_item ->> 'kind' is distinct from 'debt_settlement' then
    raise exception 'debt feed drifted: %', v_item;
  end if;
  select item.value into v_item
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value)
  where item.value ->> 'shop_sequence' = '60';
  if v_item ->> 'is_return' is distinct from 'true'
    or v_item ->> 'kind' is distinct from 'sale_return' then
    raise exception 'return feed drifted: %', v_item;
  end if;
  v_checks := v_checks + 7;

  select coalesce(jsonb_object_agg(item.value ->> 'operation_id', item.value), '{}'::jsonb)
    into v_by_id
  from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value);
  foreach v_day in array array[v_day_a, v_day_b] loop
    v_ref := public.get_ledger_operation_page(v_day, null, null, 100);
    for v_item in
      select item.value from jsonb_array_elements(v_ref -> 'items') as item(value)
    loop
      if v_by_id -> (v_item ->> 'operation_id') is distinct from v_item then
        raise exception 'feed shape diverged for % ref % got %',
          v_item ->> 'operation_id', v_item, v_by_id -> (v_item ->> 'operation_id');
      end if;
      v_shapes := v_shapes + 1;
    end loop;
  end loop;
  if v_shapes <> 11 then
    raise exception 'shape matches were %', v_shapes;
  end if;
  v_checks := v_checks + 1;

  v_before := null;
  loop
    v_page := public.get_ledger_date_v1(date '2020-01-15', v_before, 1);
    v_pages := v_pages + 1;
    if (v_page -> 'day_summary' ->> 'sale_piastres') is distinct from '9007199254748106'
      or (v_page -> 'feed_page' ->> 'server_sequence') is distinct from '60'
      or (v_page -> 'feed_page' ->> 'snapshot_sequence') is distinct from '60'
      or (v_page -> 'feed_page' ->> 'limit') is distinct from '1'
      or jsonb_typeof(v_page -> 'feed_page' -> 'day_id') is distinct from 'null' then
      raise exception 'page summary followed the cursor';
    end if;
    if jsonb_array_length(v_page -> 'feed_page' -> 'items') > 0 then
      select v_seen || coalesce(array_agg((item.value ->> 'shop_sequence')::bigint), '{}'),
             v_ids || coalesce(array_agg((item.value ->> 'operation_id')::uuid), '{}')
        into v_seen, v_ids
      from jsonb_array_elements(v_page -> 'feed_page' -> 'items') as item(value);
    end if;
    exit when v_page -> 'feed_page' ->> 'has_more' is distinct from 'true';
    v_before := v_page -> 'feed_page' ->> 'next_before_sequence';
    if v_before is null or v_pages > 30 then
      raise exception 'date walk stalled at %', v_pages;
    end if;
  end loop;
  if v_pages <> 11
    or v_seen is distinct from array[60, 50, 40, 12, 8, 7, 6, 5, 3, 2, 1]::bigint[]
    or 100 = any (v_seen) or 4 = any (v_seen)
    or exists (
      select 1 from unnest(v_ids) as seen(id)
      join public.financial_operations as operation on operation.id = seen.id
      where operation.shop_id is distinct from v_main
    ) then
    raise exception 'paged date lost a gap, a row, or shop isolation: %', v_seen;
  end if;
  v_page := public.get_ledger_date_v1(date '2020-01-15', '40', 2);
  if (v_page -> 'feed_page' -> 'items' -> 0 ->> 'shop_sequence') is distinct from '12'
    or (v_page -> 'feed_page' ->> 'has_more') is distinct from 'true'
    or (v_page -> 'feed_page' ->> 'next_before_sequence') is distinct from '8'
    or (v_page -> 'day_summary' ->> 'sale_piastres') is distinct from '9007199254748106' then
    raise exception 'cursor filled a sequence gap: %', v_page -> 'feed_page';
  end if;
  v_page := public.get_ledger_date_v1(date '2020-01-15', '1', 100);
  if jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 0
    or (v_page -> 'feed_page' ->> 'has_more') is distinct from 'false'
    or (v_page -> 'feed_page' ->> 'server_sequence') is distinct from '60'
    or (v_page -> 'day_summary' ->> 'purchase_piastres') is distinct from '9000' then
    raise exception 'exhausted cursor changed the date summary';
  end if;
  v_page := public.get_ledger_date_v1(date '2020-01-15', '9223372036854775807', 100);
  if jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 11 then
    raise exception 'max bigint cursor dropped rows';
  end if;
  v_checks := v_checks + 4;

  v_page := public.get_ledger_date_v1(date '2020-01-16', null, 100);
  if jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 1
    or (v_page -> 'feed_page' -> 'items' -> 0 ->> 'shop_sequence') is distinct from '100'
    or (v_page -> 'feed_page' ->> 'server_sequence') is distinct from '100'
    or (v_page -> 'day_summary' ->> 'sale_piastres') is distinct from '999'
    or (v_page -> 'day_summary' ->> 'sale_piastres') like '%9007199254740993%' then
    raise exception 'adjacent date leaked into the selected date';
  end if;
  v_page := public.get_ledger_date_v1(date '2019-01-01', null, 7);
  if jsonb_array_length(v_page -> 'day_ids') <> 1
    or (v_page -> 'day_summary' ->> 'sale_piastres') is distinct from '0'
    or (v_page -> 'day_summary' ->> 'purchase_piastres') is distinct from '0'
    or (v_page -> 'day_summary' ->> 'expense_piastres') is distinct from '0'
    or (v_page -> 'day_summary' ->> 'sale_count') is distinct from '0'
    or jsonb_array_length(v_page -> 'day_summary' -> 'gold_by_bucket') <> 0
    or jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 0
    or (v_page -> 'feed_page' ->> 'server_sequence') is distinct from '0'
    or (v_page -> 'feed_page' ->> 'snapshot_sequence') is distinct from '0'
    or (v_page -> 'feed_page' ->> 'limit') is distinct from '7'
    or (v_page -> 'feed_page' ->> 'has_more') is distinct from 'false' then
    raise exception 'empty session day was not zeroed: %', v_page;
  end if;
  v_page := public.get_ledger_date_v1(date '2018-05-05', null, 100);
  if jsonb_array_length(v_page -> 'day_ids') <> 0
    or (v_page -> 'day_summary' ->> 'sale_count') is distinct from '0'
    or jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 0
    or (v_page -> 'feed_page' ->> 'server_sequence') is distinct from '0'
    or (v_page ->> 'business_date') is distinct from '2018-05-05' then
    raise exception 'missing date was not an explicit empty read: %', v_page;
  end if;
  v_checks := v_checks + 3;

  begin
    perform public.get_ledger_date_v1(v_server + 1, null, 10);
    raise exception 'future_date_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_date' then
        raise exception 'expected invalid_date got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_date_v1('2020-13-40');
    raise exception 'malformed_date_succeeded';
  exception
    when datetime_field_overflow then null;
  end;
  begin
    perform public.get_ledger_date_v1('not-a-date');
    raise exception 'text_date_succeeded';
  exception
    when invalid_datetime_format then null;
  end;
  begin
    perform public.get_ledger_date_v1(date '2020-01-15', '1', '10.5');
    raise exception 'fractional_limit_succeeded';
  exception
    when invalid_text_representation then null;
  end;
  begin
    perform public.get_ledger_date_v1(date '2020-01-15', null, 10, v_main);
    raise exception 'shop_argument_succeeded';
  exception
    when undefined_function then null;
  end;
  foreach v_before in array array['01', '0', '-1', '', '1.2', ' 1'] loop
    begin
      perform public.get_ledger_date_v1(date '2020-01-15', v_before, 10);
      raise exception 'bad_cursor_succeeded: %', v_before;
    exception
      when others then
        if sqlerrm is distinct from 'invalid_input' then
          raise exception 'expected invalid_input for % got %', v_before, sqlerrm;
        end if;
    end;
  end loop;
  begin
    perform public.get_ledger_date_v1(date '2020-01-15', '9223372036854775808', 10);
    raise exception 'overflow_cursor_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'overflow' then
        raise exception 'expected overflow got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_date_v1(date '2020-01-15', null, 0);
    raise exception 'zero_limit_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for limit 0 got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_date_v1(date '2020-01-15', null, 101);
    raise exception 'huge_limit_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for limit 101 got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_date_v1(date '2020-01-15', null, null);
    raise exception 'null_limit_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for null limit got %', sqlerrm;
      end if;
  end;
  v_checks := v_checks + 11;

  if exists (
    select 1 from public.financial_operations as operation
    where operation.shop_id = v_kiri
  ) then
    raise exception 'owner read bypassed financial operation rls';
  end if;
  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000002', true);
  v_page := public.get_ledger_date_v1(null);
  v_kiri_date := (v_page ->> 'server_date')::date;
  v_utc := (pg_catalog.now() at time zone 'UTC')::date;
  if (v_page ->> 'shop_id') is distinct from v_kiri::text
    or v_kiri_date is distinct from (pg_catalog.now() at time zone 'Pacific/Kiritimati')::date
    or jsonb_array_length(v_page -> 'day_ids') <> 0 then
    raise exception 'kiritimati server date drifted: %', v_page;
  end if;
  v_other := public.get_ledger_date_v1(v_kiri_date, null, 100);
  if v_other is distinct from v_page then
    raise exception 'explicit kiritimati today diverged from the null read';
  end if;
  v_page := public.get_ledger_date_v1(date '2020-01-15', null, 100);
  if (v_page ->> 'shop_id') is distinct from v_kiri::text
    or (v_page -> 'day_summary' ->> 'sale_piastres') is distinct from '777'
    or jsonb_array_length(v_page -> 'feed_page' -> 'items') <> 1
    or (v_page -> 'feed_page' -> 'items' -> 0 ->> 'operation_id')
      is distinct from 'e2100000-0000-4000-8000-000000000001'
    or (v_page -> 'feed_page' -> 'items' -> 0 ->> 'party_name') is distinct from 'متجر آخر' then
    raise exception 'cross-shop date read leaked or dropped the other shop';
  end if;
  if v_kiri_date is distinct from v_utc then
    v_boundary := v_boundary + 1;
  end if;
  begin
    perform public.get_ledger_date_v1(v_kiri_date + 1, null, 10);
    raise exception 'kiritimati_future_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_date' then
        raise exception 'expected invalid_date for kiritimati tomorrow got %', sqlerrm;
      end if;
  end;
  v_checks := v_checks + 4;

  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000003', true);
  v_page := public.get_ledger_date_v1(null);
  v_pago_date := (v_page ->> 'server_date')::date;
  if (v_page ->> 'shop_id') is distinct from v_pago::text
    or v_pago_date is distinct from (pg_catalog.now() at time zone 'Pacific/Pago_Pago')::date
    or jsonb_array_length(v_page -> 'day_ids') <> 0 then
    raise exception 'pago server date drifted: %', v_page;
  end if;
  if v_pago_date is distinct from v_utc then
    v_boundary := v_boundary + 1;
    if v_utc > v_pago_date then
      begin
        perform public.get_ledger_date_v1(v_utc, null, 10);
        raise exception 'utc_date_accepted_for_pago';
      exception
        when others then
          if sqlerrm is distinct from 'invalid_date' then
            raise exception 'expected invalid_date for pago utc tomorrow got %', sqlerrm;
          end if;
      end;
    end if;
  end if;
  if v_kiri_date = v_pago_date or v_boundary < 1 then
    raise exception 'display zones collapsed kiri % pago % utc %', v_kiri_date, v_pago_date, v_utc;
  end if;
  v_checks := v_checks + 2;

  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.session_id', '51100000-0000-4000-8000-000000000099', true);
  begin
    perform public.get_ledger_date_v1(null);
    raise exception 'expired_session_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'session_expired' then
        raise exception 'expected session_expired got %', sqlerrm;
      end if;
  end;
  perform set_config('request.jwt.claim.session_id', '', true);
  if (public.get_ledger_date_v1(date '2020-01-15') -> 'day_summary' ->> 'sale_piastres')
      is distinct from '9007199254748106' then
    raise exception 'cleared session lost the owner date';
  end if;
  v_checks := v_checks + 2;

  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000004', true);
  begin
    perform public.get_ledger_date_v1(null);
    raise exception 'revoked_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'forbidden' then
        raise exception 'expected forbidden for revoked owner got %', sqlerrm;
      end if;
  end;
  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000005', true);
  begin
    perform public.get_ledger_date_v1(null);
    raise exception 'anonymous_auth_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'forbidden' then
        raise exception 'expected forbidden for anonymous auth got %', sqlerrm;
      end if;
  end;
  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000006', true);
  begin
    perform public.get_ledger_date_v1(null);
    raise exception 'pending_entitlement_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'shop_unavailable' then
        raise exception 'expected shop_unavailable got %', sqlerrm;
      end if;
  end;
  perform set_config('request.jwt.claim.sub', 'a1100000-0000-4000-8000-000000000007', true);
  v_page := public.get_ledger_date_v1(null);
  if (v_page ->> 'shop_id') is distinct from 'b1100000-0000-4000-8000-000000000007'
    or jsonb_array_length(v_page -> 'day_ids') <> 0 then
    raise exception 'expired entitlement lost the existing reader path';
  end if;
  v_checks := v_checks + 4;

  execute 'reset role';
  select count(*) into v_ops_after from public.financial_operations where shop_id = v_main;
  select count(*) into v_days_after from public.business_days where shop_id = v_main;
  select count(*) into v_journals_after from public.journals where shop_id = v_main;
  select revision into v_revision_after from public.shop_sync_signals where shop_id = v_main;
  if v_ops_after is distinct from v_ops
    or v_days_after is distinct from v_days
    or v_journals_after is distinct from v_journals
    or v_revision_after is distinct from v_revision then
    raise exception 'ledger date read mutated shop state';
  end if;
  v_checks := v_checks + 1;

  if v_checks < 40 or v_shapes <> 11 or v_pages <> 11 then
    raise exception 'suite counts checks % shapes % pages %', v_checks, v_shapes, v_pages;
  end if;
  raise notice 'LEDGER_DATE_CHECKS %', v_checks;
  raise notice 'LEDGER_DATE_SHAPE_MATCHES %', v_shapes;
  raise notice 'LEDGER_DATE_PAGES %', v_pages;
end;
$test$;

select 'ledger_date_read_passed' as test_result;
rollback;

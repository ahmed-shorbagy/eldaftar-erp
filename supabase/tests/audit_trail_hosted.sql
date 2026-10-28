-- AUD-01 owner audit trail: hosted rollback-only verification for the
-- development project xchapwvmvoefriqcxtvn. Every fixture rolls back.
begin;

do $hosted_guard$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20261028120000'
  ) then
    raise exception 'audit_trail_migration_not_applied';
  end if;
  if current_setting('app.eldaftar_dev_guard', true) is distinct from 'xchapwvmvoefriqcxtvn' then
    perform set_config('app.eldaftar_dev_guard', 'xchapwvmvoefriqcxtvn', true);
  end if;
end;
$hosted_guard$;
-- AUD-01 owner audit trail. Fixtures roll back. Runs as postgres after
-- every migration, including 20261028120000_owner_audit_trail.sql.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous,
  deleted_at, banned_until, created_at, updated_at, raw_user_meta_data
) values
  ('a4000000-0000-4000-8000-0000000000a1', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-owner@example.test', now(), false,
   null, null, now(), now(), '{}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a2', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-expired@example.test', now(), false,
   null, null, now(), now(), '{}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a3', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-employee@example.test', now(), false,
   null, null, now(), now(), '{"display_name":"موظف البيع"}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a4', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-partner@example.test', now(), false,
   null, null, now(), now(), '{"display_name":"شريك المتجر"}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a5', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-pending@example.test', now(), false,
   null, null, now(), now(), '{}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a6', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-revoked@example.test', now(), false,
   null, null, now(), now(), '{}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a7', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-other@example.test', now(), false,
   null, null, now(), now(), '{}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a8', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-anon@example.test', now(), true,
   null, null, now(), now(), '{}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000a9', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-counter@example.test', now(), false,
   null, null, now(), now(), '{"display_name":"عدّاد التقفيل"}'::jsonb),
  ('a4000000-0000-4000-8000-0000000000aa', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'audit-unnamed@example.test', now(), false,
   null, null, now(), now(), '{}'::jsonb);

insert into public.shops (
  id, name, owner_display_name, time_zone, created_by, setup_request_key
) values
  ('a4100000-0000-4000-8000-000000000001', 'متجر السجل', 'مالك السجل',
   'Africa/Cairo', 'a4000000-0000-4000-8000-0000000000a1', 'a4150000-0000-4000-8000-000000000001'),
  ('a4100000-0000-4000-8000-000000000002', 'متجر السجل المنتهي', 'مالك منتهي',
   'Africa/Cairo', 'a4000000-0000-4000-8000-0000000000a2', 'a4150000-0000-4000-8000-000000000002'),
  ('a4100000-0000-4000-8000-000000000003', 'متجر السجل المنتظر', 'مالك منتظر',
   'Africa/Cairo', 'a4000000-0000-4000-8000-0000000000a5', 'a4150000-0000-4000-8000-000000000003'),
  ('a4100000-0000-4000-8000-000000000004', 'متجر السجل المسحوب', 'مالك مسحوب',
   'Africa/Cairo', 'a4000000-0000-4000-8000-0000000000a6', 'a4150000-0000-4000-8000-000000000004'),
  ('a4100000-0000-4000-8000-000000000005', 'متجر سجل آخر', 'مالك آخر',
   'Africa/Cairo', 'a4000000-0000-4000-8000-0000000000a7', 'a4150000-0000-4000-8000-000000000005');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('a4100000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a1', 'owner', null),
  ('a4100000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-0000000000a2', 'owner', null),
  ('a4100000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a3', 'employee', null),
  ('a4100000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a4', 'partner', null),
  ('a4100000-0000-4000-8000-000000000003', 'a4000000-0000-4000-8000-0000000000a5', 'owner', null),
  ('a4100000-0000-4000-8000-000000000004', 'a4000000-0000-4000-8000-0000000000a6', 'owner', now()),
  ('a4100000-0000-4000-8000-000000000005', 'a4000000-0000-4000-8000-0000000000a7', 'owner', null),
  ('a4100000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000aa', 'employee', null);

insert into public.shop_member_grants (shop_id, user_id, permission, granted_by)
select 'a4100000-0000-4000-8000-000000000001',
       'a4000000-0000-4000-8000-0000000000a4',
       permission,
       'a4000000-0000-4000-8000-0000000000a1'
from unnest(array['sale','purchase','inventory','expense','reports','invoice_send']) as permission;

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a4100000-0000-4000-8000-000000000001', now() - interval '10 days', now() + interval '10 days'),
  ('a4100000-0000-4000-8000-000000000002', now() - interval '30 days', now() - interval '1 hour'),
  ('a4100000-0000-4000-8000-000000000005', now() - interval '10 days', now() + interval '10 days');

insert into public.closing_staff_accounts (shop_id, user_id, display_name, phone, created_by)
values (
  'a4100000-0000-4000-8000-000000000001',
  'a4000000-0000-4000-8000-0000000000a9',
  'عدّاد التقفيل',
  '201555000099',
  'a4000000-0000-4000-8000-0000000000a1'
);

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('a4300000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a1', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-0000000000a2', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000003', 'a4000000-0000-4000-8000-0000000000a3', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000004', 'a4000000-0000-4000-8000-0000000000a4', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000005', 'a4000000-0000-4000-8000-0000000000a5', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000006', 'a4000000-0000-4000-8000-0000000000a6', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000007', 'a4000000-0000-4000-8000-0000000000a7', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000008', 'a4000000-0000-4000-8000-0000000000a8', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-000000000009', 'a4000000-0000-4000-8000-0000000000a9', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-00000000000a', 'a4000000-0000-4000-8000-0000000000aa', now(), now(), now() + interval '1 day'),
  ('a4300000-0000-4000-8000-00000000000b', 'a4000000-0000-4000-8000-0000000000a1', now(), now(), now() - interval '1 minute');

insert into public.business_days (id, shop_id, business_date, opened_at, status)
select day_id, shop_id, (opened_at at time zone 'Africa/Cairo')::date, opened_at, 'open'
from (
  values
    ('a4400000-0000-4000-8000-000000000001'::uuid, 'a4100000-0000-4000-8000-000000000001'::uuid, timestamptz '2026-10-28 08:00:00+00'),
    ('a4400000-0000-4000-8000-000000000002'::uuid, 'a4100000-0000-4000-8000-000000000002'::uuid, timestamptz '2026-10-28 08:00:00+00'),
    ('a4400000-0000-4000-8000-000000000005'::uuid, 'a4100000-0000-4000-8000-000000000005'::uuid, timestamptz '2026-10-28 08:00:00+00')
) as seed(day_id, shop_id, opened_at);

insert into public.financial_operations (
  id, shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
) values
  ('a4500000-0000-4000-8000-000000000001', 'a4100000-0000-4000-8000-000000000001', 1, 'sale',
   'a4400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a3', timestamptz '2026-10-28 11:00:00+00'),
  ('a4500000-0000-4000-8000-000000000002', 'a4100000-0000-4000-8000-000000000001', 2, 'expense',
   'a4400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a1', timestamptz '2026-10-28 13:00:00+00'),
  ('a4500000-0000-4000-8000-000000000003', 'a4100000-0000-4000-8000-000000000001', 3, 'sale',
   'a4400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a1', timestamptz '2026-10-28 15:00:00+00'),
  ('a4500000-0000-4000-8000-000000000004', 'a4100000-0000-4000-8000-000000000001', 4, 'sale',
   'a4400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a3', timestamptz '2026-10-28 11:00:00+00'),
  ('a4500000-0000-4000-8000-000000000005', 'a4100000-0000-4000-8000-000000000001', 5, 'inventory_removal',
   'a4400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000aa', timestamptz '2026-10-28 14:00:00+00'),
  ('a4500000-0000-4000-8000-000000000006', 'a4100000-0000-4000-8000-000000000001', 6, 'sale',
   'a4400000-0000-4000-8000-000000000001', 'a4000000-0000-4000-8000-0000000000a1', timestamptz '2026-10-28 12:00:00+00'),
  ('a4500000-0000-4000-8000-000000000007', 'a4100000-0000-4000-8000-000000000002', 1, 'sale',
   'a4400000-0000-4000-8000-000000000002', 'a4000000-0000-4000-8000-0000000000a2', timestamptz '2026-10-28 09:00:00+00'),
  ('a4500000-0000-4000-8000-000000000008', 'a4100000-0000-4000-8000-000000000005', 1, 'sale',
   'a4400000-0000-4000-8000-000000000005', 'a4000000-0000-4000-8000-0000000000a7', timestamptz '2026-10-28 09:00:00+00');

insert into public.financial_audit_events (
  id, shop_id, actor_user_id, action, operation_id, created_at, details
) values
  ('a4200000-0000-4000-8000-000000000001', 'a4100000-0000-4000-8000-000000000001',
   'a4000000-0000-4000-8000-0000000000a3', 'sale_confirmed',
   'a4500000-0000-4000-8000-000000000001', timestamptz '2026-10-28 11:00:00+00',
   '{"business_day_id":"a4400000-0000-4000-8000-000000000001","operation_id":"a4500000-0000-4000-8000-000000000001"}'::jsonb),
  ('a4200000-0000-4000-8000-000000000002', 'a4100000-0000-4000-8000-000000000001',
   'a4000000-0000-4000-8000-0000000000a1', 'expense_confirmed',
   'a4500000-0000-4000-8000-000000000002', timestamptz '2026-10-28 13:00:00+00',
   '{"phone":"+201012345678","email":"pii@example.test","exception":"EXCEPTION_DUMP secret stack","has_attachment":true,"count_observations":{"cash":"999"}}'::jsonb),
  ('a4200000-0000-4000-8000-000000000003', 'a4100000-0000-4000-8000-000000000001',
   'a4000000-0000-4000-8000-0000000000a1', 'trade_deleted',
   'a4500000-0000-4000-8000-000000000003', timestamptz '2026-10-28 15:00:00+00',
   '{"action":"delete","operation_id":"a4500000-0000-4000-8000-000000000003"}'::jsonb),
  ('a4200000-0000-4000-8000-000000000004', 'a4100000-0000-4000-8000-000000000001',
   'a4000000-0000-4000-8000-0000000000a3', 'sale_confirmed',
   'a4500000-0000-4000-8000-000000000004', timestamptz '2026-10-28 11:00:00+00',
   '{"operation_id":"a4500000-0000-4000-8000-000000000004"}'::jsonb),
  ('a4200000-0000-4000-8000-000000000005', 'a4100000-0000-4000-8000-000000000001',
   'a4000000-0000-4000-8000-0000000000aa', 'inventory_removal_confirmed',
   'a4500000-0000-4000-8000-000000000005', timestamptz '2026-10-28 14:00:00+00',
   '{"operation_id":"a4500000-0000-4000-8000-000000000005"}'::jsonb),
  ('a4200000-0000-4000-8000-000000000006', 'a4100000-0000-4000-8000-000000000001',
   'a4000000-0000-4000-8000-0000000000a1', 'trade_edited',
   'a4500000-0000-4000-8000-000000000006', timestamptz '2026-10-28 12:00:00+00',
   '{"replacement_operation_id":"a4500000-0000-4000-8000-000000000004","exception":"EXCEPTION_DUMP"}'::jsonb),
  ('a4200000-0000-4000-8000-000000000007', 'a4100000-0000-4000-8000-000000000002',
   'a4000000-0000-4000-8000-0000000000a2', 'sale_confirmed',
   'a4500000-0000-4000-8000-000000000007', timestamptz '2026-10-28 09:00:00+00',
   '{"operation_id":"a4500000-0000-4000-8000-000000000007"}'::jsonb),
  ('a4200000-0000-4000-8000-000000000008', 'a4100000-0000-4000-8000-000000000005',
   'a4000000-0000-4000-8000-0000000000a7', 'sale_confirmed',
   'a4500000-0000-4000-8000-000000000008', timestamptz '2026-10-28 09:00:00+00',
   '{"operation_id":"a4500000-0000-4000-8000-000000000008"}'::jsonb);

create function pg_temp.audit_call(p_role text, p_user text, p_session text, p_sql text)
returns text
language plpgsql
as $fn$
declare
  v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claim.role', p_role, true);
  execute format('set local role %I', p_role);
  begin
    execute 'select (' || p_sql || ')::text' into v;
    execute 'reset role';
    return v;
  exception when others then
    execute 'reset role';
    return sqlerrm;
  end;
end;
$fn$;

do $test$
declare
  v_text text;
  v_page jsonb;
  v_again jsonb;
  v_ids text[];
  v_count integer;
  v_ops bigint;
  v_audits bigint;
  v_ops_after bigint;
  v_audits_after bigint;
  v_summary text;
begin
  if has_function_privilege(
       'anon',
       'public.list_shop_audit_trail_v1(text,timestamptz,uuid,integer)',
       'EXECUTE'
     )
     or has_function_privilege(
       'service_role',
       'public.list_shop_audit_trail_v1(text,timestamptz,uuid,integer)',
       'EXECUTE'
     )
     or not has_function_privilege(
       'authenticated',
       'public.list_shop_audit_trail_v1(text,timestamptz,uuid,integer)',
       'EXECUTE'
     ) then
    raise exception 'list_grant_mismatch';
  end if;
  if has_function_privilege('authenticated', 'private.audit_trail_family(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.audit_trail_action_label(text)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.audit_trail_summary(text,jsonb,bigint,date)', 'EXECUTE')
     or has_function_privilege('authenticated', 'private.audit_trail_actor_name(uuid,uuid)', 'EXECUTE')
     or not has_function_privilege('authenticated', 'private.audit_trail_owner_visible(uuid)', 'EXECUTE') then
    raise exception 'helper_grant_mismatch';
  end if;
  if has_table_privilege('authenticated', 'public.financial_audit_events', 'INSERT')
     or has_table_privilege('authenticated', 'public.financial_audit_events', 'UPDATE')
     or has_table_privilege('authenticated', 'public.financial_audit_events', 'DELETE')
     or has_table_privilege('anon', 'public.financial_audit_events', 'SELECT') then
    raise exception 'audit_write_or_anon_select_granted';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'financial_audit_events'
      and policyname = 'financial_audit_events_select_opening'
  ) or not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'public'
      and tablename = 'financial_audit_events'
      and policyname = 'financial_audit_events_select_owner'
  ) then
    raise exception 'audit_select_policy_mismatch';
  end if;
  if private.audit_trail_action_label('sale_confirmed') is distinct from 'بيع'
     or private.audit_trail_action_label('trade_deleted') is distinct from 'حذف عملية'
     or private.audit_trail_action_label('inventory_removal_confirmed') is distinct from 'خصم مخزون'
     or private.audit_trail_action_label('not_a_real_action') is distinct from 'عملية مسجّلة'
     or private.audit_trail_family('trade_edited') is distinct from 'change'
     or private.audit_trail_family('trade_deleted') is distinct from 'delete'
     or private.audit_trail_family('expense_confirmed') is distinct from 'deduction'
     or private.audit_trail_family('sale_confirmed') is distinct from 'post' then
    raise exception 'label_or_family_mismatch';
  end if;

  begin
    update public.financial_audit_events
      set details = '{"tamper":true}'::jsonb
      where id = 'a4200000-0000-4000-8000-000000000003';
    raise exception 'update_allowed';
  exception when others then
    if sqlerrm not ilike '%audit_append_only%' then
      raise exception 'update_wrong: %', sqlerrm;
    end if;
  end;
  begin
    delete from public.financial_audit_events
      where id = 'a4200000-0000-4000-8000-000000000003';
    raise exception 'delete_allowed';
  exception when others then
    if sqlerrm not ilike '%audit_append_only%' then
      raise exception 'delete_wrong: %', sqlerrm;
    end if;
  end;

  perform set_config('request.jwt.claim.sub', 'a4000000-0000-4000-8000-0000000000a1', true);
  perform set_config('request.jwt.claim.session_id', 'a4300000-0000-4000-8000-000000000001', true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  begin
    execute 'set local role authenticated';
    update public.financial_audit_events
      set details = '{"tamper":true}'::jsonb
      where id = 'a4200000-0000-4000-8000-000000000003';
    execute 'reset role';
    raise exception 'authenticated_update_allowed';
  exception
    when insufficient_privilege then
      execute 'reset role';
    when others then
      execute 'reset role';
      if sqlerrm not ilike '%audit_append_only%'
         and sqlerrm not ilike '%permission denied%' then
        raise exception 'authenticated_update_wrong: %', sqlerrm;
      end if;
  end;

  perform set_config('request.jwt.claim.sub', 'a4000000-0000-4000-8000-0000000000a4', true);
  perform set_config('request.jwt.claim.session_id', 'a4300000-0000-4000-8000-000000000004', true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.financial_audit_events;
  execute 'reset role';
  if v_count <> 0 then
    raise exception 'partner_saw_audit_rows: %', v_count;
  end if;

  perform set_config('request.jwt.claim.sub', 'a4000000-0000-4000-8000-0000000000a1', true);
  perform set_config('request.jwt.claim.session_id', 'a4300000-0000-4000-8000-000000000001', true);
  execute 'set local role authenticated';
  select count(*) into v_count from public.financial_audit_events;
  execute 'reset role';
  if v_count <> 6 then
    raise exception 'owner_select_count: %', v_count;
  end if;

  select count(*) into v_ops from public.financial_operations;
  select count(*) into v_audits from public.financial_audit_events;

  v_text := pg_temp.audit_call(
    'authenticated', null, null,
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%unauthenticated%' then
    raise exception 'missing_user_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a8',
    'a4300000-0000-4000-8000-000000000008',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%forbidden%' then
    raise exception 'anonymous_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-00000000000b',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%session_expired%' then
    raise exception 'expired_session_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a3',
    'a4300000-0000-4000-8000-000000000003',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%forbidden%' then
    raise exception 'employee_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a4',
    'a4300000-0000-4000-8000-000000000004',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%forbidden%' then
    raise exception 'partner_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a9',
    'a4300000-0000-4000-8000-000000000009',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%forbidden%' then
    raise exception 'counter_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a6',
    'a4300000-0000-4000-8000-000000000006',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%forbidden%' then
    raise exception 'revoked_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a5',
    'a4300000-0000-4000-8000-000000000005',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  if v_text not ilike '%shop_unavailable%' then
    raise exception 'pending_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1('nope', null, null, 20)$q$);
  if v_text not ilike '%invalid_input%' then
    raise exception 'bad_family_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1(null, null, 'a4200000-0000-4000-8000-000000000003', 20)$q$);
  if v_text not ilike '%invalid_input%' then
    raise exception 'half_cursor_accepted: %', v_text;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1(null, timestamptz '2026-10-28 09:00:00+00', 'a4200000-0000-4000-8000-000000000008', 20)$q$);
  if v_text not ilike '%stale_cursor%' then
    raise exception 'cross_shop_cursor_accepted: %', v_text;
  end if;

  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$);
  v_page := v_text::jsonb;
  v_again := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$)::jsonb;
  if v_page->'entries' is distinct from v_again->'entries'
     or v_page->'next_cursor_id' is distinct from v_again->'next_cursor_id'
     or v_page->>'time_zone' is distinct from v_again->>'time_zone' then
    raise exception 'unstable_page';
  end if;
  select coalesce(array_agg(value->>'id' order by ordinality), array[]::text[])
    into v_ids
  from jsonb_array_elements(v_page->'entries') with ordinality as item(value, ordinality);
  if v_ids <> array[
    'a4200000-0000-4000-8000-000000000003',
    'a4200000-0000-4000-8000-000000000005',
    'a4200000-0000-4000-8000-000000000002',
    'a4200000-0000-4000-8000-000000000006',
    'a4200000-0000-4000-8000-000000000004',
    'a4200000-0000-4000-8000-000000000001'
  ] then
    raise exception 'order_mismatch: %', v_ids;
  end if;
  if v_page->'entries'->0->>'action_label' is distinct from 'حذف عملية'
     or v_page->'entries'->0->>'actor_display_name' is distinct from 'مالك السجل'
     or v_page->'entries'->0->>'shop_sequence' is distinct from '3'
     or v_page->'entries'->0->>'action_family' is distinct from 'delete'
     or position('حذف دون بديل' in (v_page->'entries'->0->>'summary')) = 0
     or v_page->'entries'->1->>'actor_display_name' is not null
     or v_page->'entries'->1->>'action_label' is distinct from 'خصم مخزون'
     or v_page->'entries'->4->>'actor_display_name' is distinct from 'موظف البيع'
     or v_page->>'time_zone' is distinct from 'Africa/Cairo'
     or v_page->>'next_cursor_id' is not null
     or v_page::text ilike '%EXCEPTION_DUMP%'
     or v_page::text ilike '%+201012345678%'
     or v_page::text ilike '%pii@example.test%'
     or v_page::text ilike '%count_observations%'
     or v_page::text ilike '%"details"%'
     or position(
       'a4500000-0000-4000-8000-000000000004'
       in (v_page->'entries'->3->>'summary')
     ) > 0 then
    raise exception 'feed_shape_mismatch: %', v_page;
  end if;
  v_summary := v_page->'entries'->2->>'summary';
  if position('تسلسل 2' in v_summary) = 0
     or position('مع مرفق' in v_summary) = 0
     or position('2026-10-28' in v_summary) = 0 then
    raise exception 'expense_summary: %', v_summary;
  end if;
  if (v_page->'entries'->0->>'created_at_shop') is distinct from pg_catalog.to_char(
       timestamptz '2026-10-28 15:00:00+00' at time zone 'Africa/Cairo',
       'YYYY-MM-DD HH24:MI:SS'
     ) then
    raise exception 'shop_local_time: %', v_page->'entries'->0->>'created_at_shop';
  end if;
  if position('مع عملية بديلة' in (v_page->'entries'->3->>'summary')) = 0 then
    raise exception 'edit_summary: %', v_page->'entries'->3->>'summary';
  end if;

  v_page := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 2)$q$)::jsonb;
  if v_page->'entries'->0->>'id' is distinct from 'a4200000-0000-4000-8000-000000000003'
     or v_page->'entries'->1->>'id' is distinct from 'a4200000-0000-4000-8000-000000000005'
     or v_page->>'next_cursor_id' is distinct from 'a4200000-0000-4000-8000-000000000005' then
    raise exception 'page_window: %', v_page;
  end if;
  v_page := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    format(
      $q$select public.list_shop_audit_trail_v1(null, %L::timestamptz, %L::uuid, 2)$q$,
      v_page->>'next_cursor_at',
      v_page->>'next_cursor_id'
    )
  )::jsonb;
  if v_page->'entries'->0->>'id' is distinct from 'a4200000-0000-4000-8000-000000000002' then
    raise exception 'page_two: %', v_page->'entries'->0->>'id';
  end if;

  v_page := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1('deduction', null, null, 20)$q$)::jsonb;
  select coalesce(array_agg(value->>'id' order by ordinality), array[]::text[])
    into v_ids
  from jsonb_array_elements(v_page->'entries') with ordinality as item(value, ordinality);
  if v_ids <> array[
    'a4200000-0000-4000-8000-000000000005',
    'a4200000-0000-4000-8000-000000000002'
  ] then
    raise exception 'deduction_filter: %', v_ids;
  end if;
  v_text := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a1',
    'a4300000-0000-4000-8000-000000000001',
    $q$select public.list_shop_audit_trail_v1('delete', timestamptz '2026-10-28 14:00:00+00', 'a4200000-0000-4000-8000-000000000005', 20)$q$);
  if v_text not ilike '%stale_cursor%' then
    raise exception 'cross_family_cursor_accepted: %', v_text;
  end if;

  v_page := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a2',
    'a4300000-0000-4000-8000-000000000002',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$)::jsonb;
  if jsonb_array_length(v_page->'entries') <> 1
     or v_page->'entries'->0->>'id' is distinct from 'a4200000-0000-4000-8000-000000000007'
     or v_page->'entries'->0->>'actor_display_name' is distinct from 'مالك منتهي' then
    raise exception 'expired_owner_read: %', v_page;
  end if;
  v_page := pg_temp.audit_call(
    'authenticated',
    'a4000000-0000-4000-8000-0000000000a7',
    'a4300000-0000-4000-8000-000000000007',
    $q$select public.list_shop_audit_trail_v1(null, null, null, 20)$q$)::jsonb;
  if jsonb_array_length(v_page->'entries') <> 1
     or v_page->'entries'->0->>'operation_id' is distinct from 'a4500000-0000-4000-8000-000000000008' then
    raise exception 'cross_shop_leak: %', v_page;
  end if;

  select count(*) into v_ops_after from public.financial_operations;
  select count(*) into v_audits_after from public.financial_audit_events;
  if v_ops_after <> v_ops or v_audits_after <> v_audits then
    raise exception 'read_mutated ops %/% audits %/%', v_ops_after, v_ops, v_audits_after, v_audits;
  end if;
end;
$test$;

rollback;

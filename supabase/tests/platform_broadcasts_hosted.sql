-- Rollback-only checks for subscriber broadcasts (ADR 0048, ADM-06).
-- Synthetic admins, owners and shops exist only inside this transaction.
-- Existing shops may also be in "all"/status audiences, so status segments
-- are checked by membership of the synthetic shops, and counts against the
-- audience rule. Hosted execution must set eldaftar.test_project_ref.
begin isolation level repeatable read;

do $guard$
begin
  if not coalesce((
    (inet_server_addr() = '127.0.0.1'::inet
      and current_database() ~ '^eldaftar_broadcasts_')
    or current_setting('eldaftar.test_project_ref', true) = 'xchapwvmvoefriqcxtvn'
  ), false) then
    raise exception 'explicit_development_or_local_test_target_required';
  end if;
  if to_regprocedure('public.list_my_broadcasts_v1()') is null then
    raise exception 'broadcast_migration_missing';
  end if;
end;
$guard$;

-- 1 admin, 2 owner A (active, ends in 2 days), 3 owner B (expired),
-- 4 owner C (pending), 5 partner of A, 6 banned admin
insert into auth.users
  (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at,
   raw_user_meta_data, raw_app_meta_data, deleted_at, banned_until)
select ('e4900000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
  'broadcast-hosted-' || n || '@example.test', false, now(), now(),
  '{}'::jsonb, '{}'::jsonb, null,
  case when n = 6 then now() + interval '1 day' else null end
from generate_series(1, 6) n;

insert into public.shops (id, name, created_at)
select ('e4930000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'تحقق_الرسائل_' || n,
  timestamptz '2020-05-01 00:00:00.123456+00'
from generate_series(1, 4) n;

insert into public.shop_memberships (shop_id, user_id, role) values
  ('e4930000-0000-4000-8000-000000000001', 'e4900000-0000-4000-8000-000000000002', 'owner'),
  ('e4930000-0000-4000-8000-000000000002', 'e4900000-0000-4000-8000-000000000003', 'owner'),
  ('e4930000-0000-4000-8000-000000000003', 'e4900000-0000-4000-8000-000000000004', 'owner'),
  ('e4930000-0000-4000-8000-000000000001', 'e4900000-0000-4000-8000-000000000005', 'partner');
-- Shop 4 has no owner and is never a recipient.

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('e4930000-0000-4000-8000-000000000001', now() - interval '20 days', now() + interval '2 days'),
  ('e4930000-0000-4000-8000-000000000002', now() - interval '60 days', now() - interval '1 day');

insert into public.platform_admins (user_id) values
  ('e4900000-0000-4000-8000-000000000001'),
  ('e4900000-0000-4000-8000-000000000006');

insert into auth.sessions (id, user_id, created_at, updated_at, not_after) values
  ('e4920000-0000-4000-8000-000000000001', 'e4900000-0000-4000-8000-000000000001', now(), now(), now() + interval '1 day');

create function pg_temp.bc_call(p_user text, p_session text, p_sql text,
  p_role text default 'authenticated') returns text language plpgsql as $fn$
declare v text;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user, ''), true);
  perform set_config('request.jwt.claim.session_id', coalesce(p_session, ''), true);
  perform set_config('request.jwt.claims', '', true);
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

-- Admin send helper: returns the JSON result or the error text.
create function pg_temp.bc_send(p_key text, p_segment text, p_days integer, p_shop text,
  p_title text, p_starts timestamptz, p_ends timestamptz, p_expected integer) returns text
language plpgsql as $fn$
begin
  return pg_temp.bc_call('e4900000-0000-4000-8000-000000000001', 'e4920000-0000-4000-8000-000000000001',
    format('public.admin_send_broadcast_v1(%L::uuid, %L, %s, %s, %L, %L, %L, %s, %s, %s)',
      p_key, p_segment,
      coalesce(p_days::text, 'null'),
      case when p_shop is null then 'null' else quote_literal(p_shop) || '::uuid' end,
      p_title, 'نص الرسالة السري للفحص', 'https://example.test/renew',
      case when p_starts is null then 'null' else quote_literal(p_starts) || '::timestamptz' end,
      case when p_ends is null then 'null' else quote_literal(p_ends) || '::timestamptz' end,
      coalesce(p_expected::text, 'null')));
end;
$fn$;

do $checks$
declare
  v_admin constant text := 'e4900000-0000-4000-8000-000000000001';
  v_session constant text := 'e4920000-0000-4000-8000-000000000001';
  v_owner_a constant text := 'e4900000-0000-4000-8000-000000000002';
  v_owner_b constant text := 'e4900000-0000-4000-8000-000000000003';
  v_owner_c constant text := 'e4900000-0000-4000-8000-000000000004';
  v_partner constant text := 'e4900000-0000-4000-8000-000000000005';
  v_shop_a constant text := 'e4930000-0000-4000-8000-000000000001';
  v_shop_b constant text := 'e4930000-0000-4000-8000-000000000002';
  v_shop_c constant text := 'e4930000-0000-4000-8000-000000000003';
  v_shop_d constant text := 'e4930000-0000-4000-8000-000000000004';
  v jsonb;
  v_text text;
  v_msg_a uuid;
  v_msg_expired uuid;
  v_msg_later uuid;
  v_expired_count integer;
  v_audit_before integer;
begin
  -- Grants.
  if has_table_privilege('authenticated', 'public.platform_broadcasts', 'select')
    or has_table_privilege('authenticated', 'public.platform_broadcast_recipients', 'select')
    or has_function_privilege('anon', 'public.list_my_broadcasts_v1()', 'execute')
    or has_function_privilege('anon', 'public.admin_send_broadcast_v1(uuid,text,integer,uuid,text,text,text,timestamptz,timestamptz,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.admin_list_broadcasts_v1(text,integer)', 'execute')
    or not has_function_privilege('authenticated', 'public.mark_broadcast_read_v1(uuid)', 'execute') then
    raise exception 'grants';
  end if;

  -- Audience membership follows the directory rule; ownerless shops never count.
  if not exists (select 1 from private.broadcast_audience('active', null, null, now()) a where a.shop_id = v_shop_a::uuid)
    or not exists (select 1 from private.broadcast_audience('expiring', 3, null, now()) a where a.shop_id = v_shop_a::uuid)
    or exists (select 1 from private.broadcast_audience('expiring', 1, null, now()) a where a.shop_id = v_shop_a::uuid)
    or not exists (select 1 from private.broadcast_audience('expired', null, null, now()) a where a.shop_id = v_shop_b::uuid)
    or not exists (select 1 from private.broadcast_audience('pending', null, null, now()) a where a.shop_id = v_shop_c::uuid)
    or exists (select 1 from private.broadcast_audience('pending', null, null, now()) a where a.shop_id = v_shop_a::uuid)
    or exists (select 1 from private.broadcast_audience('all', null, null, now()) a where a.shop_id = v_shop_d::uuid)
    or (select count(*) from private.broadcast_audience('all', null, null, now()))
      <> (select count(distinct shop_id) from public.shop_memberships where role = 'owner' and revoked_at is null) then
    raise exception 'audience_rule';
  end if;

  -- Boundaries.
  if pg_temp.bc_call(null, null, 'public.admin_preview_broadcast_audience_v1(''all'')') <> 'unauthenticated'
    or pg_temp.bc_call(v_owner_a, null, 'public.admin_preview_broadcast_audience_v1(''all'')') <> 'forbidden'
    or pg_temp.bc_call('e4900000-0000-4000-8000-000000000006', null, 'public.admin_preview_broadcast_audience_v1(''all'')') <> 'forbidden'
    or pg_temp.bc_call(v_owner_a, null, 'public.admin_list_broadcasts_v1()') <> 'forbidden'
    or pg_temp.bc_call(v_owner_a, null, format(
      'public.admin_send_broadcast_v1(''e4940000-0000-4000-8000-000000000001''::uuid, ''shop'', null, %L::uuid, ''عنوان'', ''نص'', null, null, null, 1)', v_shop_a))
      not like '%unauthorized%'
    or pg_temp.bc_call(v_admin, v_session, 'list_my_broadcasts_v1()') not like '%unauthorized%' then
    raise exception 'boundaries';
  end if;

  -- Preview and validation.
  v := pg_temp.bc_call(v_admin, v_session, format('public.admin_preview_broadcast_audience_v1(''shop'', null, %L::uuid)', v_shop_a))::jsonb;
  if v->>'recipient_count' <> '1' then raise exception 'preview_shop %', v; end if;
  v := pg_temp.bc_call(v_admin, v_session, format('public.admin_preview_broadcast_audience_v1(''shop'', null, %L::uuid)', v_shop_d))::jsonb;
  if v->>'recipient_count' <> '0' then raise exception 'preview_ownerless %', v; end if;
  if pg_temp.bc_call(v_admin, v_session, 'public.admin_preview_broadcast_audience_v1(''expiring'')') not like '%invalid_input%'
    or pg_temp.bc_call(v_admin, v_session, 'public.admin_preview_broadcast_audience_v1(''expiring'', 91)') not like '%invalid_input%'
    or pg_temp.bc_call(v_admin, v_session, 'public.admin_preview_broadcast_audience_v1(''everyone'')') not like '%invalid_input%'
    or pg_temp.bc_call(v_admin, v_session, 'public.admin_preview_broadcast_audience_v1(''shop'', null, ''e4930000-0000-4000-8000-000000000099''::uuid)') not like '%not_found%' then
    raise exception 'preview_validation';
  end if;

  select count(*) into v_audit_before from public.platform_admin_audit_events where family = 'broadcast';

  -- Send validation, changed audience and empty audience write nothing.
  if pg_temp.bc_send('e4940000-0000-4000-8000-000000000002', 'shop', null, v_shop_a, repeat('ع', 81), null, null, 1) not like '%invalid_input%'
    or pg_temp.bc_send('e4940000-0000-4000-8000-000000000002', 'shop', null, v_shop_a, 'عنوان', null, now() - interval '1 day', 1) not like '%invalid_input%'
    or pg_temp.bc_send('e4940000-0000-4000-8000-000000000002', 'shop', null, v_shop_a, 'عنوان', now() + interval '91 days', null, 1) not like '%invalid_input%'
    or pg_temp.bc_send('e4940000-0000-4000-8000-000000000002', 'shop', null, v_shop_a, 'عنوان', null, null, 2) not like '%audience_changed%'
    or pg_temp.bc_send('e4940000-0000-4000-8000-000000000002', 'shop', null, v_shop_a, 'عنوان', null, null, null) not like '%audience_changed%'
    or pg_temp.bc_send('e4940000-0000-4000-8000-000000000002', 'shop', null, v_shop_d, 'عنوان', null, null, 0) not like '%empty_audience%' then
    raise exception 'send_validation';
  end if;
  if exists (select 1 from public.platform_broadcasts where request_key = 'e4940000-0000-4000-8000-000000000002') then
    raise exception 'rejected_send_wrote';
  end if;

  -- Send to shop A, replay, key reuse.
  v := pg_temp.bc_send('e4940000-0000-4000-8000-000000000010', 'shop', null, v_shop_a, 'تجديد الاشتراك', null, null, 1)::jsonb;
  if v->>'status' <> 'sent' or v->>'recipient_count' <> '1'
    or (v->>'ends_at')::timestamptz <> (v->>'starts_at')::timestamptz + interval '30 days' then
    raise exception 'send_a %', v;
  end if;
  v_msg_a := (v->>'broadcast_id')::uuid;
  v := pg_temp.bc_send('e4940000-0000-4000-8000-000000000010', 'shop', null, v_shop_a, 'تجديد الاشتراك', null, null, 1)::jsonb;
  if v->>'status' <> 'replayed' or (v->>'broadcast_id')::uuid <> v_msg_a then raise exception 'replay %', v; end if;
  if pg_temp.bc_send('e4940000-0000-4000-8000-000000000010', 'shop', null, v_shop_a, 'عنوان آخر', null, null, 1)
      not like '%request_key_reused%' then
    raise exception 'key_reuse';
  end if;
  if (select count(*) from public.platform_broadcasts where request_key = 'e4940000-0000-4000-8000-000000000010') <> 1
    or (select array_agg(shop_id) from public.platform_broadcast_recipients where broadcast_id = v_msg_a) <> array[v_shop_a::uuid] then
    raise exception 'send_a_rows';
  end if;

  -- Expired segment: frozen list includes B and excludes A.
  select count(*) into v_expired_count from private.broadcast_audience('expired', null, null, now());
  v := pg_temp.bc_send('e4940000-0000-4000-8000-000000000011', 'expired', null, null, 'اشتراكك منتهٍ', null, null, v_expired_count)::jsonb;
  if v->>'status' <> 'sent' or (v->>'recipient_count')::integer <> v_expired_count then raise exception 'send_expired %', v; end if;
  v_msg_expired := (v->>'broadcast_id')::uuid;
  if not exists (select 1 from public.platform_broadcast_recipients where broadcast_id = v_msg_expired and shop_id = v_shop_b::uuid)
    or exists (select 1 from public.platform_broadcast_recipients where broadcast_id = v_msg_expired and shop_id = v_shop_a::uuid) then
    raise exception 'expired_members';
  end if;

  -- Scheduled message for shop A is not visible yet.
  v := pg_temp.bc_send('e4940000-0000-4000-8000-000000000012', 'shop', null, v_shop_a, 'رسالة لاحقة', now() + interval '1 day', now() + interval '3 days', 1)::jsonb;
  v_msg_later := (v->>'broadcast_id')::uuid;
  if v->>'status' <> 'sent' then raise exception 'send_later %', v; end if;

  -- Owner A inbox: one visible unread message, delivery stamped once.
  v := pg_temp.bc_call(v_owner_a, null, 'public.list_my_broadcasts_v1()')::jsonb;
  if v->>'unread_count' <> '1' or jsonb_array_length(v->'rows') <> 1
    or (v->'rows'->0->>'id')::uuid <> v_msg_a
    or v->'rows'->0->>'read_at' is not null
    or v->>'shop_id' <> v_shop_a then
    raise exception 'inbox_a %', v;
  end if;
  if (select delivered_at from public.platform_broadcast_recipients where broadcast_id = v_msg_a) is null
    or (select delivered_at from public.platform_broadcast_recipients where broadcast_id = v_msg_later) is not null then
    raise exception 'delivery_stamp';
  end if;

  -- Owner B sees only the expired message; partner and pending owner C see their own scope.
  v := pg_temp.bc_call(v_owner_b, null, 'public.list_my_broadcasts_v1()')::jsonb;
  if jsonb_array_length(v->'rows') <> 1 or (v->'rows'->0->>'id')::uuid <> v_msg_expired then
    raise exception 'inbox_b %', v;
  end if;
  v := pg_temp.bc_call(v_owner_c, null, 'public.list_my_broadcasts_v1()')::jsonb;
  if jsonb_array_length(v->'rows') <> 0 or v->>'unread_count' <> '0' then raise exception 'inbox_c %', v; end if;
  if pg_temp.bc_call(v_partner, null, 'public.list_my_broadcasts_v1()') not like '%unauthorized%'
    or pg_temp.bc_call(v_partner, null, format('public.mark_broadcast_read_v1(%L::uuid)', v_msg_a)) not like '%unauthorized%' then
    raise exception 'partner_denied';
  end if;

  -- Read marking is idempotent and per shop.
  v := pg_temp.bc_call(v_owner_a, null, format('public.mark_broadcast_read_v1(%L::uuid)', v_msg_a))::jsonb;
  if v->>'status' <> 'read' then raise exception 'read %', v; end if;
  v := pg_temp.bc_call(v_owner_a, null, format('public.mark_broadcast_read_v1(%L::uuid)', v_msg_a))::jsonb;
  if v->>'status' <> 'already_read' then raise exception 'read_again %', v; end if;
  if pg_temp.bc_call(v_owner_b, null, format('public.mark_broadcast_read_v1(%L::uuid)', v_msg_a)) not like '%not_found%'
    or pg_temp.bc_call(v_owner_a, null, format('public.mark_broadcast_read_v1(%L::uuid)', v_msg_later)) not like '%not_found%' then
    raise exception 'read_scope';
  end if;
  v := pg_temp.bc_call(v_owner_a, null, 'public.list_my_broadcasts_v1()')::jsonb;
  if v->>'unread_count' <> '0' or v->'rows'->0->>'read_at' is null then raise exception 'inbox_after_read %', v; end if;

  -- Admin history with counts and states.
  v := pg_temp.bc_call(v_admin, v_session, 'public.admin_list_broadcasts_v1(null, 50)')::jsonb;
  if (select r->>'state' from jsonb_array_elements(v->'rows') r where (r->>'id')::uuid = v_msg_a) <> 'active'
    or (select r->>'state' from jsonb_array_elements(v->'rows') r where (r->>'id')::uuid = v_msg_later) <> 'scheduled'
    or (select r->>'recipient_count' || '/' || (r->>'delivered_count') || '/' || (r->>'read_count')
        from jsonb_array_elements(v->'rows') r where (r->>'id')::uuid = v_msg_a) <> '1/1/1'
    or (select r->>'segment_shop_name' from jsonb_array_elements(v->'rows') r where (r->>'id')::uuid = v_msg_a) <> 'تحقق_الرسائل_1'
    or (select r->>'created_by_email' from jsonb_array_elements(v->'rows') r where (r->>'id')::uuid = v_msg_a) <> 'broadcast-hosted-1@example.test' then
    raise exception 'admin_list %', v;
  end if;
  -- The three sends share created_at (statement time), so keyset order
  -- falls back to id descending.
  v := pg_temp.bc_call(v_admin, v_session, 'public.admin_list_broadcasts_v1(null, 1)')::jsonb;
  if v->>'next_cursor' is null
    or (v->'rows'->0->>'id')::uuid <> greatest(v_msg_a, v_msg_expired, v_msg_later) then
    raise exception 'paging %', v;
  end if;
  v := pg_temp.bc_call(v_admin, v_session, format('public.admin_list_broadcasts_v1(%L, 1)', v->>'next_cursor'))::jsonb;
  if (v->'rows'->0->>'id')::uuid >= greatest(v_msg_a, v_msg_expired, v_msg_later)
    or (v->'rows'->0->>'id')::uuid not in (v_msg_a, v_msg_expired, v_msg_later) then
    raise exception 'paging_next %', v;
  end if;

  -- Withdrawal hides the message and is recorded once.
  if pg_temp.bc_call(v_admin, v_session, format('public.admin_withdraw_broadcast_v1(%L::uuid, ''ab'')', v_msg_a)) not like '%invalid_input%' then
    raise exception 'withdraw_validation';
  end if;
  v := pg_temp.bc_call(v_admin, v_session, format('public.admin_withdraw_broadcast_v1(%L::uuid, ''أُرسلت بالخطأ'')', v_msg_a))::jsonb;
  if v->>'status' <> 'withdrawn' then raise exception 'withdraw %', v; end if;
  v := pg_temp.bc_call(v_admin, v_session, format('public.admin_withdraw_broadcast_v1(%L::uuid, ''مرة ثانية'')', v_msg_a))::jsonb;
  if v->>'status' <> 'already_withdrawn' then raise exception 'withdraw_again %', v; end if;
  v := pg_temp.bc_call(v_owner_a, null, 'public.list_my_broadcasts_v1()')::jsonb;
  if jsonb_array_length(v->'rows') <> 0 then raise exception 'withdrawn_visible %', v; end if;

  -- Immutability.
  begin
    update public.platform_broadcasts set title_ar = 'تعديل' where id = v_msg_expired;
    raise exception 'edit_allowed';
  exception when others then
    if sqlerrm <> 'broadcast_immutable' then raise; end if;
  end;
  begin
    delete from public.platform_broadcast_recipients where broadcast_id = v_msg_expired;
    raise exception 'recipient_delete_allowed';
  exception when others then
    if sqlerrm <> 'broadcast_recipient_immutable' then raise; end if;
  end;

  -- Audit: three sends and one withdrawal, without bodies or links.
  if (select count(*) from public.platform_admin_audit_events where family = 'broadcast') <> v_audit_before + 4 then
    raise exception 'audit_count';
  end if;
  v := pg_temp.bc_call(v_admin, v_session, format(
    'public.admin_list_audit_events_v1(''broadcast'', %L::uuid, null, 50)', v_admin))::jsonb;
  if (select count(*) from jsonb_array_elements(v->'rows') r where r->>'action' = 'broadcast_sent') <> 3
    or (select count(*) from jsonb_array_elements(v->'rows') r where r->>'action' = 'broadcast_withdrawn') <> 1
    or v::text like '%نص الرسالة السري للفحص%'
    or v::text like '%example.test/renew%' then
    raise exception 'audit %', v;
  end if;
end;
$checks$;

select 'PLATFORM_BROADCASTS_HOSTED_PASSED' as result;

rollback;

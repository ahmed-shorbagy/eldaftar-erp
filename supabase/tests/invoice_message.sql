-- SET-04 invoice message templates. Synthetic rows roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, deleted_at, created_at, updated_at
) values
  ('b1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-owner@example.test', now(), false, null, now(), now()),
  ('b2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-other@example.test', now(), false, null, now(), now()),
  ('b3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-revoked@example.test', now(), false, null, now(), now()),
  ('b4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-anon-user@example.test', now(), true, null, now(), now()),
  ('b5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-admin@example.test', now(), false, null, now(), now()),
  ('b6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-pending@example.test', now(), false, null, now(), now()),
  ('b7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-expired@example.test', now(), false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1222222-2222-4222-8222-222222222222', 'متجر الرسالة', 'مالك الرسالة', 'Asia/Riyadh'),
  ('b2222222-2222-4222-8222-222222222222', 'متجر آخر', 'مالك آخر', 'Africa/Cairo'),
  ('b3222222-2222-4222-8222-222222222222', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('b6222222-2222-4222-8222-222222222222', 'متجر معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('b7222222-2222-4222-8222-222222222222', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo'),
  ('b8222222-2222-4222-8222-222222222222', 'متجر النطاق', 'مالك النطاق', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('b1222222-2222-4222-8222-222222222222', 'b1111111-1111-4111-8111-111111111111', 'owner', null),
  ('b2222222-2222-4222-8222-222222222222', 'b2111111-1111-4111-8111-111111111111', 'owner', null),
  ('b3222222-2222-4222-8222-222222222222', 'b3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('b6222222-2222-4222-8222-222222222222', 'b6111111-1111-4111-8111-111111111111', 'owner', null),
  ('b7222222-2222-4222-8222-222222222222', 'b7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('b7222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days');

insert into public.platform_admins (user_id)
values ('b5111111-1111-4111-8111-111111111111');

create function pg_temp.expect_code(p_sql text, p_code text)
returns void language plpgsql as $fn$
begin
  begin
    execute p_sql;
    raise exception using message = 'call_succeeded';
  exception when others then
    if sqlerrm = 'call_succeeded' then
      raise exception using message = 'expected_' || p_code;
    elsif sqlerrm is distinct from p_code then
      raise exception using message = 'expected_' || p_code || '_got_' || sqlerrm;
    end if;
  end;
end;
$fn$;

create function pg_temp.message_fail()
returns trigger language plpgsql as $fn$
begin
  raise exception 'message_test_failure';
end;
$fn$;

create function pg_temp.protected_digest()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_name text;
  v_digest text;
  v_out jsonb := '{}'::jsonb;
begin
  foreach v_name in array array[
    'financial_operations', 'financial_operation_details', 'financial_command_requests',
    'financial_audit_events', 'journals', 'journal_postings',
    'invoice_dispatch_confirmations', 'purchase_cash_payables',
    'invoice_appearance_revisions', 'invoice_appearance_audits', 'invoice_appearance_requests',
    'invoice_presentation_revisions', 'invoice_presentation_requests', 'invoice_logo_assets',
    'repairs', 'repair_events', 'repair_custody_events',
    'shop_debts', 'debt_events', 'inventory_lots', 'gold_obligations', 'customers',
    'business_days'
  ] loop
    execute format(
      'select md5(coalesce((select string_agg(to_jsonb(t)::text, %L order by to_jsonb(t)::text) from public.%I as t), ''''))',
      ',',
      v_name
    ) into v_digest;
    v_out := v_out || pg_catalog.jsonb_build_object(v_name, v_digest);
  end loop;
  return v_out;
end;
$fn$;

create function pg_temp.sha256_hex(p_text text)
returns text
language sql
security definer
set search_path = ''
as $fn$
  select pg_catalog.encode(extensions.digest(pg_catalog.convert_to(p_text, 'UTF8'), 'sha256'), 'hex');
$fn$;

do $catalog$
declare
  v_def text;
begin
  if (select message_revision from public.shop_sync_signals
      where shop_id = 'b1222222-2222-4222-8222-222222222222') is distinct from 0
    or (select appearance_revision from public.shop_sync_signals
      where shop_id = 'b1222222-2222-4222-8222-222222222222') is distinct from 0 then
    raise exception 'message_revision_baseline';
  end if;
  if (select count(*) from public.business_days
      where shop_id = 'b1222222-2222-4222-8222-222222222222') is distinct from 0 then
    raise exception 'day_not_required_fixture';
  end if;
  v_def := pg_get_functiondef('private.bump_shop_sync(uuid,text)'::regprocedure);
  if v_def not like '%''ledger''%'
    or v_def not like '%''inventory''%'
    or v_def not like '%''trader''%'
    or v_def not like '%''invoice''%'
    or v_def not like '%''day''%'
    or v_def not like '%''location''%'
    or v_def not like '%''subscription''%'
    or v_def not like '%''repair''%'
    or v_def not like '%''debt''%'
    or v_def not like '%''customer''%'
    or v_def not like '%''appearance''%'
    or v_def not like '%''message''%' then
    raise exception 'sync_scopes_missing';
  end if;
  if pg_get_functiondef('private.shop_sync_touch()'::regprocedure)
      like '%invoice_message_revisions%'
    or pg_get_functiondef('private.shop_sync_touch()'::regprocedure)
      not like '%invoice_appearance_revisions%' then
    raise exception 'sync_touch_unchanged';
  end if;
  if exists (
    select 1 from pg_catalog.pg_trigger as trg
    join pg_catalog.pg_proc as proc on proc.oid = trg.tgfoid
    join pg_catalog.pg_class as rel on rel.oid = trg.tgrelid
    where proc.proname = 'shop_sync_touch'
      and rel.relname like 'invoice_message%'
  ) then
    raise exception 'message_table_double_bump_trigger';
  end if;
  if (
    select array_agg(column_name::text order by column_name::text)
    from information_schema.columns
    where table_schema = 'public' and table_name = 'invoice_message_audits'
  ) is distinct from array[
    'actor_user_id', 'created_at', 'id', 'idempotency_key', 'previous_length',
    'previous_revision', 'previous_sha256', 'revision', 'shop_id',
    'template_length', 'template_sha256'
  ]::text[] then
    raise exception 'audit_columns';
  end if;
  if exists (
    select 1 from pg_catalog.pg_policy
    where polrelid in (
      'public.invoice_message_revisions'::regclass,
      'public.invoice_message_audits'::regclass,
      'public.invoice_message_requests'::regclass
    )
      and polcmd <> 'r'
  ) or (
    select count(*) from pg_catalog.pg_policy
    where polrelid in (
      'public.invoice_message_revisions'::regclass,
      'public.invoice_message_audits'::regclass,
      'public.invoice_message_requests'::regclass
    )
  ) is distinct from 3 then
    raise exception 'message_rls_policies';
  end if;
  if not has_table_privilege('authenticated', 'public.invoice_message_revisions', 'select')
    or has_table_privilege('authenticated', 'public.invoice_message_revisions', 'insert')
    or has_table_privilege('authenticated', 'public.invoice_message_audits', 'update')
    or has_table_privilege('authenticated', 'public.invoice_message_requests', 'delete')
    or has_table_privilege('anon', 'public.invoice_message_revisions', 'select')
    or has_function_privilege('anon', 'public.get_invoice_message_v1()', 'execute')
    or has_function_privilege('authenticated', 'private.invoice_message_normalize(jsonb)', 'execute')
    or not has_function_privilege('authenticated', 'public.post_invoice_message_v1(uuid,jsonb)', 'execute') then
    raise exception 'message_grants';
  end if;
  if not exists (
    select 1 from pg_catalog.pg_proc
    where oid = 'public.post_invoice_message_v1(uuid,jsonb)'::regprocedure
      and prosecdef
      and 'search_path=""' = any (proconfig)
  ) or not exists (
    select 1 from pg_catalog.pg_proc
    where oid = 'public.get_invoice_message_source_v1(uuid)'::regprocedure
      and prosecdef
      and 'search_path=""' = any (proconfig)
  ) then
    raise exception 'message_function_hardening';
  end if;
end;
$catalog$;

set local role anon;
do $anon$
begin
  perform public.get_invoice_message_v1();
  raise exception 'anon_read_succeeded';
exception
  when insufficient_privilege then null;
  when others then
    if sqlerrm = 'anon_read_succeeded' then
      raise exception 'anon_read_succeeded';
    elsif sqlerrm is distinct from 'unauthenticated' then
      raise exception 'anon_unexpected_%', sqlerrm;
    end if;
end;
$anon$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_code('select public.get_invoice_message_v1()', 'unauthenticated');

select set_config('request.jwt.claim.sub', 'b3111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b3111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_invoice_message_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'b4111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b4111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":true}', true);
select pg_temp.expect_code('select public.get_invoice_message_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'b5111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b5111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_invoice_message_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'b6111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b6111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_invoice_message_v1()', 'shop_unavailable');

select set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

do $owner$
declare
  v_shop uuid := 'b1222222-2222-4222-8222-222222222222';
  v_read jsonb;
  v_review jsonb;
  v_payload jsonb;
  v_result jsonb;
  v_replay jsonb;
  v_status jsonb;
  v_before jsonb;
  v_after jsonb;
  v_sync jsonb;
  v_sync_after jsonb;
  v_message bigint;
  v_global bigint;
  v_rows int;
  v_audits int;
  v_marker text := 'MSGTOKEN77 {sequence}';
  v_emoji text := convert_from(decode('f09f91a8e2808df09f9189', 'hex'), 'UTF8') || ' {kind}';
  v_zwj_len int;
begin
  v_read := public.get_invoice_message_v1();
  if (v_read ->> 'revision') is distinct from '0'
    or v_read -> 'template' is distinct from 'null'::jsonb
    or v_read -> 'created_at' is distinct from 'null'::jsonb
    or v_read -> 'created_at_shop' is distinct from 'null'::jsonb
    or v_read -> 'can_write' is distinct from 'true'::jsonb
    or (v_read ->> 'time_zone') is distinct from 'Asia/Riyadh'
    or (v_read ->> 'version') is distinct from '1'
    or (v_read ->> 'shop_id') is distinct from v_shop::text then
    raise exception 'absent_default';
  end if;
  if (
    select coalesce(array_agg(entry.key order by entry.key), '{}')
    from jsonb_object_keys(v_read) as entry(key)
  ) is distinct from array[
    'can_write', 'created_at', 'created_at_shop', 'revision', 'shop_id',
    'template', 'time_zone', 'version'
  ]::text[] then
    raise exception 'read_keys';
  end if;

  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":"1","kind":"invoice_message","expected_revision":"0","template":"{sequence}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"01","template":"{sequence}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"-1","template":"{sequence}"}''::jsonb)',
    'negative_amount'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{sequence}","customer_phone":"+201012345678"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"9","template":"{remaining}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{total"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{seq{uence}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"stray }"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{Sequence}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{customer_phone}"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.review_invoice_message_v1(''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"a\u0001b"}''::jsonb)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', 'a' || E'\r' || 'b')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', E'\r{sequence}')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', '{sequence}' || E'\r')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', E'\r')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', U&'a\202Eb')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', U&'a\FEFFb')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', convert_from(decode('e2808c', 'hex'), 'UTF8'))::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', U&'\FFFE')::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', repeat('م', 401))::text
    ),
    'invalid_input'
  );
  perform pg_temp.expect_code(
    format(
      'select public.review_invoice_message_v1(%L::jsonb)',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', repeat(E'س\n', 9) || 'خ')::text
    ),
    'invalid_input'
  );
  begin
    perform '{"template":"\uD800"}'::jsonb;
    raise exception 'surrogate_accepted';
  exception when others then
    if sqlerrm = 'surrogate_accepted' then
      raise exception 'surrogate_accepted';
    end if;
  end;
  begin
    perform pg_catalog.convert_from(decode('ff', 'hex'), 'UTF8');
    raise exception 'malformed_utf8_accepted';
  exception when others then
    if sqlerrm = 'malformed_utf8_accepted' or sqlerrm not like '%UTF8%' then
      raise exception 'malformed_utf8_%', sqlerrm;
    end if;
  end;

  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', '  https://example.test <b>{kind}</b>  '
  ));
  if (v_review ->> 'status') is distinct from 'ready'
    or (v_review -> 'normalized' ->> 'template') is distinct from 'https://example.test <b>{kind}</b>'
    or v_review -> 'normalized' ? 'customer_phone' then
    raise exception 'literal_text_ready';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', repeat('م', 400)
  ));
  if (v_review ->> 'status') is distinct from 'ready'
    or pg_catalog.char_length(v_review -> 'normalized' ->> 'template') is distinct from 400 then
    raise exception 'scalar_cap';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', repeat(E'س\n', 8) || 'خ'
  ));
  if (v_review ->> 'status') is distinct from 'ready' then
    raise exception 'newline_cap';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', U&'\00A0{{sequence}}\00A0'
  ));
  if (v_review -> 'normalized' ->> 'template') is distinct from '{{sequence}}' then
    raise exception 'nbsp_escape';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', U&'a\00A0b {paid}'
  ));
  if (v_review -> 'normalized' ->> 'template') is distinct from U&'a\00A0b {paid}' then
    raise exception 'internal_nbsp';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', E'سطر\r\n{kind}'
  ));
  if (v_review ->> 'status') is distinct from 'ready'
    or (v_review -> 'normalized' ->> 'template') is distinct from E'سطر\n{kind}' then
    raise exception 'crlf_normalized';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', '   '
  ));
  if (v_review ->> 'status') is distinct from 'ready'
    or v_review -> 'normalized' -> 'template' is distinct from 'null'::jsonb then
    raise exception 'whitespace_review';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', E'\t\t'
  ));
  if (v_review ->> 'status') is distinct from 'ready'
    or v_review -> 'normalized' -> 'template' is distinct from 'null'::jsonb then
    raise exception 'tab_reset';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', U&'\00A0\00A0'
  ));
  if (v_review ->> 'status') is distinct from 'ready'
    or v_review -> 'normalized' -> 'template' is distinct from 'null'::jsonb then
    raise exception 'nbsp_reset';
  end if;
  if v_review ? 'normalized' is false or (v_review ->> 'current_revision') is distinct from '0' then
    raise exception 'review_shape';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '4',
    'template', '{sequence}'
  ));
  if (v_review ->> 'status') is distinct from 'stale'
    or v_review ? 'normalized' then
    raise exception 'stale_review';
  end if;

  v_payload := jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0',
    'template', E'  MSGTOKEN77 {sequence}\r\n'
  );
  v_before := pg_temp.protected_digest();
  select to_jsonb(s) - 'updated_at' into v_sync
  from public.shop_sync_signals as s where s.shop_id = v_shop;
  v_result := public.post_invoice_message_v1('b1555555-5555-4555-8555-555555555555', v_payload);
  if (v_result ->> 'revision') is distinct from '1'
    or (v_result ->> 'template') is distinct from v_marker
    or v_result -> 'payload' is distinct from v_payload
    or (v_result ->> 'replayed') is distinct from 'false'
    or (v_result ->> 'kind') is distinct from 'invoice_message'
    or (v_result ->> 'cash_piastres') is distinct from '0'
    or (v_result ->> 'gold_milligrams') is distinct from '0'
    or (v_result ->> 'stock_milligrams') is distinct from '0'
    or v_result -> 'invoice_effect' is distinct from 'false'::jsonb
    or v_result -> 'dispatch_effect' is distinct from 'false'::jsonb
    or (v_result ->> 'actor_user_id') is distinct from 'b1111111-1111-4111-8111-111111111111'
    or (v_result ->> 'key') is distinct from 'b1555555-5555-4555-8555-555555555555' then
    raise exception 'message_save';
  end if;
  if (
    select coalesce(array_agg(entry.key order by entry.key), '{}')
    from jsonb_object_keys(v_result) as entry(key)
  ) is distinct from array[
    'actor_user_id', 'at', 'cash_piastres', 'dispatch_effect', 'gold_milligrams',
    'invoice_effect', 'key', 'kind', 'payload', 'replayed', 'revision', 'shop_id',
    'stock_milligrams', 'template', 'version'
  ]::text[] then
    raise exception 'receipt_keys';
  end if;
  v_replay := public.post_invoice_message_v1('b1555555-5555-4555-8555-555555555555', v_payload);
  if (v_replay ->> 'replayed') is distinct from 'true'
    or v_replay -> 'payload' is distinct from v_payload
    or (select count(*) from public.invoice_message_revisions where shop_id = v_shop) is distinct from 1
    or (select count(*) from public.invoice_message_audits where shop_id = v_shop) is distinct from 1
    or (select result ->> 'replayed' from public.invoice_message_requests
        where idempotency_key = 'b1555555-5555-4555-8555-555555555555') is distinct from 'false' then
    raise exception 'message_replay';
  end if;
  perform pg_temp.expect_code(
    'select public.post_invoice_message_v1(''b1555555-5555-4555-8555-555555555555'', ''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"changed"}''::jsonb)',
    'payload_mismatch'
  );
  perform pg_temp.expect_code(
    'select public.post_invoice_message_v1(''b1555555-5555-4555-8555-555555555556'', ''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"{sequence}"}''::jsonb)',
    'stale_message'
  );
  v_status := public.get_invoice_message_status_v1('b1666666-6666-4666-8666-666666666666', v_payload);
  if (v_status ->> 'status') is distinct from 'absent' then
    raise exception 'status_absent';
  end if;
  v_status := public.get_invoice_message_status_v1('b1555555-5555-4555-8555-555555555555', v_payload);
  if (v_status ->> 'status') is distinct from 'completed'
    or v_status -> 'result' is distinct from (v_result) then
    raise exception 'status_completed';
  end if;
  perform pg_temp.expect_code(
    'select public.get_invoice_message_status_v1(''b1555555-5555-4555-8555-555555555555'', ''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"other"}''::jsonb)',
    'payload_mismatch'
  );
  v_read := public.get_invoice_message_v1();
  if (v_read ->> 'revision') is distinct from '1'
    or (v_read ->> 'template') is distinct from v_marker
    or v_read -> 'created_at' is not distinct from 'null'::jsonb
    or (v_read ->> 'created_at') is distinct from (v_result ->> 'at')
    or (v_read ->> 'created_at_shop') is distinct from (
      select to_char(created_at at time zone 'Asia/Riyadh', 'YYYY-MM-DD"T"HH24:MI:SS')
      from public.invoice_message_revisions where shop_id = v_shop and revision = 1
    ) then
    raise exception 'saved_read';
  end if;
  if exists (
    select 1 from public.invoice_message_audits
    where shop_id = v_shop and position('MSGTOKEN77' in to_jsonb(invoice_message_audits)::text) > 0
  ) or not exists (
    select 1 from public.invoice_message_requests
    where shop_id = v_shop and position('MSGTOKEN77' in to_jsonb(invoice_message_requests)::text) > 0
  ) then
    raise exception 'audit_leaked_template';
  end if;
  if (
    select template_length = char_length(v_marker)
      and template_sha256 = pg_temp.sha256_hex(v_marker)
      and previous_revision = 0
      and previous_length is null
      and previous_sha256 is null
      and actor_user_id = 'b1111111-1111-4111-8111-111111111111'
    from public.invoice_message_audits where shop_id = v_shop and revision = 1
  ) is distinct from true then
    raise exception 'audit_fingerprint';
  end if;
  select to_jsonb(s) - 'updated_at' into v_sync_after
  from public.shop_sync_signals as s where s.shop_id = v_shop;
  if (v_sync_after ->> 'message_revision')::bigint is distinct from (v_sync ->> 'message_revision')::bigint + 1
    or (v_sync_after ->> 'revision')::bigint is distinct from (v_sync ->> 'revision')::bigint + 1
    or (v_sync_after - 'message_revision' - 'revision')
      is distinct from (v_sync - 'message_revision' - 'revision') then
    raise exception 'message_sync_scope';
  end if;
  v_after := pg_temp.protected_digest();
  if v_after is distinct from v_before then
    raise exception 'finance_digest_changed_%', v_after;
  end if;

  v_result := public.post_invoice_message_v1(
    'b1777777-7777-4777-8777-777777777777',
    jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '1', 'template', E' \r\n ')
  );
  if (v_result ->> 'revision') is distinct from '2'
    or v_result -> 'template' is distinct from 'null'::jsonb
    or (public.get_invoice_message_v1() ->> 'revision') is distinct from '2'
    or public.get_invoice_message_v1() -> 'template' is distinct from 'null'::jsonb
    or public.get_invoice_message_v1() -> 'created_at' = 'null'::jsonb
    or exists (
      select 1 from public.invoice_message_revisions
      where shop_id = v_shop and template like '%يرجى مراجعة%'
    ) then
    raise exception 'whitespace_reset';
  end if;

  v_zwj_len := char_length(v_emoji);
  v_result := public.post_invoice_message_v1(
    'b1888888-8888-4888-8888-888888888888',
    jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '2', 'template', v_emoji)
  );
  if (v_result ->> 'template') is distinct from v_emoji
    or char_length(v_result ->> 'template') is distinct from v_zwj_len
    or v_zwj_len is distinct from 10
    or (
      select template_length from public.invoice_message_audits
      where shop_id = v_shop and revision = 3
    ) is distinct from v_zwj_len then
    raise exception 'emoji_scalars';
  end if;
  if public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '3',
    'template', convert_from(decode('e298baefb88f', 'hex'), 'UTF8') || ' {total}'
  )) ->> 'status' is distinct from 'ready' then
    raise exception 'variation_selector';
  end if;

  v_result := public.post_invoice_message_v1(
    'b1999999-9999-4999-8999-999999999999',
    jsonb_build_object(
      'version', 1, 'kind', 'invoice_message', 'expected_revision', '3',
      'template', '{sequence}{kind}{shop_name}{operation_time}{total}{customer_name}{item_count}{grams_14}{grams_18}{grams_21}{grams_22}{grams_24}{paid}{obligation}'
    )
  );
  if (v_result ->> 'revision') is distinct from '4' then
    raise exception 'allowlist_save';
  end if;
  v_result := public.post_invoice_message_v1(
    'b1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '4', 'template', null)
  );
  if (v_result ->> 'revision') is distinct from '5'
    or v_result -> 'template' is distinct from 'null'::jsonb then
    raise exception 'explicit_null_reset';
  end if;

  select count(*) into v_rows from public.invoice_message_revisions where shop_id = v_shop;
  select count(*) into v_audits from public.invoice_message_audits where shop_id = v_shop;
  select message_revision, revision into v_message, v_global
  from public.shop_sync_signals where shop_id = v_shop;
  v_before := pg_temp.protected_digest();
end;
$owner$;

reset role;
do $scopes$
declare
  v_shop uuid := 'b8222222-2222-4222-8222-222222222222';
  v_row public.shop_sync_signals%rowtype;
  v_scope text;
begin
  select * into v_row from public.shop_sync_signals where shop_id = v_shop;
  foreach v_scope in array array['ledger', 'inventory', 'trader', 'invoice', 'day', 'location', 'subscription', 'repair', 'debt', 'customer', 'appearance'] loop
    perform private.bump_shop_sync(v_shop, v_scope);
  end loop;
  if (select message_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.message_revision
    or (select appearance_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.appearance_revision + 1
    or (select ledger_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.ledger_revision + 1
    or (select invoice_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.invoice_revision + 1
    or (select repair_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.repair_revision + 1
    or (select customer_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.customer_revision + 1
    or (select revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.revision + 11 then
    raise exception 'prior_scopes';
  end if;
  perform private.bump_shop_sync(v_shop, 'message');
  if (select message_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.message_revision + 1
    or (select appearance_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.appearance_revision + 1
    or (select ledger_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_row.ledger_revision + 1 then
    raise exception 'message_scope_isolated';
  end if;
end;
$scopes$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

do $rollback$
declare
  v_shop uuid := 'b1222222-2222-4222-8222-222222222222';
  v_rows int;
  v_audits int;
  v_requests int;
  v_message bigint;
  v_appearance bigint;
  v_digest jsonb;
begin
  select count(*) into v_rows from public.invoice_message_revisions where shop_id = v_shop;
  select count(*) into v_audits from public.invoice_message_audits where shop_id = v_shop;
  select count(*) into v_requests from public.invoice_message_requests where shop_id = v_shop;
  select message_revision, appearance_revision into v_message, v_appearance
  from public.shop_sync_signals where shop_id = v_shop;
  v_digest := pg_temp.protected_digest();
  reset role;
  create trigger message_test_failure
    after insert on public.invoice_message_audits
    for each row execute function pg_temp.message_fail();
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
  perform set_config('request.jwt.claims', '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
  begin
    perform public.post_invoice_message_v1(
      'b1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '5', 'template', 'لن يُحفظ {sequence}')
    );
    raise exception 'message_partial_commit';
  exception when others then
    if sqlerrm is distinct from 'message_test_failure' then
      raise exception 'rollback_got_%', sqlerrm;
    end if;
  end;
  reset role;
  drop trigger message_test_failure on public.invoice_message_audits;
  if (select count(*) from public.invoice_message_revisions where shop_id = v_shop) is distinct from v_rows
    or (select count(*) from public.invoice_message_audits where shop_id = v_shop) is distinct from v_audits
    or (select count(*) from public.invoice_message_requests where shop_id = v_shop) is distinct from v_requests
    or (select message_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_message
    or (select appearance_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_appearance
    or pg_temp.protected_digest() is distinct from v_digest then
    raise exception 'message_partial_commit';
  end if;
end;
$rollback$;

reset role;
insert into public.business_days (id, shop_id, business_date, opened_at, status, day_version)
values (
  'b1444444-4444-4444-8444-444444444444',
  'b1222222-2222-4222-8222-222222222222',
  (timestamptz '2026-01-17 22:30:00+00' at time zone 'Africa/Cairo')::date,
  timestamptz '2026-01-17 22:30:00+00',
  'open',
  1
);
insert into public.financial_operations (
  id, shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
) values
  ('b1333333-3333-4333-8333-333333333333', 'b1222222-2222-4222-8222-222222222222', 73, 'sale',
   'b1444444-4444-4444-8444-444444444444', 'b1111111-1111-4111-8111-111111111111', timestamptz '2026-01-17 22:30:00+00'),
  ('b1333333-3333-4333-8333-333333333334', 'b1222222-2222-4222-8222-222222222222', 74, 'purchase',
   'b1444444-4444-4444-8444-444444444444', 'b1111111-1111-4111-8111-111111111111', timestamptz '2026-01-17 22:30:00+00'),
  ('b1333333-3333-4333-8333-333333333335', 'b1222222-2222-4222-8222-222222222222', 75, 'expense',
   'b1444444-4444-4444-8444-444444444444', 'b1111111-1111-4111-8111-111111111111', timestamptz '2026-01-17 22:30:00+00');
insert into public.financial_operation_details (operation_id, shop_id, payload, created_at) values
  ('b1333333-3333-4333-8333-333333333333', 'b1222222-2222-4222-8222-222222222222',
   jsonb_build_object('version', 1, 'kind', 'sale', 'total_piastres', '123450', 'customer_name', '  ',
     'items', jsonb_build_array(jsonb_build_object('karat', 18, 'milligrams', '1255')),
     'tenders', jsonb_build_array(jsonb_build_object('method', 'cash', 'piastres', '123450'))),
   timestamptz '2026-01-17 22:30:00+00'),
  ('b1333333-3333-4333-8333-333333333334', 'b1222222-2222-4222-8222-222222222222',
   jsonb_build_object('version', 1, 'kind', 'purchase', 'total_piastres', '200000',
     'purchase_obligation_piastres', '100000'),
   timestamptz '2026-01-17 22:30:00+00');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

do $source$
declare
  v_shop uuid := 'b1222222-2222-4222-8222-222222222222';
  v_source jsonb;
  v_again jsonb;
  v_hash text;
  v_message bigint;
  v_digest jsonb;
  v_keys text[];
begin
  v_message := (select message_revision from public.shop_sync_signals where shop_id = v_shop);
  v_digest := pg_temp.protected_digest();
  v_source := public.get_invoice_message_source_v1('b1333333-3333-4333-8333-333333333333');
  select coalesce(array_agg(entry.key order by entry.key), '{}') into v_keys
  from jsonb_object_keys(v_source) as entry(key);
  if v_keys is distinct from array[
    'content_sha256', 'kind', 'message', 'occurred_at', 'occurred_at_shop',
    'operation_id', 'payload', 'shop_id', 'shop_name', 'shop_sequence',
    'time_zone', 'version'
  ]::text[]
    or v_source ? 'appearance'
    or v_source ? 'accent'
    or v_source ? 'latest_edition'
    or (v_source ->> 'kind') is distinct from 'sale'
    or (v_source ->> 'shop_sequence') is distinct from '73'
    or (v_source ->> 'shop_name') is distinct from 'متجر الرسالة'
    or (v_source ->> 'time_zone') is distinct from 'Asia/Riyadh'
    or (v_source ->> 'operation_id') is distinct from 'b1333333-3333-4333-8333-333333333333'
    or (v_source -> 'payload' ->> 'total_piastres') is distinct from '123450'
    or (v_source ->> 'occurred_at') not like '2026-01-17%Z'
    or (v_source ->> 'occurred_at_shop') is distinct from to_char(timestamptz '2026-01-17 22:30:00+00' at time zone 'Asia/Riyadh', 'YYYY-MM-DD"T"HH24:MI:SS')
    or (v_source ->> 'occurred_at_shop') is not distinct from to_char(timestamptz '2026-01-17 22:30:00+00' at time zone 'Africa/Cairo', 'YYYY-MM-DD"T"HH24:MI:SS')
    or left(v_source ->> 'occurred_at', 10) is not distinct from left(v_source ->> 'occurred_at_shop', 10)
    or (v_source ->> 'content_sha256') !~ '^[0-9a-f]{64}$'
    or (v_source -> 'message' ->> 'revision') is distinct from '5'
    or v_source -> 'message' -> 'template' is distinct from 'null'::jsonb
    or (v_source -> 'message' ->> 'shop_id') is distinct from v_shop::text then
    raise exception 'source_sale';
  end if;
  v_hash := v_source ->> 'content_sha256';
  if (select message_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_message
    or (select count(*) from public.invoice_message_audits where shop_id = v_shop) is distinct from 5
    or pg_temp.protected_digest() is distinct from v_digest then
    raise exception 'source_wrote';
  end if;
  perform pg_temp.expect_code(
    'select public.get_invoice_message_source_v1(null)',
    'invalid_input'
  );
  perform pg_temp.expect_code(
    'select public.get_invoice_message_source_v1(''b1333333-3333-4333-8333-333333333399'')',
    'not_found'
  );
  perform pg_temp.expect_code(
    'select public.get_invoice_message_source_v1(''b1333333-3333-4333-8333-333333333335'')',
    'wrong_operation_kind'
  );
  if (public.get_invoice_message_source_v1('b1333333-3333-4333-8333-333333333334') ->> 'kind') is distinct from 'purchase' then
    raise exception 'source_purchase';
  end if;
  reset role;
  update public.shops set name = 'اسم حي' where id = v_shop;
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'b1111111-1111-4111-8111-111111111111', true);
  perform set_config('request.jwt.claims', '{"sub":"b1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
  v_again := public.get_invoice_message_source_v1('b1333333-3333-4333-8333-333333333333');
  if (v_again ->> 'shop_name') is distinct from 'اسم حي'
    or (v_again ->> 'content_sha256') is distinct from v_hash
    or (v_again -> 'payload' ->> 'total_piastres') is distinct from '123450' then
    raise exception 'source_name_hash';
  end if;
  if (select message_revision from public.shop_sync_signals where shop_id = v_shop) is distinct from v_message then
    raise exception 'rename_bumped_message';
  end if;
end;
$source$;

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b2111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $other$
begin
  if (public.get_invoice_message_v1() ->> 'shop_id') is distinct from 'b2222222-2222-4222-8222-222222222222'
    or (public.get_invoice_message_v1() ->> 'revision') is distinct from '0' then
    raise exception 'other_shop_read';
  end if;
  if (select count(*) from public.invoice_message_revisions
      where shop_id = 'b1222222-2222-4222-8222-222222222222') is distinct from 0 then
    raise exception 'other_shop_rls';
  end if;
  perform pg_temp.expect_code(
    'select public.get_invoice_message_source_v1(''b1333333-3333-4333-8333-333333333333'')',
    'not_found'
  );
end;
$other$;

select set_config('request.jwt.claim.sub', 'b7111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b7111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $expired_prepare$
declare
  v_saved jsonb;
begin
  v_saved := public.post_invoice_message_v1(
    'b1cccccc-cccc-4ccc-8ccc-cccccccccccc',
    jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', 'منتهي {sequence}')
  );
  if (v_saved ->> 'revision') is distinct from '1' then
    raise exception 'expired_seed';
  end if;
end;
$expired_prepare$;
reset role;
update public.shop_entitlements
  set expires_at = now() - interval '1 minute'
  where shop_id = 'b7222222-2222-4222-8222-222222222222';
set local role authenticated;
select set_config('request.jwt.claim.sub', 'b7111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"b7111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $expired$
declare
  v_read jsonb;
  v_review jsonb;
  v_replay jsonb;
  v_rows int;
begin
  v_read := public.get_invoice_message_v1();
  if (v_read ->> 'can_write') is distinct from 'false'
    or (v_read ->> 'revision') is distinct from '1'
    or (v_read ->> 'template') is distinct from 'منتهي {sequence}' then
    raise exception 'expired_read';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', '{sequence}'
  ));
  if (v_review ->> 'status') is distinct from 'stale' or v_review ? 'normalized' then
    raise exception 'expired_stale';
  end if;
  v_review := public.review_invoice_message_v1(jsonb_build_object(
    'version', 1, 'kind', 'invoice_message', 'expected_revision', '1', 'template', '{sequence}'
  ));
  if (v_review ->> 'status') is distinct from 'expired'
    or v_review -> 'can_write' is distinct from 'false'::jsonb
    or v_review ? 'normalized' then
    raise exception 'expired_review';
  end if;
  select count(*) into v_rows from public.invoice_message_revisions
    where shop_id = 'b7222222-2222-4222-8222-222222222222';
  v_replay := public.post_invoice_message_v1(
    'b1cccccc-cccc-4ccc-8ccc-cccccccccccc',
    jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', 'منتهي {sequence}')
  );
  if (v_replay ->> 'replayed') is distinct from 'true'
    or (v_replay ->> 'revision') is distinct from '1'
    or (select count(*) from public.invoice_message_revisions
        where shop_id = 'b7222222-2222-4222-8222-222222222222') is distinct from v_rows then
    raise exception 'expired_replay';
  end if;
  if (public.get_invoice_message_status_v1(
    'b1cccccc-cccc-4ccc-8ccc-cccccccccccc',
    jsonb_build_object('version', 1, 'kind', 'invoice_message', 'expected_revision', '0', 'template', 'منتهي {sequence}')
  ) ->> 'status') is distinct from 'completed' then
    raise exception 'expired_status';
  end if;
  perform pg_temp.expect_code(
    'select public.post_invoice_message_v1(''b1cccccc-cccc-4ccc-8ccc-cccccccccccc'', ''{"version":1,"kind":"invoice_message","expected_revision":"0","template":"new"}''::jsonb)',
    'payload_mismatch'
  );
  perform pg_temp.expect_code(
    'select public.post_invoice_message_v1(''b1dddddd-dddd-4ddd-8ddd-dddddddddddd'', ''{"version":1,"kind":"invoice_message","expected_revision":"1","template":"{sequence}"}''::jsonb)',
    'shop_not_active'
  );
  if (public.get_invoice_message_source_v1('b1333333-3333-4333-8333-333333333333') ->> 'shop_id') is not null then
    raise exception 'expired_cross_shop';
  end if;
exception when others then
  if sqlerrm is distinct from 'not_found' then
    raise;
  end if;
end;
$expired$;

select pg_temp.expect_code(
  'insert into public.invoice_message_revisions default values',
  'permission denied for table invoice_message_revisions'
);
select pg_temp.expect_code(
  'insert into public.invoice_message_audits default values',
  'permission denied for table invoice_message_audits'
);
select pg_temp.expect_code(
  'insert into public.invoice_message_requests default values',
  'permission denied for table invoice_message_requests'
);
select pg_temp.expect_code(
  'update public.invoice_message_audits set revision = revision',
  'permission denied for table invoice_message_audits'
);
select pg_temp.expect_code(
  'delete from public.invoice_message_requests',
  'permission denied for table invoice_message_requests'
);

reset role;
set local role service_role;
do $service$
begin
  update public.invoice_message_audits set revision = revision
  where shop_id = 'b1222222-2222-4222-8222-222222222222';
  raise exception 'service_update_succeeded';
exception when insufficient_privilege then null;
  when others then
    if sqlerrm = 'service_update_succeeded' then
      raise exception 'service_update_succeeded';
    elsif sqlerrm not like 'permission denied%' then
      raise exception 'service_got_%', sqlerrm;
    end if;
end;
$service$;

reset role;
do $append$
begin
  update public.invoice_message_audits set previous_revision = 0
  where shop_id = 'b1222222-2222-4222-8222-222222222222';
  raise exception 'audit_update_succeeded';
exception when others then
  if sqlerrm is distinct from 'audit_append_only' then
    raise exception 'audit_got_%', sqlerrm;
  end if;
end;
$append$;
do $append_request$
begin
  delete from public.invoice_message_requests
  where shop_id = 'b1222222-2222-4222-8222-222222222222';
  raise exception 'request_delete_succeeded';
exception when others then
  if sqlerrm is distinct from 'audit_append_only' then
    raise exception 'request_got_%', sqlerrm;
  end if;
end;
$append_request$;

rollback;

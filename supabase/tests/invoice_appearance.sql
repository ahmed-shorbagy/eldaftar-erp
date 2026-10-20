-- SET-03 appearance and branded presentation copies. Synthetic rows roll back.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, deleted_at, created_at, updated_at
) values
  ('a1111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-owner@example.test', now(), false, null, now(), now()),
  ('a2111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-other@example.test', now(), false, null, now(), now()),
  ('a3111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-revoked@example.test', now(), false, null, now(), now()),
  ('a4111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-anon@example.test', now(), true, null, now(), now()),
  ('a5111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-admin@example.test', now(), false, null, now(), now()),
  ('a6111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-pending@example.test', now(), false, null, now(), now()),
  ('a7111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-expired@example.test', now(), false, null, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('a1222222-2222-4222-8222-222222222222', 'متجر المظهر', 'مالك المظهر', 'Africa/Cairo'),
  ('a2222222-2222-4222-8222-222222222222', 'متجر آخر', 'مالك آخر', 'Africa/Cairo'),
  ('a3222222-2222-4222-8222-222222222222', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('a6222222-2222-4222-8222-222222222222', 'متجر معلّق', 'مالك معلّق', 'Africa/Cairo'),
  ('a7222222-2222-4222-8222-222222222222', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('a1222222-2222-4222-8222-222222222222', 'a1111111-1111-4111-8111-111111111111', 'owner', null),
  ('a2222222-2222-4222-8222-222222222222', 'a2111111-1111-4111-8111-111111111111', 'owner', null),
  ('a3222222-2222-4222-8222-222222222222', 'a3111111-1111-4111-8111-111111111111', 'owner', now()),
  ('a6222222-2222-4222-8222-222222222222', 'a6111111-1111-4111-8111-111111111111', 'owner', null),
  ('a7222222-2222-4222-8222-222222222222', 'a7111111-1111-4111-8111-111111111111', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a1222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('a2222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('a3222222-2222-4222-8222-222222222222', now() - interval '1 day', now() + interval '30 days'),
  ('a7222222-2222-4222-8222-222222222222', now() - interval '10 days', now() - interval '1 day');

insert into public.platform_admins (user_id)
values ('a5111111-1111-4111-8111-111111111111');

insert into public.business_days (id, shop_id, business_date, opened_at, status, day_version)
values (
  'a1444444-4444-4444-8444-444444444444',
  'a1222222-2222-4222-8222-222222222222',
  (timestamptz '2026-10-17 08:00:00+00' at time zone 'Africa/Cairo')::date,
  timestamptz '2026-10-17 08:00:00+00',
  'open',
  1
);

insert into public.financial_operations (
  id, shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
) values (
  'a1333333-3333-4333-8333-333333333333',
  'a1222222-2222-4222-8222-222222222222',
  44,
  'purchase',
  'a1444444-4444-4444-8444-444444444444',
  'a1111111-1111-4111-8111-111111111111',
  timestamptz '2026-10-17 08:00:00+00'
);

insert into public.financial_operation_details (operation_id, shop_id, payload, created_at)
values (
  'a1333333-3333-4333-8333-333333333333',
  'a1222222-2222-4222-8222-222222222222',
  jsonb_build_object(
    'version', 1,
    'kind', 'purchase',
    'total_piastres', '104002',
    'purchase_obligation_piastres', '8000',
    'purchase_payable_remaining_piastres', '1',
    'items', jsonb_build_array(jsonb_build_object(
      'item_name', 'خاتم', 'category', 'worked_jewelry', 'karat', 18,
      'milligrams', '1830', 'count', '1', 'line_price_piastres', null
    )),
    'tenders', jsonb_build_array(
      jsonb_build_object('method', 'cash', 'piastres', '50000'),
      jsonb_build_object('method', 'card', 'piastres', '54002')
    )
  ),
  timestamptz '2026-10-17 08:00:00+00'
);

create function pg_temp.appearance_fail()
returns trigger language plpgsql as $fn$
begin
  raise exception 'appearance_test_failure';
end;
$fn$;

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

do $migration$
begin
  if (select appearance_revision from public.shop_sync_signals
      where shop_id = 'a1222222-2222-4222-8222-222222222222') < 0 then
    raise exception 'appearance_revision_missing';
  end if;
  if (select "public" from storage.buckets where id = 'eldafttar-private-invoice-logos') is distinct from false
    or (select file_size_limit from storage.buckets where id = 'eldafttar-private-invoice-logos') is distinct from 2097152
    or (select allowed_mime_types from storage.buckets where id = 'eldafttar-private-invoice-logos')
      is distinct from array['image/png', 'image/jpeg']::text[] then
    raise exception 'logo_bucket';
  end if;
  if to_regprocedure('public.post_invoice_appearance_v1(uuid,jsonb)') is null
    or to_regprocedure('public.confirm_invoice_logo_v1(text)') is null
    or to_regprocedure('public.post_invoice_presentation_v1(uuid,jsonb)') is null then
    raise exception 'appearance_functions_missing';
  end if;
end;
$migration$;

set local role anon;
do $anon$
begin
  perform public.get_invoice_appearance_v1();
  raise exception 'anon_read_succeeded';
exception
  when insufficient_privilege then null;
  when others then
    if sqlerrm is distinct from 'unauthenticated' and sqlerrm is distinct from 'anon_read_succeeded' then
      raise exception 'anon_unexpected_%', sqlerrm;
    elsif sqlerrm = 'anon_read_succeeded' then
      raise exception 'anon_read_succeeded';
    end if;
end;
$anon$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_code('select public.get_invoice_appearance_v1()', 'unauthenticated');

select set_config('request.jwt.claim.sub', 'a3111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a3111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code('select public.get_invoice_appearance_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'a4111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_invoice_appearance_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'a5111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_invoice_appearance_v1()', 'forbidden');

select set_config('request.jwt.claim.sub', 'a6111111-1111-4111-8111-111111111111', true);
select pg_temp.expect_code('select public.get_invoice_appearance_v1()', 'shop_unavailable');

select set_config('request.jwt.claim.sub', 'a2111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a2111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code(
  'select public.get_invoice_brand_source_v1(''a1333333-3333-4333-8333-333333333333'')',
  'not_found'
);

select set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

do $owner$
declare
  v_before jsonb;
  v_after jsonb;
  v_read jsonb;
  v_result jsonb;
  v_replay jsonb;
  v_source jsonb;
  v_edition jsonb;
  v_second jsonb;
  v_copy jsonb;
  v_png bytea := decode('89504e470d0a1a0a0000000d494844520000000200000002080600000072b60d240000001a49444154789c63e1129163909393fbcf626363d3b07bd3ca930020e105b1e1ef98ad0000000049454e44ae426082', 'hex');
  v_sha text;
  v_ops int;
  v_details int;
  v_commands int;
  v_dispatch int;
  v_rows int;
  v_sync bigint;
  v_payload jsonb := jsonb_build_object(
    'version', 1, 'kind', 'invoice_appearance', 'expected_revision', '0',
    'slogan', '  ذهب أمين  ', 'address', E'سطر\nثان', 'template', 'compact',
    'accent', 'gold', 'logo_asset_id', null
  );
begin
  if (public.get_invoice_appearance_v1() ->> 'revision') is distinct from '0'
    or (public.get_invoice_appearance_v1() ->> 'template') is distinct from 'header'
    or (public.get_invoice_appearance_v1() ->> 'accent') is distinct from 'brown'
    or public.get_invoice_appearance_v1() -> 'slogan' is distinct from 'null'::jsonb then
    raise exception 'defaults';
  end if;
  perform pg_temp.expect_code(
    'select public.review_invoice_appearance_v1(''{"version":1,"kind":"invoice_appearance","expected_revision":"0","slogan":"تحكم\u0001","address":null,"template":"header","accent":"brown","logo_asset_id":null}''::jsonb)',
    'invalid_input'
  );
  v_source := public.get_invoice_brand_source_v1('a1333333-3333-4333-8333-333333333333');
  if (v_source -> 'payload' ->> 'purchase_obligation_piastres') is distinct from '8000'
    or (v_source -> 'payload' ->> 'purchase_payable_remaining_piastres') is distinct from '1'
    or (v_source ->> 'shop_sequence') is distinct from '44'
    or (v_source ->> 'latest_edition') is distinct from '0' then
    raise exception 'brand_source';
  end if;
  select jsonb_build_object(
    'revision', revision, 'ledger', ledger_revision, 'invoice', invoice_revision,
    'debt', debt_revision, 'customer', customer_revision, 'appearance', appearance_revision
  ) into v_before
  from public.shop_sync_signals
  where shop_id = 'a1222222-2222-4222-8222-222222222222';
  select count(*) into v_ops from public.financial_operations
    where shop_id = 'a1222222-2222-4222-8222-222222222222';
  select count(*) into v_details from public.financial_operation_details
    where shop_id = 'a1222222-2222-4222-8222-222222222222';
  select count(*) into v_commands from public.financial_command_requests
    where shop_id = 'a1222222-2222-4222-8222-222222222222';
  select count(*) into v_dispatch from public.invoice_dispatch_confirmations
    where shop_id = 'a1222222-2222-4222-8222-222222222222';
  v_result := public.post_invoice_appearance_v1('a1555555-5555-4555-8555-555555555555', v_payload);
  if (v_result ->> 'revision') is distinct from '1'
    or (v_result ->> 'slogan') is distinct from 'ذهب أمين'
    or (v_result ->> 'replayed') is distinct from 'false'
    or (v_result ->> 'cash_piastres') is distinct from '0'
    or (v_result ->> 'invoice_effect') is distinct from 'false'
    or (v_result ->> 'dispatch_effect') is distinct from 'false' then
    raise exception 'appearance_save';
  end if;
  v_replay := public.post_invoice_appearance_v1('a1555555-5555-4555-8555-555555555555', v_payload);
  if (v_replay ->> 'replayed') is distinct from 'true'
    or (v_replay ->> 'revision') is distinct from '1'
    or (select count(*) from public.invoice_appearance_revisions
        where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from 1 then
    raise exception 'appearance_replay';
  end if;
  perform pg_temp.expect_code(
    'select public.post_invoice_appearance_v1(''a1555555-5555-4555-8555-555555555555'', ''{"version":1,"kind":"invoice_appearance","expected_revision":"0","slogan":"آخر","address":null,"template":"header","accent":"brown","logo_asset_id":null}''::jsonb)',
    'payload_mismatch'
  );
  perform pg_temp.expect_code(
    'select public.post_invoice_appearance_v1(''a1555555-5555-4555-8555-555555555556'', ''{"version":1,"kind":"invoice_appearance","expected_revision":"0","slogan":null,"address":null,"template":"header","accent":"brown","logo_asset_id":null}''::jsonb)',
    'stale_appearance'
  );
  select jsonb_build_object(
    'revision', revision, 'ledger', ledger_revision, 'invoice', invoice_revision,
    'debt', debt_revision, 'customer', customer_revision, 'appearance', appearance_revision
  ) into v_after
  from public.shop_sync_signals
  where shop_id = 'a1222222-2222-4222-8222-222222222222';
  if (v_after ->> 'appearance')::bigint is distinct from (v_before ->> 'appearance')::bigint + 1
    or (v_after ->> 'revision')::bigint is distinct from (v_before ->> 'revision')::bigint + 1
    or (v_after ->> 'ledger') is distinct from (v_before ->> 'ledger')
    or (v_after ->> 'invoice') is distinct from (v_before ->> 'invoice')
    or (v_after ->> 'debt') is distinct from (v_before ->> 'debt')
    or (v_after ->> 'customer') is distinct from (v_before ->> 'customer') then
    raise exception 'appearance_sync';
  end if;
  if (select count(*) from public.financial_operations where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from v_ops
    or (select count(*) from public.financial_operation_details where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from v_details
    or (select count(*) from public.financial_command_requests where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from v_commands
    or (select count(*) from public.invoice_dispatch_confirmations where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from v_dispatch then
    raise exception 'appearance_mutated_finance';
  end if;
  reset role;
  v_sha := encode(extensions.digest(v_png, 'sha256'), 'hex');
  set local role authenticated;
  perform pg_temp.expect_code(
    format('select public.confirm_invoice_logo_v1(%L)', replace(encode(v_png, 'base64'), E'\n', '')),
    'logo_not_uploaded'
  );
  reset role;
  insert into storage.objects (bucket_id, name, owner, metadata)
  values (
    'eldafttar-private-invoice-logos',
    'a1222222-2222-4222-8222-222222222222/' || v_sha || '.png',
    'a1111111-1111-4111-8111-111111111111',
    jsonb_build_object('mimetype', 'image/png', 'size', octet_length(v_png)::text)
  );
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
  perform set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
  v_read := public.confirm_invoice_logo_v1(replace(encode(v_png, 'base64'), E'\n', ''));
  if (v_read ->> 'sha256') is distinct from v_sha
    or (v_read ->> 'confirmed') is distinct from 'true'
    or (v_read ->> 'replayed') is distinct from 'false' then
    raise exception 'logo_confirm';
  end if;
  if (select appearance_revision from public.shop_sync_signals
      where shop_id = 'a1222222-2222-4222-8222-222222222222')
      is distinct from (v_after ->> 'appearance')::bigint then
    raise exception 'logo_bumped_appearance';
  end if;
  if (public.confirm_invoice_logo_v1(replace(encode(v_png, 'base64'), E'\n', '')) ->> 'replayed') is distinct from 'true'
    or (select count(*) from public.invoice_logo_assets
        where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from 1 then
    raise exception 'logo_replay';
  end if;
  v_edition := public.post_invoice_presentation_v1(
    'a1666666-6666-4666-8666-666666666666',
    jsonb_build_object(
      'version', 1, 'kind', 'invoice_presentation',
      'operation_id', 'a1333333-3333-4333-8333-333333333333',
      'expected_content_sha256', v_source ->> 'content_sha256',
      'expected_appearance_revision', '1',
      'expected_latest_edition', '0'
    )
  );
  if (v_edition ->> 'edition') is distinct from '1'
    or (v_edition ->> 'slogan') is distinct from 'ذهب أمين'
    or (v_edition ->> 'appearance_revision') is distinct from '1'
    or (v_edition ->> 'dispatch_effect') is distinct from 'false' then
    raise exception 'edition';
  end if;
  perform public.post_invoice_appearance_v1(
    'a1777777-7777-4777-8777-777777777777',
    jsonb_build_object(
      'version', 1, 'kind', 'invoice_appearance', 'expected_revision', '1',
      'slogan', null, 'address', null, 'template', 'header', 'accent', 'brown',
      'logo_asset_id', v_read ->> 'asset_id'
    )
  );
  v_copy := public.get_invoice_presentation_v1('a1333333-3333-4333-8333-333333333333', 1);
  if (v_copy ->> 'slogan') is distinct from 'ذهب أمين'
    or (v_copy ->> 'appearance_revision') is distinct from '1'
    or (v_copy ->> 'content_matches') is distinct from 'true'
    or (v_copy ->> 'logo_asset_id') is not null then
    raise exception 'edition_frozen';
  end if;
  reset role;
  update public.shops set name = 'اسم حي' where id = 'a1222222-2222-4222-8222-222222222222';
  set local role authenticated;
  perform set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
  perform set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
  if (public.get_invoice_presentation_v1('a1333333-3333-4333-8333-333333333333', 1) ->> 'shop_name')
      is distinct from 'اسم حي'
    or (public.get_invoice_presentation_v1('a1333333-3333-4333-8333-333333333333', 1) ->> 'content_sha256')
      is distinct from (v_edition ->> 'content_sha256') then
    raise exception 'shop_name_hash';
  end if;
  v_second := public.post_invoice_presentation_v1(
    'a1888888-8888-4888-8888-888888888888',
    jsonb_build_object(
      'version', 1, 'kind', 'invoice_presentation',
      'operation_id', 'a1333333-3333-4333-8333-333333333333',
      'expected_content_sha256', v_source ->> 'content_sha256',
      'expected_appearance_revision', '2',
      'expected_latest_edition', '1'
    )
  );
  if (v_second ->> 'edition') is distinct from '2'
    or (v_second ->> 'logo_asset_id') is distinct from (v_read ->> 'asset_id')
    or (select count(*) from public.invoice_presentation_revisions
        where operation_id = 'a1333333-3333-4333-8333-333333333333') is distinct from 2
    or (select slogan from public.invoice_presentation_revisions where edition = 1) is distinct from 'ذهب أمين' then
    raise exception 'second_edition';
  end if;
  perform public.post_invoice_appearance_v1(
    'a1aaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    jsonb_build_object(
      'version', 1, 'kind', 'invoice_appearance', 'expected_revision', '2',
      'slogan', null, 'address', null, 'template', 'header', 'accent', 'brown',
      'logo_asset_id', null
    )
  );
  if (select count(*) from public.invoice_logo_assets
      where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from 1
    or (select logo_asset_id from public.invoice_presentation_revisions where edition = 2)
      is distinct from (v_read ->> 'asset_id')::uuid
    or (select logo_asset_id from public.invoice_appearance_revisions
        where shop_id = 'a1222222-2222-4222-8222-222222222222' and revision = 3) is not null then
    raise exception 'clearing_logo_deleted_asset';
  end if;
  select count(*) into v_rows from public.invoice_appearance_revisions
    where shop_id = 'a1222222-2222-4222-8222-222222222222';
  select appearance_revision into v_sync from public.shop_sync_signals
    where shop_id = 'a1222222-2222-4222-8222-222222222222';
  reset role;
  create trigger appearance_test_failure
    after insert on public.invoice_appearance_requests
    for each row execute function pg_temp.appearance_fail();
  set local role authenticated;
  begin
    perform public.post_invoice_appearance_v1(
      'a1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      jsonb_build_object(
        'version', 1, 'kind', 'invoice_appearance', 'expected_revision', '3',
        'slogan', 'لن يُحفظ', 'address', null, 'template', 'header', 'accent', 'brown',
        'logo_asset_id', null
      )
    );
    raise exception 'appearance_partial_commit';
  exception when others then
    if sqlerrm is distinct from 'appearance_test_failure' then
      raise exception 'rollback_got_%', sqlerrm;
    end if;
  end;
  reset role;
  drop trigger appearance_test_failure on public.invoice_appearance_requests;
  set local role authenticated;
  if (select count(*) from public.invoice_appearance_revisions
      where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from v_rows
    or (select appearance_revision from public.shop_sync_signals
        where shop_id = 'a1222222-2222-4222-8222-222222222222') is distinct from v_sync
    or exists (
      select 1 from public.invoice_appearance_requests
      where idempotency_key = 'a1bbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
    ) then
    raise exception 'appearance_partial_commit';
  end if;
end;
$owner$;

reset role;
do $bytes$
declare
  v_png bytea := decode('89504e470d0a1a0a0000000d494844520000000200000002080600000072b60d240000001a49444154789c63e1129163909393fbcf626363d3b07bd3ca930020e105b1e1ef98ad0000000049454e44ae426082', 'hex');
  v_wide bytea;
  v_text bytea;
begin
  perform private.invoice_logo_facts(v_png, true);
  begin
    perform private.invoice_logo_facts(''::bytea, true);
    raise exception 'empty_accepted';
  exception when others then
    if sqlerrm is distinct from 'image_too_large' then
      raise exception 'empty_got_%', sqlerrm;
    end if;
  end;
  begin
    perform private.invoice_logo_facts(decode('474946383961', 'hex'), true);
    raise exception 'gif_accepted';
  exception when others then
    if sqlerrm is distinct from 'logo_rejected' then raise exception 'gif_got_%', sqlerrm; end if;
  end;
  v_wide := overlay(v_png placing decode('00000801', 'hex') from 17);
  begin
    perform private.invoice_logo_facts(v_wide, false);
    raise exception 'wide_accepted';
  exception when others then
    if sqlerrm is distinct from 'logo_rejected' then raise exception 'wide_got_%', sqlerrm; end if;
  end;
  v_text := substring(v_png from 1 for octet_length(v_png) - 12)
    || decode('000000037445587441006200000000', 'hex')
    || substring(v_png from octet_length(v_png) - 11);
  begin
    perform private.invoice_logo_facts(v_text, true);
    raise exception 'text_accepted';
  exception when others then
    if sqlerrm is distinct from 'logo_rejected' then raise exception 'text_got_%', sqlerrm; end if;
  end;
  if (private.invoice_logo_facts(v_text, false)).mime is distinct from 'image/png' then
    raise exception 'source_text_rejected';
  end if;
end;
$bytes$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);

do $storage$
declare
  v_name text := 'a1222222-2222-4222-8222-222222222222/' || repeat('ab', 32) || '.png';
  v_meta jsonb;
begin
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values ('eldafttar-private-invoice-logos', v_name, auth.uid(), '{"mimetype":"image/png","size":"83"}'::jsonb);
  exception when insufficient_privilege then
    raise exception 'owner_insert_denied';
  end;
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values ('eldafttar-private-invoice-logos', 'a2222222-2222-4222-8222-222222222222/' || repeat('ab', 32) || '.png', auth.uid(), '{"mimetype":"image/png","size":"83"}'::jsonb);
    raise exception 'cross_shop_insert_succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    update storage.objects set metadata = '{"mimetype":"image/png","size":"1"}'::jsonb
    where bucket_id = 'eldafttar-private-invoice-logos' and name = v_name;
  exception when insufficient_privilege then null;
  end;
  begin
    select metadata into v_meta from storage.objects
    where bucket_id = 'eldafttar-private-invoice-logos' and name = v_name;
    if v_meta is not null and (v_meta ->> 'size') is distinct from '83' then
      raise exception 'storage_update_changed_logo';
    end if;
  exception
    when insufficient_privilege then null;
  end;
  begin
    delete from storage.objects
    where bucket_id = 'eldafttar-private-invoice-logos' and name = v_name;
  exception when insufficient_privilege then null;
  end;
  reset role;
  if (select metadata ->> 'size' from storage.objects
      where bucket_id = 'eldafttar-private-invoice-logos' and name = v_name)
      is distinct from '83' then
    raise exception 'storage_delete_removed_logo';
  end if;
end;
$storage$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code(
  'insert into public.invoice_appearance_audits default values',
  'permission denied for table invoice_appearance_audits'
);
select pg_temp.expect_code(
  'insert into public.invoice_appearance_requests default values',
  'permission denied for table invoice_appearance_requests'
);
select pg_temp.expect_code(
  'insert into public.invoice_presentation_revisions default values',
  'permission denied for table invoice_presentation_revisions'
);
reset role;

reset role;
do $audit$
begin
  update public.invoice_appearance_audits set actor_display_name = 'تغيير'
  where shop_id = 'a1222222-2222-4222-8222-222222222222';
  raise exception 'audit_update_succeeded';
exception when others then
  if sqlerrm is distinct from 'audit_append_only' then
    raise exception 'audit_got_%', sqlerrm;
  end if;
end;
$audit$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a7111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a7111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
select pg_temp.expect_code(
  'select public.post_invoice_appearance_v1(''a1999999-9999-4999-8999-999999999999'', ''{"version":1,"kind":"invoice_appearance","expected_revision":"0","slogan":null,"address":null,"template":"header","accent":"brown","logo_asset_id":null}''::jsonb)',
  'shop_not_active'
);
do $expired_read$
begin
  if (public.get_invoice_appearance_v1() ->> 'can_write') is distinct from 'false' then
    raise exception 'expired_read';
  end if;
end;
$expired_read$;

-- Render-v2 editions and their legacy copies coexist without dispatching or
-- mutating the financial source. This block uses the synthetic owner above.
select set_config('request.jwt.claim.sub', 'a1111111-1111-4111-8111-111111111111', true);
select set_config('request.jwt.claims', '{"sub":"a1111111-1111-4111-8111-111111111111","role":"authenticated","is_anonymous":false}', true);
do $render_v2$
declare
  v_source jsonb := public.get_invoice_brand_source_v1('a1333333-3333-4333-8333-333333333333');
  v_payload jsonb;
  v_result jsonb;
  v_before jsonb := public.get_daily_ledger_operation('a1333333-3333-4333-8333-333333333333');
begin
  v_payload := jsonb_build_object('version',1,'kind','invoice_presentation',
    'operation_id','a1333333-3333-4333-8333-333333333333',
    'expected_content_sha256',v_source->>'content_sha256',
    'expected_appearance_revision','3','expected_latest_edition','2');
  v_result := public.post_invoice_presentation_v2('a1eeeeee-eeee-4eee-8eee-eeeeeeeeeeee',v_payload);
  if v_result->>'render_version' <> '2' or v_result->>'edition' <> '3'
    or v_result->>'dispatch_effect' <> 'false' then raise exception 'white_render_v2'; end if;
  if public.post_invoice_presentation_v2('a1eeeeee-eeee-4eee-8eee-eeeeeeeeeeee',v_payload)->>'replayed' <> 'true'
    then raise exception 'render_v2_replay'; end if;
  perform public.post_invoice_appearance_v1('a1ffffff-ffff-4fff-8fff-ffffffffffff',
    '{"version":1,"kind":"invoice_appearance","expected_revision":"3","template":"dark","accent":"gold","slogan":null,"address":null,"logo_asset_id":null}'::jsonb);
  v_payload := v_payload || '{"expected_appearance_revision":"4","expected_latest_edition":"3"}'::jsonb;
  begin
    perform public.post_invoice_presentation_v1('a1000000-0000-4000-8000-000000000099',v_payload);
    raise exception 'legacy_accepted_dark';
  exception when others then
    if sqlerrm <> 'unsupported_render_version' then raise; end if;
  end;
  v_result := public.post_invoice_presentation_v2('a1000000-0000-4000-8000-000000000098',v_payload);
  if v_result->>'render_version' <> '2' or v_result->>'template' <> 'dark'
    or public.get_invoice_presentation_v1('a1333333-3333-4333-8333-333333333333',1)->>'render_version' <> '1'
    or public.get_invoice_presentation_v1('a1333333-3333-4333-8333-333333333333',3)->>'template' <> 'header'
    or public.get_daily_ledger_operation('a1333333-3333-4333-8333-333333333333') is distinct from v_before
    then raise exception 'dark_or_legacy_or_financial_mutation'; end if;
end;
$render_v2$;
rollback;

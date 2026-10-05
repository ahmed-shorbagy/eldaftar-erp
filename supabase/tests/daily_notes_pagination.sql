-- Notes and ledger pagination. Synthetic fixtures roll back. Local SQL only.
begin;

do $guard$
begin
  if inet_server_addr() is distinct from '127.0.0.1'::inet
    or current_database() not in ('eldafttar_notes_test', 'eldafttar_complete_test') then
    raise exception 'refusing notes test outside a named local disposable test database';
  end if;
end;
$guard$;

create temp table notes_probe(name text primary key, value bigint);
insert into notes_probe
values ('shops_before', (select count(*) from public.shops));

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('81818181-8181-4181-8181-818181818181', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'notes-owner@example.test', false, now(), now()),
  ('82828282-8282-4282-8282-828282828282', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'notes-other@example.test', false, now(), now()),
  ('83838383-8383-4383-8383-838383838383', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'notes-revoked@example.test', false, now(), now()),
  ('84848484-8484-4484-8484-848484848484', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'notes-anon@example.test', true, now(), now()),
  ('86868686-8686-4686-8686-868686868686', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'notes-admin@example.test', false, now(), now()),
  ('89898989-8989-4989-8989-898989898989', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'notes-expired@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1818181-8181-4181-8181-818181818181', 'متجر الملاحظات', 'مالك الملاحظات', 'Africa/Cairo'),
  ('b2828282-8282-4282-8282-828282828282', 'متجر الآخر', 'مالك الآخر', 'Africa/Cairo'),
  ('b3838383-8383-4383-8383-838383838383', 'متجر موقوف', 'مالك موقوف', 'Africa/Cairo'),
  ('b9898989-8989-4989-8989-898989898989', 'متجر منتهي', 'مالك منتهي', 'Africa/Cairo');

insert into public.shop_memberships (shop_id, user_id, role, revoked_at) values
  ('b1818181-8181-4181-8181-818181818181', '81818181-8181-4181-8181-818181818181', 'owner', null),
  ('b2828282-8282-4282-8282-828282828282', '82828282-8282-4282-8282-828282828282', 'owner', null),
  ('b3838383-8383-4383-8383-838383838383', '83838383-8383-4383-8383-838383838383', 'owner', now()),
  ('b9898989-8989-4989-8989-898989898989', '89898989-8989-4989-8989-898989898989', 'owner', null);

insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1818181-8181-4181-8181-818181818181', now() - interval '1 day', now() + interval '30 days'),
  ('b2828282-8282-4282-8282-828282828282', now() - interval '1 day', now() + interval '30 days'),
  ('b3838383-8383-4383-8383-838383838383', now() - interval '1 day', now() + interval '30 days'),
  ('b9898989-8989-4989-8989-898989898989', now() - interval '10 days', now() - interval '1 day');

insert into public.platform_admins (user_id)
values ('86868686-8686-4686-8686-868686868686');

insert into public.business_days (id, shop_id, business_date, opened_at, status, day_version)
values (
  'd9898989-8989-4989-8989-898989898989',
  'b9898989-8989-4989-8989-898989898989',
  (now() at time zone 'Africa/Cairo')::date,
  now(),
  'open',
  1
);

do $index$
begin
  if not exists (
    select 1 from pg_indexes
    where indexname = 'financial_operations_shop_day_sequence_idx'
  ) then
    raise exception 'missing shop day sequence index';
  end if;
  if (select "public" from storage.buckets where id = 'eldafttar-private-notes') is distinct from false then
    raise exception 'notes bucket is not private';
  end if;
  if (select file_size_limit from storage.buckets where id = 'eldafttar-private-notes') <> 5242880 then
    raise exception 'notes bucket size limit';
  end if;
end;
$index$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
select set_config('request.jwt.claim.session_id', '', true);

do $test$
declare
  v_day uuid;
  v_sale uuid;
  v_note uuid;
  v_image uuid;
  v_result jsonb;
  v_page jsonb;
  v_ledger jsonb;
  v_before text;
  v_pages integer := 0;
  v_seen integer := 0;
  v_pivot text;
  v_older jsonb;
  v_newer jsonb;
  v_item jsonb;
  v_at timestamptz := timestamptz '2026-01-01 22:30:00+00';
  v_seq bigint;
  v_cairo text;
  v_utc text;
  v_egypt text;
  v_state jsonb;
  v_financial_before jsonb;
  v_bad_path text;
  v_bad_limit integer;
  v_path text;
  v_client uuid := 'c4c4c4c4-c4c4-44c4-84c4-c4c4c4c4c4c4';
begin
  if (timezone('UTC', v_at))::date = (timezone('Africa/Cairo', v_at))::date then
    raise exception 'midnight fixture does not cross dates';
  end if;
  v_result := public.confirm_opening_balances(
    'c1818181-8181-4181-8181-818181818181',
    '{"version":1,"cash":{"cash":"10000","card":"3000"},"stock":[{"category":"worked_jewelry","karat":18,"milligrams":"3000","count":"3"}],"scrap":[]}'::jsonb
  );
  v_day := (v_result ->> 'business_day_id')::uuid;
  if v_day is null then
    raise exception 'opening did not return a day';
  end if;
  v_result := public.post_daily_ledger_trade(
    'c2828282-8282-4282-8282-828282828282',
    '{"version":1,"kind":"sale","total_piastres":"5000","tenders":[{"method":"cash","piastres":"5000"}],"items":[{"category":"worked_jewelry","karat":18,"milligrams":"1000","count":"1","item_name":"خاتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'sale did not commit';
  end if;
  v_sale := (v_result ->> 'operation_id')::uuid;
  select operation.shop_sequence::text into v_pivot
  from public.financial_operations as operation
  where operation.id = v_sale;
  v_financial_before := public.get_daily_ledger_v2() - 'feed' - 'feed_page';

  v_result := public.post_daily_note(
    'c3838383-8383-4383-8383-838383838383',
    jsonb_build_object(
      'version', 1,
      'kind', 'daily_note',
      'business_day_id', v_day::text,
      'text', 'ملاحظة أولى',
      'attachment', null
    )
  );
  if v_result ->> 'ok' is distinct from 'true'
    or v_result ->> 'replayed' is distinct from 'false'
    or v_result ->> 'shop_sequence' !~ '^[1-9][0-9]*$' then
    raise exception 'note did not commit';
  end if;
  v_note := (v_result ->> 'note_id')::uuid;
  if (select count(*) from public.journals where operation_id = v_note) <> 0 then
    raise exception 'note created a journal';
  end if;
  if (select count(*) from public.financial_audit_events
      where operation_id = v_note and action = 'daily_note_recorded') <> 1 then
    raise exception 'note audit missing';
  end if;
  if (select count(*) from public.financial_outbox
      where operation_id = v_note and event_type = 'daily_note_recorded') <> 1 then
    raise exception 'note outbox missing';
  end if;
  v_result := public.post_daily_note(
    'c3838383-8383-4383-8383-838383838383',
    jsonb_build_object(
      'version', 1,
      'kind', 'daily_note',
      'business_day_id', v_day::text,
      'text', 'ملاحظة أولى',
      'attachment', null
    )
  );
  if v_result ->> 'replayed' is distinct from 'true'
    or (v_result ->> 'note_id')::uuid is distinct from v_note then
    raise exception 'same note key did not replay';
  end if;
  begin
    perform public.post_daily_note(
      'c3838383-8383-4383-8383-838383838383',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', 'نص مختلف', 'attachment', null
      )
    );
    raise exception 'mismatch_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'payload_mismatch' then
        raise exception 'expected payload_mismatch got %', sqlerrm;
      end if;
  end;
  if (select count(*) from public.financial_audit_events
      where operation_id = v_note) <> 1
    or (select count(*) from public.financial_outbox where operation_id = v_note) <> 1
    or (select count(*) from public.financial_operations where id = v_note) <> 1
    or (select count(*) from public.financial_command_requests
        where idempotency_key = 'c3838383-8383-4383-8383-838383838383') <> 1 then
    raise exception 'retry or mismatch duplicated operation, request, audit or outbox';
  end if;
  begin
    perform public.post_daily_note(
      'c4848484-8484-4484-8484-848484848484',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', '   ', 'attachment', null
      )
    );
    raise exception 'empty_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'note_empty' then
        raise exception 'expected note_empty got %', sqlerrm;
      end if;
  end;

  v_path := 'b1818181-8181-4181-8181-818181818181/' || v_day::text || '/' || v_client::text || '.jpg';
  insert into storage.objects (bucket_id, name, owner, metadata)
  values (
    'eldafttar-private-notes',
    v_path,
    '81818181-8181-4181-8181-818181818181',
    jsonb_build_object('mimetype', 'image/jpeg', 'size', '4')
  );
  v_result := public.post_daily_note(
    'c5858585-8585-4585-8585-858585858585',
    jsonb_build_object(
      'version', 1,
      'kind', 'daily_note',
      'business_day_id', v_day::text,
      'text', '',
      'attachment', jsonb_build_object(
        'client_object_id', v_client::text,
        'mime_type', 'image/jpeg',
        'byte_size', '4',
        'extension', 'jpg'
      )
    )
  );
  if v_result ->> 'replayed' is distinct from 'false' then
    raise exception 'image note did not commit';
  end if;
  v_image := (v_result ->> 'note_id')::uuid;
  if (select count(*) from public.journals where operation_id = v_image) <> 0 then
    raise exception 'image note created a journal';
  end if;
  if (select object_name from public.daily_note_attachments where operation_id = v_image) is distinct from v_path then
    raise exception 'attachment path was not the owner shop day path';
  end if;
  execute 'reset role';
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (
    'eldafttar-private-notes',
    'b1818181-8181-4181-8181-818181818181/' || v_day::text
      || '/d1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1.jpg',
    null,
    null,
    jsonb_build_object('mimetype', 'image/jpeg', 'size', '4')
  );
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  values (
    'eldafttar-private-notes',
    'b1818181-8181-4181-8181-818181818181/' || v_day::text
      || '/d2d2d2d2-d2d2-42d2-82d2-d2d2d2d2d2d2.jpg',
    '99999999-9999-4999-8999-999999999999',
    null,
    jsonb_build_object('mimetype', 'image/jpeg', 'size', '4')
  );
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
  begin
    perform public.post_daily_note(
      'cd1d1d1d-d1d1-41d1-81d1-d1d1d1d1d1d1',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', 'بدون مالك',
        'attachment', jsonb_build_object(
          'client_object_id', 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1',
          'mime_type', 'image/jpeg', 'byte_size', '4', 'extension', 'jpg'
        )
      )
    );
    raise exception 'null_owner_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'attachment_rejected' then
        raise exception 'expected attachment_rejected for null owner got %', sqlerrm;
      end if;
  end;
  begin
    perform public.post_daily_note(
      'cd2d2d2d-d2d2-42d2-82d2-d2d2d2d2d2d2',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', 'مالك آخر',
        'attachment', jsonb_build_object(
          'client_object_id', 'd2d2d2d2-d2d2-42d2-82d2-d2d2d2d2d2d2',
          'mime_type', 'image/jpeg', 'byte_size', '4', 'extension', 'jpg'
        )
      )
    );
    raise exception 'wrong_owner_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'attachment_rejected' then
        raise exception 'expected attachment_rejected for wrong owner got %', sqlerrm;
      end if;
  end;
  begin
    perform public.post_daily_note(
      'c6868686-8686-4686-8686-868686868686',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', 'تكرار',
        'attachment', jsonb_build_object(
          'client_object_id', v_client::text,
          'mime_type', 'image/jpeg', 'byte_size', '4', 'extension', 'jpg'
        )
      )
    );
    raise exception 'duplicate_attachment_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'attachment_rejected' then
        raise exception 'expected attachment_rejected got %', sqlerrm;
      end if;
  end;
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values (
      'eldafttar-private-notes',
      'b1818181-8181-4181-8181-818181818181/' || v_day::text
        || '/66666666-6666-4666-8666-666666666666.jpg',
      '81818181-8181-4181-8181-818181818181',
      jsonb_build_object('mimetype', 'image/gif', 'size', '4')
    );
    raise exception 'gif_metadata_succeeded';
  exception
    when others then
      if sqlerrm = 'gif_metadata_succeeded' then
        raise exception 'object metadata accepted a non-image';
      end if;
  end;
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values (
      'eldafttar-private-notes',
      'b1818181-8181-4181-8181-818181818181/' || v_day::text
        || '/67676767-6767-4676-8676-676767676767.jpg',
      '81818181-8181-4181-8181-818181818181',
      jsonb_build_object('mimetype', 'image/jpeg', 'size', '5242881')
    );
    raise exception 'oversize_metadata_succeeded';
  exception
    when others then
      if sqlerrm = 'oversize_metadata_succeeded' then
        raise exception 'object metadata accepted more than 5MiB';
      end if;
  end;
  insert into storage.objects (bucket_id, name, owner, metadata)
  values (
    'eldafttar-private-notes',
    'b1818181-8181-4181-8181-818181818181/' || v_day::text
      || '/77777777-7777-4777-8777-777777777777.webp',
    '81818181-8181-4181-8181-818181818181',
    jsonb_build_object('mimetype', 'image/webp', 'size', '1')
  );

  -- Denied inserts must fail at authorization, rather than an unrelated error.
  foreach v_bad_path in array array[
    'b1818181-8181-4181-8181-818181818181/' || v_day::text || '/extra/11111111-1111-4111-8111-111111111111.jpg',
    'b1818181-8181-4181-8181-818181818181/' || v_day::text || '/not-a-uuid.jpg',
    'b1818181-8181-4181-8181-818181818181/d9898989-8989-4989-8989-898989898989/11111111-1111-4111-8111-111111111111.jpg'
  ] loop
    begin
      insert into storage.objects(bucket_id, name, owner, metadata)
      values ('eldafttar-private-notes', v_bad_path, auth.uid(),
        '{"mimetype":"image/jpeg","size":"4"}'::jsonb);
      raise exception 'invalid_path_succeeded';
    exception when insufficient_privilege then null;
    end;
  end loop;
  begin
    insert into storage.objects(bucket_id, name, owner, metadata)
    values ('eldafttar-private-notes',
      'b1818181-8181-4181-8181-818181818181/' || v_day::text || '/11111111-1111-4111-8111-111111111111.jpg',
      '82828282-8282-4282-8282-828282828282',
      '{"mimetype":"image/jpeg","size":"4"}'::jsonb);
    raise exception 'invalid_upload_owner_succeeded';
  exception when insufficient_privilege then null;
  end;
  begin
    update storage.objects set metadata = '{"mimetype":"image/jpeg","size":"3"}'::jsonb
    where name = v_path;
    raise exception 'storage_update_succeeded';
  exception when insufficient_privilege then null;
  end;
  if (public.get_daily_ledger_v2() - 'feed' - 'feed_page')
      is distinct from v_financial_before then
    raise exception 'real note RPCs changed cash, stock, scrap, gold or financial totals';
  end if;
  foreach v_bad_limit in array array[null::integer, 0, 51] loop
    begin
      perform public.list_daily_notes(v_day, null, v_bad_limit, null);
      raise exception 'notes_limit_succeeded';
    exception when others then
      if sqlerrm is distinct from 'invalid_input' then raise; end if;
    end;
  end loop;
  v_page := public.list_daily_notes(v_day, null, 1, 'ملاحظة أولى');
  if jsonb_array_length(v_page -> 'items') <> 1
    or (v_page -> 'items' -> 0 ->> 'note_id')::uuid is distinct from v_note
    or v_page ->> 'has_more' is distinct from 'false' then
    raise exception 'notes search was not applied before limit';
  end if;
  -- Expire an entitlement after a real confirmed RPC, rather than only
  -- recognizing a privileged pre-seeded request on an already expired shop.
  execute 'reset role';
  update public.shop_entitlements set expires_at = now() - interval '1 second'
  where shop_id = 'b1818181-8181-4181-8181-818181818181';
  execute 'set local role authenticated';
  v_result := public.post_daily_note('c3838383-8383-4383-8383-838383838383',
    jsonb_build_object('version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
      'text', 'ملاحظة أولى', 'attachment', null));
  if v_result ->> 'replayed' is distinct from 'true'
    or (v_result ->> 'note_id')::uuid is distinct from v_note
    or public.get_daily_note_status('c3838383-8383-4383-8383-838383838383')
        ->> 'status' is distinct from 'completed'
    or (select count(*) from public.daily_note_attachments where operation_id = v_image) <> 1 then
    raise exception 'confirmed request or attachment lost after actual expiry';
  end if;
  begin
    perform public.post_daily_note('c1111111-1111-4111-8111-111111111111',
      jsonb_build_object('version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', 'طلب جديد', 'attachment', null));
    raise exception 'new_expired_key_succeeded';
  exception when others then
    if sqlerrm is distinct from 'shop_not_active' then raise; end if;
  end;
  execute 'reset role';
  update public.shop_entitlements set expires_at = now() + interval '30 days'
  where shop_id = 'b1818181-8181-4181-8181-818181818181';
  execute 'reset role';
  select coalesce(max(operation.shop_sequence), 0) into v_seq
  from public.financial_operations as operation
  where operation.shop_id = 'b1818181-8181-4181-8181-818181818181';
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  )
  select
    'b1818181-8181-4181-8181-818181818181',
    v_seq + series.n,
    'daily_note',
    v_day,
    '81818181-8181-4181-8181-818181818181',
    case when series.n = 520 then v_at else clock_timestamp() end
  from generate_series(1, 520) as series(n);
  insert into public.financial_operation_details (operation_id, shop_id, payload, created_at)
  select operation.id, operation.shop_id,
    jsonb_build_object(
      'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
      'text', 'صفحة ' || operation.shop_sequence::text, 'attachment', null
    ),
    operation.created_at
  from public.financial_operations as operation
  where operation.shop_id = 'b1818181-8181-4181-8181-818181818181'
    and operation.kind = 'daily_note'
    and operation.shop_sequence > v_seq;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
  perform set_config('request.jwt.claim.session_id', '', true);

  v_ledger := public.get_daily_ledger_v2();
  if jsonb_array_length(v_ledger -> 'feed') > 100
    or jsonb_array_length(v_ledger -> 'feed') < 1 then
    raise exception 'summary feed was not bounded to 100';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_ledger -> 'feed') as item(value)
    where item.value ->> 'operation_id' = v_sale::text
  ) then
    raise exception 'oldest sale remained inside the newest summary page';
  end if;
  if (v_ledger -> 'day_summary' ->> 'sale_piastres')::numeric <> 5000
    or (v_ledger -> 'day_summary' ->> 'purchase_piastres')::numeric <> 0
    or (v_ledger -> 'day_summary' ->> 'expense_piastres')::numeric <> 0 then
    raise exception 'bounded feed changed monetary summary';
  end if;
  if public.get_daily_ledger() ->> 'state' is distinct from 'confirmed' then
    raise exception 'legacy ledger root unreadable';
  end if;

  v_before := null;
  loop
    v_page := public.get_ledger_operation_page(v_day, v_before, null, 1);
    v_pages := v_pages + 1;
    v_seen := v_seen + jsonb_array_length(v_page -> 'items');
    if v_pages = 201 and v_page ->> 'has_more' is distinct from 'true' then
      raise exception 'history stopped at 200';
    end if;
    exit when v_page ->> 'has_more' is distinct from 'true';
    v_before := v_page ->> 'next_before_sequence';
    if v_before is null or v_pages > 700 then
      raise exception 'page walk did not advance';
    end if;
  end loop;
  if v_pages < 501 or v_seen <> v_pages then
    raise exception 'expected more than 500 disjoint pages, got %', v_pages;
  end if;

  v_older := public.get_ledger_operation_page(v_day, v_pivot, null, 100);
  v_newer := public.get_ledger_operation_page(v_day, null, v_pivot, 100);
  if exists (
    select 1 from jsonb_array_elements(v_older -> 'items') as item(value)
    where (item.value ->> 'shop_sequence')::bigint >= v_pivot::bigint
  ) or exists (
    select 1 from jsonb_array_elements(v_newer -> 'items') as item(value)
    where (item.value ->> 'shop_sequence')::bigint <= v_pivot::bigint
  ) then
    raise exception 'before and after pages overlap the pivot';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(v_older -> 'items') as older(value)
    join jsonb_array_elements(v_newer -> 'items') as newer(value)
      on newer.value ->> 'operation_id' = older.value ->> 'operation_id'
  ) then
    raise exception 'before and after pages share an operation';
  end if;
  begin
    perform public.get_ledger_operation_page(v_day, '2', '4', 10);
    raise exception 'both_cursors_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for both cursors got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_operation_page(v_day, null, null, 101);
    raise exception 'limit_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for limit got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_operation_page(v_day, '9223372036854775808', null, 1);
    raise exception 'overflow_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'overflow' then
        raise exception 'expected overflow got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_ledger_operation_page(v_day, '01', null, 1);
    raise exception 'canonical_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for sequence got %', sqlerrm;
      end if;
  end;

  select operation.shop_sequence into v_seq
  from public.financial_operations as operation
  where operation.shop_id = 'b1818181-8181-4181-8181-818181818181'
    and operation.created_at = v_at
  order by operation.shop_sequence desc
  limit 1;
  execute 'reset role';
  update public.shops set time_zone = 'UTC'
  where id = 'b1818181-8181-4181-8181-818181818181';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
  v_page := public.get_ledger_operation_page(v_day, null, (v_seq - 1)::text, 1);
  v_utc := v_page -> 'items' -> 0 ->> 'occurred_at_shop';
  execute 'reset role';
  update public.shops set time_zone = 'Africa/Cairo'
  where id = 'b1818181-8181-4181-8181-818181818181';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
  v_page := public.get_ledger_operation_page(v_day, null, (v_seq - 1)::text, 1);
  v_cairo := v_page -> 'items' -> 0 ->> 'occurred_at_shop';
  execute 'reset role';
  update public.shops set time_zone = 'Egypt'
  where id = 'b1818181-8181-4181-8181-818181818181';
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', '81818181-8181-4181-8181-818181818181', true);
  v_page := public.get_ledger_operation_page(v_day, null, (v_seq - 1)::text, 1);
  v_egypt := v_page -> 'items' -> 0 ->> 'occurred_at_shop';
  if left(v_utc, 10) is distinct from '2026-01-01'
    or left(v_cairo, 10) is distinct from '2026-01-02'
    or v_egypt is distinct from v_cairo
    or (v_page -> 'items' -> 0 ->> 'occurred_at_cairo') is distinct from v_cairo then
    raise exception 'shop timezone midnight mismatch utc % cairo % egypt %', v_utc, v_cairo, v_egypt;
  end if;

  v_state := public.get_daily_ledger_day_state();
  v_result := public.close_daily_ledger_day(
    'c7878787-8787-4787-8787-878787878787',
    (v_state ->> 'business_day_id')::uuid,
    (v_state ->> 'day_version')::bigint,
    v_state -> 'counts'
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'close failed %', v_result;
  end if;
  if jsonb_array_length(public.list_daily_notes(v_day, null, 30, 'ملاحظة') -> 'items') < 1 then
    raise exception 'historical note read failed';
  end if;
  begin
    perform public.post_daily_note(
      'c8888888-8888-4888-8888-888888888888',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
        'text', 'بعد الإقفال', 'attachment', null
      )
    );
    raise exception 'closed_write_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'day_closed' then
        raise exception 'expected day_closed got %', sqlerrm;
      end if;
  end;
  v_result := public.post_daily_note(
    'c3838383-8383-4383-8383-838383838383',
    jsonb_build_object(
      'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
      'text', 'ملاحظة أولى', 'attachment', null
    )
  );
  if v_result ->> 'replayed' is distinct from 'true'
    or (v_result ->> 'note_id')::uuid is distinct from v_note
    or (v_result ->> 'business_day_id')::uuid is distinct from v_day then
    raise exception 'closed replay did not return the original day %', v_result;
  end if;
  if public.get_daily_note_status('c3838383-8383-4383-8383-838383838383')
      ->> 'status' is distinct from 'completed' then
    raise exception 'closed confirmed key no longer recognizable';
  end if;

  begin
    insert into public.financial_operations (
      shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
    ) values (
      'b1818181-8181-4181-8181-818181818181', 1, 'daily_note', v_day,
      '81818181-8181-4181-8181-818181818181', now()
    );
    raise exception 'direct_write_succeeded';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm = 'direct_write_succeeded' then
        raise exception 'authenticated inserted a financial operation';
      end if;
  end;
  begin
    delete from storage.objects where bucket_id = 'eldafttar-private-notes';
    raise exception 'storage_delete_succeeded';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm = 'storage_delete_succeeded' then
        raise exception 'client deleted a private object';
      end if;
  end;
  if (select count(*) from storage.objects
      where bucket_id = 'eldafttar-private-notes' and name = v_path) <> 1 then
    raise exception 'owner lost private object visibility';
  end if;
end;
$test$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '82828282-8282-4282-8282-828282828282', true);
select set_config('request.jwt.claim.session_id', '', true);
do $cross$
declare
  v_note uuid;
  v_day uuid;
begin
  execute 'reset role';
  select operation.id, operation.business_day_id into v_note, v_day
  from public.financial_operations as operation
  where operation.shop_id = 'b1818181-8181-4181-8181-818181818181'
    and operation.kind = 'daily_note'
  limit 1;
  if v_note is null then
    raise exception 'cross-shop detail fixture missing';
  end if;
  execute 'set local role authenticated';
  if (select count(*) from storage.objects
      where name like 'b1818181-8181-4181-8181-818181818181/%') <> 0 then
    raise exception 'cross shop storage read';
  end if;
  begin
    perform public.list_daily_notes(
      v_day,
      null,
      10,
      null
    );
    raise exception 'cross_list_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for cross list got %', sqlerrm;
      end if;
  end;
  begin
    perform public.get_daily_note(v_note);
    raise exception 'cross_detail_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for cross shop got %', sqlerrm;
      end if;
  end;
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values (
      'eldafttar-private-notes',
      'b1818181-8181-4181-8181-818181818181/d1818181-8181-4181-8181-818181818181/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.jpg',
      '82828282-8282-4282-8282-828282828282',
      '{"mimetype":"image/jpeg","size":"4"}'::jsonb
    );
    raise exception 'cross_insert_succeeded';
  exception
    when others then
      if sqlerrm = 'cross_insert_succeeded' then
        raise exception 'cross shop storage insert was accepted';
      end if;
  end;
end;
$cross$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '83838383-8383-4383-8383-838383838383', true);
select set_config('request.jwt.claim.session_id', '', true);
do $revoked$
begin
  begin
    perform public.list_daily_notes(null, null, 10, null);
    raise exception 'revoked_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'forbidden' then
        raise exception 'expected forbidden for revoked got %', sqlerrm;
      end if;
  end;
end;
$revoked$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '84848484-8484-4484-8484-848484848484', true);
select set_config('request.jwt.claim.session_id', '', true);
do $anon_user$
begin
  begin
    perform public.post_daily_note(
      'c9999999-9999-4999-8999-999999999999',
      '{"version":1,"kind":"daily_note","business_day_id":"d9898989-8989-4989-8989-898989898989","text":"لا","attachment":null}'::jsonb
    );
    raise exception 'anon_user_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'forbidden' then
        raise exception 'expected forbidden for anonymous user got %', sqlerrm;
      end if;
  end;
end;
$anon_user$;

set local role anon;
do $anon_role$
begin
  begin
    perform public.list_daily_notes(null, null, 10, null);
    raise exception 'anon_role_succeeded';
  exception
    when insufficient_privilege then null;
    when others then
      if sqlerrm = 'anon_role_succeeded' then
        raise exception 'anon role listed notes';
      end if;
  end;
end;
$anon_role$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '86868686-8686-4686-8686-868686868686', true);
select set_config('request.jwt.claim.session_id', '', true);
do $admin$
begin
  begin
    perform public.post_daily_note(
      'caaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      '{"version":1,"kind":"daily_note","business_day_id":"d9898989-8989-4989-8989-898989898989","text":"إدارة","attachment":null}'::jsonb
    );
    raise exception 'admin_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'forbidden' then
        raise exception 'expected forbidden for admin got %', sqlerrm;
      end if;
  end;
end;
$admin$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '89898989-8989-4989-8989-898989898989', true);
select set_config('request.jwt.claim.session_id', '', true);
do $expired$
declare
  v_op uuid := 'e9898989-8989-4989-8989-898989898989';
  v_day uuid := 'd9898989-8989-4989-8989-898989898989';
  v_canonical jsonb;
  v_result jsonb;
begin
  execute 'reset role';
  insert into public.financial_operations (
    id, shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    v_op, 'b9898989-8989-4989-8989-898989898989', 1, 'daily_note',
    'd9898989-8989-4989-8989-898989898989',
    '89898989-8989-4989-8989-898989898989', now()
  );
  insert into public.financial_operation_details (operation_id, shop_id, payload, created_at)
  values (
    v_op, 'b9898989-8989-4989-8989-898989898989',
    jsonb_build_object(
      'version', 1, 'kind', 'daily_note',
      'business_day_id', 'd9898989-8989-4989-8989-898989898989',
      'text', 'قراءة منتهية', 'attachment', null
    ),
    now()
  );
  v_canonical := jsonb_build_object(
    'attachment', 'null'::jsonb,
    'business_day_id', v_day::text,
    'kind', 'daily_note',
    'text', 'قراءة منتهية',
    'version', 1
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id
  ) values (
    'b9898989-8989-4989-8989-898989898989',
    'c9898989-8989-4989-8989-898989898989',
    v_canonical,
    extensions.digest(convert_to(v_canonical::text, 'UTF8'), 'sha256'),
    v_op
  );
  insert into storage.objects (bucket_id, name, owner, metadata)
  values (
    'eldafttar-private-notes',
    'b9898989-8989-4989-8989-898989898989/d9898989-8989-4989-8989-898989898989/44444444-4444-4444-8444-444444444444.jpg',
    '89898989-8989-4989-8989-898989898989',
    '{"mimetype":"image/jpeg","size":"4"}'::jsonb
  );
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', '89898989-8989-4989-8989-898989898989', true);
  if jsonb_array_length(public.list_daily_notes(null, null, 10, null) -> 'items') <> 1 then
    raise exception 'expired owner could not read notes';
  end if;
  if (select count(*) from storage.objects
      where bucket_id = 'eldafttar-private-notes'
        and name like 'b9898989-8989-4989-8989-898989898989/%') <> 1 then
    raise exception 'expired owner could not read the private object';
  end if;
  v_result := public.post_daily_note(
    'c9898989-8989-4989-8989-898989898989',
    jsonb_build_object(
      'version', 1,
      'kind', 'daily_note',
      'business_day_id', v_day::text,
      'text', 'قراءة منتهية',
      'attachment', null
    )
  );
  if v_result ->> 'replayed' is distinct from 'true'
    or (v_result ->> 'note_id')::uuid is distinct from v_op
    or (v_result ->> 'business_day_id')::uuid is distinct from v_day then
    raise exception 'expired replay did not return the original day %', v_result;
  end if;
  if public.get_daily_note_status('c9898989-8989-4989-8989-898989898989')
      ->> 'status' is distinct from 'completed' then
    raise exception 'expired confirmed key no longer recognizable';
  end if;
  begin
    perform public.post_daily_note(
      'cbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      jsonb_build_object(
        'version', 1, 'kind', 'daily_note',
        'business_day_id', 'd9898989-8989-4989-8989-898989898989',
        'text', 'كتابة منتهية', 'attachment', null
      )
    );
    raise exception 'expired_write_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'shop_not_active' then
        raise exception 'expected shop_not_active got %', sqlerrm;
      end if;
  end;
  begin
    insert into storage.objects (bucket_id, name, owner, metadata)
    values (
      'eldafttar-private-notes',
      'b9898989-8989-4989-8989-898989898989/d9898989-8989-4989-8989-898989898989/55555555-5555-4555-8555-555555555555.jpg',
      '89898989-8989-4989-8989-898989898989',
      '{"mimetype":"image/jpeg","size":"4"}'::jsonb
    );
    raise exception 'expired_storage_succeeded';
  exception
    when others then
      if sqlerrm = 'expired_storage_succeeded' then
        raise exception 'expired owner inserted a private object';
      end if;
  end;
end;
$expired$;

reset role;
do $counts$
begin
  if (select count(*) from public.shops)
      <= (select value from notes_probe where name = 'shops_before') then
    raise exception 'note fixtures were not created';
  end if;
end;
$counts$;

-- Thousands of feed rows stay on the shop/day sequence index. Sequence holes
-- are returned as stored. Another owner and a stale session cannot read them.
do $bounded$
declare
  v_shop uuid := 'b1818181-8181-4181-8181-818181818181';
  v_other uuid := 'b2828282-8282-4282-8282-828282828282';
  v_owner uuid := '81818181-8181-4181-8181-818181818181';
  v_other_owner uuid := '82828282-8282-4282-8282-828282828282';
  v_day uuid;
  v_at timestamptz := clock_timestamp();
  v_base bigint;
  v_max bigint;
  v_below bigint;
  v_above bigint;
  v_gap bigint;
  v_version bigint;
  v_journal bigint;
  v_sale text;
  v_cash jsonb;
  v_page jsonb;
  v_before text;
  v_seen bigint[] := '{}';
  v_ids uuid[] := '{}';
  v_expected bigint[];
  v_plan text := '';
  v_line text;
  v_pages integer := 0;
begin
  select day.id, day.day_version
    into v_day, v_version
  from public.business_days as day
  where day.shop_id = v_shop
  order by day.opened_at desc, day.id desc
  limit 1;
  select coalesce(sum(posting.amount), 0)
    into v_journal
  from public.journal_postings as posting
  where posting.shop_id = v_shop;
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.session_id', '', true);
  execute 'set local role authenticated';
  v_page := public.get_daily_ledger_v2();
  v_sale := v_page -> 'day_summary' ->> 'sale_piastres';
  v_cash := v_page -> 'cash';
  if v_sale is distinct from '5000'
    or v_cash is distinct from (public.get_daily_ledger() -> 'cash') then
    raise exception 'baseline gross or net summary drifted';
  end if;
  execute 'reset role';
  select coalesce(max(operation.shop_sequence), 0)
    into v_base
  from public.financial_operations as operation
  where operation.shop_id = v_shop;
  -- Above JavaScript's exact integer range: values must remain decimal strings.
  v_base := greatest(v_base, 9007199254740993::bigint);
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  )
  select v_shop, v_base + series.n, 'daily_note', v_day, v_owner, v_at
  from generate_series(1, 4200) as series(n)
  where series.n < 2000 or series.n > 2150;
  v_below := v_base + 1999;
  v_gap := v_base + 2000;
  v_above := v_base + 2151;
  v_max := v_base + 4200;
  insert into public.business_days(id, shop_id, business_date, opened_at, closed_at, status, day_version)
  values ('d1818181-8181-4181-8181-818181818181', v_shop,
    (v_at at time zone 'Africa/Cairo')::date - 1, v_at - interval '1 day',
    v_at - interval '1 hour', 'closed', 1);
  insert into public.financial_operations(shop_id, shop_sequence, kind, business_day_id, actor_user_id)
  values (v_shop, v_max + 1, 'daily_note', 'd1818181-8181-4181-8181-818181818181', v_owner);
  if exists (
    select 1 from public.financial_operations as operation
    where operation.shop_id = v_shop and operation.shop_sequence = v_gap
  ) then
    raise exception 'fixture failed to leave a sequence gap';
  end if;
  insert into public.business_days (
    id, shop_id, business_date, opened_at, status, day_version
  ) values (
    'd2828282-8282-4282-8282-828282828282',
    v_other,
    (v_at at time zone 'Africa/Cairo')::date,
    v_at,
    'open',
    1
  );
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  )
  select v_other, series.n, 'daily_note',
    'd2828282-8282-4282-8282-828282828282', v_other_owner, v_at
  from generate_series(1, 39) as series(n);
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    v_other, v_max, 'daily_note',
    'd2828282-8282-4282-8282-828282828282', v_other_owner, v_at
  );
  execute 'analyze public.financial_operations';
  for v_line in execute format(
    'explain (format text) select operation.id from public.financial_operations as operation where operation.shop_id = %L::uuid and operation.business_day_id = %L::uuid order by operation.shop_sequence desc limit 101',
    v_shop, v_day)
  loop
    v_plan := v_plan || v_line || E'\n';
  end loop;
  if position('Limit' in v_plan) = 0
    or position('Index Scan' in v_plan) = 0
    or v_plan like '%Seq Scan on financial_operations%'
    or v_plan like '%Sort%'
    or (
      v_plan not like '%financial_operations_shop_day_sequence_idx%'
      and v_plan not like '%financial_operations_shop_sequence_key%'
    ) then
    raise exception 'feed page is not a bounded index read: %', v_plan;
  end if;
  if pg_catalog.pg_get_functiondef('public.get_daily_ledger_v2()'::regprocedure)
    ilike '%get_daily_ledger_v2_before_notes_pagination%' then
    raise exception 'summary still calls the unbounded legacy feed';
  end if;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.session_id', '', true);
  v_page := public.get_daily_ledger_v2();
  if jsonb_array_length(v_page -> 'feed') <> 100
    or jsonb_typeof(v_page -> 'feed' -> 0 -> 'shop_sequence') is distinct from 'string'
    or v_page -> 'feed' -> 0 ->> 'shop_sequence' is distinct from v_max::text
    or (v_page -> 'feed' -> 0 ->> 'shop_sequence')::bigint is distinct from v_max
    or (v_page -> 'feed' -> 99 ->> 'shop_sequence')::bigint is distinct from v_max - 99
    or v_page -> 'feed_page' ->> 'next_before_sequence' is distinct from (v_max - 99)::text then
    raise exception 'summary page did not keep the newest sequences';
  end if;
  if public.list_daily_notes('d1818181-8181-4181-8181-818181818181', null, 50, null)
      ->> 'server_sequence' is distinct from (v_max + 1)::text then
    raise exception 'notes sequence crossed same-shop day boundary';
  end if;
  if v_page -> 'day_summary' ->> 'sale_piastres' is distinct from v_sale
    or v_page -> 'day_summary' ->> 'purchase_piastres' is distinct from '0'
    or v_page -> 'day_summary' ->> 'expense_piastres' is distinct from '0'
    or v_page -> 'day_summary' ->> 'sale_count' is distinct from '1'
    or v_page -> 'cash' is distinct from v_cash then
    raise exception 'notes changed gross or net figures';
  end if;
  if (select day.day_version from public.business_days as day where day.id = v_day)
      is distinct from v_version
    or (select coalesce(sum(posting.amount), 0)
        from public.journal_postings as posting
        where posting.shop_id = v_shop) is distinct from v_journal
    or exists (
      select 1
      from public.journals as journal
      join public.financial_operations as operation
        on operation.shop_id = journal.shop_id
       and operation.id = journal.operation_id
      where journal.shop_id = v_shop
        and operation.kind = 'daily_note'
    ) then
    raise exception 'notes changed journal amounts or the day version';
  end if;
  v_page := public.get_ledger_operation_page(v_day, v_above::text, null, 1);
  if (v_page -> 'items' -> 0 ->> 'shop_sequence')::bigint is distinct from v_below then
    raise exception 'cursor filled a sequence gap with %',
      v_page -> 'items' -> 0 ->> 'shop_sequence';
  end if;
  v_before := null;
  loop
    v_page := public.get_ledger_operation_page(v_day, v_before, null, 100);
    v_pages := v_pages + 1;
    if jsonb_array_length(v_page -> 'items') > 0 then
      select v_seen || coalesce(array_agg((item.value ->> 'shop_sequence')::bigint), '{}'),
             v_ids || coalesce(array_agg((item.value ->> 'operation_id')::uuid), '{}')
        into v_seen, v_ids
      from jsonb_array_elements(v_page -> 'items') with ordinality as item(value, ordinality);
    end if;
    exit when v_page ->> 'has_more' is distinct from 'true';
    v_before := v_page ->> 'next_before_sequence';
    if v_before is null or v_pages > 80 then
      raise exception 'bounded walk stalled at %', v_pages;
    end if;
  end loop;
  select coalesce(array_agg(operation.shop_sequence order by operation.shop_sequence), '{}')
    into v_expected
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = v_day;
  if (select array_agg(seq order by seq) from unnest(v_seen) as seq)
      is distinct from v_expected
    or v_gap = any (v_seen)
    or exists (
      select 1
      from unnest(v_ids) as seen(id)
      join public.financial_operations as operation on operation.id = seen.id
      where operation.shop_id is distinct from v_shop
    ) then
    raise exception 'paged feed lost a gap, a row, or shop isolation';
  end if;
  perform set_config('request.jwt.claim.sub', v_other_owner::text, true);
  perform set_config('request.jwt.claim.session_id', '', true);
  v_page := public.get_ledger_operation_page(null, null, null, 100);
  if jsonb_array_length(v_page -> 'items') <> 40
    or exists (
      select 1
      from jsonb_array_elements(v_page -> 'items') as item(value)
      where (item.value ->> 'operation_id')::uuid = any (v_ids)
    ) then
    raise exception 'other owner did not stay on their own feed';
  end if;
  begin
    perform public.get_ledger_operation_page(v_day, null, null, 10);
    raise exception 'foreign_day_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'invalid_input' then
        raise exception 'expected invalid_input for foreign day got %', sqlerrm;
      end if;
  end;
  execute 'reset role';
  insert into auth.sessions (id, user_id, not_after) values
    -- Authorization compares expiry with transaction time. A long fixture setup
    -- can put clock_timestamp() minutes ahead of that fixed server timestamp.
    ('a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', v_owner, transaction_timestamp() - interval '2 minutes'),
    ('a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', v_other_owner, v_at + interval '30 minutes');
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.session_id', 'a1a1a1a1-a1a1-41a1-81a1-a1a1a1a1a1a1', true);
  begin
    perform public.get_daily_ledger_v2();
    raise exception 'stale_session_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'session_expired' then
        raise exception 'expected session_expired for stale session got %', sqlerrm;
      end if;
  end;
  perform set_config('request.jwt.claim.session_id', 'a2a2a2a2-a2a2-42a2-82a2-a2a2a2a2a2a2', true);
  begin
    perform public.get_ledger_operation_page(null, null, null, 10);
    raise exception 'crossed_session_succeeded';
  exception
    when others then
      if sqlerrm is distinct from 'session_expired' then
        raise exception 'expected session_expired for crossed session got %', sqlerrm;
      end if;
  end;
  perform set_config('request.jwt.claim.session_id', '', true);
  v_page := public.get_daily_ledger_v2();
  if (v_page -> 'feed' -> 0 ->> 'shop_sequence')::bigint is distinct from v_max
    or exists (
      select 1
      from public.financial_operations as operation
      where operation.shop_id = v_other
        and operation.id = (v_page -> 'feed' -> 0 ->> 'operation_id')::uuid
    ) then
    raise exception 'cleared session mixed owners';
  end if;
  execute 'reset role';
  create or replace function public.get_daily_ledger_v2_before_notes_pagination()
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
  as $trap$
  begin
    raise exception 'unbounded_legacy_feed';
  end;
  $trap$;
  execute 'set local role authenticated';
  perform set_config('request.jwt.claim.sub', v_owner::text, true);
  perform set_config('request.jwt.claim.session_id', '', true);
  v_page := public.get_daily_ledger_v2();
  if jsonb_array_length(v_page -> 'feed') <> 100
    or v_page -> 'day_summary' ->> 'sale_piastres' is distinct from '5000'
    or v_page -> 'day_summary' -> 'gold_by_bucket' -> 0 ->> 'milligrams'
      is distinct from '1000' then
    raise exception 'bounded summary changed after the legacy feed was trapped';
  end if;
end;
$bounded$;

reset role;
savepoint inventory_kind_guard;
create temp table note_kind_probe (kind text);
alter table note_kind_probe add constraint note_kind_probe_check
  check (kind in ('sale', 'inventory_count'));
select private.extend_enumerated_check(
  'note_kind_probe'::regclass,
  'note_kind_probe_check',
  'kind',
  'daily_note');
insert into note_kind_probe (kind) values ('sale'), ('inventory_count'), ('daily_note');
do $removed_kind$
begin
  insert into note_kind_probe (kind) values ('purchase');
  raise exception 'removed_kind_succeeded';
exception
  when check_violation then null;
  when others then
    if sqlerrm = 'removed_kind_succeeded' then
      raise exception 'extended check dropped the independent kind or kept a removed one';
    end if;
end;
$removed_kind$;
select private.extend_enumerated_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  'inventory_count');
select private.extend_enumerated_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  'inventory_count_recorded');
select private.extend_enumerated_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  'inventory_count_recorded');
do $live_kinds$
declare
  v_kind text;
  v_action text;
  v_event text;
  v_shop uuid := 'b1818181-8181-4181-8181-818181818181';
  v_actor uuid := '81818181-8181-4181-8181-818181818181';
  v_day uuid;
  v_operation uuid;
  v_seq bigint;
begin
  select pg_catalog.pg_get_constraintdef(constraint_row.oid)
    into v_kind
  from pg_catalog.pg_constraint as constraint_row
  where constraint_row.conname = 'financial_operations_kind_check';
  select pg_catalog.pg_get_constraintdef(constraint_row.oid)
    into v_action
  from pg_catalog.pg_constraint as constraint_row
  where constraint_row.conname = 'financial_audit_events_action_check';
  select pg_catalog.pg_get_constraintdef(constraint_row.oid)
    into v_event
  from pg_catalog.pg_constraint as constraint_row
  where constraint_row.conname = 'financial_outbox_event_check';
  if position('''inventory_count''' in v_kind) = 0
    or position('''daily_note''' in v_kind) = 0
    or position('''sale_return''' in v_kind) = 0
    or position('''scrap_to_stock''' in v_kind) = 0
    or position('''inventory_count_recorded''' in v_action) = 0
    or position('''daily_note_recorded''' in v_action) = 0
    or position('''invoice_send_confirmed''' in v_action) = 0
    or position('''inventory_count_recorded''' in v_event) = 0
    or position('''daily_note_recorded''' in v_event) = 0
    or position('''scrap_sale_confirmed''' in v_event) = 0 then
    raise exception 'extending note checks removed an existing kind';
  end if;
  select day.id into v_day
  from public.business_days as day
  where day.shop_id = v_shop
  order by day.opened_at desc
  limit 1;
  select coalesce(max(operation.shop_sequence), 0) + 1
    into v_seq
  from public.financial_operations as operation
  where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id
  ) values (
    v_shop, v_seq, 'inventory_count', v_day, v_actor
  ) returning id into v_operation;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, details
  ) values (
    v_shop, v_actor, 'inventory_count_recorded', v_operation, '{}'::jsonb
  );
  insert into public.financial_outbox (shop_id, operation_id, event_type)
  values (v_shop, v_operation, 'inventory_count_recorded');
  begin
    insert into public.financial_operations (
      shop_id, shop_sequence, kind, business_day_id, actor_user_id
    ) values (
      v_shop, v_seq + 1, 'removed_kind', v_day, v_actor
    );
    raise exception 'removed_kind_succeeded';
  exception
    when check_violation then null;
    when others then
      if sqlerrm = 'removed_kind_succeeded' then
        raise exception 'live kind check accepted a removed value';
      end if;
  end;
end;
$live_kinds$;
rollback to savepoint inventory_kind_guard;

rollback;

-- Owner edit and delete for daily notes. One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('16161616-1616-4161-8161-616161616161', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'note-owner@example.test', false, now(), now()),
  ('17171717-1717-4171-8171-717171717171', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'note-partner@example.test', false, now(), now()),
  ('18181818-1818-4181-8181-818181818181', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'note-other@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1616161-1616-4161-8161-616161616161', 'متجر الملاحظات', 'المالك', 'Africa/Cairo'),
  ('b1818181-1818-4181-8181-818181818181', 'متجر آخر', 'آخر', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1616161-1616-4161-8161-616161616161', '16161616-1616-4161-8161-616161616161', 'owner'),
  ('b1616161-1616-4161-8161-616161616161', '17171717-1717-4171-8171-717171717171', 'partner'),
  ('b1818181-1818-4181-8181-818181818181', '18181818-1818-4181-8181-818181818181', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1616161-1616-4161-8161-616161616161', now() - interval '1 day', now() + interval '30 days'),
  ('b1818181-1818-4181-8181-818181818181', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', '16161616-1616-4161-8161-616161616161', true);

do $test$
declare
  v_shop uuid := 'b1616161-1616-4161-8161-616161616161';
  v_day uuid;
  v_date date;
  v_note uuid;
  v_client uuid := 'c1616161-1616-4161-8161-616161616161';
  v_key text;
  v_result jsonb;
  v_page jsonb;
  v_item jsonb;
  v_original text;
begin
  -- The change table is closed to clients.
  begin
    perform 1 from public.daily_note_changes limit 1;
    raise exception 'client_read_daily_note_changes';
  exception when insufficient_privilege then null;
  end;
  v_result := public.confirm_opening_balances(
    'a1616161-1616-4161-8161-616161616161',
    '{"version":1,"cash":{"cash":"500000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'opening failed %', v_result;
  end if;
  v_day := (public.get_daily_ledger_day_state() ->> 'business_day_id')::uuid;
  v_date := (public.get_daily_ledger_day_state() ->> 'business_date')::date;
  v_result := public.post_daily_note(
    'd1616161-1616-4161-8161-616161616161',
    jsonb_build_object(
      'version', 1, 'kind', 'daily_note', 'business_day_id', v_day::text,
      'text', 'النص الأصلي', 'attachment', null
    )
  );
  v_note := (v_result ->> 'note_id')::uuid;
  if v_result ->> 'ok' is distinct from 'true' or v_note is null then
    raise exception 'note was not posted %', v_result;
  end if;
  v_original := (
    select detail.payload ->> 'text'
    from public.financial_operation_details as detail
    where detail.shop_id = v_shop and detail.operation_id = v_note
  );
  v_key := 'note-image/' || v_shop::text || '/' || v_day::text || '/' || v_client::text || '.jpg';
  execute 'reset role';
  insert into public.r2_media_objects (
    object_key, shop_id, kind, mime, byte_size, sha256, uploaded_by, verified_at
  ) values (
    v_key, v_shop, 'note_image', 'image/jpeg', 4, repeat('ab', 32),
    '16161616-1616-4161-8161-616161616161', clock_timestamp()
  );
  insert into public.daily_note_attachments (
    operation_id, shop_id, business_day_id, bucket_id, object_name,
    mime_type, byte_size, client_object_id, created_at
  ) values (
    v_note, v_shop, v_day, 'cloudflare-r2',
    v_shop::text || '/' || v_day::text || '/' || v_client::text || '.jpg',
    'image/jpeg', 4, v_client, clock_timestamp()
  );
  execute 'set local role authenticated';

  if public.note_image_readable_v1(v_key) is distinct from true then
    raise exception 'a live note image must be readable';
  end if;
  v_result := public.post_daily_note_change_v1(
    'e1616161-1616-4161-8161-616161616161', v_note, 'edit', '  النص الجديد  '
  );
  if v_result ->> 'replayed' is distinct from 'false'
    or v_result ->> 'action' is distinct from 'edit' then
    raise exception 'edit did not commit %', v_result;
  end if;
  if (select detail.payload ->> 'text'
      from public.financial_operation_details as detail
      where detail.operation_id = v_note) is distinct from v_original then
    raise exception 'the original payload was rewritten';
  end if;
  v_page := public.list_daily_notes(v_day, null, 20, null);
  if v_page #>> '{items,0,text}' is distinct from 'النص الجديد'
    or v_page #>> '{items,0,edited}' is distinct from 'true'
    or v_page #>> '{items,0,edited_at}' is null then
    raise exception 'list did not show the edit %', v_page;
  end if;
  if jsonb_array_length(public.list_daily_notes(v_day, null, 20, 'الجديد') -> 'items') <> 1
    or jsonb_array_length(public.list_daily_notes(v_day, null, 20, 'الأصلي') -> 'items') <> 0 then
    raise exception 'search did not use the edited text';
  end if;
  v_page := public.get_ledger_date_v1(v_date, null, 20);
  select item into v_item
  from jsonb_array_elements(v_page #> '{feed_page,items}') as item
  where item ->> 'operation_id' = v_note::text;
  if v_item ->> 'text' is distinct from 'النص الجديد'
    or v_item ->> 'edited' is distinct from 'true' then
    raise exception 'feed did not carry the edited note %', v_item;
  end if;
  v_result := public.post_daily_note_change_v1(
    'e1616161-1616-4161-8161-616161616161', v_note, 'edit', 'النص الجديد'
  );
  if v_result ->> 'replayed' is distinct from 'true' then
    raise exception 'edit replay failed %', v_result;
  end if;
  begin
    perform public.post_daily_note_change_v1(
      'e1616161-1616-4161-8161-616161616161', v_note, 'edit', 'نص مختلف'
    );
    raise exception 'mismatch_succeeded';
  exception when others then
    if sqlerrm is distinct from 'payload_mismatch' then
      raise exception 'expected payload_mismatch got %', sqlerrm;
    end if;
  end;
  -- Clients cannot read daily_note_changes; count it as the database owner.
  execute 'reset role';
  if (select count(*) from public.daily_note_changes where note_operation_id = v_note) <> 1 then
    raise exception 'replay wrote a second change';
  end if;
  update public.business_days
    set status = 'closed', closed_at = clock_timestamp()
    where id = v_day;
  execute 'set local role authenticated';
  v_result := public.post_daily_note_change_v1(
    'e2626262-2626-4262-8262-262626262626', v_note, 'edit', 'بعد الإقفال'
  );
  if v_result ->> 'replayed' is distinct from 'false'
    or public.list_daily_notes(v_day, null, 20, null) #>> '{items,0,text}'
      is distinct from 'بعد الإقفال' then
    raise exception 'a closed day refused the edit %', v_result;
  end if;

  v_result := public.post_daily_note_change_v1(
    'e3636363-3636-4363-8363-363636363636', v_note, 'delete', null
  );
  if v_result ->> 'action' is distinct from 'delete' then
    raise exception 'delete did not commit %', v_result;
  end if;
  if jsonb_array_length(public.list_daily_notes(v_day, null, 20, null) -> 'items') <> 0 then
    raise exception 'a deleted note stayed in the list';
  end if;
  if public.get_daily_ledger_home_v1() #>> '{journal_context,note_count}' is distinct from '0' then
    raise exception 'note_count still counts the deleted note';
  end if;
  v_page := public.get_ledger_date_v1(v_date, null, 20);
  if exists (
    select 1 from jsonb_array_elements(v_page #> '{feed_page,items}') as item
    where item ->> 'operation_id' = v_note::text
  ) then
    raise exception 'the feed still shows the deleted note';
  end if;
  begin
    perform public.get_daily_note(v_note);
    raise exception 'deleted_note_readable';
  exception when others then
    if sqlerrm is distinct from 'invalid_input' then
      raise exception 'expected invalid_input for a deleted note got %', sqlerrm;
    end if;
  end;
  if public.note_image_readable_v1(v_key) is distinct from false then
    raise exception 'a deleted note image stayed readable';
  end if;
  execute 'reset role';
  if (select count(*) from public.r2_media_objects where object_key = v_key) <> 1
    or (select count(*) from public.daily_note_attachments where operation_id = v_note) <> 1
    or (select count(*) from public.financial_audit_events
        where operation_id = v_note and action = 'daily_note_deleted') <> 1 then
    raise exception 'the object, attachment, or audit row was removed';
  end if;
  execute 'set local role authenticated';
  v_result := public.post_daily_note_change_v1(
    'e3636363-3636-4363-8363-363636363636', v_note, 'delete', null
  );
  if v_result ->> 'replayed' is distinct from 'true' then
    raise exception 'delete replay failed %', v_result;
  end if;
  begin
    perform public.post_daily_note_change_v1(
      'e4646464-4646-4464-8464-464646464646', v_note, 'edit', 'بعد المسح'
    );
    raise exception 'edit_after_delete_succeeded';
  exception when others then
    if sqlerrm is distinct from 'note_deleted' then
      raise exception 'expected note_deleted got %', sqlerrm;
    end if;
  end;

  perform set_config('request.jwt.claim.sub', '17171717-1717-4171-8171-717171717171', true);
  begin
    perform public.post_daily_note_change_v1(
      'e5656565-5656-4565-8565-565656565656', v_note, 'edit', 'شريك'
    );
    raise exception 'partner_succeeded';
  exception when others then
    if sqlerrm is distinct from 'forbidden' then
      raise exception 'expected forbidden for a partner got %', sqlerrm;
    end if;
  end;
  perform set_config('request.jwt.claim.sub', '18181818-1818-4181-8181-818181818181', true);
  begin
    perform public.post_daily_note_change_v1(
      'e6666666-6666-4666-8666-666666666666', v_note, 'delete', null
    );
    raise exception 'other_shop_succeeded';
  exception when others then
    if sqlerrm is distinct from 'not_found' then
      raise exception 'expected not_found for another shop got %', sqlerrm;
    end if;
  end;
end;
$test$;

select 'DAILY_NOTE_CHANGES_PASSED' as result;
rollback;

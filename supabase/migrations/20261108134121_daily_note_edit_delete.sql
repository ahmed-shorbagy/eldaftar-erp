-- Owner edit and delete for daily notes on any day.
-- The original payload, attachment row, and R2 object stay.
-- A deleted note leaves lists, the feed, and note_count.
-- Its image is no longer signed for reading.

begin;

select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  array['daily_note_edited', 'daily_note_deleted']
);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  array['daily_note_edited', 'daily_note_deleted']
);

create table public.daily_note_changes (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  note_operation_id uuid not null,
  action text not null,
  text text,
  actor_user_id uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  command_key uuid not null,
  constraint daily_note_changes_action_check check (action in ('edit', 'delete')),
  constraint daily_note_changes_text_check check (
    (action = 'delete' and text is null)
    or (
      action = 'edit'
      and text is not null
      and char_length(text) <= 4000
      and text = btrim(text)
    )
  ),
  constraint daily_note_changes_command_key unique (shop_id, command_key),
  constraint daily_note_changes_note_fkey
    foreign key (shop_id, note_operation_id)
    references public.financial_operations (shop_id, id),
  constraint daily_note_changes_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create index daily_note_changes_note_idx
  on public.daily_note_changes (shop_id, note_operation_id, created_at desc);

alter table public.daily_note_changes enable row level security;
revoke all on table public.daily_note_changes from public, anon, authenticated;

create function private.daily_note_deleted(p_shop uuid, p_operation uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce((
    select change.action = 'delete'
    from public.daily_note_changes as change
    where change.shop_id = p_shop
      and change.note_operation_id = p_operation
    order by change.created_at desc, change.id desc
    limit 1
  ), false);
$fn$;

create function private.daily_note_display_text(p_shop uuid, p_operation uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce((
    select change.text
    from public.daily_note_changes as change
    where change.shop_id = p_shop
      and change.note_operation_id = p_operation
      and change.action = 'edit'
    order by change.created_at desc, change.id desc
    limit 1
  ), (
    select detail.payload ->> 'text'
    from public.financial_operation_details as detail
    where detail.shop_id = p_shop
      and detail.operation_id = p_operation
  ), '');
$fn$;

create function private.daily_note_edited_at(p_shop uuid, p_operation uuid)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $fn$
  select change.created_at
  from public.daily_note_changes as change
  where change.shop_id = p_shop
    and change.note_operation_id = p_operation
    and change.action = 'edit'
  order by change.created_at desc, change.id desc
  limit 1;
$fn$;

revoke all on function private.daily_note_deleted(uuid, uuid),
  private.daily_note_display_text(uuid, uuid),
  private.daily_note_edited_at(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.daily_note_json(
  p_operation_id uuid,
  p_shop uuid,
  p_zone text,
  p_name text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_row jsonb;
  v_edited_at timestamptz;
begin
  if private.daily_note_deleted(p_shop, p_operation_id) then
    return null;
  end if;
  v_edited_at := private.daily_note_edited_at(p_shop, p_operation_id);
  select jsonb_build_object(
    'note_id', operation.id,
    'operation_id', operation.id,
    'shop_sequence', operation.shop_sequence::text,
    'business_day_id', operation.business_day_id,
    'text', private.daily_note_display_text(p_shop, operation.id),
    'actor_display_name', coalesce(p_name, ''),
    'created_at', pg_catalog.to_jsonb(operation.created_at),
    'occurred_at_shop', to_char(
      operation.created_at at time zone p_zone,
      'YYYY-MM-DD"T"HH24:MI:SS'
    ),
    'edited', v_edited_at is not null,
    'edited_at', case
      when v_edited_at is null then 'null'::jsonb
      else pg_catalog.to_jsonb(v_edited_at)
    end,
    'attachment', case
      when attachment.operation_id is null then null
      else jsonb_build_object(
        'bucket', attachment.bucket_id,
        'object_name', attachment.object_name,
        'mime_type', attachment.mime_type,
        'byte_size', attachment.byte_size::text
      )
    end
  )
    into v_row
  from public.financial_operations as operation
  join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  left join public.daily_note_attachments as attachment
    on attachment.shop_id = operation.shop_id
   and attachment.operation_id = operation.id
  where operation.shop_id = p_shop
    and operation.id = p_operation_id
    and operation.kind = 'daily_note';
  return v_row;
end;
$fn$;

revoke all on function private.daily_note_json(uuid, uuid, text, text)
  from public, anon, authenticated;

create or replace function private.note_storage_select_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  if auth.uid() is null or p_name is null then
    return false;
  end if;
  begin
    v_shop := ((storage.foldername(p_name))[1])::uuid;
  exception
    when others then
      return false;
  end;
  if not private.opening_financial_visible(v_shop) then
    return false;
  end if;
  return not exists (
    select 1
    from public.daily_note_attachments as attachment
    where attachment.shop_id = v_shop
      and attachment.object_name = p_name
      and private.daily_note_deleted(v_shop, attachment.operation_id)
  );
end;
$fn$;

create function public.note_image_readable_v1(p_object_key text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_name text;
  v_operation uuid;
begin
  v_shop := private.opening_require_reader_shop();
  if p_object_key is null
    or p_object_key !~ '^note-image/[0-9a-f-]+/.+'
    or p_object_key like '%..%'
    or strpos(p_object_key, '//') > 0 then
    return false;
  end if;
  v_name := substr(p_object_key, length('note-image/') + 1);
  if split_part(v_name, '/', 1) is distinct from v_shop::text then
    return false;
  end if;
  select attachment.operation_id
    into v_operation
  from public.daily_note_attachments as attachment
  where attachment.shop_id = v_shop
    and attachment.object_name = v_name;
  if v_operation is null then
    return true;
  end if;
  return not private.daily_note_deleted(v_shop, v_operation);
end;
$fn$;

revoke all on function public.note_image_readable_v1(text) from public, anon;
grant execute on function public.note_image_readable_v1(text) to authenticated;

create function public.post_daily_note_change_v1(
  p_idempotency_key uuid,
  p_note_operation_id uuid,
  p_action text,
  p_text text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_actor uuid;
  v_kind text;
  v_text text;
  v_canonical jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_at timestamptz;
  v_action text;
begin
  if p_idempotency_key is null or p_note_operation_id is null
    or p_action is null or p_action not in ('edit', 'delete') then
    raise exception 'invalid_input';
  end if;
  if p_action = 'edit' then
    if p_text is null then
      raise exception 'invalid_input';
    end if;
    v_text := btrim(p_text);
    if char_length(v_text) > 4000 then
      raise exception 'overflow';
    end if;
    if translate(v_text, E'\n\r\t', '') ~ '[[:cntrl:]]' then
      raise exception 'invalid_input';
    end if;
  else
    if p_text is not null then
      raise exception 'invalid_input';
    end if;
    v_text := null;
  end if;
  v_canonical := jsonb_build_object(
    'action', p_action,
    'kind', 'daily_note_change',
    'note_operation_id', p_note_operation_id,
    'text', to_jsonb(v_text)
  );
  v_hash := extensions.digest(convert_to(v_canonical::text, 'UTF8'), 'sha256');
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  select request.*
    into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key;
  if v_request.id is not null then
    if v_request.operation_id is distinct from p_note_operation_id
      or v_request.payload_canonical is distinct from v_canonical
      or v_request.payload_sha256 is distinct from v_hash then
      raise exception 'payload_mismatch';
    end if;
    return jsonb_build_object(
      'ok', true,
      'replayed', true,
      'note_id', p_note_operation_id,
      'action', p_action
    );
  end if;
  select operation.kind
    into v_kind
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.id = p_note_operation_id;
  if v_kind is distinct from 'daily_note' then
    raise exception 'not_found';
  end if;
  if private.daily_note_deleted(v_shop, p_note_operation_id) then
    raise exception 'note_deleted';
  end if;
  if p_action = 'edit' and v_text = '' and not exists (
    select 1
    from public.daily_note_attachments as attachment
    where attachment.shop_id = v_shop
      and attachment.operation_id = p_note_operation_id
  ) then
    raise exception 'invalid_input';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  v_action := case p_action
    when 'edit' then 'daily_note_edited'
    else 'daily_note_deleted'
  end;
  insert into public.daily_note_changes (
    shop_id, note_operation_id, action, text, actor_user_id, created_at, command_key
  ) values (
    v_shop, p_note_operation_id, p_action, v_text, v_actor, v_at, p_idempotency_key
  );
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, v_action, p_note_operation_id, v_at,
    jsonb_build_object('action', p_action, 'note_operation_id', p_note_operation_id)
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (
    v_shop, p_note_operation_id, v_action, v_at
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256, operation_id, created_at
  ) values (
    v_shop, p_idempotency_key, v_canonical, v_hash, p_note_operation_id, v_at
  );
  perform private.bump_shop_sync(v_shop, 'ledger');
  return jsonb_build_object(
    'ok', true,
    'replayed', false,
    'note_id', p_note_operation_id,
    'action', p_action
  );
end;
$fn$;

revoke all on function public.post_daily_note_change_v1(uuid, uuid, text, text)
  from public, anon;
grant execute on function public.post_daily_note_change_v1(uuid, uuid, text, text)
  to authenticated;

-- Hide deleted notes from the note lists and search the text the owner sees.
do $patch_lists$
declare
  v_proc regprocedure;
  v_def text;
  v_old text;
  v_new text;
begin
  foreach v_proc in array array[
    'public.list_daily_notes(uuid, text, integer, text)'::regprocedure,
    'public.list_daily_notes_date_v1(date, text, integer, text)'::regprocedure
  ] loop
    v_def := pg_catalog.pg_get_functiondef(v_proc);
    v_old := 'and operation.kind = ''daily_note''';
    v_new := 'and operation.kind = ''daily_note'' and not private.daily_note_deleted(operation.shop_id, operation.id)';
    if pg_catalog.strpos(v_def, v_old) = 0 then
      raise exception 'note_list_kind_anchor: %', v_proc;
    end if;
    v_def := pg_catalog.replace(v_def, v_old, v_new);
    v_old := 'lower(coalesce(detail.payload ->> ''text'', ''''))';
    v_new := 'lower(private.daily_note_display_text(operation.shop_id, operation.id))';
    if pg_catalog.strpos(v_def, v_old) = 0 then
      raise exception 'note_list_text_anchor: %', v_proc;
    end if;
    v_def := pg_catalog.replace(v_def, v_old, v_new);
    execute v_def;
  end loop;
end;
$patch_lists$;

do $patch_feeds$
declare
  v_def text;
  v_old text;
  v_new text;
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.get_ledger_date_v1_before_staff(date, text, integer)'::regprocedure
  );
  v_old := 'and (v_before is null or operation.shop_sequence < v_before)';
  v_new := v_old || ' and not private.daily_note_deleted(operation.shop_id, operation.id)';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'note_date_feed_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);

  v_def := pg_catalog.pg_get_functiondef(
    'public.get_ledger_operation_page(uuid, text, text, integer)'::regprocedure
  );
  if pg_catalog.strpos(v_def, v_old) = 0
    or pg_catalog.strpos(v_def, 'and operation.shop_sequence > v_after') = 0 then
    raise exception 'note_page_feed_anchor';
  end if;
  v_def := pg_catalog.replace(v_def, v_old, v_new);
  v_def := pg_catalog.replace(
    v_def,
    'and operation.shop_sequence > v_after',
    'and operation.shop_sequence > v_after and not private.daily_note_deleted(operation.shop_id, operation.id)'
  );
  execute v_def;

  v_def := pg_catalog.pg_get_functiondef(
    'public.get_daily_ledger_home_v1_before_staff()'::regprocedure
  );
  v_old := 'count(*) filter (where operation.kind = ''daily_note'')';
  v_new := 'count(*) filter (where operation.kind = ''daily_note'' and not private.daily_note_deleted(operation.shop_id, operation.id))';
  if pg_catalog.strpos(v_def, v_old) = 0 then
    raise exception 'note_count_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_feeds$;

create function private.ledger_feed_with_note_text(p_shop uuid, p_items jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(jsonb_agg(enriched.item order by enriched.ord), '[]'::jsonb)
  from (
    select rows.ord,
      case
        when rows.item ->> 'kind' = 'daily_note'
          and private.daily_note_deleted(p_shop, (rows.item ->> 'operation_id')::uuid)
          then null
        when rows.item ->> 'kind' = 'daily_note' then rows.item || jsonb_build_object(
          'text', private.daily_note_display_text(p_shop, (rows.item ->> 'operation_id')::uuid),
          'edited', private.daily_note_edited_at(p_shop, (rows.item ->> 'operation_id')::uuid) is not null,
          'edited_at', case
            when private.daily_note_edited_at(p_shop, (rows.item ->> 'operation_id')::uuid) is null
              then 'null'::jsonb
            else pg_catalog.to_jsonb(private.daily_note_edited_at(
              p_shop, (rows.item ->> 'operation_id')::uuid
            ))
          end
        )
        else rows.item
      end as item
    from jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) with ordinality as rows(item, ord)
  ) as enriched
  where enriched.item is not null;
$fn$;

revoke all on function private.ledger_feed_with_note_text(uuid, jsonb)
  from public, anon, authenticated;

alter function public.get_ledger_operation_page(uuid, text, text, integer)
  rename to get_ledger_operation_page_before_note_change;
revoke all on function public.get_ledger_operation_page_before_note_change(uuid, text, text, integer)
  from public, anon, authenticated;

create function public.get_ledger_operation_page(
  p_day_id uuid,
  p_before_sequence text,
  p_after_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_result jsonb;
begin
  v_result := public.get_ledger_operation_page_before_note_change(
    p_day_id, p_before_sequence, p_after_sequence, p_limit
  );
  v_shop := private.opening_require_reader_shop();
  if v_result ? 'items' then
    v_result := jsonb_set(
      v_result,
      '{items}',
      private.ledger_feed_with_note_text(v_shop, v_result -> 'items')
    );
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_ledger_operation_page(uuid, text, text, integer)
  from public, anon;
grant execute on function public.get_ledger_operation_page(uuid, text, text, integer)
  to authenticated;

alter function public.get_ledger_date_v1(date, text, integer)
  rename to get_ledger_date_v1_before_note_change;
revoke all on function public.get_ledger_date_v1_before_note_change(date, text, integer)
  from public, anon, authenticated;

create function public.get_ledger_date_v1(
  p_business_date date,
  p_before_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_result jsonb;
begin
  v_result := public.get_ledger_date_v1_before_note_change(
    p_business_date, p_before_sequence, p_limit
  );
  v_shop := private.opening_require_reader_shop();
  if v_result #> '{feed_page,items}' is not null then
    v_result := jsonb_set(
      v_result,
      '{feed_page,items}',
      private.ledger_feed_with_note_text(v_shop, v_result #> '{feed_page,items}')
    );
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_ledger_date_v1(date, text, integer) from public, anon;
grant execute on function public.get_ledger_date_v1(date, text, integer) to authenticated;

notify pgrst, 'reload schema';
commit;

-- Daily notes and bounded ledger pagination.
-- Notes are append-only operations with no cash or gold postings.
-- Clients cannot write the note tables. Storage orphans are not deleted here.
-- Local storage tables are not created here. Hosted projects already have
-- them; local SQL applies supabase/tests/local_storage_bootstrap.sql first.
begin;

-- Add one permitted value without dropping kinds already allowed by an
-- independent migration, including inventory commands.
create function private.extend_enumerated_check(
  p_table regclass,
  p_constraint name,
  p_column text,
  p_value text
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_def text;
  v_inner text;
begin
  if p_column !~ '^[a-z_][a-z0-9_]{0,62}$'
    or p_value !~ '^[a-z][a-z0-9_]{0,62}$' then
    raise exception 'invalid_input';
  end if;
  select pg_catalog.pg_get_constraintdef(constraint_row.oid)
    into v_def
  from pg_catalog.pg_constraint as constraint_row
  where constraint_row.conrelid = p_table
    and constraint_row.conname = p_constraint
    and constraint_row.contype = 'c';
  if v_def is null or left(v_def, 6) <> 'CHECK ' then
    raise exception 'missing_constraint';
  end if;
  if position(pg_catalog.quote_literal(p_value) in v_def) > 0 then
    return;
  end if;
  v_inner := substring(v_def from 7);
  execute 'alter table ' || p_table::text
    || ' drop constraint ' || pg_catalog.quote_ident(p_constraint::text);
  execute 'alter table ' || p_table::text
    || ' add constraint ' || pg_catalog.quote_ident(p_constraint::text)
    || ' check ((' || v_inner || ') or '
    || pg_catalog.quote_ident(p_column) || ' = '
    || pg_catalog.quote_literal(p_value) || ')';
end;
$fn$;

revoke all on function private.extend_enumerated_check(regclass, name, text, text)
  from public, anon, authenticated;

select private.extend_enumerated_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  'daily_note');
select private.extend_enumerated_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  'daily_note_recorded');
select private.extend_enumerated_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  'daily_note_recorded');

create index financial_operations_shop_day_sequence_idx
  on public.financial_operations (shop_id, business_day_id, shop_sequence);

create table public.daily_note_attachments (
  operation_id uuid primary key,
  shop_id uuid not null,
  business_day_id uuid not null,
  bucket_id text not null,
  object_name text not null,
  mime_type text not null,
  byte_size bigint not null,
  client_object_id uuid not null,
  created_at timestamptz not null,
  constraint daily_note_attachments_bucket_check
    check (bucket_id = 'eldafttar-private-notes'),
  constraint daily_note_attachments_mime_check
    check (mime_type in ('image/jpeg', 'image/png', 'image/webp')),
  constraint daily_note_attachments_size_check
    check (byte_size between 1 and 5242880),
  constraint daily_note_attachments_object_name_check
    check (
      object_name = shop_id::text || '/' || business_day_id::text || '/'
        || client_object_id::text || '.'
        || case mime_type
          when 'image/jpeg' then 'jpg'
          when 'image/png' then 'png'
          else 'webp'
        end
    ),
  constraint daily_note_attachments_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint daily_note_attachments_day_fkey
    foreign key (shop_id, business_day_id)
    references public.business_days (shop_id, id),
  constraint daily_note_attachments_object_key unique (bucket_id, object_name),
  constraint daily_note_attachments_client_key unique (shop_id, client_object_id)
);

create index if not exists daily_note_attachments_shop_operation_idx
  on public.daily_note_attachments (shop_id, operation_id);
create index if not exists daily_note_attachments_shop_day_idx
  on public.daily_note_attachments (shop_id, business_day_id);

alter table public.daily_note_attachments enable row level security;
create policy daily_note_attachments_owner_read
  on public.daily_note_attachments for select to authenticated
  using (private.opening_financial_visible(shop_id));
revoke all on public.daily_note_attachments from public, anon, authenticated;
grant select on public.daily_note_attachments to authenticated;
create trigger daily_note_attachments_append_only
  before update or delete on public.daily_note_attachments
  for each row execute function private.financial_audit_events_append_only();

do $attachments_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.daily_note_attachments from service_role';
  end if;
end;
$attachments_revoke$;

-- Hosted Storage already provides storage.buckets, storage.objects, and
-- storage.foldername / filename / extension. This migration only configures
-- the private notes bucket and its policies.
insert into storage.buckets (id, name, "public", file_size_limit, allowed_mime_types)
values (
  'eldafttar-private-notes',
  'eldafttar-private-notes',
  false,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set "public" = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types,
    name = excluded.name;

-- Hosted Storage owns this table and already enables RLS. The project
-- postgres role can manage policies but cannot alter the managed table.
-- Only disposable local fixtures need RLS enabled by this migration.
do $storage_rls$
begin
  if not (select relrowsecurity from pg_catalog.pg_class
    where oid = 'storage.objects'::regclass) then
    alter table storage.objects enable row level security;
  end if;
end;
$storage_rls$;
grant usage on schema storage to authenticated;
grant select, insert on storage.objects to authenticated;
grant execute on function storage.foldername(text), storage.filename(text), storage.extension(text)
  to authenticated;

create function private.parse_optional_sequence(p_value text)
returns bigint
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_num numeric;
begin
  if p_value is null then
    return null;
  end if;
  if p_value !~ '^[1-9][0-9]{0,18}$' then
    raise exception 'invalid_input';
  end if;
  v_num := p_value::numeric;
  if v_num > 9223372036854775807 then
    raise exception 'overflow';
  end if;
  return v_num::bigint;
end;
$fn$;

create function private.note_mime_extension(p_mime text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case p_mime
    when 'image/jpeg' then 'jpg'
    when 'image/png' then 'png'
    when 'image/webp' then 'webp'
    else null
  end;
$fn$;

create function private.shop_display_zone(p_zone text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  if p_zone is not null and exists (
    select 1 from pg_catalog.pg_timezone_names as zone
    where zone.name = p_zone
  ) then
    return p_zone;
  end if;
  return 'Africa/Cairo';
end;
$fn$;

create function private.note_storage_select_allowed(p_name text)
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
  return private.opening_financial_visible(v_shop);
end;
$fn$;

create function private.note_storage_insert_allowed(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_folders text[];
  v_shop uuid;
  v_day uuid;
  v_file text;
  v_ext text;
  v_object uuid;
begin
  if auth.uid() is null or p_name is null then
    return false;
  end if;
  v_folders := storage.foldername(p_name);
  v_file := storage.filename(p_name);
  v_ext := storage.extension(p_name);
  if v_folders is null or cardinality(v_folders) <> 2 then
    return false;
  end if;
  if v_ext not in ('jpg', 'png', 'webp') then
    return false;
  end if;
  begin
    v_shop := v_folders[1]::uuid;
    v_day := v_folders[2]::uuid;
    v_object := replace(v_file, '.' || v_ext, '')::uuid;
  exception
    when others then
      return false;
  end;
  if v_file is distinct from (v_object::text || '.' || v_ext) then
    return false;
  end if;
  if p_name is distinct from (v_shop::text || '/' || v_day::text || '/' || v_file) then
    return false;
  end if;
  if not private.can_write_shop(v_shop) then
    return false;
  end if;
  return exists (
    select 1
    from public.business_days as day
    where day.shop_id = v_shop
      and day.id = v_day
      and day.status = 'open'
  );
end;
$fn$;

create function private.note_storage_metadata_allowed(p_name text, p_meta jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_ext text;
  v_size text;
  v_size_num numeric;
begin
  if p_name is null or jsonb_typeof(p_meta) is distinct from 'object' then
    return false;
  end if;
  v_ext := storage.extension(p_name);
  if private.note_mime_extension(p_meta ->> 'mimetype') is distinct from v_ext then
    return false;
  end if;
  v_size := coalesce(p_meta ->> 'size', p_meta ->> 'contentLength');
  if v_size is null or v_size !~ '^[1-9][0-9]{0,7}$' then
    return false;
  end if;
  v_size_num := v_size::numeric;
  return v_size_num <= 5242880;
end;
$fn$;

revoke all on function private.parse_optional_sequence(text) from public, anon, authenticated;
revoke all on function private.note_mime_extension(text) from public, anon, authenticated;
revoke all on function private.shop_display_zone(text) from public, anon, authenticated;
revoke all on function private.note_storage_select_allowed(text) from public, anon;
revoke all on function private.note_storage_insert_allowed(text) from public, anon;
revoke all on function private.note_storage_metadata_allowed(text, jsonb) from public, anon;
grant execute on function private.note_storage_select_allowed(text) to authenticated;
grant execute on function private.note_storage_insert_allowed(text) to authenticated;
grant execute on function private.note_storage_metadata_allowed(text, jsonb) to authenticated;

drop policy if exists eldafttar_private_notes_select on storage.objects;
drop policy if exists eldafttar_private_notes_insert on storage.objects;
create policy eldafttar_private_notes_select
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'eldafttar-private-notes'
    and private.note_storage_select_allowed(name)
  );
create policy eldafttar_private_notes_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'eldafttar-private-notes'
    and (
      (owner = auth.uid() and (owner_id is null or owner_id = auth.uid()::text))
      or (owner is null and owner_id = auth.uid()::text)
    )
    and private.note_storage_insert_allowed(name)
    and private.note_storage_metadata_allowed(name, metadata)
  );

create function private.ledger_operation_label(p_kind text)
returns text
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select case p_kind
    when 'opening_balances' then 'رصيد افتتاحي'
    when 'sale' then 'بيع'
    when 'purchase' then 'شراء'
    when 'expense' then 'مصروف'
    when 'purchase_settlement' then 'سداد شراء'
    when 'cash_transfer' then 'تحويل نقدية'
    when 'scrap_sale' then 'بيع كسر'
    when 'scrap_to_stock' then 'تحويل كسر إلى مخزون'
    when 'sale_return' then 'مرتجع بيع'
    when 'purchase_return' then 'مرتجع شراء'
    when 'close_day' then 'تقفيل اليومية'
    when 'open_day' then 'فتح اليومية'
    when 'daily_note' then 'ملاحظة يومية'
    else null
  end;
$fn$;

revoke all on function private.ledger_operation_label(text) from public, anon, authenticated;

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
  v_day uuid;
  v_before bigint;
  v_after bigint;
  v_zone text;
  v_name text;
  v_server bigint;
  v_rows jsonb;
  v_count integer;
  v_has_more boolean;
  v_next text;
  v_direction text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_before_sequence is not null and p_after_sequence is not null then
    raise exception 'invalid_input';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid_input';
  end if;
  v_before := private.parse_optional_sequence(p_before_sequence);
  v_after := private.parse_optional_sequence(p_after_sequence);
  v_shop := private.opening_require_reader_shop();
  if p_day_id is null then
    select day.id
      into v_day
    from public.business_days as day
    where day.shop_id = v_shop
    order by day.opened_at desc, day.id desc
    limit 1;
  else
    select day.id
      into v_day
    from public.business_days as day
    where day.shop_id = v_shop
      and day.id = p_day_id;
    if v_day is null then
      raise exception 'invalid_input';
    end if;
  end if;
  select private.shop_display_zone(shop.time_zone), shop.owner_display_name
    into v_zone, v_name
  from public.shops as shop
  where shop.id = v_shop;
  if v_day is null then
    return jsonb_build_object(
      'shop_id', v_shop,
      'day_id', null,
      'direction', case when v_after is null then 'desc' else 'asc' end,
      'limit', p_limit,
      'has_more', false,
      'server_sequence', '0',
      'snapshot_sequence', '0',
      'next_before_sequence', null,
      'next_after_sequence', null,
      'items', '[]'::jsonb
    );
  end if;
  select coalesce(max(operation.shop_sequence), 0)
    into v_server
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = v_day;
  -- Desc and asc are separate statements so the shop/day sequence index
  -- can stop after limit+1 rows. A CASE sort would read the whole day.
  v_direction := case when v_after is null then 'desc' else 'asc' end;
  if v_after is null then
    with fetched as materialized (
      select
        operation.id,
        operation.shop_id,
        operation.kind,
        operation.shop_sequence,
        operation.created_at
      from public.financial_operations as operation
      where operation.shop_id = v_shop
        and operation.business_day_id = v_day
        and (v_before is null or operation.shop_sequence < v_before)
      order by operation.shop_sequence desc
      limit (p_limit + 1)
    ),
    shaped as (
      select
        fetched.id,
        fetched.kind,
        fetched.shop_sequence,
        fetched.created_at,
        (
          coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
          or (
            fetched.kind = 'daily_note'
            and coalesce(length(btrim(detail.payload ->> 'text')) > 0, false)
          )
          or exists (
            select 1
            from public.daily_note_attachments as attachment
            where attachment.shop_id = fetched.shop_id
              and attachment.operation_id = fetched.id
          )
        ) as has_note
      from fetched
      left join public.financial_operation_details as detail
        on detail.shop_id = fetched.shop_id
       and detail.operation_id = fetched.id
    ),
    kept as (
      select shaped.*
      from shaped
      order by shaped.shop_sequence desc
      limit p_limit
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'kind', kept.kind,
        'label_ar', private.ledger_operation_label(kept.kind),
        'operation_id', kept.id,
        'actor_display_name', coalesce(v_name, ''),
        'occurred_at', pg_catalog.to_jsonb(kept.created_at),
        'occurred_at_cairo', to_char(
          kept.created_at at time zone 'Africa/Cairo',
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'occurred_at_shop', to_char(
          kept.created_at at time zone v_zone,
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'has_note', kept.has_note,
        'is_daily_note', kept.kind = 'daily_note',
        'is_return', kept.kind in ('sale_return', 'purchase_return'),
        'shop_sequence', kept.shop_sequence::text
      ) order by kept.shop_sequence desc), '[]'::jsonb),
      (select count(*) from fetched) > p_limit,
      (select min(edge.shop_sequence)::text from kept as edge)
      into v_rows, v_has_more, v_next
    from kept;
  else
    with fetched as materialized (
      select
        operation.id,
        operation.shop_id,
        operation.kind,
        operation.shop_sequence,
        operation.created_at
      from public.financial_operations as operation
      where operation.shop_id = v_shop
        and operation.business_day_id = v_day
        and operation.shop_sequence > v_after
      order by operation.shop_sequence asc
      limit (p_limit + 1)
    ),
    shaped as (
      select
        fetched.id,
        fetched.kind,
        fetched.shop_sequence,
        fetched.created_at,
        (
          coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
          or (
            fetched.kind = 'daily_note'
            and coalesce(length(btrim(detail.payload ->> 'text')) > 0, false)
          )
          or exists (
            select 1
            from public.daily_note_attachments as attachment
            where attachment.shop_id = fetched.shop_id
              and attachment.operation_id = fetched.id
          )
        ) as has_note
      from fetched
      left join public.financial_operation_details as detail
        on detail.shop_id = fetched.shop_id
       and detail.operation_id = fetched.id
    ),
    kept as (
      select shaped.*
      from shaped
      order by shaped.shop_sequence asc
      limit p_limit
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'kind', kept.kind,
        'label_ar', private.ledger_operation_label(kept.kind),
        'operation_id', kept.id,
        'actor_display_name', coalesce(v_name, ''),
        'occurred_at', pg_catalog.to_jsonb(kept.created_at),
        'occurred_at_cairo', to_char(
          kept.created_at at time zone 'Africa/Cairo',
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'occurred_at_shop', to_char(
          kept.created_at at time zone v_zone,
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'has_note', kept.has_note,
        'is_daily_note', kept.kind = 'daily_note',
        'is_return', kept.kind in ('sale_return', 'purchase_return'),
        'shop_sequence', kept.shop_sequence::text
      ) order by kept.shop_sequence asc), '[]'::jsonb),
      (select count(*) from fetched) > p_limit,
      (select max(edge.shop_sequence)::text from kept as edge)
      into v_rows, v_has_more, v_next
    from kept;
  end if;
  if not found then
    v_rows := '[]'::jsonb;
    v_has_more := false;
    v_next := null;
  elsif not coalesce(v_has_more, false) then
    v_next := null;
  end if;
  return jsonb_build_object(
    'shop_id', v_shop,
    'day_id', v_day,
    'direction', v_direction,
    'limit', p_limit,
    'has_more', coalesce(v_has_more, false),
    'server_sequence', v_server::text,
    'snapshot_sequence', v_server::text,
    'next_before_sequence', case when v_direction = 'desc' and v_has_more then v_next else null end,
    'next_after_sequence', case when v_direction = 'asc' and v_has_more then v_next else null end,
    'items', coalesce(v_rows, '[]'::jsonb)
  );
end;
$fn$;

create function public.post_daily_note(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_recheck uuid;
  v_actor uuid;
  v_day uuid;
  v_requested_day uuid;
  v_text text;
  v_attachment jsonb;
  v_client uuid;
  v_mime text;
  v_extension text;
  v_size_text text;
  v_size bigint;
  v_canonical jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_existing_kind text;
  v_existing_sequence bigint;
  v_existing_day uuid;
  v_path text;
  v_owner uuid;
  v_owner_id text;
  v_meta jsonb;
  v_stored_size text;
  v_at timestamptz;
  v_sequence bigint;
  v_operation uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(p_payload) as key
    where key not in ('version', 'kind', 'business_day_id', 'text', 'attachment')
  ) then
    raise exception 'invalid_input';
  end if;
  if (p_payload -> 'version') is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'daily_note'
    or jsonb_typeof(p_payload -> 'text') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'business_day_id') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  begin
    v_requested_day := (p_payload ->> 'business_day_id')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'invalid_input';
  end;
  v_text := btrim(p_payload ->> 'text');
  if char_length(v_text) > 4000 then
    raise exception 'overflow';
  end if;
  if translate(v_text, E'\n\r\t', '') ~ '[[:cntrl:]]' then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'attachment') = 'null' then
    v_attachment := null;
  elsif jsonb_typeof(p_payload -> 'attachment') = 'object' then
    if exists (
      select 1
      from jsonb_object_keys(p_payload -> 'attachment') as key
      where key not in ('client_object_id', 'mime_type', 'byte_size', 'extension')
    ) then
      raise exception 'invalid_input';
    end if;
    if jsonb_typeof(p_payload -> 'attachment' -> 'client_object_id') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'attachment' -> 'mime_type') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'attachment' -> 'byte_size') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'attachment' -> 'extension') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    begin
      v_client := (p_payload -> 'attachment' ->> 'client_object_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'invalid_input';
    end;
    v_mime := p_payload -> 'attachment' ->> 'mime_type';
    v_extension := private.note_mime_extension(v_mime);
    if v_extension is null
      or p_payload -> 'attachment' ->> 'extension' is distinct from v_extension then
      raise exception 'attachment_rejected';
    end if;
    v_size_text := p_payload -> 'attachment' ->> 'byte_size';
    v_size := private.parse_optional_sequence(v_size_text);
    if v_size is null or v_size > 5242880 then
      raise exception 'attachment_rejected';
    end if;
    v_attachment := jsonb_build_object(
      'byte_size', v_size::text,
      'client_object_id', v_client::text,
      'extension', v_extension,
      'mime_type', v_mime
    );
  else
    raise exception 'invalid_input';
  end if;
  if v_text = '' and v_attachment is null then
    raise exception 'note_empty';
  end if;
  v_canonical := jsonb_build_object(
    'attachment', coalesce(v_attachment, 'null'::jsonb),
    'business_day_id', v_requested_day::text,
    'kind', 'daily_note',
    'text', v_text,
    'version', 1
  );
  v_shop := private.opening_require_reader_shop();
  perform 1
  from public.shops as shop
  where shop.id = v_shop
  for update;
  v_recheck := private.opening_require_reader_shop();
  if v_recheck is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select request.*
    into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key
  for update;
  v_hash := extensions.digest(convert_to(v_canonical::text, 'UTF8'), 'sha256');
  if v_request.id is not null then
    select operation.kind, operation.shop_sequence, operation.business_day_id
      into v_existing_kind, v_existing_sequence, v_existing_day
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.id = v_request.operation_id;
    if v_existing_kind is distinct from 'daily_note'
      or v_existing_day is null
      or v_request.payload_canonical is distinct from v_canonical
      or v_request.payload_sha256 is distinct from v_hash then
      raise exception 'payload_mismatch';
    end if;
    return jsonb_build_object(
      'ok', true,
      'note_id', v_request.operation_id,
      'operation_id', v_request.operation_id,
      'business_day_id', v_existing_day,
      'shop_sequence', v_existing_sequence::text,
      'replayed', true
    );
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  select day.id
    into v_day
  from public.business_days as day
  where day.shop_id = v_shop
    and day.status = 'open'
  for update;
  if v_day is null then
    raise exception 'day_closed';
  end if;
  if v_day is distinct from v_requested_day then
    raise exception 'stale_day';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  if v_attachment is not null then
    v_path := v_shop::text || '/' || v_day::text || '/' || v_client::text || '.' || v_extension;
    select object.owner, object.owner_id, object.metadata
      into v_owner, v_owner_id, v_meta
    from storage.objects as object
    where object.bucket_id = 'eldafttar-private-notes'
      and object.name = v_path;
    if v_owner is null and v_owner_id is null and v_meta is null and not exists (
      select 1
      from storage.objects as object
      where object.bucket_id = 'eldafttar-private-notes'
        and object.name = v_path
    ) then
      raise exception 'attachment_missing';
    end if;
    if (
      (v_owner = v_actor and (v_owner_id is null or v_owner_id = v_actor::text))
      or (v_owner is null and v_owner_id = v_actor::text)
    ) is distinct from true then
      raise exception 'attachment_rejected';
    end if;
    if v_meta ->> 'mimetype' is distinct from v_mime then
      raise exception 'attachment_rejected';
    end if;
    v_stored_size := coalesce(v_meta ->> 'size', v_meta ->> 'contentLength');
    if v_stored_size is distinct from v_size::text then
      raise exception 'attachment_rejected';
    end if;
    if exists (
      select 1
      from public.daily_note_attachments as attachment
      where attachment.bucket_id = 'eldafttar-private-notes'
        and (
          attachment.object_name = v_path
          or attachment.client_object_id = v_client
        )
    ) then
      raise exception 'attachment_rejected';
    end if;
  end if;
  select coalesce(max(operation.shop_sequence), 0) + 1
    into v_sequence
  from public.financial_operations as operation
  where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    v_shop, v_sequence, 'daily_note', v_day, v_actor, v_at
  ) returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (
    v_operation, v_shop, v_canonical, v_at
  );
  if v_attachment is not null then
    insert into public.daily_note_attachments (
      operation_id, shop_id, business_day_id, bucket_id, object_name,
      mime_type, byte_size, client_object_id, created_at
    ) values (
      v_operation, v_shop, v_day, 'eldafttar-private-notes', v_path,
      v_mime, v_size, v_client, v_at
    );
  end if;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, 'daily_note_recorded', v_operation, v_at,
    jsonb_build_object(
      'business_day_id', v_day,
      'operation_id', v_operation,
      'has_attachment', v_attachment is not null
    )
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (
    v_shop, v_operation, 'daily_note_recorded', v_at
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (
    v_shop, p_idempotency_key, v_canonical, v_hash, v_operation, v_at
  );
  return jsonb_build_object(
    'ok', true,
    'note_id', v_operation,
    'operation_id', v_operation,
    'business_day_id', v_day,
    'shop_sequence', v_sequence::text,
    'replayed', false
  );
end;
$fn$;

create function public.get_daily_note_status(p_idempotency_key uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_operation uuid;
  v_kind text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select request.operation_id, operation.kind
    into v_operation, v_kind
  from public.financial_command_requests as request
  left join public.financial_operations as operation
    on operation.shop_id = request.shop_id
   and operation.id = request.operation_id
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key;
  if v_operation is null then
    return jsonb_build_object('status', 'absent');
  end if;
  if v_kind is distinct from 'daily_note' then
    raise exception 'payload_mismatch';
  end if;
  return jsonb_build_object(
    'status', 'completed',
    'note_id', v_operation,
    'operation_id', v_operation
  );
end;
$fn$;

create function private.daily_note_json(
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
begin
  select jsonb_build_object(
    'note_id', operation.id,
    'operation_id', operation.id,
    'shop_sequence', operation.shop_sequence::text,
    'business_day_id', operation.business_day_id,
    'text', coalesce(detail.payload ->> 'text', ''),
    'actor_display_name', coalesce(p_name, ''),
    'created_at', pg_catalog.to_jsonb(operation.created_at),
    'occurred_at_shop', to_char(
      operation.created_at at time zone p_zone,
      'YYYY-MM-DD"T"HH24:MI:SS'
    ),
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

create function public.get_daily_note(p_note_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_name text;
  v_row jsonb;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_note_id is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select private.shop_display_zone(shop.time_zone), shop.owner_display_name
    into v_zone, v_name
  from public.shops as shop
  where shop.id = v_shop;
  v_row := private.daily_note_json(p_note_id, v_shop, v_zone, v_name);
  if v_row is null then
    raise exception 'invalid_input';
  end if;
  return v_row;
end;
$fn$;

create function public.list_daily_notes(
  p_day_id uuid,
  p_before_sequence text,
  p_limit integer,
  p_query text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_day uuid;
  v_before bigint;
  v_zone text;
  v_name text;
  v_query text;
  v_server bigint;
  v_items jsonb;
  v_has_more boolean;
  v_next text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'invalid_input';
  end if;
  if p_query is not null and char_length(p_query) > 80 then
    raise exception 'invalid_input';
  end if;
  v_before := private.parse_optional_sequence(p_before_sequence);
  v_query := nullif(btrim(coalesce(p_query, '')), '');
  v_shop := private.opening_require_reader_shop();
  if p_day_id is null then
    select day.id
      into v_day
    from public.business_days as day
    where day.shop_id = v_shop
      and day.status = 'open'
    order by day.opened_at desc
    limit 1;
    if v_day is null then
      select day.id
        into v_day
      from public.business_days as day
      where day.shop_id = v_shop
      order by day.opened_at desc, day.id desc
      limit 1;
    end if;
  else
    select day.id
      into v_day
    from public.business_days as day
    where day.shop_id = v_shop
      and day.id = p_day_id;
    if v_day is null then
      raise exception 'invalid_input';
    end if;
  end if;
  select private.shop_display_zone(shop.time_zone), shop.owner_display_name
    into v_zone, v_name
  from public.shops as shop
  where shop.id = v_shop;
  if v_day is null then
    return jsonb_build_object(
      'shop_id', v_shop,
      'day_id', null,
      'limit', p_limit,
      'has_more', false,
      'server_sequence', '0',
      'snapshot_sequence', '0',
      'next_before_sequence', null,
      'items', '[]'::jsonb
    );
  end if;
  select operation.shop_sequence
    into v_server
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = v_day
    and operation.kind = 'daily_note'
  order by operation.shop_sequence desc
  limit 1;
  with matched as materialized (
    select operation.id, operation.shop_sequence
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.business_day_id = v_day
      and operation.kind = 'daily_note'
      and (v_before is null or operation.shop_sequence < v_before)
      and (
        v_query is null
        or exists (
          select 1
          from public.financial_operation_details as detail
          where detail.shop_id = operation.shop_id
            and detail.operation_id = operation.id
            and strpos(
              lower(coalesce(detail.payload ->> 'text', '')),
              lower(v_query)
            ) > 0
        )
      )
    order by operation.shop_sequence desc
    limit (p_limit + 1)
  )
  select
    coalesce((
      select jsonb_agg(private.daily_note_json(
        picked.id, v_shop, v_zone, v_name
      ) order by picked.shop_sequence desc)
      from (
        select matched.id, matched.shop_sequence
        from matched
        order by matched.shop_sequence desc
        limit p_limit
      ) as picked
    ), '[]'::jsonb),
    (select count(*) from matched) > p_limit,
    (
      select min(edge.shop_sequence)::text
      from (
        select matched.shop_sequence
        from matched
        order by matched.shop_sequence desc
        limit p_limit
      ) as edge
    )
  into v_items, v_has_more, v_next;
  if v_has_more is distinct from true then
    v_next := null;
  end if;
  return jsonb_build_object(
    'shop_id', v_shop,
    'day_id', v_day,
    'limit', p_limit,
    'has_more', coalesce(v_has_more, false),
    'server_sequence', coalesce(v_server, 0)::text,
    'snapshot_sequence', coalesce(v_server, 0)::text,
    'next_before_sequence', case when v_has_more then v_next else null end,
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$fn$;

alter function public.get_daily_ledger_v2()
  rename to get_daily_ledger_v2_before_notes_pagination;
revoke all on function public.get_daily_ledger_v2_before_notes_pagination()
  from public, anon, authenticated;

create function public.get_daily_ledger_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_base jsonb;
  v_day uuid;
  v_date date;
  v_opened timestamptz;
  v_summary jsonb;
  v_gold jsonb;
  v_page jsonb;
begin
  v_base := public.get_daily_ledger();
  if v_base ->> 'state' is distinct from 'confirmed' then
    return v_base;
  end if;
  v_shop := private.opening_require_reader_shop();
  select day.id, day.business_date, day.opened_at
    into v_day, v_date, v_opened
  from public.business_days as day
  where day.shop_id = v_shop
  order by day.opened_at desc, day.id desc
  limit 1;
  if v_day is null then
    raise exception 'invalid_input';
  end if;
  select jsonb_build_object(
    'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind in ('sale', 'scrap_sale')), 0)::text,
    'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'purchase'), 0)::text,
    'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where operation.kind = 'expense'), 0)::text,
    'sale_count', count(*) filter (where operation.kind in ('sale', 'scrap_sale')),
    'purchase_count', count(*) filter (where operation.kind = 'purchase'),
    'expense_count', count(*) filter (where operation.kind = 'expense')
  )
    into v_summary
  from public.financial_operations as operation
  left join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  where operation.shop_id = v_shop
    and operation.business_day_id = v_day;
  select coalesce(jsonb_agg(jsonb_build_object(
    'kind', bucket.kind,
    'category', bucket.category,
    'karat', bucket.karat,
    'milligrams', bucket.milligrams::text,
    'count', bucket.pieces::text
  ) order by bucket.kind, bucket.category, bucket.karat), '[]'::jsonb)
    into v_gold
  from (
    select case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end as kind,
      item.value ->> 'category' as category,
      (item.value ->> 'karat')::smallint as karat,
      sum((item.value ->> 'milligrams')::numeric) as milligrams,
      sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id
     and detail.operation_id = operation.id
    cross join lateral jsonb_array_elements(detail.payload -> 'items') as item(value)
    where operation.shop_id = v_shop
      and operation.business_day_id = v_day
      and operation.kind in ('sale', 'purchase', 'scrap_sale')
    group by case when operation.kind = 'scrap_sale' then 'sale' else operation.kind end,
      item.value ->> 'category',
      (item.value ->> 'karat')::smallint
  ) as bucket;
  v_summary := v_summary || jsonb_build_object('gold_by_bucket', v_gold);
  v_page := public.get_ledger_operation_page(v_day, null, null, 100);
  return jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(v_base, '{read_model_version}', '2'::jsonb),
        '{business_day}', jsonb_build_object(
          'id', v_day,
          'business_date', to_char(v_date, 'YYYY-MM-DD'),
          'opened_at', pg_catalog.to_jsonb(v_opened)
        )
      ),
      '{feed}', coalesce(v_page -> 'items', '[]'::jsonb)
    ),
    '{day_summary}', v_summary
  ) || jsonb_build_object(
    'feed_page', jsonb_build_object(
      'limit', v_page -> 'limit',
      'has_more', v_page -> 'has_more',
      'direction', v_page -> 'direction',
      'next_before_sequence', v_page -> 'next_before_sequence',
      'server_sequence', v_page -> 'server_sequence',
      'snapshot_sequence', v_page -> 'snapshot_sequence'
    )
  );
end;
$fn$;

revoke all on function private.daily_note_json(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke all on function public.get_ledger_operation_page(uuid, text, text, integer)
  from public, anon;
revoke all on function public.post_daily_note(uuid, jsonb) from public, anon;
revoke all on function public.get_daily_note_status(uuid) from public, anon;
revoke all on function public.get_daily_note(uuid) from public, anon;
revoke all on function public.list_daily_notes(uuid, text, integer, text)
  from public, anon;
revoke all on function public.get_daily_ledger_v2() from public, anon;

grant execute on function public.get_ledger_operation_page(uuid, text, text, integer)
  to authenticated;
grant execute on function public.post_daily_note(uuid, jsonb) to authenticated;
grant execute on function public.get_daily_note_status(uuid) to authenticated;
grant execute on function public.get_daily_note(uuid) to authenticated;
grant execute on function public.list_daily_notes(uuid, text, integer, text)
  to authenticated;
grant execute on function public.get_daily_ledger_v2() to authenticated;

commit;

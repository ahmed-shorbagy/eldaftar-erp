-- CRM-05: owner declarations per normalized number incarnation. No finance writes.
begin;
create table public.customer_number_declarations (
 id uuid primary key default pg_catalog.gen_random_uuid(),
 shop_id uuid not null, customer_id uuid not null, normalized_number text not null,
 state text not null default 'unknown' check (state in ('unknown','saved','not_saved')),
 tracking_started_at timestamptz not null, retired_at timestamptz,
 actor_user_id uuid, actor_display_name text, declared_at timestamptz,
 unique (shop_id,customer_id,id),
 foreign key (shop_id,customer_id) references public.customers(shop_id,id),
 foreign key (shop_id,actor_user_id) references public.shop_memberships(shop_id,user_id),
 check (normalized_number ~ '^\+[1-9][0-9]{6,14}$'),
 check ((actor_user_id is null and actor_display_name is null and declared_at is null and state='unknown')
     or (actor_user_id is not null and actor_display_name is not null and declared_at is not null))
);
create unique index customer_number_active_idx on public.customer_number_declarations(shop_id,customer_id,normalized_number) where retired_at is null;
create index customer_number_actor_idx on public.customer_number_declarations(shop_id,actor_user_id);
create table public.customer_number_events (
 id uuid primary key default pg_catalog.gen_random_uuid(),
 shop_id uuid not null, customer_id uuid not null, number_id uuid not null,
 actor_user_id uuid not null, actor_display_name text not null,
 created_at timestamptz not null, payload jsonb not null check (jsonb_typeof(payload)='object'),
 foreign key (shop_id,customer_id,number_id) references public.customer_number_declarations(shop_id,customer_id,id),
 foreign key (shop_id,actor_user_id) references public.shop_memberships(shop_id,user_id)
);
create index customer_number_events_customer_idx on public.customer_number_events(shop_id,customer_id,created_at desc,id desc);
create index customer_number_events_number_idx on public.customer_number_events(shop_id,customer_id,number_id);
create index customer_number_events_actor_idx on public.customer_number_events(shop_id,actor_user_id);
create trigger customer_number_events_append_only before update or delete on public.customer_number_events
 for each row execute function private.customer_reject_mutation();
alter table public.customer_number_declarations enable row level security;
alter table public.customer_number_declarations force row level security;
alter table public.customer_number_events enable row level security;
alter table public.customer_number_events force row level security;
revoke all on public.customer_number_declarations,public.customer_number_events from public,anon,authenticated;
grant select on public.customer_number_declarations,public.customer_number_events to authenticated;
create policy customer_number_owner_read on public.customer_number_declarations for select to authenticated using(private.opening_financial_visible(shop_id));
create policy customer_number_events_owner_read on public.customer_number_events for select to authenticated using(private.opening_financial_visible(shop_id));
-- Start tracking existing numbers as unknown, with no invented declaration/actor.
insert into public.customer_number_declarations(shop_id,customer_id,normalized_number,tracking_started_at)
 select shop_id,customer_id,normalized_number,pg_catalog.clock_timestamp() from public.customer_phones;
create function private.customer_reconcile_numbers(p_shop uuid,p_customer uuid,p_at timestamptz) returns void
language plpgsql security definer set search_path='' as $fn$
begin
 update public.customer_number_declarations as d set retired_at=p_at
 where d.shop_id=p_shop and d.customer_id=p_customer and d.retired_at is null
 and not exists(select 1 from public.customer_phones p where p.shop_id=p_shop and p.customer_id=p_customer and p.normalized_number=d.normalized_number);
 insert into public.customer_number_declarations(shop_id,customer_id,normalized_number,tracking_started_at)
 select p.shop_id,p.customer_id,p.normalized_number,p_at from public.customer_phones p
 where p.shop_id=p_shop and p.customer_id=p_customer
 and not exists(select 1 from public.customer_number_declarations d where d.shop_id=p_shop and d.customer_id=p_customer and d.normalized_number=p.normalized_number and d.retired_at is null);
end;
$fn$;
create or replace function private.customer_replace_phones(
  p_shop uuid, p_customer uuid, p_phones jsonb, p_at timestamptz
) returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_phone jsonb;
begin
  delete from public.customer_phones as phone
  where phone.shop_id = p_shop and phone.customer_id = p_customer;
  for v_phone in
    select entry.value from pg_catalog.jsonb_array_elements(p_phones) as entry(value)
  loop
    if exists (
      select 1 from public.customer_phones as phone
      where phone.shop_id = p_shop
        and phone.normalized_number = v_phone ->> 'normalized'
        and phone.customer_id is distinct from p_customer
    ) then
      raise exception 'phone_conflict';
    end if;
    begin
      insert into public.customer_phones (
        shop_id, customer_id, raw_number, normalized_number, is_primary, created_at
      ) values (
        p_shop, p_customer, v_phone ->> 'raw', v_phone ->> 'normalized',
        (v_phone ->> 'is_primary')::boolean, p_at
      );
    exception
      when unique_violation then
        raise exception 'phone_conflict';
    end;
  end loop;
  perform private.customer_reconcile_numbers(p_shop,p_customer,p_at);
end;
$fn$;


create function private.customer_saved_enrich(p_base jsonb,p_shop uuid,p_zone text) returns jsonb
language sql stable security definer set search_path='' as $fn$
 select p_base || pg_catalog.jsonb_build_object('saved_number_policy','owner_number_v1','phones',
 coalesce((select jsonb_agg(p.value || jsonb_build_object('saved_number',jsonb_build_object(
 'number_id',d.id,'state',d.state,'actor_user_id',d.actor_user_id,'actor_display_name',d.actor_display_name,
 'declared_at',private.customer_utc(d.declared_at),'declared_at_shop',private.customer_local(d.declared_at,p_zone))) order by p.ordinality)
 from jsonb_array_elements(p_base->'phones') with ordinality p(value,ordinality)
 join public.customer_number_declarations d on d.shop_id=p_shop and d.customer_id=(p_base->>'customer_id')::uuid
 and d.normalized_number=p.value->>'normalized' and d.retired_at is null),'[]'::jsonb));
$fn$;
create function private.customer_saved_view(p_customer public.customers,p_zone text) returns jsonb
language sql stable security definer set search_path='' as $fn$
 select private.customer_saved_enrich(private.customer_statistics_view(p_customer,p_zone),p_customer.shop_id,p_zone);
$fn$;
alter table public.customer_command_requests drop constraint customer_command_requests_kind_check;
alter table public.customer_command_requests add constraint customer_command_requests_kind_check check(command_kind in (
 'customer_create','customer_edit','customer_note','customer_status','customer_archive','customer_restore','customer_link','customer_unlink','customer_saved_number'));
create function private.customer_saved_number(p_key uuid,p_payload jsonb) returns jsonb
language plpgsql security definer set search_path='' as $fn$
declare
 v_claim jsonb; v_shop uuid; v_id uuid; v_number uuid; v_row public.customers%rowtype;
 v_decl public.customer_number_declarations%rowtype; v_state text; v_normalized text;
 v_actor uuid; v_name text; v_at timestamptz; v_result jsonb; v_event uuid;
begin
 v_claim:=private.customer_claim(p_key,p_payload,'customer_saved_number');
 if v_claim->>'continue'='false' then return v_claim->'result'; end if;
 perform private.customer_require_keys(p_payload,array['version','kind','customer_id','expected_version','number_id','normalized_number','state']);
 v_shop:=(v_claim->>'shop_id')::uuid;
 v_id:=private.customer_uuid(p_payload->'customer_id'); v_number:=private.customer_uuid(p_payload->'number_id');
 v_row:=private.customer_lock(v_shop,v_id,private.customer_expected_version(p_payload->'expected_version'));
 v_state:=p_payload->>'state'; v_normalized:=p_payload->>'normalized_number';
 if jsonb_typeof(p_payload->'state') is distinct from 'string' or v_state not in ('unknown','saved','not_saved')
 or jsonb_typeof(p_payload->'normalized_number') is distinct from 'string'
 or private.customer_normalize_phone(v_normalized) is distinct from v_normalized then raise exception 'invalid_input'; end if;
 select d.* into v_decl from public.customer_number_declarations d
 where d.shop_id=v_shop and d.customer_id=v_id and d.id=v_number and d.normalized_number=v_normalized and d.retired_at is null for update;
 if v_decl.id is null or not exists(select 1 from public.customer_phones p where p.shop_id=v_shop and p.customer_id=v_id and p.normalized_number=v_normalized)
 then raise exception 'stale_number'; end if;
 v_actor:=auth.uid(); v_name:=private.customer_actor_name(v_shop); v_at:=pg_catalog.clock_timestamp();
 update public.customer_number_declarations set state=v_state,actor_user_id=v_actor,actor_display_name=v_name,declared_at=v_at where id=v_number;
 update public.customers c set record_version=c.record_version+1,updated_at=v_at where c.id=v_id returning c.* into v_row;
 insert into public.customer_number_events(shop_id,customer_id,number_id,actor_user_id,actor_display_name,created_at,payload)
 values(v_shop,v_id,v_number,v_actor,v_name,v_at,jsonb_build_object('number_id',v_number,'normalized_number',v_normalized,'before',v_decl.state,'state',v_state,'record_version',v_row.record_version::text)) returning id into v_event;
 v_result:=private.customer_saved_enrich(private.customer_view(v_row,private.customer_zone(v_shop)),v_shop,private.customer_zone(v_shop))
 || jsonb_build_object('ok',true,'replayed',false,'command_kind','customer_saved_number','declaration_event_id',v_event);
 return private.customer_finish(v_shop,p_key,'customer_saved_number',p_payload,v_claim->>'hash',v_id,v_result);
end;
$fn$;
create function public.post_customer_saved_number_v1(p_idempotency_key uuid,p_payload jsonb) returns jsonb
language sql security definer set search_path='' as $fn$
 select private.customer_saved_number(p_idempotency_key,p_payload);
$fn$;
create function public.get_customer_command_status_v2(
  p_idempotency_key uuid, p_command_kind text, p_customer_id uuid, p_payload jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_request public.customer_command_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null
    or p_command_kind not in (
      'customer_create', 'customer_edit', 'customer_note', 'customer_status',
      'customer_archive', 'customer_restore', 'customer_link', 'customer_unlink', 'customer_saved_number'
    )
    or p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object'
    or p_payload ->> 'kind' is distinct from p_command_kind then
    raise exception 'invalid_input';
  end if;
  if p_payload ? 'customer_id' and (
    p_customer_id is null
    or p_payload ->> 'customer_id' is distinct from p_customer_id::text
  ) then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select request.* into v_request
  from public.customer_command_requests as request
  where request.shop_id = v_shop and request.idempotency_key = p_idempotency_key;
  if v_request.idempotency_key is null then
    return pg_catalog.jsonb_build_object('status', 'absent');
  end if;
  if v_request.command_kind is distinct from p_command_kind
    or v_request.payload_canonical is distinct from p_payload
    or (p_customer_id is not null and v_request.customer_id is distinct from p_customer_id) then
    raise exception 'payload_mismatch';
  end if;
  return pg_catalog.jsonb_build_object(
    'status', 'completed',
    'command_kind', v_request.command_kind,
    'customer_id', v_request.customer_id,
    'result', v_request.result
  );
end;
$fn$;

create function public.get_customer_list_v3(
  p_query text, p_sort text, p_filter text, p_limit integer, p_cursor text
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_sort text := coalesce(p_sort, 'name');
  v_filter text := coalesce(p_filter, 'active');
  v_query text := coalesce(pg_catalog.btrim(p_query), '');
  v_limit integer;
  v_like text;
  v_phone text;
  v_cursor jsonb;
  v_use boolean := false;
  v_cursor_name text;
  v_cursor_at timestamptz;
  v_cursor_id uuid;
  v_cursor_has_time boolean := false;
  v_items jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_next text;
  v_row record;
  v_loaded public.customers%rowtype;
  v_folded text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if v_sort not in ('name', 'last_operation')
    or v_filter not in ('active', 'archived', 'vip', 'open_request', 'all')
    or pg_catalog.char_length(v_query) > 80 then
    raise exception 'invalid_input';
  end if;
  v_limit := private.customer_limit(p_limit);
  v_shop := private.opening_require_reader_shop();
  v_zone := private.customer_zone(v_shop);
  v_cursor := private.customer_cursor_read(p_cursor, v_sort, 'statistics:' || v_filter, v_query);
  if nullif(btrim(p_cursor),'') is not null and v_cursor is null then raise exception 'invalid_cursor'; end if;
  if v_cursor is not null then
    v_use := true;
    v_cursor_id := (v_cursor ->> 'id')::uuid;
    v_cursor_name := v_cursor ->> 'name';
    v_cursor_has_time := coalesce((v_cursor ->> 'has_time')::boolean, false);
    if v_cursor_has_time then
      v_cursor_at := (v_cursor ->> 'at')::timestamptz;
    end if;
  end if;
  v_folded := private.customer_fold_digits(v_query);
  v_like := '%' || replace(replace(replace(v_folded, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  if v_query <> '' then
    begin
      v_phone := private.customer_normalize_phone(v_query);
    exception
      when others then
        if sqlerrm = 'invalid_phone' then
          v_phone := null;
        else
          raise;
        end if;
    end;
  end if;
  if v_sort = 'name' then
    for v_row in
      select customer.*
      from public.customers as customer
      where customer.shop_id = v_shop
        and (
          v_filter = 'all'
          or (v_filter = 'active' and customer.status = 'active')
          or (v_filter = 'archived' and customer.status = 'archived')
          or (v_filter = 'vip' and customer.is_vip)
          or (v_filter = 'open_request' and customer.has_open_request)
        )
        and (
          v_query = ''
          or private.customer_fold_digits(customer.display_name) ilike v_like escape '\'
          or exists (
            select 1 from public.customer_phones as phone
            where phone.shop_id = customer.shop_id
              and phone.customer_id = customer.id
              and (
                private.customer_fold_digits(phone.raw_number) ilike v_like escape '\'
                or phone.normalized_number ilike v_like escape '\'
                or (v_phone is not null and phone.normalized_number = v_phone)
              )
          )
        )
        and (
          not v_use
          or customer.display_name > v_cursor_name
          or (customer.display_name = v_cursor_name and customer.id > v_cursor_id)
        )
      order by customer.display_name asc, customer.id asc
      limit v_limit + 1
    loop
      v_count := v_count + 1;
      if v_count <= v_limit then
        select customer.* into v_loaded
        from public.customers as customer
        where customer.id = v_row.id;
        v_items := v_items || pg_catalog.jsonb_build_array(
          private.customer_saved_view(v_loaded, v_zone)
        );
        v_next := private.customer_cursor_pack(
          v_sort, 'statistics:' || v_filter, v_query, v_loaded.display_name, null, v_loaded.id
        );
      end if;
    end loop;
  else
    for v_row in
      select customer.*, activity.last_operation_at
      from public.customers as customer
      left join lateral (
        select max(operation.created_at) as last_operation_at
        from private.customer_statistics_activity(customer.shop_id, customer.id) operation
      ) as activity on true
      where customer.shop_id = v_shop
        and (
          v_filter = 'all'
          or (v_filter = 'active' and customer.status = 'active')
          or (v_filter = 'archived' and customer.status = 'archived')
          or (v_filter = 'vip' and customer.is_vip)
          or (v_filter = 'open_request' and customer.has_open_request)
        )
        and (
          v_query = ''
          or private.customer_fold_digits(customer.display_name) ilike v_like escape '\'
          or exists (
            select 1 from public.customer_phones as phone
            where phone.shop_id = customer.shop_id
              and phone.customer_id = customer.id
              and (
                private.customer_fold_digits(phone.raw_number) ilike v_like escape '\'
                or phone.normalized_number ilike v_like escape '\'
                or (v_phone is not null and phone.normalized_number = v_phone)
              )
          )
        )
        and (
          not v_use
          or (
            v_cursor_has_time
            and (
              activity.last_operation_at < v_cursor_at
              or (activity.last_operation_at = v_cursor_at and customer.id < v_cursor_id)
              or activity.last_operation_at is null
            )
          )
          or (
            v_use and not v_cursor_has_time
            and activity.last_operation_at is null
            and customer.id < v_cursor_id
          )
        )
      order by activity.last_operation_at desc nulls last, customer.id desc
      limit v_limit + 1
    loop
      v_count := v_count + 1;
      if v_count <= v_limit then
        select customer.* into v_loaded
        from public.customers as customer
        where customer.id = v_row.id;
        v_items := v_items || pg_catalog.jsonb_build_array(
          private.customer_saved_view(v_loaded, v_zone)
        );
        v_next := private.customer_cursor_pack(
          v_sort, 'statistics:' || v_filter, v_query, null, v_row.last_operation_at, v_loaded.id
        );
      end if;
    end loop;
  end if;
  if v_count <= v_limit then
    v_next := null;
  end if;
  return pg_catalog.jsonb_build_object(
    'items', v_items,
    'next_cursor', v_next,
    'time_zone', v_zone,
    'locale', 'ar',
    'sort', v_sort,
    'filter', v_filter
  );
end;
$fn$;

create function public.get_customer_v3(
  p_customer_id uuid,
  p_notes_limit integer, p_notes_cursor text,
  p_history_limit integer, p_history_cursor text,
  p_links_limit integer, p_links_cursor text
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_zone text;
  v_row public.customers%rowtype;
  v_notes_limit integer;
  v_history_limit integer;
  v_links_limit integer;
  v_notes_cursor jsonb;
  v_history_cursor jsonb;
  v_links_cursor jsonb;
  v_notes jsonb := '[]'::jsonb;
  v_history jsonb := '[]'::jsonb;
  v_links jsonb := '[]'::jsonb;
  v_count integer;
  v_next text;
  v_note public.customer_notes%rowtype;
  v_event record;
  v_link record;
  v_op public.financial_operations%rowtype;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_customer_id is null then
    raise exception 'invalid_input';
  end if;
  v_notes_limit := private.customer_limit(p_notes_limit);
  v_history_limit := private.customer_limit(p_history_limit);
  v_links_limit := private.customer_limit(p_links_limit);
  v_shop := private.opening_require_reader_shop();
  v_zone := private.customer_zone(v_shop);
  select customer.* into v_row
  from public.customers as customer
  where customer.shop_id = v_shop and customer.id = p_customer_id;
  if v_row.id is null then
    raise exception 'not_found';
  end if;
  v_notes_cursor := private.customer_page_cursor(p_notes_cursor, 'notes:' || p_customer_id::text);
  v_history_cursor := private.customer_page_cursor(p_history_cursor, 'history3:' || p_customer_id::text);
  v_links_cursor := private.customer_page_cursor(p_links_cursor, 'links:' || p_customer_id::text);
  if (nullif(btrim(p_notes_cursor),'') is not null and v_notes_cursor is null) or (nullif(btrim(p_history_cursor),'') is not null and v_history_cursor is null) or (nullif(btrim(p_links_cursor),'') is not null and v_links_cursor is null) then raise exception 'invalid_cursor'; end if;
  v_count := 0;
  v_next := null;
  for v_note in
    select note.*
    from public.customer_notes as note
    where note.shop_id = v_shop and note.customer_id = p_customer_id
      and (
        v_notes_cursor is null
        or note.created_at < (v_notes_cursor ->> 'at')::timestamptz
        or (
          note.created_at = (v_notes_cursor ->> 'at')::timestamptz
          and note.id < (v_notes_cursor ->> 'id')::uuid
        )
      )
    order by note.created_at desc, note.id desc
    limit v_notes_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_notes_limit then
      v_notes := v_notes || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'note_id', v_note.id,
        'body', v_note.body,
        'created_at', private.customer_utc(v_note.created_at),
        'created_at_shop', private.customer_local(v_note.created_at, v_zone),
        'actor_user_id', v_note.actor_user_id,
        'actor_display_name', v_note.actor_display_name
      ));
      v_next := private.customer_page_pack('notes:' || p_customer_id::text, v_note.created_at, v_note.id);
    end if;
  end loop;
  if v_count <= v_notes_limit then
    v_next := null;
  end if;
  v_notes := pg_catalog.jsonb_build_object('items', v_notes, 'next_cursor', v_next);
  v_count := 0;
  v_next := null;
  for v_event in
    select event.*
    from (
      select e.id,e.shop_id,e.customer_id,e.event_type,e.actor_user_id,e.actor_display_name,e.created_at,e.payload from public.customer_events e
      union all
      select e.id,e.shop_id,e.customer_id,'saved_number_changed'::text,e.actor_user_id,e.actor_display_name,e.created_at,e.payload from public.customer_number_events e
    ) as event
    where event.shop_id = v_shop and event.customer_id = p_customer_id
      and (
        v_history_cursor is null
        or event.created_at < (v_history_cursor ->> 'at')::timestamptz
        or (
          event.created_at = (v_history_cursor ->> 'at')::timestamptz
          and event.id < (v_history_cursor ->> 'id')::uuid
        )
      )
    order by event.created_at desc, event.id desc
    limit v_history_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_history_limit then
      v_history := v_history || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'event_id', v_event.id,
        'event_type', v_event.event_type,
        'created_at', private.customer_utc(v_event.created_at),
        'created_at_shop', private.customer_local(v_event.created_at, v_zone),
        'actor_user_id', v_event.actor_user_id,
        'actor_display_name', v_event.actor_display_name,
        'payload', v_event.payload
      ));
      v_next := private.customer_page_pack('history3:' || p_customer_id::text, v_event.created_at, v_event.id);
    end if;
  end loop;
  if v_count <= v_history_limit then
    v_next := null;
  end if;
  v_history := pg_catalog.jsonb_build_object('items', v_history, 'next_cursor', v_next);
  v_count := 0;
  v_next := null;
  for v_link in
    select link.*, operation.created_at as operation_created_at
    from public.customer_operation_links as link
    join public.financial_operations as operation
      on operation.shop_id = link.shop_id
     and operation.id = link.operation_id
    where link.shop_id = v_shop and link.customer_id = p_customer_id
      and (
        v_links_cursor is null
        or operation.created_at < (v_links_cursor ->> 'at')::timestamptz
        or (
          operation.created_at = (v_links_cursor ->> 'at')::timestamptz
          and link.id < (v_links_cursor ->> 'id')::uuid
        )
      )
    order by operation.created_at desc, link.id desc
    limit v_links_limit + 1
  loop
    v_count := v_count + 1;
    if v_count <= v_links_limit then
      select operation.* into v_op
      from public.financial_operations as operation
      where operation.shop_id = v_shop and operation.id = v_link.operation_id;
      v_links := v_links || pg_catalog.jsonb_build_array(
        private.customer_operation_public(v_op, v_zone)
        || pg_catalog.jsonb_build_object(
          'link_id', v_link.id,
          'link_status', v_link.status,
          'linked_at', private.customer_utc(v_link.linked_at),
          'linked_at_shop', private.customer_local(v_link.linked_at, v_zone),
          'unlinked_at', private.customer_utc(v_link.unlinked_at),
          'unlinked_at_shop', private.customer_local(v_link.unlinked_at, v_zone)
        )
      );
      v_next := private.customer_page_pack('links:' || p_customer_id::text, v_link.operation_created_at, v_link.id);
    end if;
  end loop;
  if v_count <= v_links_limit then
    v_next := null;
  end if;
  return private.customer_saved_view(v_row, v_zone) || pg_catalog.jsonb_build_object(
    'notes', v_notes,
    'history', v_history,
    'links', pg_catalog.jsonb_build_object('items', v_links, 'next_cursor', v_next)
  );
end;
$fn$;

revoke all on function private.customer_reconcile_numbers(uuid,uuid,timestamptz) from public,anon,authenticated;
revoke all on function private.customer_saved_enrich(jsonb,uuid,text) from public,anon,authenticated;
revoke all on function private.customer_saved_view(public.customers,text) from public,anon,authenticated;
revoke all on function private.customer_saved_number(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.post_customer_saved_number_v1(uuid,jsonb) from public,anon;
grant execute on function public.post_customer_saved_number_v1(uuid,jsonb) to authenticated;
revoke all on function public.get_customer_command_status_v2(uuid,text,uuid,jsonb) from public,anon;
grant execute on function public.get_customer_command_status_v2(uuid,text,uuid,jsonb) to authenticated;
revoke all on function public.get_customer_list_v3(text,text,text,integer,text) from public,anon;
grant execute on function public.get_customer_list_v3(text,text,text,integer,text) to authenticated;
revoke all on function public.get_customer_v3(uuid,integer,text,integer,text,integer,text) from public,anon;
grant execute on function public.get_customer_v3(uuid,integer,text,integer,text,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;

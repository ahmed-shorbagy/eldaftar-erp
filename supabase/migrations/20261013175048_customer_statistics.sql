-- CRM-02 live net grams; explicit associations; no financial writes or v1 changes.
begin;
create function private.customer_statistics_activity(p_shop uuid, p_customer uuid)
returns setof public.financial_operations
language sql stable security definer set search_path = '' as $fn$
 with originals as materialized (
  select operation.* from public.customer_operation_links link
  join public.financial_operations operation on operation.shop_id=link.shop_id and operation.id=link.operation_id
  where link.shop_id=p_shop and link.customer_id=p_customer and link.status='active'
   and operation.kind in ('sale','purchase')
   and exists(select 1 from public.financial_operation_details d where d.shop_id=p_shop and d.operation_id=operation.id)
   and exists(select 1 from public.financial_audit_events a where a.shop_id=p_shop and a.operation_id=operation.id and a.action=operation.kind||'_confirmed')
 )
 select * from originals
 union all
 select operation.* from originals original
 join public.financial_operation_details detail on detail.shop_id=p_shop
  and detail.payload ? 'original_operation_id'
  and detail.payload->>'original_operation_id'=original.id::text
 join public.financial_operations operation on operation.shop_id=p_shop and operation.id=detail.operation_id and operation.kind=original.kind||'_return'
 where exists(select 1 from public.financial_audit_events a where a.shop_id=p_shop and a.operation_id=operation.id and a.action=operation.kind||'_confirmed');
$fn$;
create function private.customer_statistics(p_shop uuid,p_customer uuid,p_zone text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_weights jsonb; v_bought numeric; v_sold numeric; v_last public.financial_operations%rowtype;
begin
 -- Operation counts are independent of line expansion and returned weights.
 with activity as materialized (select * from private.customer_statistics_activity(p_shop,p_customer)),
 quantities as (
  select operation.kind,(item.value->>'karat')::smallint karat,private.line_milligrams(item.value)::numeric milligrams
  from activity operation join public.financial_operation_details detail on detail.shop_id=p_shop and detail.operation_id=operation.id
  cross join lateral jsonb_array_elements(detail.payload->'items') item(value) where operation.kind in ('sale','purchase')
  union all
  select case operation.kind when 'sale_return' then 'sale' else 'purchase' end,line.karat,-line.milligrams::numeric
  from activity operation join public.financial_operation_details detail on detail.shop_id=p_shop and detail.operation_id=operation.id
  cross join lateral private.return_movement_lines(p_shop,detail.payload) line where operation.kind in ('sale_return','purchase_return')
 ), totals as (
  select karat,coalesce(sum(milligrams) filter(where kind='sale'),0) bought,coalesce(sum(milligrams) filter(where kind='purchase'),0) sold
  from quantities group by karat
 )
 select jsonb_agg(jsonb_build_object('karat',karat.value,'bought_milligrams',coalesce(totals.bought,0)::text,'sold_milligrams',coalesce(totals.sold,0)::text) order by karat.value),
  (select count(*) from activity where kind='sale'),(select count(*) from activity where kind='purchase')
 into v_weights,v_bought,v_sold from unnest(array[14,18,21,22,24]) karat(value) left join totals on totals.karat=karat.value;
 if exists(select 1 from jsonb_array_elements(v_weights) weight where (weight->>'bought_milligrams')::numeric<0 or (weight->>'sold_milligrams')::numeric<0) then
  raise exception 'inconsistent_customer_statistics';
 end if;
 select operation.* into v_last from private.customer_statistics_activity(p_shop,p_customer) operation
 order by operation.created_at desc,operation.shop_sequence desc,operation.id desc limit 1;
 return jsonb_build_object('version',1,'policy','net_explicit_links_v1','weights',v_weights,'bought_count',v_bought::text,'sold_count',v_sold::text,
  'last_operation',case when v_last.id is null then null else private.customer_operation_public(v_last,p_zone) end);
end;
$fn$;
create function private.customer_statistics_view(p_customer public.customers,p_zone text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_statistics jsonb;
begin
 v_statistics:=private.customer_statistics(p_customer.shop_id,p_customer.id,p_zone);
 return private.customer_view(p_customer,p_zone)||jsonb_build_object('statistics',v_statistics,
  'last_operation_at',v_statistics->'last_operation'->'operation_created_at','last_operation_at_shop',v_statistics->'last_operation'->'operation_created_at_shop');
end;
$fn$;
create index customer_statistics_return_reference_idx on public.financial_operation_details (shop_id,(payload->>'original_operation_id'))
 where payload ? 'original_operation_id';
create function public.get_customer_list_v2(
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
          private.customer_statistics_view(v_loaded, v_zone)
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
          private.customer_statistics_view(v_loaded, v_zone)
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

create function public.get_customer_v2(
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
  v_event public.customer_events%rowtype;
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
  v_history_cursor := private.customer_page_cursor(p_history_cursor, 'history:' || p_customer_id::text);
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
    from public.customer_events as event
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
      v_next := private.customer_page_pack('history:' || p_customer_id::text, v_event.created_at, v_event.id);
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
  return private.customer_statistics_view(v_row, v_zone) || pg_catalog.jsonb_build_object(
    'notes', v_notes,
    'history', v_history,
    'links', pg_catalog.jsonb_build_object('items', v_links, 'next_cursor', v_next)
  );
end;
$fn$;

revoke all on function private.customer_statistics_activity(uuid,uuid) from public,anon,authenticated;
revoke all on function private.customer_statistics(uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.customer_statistics_view(public.customers,text) from public,anon,authenticated;
revoke all on function public.get_customer_list_v2(text,text,text,integer,text) from public,anon;
revoke all on function public.get_customer_v2(uuid,integer,text,integer,text,integer,text) from public,anon;
grant execute on function public.get_customer_list_v2(text,text,text,integer,text) to authenticated;
grant execute on function public.get_customer_v2(uuid,integer,text,integer,text,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;

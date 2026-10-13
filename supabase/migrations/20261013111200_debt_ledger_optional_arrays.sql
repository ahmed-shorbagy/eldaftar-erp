-- Preserve immutable debt command payloads with explicit JSON null arrays.
-- Both ledger pagination directions must treat absent optional arrays as empty.
begin;

create or replace function public.get_ledger_operation_page(
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
        detail.payload as summary_payload,
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
        'shop_sequence', kept.shop_sequence::text,
        'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),
        'item_summary', (select left(string_agg(nullif(item ->> 'item_name', ''), '، ' order by ord), 200)
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) with ordinality as items(item, ord)),
        'piece_count', (select sum((item ->> 'count')::numeric)::text
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item
          where item ->> 'count' ~ '^[0-9]+$'),
        'total_pounds', case when kept.summary_payload ->> 'total_piastres' ~ '^[0-9]+$'
          then trunc((kept.summary_payload ->> 'total_piastres')::numeric / 100)::text || '.' ||
            lpad(mod((kept.summary_payload ->> 'total_piastres')::numeric, 100)::text, 2, '0') else null end,
        'weight_grams', (select case when sum((item ->> 'milligrams')::numeric) is null then null
          else trunc(sum((item ->> 'milligrams')::numeric) / 1000)::text || '.' ||
            lpad(mod(sum((item ->> 'milligrams')::numeric), 1000)::text, 3, '0') end
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item),
        'karat', (select case when count(distinct item ->> 'karat') = 1
          then min((item ->> 'karat')::integer) else null end
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item),
        'payment_label', (select string_agg(case tender ->> 'method'
          when 'cash' then 'كاش' when 'instant_transfer' then 'إنستا باي'
          when 'wallet' then 'محفظة' when 'card' then 'فيزا' end, ' + ' order by tender ->> 'method')
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'tenders', 'null'::jsonb), '[]'::jsonb)) tender)
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
        detail.payload as summary_payload,
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
        'shop_sequence', kept.shop_sequence::text,
        'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),
        'item_summary', (select left(string_agg(nullif(item ->> 'item_name', ''), '، ' order by ord), 200)
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) with ordinality as items(item, ord)),
        'piece_count', (select sum((item ->> 'count')::numeric)::text
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item
          where item ->> 'count' ~ '^[0-9]+$'),
        'total_pounds', case when kept.summary_payload ->> 'total_piastres' ~ '^[0-9]+$'
          then trunc((kept.summary_payload ->> 'total_piastres')::numeric / 100)::text || '.' ||
            lpad(mod((kept.summary_payload ->> 'total_piastres')::numeric, 100)::text, 2, '0') else null end,
        'weight_grams', (select case when sum((item ->> 'milligrams')::numeric) is null then null
          else trunc(sum((item ->> 'milligrams')::numeric) / 1000)::text || '.' ||
            lpad(mod(sum((item ->> 'milligrams')::numeric), 1000)::text, 3, '0') end
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item),
        'karat', (select case when count(distinct item ->> 'karat') = 1
          then min((item ->> 'karat')::integer) else null end
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'items', 'null'::jsonb), '[]'::jsonb)) item),
        'payment_label', (select string_agg(case tender ->> 'method'
          when 'cash' then 'كاش' when 'instant_transfer' then 'إنستا باي'
          when 'wallet' then 'محفظة' when 'card' then 'فيزا' end, ' + ' order by tender ->> 'method')
          from jsonb_array_elements(coalesce(nullif(kept.summary_payload -> 'tenders', 'null'::jsonb), '[]'::jsonb)) tender)
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
notify pgrst, 'reload schema';
commit;

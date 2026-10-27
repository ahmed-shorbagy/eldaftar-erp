-- Shop analytics: week / calendar month / calendar year + owner-only staff weights.
-- Reuses daily report accounting; report_pdf R2 kind unchanged.
begin;

create function public.get_financial_period_analytics_v1(
  p_period text,
  p_anchor date default null
) returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_name text; v_zone text; v_server_date date;
  v_anchor date; v_start date; v_end date; v_first date; v_last date;
  v_day record; v_report jsonb; v_days jsonb := '[]'::jsonb;
  v_summary jsonb; v_gold jsonb; v_actors jsonb := '[]'::jsonb;
  v_content jsonb; v_open boolean := false; v_is_owner boolean;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_period is null or p_period not in ('week', 'month', 'year') then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission('reports');
  v_shop := private.opening_require_reader_shop();
  v_is_owner := private.is_shop_owner(v_shop);
  select name, private.shop_display_zone(time_zone) into v_name, v_zone
    from public.shops where id = v_shop;
  v_server_date := (now() at time zone v_zone)::date;
  select min(business_date), greatest(v_server_date, max(business_date))
    into v_first, v_last
    from public.business_days where shop_id = v_shop;
  if p_anchor is null then
    select business_date into v_anchor from public.business_days
      where shop_id = v_shop
      order by (status = 'open') desc, opened_at desc, id desc
      limit 1;
    v_anchor := coalesce(v_anchor, v_server_date);
  else
    v_anchor := p_anchor;
  end if;
  if v_anchor > v_last or v_anchor < date '0001-01-01' then
    raise exception 'invalid_date';
  end if;

  if p_period = 'week' then
    v_end := v_anchor;
    v_start := v_end - 6;
  elsif p_period = 'month' then
    v_start := date_trunc('month', v_anchor::timestamp)::date;
    v_end := (date_trunc('month', v_anchor::timestamp) + interval '1 month - 1 day')::date;
  else
    v_start := make_date(extract(year from v_anchor)::int, 1, 1);
    v_end := make_date(extract(year from v_anchor)::int, 12, 31);
  end if;

  for v_day in
    select id, status from public.business_days
    where shop_id = v_shop and business_date between v_start and v_end
    order by business_date, opened_at, id
  loop
    v_report := public.get_financial_day_report_v1_before_staff(v_day.id)
      - 'generated_at_utc' - 'generated_at_shop';
    v_days := v_days || jsonb_build_array(v_report);
    v_open := v_open or v_day.status = 'open';
  end loop;

  select jsonb_object_agg(metric.key, coalesce((
    select sum((d.value #>> array['summary', metric.key])::numeric)
    from jsonb_array_elements(v_days) d(value)), 0)::text)
  into v_summary
  from unnest(array[
    'sales', 'sale_returns', 'net_sales', 'purchases', 'purchase_returns',
    'net_purchases', 'expenses', 'net_cash', 'opening_cash', 'sale_count',
    'purchase_count', 'expense_count', 'return_count', 'operation_count',
    'audit_row_count'
  ]) metric(key);

  select jsonb_agg(jsonb_build_object(
    'karat', k,
    'sold', coalesce((
      select sum((g.value->>'sold')::numeric)
      from jsonb_array_elements(v_days) d(value)
      cross join lateral jsonb_array_elements(d.value->'gold') g(value)
      where (g.value->>'karat')::integer = k), 0)::text,
    'bought', coalesce((
      select sum((g.value->>'bought')::numeric)
      from jsonb_array_elements(v_days) d(value)
      cross join lateral jsonb_array_elements(d.value->'gold') g(value)
      where (g.value->>'karat')::integer = k), 0)::text
  ) order by k)
  into v_gold from unnest(array[14, 18, 21, 22, 24]) k;

  if v_is_owner then
    with day_ids as (
      select id from public.business_days
      where shop_id = v_shop and business_date between v_start and v_end
    ), operations as (
      select o.id, o.kind, o.actor_user_id,
        private.ledger_trade_hidden(v_shop, o.id) as hidden,
        coalesce(d.payload, '{}'::jsonb) as payload
      from public.financial_operations o
      left join public.financial_operation_details d
        on d.shop_id = o.shop_id and d.operation_id = o.id
      where o.shop_id = v_shop
        and o.business_day_id in (select id from day_ids)
        and o.kind in ('sale', 'scrap_sale', 'purchase', 'sale_return', 'purchase_return')
    ), lines as (
      select o.actor_user_id, (i.value->>'karat')::integer as karat,
        (i.value->>'milligrams')::numeric as mg, o.kind, o.hidden
      from operations o
      cross join lateral jsonb_array_elements(
        coalesce(nullif(o.payload->'items', 'null'::jsonb), '[]'::jsonb)
      ) i(value)
      where o.kind in ('sale', 'scrap_sale', 'purchase')
      union all
      select o.actor_user_id, l.karat, l.milligrams::numeric, o.kind, o.hidden
      from operations o
      cross join lateral private.return_movement_lines(v_shop, o.payload) l
      where o.kind in ('sale_return', 'purchase_return')
    ), gold as (
      select actor_user_id, karat,
        case when hidden then 0
          when kind in ('sale', 'scrap_sale') then mg
          when kind = 'sale_return' then -mg else 0 end as sold,
        case when hidden then 0
          when kind = 'purchase' then mg
          when kind = 'purchase_return' then -mg else 0 end as bought
      from lines
    ), by_actor as (
      select actor_user_id,
        coalesce(jsonb_agg(jsonb_build_object(
          'karat', karat,
          'sold', sold::text,
          'bought', bought::text
        ) order by karat), '[]'::jsonb) as gold,
        sum(sold) as sold_total,
        sum(bought) as bought_total
      from (
        select actor_user_id, karat, sum(sold) as sold, sum(bought) as bought
        from gold
        group by actor_user_id, karat
      ) g
      group by actor_user_id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'actor_user_id', a.actor_user_id,
      'display_name', coalesce(
        nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
        case when m.role = 'owner' then s.owner_display_name else null end,
        'مستخدم'
      ),
      'role', coalesce(m.role, 'unknown'),
      'gold', a.gold,
      'sold_total', a.sold_total::text,
      'bought_total', a.bought_total::text
    ) order by coalesce(
      nullif(btrim(u.raw_user_meta_data ->> 'display_name'), ''),
      case when m.role = 'owner' then s.owner_display_name else null end,
      'مستخدم'
    )), '[]'::jsonb)
    into v_actors
    from by_actor a
    left join auth.users u on u.id = a.actor_user_id
    left join public.shop_memberships m
      on m.shop_id = v_shop and m.user_id = a.actor_user_id
    join public.shops s on s.id = v_shop;
  end if;

  v_content := jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'shop_name', v_name,
    'time_zone', v_zone,
    'period', p_period,
    'anchor_date', v_anchor::text,
    'start_date', v_start::text,
    'end_date', v_end::text,
    'contains_open_day', v_open,
    'is_owner', v_is_owner,
    'summary', v_summary,
    'gold', v_gold,
    'actors', v_actors,
    'day_count', jsonb_array_length(v_days)
  );
  return v_content || jsonb_build_object(
    'fingerprint', encode(
      extensions.digest(convert_to(v_content::text, 'UTF8'), 'sha256'), 'hex'
    ),
    'server_date', v_server_date::text,
    'first_business_date', v_first::text,
    'last_selectable_date', v_last::text,
    'generated_at_utc', now(),
    'generated_at_shop', to_char(now() at time zone v_zone, 'YYYY-MM-DD HH24:MI:SS')
  );
end;
$fn$;

revoke all on function public.get_financial_period_analytics_v1(text, date)
  from public, anon;
grant execute on function public.get_financial_period_analytics_v1(text, date)
  to authenticated;

create function public.confirm_financial_period_analytics_pdf_v1(
  p_period text,
  p_anchor date,
  p_fingerprint text,
  p_object_key text
) returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_report jsonb;
  v_row public.r2_media_objects%rowtype;
begin
  if p_period is null or p_period not in ('week', 'month', 'year')
    or p_anchor is null or p_fingerprint is null or p_object_key is null then
    raise exception 'invalid_input';
  end if;
  v_report := public.get_financial_period_analytics_v1(p_period, p_anchor);
  if p_fingerprint is distinct from v_report->>'fingerprint' then
    raise exception 'stale_report';
  end if;
  select * into v_row from public.r2_media_objects
  where object_key = p_object_key
    and shop_id = (v_report->>'shop_id')::uuid
    and uploaded_by = auth.uid()
    and kind = 'report_pdf';
  if not found then raise exception 'media_rejected'; end if;
  return jsonb_build_object(
    'object_key', v_row.object_key,
    'sha256', v_row.sha256,
    'byte_size', v_row.byte_size
  );
end;
$fn$;

revoke all on function public.confirm_financial_period_analytics_pdf_v1(text, date, text, text)
  from public, anon;
grant execute on function public.confirm_financial_period_analytics_pdf_v1(text, date, text, text)
  to authenticated;

notify pgrst, 'reload schema';
commit;

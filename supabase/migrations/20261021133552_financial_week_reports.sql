-- Seven financial dates ending on the selected date, in one stable snapshot.
-- Reuse the daily accounting contract; no new posting or media store.
begin;

create function public.get_financial_week_report_v1(p_end_date date default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare
  v_shop uuid; v_name text; v_zone text; v_server_date date;
  v_end date; v_start date; v_first date; v_last date; v_day record; v_report jsonb;
  v_days jsonb := '[]'::jsonb; v_summary jsonb; v_gold jsonb; v_groups jsonb;
  v_content jsonb; v_open boolean := false;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  select name,private.shop_display_zone(time_zone) into v_name,v_zone
    from public.shops where id=v_shop;
  v_server_date := (now() at time zone v_zone)::date;
  select min(business_date),greatest(v_server_date,max(business_date)) into v_first,v_last
    from public.business_days where shop_id=v_shop;
  if p_end_date is null then
    select business_date into v_end from public.business_days where shop_id=v_shop
      order by (status='open') desc,opened_at desc,id desc limit 1;
    v_end := coalesce(v_end,v_server_date);
  else v_end := p_end_date;
  end if;
  -- An existing financial date remains selectable after a time-zone change,
  -- even if that date is now ahead of the shop's current calendar date.
  if v_end>v_last or v_end<date '0001-01-07' then raise exception 'invalid_date'; end if;
  v_start := v_end-6;
  for v_day in select id,status from public.business_days
    where shop_id=v_shop and business_date between v_start and v_end
    order by business_date,opened_at,id
  loop
    -- Generation time belongs to the weekly envelope, not its content hash.
    v_report := public.get_financial_day_report_v1(v_day.id)
      -'generated_at_utc'-'generated_at_shop';
    v_days := v_days || jsonb_build_array(v_report);
    v_open := v_open or v_day.status='open';
  end loop;

  select jsonb_object_agg(metric.key,coalesce((
    select sum((d.value #>> array['summary',metric.key])::numeric)
    from jsonb_array_elements(v_days) d(value)),0)::text)
  into v_summary
  from unnest(array['sales','sale_returns','net_sales','purchases','purchase_returns',
    'net_purchases','expenses','net_cash','opening_cash','sale_count','purchase_count',
    'expense_count','return_count','operation_count','audit_row_count']) metric(key);

  select jsonb_agg(jsonb_build_object('karat',k,'sold',coalesce((
    select sum((g.value->>'sold')::numeric) from jsonb_array_elements(v_days) d(value)
    cross join lateral jsonb_array_elements(d.value->'gold') g(value)
    where (g.value->>'karat')::integer=k),0)::text,'bought',coalesce((
    select sum((g.value->>'bought')::numeric) from jsonb_array_elements(v_days) d(value)
    cross join lateral jsonb_array_elements(d.value->'gold') g(value)
    where (g.value->>'karat')::integer=k),0)::text) order by k)
  into v_gold from unnest(array[14,18,21,22,24]) k;

  with lines as (
    select t.value->>'id' operation_id,i.value->>'category' category,
      (i.value->>'karat')::integer karat,(i.value->>'sold')::numeric sold,
      (i.value->>'bought')::numeric bought
    from jsonb_array_elements(v_days) d(value)
    cross join lateral jsonb_array_elements(d.value->'transactions') t(value)
    cross join lateral jsonb_array_elements(t.value->'items') i(value)
    where (i.value->>'sold')::numeric<>0 or (i.value->>'bought')::numeric<>0
  ), grouped as (
    select category,karat,sum(sold) sold,sum(bought) bought,
      count(distinct operation_id) filter(where sold<>0) sale_movements,
      count(distinct operation_id) filter(where bought<>0) purchase_movements
    from lines group by category,karat
  )
  select coalesce(jsonb_agg(jsonb_build_object('category',category,'karat',karat,
    'sold',sold::text,'bought',bought::text,'sale_movements',sale_movements::text,
    'purchase_movements',purchase_movements::text) order by category,karat),'[]'::jsonb)
  into v_groups from grouped;

  v_content := jsonb_build_object('version',1,'shop_id',v_shop,'shop_name',v_name,
    'time_zone',v_zone,'start_date',v_start::text,'end_date',v_end::text,
    'contains_open_day',v_open,'summary',v_summary,'gold',v_gold,
    'groups',v_groups,'days',v_days);
  return v_content || jsonb_build_object(
    'fingerprint',encode(extensions.digest(convert_to(v_content::text,'UTF8'),'sha256'),'hex'),
    'server_date',v_server_date::text,'first_business_date',v_first::text,'last_selectable_date',v_last::text,
    'generated_at_utc',now(),'generated_at_shop',to_char(now() at time zone v_zone,'YYYY-MM-DD HH24:MI:SS'));
end;
$fn$;
revoke all on function public.get_financial_week_report_v1(date) from public,anon;
grant execute on function public.get_financial_week_report_v1(date) to authenticated;

create function public.confirm_financial_week_pdf_v1(p_end_date date,p_fingerprint text,p_object_key text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_report jsonb; v_row public.r2_media_objects%rowtype;
begin
  if p_end_date is null then raise exception 'invalid_date'; end if;
  v_report := public.get_financial_week_report_v1(p_end_date);
  if p_fingerprint is distinct from v_report->>'fingerprint' then raise exception 'stale_report'; end if;
  select * into v_row from public.r2_media_objects where object_key=p_object_key
    and shop_id=(v_report->>'shop_id')::uuid and uploaded_by=auth.uid() and kind='report_pdf';
  if not found then raise exception 'media_rejected'; end if;
  return jsonb_build_object('object_key',v_row.object_key,'sha256',v_row.sha256,'byte_size',v_row.byte_size);
end;
$fn$;
revoke all on function public.confirm_financial_week_pdf_v1(date,text,text) from public,anon;
grant execute on function public.confirm_financial_week_pdf_v1(date,text,text) to authenticated;
notify pgrst,'reload schema';
commit;

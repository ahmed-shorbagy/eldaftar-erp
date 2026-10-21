-- One owner-scoped MVCC snapshot; no pagination or client-side financial sums.
begin;

create function public.list_financial_report_days_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_shop uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  return jsonb_build_object('shop_id', v_shop, 'days', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'date', d.business_date::text,
      'status', d.status, 'opened_at_shop', to_char(d.opened_at at time zone
        private.shop_display_zone(s.time_zone), 'YYYY-MM-DD HH24:MI:SS'))
      order by d.opened_at desc, d.id desc)
    from public.business_days d join public.shops s on s.id = d.shop_id
    where d.shop_id = v_shop), '[]'::jsonb));
end;
$fn$;

create function public.get_financial_day_report_v1(p_day_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_shop uuid; v_day public.business_days%rowtype; v_zone text; v_name text;
  v_rows jsonb; v_summary jsonb; v_gold jsonb; v_content jsonb;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  select * into v_day from public.business_days where shop_id = v_shop and id = p_day_id;
  if not found then raise exception 'not_found'; end if;
  select name, private.shop_display_zone(time_zone) into v_name, v_zone
    from public.shops where id = v_shop;

  with operations as materialized (
    select o.*, coalesce(d.payload, '{}'::jsonb) payload,
      private.ledger_trade_hidden(v_shop, o.id) hidden,
      coalesce((select c.action from public.ledger_trade_changes c
        where c.shop_id = v_shop and c.source_operation_id = o.id),
        case when exists(select 1 from public.ledger_trade_changes c
          where c.shop_id = v_shop and c.reversal_operation_id = o.id)
          then 'internal_reversal' else 'confirmed' end) state,
      (select c.source_operation_id from public.ledger_trade_changes c
        where c.shop_id = v_shop and (c.reversal_operation_id = o.id
          or c.replacement_operation_id = o.id)) change_source
    from public.financial_operations o left join public.financial_operation_details d
      on d.shop_id = o.shop_id and d.operation_id = o.id
    where o.shop_id = v_shop and o.business_day_id = p_day_id
      and o.kind <> 'daily_note'
  ), amounts as materialized (
    select o.*,
      case when hidden then 0 when kind in ('sale', 'scrap_sale')
        then coalesce((payload->>'total_piastres')::numeric,0)
        when kind = 'sale_return' then -private.return_consideration(payload) else 0 end sale,
      case when hidden then 0 when kind = 'purchase'
        then coalesce((payload->>'total_piastres')::numeric,0)
        when kind = 'purchase_return' then -private.return_consideration(payload) else 0 end purchase,
      case when kind = 'expense' then (payload->>'total_piastres')::numeric else 0 end expense,
      coalesce((select sum(p.amount)::numeric from public.journal_postings p
        join public.ledger_accounts a on a.shop_id = p.shop_id and a.id = p.account_id
        where p.shop_id = v_shop and p.operation_id = o.id and a.account_kind = 'cash_method'),0) cash,
      coalesce((select jsonb_agg(jsonb_build_object('method', t.method_code, 'amount', t.amount::text)
        order by t.method_code) from (
        select a.method_code, sum(p.amount)::numeric amount from public.journal_postings p
        join public.ledger_accounts a on a.shop_id = p.shop_id and a.id = p.account_id
        where p.shop_id = v_shop and p.operation_id = o.id and a.account_kind = 'cash_method'
        group by a.method_code) t), '[]'::jsonb) methods
    from operations o
  ), lines as materialized (
    select o.id, o.kind, o.hidden, i.value->>'item_name' name,
      i.value->>'category' category, (i.value->>'karat')::integer karat,
      (i.value->>'milligrams')::numeric mg
    from operations o cross join lateral jsonb_array_elements(
      coalesce(nullif(o.payload->'items', 'null'::jsonb), '[]'::jsonb)) i(value)
    where o.kind in ('sale','scrap_sale','purchase')
    union all
    select o.id, o.kind, o.hidden, l.item_name, l.category, l.karat, l.milligrams::numeric
    from operations o cross join lateral private.return_movement_lines(v_shop, o.payload) l
    where o.kind in ('sale_return','purchase_return')
  ), gold as materialized (
    select id, name, category, karat, mg,
      case when hidden then 0 when kind in ('sale','scrap_sale') then mg
        when kind = 'sale_return' then -mg else 0 end sold,
      case when hidden then 0 when kind = 'purchase' then mg
        when kind = 'purchase_return' then -mg else 0 end bought
    from lines
  )
  select
    coalesce((select jsonb_agg(jsonb_build_object(
      'id', a.id, 'sequence', a.shop_sequence::text, 'kind', a.kind,
      'label', private.ledger_operation_label(a.kind), 'state', a.state,
      'source_id', coalesce(a.change_source::text, a.payload->>'original_operation_id'),
      'at_utc', a.created_at, 'at_shop', to_char(a.created_at at time zone v_zone,'YYYY-MM-DD HH24:MI:SS'),
      'description', coalesce(nullif(a.payload->>'description',''),nullif(a.payload->>'note',''),''),
      'original_total', coalesce(a.payload->>'total_piastres','0'),
      'sale', a.sale::text, 'purchase', a.purchase::text, 'expense', a.expense::text,
      'cash', (case when a.kind = 'opening_balances' then 0 else a.cash end)::text,
      'opening_cash', (case when a.kind = 'opening_balances' then a.cash else 0 end)::text,
      'methods', a.methods,
      'items', coalesce((select jsonb_agg(jsonb_build_object('name',coalesce(g.name,''),
        'category',g.category,'karat',g.karat,'milligrams',g.mg::text,
        'sold',g.sold::text,'bought',g.bought::text) order by g.karat,g.category,g.name)
        from gold g where g.id = a.id),'[]'::jsonb),
      'inventory', coalesce((select jsonb_agg(jsonb_build_object('karat',t.karat,'milligrams',t.mg::text)
        order by t.karat) from (select ac.karat,sum(p.amount)::numeric mg
        from public.journal_postings p join public.ledger_accounts ac
          on ac.shop_id=p.shop_id and ac.id=p.account_id
        where p.shop_id=v_shop and p.operation_id=a.id
          and ac.account_kind in ('saleable_metal','scrap_metal') group by ac.karat) t),'[]'::jsonb)
    ) order by a.shop_sequence) from amounts a),'[]'::jsonb),
    (select jsonb_build_object(
      'sales',coalesce(sum(sale) filter(where sale>0),0)::text,
      'sale_returns',(-coalesce(sum(sale) filter(where sale<0),0))::text,
      'net_sales',coalesce(sum(sale),0)::text,
      'purchases',coalesce(sum(purchase) filter(where purchase>0),0)::text,
      'purchase_returns',(-coalesce(sum(purchase) filter(where purchase<0),0))::text,
      'net_purchases',coalesce(sum(purchase),0)::text,
      'expenses',coalesce(sum(expense),0)::text,
      'net_cash',coalesce(sum(cash) filter(where kind<>'opening_balances'),0)::text,
      'opening_cash',coalesce(sum(cash) filter(where kind='opening_balances'),0)::text,
      'sale_count',count(*) filter(where not hidden and kind in ('sale','scrap_sale'))::text,
      'purchase_count',count(*) filter(where not hidden and kind='purchase')::text,
      'expense_count',count(*) filter(where kind='expense')::text,
      'return_count',count(*) filter(where not hidden and kind in ('sale_return','purchase_return'))::text,
      'operation_count',count(*) filter(where not hidden and kind not in ('opening_balances','close_day'))::text,
      'audit_row_count',count(*)::text) from amounts),
    (select jsonb_agg(jsonb_build_object('karat',k,'sold',coalesce((select sum(sold) from gold where karat=k),0)::text,
      'bought',coalesce((select sum(bought) from gold where karat=k),0)::text) order by k)
      from unnest(array[14,18,21,22,24]) k)
  into v_rows, v_summary, v_gold;
  v_content := jsonb_build_object('version',1,'shop_id',v_shop,'shop_name',v_name,'time_zone',v_zone,
    'day_id',v_day.id,'date',v_day.business_date::text,'status',v_day.status,
    'opened_at_shop',to_char(v_day.opened_at at time zone v_zone,'YYYY-MM-DD HH24:MI:SS'),
    'summary',v_summary,'gold',v_gold,'transactions',v_rows);
  return v_content || jsonb_build_object('fingerprint',encode(extensions.digest(convert_to(v_content::text,'UTF8'),'sha256'),'hex'),
    'generated_at_utc',now(),'generated_at_shop',to_char(now() at time zone v_zone,'YYYY-MM-DD HH24:MI:SS'));
end;
$fn$;
revoke all on function public.list_financial_report_days_v1() from public, anon;
revoke all on function public.get_financial_day_report_v1(uuid) from public, anon;
grant execute on function public.list_financial_report_days_v1(), public.get_financial_day_report_v1(uuid) to authenticated;
-- Reports are documents in R2; only verified metadata enters Postgres.
alter table public.r2_media_objects drop constraint r2_media_objects_kind_check,
  drop constraint r2_media_objects_mime_check, drop constraint r2_media_objects_size_check,
  drop constraint r2_media_objects_dimensions_check, drop constraint r2_media_objects_key_check;
alter table public.r2_media_objects add constraint r2_media_objects_kind_check
  check(kind in ('shop_image','invoice_logo','note_image','report_pdf')),
  add constraint r2_media_objects_mime_check check(mime in ('image/jpeg','image/png','image/webp','application/pdf')),
  add constraint r2_media_objects_size_check check(
    (kind='report_pdf' and byte_size between 1 and 20971520)
    or (kind='note_image' and byte_size between 1 and 5242880)
    or (kind in ('shop_image','invoice_logo') and byte_size between 1 and 2097152)),
  add constraint r2_media_objects_dimensions_check check(
    (kind in ('note_image','report_pdf') and width is null and height is null)
    or (kind in ('shop_image','invoice_logo') and width between 1 and 2048 and height between 1 and 2048)),
  add constraint r2_media_objects_key_check check(
    (kind='report_pdf' and mime='application/pdf' and object_key='report-pdf/'||shop_id::text||'/'||sha256||'.pdf')
    or (kind in ('shop_image','invoice_logo') and mime in ('image/jpeg','image/png') and object_key=
      case kind when 'shop_image' then 'shop-image/' else 'invoice-logo/' end||shop_id::text||'/'||sha256||'.'||
      case mime when 'image/png' then 'png' else 'jpg' end)
    or (kind='note_image' and mime in ('image/jpeg','image/png','image/webp') and object_key ~ (
      '^note-image/'||shop_id::text||'/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.]'||
      case mime when 'image/png' then 'png' when 'image/webp' then 'webp' else 'jpg' end||'$')));

create function public.record_report_pdf_object_v1(p_actor uuid,p_shop uuid,p_object_key text,p_byte_size bigint,p_sha256 text)
returns jsonb language plpgsql volatile security definer set search_path='' as $fn$
declare v_row public.r2_media_objects%rowtype; v_replay boolean;
begin
  if p_actor is null or not exists(select 1 from public.shop_memberships
    where shop_id=p_shop and user_id=p_actor and role='owner' and revoked_at is null)
    then raise exception 'forbidden'; end if;
  -- Read/export remains available to an expired authorized owner.
  if p_sha256 is null or p_sha256 !~ '^[0-9a-f]{64}$' or p_byte_size is null
    or p_byte_size not between 1 and 20971520 or p_object_key is distinct from
      'report-pdf/'||p_shop::text||'/'||p_sha256||'.pdf' then raise exception 'media_rejected'; end if;
  insert into public.r2_media_objects(object_key,shop_id,kind,mime,byte_size,sha256,uploaded_by,verified_at)
    values(p_object_key,p_shop,'report_pdf','application/pdf',p_byte_size,p_sha256,p_actor,clock_timestamp())
    on conflict(object_key) do nothing;
  v_replay := not found;
  select * into strict v_row from public.r2_media_objects where object_key=p_object_key;
  if v_row.shop_id<>p_shop or v_row.uploaded_by<>p_actor or v_row.kind<>'report_pdf'
    or v_row.sha256<>p_sha256 or v_row.byte_size<>p_byte_size then raise exception 'media_mismatch'; end if;
  return jsonb_build_object('object_key',v_row.object_key,'sha256',v_row.sha256,'byte_size',v_row.byte_size,'replayed',v_replay);
end;
$fn$;
revoke all on function public.record_report_pdf_object_v1(uuid,uuid,text,bigint,text) from public,anon,authenticated;
grant execute on function public.record_report_pdf_object_v1(uuid,uuid,text,bigint,text) to service_role;

create function public.confirm_financial_day_pdf_v1(p_day_id uuid,p_fingerprint text,p_object_key text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_report jsonb; v_row public.r2_media_objects%rowtype;
begin
  v_report := public.get_financial_day_report_v1(p_day_id);
  if p_fingerprint is distinct from v_report->>'fingerprint' then raise exception 'stale_report'; end if;
  select * into v_row from public.r2_media_objects where object_key=p_object_key
    and shop_id=(v_report->>'shop_id')::uuid and uploaded_by=auth.uid() and kind='report_pdf';
  if not found then raise exception 'media_rejected'; end if;
  return jsonb_build_object('object_key',v_row.object_key,'sha256',v_row.sha256,'byte_size',v_row.byte_size);
end;
$fn$;
revoke all on function public.confirm_financial_day_pdf_v1(uuid,text,text) from public,anon;
grant execute on function public.confirm_financial_day_pdf_v1(uuid,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;

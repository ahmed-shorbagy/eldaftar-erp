-- U18 (device pass 2026-11-11): «الدفاتر» showed only when a closed day was
-- opened. The day list now also carries the server close time in the shop's
-- display zone (`closed_at_shop`, null while open). Older builds ignore the
-- extra key; the staff wrapper (reports grant) is unchanged.
begin;

create or replace function public.list_financial_report_days_v1_before_staff()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_shop uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.opening_require_reader_shop();
  return jsonb_build_object('shop_id', v_shop, 'days', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'date', d.business_date::text,
      'status', d.status,
      'opened_at_shop', to_char(d.opened_at at time zone
        private.shop_display_zone(s.time_zone), 'YYYY-MM-DD HH24:MI:SS'),
      'closed_at_shop', case when d.closed_at is null then null else to_char(
        d.closed_at at time zone private.shop_display_zone(s.time_zone),
        'YYYY-MM-DD HH24:MI:SS') end)
      order by d.opened_at desc, d.id desc)
    from public.business_days d join public.shops s on s.id = d.shop_id
    where d.shop_id = v_shop), '[]'::jsonb));
end;
$fn$;

revoke all on function public.list_financial_report_days_v1_before_staff()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;

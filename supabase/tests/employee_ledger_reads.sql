-- ADR 0033 employee ledger reads (2026-11-15). Rolled back. Each call starts
-- like a fresh request (the declared grant is cleared first).
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, raw_user_meta_data, created_at, updated_at)
values
  ('a6600000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'employee-reads-owner@example.test', false, '{}'::jsonb, now(), now()),
  ('a6600000-0000-4000-8000-000000000002', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'employee-reads-partner@example.test', false,
   '{"display_name":"شريك القراءة"}'::jsonb, now(), now()),
  ('a6600000-0000-4000-8000-000000000003', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'employee-reads-seller@example.test', false,
   '{"display_name":"بائع القراءة"}'::jsonb, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('a6600000-0000-4000-8000-000000000010', 'متجر قراءات الموظف', 'مالك القراءات', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('a6600000-0000-4000-8000-000000000010', 'a6600000-0000-4000-8000-000000000001', 'owner'),
  ('a6600000-0000-4000-8000-000000000010', 'a6600000-0000-4000-8000-000000000002', 'partner'),
  ('a6600000-0000-4000-8000-000000000010', 'a6600000-0000-4000-8000-000000000003', 'employee');
insert into public.shop_member_grants (shop_id, user_id, permission, granted_by)
select 'a6600000-0000-4000-8000-000000000010', member.user_id, member.permission,
  'a6600000-0000-4000-8000-000000000001'
from (values
  ('a6600000-0000-4000-8000-000000000002'::uuid, 'sale'),
  ('a6600000-0000-4000-8000-000000000002'::uuid, 'reports'),
  ('a6600000-0000-4000-8000-000000000003'::uuid, 'sale'),
  ('a6600000-0000-4000-8000-000000000003'::uuid, 'reports')
) as member(user_id, permission);
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('a6600000-0000-4000-8000-000000000010', now() - interval '1 day', now() + interval '30 days');

create function pg_temp.call_as(p_user uuid, p_sql text)
returns text language plpgsql security invoker set search_path = '' as $fn$
declare
  v_result text;
begin
  perform pg_catalog.set_config('request.jwt.claim.sub', p_user::text, true);
  perform pg_catalog.set_config('request.jwt.claim.session_id', '', true);
  perform pg_catalog.set_config('app.required_shop_permission', '', true);
  execute p_sql into v_result;
  return coalesce(v_result, 'null');
exception when others then
  return 'ERROR ' || sqlerrm;
end;
$fn$;

create function pg_temp.sale(p_karat int, p_mg text, p_piastres text)
returns text language sql immutable as $fn$
  select 'select public.post_daily_ledger_trade(gen_random_uuid(), '
    || pg_catalog.quote_literal(pg_catalog.jsonb_build_object(
      'version', 1, 'kind', 'sale', 'total_piastres', p_piastres,
      'tenders', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('method', 'cash', 'piastres', p_piastres)),
      'items', pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'category', 'worked_jewelry', 'karat', p_karat, 'milligrams', p_mg,
        'count', '1', 'item_name', 'خاتم', 'line_price_piastres', null)),
      'description', '', 'customer_name', '', 'customer_phone', '', 'note', ''
    )::text) || '::jsonb)::text';
$fn$;

set local role authenticated;

do $suite$
declare
  v_owner uuid := 'a6600000-0000-4000-8000-000000000001';
  v_partner uuid := 'a6600000-0000-4000-8000-000000000002';
  v_seller uuid := 'a6600000-0000-4000-8000-000000000003';
  v_r text;
  v_home jsonb;
  v_day uuid;
  v_seller_sale uuid;
begin
  v_r := pg_temp.call_as(v_owner, 'select public.confirm_opening_balances(gen_random_uuid(), '
    || quote_literal('{"version":1,"cash":{"cash":"5000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"40000","count":"8"},{"category":"worked_jewelry","karat":18,"milligrams":"20000","count":"5"}],"scrap":[]}')
    || '::jsonb)::text');
  if v_r like 'ERROR%' then raise exception 'opening_failed %', v_r; end if;
  v_day := (v_r::jsonb ->> 'business_day_id')::uuid;

  v_r := pg_temp.call_as(v_owner, pg_temp.sale(21, '5000', '2000000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'owner_sale %', v_r; end if;
  v_r := pg_temp.call_as(v_seller, pg_temp.sale(18, '4000', '1000000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'seller_sale %', v_r; end if;
  v_seller_sale := (v_r::jsonb ->> 'operation_id')::uuid;
  v_r := pg_temp.call_as(v_partner, pg_temp.sale(18, '2000', '500000'));
  if (v_r::jsonb ->> 'ok') is distinct from 'true' then raise exception 'partner_sale %', v_r; end if;

  -- Employee home: the current read model, own operations and totals only.
  v_r := pg_temp.call_as(v_seller, 'select public.get_daily_ledger_home_v2()::text');
  if v_r like 'ERROR%' then raise exception 'seller_home %', v_r; end if;
  v_home := v_r::jsonb;
  if (v_home ->> 'read_model_version') is distinct from '3'
    or v_home ? 'employee_ledger' or v_home ? 'balances_hidden'
    or (v_home ->> 'can_confirm') is distinct from 'false'
    or v_home -> 'business_day' is null
    or v_home -> 'journal_context' is null then
    raise exception 'seller_home_shape %', left(v_r, 600);
  end if;
  if jsonb_array_length(v_home -> 'feed') <> 1
    or (v_home -> 'feed' -> 0 ->> 'operation_id')::uuid is distinct from v_seller_sale
    or (v_home -> 'feed' -> 0 ->> 'actor_display_name') is distinct from 'بائع القراءة' then
    raise exception 'seller_home_feed %', v_home -> 'feed';
  end if;
  if (v_home #>> '{day_summary,sale_piastres}') is distinct from '1000000'
    or (v_home #>> '{day_summary,sale_count}') is distinct from '1' then
    raise exception 'seller_home_summary %', v_home -> 'day_summary';
  end if;
  if jsonb_array_length(v_home -> 'cash') <> 4
    or exists (select 1 from jsonb_array_elements(v_home -> 'cash') as line
               where line ->> 'piastres' <> '0' or line ->> 'label_ar' is null)
    or v_home -> 'stock' <> '[]'::jsonb or v_home -> 'scrap' <> '[]'::jsonb then
    raise exception 'seller_home_balances % % %', v_home -> 'cash', v_home -> 'stock', v_home -> 'scrap';
  end if;

  -- Employee date and closed-day reads: own rows and own summary.
  v_r := pg_temp.call_as(v_seller, 'select public.get_ledger_date_v2(null, null, 100)::text');
  if v_r like 'ERROR%'
    or jsonb_array_length(v_r::jsonb #> '{feed_page,items}') <> 1
    or (v_r::jsonb #>> '{day_summary,sale_piastres}') is distinct from '1000000' then
    raise exception 'seller_date %', left(v_r, 600);
  end if;
  v_r := pg_temp.call_as(v_seller, format('select public.get_ledger_day_v1(%L::uuid, null, 100)::text', v_day));
  if v_r like 'ERROR%'
    or jsonb_array_length(v_r::jsonb #> '{feed_page,items}') <> 1
    or (v_r::jsonb #>> '{day_summary,sale_piastres}') is distinct from '1000000' then
    raise exception 'seller_closed_day %', left(v_r, 600);
  end if;

  -- Owner and partner: shop-wide reads, each row named by its recorder.
  v_r := pg_temp.call_as(v_owner, 'select public.get_daily_ledger_home_v2()::text');
  v_home := v_r::jsonb;
  if (v_home #>> '{day_summary,sale_piastres}') is distinct from '3500000'
    or (select pg_catalog.array_agg(item ->> 'actor_display_name' order by (item ->> 'shop_sequence')::bigint)
        from jsonb_array_elements(v_home -> 'feed') as item
        where item ->> 'kind' = 'sale')
       is distinct from array['مالك القراءات', 'بائع القراءة', 'شريك القراءة'] then
    raise exception 'owner_home %', left(v_r, 800);
  end if;
  if not exists (select 1 from jsonb_array_elements(v_home -> 'cash') as line where line ->> 'piastres' <> '0') then
    raise exception 'owner_cash_hidden %', v_home -> 'cash';
  end if;
  v_r := pg_temp.call_as(v_partner, 'select public.get_daily_ledger_home_v2()::text');
  if (v_r::jsonb #>> '{day_summary,sale_piastres}') is distinct from '3500000' then
    raise exception 'partner_home %', left(v_r, 400);
  end if;
  v_r := pg_temp.call_as(v_owner, format('select public.get_daily_ledger_operation(%L::uuid)::text', v_seller_sale));
  if (v_r::jsonb ->> 'actor_display_name') is distinct from 'بائع القراءة' then
    raise exception 'operation_actor %', left(v_r, 300);
  end if;

  -- No leaked grant after the employee home read.
  v_r := pg_temp.call_as(v_seller, 'select public.get_daily_ledger_home_v2()::text');
  if coalesce(current_setting('app.required_shop_permission', true), '') <> '' then
    raise exception 'grant_leaked_after_home %', current_setting('app.required_shop_permission', true);
  end if;
end;
$suite$;

rollback;

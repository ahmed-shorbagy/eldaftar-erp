-- A new shop that confirms zero opening balances must get a readable home.
-- Owner report of 2026-11-17: the app refused this read because the home feed
-- names the opening row `opening_balances`, not `opening_balances_confirmed`.
-- This pins what the home read returns so the client contract cannot drift.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('c1100000-0000-4000-8000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'opening-home-owner@example.test', false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone) values
  ('c2200000-0000-4000-8000-000000000001', 'متجر الافتتاح', 'مالك الافتتاح', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('c2200000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000001', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('c2200000-0000-4000-8000-000000000001', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'c1100000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.session_id', '', true);

do $opening$
declare
  v_before jsonb;
  v_confirm jsonb;
  v_home jsonb;
  v_legacy jsonb;
  v_row jsonb;
begin
  v_before := public.get_daily_ledger_home_v2();
  if v_before ->> 'state' is distinct from 'uninitialized'
    or v_before ->> 'can_confirm' is distinct from 'true' then
    raise exception 'new_shop_not_uninitialized %', jsonb_build_object(
      'state', v_before -> 'state', 'can_confirm', v_before -> 'can_confirm');
  end if;

  v_confirm := public.confirm_opening_balances(
    'c3300000-0000-4000-8000-000000000001',
    '{"version":1,"cash":{"cash":"0","instant_transfer":"0","wallet":"0","card":"0"},"stock":[],"scrap":[]}'::jsonb
  );
  if v_confirm ->> 'ok' is distinct from 'true' then
    raise exception 'zero_opening_rejected %', v_confirm;
  end if;

  v_home := public.get_daily_ledger_home_v2();
  if v_home ->> 'state' is distinct from 'confirmed'
    or v_home ->> 'can_confirm' is distinct from 'false'
    or v_home ->> 'day_reset' is distinct from 'false'
    or v_home #>> '{business_day,id}' is distinct from v_confirm ->> 'business_day_id'
    or jsonb_typeof(v_home -> 'feed_page') is distinct from 'object'
    or jsonb_array_length(v_home -> 'feed') <> 1 then
    raise exception 'home_after_zero_opening_wrong %', jsonb_build_object(
      'state', v_home -> 'state',
      'can_confirm', v_home -> 'can_confirm',
      'day_reset', v_home -> 'day_reset',
      'business_day', v_home -> 'business_day',
      'feed_page', v_home -> 'feed_page',
      'feed', v_home -> 'feed');
  end if;

  v_row := v_home #> '{feed,0}';
  if v_row ->> 'kind' is distinct from 'opening_balances'
    or v_row ->> 'operation_id' is distinct from v_confirm ->> 'operation_id'
    or v_row ->> 'label_ar' is distinct from 'رصيد افتتاحي' then
    raise exception 'home_opening_row_wrong %', v_row;
  end if;

  -- Installed older builds read the legacy function and its own kind.
  v_legacy := public.get_daily_ledger();
  if v_legacy #>> '{feed,0,kind}' is distinct from 'opening_balances_confirmed'
    or v_legacy #>> '{feed,0,operation_id}' is distinct from v_confirm ->> 'operation_id' then
    raise exception 'legacy_opening_row_wrong %', v_legacy -> 'feed';
  end if;
end;
$opening$;

rollback;

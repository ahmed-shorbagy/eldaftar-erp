-- Trade edit with the stored tender label snapshot (20261111090000).
-- The detail trigger stores label_ar in each tender; the edit screen starts
-- from that payload. Review and post must accept it, ignore the client label,
-- and keep the server snapshot. One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values
  ('16161616-1616-4161-8161-161616161616', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tender-label-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b1616161-6161-4161-8161-161616161616', 'متجر تسمية الدفع', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b1616161-6161-4161-8161-161616161616', '16161616-1616-4161-8161-161616161616', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b1616161-6161-4161-8161-161616161616', now() - interval '1 day', now() + interval '30 days');

do $priv$
begin
  if not has_function_privilege(
    'authenticated', 'public.review_ledger_trade_change_v1(uuid,text,jsonb)', 'execute'
  ) or not has_function_privilege(
    'authenticated',
    'public.post_ledger_trade_change_v1(uuid,uuid,text,jsonb,uuid,bigint,text,text)',
    'execute'
  ) then
    raise exception 'trade_change_execute_missing';
  end if;
  if has_function_privilege(
    'authenticated',
    'public.review_ledger_trade_change_v1_before_tender_label(uuid,text,jsonb)',
    'execute'
  ) or has_function_privilege(
    'authenticated',
    'public.post_ledger_trade_change_v1_before_tender_label(uuid,uuid,text,jsonb,uuid,bigint,text,text)',
    'execute'
  ) or has_function_privilege(
    'authenticated', 'private.trade_replacement_without_tender_labels(jsonb)', 'execute'
  ) then
    raise exception 'before_or_private_still_granted';
  end if;
  if private.trade_replacement_without_tender_labels(
    '{"tenders":[{"method":"cash","label_ar":"x","piastres":"1"},{"method":"card","piastres":"2"}],"note":"n"}'::jsonb
  ) is distinct from
    '{"tenders":[{"method":"cash","piastres":"1"},{"method":"card","piastres":"2"}],"note":"n"}'::jsonb
  or private.trade_replacement_without_tender_labels(null) is not null
  or private.trade_replacement_without_tender_labels('[]'::jsonb) is distinct from '[]'::jsonb then
    raise exception 'normalizer_wrong';
  end if;
end;
$priv$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '16161616-1616-4161-8161-161616161616', true);

do $test$
declare
  v_shop uuid := 'b1616161-6161-4161-8161-161616161616';
  v_result jsonb;
  v_sale uuid;
  v_stored jsonb;
  v_review jsonb;
  v_replacement jsonb;
  v_posted jsonb;
  v_new_payload jsonb;
  v_cash bigint;
  v_card bigint;
begin
  v_result := public.confirm_opening_balances(
    'a1616161-6161-4161-8161-161616161616',
    '{"version":1,"cash":{"cash":"10000000","instant_transfer":"0","wallet":"0","card":"0"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"50000","count":"5"}],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'opening failed %', v_result;
  end if;

  v_result := public.post_daily_ledger_trade(
    'c1616161-6161-4161-8161-161616161601',
    '{"version":1,"kind":"sale","total_piastres":"3000000","tenders":[{"method":"cash","piastres":"2000000"},{"method":"card","piastres":"1000000"}],"items":[{"category":"worked_jewelry","karat":21,"milligrams":"10000","count":"1","item_name":"خواتم","line_price_piastres":null}],"description":"","customer_name":"","customer_phone":"","note":""}'::jsonb
  );
  v_sale := (v_result ->> 'operation_id')::uuid;

  -- The stored payload carries the label snapshot.
  v_stored := (public.review_ledger_trade_change_v1(v_sale, 'delete', null))
    -> 'source' -> 'payload';
  if not (v_stored -> 'tenders' -> 0 ? 'label_ar') then
    raise exception 'stored tenders have no label snapshot %', v_stored;
  end if;

  -- The edit screen prepares from the stored payload: accepted.
  v_review := public.review_ledger_trade_change_v1(v_sale, 'edit', v_stored);
  if v_review ->> 'action' is distinct from 'edit' then
    raise exception 'prepare edit failed %', v_review;
  end if;

  -- A real edit that still carries labels (and a forged one): accepted, and
  -- the server snapshot wins.
  v_replacement := jsonb_set(
    jsonb_set(v_stored, '{items,0,milligrams}', '"9000"'),
    '{tenders,0,label_ar}', '"مزور"'
  );
  v_review := public.review_ledger_trade_change_v1(v_sale, 'edit', v_replacement);
  if (v_review -> 'effects' -> 'stock' -> 0 ->> 'delta_milligrams') is distinct from '1000' then
    raise exception 'edit effect %', v_review -> 'effects';
  end if;
  v_posted := public.post_ledger_trade_change_v1(
    'c1616161-6161-4161-8161-161616161610', v_sale, 'edit', v_replacement,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token'
  );
  if v_posted ->> 'ok' is distinct from 'true' or v_posted ->> 'replayed' is distinct from 'false' then
    raise exception 'edit post failed %', v_posted;
  end if;
  -- Idempotent replay with the same labeled body.
  if (public.post_ledger_trade_change_v1(
    'c1616161-6161-4161-8161-161616161610', v_sale, 'edit', v_replacement,
    (v_review ->> 'expected_day_id')::uuid,
    (v_review ->> 'expected_day_version')::bigint,
    v_review ->> 'source_sha256',
    v_review ->> 'review_token'
  ) ->> 'replayed') is distinct from 'true' then
    raise exception 'edit replay failed';
  end if;

  select detail.payload into v_new_payload
  from public.financial_operation_details as detail
  where detail.shop_id = v_shop
    and detail.operation_id = (v_posted ->> 'replacement_operation_id')::uuid;
  if v_new_payload -> 'items' -> 0 ->> 'milligrams' is distinct from '9000'
    or v_new_payload -> 'tenders' -> 0 ->> 'label_ar' is null
    or v_new_payload -> 'tenders' -> 0 ->> 'label_ar' = 'مزور' then
    raise exception 'replacement payload %', v_new_payload;
  end if;

  v_cash := (select amount from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'cash');
  v_card := (select amount from public.ledger_account_balances
    where shop_id = v_shop and account_kind = 'cash_method' and method_code = 'card');
  if v_cash is distinct from 12000000 or v_card is distinct from 1000000 then
    raise exception 'balances after edit cash % card %', v_cash, v_card;
  end if;
end;
$test$;

select 'TRADE_CHANGE_TENDER_LABEL_PASSED' as result;
rollback;

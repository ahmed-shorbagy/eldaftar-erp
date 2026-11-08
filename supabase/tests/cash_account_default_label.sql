-- Regression: a brand-new shop can confirm opening balances again.
-- One transaction, then ROLLBACK.
begin;

insert into auth.users (id, instance_id, aud, role, email, is_anonymous, created_at, updated_at)
values ('93939393-9393-4393-8393-939393939393', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'label-owner@example.test', false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b3939393-9393-4393-8393-939393939393', 'متجر الافتتاح', 'المالك', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role) values
  ('b3939393-9393-4393-8393-939393939393', '93939393-9393-4393-8393-939393939393', 'owner');
insert into public.shop_entitlements (shop_id, starts_at, expires_at) values
  ('b3939393-9393-4393-8393-939393939393', now() - interval '1 day', now() + interval '30 days');

set local role authenticated;
select set_config('request.jwt.claim.sub', '93939393-9393-4393-8393-939393939393', true);

do $test$
declare
  v_shop uuid := 'b3939393-9393-4393-8393-939393939393';
  v_result jsonb;
begin
  v_result := public.confirm_opening_balances(
    'c3939393-9393-4393-8393-939393939393',
    '{"version":1,"cash":{"cash":"500000","instant_transfer":"100","wallet":"200","card":"300"},"stock":[],"scrap":[]}'::jsonb
  );
  if v_result ->> 'ok' is distinct from 'true' then
    raise exception 'opening did not commit %', v_result;
  end if;
  if (select count(*) from public.ledger_accounts
      where shop_id = v_shop and account_kind = 'cash_method') <> 4
    or exists (
      select 1 from public.ledger_accounts
      where shop_id = v_shop and account_kind = 'cash_method'
        and display_label_ar is distinct from
          private.default_cash_method_label(method_code)
    ) then
    raise exception 'cash accounts missing default labels';
  end if;
  if (public.get_daily_ledger_day_state() ->> 'business_day_id') is null then
    raise exception 'opening did not open a business day';
  end if;
end;
$test$;

reset role;
-- An explicit label is kept; a blank one gets the default.
insert into public.shops (id, name, owner_display_name, time_zone) values
  ('b3939393-9393-4393-8393-939393939394', 'متجر التسمية', 'المالك', 'Africa/Cairo');
insert into public.ledger_accounts (shop_id, account_kind, unit_kind, currency_code, method_code, display_label_ar)
values
  ('b3939393-9393-4393-8393-939393939394', 'cash_method', 'money', 'EGP', 'cash', 'الخزنة'),
  ('b3939393-9393-4393-8393-939393939394', 'cash_method', 'money', 'EGP', 'card', '  ');
do $kept$
begin
  if (select display_label_ar from public.ledger_accounts
      where shop_id = 'b3939393-9393-4393-8393-939393939394' and method_code = 'cash')
      is distinct from 'الخزنة'
    or (select display_label_ar from public.ledger_accounts
      where shop_id = 'b3939393-9393-4393-8393-939393939394' and method_code = 'card')
      is distinct from 'فيزا' then
    raise exception 'explicit or blank label handled wrongly';
  end if;
end;
$kept$;

select 'CASH_ACCOUNT_DEFAULT_LABEL_PASSED' as result;
rollback;

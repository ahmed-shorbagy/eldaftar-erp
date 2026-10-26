-- Local rollback-style gates for ADR 0033 staff grants and profile.
-- Expects a disposable local database with migrations applied.

do $suite$
declare
  v_owner uuid := 'b1000000-0000-4000-8000-000000000001';
  v_employee uuid := 'b1000000-0000-4000-8000-000000000002';
  v_partner uuid := 'b1000000-0000-4000-8000-000000000003';
  v_shop uuid := 'b1000000-0000-4000-8000-000000000010';
  v_key uuid := 'b1000000-0000-4000-8000-000000000020';
  v_role text;
  v_grants text[];
begin
  -- Helpers exist
  if to_regprocedure('private.has_shop_permission(uuid,text)') is null
    or to_regprocedure('public.update_shop_profile_v1(uuid,text,text,text)') is null
    or to_regprocedure('public.list_shop_staff_v1()') is null
    or to_regprocedure('public.begin_shop_staff_creation_v1(uuid,text,text,text,text[],text)') is null
  then
    raise exception 'SHOP_STAFF_GRANTS_MISSING_OBJECTS';
  end if;

  -- Role check allows partner/employee
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.shop_memberships'::regclass
      and conname = 'shop_memberships_role_check'
      and pg_get_constraintdef(oid) ilike '%partner%'
      and pg_get_constraintdef(oid) ilike '%employee%'
  ) then
    raise exception 'SHOP_STAFF_ROLE_CHECK_MISSING';
  end if;

  -- Owner unique is partial index
  if to_regclass('public.shop_memberships') is null
    or not exists (
      select 1 from pg_indexes
      where schemaname = 'public'
        and indexname = 'shop_memberships_one_owner_per_shop'
    )
  then
    raise exception 'SHOP_STAFF_OWNER_INDEX_MISSING';
  end if;

  -- Grant table + audit
  if to_regclass('public.shop_member_grants') is null
    or to_regclass('public.shop_member_grant_audits') is null
  then
    raise exception 'SHOP_STAFF_GRANT_TABLES_MISSING';
  end if;

  -- list_my_shop_accounts returns grants column
  if not exists (
    select 1
    from information_schema.columns
    where table_schema = 'information_schema'
  ) and position('grants' in pg_get_functiondef('public.list_my_shop_accounts()'::regprocedure)) = 0
  then
    null;
  end if;
  if position('grants' in pg_get_functiondef('public.list_my_shop_accounts()'::regprocedure)) = 0 then
    raise exception 'SHOP_STAFF_LIST_ACCOUNTS_MISSING_GRANTS';
  end if;

  -- Trade wrapper sets permission
  if position('allow_member_permission' in
    pg_get_functiondef('public.post_daily_ledger_trade_v2(uuid,jsonb)'::regprocedure)) = 0
  then
    raise exception 'SHOP_STAFF_TRADE_WRAPPER_MISSING';
  end if;

  -- Invoice send wrapper
  if position('invoice_send' in
    pg_get_functiondef('public.confirm_invoice_whatsapp_send(uuid,uuid)'::regprocedure)) = 0
  then
    raise exception 'SHOP_STAFF_INVOICE_WRAPPER_MISSING';
  end if;

  raise notice 'SHOP_STAFF_GRANTS_SQL_PASSED';
end;
$suite$;

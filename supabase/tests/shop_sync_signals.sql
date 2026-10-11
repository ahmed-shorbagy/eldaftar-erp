-- Shop sync signals stay payload-free and cover catalog/membership mutations.
begin;

insert into auth.users (
  id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at
) values
  ('f1f1f1f1-f1f1-41f1-81f1-f1f1f1f1f101', '00000000-0000-0000-0000-000000000000',
   'authenticated', 'authenticated', 'sync-owner@example.test', now(), false, now(), now());

insert into public.shops (id, name, owner_display_name, time_zone, created_by, setup_request_key)
values (
  'f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f201', 'متجر المزامنة', 'مالك المزامنة',
  'Africa/Cairo', 'f1f1f1f1-f1f1-41f1-81f1-f1f1f1f1f101', 'f3f3f3f3-f3f3-43f3-83f3-f3f3f3f3f301'
);

insert into public.shop_memberships (shop_id, user_id, role)
values ('f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f201', 'f1f1f1f1-f1f1-41f1-81f1-f1f1f1f1f101', 'owner');

insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values ('f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f201', now() - interval '1 day', now() + interval '1 day');

do $test$
declare
  v_before bigint;
  v_inventory bigint;
  v_shop uuid := 'f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f201';
  v_product uuid;
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'shop_sync_signals'
  ) then
    raise exception 'realtime_publication_missing';
  end if;
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'shop_sync_signals'
      and column_name in ('cash_piastres', 'grams', 'payload')
  ) then
    raise exception 'financial_payload_on_signal';
  end if;

  select inventory_revision, revision into v_inventory, v_before
  from public.shop_sync_signals where shop_id = v_shop;

  insert into public.inventory_products (shop_id, name, category_code, karat)
  values (v_shop, 'خاتم اختبار', 'worked_jewelry', 18)
  returning id into v_product;

  if (select inventory_revision from public.shop_sync_signals where shop_id = v_shop) <= v_inventory then
    raise exception 'catalog_product_did_not_bump';
  end if;

  v_inventory := (select inventory_revision from public.shop_sync_signals where shop_id = v_shop);
  insert into public.bullion_denominations (shop_id, label, nominal_milligrams)
  values (v_shop, 'سبيكة اختبار', 10000);
  if (select inventory_revision from public.shop_sync_signals where shop_id = v_shop) <= v_inventory then
    raise exception 'bullion_did_not_bump';
  end if;
  v_inventory := (select inventory_revision from public.shop_sync_signals where shop_id = v_shop);
  insert into public.coin_types (shop_id, label, nominal_milligrams)
  values (v_shop, 'عملة اختبار', 8000);
  if (select inventory_revision from public.shop_sync_signals where shop_id = v_shop) <= v_inventory then
    raise exception 'coin_did_not_bump';
  end if;

  v_before := (select location_revision from public.shop_sync_signals where shop_id = v_shop);
  update public.shop_memberships
    set revoked_at = clock_timestamp()
    where shop_id = v_shop;
  if (select location_revision from public.shop_sync_signals where shop_id = v_shop) <= v_before then
    raise exception 'membership_revoke_did_not_bump';
  end if;
  update public.shop_memberships
    set revoked_at = null
    where shop_id = v_shop;

  begin
    delete from public.shops where id = v_shop;
    raise exception 'referenced_shop_deleted';
  exception when foreign_key_violation then null;
  end;
  -- Existing business references must keep their integrity. Exercise deletion
  -- with a separate empty shop, whose only child is the cascade-owned signal.
  insert into public.shops (id, name)
  values ('f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f299', 'متجر فارغ للاختبار');
  delete from public.shops where id = 'f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f299';
  if exists (select 1 from public.shop_sync_signals
    where shop_id = 'f2f2f2f2-f2f2-42f2-82f2-f2f2f2f2f299') then
    raise exception 'deleted_shop_signal_remained';
  end if;
end;
$test$;

rollback;

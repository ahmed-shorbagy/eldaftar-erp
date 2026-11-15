-- Read-only counts taken before and after applying 20261115090000 on development.
select
  (select count(*) from public.shops) as shops,
  (select count(*) from public.shop_entitlements) as entitlements,
  (select count(*) from public.shop_memberships) as memberships,
  (select count(*) from public.shop_member_grants) as member_grants,
  (select count(*) from auth.users) as auth_users,
  (select count(*) from public.financial_operations) as financial_operations,
  (select count(*) from public.inventory_lot_movements) as lot_movements,
  (select count(*) from public.invoice_dispatch_confirmations) as dispatch_confirmations,
  (select md5(string_agg(shop_id::text || user_id::text || role || coalesce(revoked_at::text, ''), ',' order by shop_id, user_id))
     from public.shop_memberships) as memberships_md5,
  (select count(*) from supabase_migrations.schema_migrations) as migration_rows,
  (select max(version) from supabase_migrations.schema_migrations) as latest_migration;

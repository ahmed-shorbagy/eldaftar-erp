select jsonb_build_object(
  'snapshot_utc', (clock_timestamp() at time zone 'utc'),
  'migration_count', (select count(*)::int from supabase_migrations.schema_migrations),
  'latest_version', (select version from supabase_migrations.schema_migrations order by version desc limit 1),
  'shops', (select count(*)::int from public.shops),
  'entitlements', (select count(*)::int from public.shop_entitlements),
  'memberships', (select count(*)::int from public.shop_memberships),
  'auth_users', (select count(*)::int from auth.users),
  'financial_operations', (select count(*)::int from public.financial_operations),
  'membership_roles_md5', md5((
    select coalesce(
      string_agg(
        shop_id::text || ':' || user_id::text || ':' || role || ':' || coalesce(revoked_at::text, ''),
        '|' order by shop_id, user_id
      ),
      ''
    )
    from public.shop_memberships
  )),
  'has_original_held', (
    position('original_held_milligrams' in pg_get_functiondef('public.get_inventory_totals_v1(text,smallint)'::regprocedure)) > 0
  ),
  'has_trader_pending', (
    position('pending_receipt_count' in pg_get_functiondef('public.search_traders_v1(text,integer,text)'::regprocedure)) > 0
  )
);

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
  'staff_grants', (select count(*)::int from public.shop_member_grants),
  'has_profile_rpc', (to_regprocedure('public.update_shop_profile_v1(uuid,text,text,text)') is not null),
  'has_staff_list_rpc', (to_regprocedure('public.list_shop_staff_v1()') is not null),
  'has_trade_wrapper', (
    position('allow_member_permission' in pg_get_functiondef('public.post_daily_ledger_trade_v2(uuid,jsonb)'::regprocedure)) > 0
  )
);

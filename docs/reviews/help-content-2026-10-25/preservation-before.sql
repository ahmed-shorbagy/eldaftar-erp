select jsonb_build_object(
  'snapshot_utc', (now() at time zone 'utc'),
  'migration_count', (select count(*)::int from supabase_migrations.schema_migrations),
  'latest_version', (select version from supabase_migrations.schema_migrations order by version desc limit 1),
  'latest_name', (select name from supabase_migrations.schema_migrations order by version desc limit 1),
  'migration_versions_md5_through_20261025100000', md5((
    select string_agg(version, ',' order by version)
    from supabase_migrations.schema_migrations
    where version <= '20261025100000'
  )),
  'list_accounts_md5', md5(pg_get_functiondef('public.list_my_shop_accounts()'::regprocedure)),
  'shops', (select count(*)::int from public.shops),
  'entitlements', (select count(*)::int from public.shop_entitlements),
  'memberships', (select count(*)::int from public.shop_memberships),
  'auth_users', (select count(*)::int from auth.users),
  'auth_sessions', (select count(*)::int from auth.sessions),
  'financial_operations', (select count(*)::int from public.financial_operations),
  'help_topics_oid', to_regclass('public.help_topics')::text,
  'list_help_oid', to_regprocedure('public.list_help_catalog_v1()')::text
);

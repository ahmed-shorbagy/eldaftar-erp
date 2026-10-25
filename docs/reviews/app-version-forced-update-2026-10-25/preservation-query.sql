-- Read-only preservation fingerprints for ADM-04 development deploy.
select jsonb_build_object(
  'snapshot_utc', (now() at time zone 'utc'),
  'migration_count', (select count(*)::int from supabase_migrations.schema_migrations),
  'latest_version', (
    select version
    from supabase_migrations.schema_migrations
    order by version desc
    limit 1
  ),
  'latest_name', (
    select name
    from supabase_migrations.schema_migrations
    order by version desc
    limit 1
  ),
  'migration_versions_md5', md5((
    select string_agg(version, ',' order by version)
    from supabase_migrations.schema_migrations
  )),
  'migration_versions_md5_through_20261025093000', md5((
    select string_agg(version, ',' order by version)
    from supabase_migrations.schema_migrations
    where version <= '20261025093000'
  )),
  'list_accounts_md5', md5(pg_get_functiondef('public.list_my_shop_accounts()'::regprocedure)),
  'shops', (select count(*)::int from public.shops),
  'entitlements', (select count(*)::int from public.shop_entitlements),
  'memberships', (select count(*)::int from public.shop_memberships),
  'auth_users', (select count(*)::int from auth.users),
  'auth_sessions', (select count(*)::int from auth.sessions),
  'financial_operations', (select count(*)::int from public.financial_operations),
  'subscription_codes', (select count(*)::int from private.subscription_codes),
  'notice_dismissals', (select count(*)::int from public.subscription_notice_dismissals),
  'policy_table_oid', to_regclass('public.app_version_policies')::text,
  'get_policy_oid', to_regprocedure('public.get_app_version_policy_v1()')::text,
  'admin_get_oid', to_regprocedure('public.admin_get_app_version_policy_v1()')::text,
  'admin_set_oid', to_regprocedure(
    'public.admin_set_app_version_policy_v1(text,text,text,text)'
  )::text
);

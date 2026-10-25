-- Read-only after fingerprints once app_version objects exist.
select jsonb_build_object(
  'snapshot_utc', (now() at time zone 'utc'),
  'migration_count', (select count(*)::int from supabase_migrations.schema_migrations),
  'latest_version', (
    select version from supabase_migrations.schema_migrations order by version desc limit 1
  ),
  'latest_name', (
    select name from supabase_migrations.schema_migrations order by version desc limit 1
  ),
  'migration_versions_md5', md5((
    select string_agg(version, ',' order by version) from supabase_migrations.schema_migrations
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
  'app_version_policies', (select count(*)::int from public.app_version_policies),
  'policy_table_present', true,
  'get_policy_present', true,
  'admin_get_present', true,
  'admin_set_present', true,
  'anon_get_exec', has_function_privilege('anon', 'public.get_app_version_policy_v1()', 'EXECUTE'),
  'authenticated_get_exec', has_function_privilege(
    'authenticated', 'public.get_app_version_policy_v1()', 'EXECUTE'
  ),
  'authenticated_admin_set_exec', has_function_privilege(
    'authenticated',
    'public.admin_set_app_version_policy_v1(text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated_table_select', has_table_privilege(
    'authenticated', 'public.app_version_policies', 'SELECT'
  ),
  'anon_table_select', has_table_privilege('anon', 'public.app_version_policies', 'SELECT')
);

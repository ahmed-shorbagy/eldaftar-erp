do $$
declare
  result jsonb;
  count_in text;
  count_inquiries int;
  count_events int;
begin
  select count(*) into count_inquiries
    from (select 1) as t
    where to_regclass('public.support_inquiries') is not null;
  if count_inquiries is null then count_inquiries := 0; end if;
  if to_regclass('public.support_inquiries') is null then
    count_inquiries := -1;
  else
    execute 'select count(*) from public.support_inquiries' into count_inquiries;
  end if;
  if to_regclass('public.support_inquiry_events') is null then
    count_events := -1;
  else
    execute 'select count(*) from public.support_inquiry_events' into count_events;
  end if;
  select jsonb_build_object(
    'snapshot_utc', (clock_timestamp() at time zone 'utc'),
    'migration_count', (select count(*)::int from supabase_migrations.schema_migrations),
    'latest_version', (select version from supabase_migrations.schema_migrations order by version desc limit 1),
    'shops', (select count(*)::int from public.shops),
    'entitlements', (select count(*)::int from public.shop_entitlements),
    'memberships', (select count(*)::int from public.shop_memberships),
    'auth_users', (select count(*)::int from auth.users),
    'financial_operations', (select count(*)::int from public.financial_operations),
    'support_inquiries', count_inquiries,
    'support_inquiry_events', count_events,
    'membership_roles_md5', md5((
      select coalesce(
        string_agg(
          shop_id::text || ':' || user_id::text || ':' || role || ':' || coalesce(revoked_at::text, ''),
          '|' order by shop_id, user_id
        ),
        ''
      )
      from public.shop_memberships
    ))
  ) into result;
  create temp table preservation_snapshot (payload jsonb) on commit drop;
  insert into preservation_snapshot values (result);
end
$$;

select payload from preservation_snapshot;

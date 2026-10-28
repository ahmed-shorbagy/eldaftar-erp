do $$
declare
  result jsonb;
  financial_audits int;
  identity_audits int;
  grant_audits int;
  invoice_message_audits int;
  invoice_appearance_audits int;
  closing_audits int;
  support_events int;
  trade_change_audits int;
begin
  if to_regclass('public.financial_audit_events') is null then
    financial_audits := -1;
  else
    execute 'select count(*)::int from public.financial_audit_events' into financial_audits;
  end if;
  if to_regclass('public.identity_audit_events') is null then
    identity_audits := -1;
  else
    execute 'select count(*)::int from public.identity_audit_events' into identity_audits;
  end if;
  if to_regclass('public.shop_member_grant_audits') is null then
    grant_audits := -1;
  else
    execute 'select count(*)::int from public.shop_member_grant_audits' into grant_audits;
  end if;
  if to_regclass('public.invoice_message_audits') is null then
    invoice_message_audits := -1;
  else
    execute 'select count(*)::int from public.invoice_message_audits' into invoice_message_audits;
  end if;
  if to_regclass('public.invoice_appearance_audits') is null then
    invoice_appearance_audits := -1;
  else
    execute 'select count(*)::int from public.invoice_appearance_audits' into invoice_appearance_audits;
  end if;
  if to_regclass('public.closing_delegation_audit') is null then
    closing_audits := -1;
  else
    execute 'select count(*)::int from public.closing_delegation_audit' into closing_audits;
  end if;
  if to_regclass('public.support_inquiry_events') is null then
    support_events := -1;
  else
    execute 'select count(*)::int from public.support_inquiry_events' into support_events;
  end if;
  if to_regclass('public.ledger_trade_change_audits') is null then
    trade_change_audits := -1;
  else
    execute 'select count(*)::int from public.ledger_trade_change_audits' into trade_change_audits;
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
    'financial_audit_events', financial_audits,
    'identity_audit_events', identity_audits,
    'shop_member_grant_audits', grant_audits,
    'invoice_message_audits', invoice_message_audits,
    'invoice_appearance_audits', invoice_appearance_audits,
    'closing_delegation_audit', closing_audits,
    'support_inquiry_events', support_events,
    'ledger_trade_change_audits', trade_change_audits,
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

-- Read-only only. Route through execute_sql(project_id='xchapwvmvoefriqcxtvn').
select jsonb_build_object(
'identity',(select jsonb_build_object('database',current_database(),'role',current_user,'project_ref',current_setting('app.settings.project_ref',true))),
'columns',(select jsonb_agg(to_jsonb(c)) from (select table_schema,table_name,column_name,data_type,is_nullable,column_default from information_schema.columns where (table_schema='auth' and table_name in ('users','sessions')) or (table_schema='storage' and table_name in ('buckets','objects')) order by table_schema,table_name,ordinal_position)c),
'policies',(select coalesce(jsonb_agg(to_jsonb(p)),'[]') from pg_policies p where schemaname='storage'),
'buckets',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'public',public,'limit',file_size_limit,'mime',allowed_mime_types)),'[]') from storage.buckets),
'triggers',(select jsonb_agg(jsonb_build_object('table',tgrelid::regclass::text,'definition',pg_get_triggerdef(oid))) from pg_trigger where not tgisinternal and tgrelid in ('auth.users'::regclass,'storage.objects'::regclass)),
'notes_table',to_regclass('public.daily_note_attachments'),
'settings',(select coalesce(jsonb_agg(jsonb_build_object('name',name,'setting',setting)),'[]') from pg_settings where name like '%project%' or name like '%jwt%')
) as preflight;

select system_identifier::text from pg_control_system();

select jsonb_object_agg(relation,n) as counts from (select 'auth.users' relation,count(*) n from auth.users union all select 'auth.sessions',count(*) from auth.sessions union all select 'storage.objects',count(*) from storage.objects union all select 'storage.buckets',count(*) from storage.buckets union all select 'public.shops',count(*) from public.shops union all select 'public.financial_operations',count(*) from public.financial_operations union all select 'public.financial_command_requests',count(*) from public.financial_command_requests union all select 'public.financial_audit_events',count(*) from public.financial_audit_events union all select 'public.financial_outbox',count(*) from public.financial_outbox union all select 'public.journals',count(*) from public.journals union all select 'public.journal_postings',count(*) from public.journal_postings)c;

select r.rolname,c.relname,c.relrowsecurity,
  has_table_privilege(r.rolname,c.oid,'SELECT') as select_allowed,
  has_table_privilege(r.rolname,c.oid,'INSERT') as insert_allowed,
  has_table_privilege(r.rolname,c.oid,'UPDATE') as update_allowed,
  has_table_privilege(r.rolname,c.oid,'DELETE') as delete_allowed
from pg_roles r cross join pg_class c join pg_namespace n on n.oid=c.relnamespace
where r.rolname in ('anon','authenticated') and n.nspname='storage'
  and c.relname in ('buckets','objects');

select jsonb_build_object(
  'auth_functions',(select jsonb_agg(jsonb_build_object('name',p.proname,'body',pg_get_functiondef(p.oid)))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='auth' and p.proname in ('uid','jwt')),
  'delete_guard',(select pg_get_functiondef('storage.protect_delete()'::regprocedure)),
  'auth_constraints',(select jsonb_agg(pg_get_constraintdef(oid)) from pg_constraint where conrelid='auth.users'::regclass),
  'role_settings',(select jsonb_agg(jsonb_build_object('database',setdatabase,'role',setrole,'settings',setconfig))
    from pg_db_role_setting)
) as result;

select jsonb_build_object(
  'constraint_definitions',(select jsonb_agg(jsonb_build_object('table',conrelid::regclass::text,
    'name',conname,'definition',pg_get_constraintdef(oid))) from pg_constraint
    where conname in ('financial_operations_kind_check','financial_audit_events_action_check','financial_outbox_event_check')),
  'migration_collisions',(select coalesce(jsonb_agg(proname),'[]') from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where (n.nspname='private' and proname in ('extend_enumerated_check','parse_optional_sequence',
      'note_mime_extension','shop_display_zone','note_storage_select_allowed','note_storage_insert_allowed',
      'note_storage_metadata_allowed','ledger_operation_label','daily_note_json'))
    or (n.nspname='public' and proname in ('post_daily_note','get_daily_note_status','get_daily_note',
      'list_daily_notes','get_ledger_operation_page','get_daily_ledger_v2_before_notes_pagination'))),
  'existing_ledger',(select jsonb_agg(jsonb_build_object('name',proname,'owner',pg_get_userbyid(proowner),
    'acl',proacl)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and proname='get_daily_ledger_v2'),
  'storage_helpers',(select jsonb_agg(proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='storage' and proname in ('foldername','filename','extension'))
) as migration_preflight;

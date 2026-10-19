select c.relname as relation,
(xpath('//payload/text()',query_to_xml(format(
'select count(*)::text || ''|'' || encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text, E''\n'' order by to_jsonb(t)::text), ''''), ''UTF8''), ''sha256''), ''hex'') as payload from public.%I t',c.relname),false,false,'')))[1]::text as payload
from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' order by 1;

select jsonb_build_object(
'functions_protected', (select encode(extensions.digest(convert_to(coalesce(string_agg(n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||') '||md5(pg_get_functiondef(p.oid))||' '||coalesce(p.proacl::text,''),E'\n' order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid)),''),'UTF8'),'sha256'),'hex') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f' and p.proname <> 'bump_shop_sync' and p.proname not like 'invoice_message_%' and p.proname not in ('get_invoice_message_v1','review_invoice_message_v1','post_invoice_message_v1','get_invoice_message_status_v1','get_invoice_message_source_v1')),
'policies_protected',(select md5(coalesce(string_agg(row_to_json(t)::text,E'\n' order by schemaname,tablename,policyname),'')) from pg_policies t where schemaname in ('public','private','auth','storage') and tablename not in ('invoice_message_revisions','invoice_message_audits','invoice_message_requests')),
'triggers_protected',(select md5(coalesce(string_agg(pg_get_triggerdef(t.oid),E'\n' order by n.nspname,c.relname,t.tgname),'')) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where not t.tgisinternal and n.nspname in ('public','private','auth','storage') and c.relname not in ('invoice_message_revisions','invoice_message_audits','invoice_message_requests')),
'storage_objects',(select count(*) from storage.objects),
'storage_objects_digest',(select encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\n' order by to_jsonb(t)::text),''),'UTF8'),'sha256'),'hex') from storage.objects t),
'storage_buckets_digest',(select encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\n' order by to_jsonb(t)::text),''),'UTF8'),'sha256'),'hex') from storage.buckets t),
'auth_users_count',(select count(*) from auth.users),
'auth_users_digest',(select encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\n' order by to_jsonb(t)::text),''),'UTF8'),'sha256'),'hex') from auth.users t),
'auth_sessions_count',(select count(*) from auth.sessions),
'auth_sessions_digest',(select encode(extensions.digest(convert_to(coalesce(string_agg(to_jsonb(t)::text,E'\n' order by to_jsonb(t)::text),''),'UTF8'),'sha256'),'hex') from auth.sessions t),
'sync_without_message',(select encode(extensions.digest(convert_to(coalesce(string_agg((to_jsonb(t)-'message_revision')::text,E'\n' order by (to_jsonb(t)-'message_revision')::text),''),'UTF8'),'sha256'),'hex') from public.shop_sync_signals t),
'message_table_absent',to_regclass('public.invoice_message_revisions') is null,
'message_rpc_absent',to_regprocedure('public.get_invoice_message_v1()') is null,
'message_column_absent',not exists(select 1 from information_schema.columns where table_schema='public' and table_name='shop_sync_signals' and column_name='message_revision')
) as meta;

select version,name,cardinality(statements) as statement_count,encode(extensions.digest(convert_to(btrim(replace(array_to_string(statements,E'\n'),E'\r',''),E' \t\n\r'),'UTF8'),'sha256'),'hex') as normalized_sha256 from supabase_migrations.schema_migrations order by version;


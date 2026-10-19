begin;
select pg_catalog.set_config('request.jwt.claims','{}',true);
do $check$ begin
if private.invoice_message_normalize(to_jsonb(E'  {sequence}\r\n{total}  '::text)) is distinct from E'{sequence}\n{total}' then raise exception 'normalize_failed'; end if;
if private.invoice_message_normalize(to_jsonb('   '::text)) is not null then raise exception 'reset_failed'; end if;
begin perform private.invoice_message_assert_template('{remaining}'); raise exception 'invalid_token_accepted'; exception when others then if sqlerrm='invalid_token_accepted' then raise; end if; end;
end $check$;
set local role authenticated;
do $check$ declare t text; begin
foreach t in array array['invoice_message_revisions','invoice_message_audits','invoice_message_requests'] loop
if has_table_privilege(current_user,'public.'||t,'insert') or has_table_privilege(current_user,'public.'||t,'update') or has_table_privilege(current_user,'public.'||t,'delete') then raise exception 'direct_write_grant'; end if;
end loop;
if exists(select 1 from public.invoice_message_revisions) or exists(select 1 from public.invoice_message_audits) or exists(select 1 from public.invoice_message_requests) then raise exception 'unscoped_rows_visible'; end if;
begin perform public.get_invoice_message_v1(); raise exception 'read_accepted_without_identity'; exception when others then if sqlerrm <> 'unauthenticated' then raise; end if; end;
begin perform public.review_invoice_message_v1('{}'); raise exception 'review_accepted_without_identity'; exception when others then if sqlerrm <> 'unauthenticated' then raise; end if; end;
begin perform public.post_invoice_message_v1('b1555555-5555-4555-8555-555555555555','{}'); raise exception 'write_accepted_without_identity'; exception when others then if sqlerrm <> 'unauthenticated' then raise; end if; end;
begin perform public.get_invoice_message_status_v1('b1555555-5555-4555-8555-555555555555','{}'); raise exception 'status_accepted_without_identity'; exception when others then if sqlerrm <> 'unauthenticated' then raise; end if; end;
begin perform public.get_invoice_message_source_v1('b1444444-4444-4444-8444-444444444444'); raise exception 'source_accepted_without_identity'; exception when others then if sqlerrm <> 'unauthenticated' then raise; end if; end;
end $check$;
set local role anon;
do $check$ begin
begin perform public.get_invoice_message_v1(); raise exception 'anonymous_execute_allowed'; exception when insufficient_privilege then null; end;
end $check$;
reset role;
rollback;
select 'HOSTED_READONLY_AUTHORIZATION_AND_PARSER_PASSED' as gate;


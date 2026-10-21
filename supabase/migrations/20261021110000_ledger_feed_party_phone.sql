-- Compact journal feed rows expose optional customer phone beside party_name.
-- Home date reads and operation pages share the same feed object shape.
begin;

do $patch_feed_phone$
declare
  v_anchor text := $a$'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),$a$;
  v_next text := $n$'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),
      'party_phone', nullif(pg_catalog.btrim(kept.summary_payload ->> 'customer_phone'), ''),$n$;
  v_procs regprocedure[] := array[
    'public.get_ledger_date_v1(date, text, integer)'::regprocedure,
    'public.get_ledger_operation_page(uuid, text, text, integer)'::regprocedure
  ];
  v_proc regprocedure;
  v_def text;
  v_count integer;
begin
  foreach v_proc in array v_procs loop
    v_def := pg_catalog.replace(
      pg_catalog.pg_get_functiondef(v_proc),
      E'\r\n',
      E'\n'
    );
    if v_def is null
      or pg_catalog.strpos(v_def, v_anchor) = 0 then
      raise exception 'feed_party_phone_anchor: %', v_proc;
    end if;
    if pg_catalog.strpos(v_def, 'party_phone') <> 0 then
      raise exception 'feed_party_phone_already_present: %', v_proc;
    end if;
    v_def := pg_catalog.replace(v_def, v_anchor, v_next);
    v_count := (
      pg_catalog.length(v_def)
      - pg_catalog.length(pg_catalog.replace(v_def, 'party_phone', ''))
    ) / pg_catalog.length('party_phone');
    if v_proc = 'public.get_ledger_date_v1(date, text, integer)'::regprocedure
      and v_count is distinct from 1 then
      raise exception 'feed_party_phone_count_date: %', v_count;
    end if;
    if v_proc = 'public.get_ledger_operation_page(uuid, text, text, integer)'::regprocedure
      and v_count is distinct from 2 then
      raise exception 'feed_party_phone_count_page: %', v_count;
    end if;
    execute v_def;
  end loop;
end;
$patch_feed_phone$;

comment on function public.get_ledger_date_v1(date, text, integer) is
  'Owner read of one shop business date. Feed rows include optional party_name and party_phone from the trade payload when present.';

comment on function public.get_ledger_operation_page(uuid, text, text, integer) is
  'Paginated confirmed operations for one business day. Feed rows include optional party_name and party_phone from the trade payload when present.';

commit;

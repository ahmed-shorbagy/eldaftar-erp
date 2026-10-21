-- Journal payment labels use «انستا», matching owner-facing cash method copy.
begin;

do $patch_insta_label$
declare
  v_old text := $$when 'instant_transfer' then 'إنستا باي'$$;
  v_new text := $$when 'instant_transfer' then 'انستا'$$;
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
      or pg_catalog.strpos(v_def, v_old) = 0 then
      raise exception 'feed_insta_label_anchor: %', v_proc;
    end if;
    v_def := pg_catalog.replace(v_def, v_old, v_new);
    v_count := (
      pg_catalog.length(v_def)
      - pg_catalog.length(pg_catalog.replace(v_def, v_new, ''))
    ) / pg_catalog.length(v_new);
    if v_proc = 'public.get_ledger_date_v1(date, text, integer)'::regprocedure
      and v_count is distinct from 1 then
      raise exception 'feed_insta_label_count_date: %', v_count;
    end if;
    if v_proc = 'public.get_ledger_operation_page(uuid, text, text, integer)'::regprocedure
      and v_count is distinct from 2 then
      raise exception 'feed_insta_label_count_page: %', v_count;
    end if;
    execute v_def;
  end loop;
end;
$patch_insta_label$;

commit;

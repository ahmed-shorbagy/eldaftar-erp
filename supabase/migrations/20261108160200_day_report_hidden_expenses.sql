-- The day report summed every expense, including deleted and replaced ones.
-- Expenses only became editable in 20261108160000, so the report's expense
-- total and count never applied the `hidden` flag the other totals use. Weekly
-- reports and period analytics add up day reports, so this fixes them too.
-- Each anchor must occur exactly once; otherwise the migration aborts.

begin;

do $patch$
declare
  v_def text;
  v_anchor text;
  v_hits integer;
  v_old1 text := 'case when kind = ''expense'' then (payload->>''total_piastres'')::numeric else 0 end expense,';
  v_new1 text := 'case when hidden then 0 when kind = ''expense'' then (payload->>''total_piastres'')::numeric else 0 end expense,';
  v_old2 text := '''expense_count'',count(*) filter(where kind=''expense'')::text,';
  v_new2 text := '''expense_count'',count(*) filter(where not hidden and kind=''expense'')::text,';
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.get_financial_day_report_v1_before_staff(uuid)'::regprocedure
  );
  foreach v_anchor in array array[v_old1, v_old2] loop
    v_hits := (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_anchor, '')))
      / pg_catalog.length(v_anchor);
    if v_hits <> 1 then
      raise exception 'day_report_expense_anchor % found %', v_anchor, v_hits;
    end if;
  end loop;
  v_def := pg_catalog.replace(v_def, v_old1, v_new1);
  v_def := pg_catalog.replace(v_def, v_old2, v_new2);
  execute v_def;
end;
$patch$;

notify pgrst, 'reload schema';
commit;

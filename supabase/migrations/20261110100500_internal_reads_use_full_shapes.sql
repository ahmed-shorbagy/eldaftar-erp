-- Internal read chains must use the full reads (ADR 0044 C-D1 review).
-- 20261110100000 renamed get_ledger_date_v1 and get_financial_day_report_v1
-- to *_full and put legacy wrappers under the old names, but two internal
-- callers still resolved the old names:
-- * get_daily_ledger_home_v1_before_staff fed the current home (v2) from the
--   legacy date read, so after a day close the v2 day_summary had no
--   repair_piastres / repair_count, and the v2 feed carried 361ad2e labels.
-- * get_financial_week_report_v1_before_staff built each day from the legacy
--   day report, so weekly days lost their repair totals.
-- Both now call the *_v2 reads. Older builds read weeks with a parser that
-- accepts extra summary keys, so the week shape stays compatible.

begin;

do $patch_home$
declare
  v_def text;
  v_old text := 'public.get_ledger_date_v1(';
  v_new text := 'public.get_ledger_date_v2(';
  v_count integer;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.get_daily_ledger_home_v1_before_staff()'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, ''))
  ) / pg_catalog.length(v_old);
  if v_count = 0 and pg_catalog.strpos(v_def, v_new) > 0 then
    return;
  end if;
  if v_count <> 1 then
    raise exception 'home_before_staff_date_anchor %', v_count;
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_home$;

do $patch_week$
declare
  v_def text;
  v_old text := 'public.get_financial_day_report_v1(';
  v_new text := 'public.get_financial_day_report_v2(';
  v_count integer;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.get_financial_week_report_v1_before_staff(date)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, ''))
  ) / pg_catalog.length(v_old);
  if v_count = 0 and pg_catalog.strpos(v_def, v_new) > 0 then
    return;
  end if;
  if v_count <> 1 then
    raise exception 'week_report_day_anchor %', v_count;
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_week$;

notify pgrst, 'reload schema';
commit;

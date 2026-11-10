-- Freeze public read shapes for app builds up to 361ad2e (ADR 0044 C-D1).
-- Full payloads move to *_full internals and public *_v2; legacy names strip
-- keys the old parsers reject.

begin;

-- ---------------------------------------------------------------------------
-- get_daily_ledger_home_v1
-- ---------------------------------------------------------------------------
alter function public.get_daily_ledger_home_v1()
  rename to get_daily_ledger_home_v1_full;
revoke all on function public.get_daily_ledger_home_v1_full()
  from public, anon, authenticated;

create function public.get_daily_ledger_home_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  return public.get_daily_ledger_home_v1_full();
end;
$fn$;

revoke all on function public.get_daily_ledger_home_v2() from public, anon;
grant execute on function public.get_daily_ledger_home_v2() to authenticated;

comment on function public.get_daily_ledger_home_v2() is
  'Current-app home read with day_reset and repair day_summary keys (ADR 0044).';

create function public.get_daily_ledger_home_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_summary jsonb;
begin
  -- Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).
  v_result := public.get_daily_ledger_home_v1_full();
  v_result := v_result - 'day_reset' - 'last_closed_business_date';
  if pg_catalog.jsonb_typeof(v_result -> 'day_summary') = 'object' then
    v_summary := (v_result -> 'day_summary')
      - 'repair_piastres'
      - 'repair_count';
    v_result := pg_catalog.jsonb_set(v_result, '{day_summary}', v_summary);
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_daily_ledger_home_v1() from public, anon;
grant execute on function public.get_daily_ledger_home_v1() to authenticated;

comment on function public.get_daily_ledger_home_v1() is
  'Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).';

-- ---------------------------------------------------------------------------
-- get_ledger_date_v1
-- ---------------------------------------------------------------------------
alter function public.get_ledger_date_v1(date, text, integer)
  rename to get_ledger_date_v1_full;
revoke all on function public.get_ledger_date_v1_full(date, text, integer)
  from public, anon, authenticated;

create function public.get_ledger_date_v2(
  p_business_date date default null,
  p_before_sequence text default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  return public.get_ledger_date_v1_full(
    p_business_date, p_before_sequence, p_limit
  );
end;
$fn$;

revoke all on function public.get_ledger_date_v2(date, text, integer)
  from public, anon;
grant execute on function public.get_ledger_date_v2(date, text, integer)
  to authenticated;

comment on function public.get_ledger_date_v2(date, text, integer) is
  'Current-app ledger date read with repair day_summary keys (ADR 0044).';

create function public.get_ledger_date_v1(
  p_business_date date default null,
  p_before_sequence text default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_summary jsonb;
begin
  -- Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).
  v_result := public.get_ledger_date_v1_full(
    p_business_date, p_before_sequence, p_limit
  );
  if pg_catalog.jsonb_typeof(v_result -> 'day_summary') = 'object' then
    v_summary := (v_result -> 'day_summary')
      - 'repair_piastres'
      - 'repair_count';
    v_result := pg_catalog.jsonb_set(v_result, '{day_summary}', v_summary);
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_ledger_date_v1(date, text, integer)
  from public, anon;
grant execute on function public.get_ledger_date_v1(date, text, integer)
  to authenticated;

comment on function public.get_ledger_date_v1(date, text, integer) is
  'Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).';

-- ---------------------------------------------------------------------------
-- get_financial_day_report_v1
-- ---------------------------------------------------------------------------
alter function public.get_financial_day_report_v1(uuid)
  rename to get_financial_day_report_v1_full;
revoke all on function public.get_financial_day_report_v1_full(uuid)
  from public, anon, authenticated;

create function public.get_financial_day_report_v2(p_day_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
begin
  return public.get_financial_day_report_v1_full(p_day_id);
end;
$fn$;

revoke all on function public.get_financial_day_report_v2(uuid)
  from public, anon;
grant execute on function public.get_financial_day_report_v2(uuid)
  to authenticated;

comment on function public.get_financial_day_report_v2(uuid) is
  'Current-app day report with repair summary keys (ADR 0044).';

create function public.get_financial_day_report_v1(p_day_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_summary jsonb;
begin
  -- Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).
  v_result := public.get_financial_day_report_v1_full(p_day_id);
  if pg_catalog.jsonb_typeof(v_result -> 'summary') = 'object' then
    v_summary := (v_result -> 'summary')
      - 'repair_piastres'
      - 'repair_count';
    v_result := pg_catalog.jsonb_set(v_result, '{summary}', v_summary);
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_financial_day_report_v1(uuid)
  from public, anon;
grant execute on function public.get_financial_day_report_v1(uuid)
  to authenticated;

comment on function public.get_financial_day_report_v1(uuid) is
  'Shape frozen for app builds up to 361ad2e (ADR 0044 C-D1).';

-- get_repair_v1 collections: old parser is not strict on extra keys; leave as-is.
-- get_ledger_day_v1 is new on 2026-11-09 and used only by the current app.
-- It called get_ledger_date_v1; keep the full repair keys by calling v2.
do $patch_day_read$
declare
  v_def text;
  v_old text := 'public.get_ledger_date_v1(';
  v_new text := 'public.get_ledger_date_v2(';
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.get_ledger_day_v1(uuid, text, integer)'::regprocedure
  );
  if (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
    / pg_catalog.length(v_old) < 1 then
    raise exception 'ledger_day_read_date_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_day_read$;

notify pgrst, 'reload schema';
commit;

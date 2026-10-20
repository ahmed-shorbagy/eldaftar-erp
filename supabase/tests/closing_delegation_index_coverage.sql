-- Catalog-only FK coverage verification; safe on local or hosted databases.
do $coverage$ declare v_missing text; begin
  select string_agg(c.conrelid::regclass::text||'.'||c.conname,', ' order by c.conname)
    into v_missing
  from pg_constraint c
  where c.contype='f' and c.conrelid in (
    'public.closing_staff_accounts'::regclass,'public.closing_count_tasks'::regclass,
    'public.closing_delegation_audit'::regclass,'private.closing_staff_creation_requests'::regclass,
    'private.closing_delegation_commands'::regclass)
  and not exists (
    select 1 from pg_index i where i.indrelid=c.conrelid and i.indisvalid and i.indisready
      and i.indpred is null and i.indnkeyatts>=cardinality(c.conkey)
      and not exists(select 1 from unnest(c.conkey) with ordinality k(attnum,pos) where i.indkey[k.pos::integer-1]<>k.attnum)
  );
  if v_missing is not null then raise exception 'uncovered count delegation FKs: %',v_missing; end if;
end; $coverage$;
select 'CLOSING_DELEGATION_FK_COVERAGE_PASSED' as result;

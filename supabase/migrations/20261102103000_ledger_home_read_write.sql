-- The staff wrapper recreated get_daily_ledger_home_v1 as STABLE.
-- PostgREST runs a STABLE RPC in a read-only transaction. The home read
-- calls get_daily_ledger_v2, which takes FOR SHARE on the shop row, and
-- Postgres rejects that with 25006. The client maps the unrecognized
-- error to the generic home failure. Mark the wrapper volatile again so
-- PostgREST uses a read/write transaction.
begin;

alter function public.get_daily_ledger_home_v1() volatile;

comment on function public.get_daily_ledger_home_v1() is
  'Home summary and feed for the open financial day until explicit close. Volatile so PostgREST allows the shop share lock used by get_daily_ledger_v2.';

notify pgrst, 'reload schema';

commit;

-- get_daily_ledger_home_v1 is a read model, but it calls get_daily_ledger_v2,
-- which takes SELECT FOR SHARE on shops so the trade-change revision matches
-- writers. PostgREST runs STABLE RPCs in a read-only transaction, which rejects
-- FOR SHARE (25006). Mark the home RPC volatile so it uses a read/write
-- transaction, matching get_daily_ledger_v2 itself.
begin;

alter function public.get_daily_ledger_home_v1() volatile;

comment on function public.get_daily_ledger_home_v1() is
  'Owner-only calendar-date home summary/feed with exact return/note counters and server UTC rollover timing. Read only for business state; volatile so PostgREST allows the shared shop lock used by get_daily_ledger_v2.';

notify pgrst, 'reload schema';

commit;

-- Cover repair foreign keys found by the hosted performance advisor.
-- These indexes do not change custody, fees, access or historical records.
begin;
create index repairs_actor_idx on public.repairs (shop_id, intake_actor_user_id);
create index repairs_fee_operation_idx on public.repairs (shop_id, financial_operation_id);
create index repair_events_actor_idx on public.repair_events (shop_id, actor_user_id);
create index repair_custody_actor_idx on public.repair_custody_events (shop_id, actor_user_id);
commit;

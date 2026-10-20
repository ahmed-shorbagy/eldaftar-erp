-- Cover the new count-only identity/task/audit foreign keys. No data or grants
-- change; the owner and staff authorization boundaries stay unchanged.
begin;
create index closing_staff_accounts_creator_idx on public.closing_staff_accounts(created_by);
create index closing_count_tasks_day_idx on public.closing_count_tasks(business_day_id);
create index closing_count_tasks_assigner_idx on public.closing_count_tasks(assigned_by);
create index closing_count_tasks_submitter_idx on public.closing_count_tasks(submitted_by);
create index closing_count_tasks_close_operation_idx on public.closing_count_tasks(closed_operation_id);
create index closing_count_tasks_shop_staff_idx on public.closing_count_tasks(shop_id,staff_id);
create index closing_delegation_audit_shop_idx on public.closing_delegation_audit(shop_id,created_at desc,id);
create index closing_delegation_audit_actor_idx on public.closing_delegation_audit(actor_user_id);
create index closing_delegation_audit_staff_idx on public.closing_delegation_audit(staff_id);
create index closing_delegation_audit_task_idx on public.closing_delegation_audit(task_id);
create index closing_delegation_audit_operation_idx on public.closing_delegation_audit(operation_id);
create index closing_staff_creation_owner_idx on private.closing_staff_creation_requests(owner_user_id);
create index closing_staff_creation_staff_idx on private.closing_staff_creation_requests(staff_id);
create index closing_delegation_commands_actor_idx on private.closing_delegation_commands(actor_user_id);
commit;

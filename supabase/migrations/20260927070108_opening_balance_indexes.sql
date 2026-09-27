-- Forward performance fix from development advisor review.
-- Preserve the applied opening migration. No data, policy, or RPC changes.
create index financial_operations_actor_idx on public.financial_operations (shop_id, actor_user_id);
create index financial_operations_day_idx on public.financial_operations (shop_id, business_day_id);
create index journals_operation_idx on public.journals (shop_id, operation_id);
create index journal_postings_account_idx on public.journal_postings (shop_id, account_id);
create index journal_postings_journal_operation_idx on public.journal_postings (shop_id, journal_id, operation_id);
-- Conservation checks resolve a globally unique journal id before scanning postings.
create index journal_postings_journal_idx on public.journal_postings (journal_id);
create index journal_postings_operation_idx on public.journal_postings (shop_id, operation_id);
create index financial_command_requests_operation_idx on public.financial_command_requests (shop_id, operation_id);
create index financial_audit_events_actor_idx on public.financial_audit_events (shop_id, actor_user_id);
create index financial_audit_events_operation_idx on public.financial_audit_events (shop_id, operation_id);
create index financial_outbox_operation_idx on public.financial_outbox (shop_id, operation_id);

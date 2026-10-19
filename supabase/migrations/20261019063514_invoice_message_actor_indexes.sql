-- Cover owner membership foreign keys on append-only SET-04 metadata.
-- Follow-up to the hosted advisor; no row, grant, policy or function changes.
begin;

create index invoice_message_revisions_actor_idx
  on public.invoice_message_revisions (shop_id, actor_user_id);

create index invoice_message_audits_actor_idx
  on public.invoice_message_audits (shop_id, actor_user_id);

commit;

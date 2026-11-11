-- Auto-captured customers show their phone (ADR 0043 B-D3, CRM-05).
--
-- Customer reads build `phones` in `private.customer_saved_enrich` with an
-- inner join to `public.customer_number_declarations`. The owner's customer
-- commands insert phones through `private.customer_replace_phones`, which
-- calls `private.customer_reconcile_numbers` and starts an `unknown`
-- declaration. `private.customer_auto_capture` (20261109110100) inserts the
-- phone directly and starts none, so every customer created from a sale or
-- purchase read back with `phones: []`: «بدون رقم هاتف», and no WhatsApp or
-- call action (found in the 2026-11-11 device pass).
--
-- Every phone insert now starts the `unknown` declaration when the number has
-- no active one. The existing reconcile path stays correct: the partial unique
-- index makes the second insert a no-op. Phones already missing a declaration
-- are backfilled as `unknown`, with no actor, as 20261014080820 did.

begin;

create function private.customer_phone_start_declaration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.customer_number_declarations (
    shop_id, customer_id, normalized_number, tracking_started_at
  )
  values (
    NEW.shop_id, NEW.customer_id, NEW.normalized_number,
    pg_catalog.clock_timestamp()
  )
  on conflict (shop_id, customer_id, normalized_number)
    where retired_at is null
    do nothing;
  return NEW;
end;
$fn$;

revoke all on function private.customer_phone_start_declaration()
  from public, anon, authenticated;

create trigger customer_phones_start_declaration
after insert on public.customer_phones
for each row execute function private.customer_phone_start_declaration();

insert into public.customer_number_declarations (
  shop_id, customer_id, normalized_number, tracking_started_at
)
select phone.shop_id, phone.customer_id, phone.normalized_number,
  pg_catalog.clock_timestamp()
from public.customer_phones as phone
where not exists (
  select 1
  from public.customer_number_declarations as declaration
  where declaration.shop_id = phone.shop_id
    and declaration.customer_id = phone.customer_id
    and declaration.normalized_number = phone.normalized_number
    and declaration.retired_at is null
)
on conflict (shop_id, customer_id, normalized_number)
  where retired_at is null
  do nothing;

commit;

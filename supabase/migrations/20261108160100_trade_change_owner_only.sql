-- Trade edit/delete stays owner-only for every kind (plan D7, T5.1).
-- Sale and purchase changes set no member permission, so only an owner passes
-- private.opening_require_reader_shop(). The expense/customer_return path from
-- 20261108160000 set the expense or sale grant first, which let any partner or
-- employee with that grant edit or delete any expense or return in the shop,
-- including operations an employee cannot see. These wrappers check the owner
-- role explicitly before any change, for all kinds.

begin;

alter function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  rename to review_ledger_trade_change_v1_before_owner_check;
revoke all on function public.review_ledger_trade_change_v1_before_owner_check(
  uuid, text, jsonb
) from public, anon, authenticated;

create function public.review_ledger_trade_change_v1(
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  v_shop := private.opening_require_reader_shop();
  if private.shop_member_role(v_shop) is distinct from 'owner' then
    raise exception 'forbidden';
  end if;
  return public.review_ledger_trade_change_v1_before_owner_check(
    p_operation_id, p_action, p_replacement
  );
end;
$fn$;

revoke all on function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  from public, anon;
grant execute on function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  to authenticated;

alter function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) rename to post_ledger_trade_change_v1_before_owner_check;
revoke all on function public.post_ledger_trade_change_v1_before_owner_check(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon, authenticated;

create function public.post_ledger_trade_change_v1(
  p_idempotency_key uuid,
  p_operation_id uuid,
  p_action text,
  p_replacement jsonb,
  p_expected_day_id uuid,
  p_expected_day_version bigint,
  p_source_sha256 text,
  p_review_token text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  v_shop := private.opening_require_reader_shop();
  if private.shop_member_role(v_shop) is distinct from 'owner' then
    raise exception 'forbidden';
  end if;
  return public.post_ledger_trade_change_v1_before_owner_check(
    p_idempotency_key, p_operation_id, p_action, p_replacement,
    p_expected_day_id, p_expected_day_version, p_source_sha256, p_review_token
  );
end;
$fn$;

revoke all on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon;
grant execute on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) to authenticated;

notify pgrst, 'reload schema';
commit;

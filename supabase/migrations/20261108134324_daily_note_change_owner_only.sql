-- Daily notes stay owner-only (AGENTS.md). post_daily_note_change_v1 relied on
-- private.opening_require_reader_shop(), which admits a partner or employee
-- whenever an earlier call in the same transaction set a member permission.
-- This wrapper checks the owner role explicitly before any change.

begin;

alter function public.post_daily_note_change_v1(uuid, uuid, text, text)
  rename to post_daily_note_change_v1_before_owner_check;
revoke all on function public.post_daily_note_change_v1_before_owner_check(uuid, uuid, text, text)
  from public, anon, authenticated;

create function public.post_daily_note_change_v1(
  p_idempotency_key uuid,
  p_note_operation_id uuid,
  p_action text,
  p_text text
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
  return public.post_daily_note_change_v1_before_owner_check(
    p_idempotency_key, p_note_operation_id, p_action, p_text
  );
end;
$fn$;

revoke all on function public.post_daily_note_change_v1(uuid, uuid, text, text)
  from public, anon;
grant execute on function public.post_daily_note_change_v1(uuid, uuid, text, text)
  to authenticated;

notify pgrst, 'reload schema';
commit;

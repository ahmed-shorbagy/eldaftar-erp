-- Edit/delete can invalidate an operation in any previously loaded feed page.
-- Expose a monotonic server sequence so clients discard those cached pages.
begin;

-- Every statement in one historical response sees the same committed snapshot.
alter function public.get_ledger_date_v1(date, text, integer) stable;

alter function public.get_daily_ledger_v2()
  rename to get_daily_ledger_v2_before_trade_cache;
revoke all on function public.get_daily_ledger_v2_before_trade_cache()
  from public, anon, authenticated;

create function public.get_daily_ledger_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_sequence bigint;
begin
  -- The legacy read model uses volatile helpers. Serialize its read and the
  -- revision with financial writers, which already lock this shop row.
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for share;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  v_result := public.get_daily_ledger_v2_before_trade_cache();
  if v_result ->> 'state' is distinct from 'confirmed' then
    return v_result;
  end if;
  select coalesce(max(operation.shop_sequence), 0)
    into v_sequence
  from public.ledger_trade_changes as change
  join public.financial_operations as operation
    on operation.shop_id = change.shop_id
   and operation.id = change.reversal_operation_id
  where change.shop_id = v_shop;
  return v_result || pg_catalog.jsonb_build_object(
    'trade_change_sequence', v_sequence::text
  );
end;
$fn$;

revoke all on function public.get_daily_ledger_v2() from public, anon;
grant execute on function public.get_daily_ledger_v2() to authenticated;
notify pgrst, 'reload schema';
commit;

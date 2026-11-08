-- Purchases are paid in full. A new jewelry line is scrap, not worked stock.
-- An idempotent replay of a stored command skips the new checks.
-- Edit and exchange replacements post through public.post_daily_ledger_trade
-- internally. They set eldaftar.purchase_keep_category for that call, so an
-- old purchase may keep its jewelry line. Payment in full still applies.
-- Clients cannot set this flag: set_config is not an exposed RPC.

begin;

create function private.purchase_paid_violation(
  p_payload jsonb,
  p_check_jewelry boolean
)
returns text
language plpgsql
immutable
set search_path = ''
as $fn$
declare
  v_sum numeric;
begin
  if p_payload ->> 'kind' is distinct from 'purchase' then
    return null;
  end if;
  if p_payload ? 'purchase_obligation_piastres' then
    return 'purchase_must_be_paid';
  end if;
  -- A malformed amount is left to the original writer, which raises
  -- invalid_input. This guard only judges well-formed purchases.
  begin
    select coalesce(sum((tender ->> 'piastres')::numeric), 0)
      into v_sum
    from jsonb_array_elements(coalesce(p_payload -> 'tenders', '[]'::jsonb)) as tender;
    if v_sum is distinct from (p_payload ->> 'total_piastres')::numeric then
      return 'purchase_must_be_paid';
    end if;
  exception when others then
    return null;
  end;
  if p_check_jewelry and exists (
    select 1
    from jsonb_array_elements(coalesce(p_payload -> 'items', '[]'::jsonb)) as item
    where item ->> 'category' = 'worked_jewelry'
  ) then
    return 'purchase_jewelry_is_scrap';
  end if;
  return null;
end;
$fn$;

revoke all on function private.purchase_paid_violation(jsonb, boolean)
  from public, anon, authenticated;

alter function public.post_daily_ledger_trade_v2(uuid, jsonb)
  rename to post_daily_ledger_trade_v2_before_paid_purchase;
revoke all on function public.post_daily_ledger_trade_v2_before_paid_purchase(uuid, jsonb)
  from public, anon, authenticated;

create function public.post_daily_ledger_trade_v2(
  p_idempotency_key uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_kind text;
  v_perm text;
  v_shop uuid;
  v_error text;
begin
  v_kind := p_payload ->> 'kind';
  v_perm := case
    when v_kind in ('sale', 'scrap_sale') then 'sale'
    when v_kind = 'purchase' then 'purchase'
    when v_kind = 'expense' then 'expense'
    else null
  end;
  if v_perm is null then
    raise exception 'invalid_input';
  end if;
  perform private.allow_member_permission(v_perm);
  v_shop := private.opening_require_reader_shop();
  if exists (
    select 1
    from public.financial_command_requests as request
    where request.shop_id = v_shop
      and request.idempotency_key = p_idempotency_key
  ) then
    return public.post_daily_ledger_trade_v2_before_paid_purchase(
      p_idempotency_key, p_payload
    );
  end if;
  v_error := private.purchase_paid_violation(p_payload, true);
  if v_error is not null then
    raise exception '%', v_error;
  end if;
  return public.post_daily_ledger_trade_v2_before_paid_purchase(
    p_idempotency_key, p_payload
  );
end;
$fn$;

revoke all on function public.post_daily_ledger_trade_v2(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_trade_v2(uuid, jsonb) to authenticated;

alter function public.post_daily_ledger_trade(uuid, jsonb)
  rename to post_daily_ledger_trade_before_paid_purchase;
revoke all on function public.post_daily_ledger_trade_before_paid_purchase(uuid, jsonb)
  from public, anon, authenticated;

create function public.post_daily_ledger_trade(
  p_idempotency_key uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_error text;
begin
  v_shop := private.opening_require_reader_shop();
  if exists (
    select 1
    from public.financial_command_requests as request
    where request.shop_id = v_shop
      and request.idempotency_key = p_idempotency_key
  ) then
    return public.post_daily_ledger_trade_before_paid_purchase(
      p_idempotency_key, p_payload
    );
  end if;
  v_error := private.purchase_paid_violation(
    p_payload,
    coalesce(
      pg_catalog.current_setting('eldaftar.purchase_keep_category', true), ''
    ) is distinct from 'on'
  );
  if v_error is not null then
    raise exception '%', v_error;
  end if;
  return public.post_daily_ledger_trade_before_paid_purchase(
    p_idempotency_key, p_payload
  );
end;
$fn$;

revoke all on function public.post_daily_ledger_trade(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_trade(uuid, jsonb) to authenticated;

alter function public.review_ledger_trade_change_v1(uuid, text, jsonb)
  rename to review_ledger_trade_change_v1_before_paid_purchase;
revoke all on function public.review_ledger_trade_change_v1_before_paid_purchase(uuid, text, jsonb)
  from public, anon, authenticated;

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
  v_kind text;
  v_error text;
begin
  v_shop := private.opening_require_reader_shop();
  if p_action = 'edit' then
    select operation.kind into v_kind
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.id = p_operation_id;
    if v_kind = 'purchase' then
      v_error := private.purchase_paid_violation(p_replacement, false);
      if v_error is not null then
        raise exception '%', v_error;
      end if;
    end if;
  end if;
  return public.review_ledger_trade_change_v1_before_paid_purchase(
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
) rename to post_ledger_trade_change_v1_before_paid_purchase;
revoke all on function public.post_ledger_trade_change_v1_before_paid_purchase(
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
  v_kind text;
  v_error text;
  v_result jsonb;
begin
  v_shop := private.opening_require_reader_shop();
  if exists (
    select 1
    from public.financial_command_requests as request
    where request.shop_id = v_shop
      and request.idempotency_key = p_idempotency_key
  ) then
    return public.post_ledger_trade_change_v1_before_paid_purchase(
      p_idempotency_key, p_operation_id, p_action, p_replacement,
      p_expected_day_id, p_expected_day_version, p_source_sha256, p_review_token
    );
  end if;
  if p_action = 'edit' then
    select operation.kind into v_kind
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.id = p_operation_id;
    if v_kind = 'purchase' then
      v_error := private.purchase_paid_violation(p_replacement, false);
      if v_error is not null then
        raise exception '%', v_error;
      end if;
    end if;
  end if;
  perform pg_catalog.set_config('eldaftar.purchase_keep_category', 'on', true);
  v_result := public.post_ledger_trade_change_v1_before_paid_purchase(
    p_idempotency_key, p_operation_id, p_action, p_replacement,
    p_expected_day_id, p_expected_day_version, p_source_sha256, p_review_token
  );
  perform pg_catalog.set_config('eldaftar.purchase_keep_category', 'off', true);
  return v_result;
end;
$fn$;

revoke all on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) from public, anon;
grant execute on function public.post_ledger_trade_change_v1(
  uuid, uuid, text, jsonb, uuid, bigint, text, text
) to authenticated;

alter function public.post_exchange_v1(uuid, jsonb)
  rename to post_exchange_v1_before_paid_purchase;
revoke all on function public.post_exchange_v1_before_paid_purchase(uuid, jsonb)
  from public, anon, authenticated;

-- Retired from clients (20261019230000). Wrapped so a replacement keeps the
-- category the owner chose (ADR 0040) while the purchase is still paid in full.
create function public.post_exchange_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
begin
  perform pg_catalog.set_config('eldaftar.purchase_keep_category', 'on', true);
  v_result := public.post_exchange_v1_before_paid_purchase(
    p_idempotency_key, p_payload
  );
  perform pg_catalog.set_config('eldaftar.purchase_keep_category', 'off', true);
  return v_result;
end;
$fn$;

revoke all on function public.post_exchange_v1(uuid, jsonb)
  from public, anon, authenticated;

commit;

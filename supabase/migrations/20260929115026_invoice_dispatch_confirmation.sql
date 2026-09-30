-- Owner-attested WhatsApp send. Apply only after daily_ledger_trades.
begin;

alter table public.financial_audit_events drop constraint financial_audit_events_action_check;
alter table public.financial_audit_events add constraint financial_audit_events_action_check
  check (action in ('opening_balances_confirmed', 'sale_confirmed',
    'purchase_confirmed', 'expense_confirmed', 'business_day_closed',
    'business_day_opened', 'invoice_send_confirmed'));

create table public.invoice_dispatch_confirmations (
  operation_id uuid primary key,
  shop_id uuid not null,
  idempotency_key uuid not null,
  actor_user_id uuid not null,
  confirmed_at timestamptz not null,
  constraint invoice_dispatch_confirmations_shop_key unique (shop_id, idempotency_key),
  constraint invoice_dispatch_confirmations_operation_fk
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint invoice_dispatch_confirmations_actor_fk
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);
create index invoice_dispatch_confirmations_shop_time_idx
  on public.invoice_dispatch_confirmations (shop_id, confirmed_at desc);
alter table public.invoice_dispatch_confirmations enable row level security;
create policy invoice_dispatch_confirmations_owner_read
  on public.invoice_dispatch_confirmations for select to authenticated
  using (private.opening_financial_visible(shop_id));
revoke all on public.invoice_dispatch_confirmations from public, anon, authenticated;
grant select on public.invoice_dispatch_confirmations to authenticated;
create trigger invoice_dispatch_confirmations_append_only
  before update or delete on public.invoice_dispatch_confirmations
  for each row execute function private.financial_audit_events_append_only();
do $revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.invoice_dispatch_confirmations from service_role';
  end if;
end;
$revoke$;

create function public.confirm_invoice_whatsapp_send(
  p_operation_id uuid, p_idempotency_key uuid
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
  v_kind text;
  v_at timestamptz;
  v_actor uuid;
  v_existing public.invoice_dispatch_confirmations%rowtype;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_operation_id is null or p_idempotency_key is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops as shop where shop.id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select operation.kind into v_kind
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if v_kind not in ('sale', 'purchase') or v_kind is null then
    raise exception 'not_found';
  end if;
  select dispatch.* into v_existing
  from public.invoice_dispatch_confirmations as dispatch
  where dispatch.shop_id = v_shop and dispatch.operation_id = p_operation_id;
  if found then
    return jsonb_build_object('ok', true, 'operation_id', p_operation_id,
      'actor_user_id', v_existing.actor_user_id,
      'confirmed_at', pg_catalog.to_jsonb(v_existing.confirmed_at),
      'replayed', v_existing.idempotency_key = p_idempotency_key,
      'already_confirmed', true);
  end if;
  if exists (
    select 1 from public.invoice_dispatch_confirmations as dispatch
    where dispatch.shop_id = v_shop and dispatch.idempotency_key = p_idempotency_key
  ) then
    raise exception 'payload_mismatch';
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  v_at := pg_catalog.clock_timestamp();
  v_actor := auth.uid();
  insert into public.invoice_dispatch_confirmations (
    operation_id, shop_id, idempotency_key, actor_user_id, confirmed_at
  ) values (p_operation_id, v_shop, p_idempotency_key, v_actor, v_at);
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (v_shop, v_actor, 'invoice_send_confirmed', p_operation_id,
    v_at, jsonb_build_object('channel', 'whatsapp', 'evidence', 'owner_attestation'));
  return jsonb_build_object('ok', true, 'operation_id', p_operation_id,
    'actor_user_id', v_actor, 'confirmed_at', pg_catalog.to_jsonb(v_at),
    'replayed', false, 'already_confirmed', false);
end;
$fn$;

create function public.get_invoice_dispatch_state(p_operation_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_kind text; v_dispatch public.invoice_dispatch_confirmations%rowtype;
begin
  if p_operation_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  select operation.kind into v_kind from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if v_kind not in ('sale', 'purchase') or v_kind is null then
    raise exception 'not_found';
  end if;
  select dispatch.* into v_dispatch from public.invoice_dispatch_confirmations as dispatch
  where dispatch.shop_id = v_shop and dispatch.operation_id = p_operation_id;
  return jsonb_build_object('operation_id', p_operation_id,
    'status', case when v_dispatch.operation_id is null then 'unconfirmed'
      else 'owner_confirmed' end,
    'actor_user_id', v_dispatch.actor_user_id,
    'confirmed_at', pg_catalog.to_jsonb(v_dispatch.confirmed_at));
end;
$fn$;

create function public.get_pending_invoice_sends(p_before_sequence bigint default null)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_items jsonb; v_next bigint; v_more boolean;
begin
  v_shop := private.opening_require_reader_shop();
  if p_before_sequence is not null and p_before_sequence < 1 then
    raise exception 'invalid_input';
  end if;
  with page as (
    select operation.id, operation.kind, operation.shop_sequence,
      operation.created_at, detail.payload ->> 'customer_name' as customer_name
    from public.financial_operations as operation
    join public.financial_operation_details as detail
      on detail.shop_id = operation.shop_id and detail.operation_id = operation.id
    left join public.invoice_dispatch_confirmations as dispatch
      on dispatch.shop_id = operation.shop_id and dispatch.operation_id = operation.id
    where operation.shop_id = v_shop and operation.kind in ('sale', 'purchase')
      and dispatch.operation_id is null
      and (p_before_sequence is null or operation.shop_sequence < p_before_sequence)
    order by operation.shop_sequence desc
    limit 51
  ), numbered as (
    select page.*, row_number() over (order by page.shop_sequence desc) as row_no
    from page
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'operation_id', numbered.id,
      'kind', numbered.kind,
      'shop_sequence', numbered.shop_sequence::text,
      'occurred_at_cairo', to_char(numbered.created_at at time zone 'Africa/Cairo',
        'YYYY-MM-DD"T"HH24:MI:SS'),
      'customer_name', coalesce(numbered.customer_name, '')
    ) order by numbered.shop_sequence desc)
      filter (where numbered.row_no <= 50), '[]'::jsonb),
    min(numbered.shop_sequence) filter (where numbered.row_no <= 50),
    coalesce(bool_or(numbered.row_no = 51), false)
    into v_items, v_next, v_more
  from numbered;
  return jsonb_build_object('items', v_items,
    'next_before_sequence', case when v_more then v_next else null end);
end;
$fn$;

revoke all on function public.confirm_invoice_whatsapp_send(uuid, uuid) from public, anon;
revoke all on function public.get_invoice_dispatch_state(uuid) from public, anon;
revoke all on function public.get_pending_invoice_sends(bigint) from public, anon;
grant execute on function public.confirm_invoice_whatsapp_send(uuid, uuid) to authenticated;
grant execute on function public.get_invoice_dispatch_state(uuid) to authenticated;
grant execute on function public.get_pending_invoice_sends(bigint) to authenticated;

commit;

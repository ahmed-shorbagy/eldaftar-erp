-- Additive, read-only DEBT-02 contract. Never replaces v1 or a command.
begin;

create function private.debt_statement_content_v1(p_shop uuid, p_kind text, p_source uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare
  v_shop public.shops%rowtype;
  v_balance record;
  v_history jsonb;
  v_entries jsonb;
  v_origin numeric;
  v_settled numeric;
  v_cancelled numeric;
begin
  if not private.opening_financial_visible(p_shop) then raise exception 'forbidden'; end if;
  select * into v_shop from public.shops where id = p_shop;
  select * into v_balance from private.debt_balances(p_shop)
    where source_kind = p_kind and source_id = p_source;
  if v_balance.source_id is null then raise exception 'not_found'; end if;

  -- Inner joins in the legacy history must not hide incomplete origin/operation evidence.
  if exists (
    select 1 from public.financial_operations o
    where o.shop_id = p_shop and p_kind <> 'standalone' and (
      o.id = p_source or exists (
        select 1 from public.financial_operation_details d
        where d.shop_id = p_shop and d.operation_id = o.id and (
          d.payload ->> 'purchase_operation_id' = p_source::text or
          d.payload ->> 'obligation_operation_id' = p_source::text or
          d.payload ->> 'original_operation_id' = p_source::text
        )
      )
    ) and (not exists (select 1 from public.financial_operation_details d
      where d.shop_id = p_shop and d.operation_id = o.id)
      or not exists (select 1 from public.financial_audit_events a
        where a.shop_id = p_shop and a.operation_id = o.id))
  ) then raise exception 'incomplete_debt_statement'; end if;

  v_history := private.debt_history(p_shop, p_kind, p_source, v_shop.time_zone);
  if (v_balance.display_status = 'archived') is distinct from exists (
    select 1 from public.debt_events e where e.shop_id=p_shop and e.source_kind=p_kind
      and e.source_id=p_source and e.event_type='archived'
  ) or exists (
    select 1 from public.debt_events e where e.shop_id=p_shop and e.source_kind=p_kind
      and e.source_id=p_source and e.event_type='settled' and e.payload->>'ledger_effect'='move'
      and (not exists (select 1 from public.financial_operations o where o.shop_id=p_shop
        and o.id::text=e.payload->>'operation_id')
        or not exists (select 1 from public.financial_operation_details d where d.shop_id=p_shop
          and d.operation_id::text=e.payload->>'operation_id')
        or not exists (select 1 from public.financial_audit_events a where a.shop_id=p_shop
          and a.operation_id::text=e.payload->>'operation_id'))
  ) then raise exception 'incomplete_debt_statement'; end if;
  -- Whitelist document evidence. No financial JSON or client command payload leaves this RPC.
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', e -> 'id', 'at', e -> 'at', 'at_shop', e -> 'at_shop',
    'event_type', e -> 'event_type', 'label_ar', e -> 'label_ar',
    'actor_user_id', e -> 'actor_user_id', 'actor_display_name', e -> 'actor_display_name',
    'actor_name_current', (e ->> 'event_type') in ('posted','linked_return','linked_settlement','linked'),
    'operation_id', case when (e ->> 'event_type') in ('posted','linked_return','linked_settlement','linked')
      then e -> 'id' else e -> 'payload' -> 'operation_id' end,
    'amount', e -> 'amount', 'cancelled_amount', e -> 'cancelled_amount',
    'cash_piastres', e -> 'cash_piastres', 'gold_milligrams', case when v_balance.unit='gold'
      then e -> 'gold_milligrams' else '"0"'::jsonb end,
    'reason', e -> 'payload' -> 'reason',
    'ledger_effect', case when (e ->> 'event_type') in ('posted','linked_return','linked_settlement','linked')
      then 'move' else coalesce(e -> 'payload' ->> 'ledger_effect', 'none') end
  ) order by n), '[]'::jsonb) into v_entries
  from jsonb_array_elements(v_history) with ordinality as h(e,n);

  select coalesce(sum((e ->> 'amount')::numeric) filter (where e ->> 'event_type' in ('declared','posted')),0),
    coalesce(sum((e ->> 'amount')::numeric) filter (where e ->> 'event_type' in ('settled','linked_settlement')),0),
    coalesce(sum((e ->> 'cancelled_amount')::numeric),0)
  into v_origin, v_settled, v_cancelled from jsonb_array_elements(v_entries) h(e);
  if v_origin <> v_balance.original_amount or v_settled <> v_balance.settled_amount
    or v_cancelled <> v_balance.cancelled_amount
    or (select count(*) from jsonb_array_elements(v_entries) h(e)
      where e ->> 'event_type' in ('declared','posted')) <> 1
    or exists (select 1 from jsonb_array_elements(v_entries) h(e)
      where nullif(e ->> 'actor_display_name','') is null or e ->> 'actor_user_id' is null)
  then raise exception 'incomplete_debt_statement'; end if;

  return jsonb_build_object(
    'shop_id', p_shop, 'shop_name', v_shop.name, 'shop_phone', nullif(v_shop.phone,''),
    'time_zone', v_shop.time_zone, 'source_kind', p_kind, 'source_id', p_source,
    'source_sequence', (select o.shop_sequence::text from public.financial_operations o
      where o.shop_id = p_shop and o.id = p_source and p_kind <> 'standalone'),
    'direction', v_balance.direction, 'unit', v_balance.unit, 'karat', v_balance.karat,
    'party_name', v_balance.party_name, 'contact_phone', nullif(v_balance.contact_phone,''),
    'reason', v_balance.reason, 'external_reference', v_balance.external_reference,
    'original_amount', v_balance.original_amount::text, 'settled_amount', v_balance.settled_amount::text,
    'cancelled_amount', v_balance.cancelled_amount::text, 'remaining_amount', v_balance.remaining_amount::text,
    'display_status', v_balance.display_status, 'history_complete', true,
    'history_count', jsonb_array_length(v_entries), 'history', v_entries
  );
end;
$fn$;

create function public.get_debt_statement_v1(p_source_kind text, p_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_shop uuid; v_content jsonb; v_at timestamptz := statement_timestamp();
begin
  if p_source_kind is null or p_source_kind not in ('standalone','purchase_cash_payable','gold_obligation')
    or p_source_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.opening_require_reader_shop();
  -- STABLE: header, amounts and every history row use the calling query MVCC snapshot.
  v_content := private.debt_statement_content_v1(v_shop,p_source_kind,p_source_id);
  return v_content || jsonb_build_object(
    'version',1, 'snapshot_at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'snapshot_at_shop',to_char(v_at at time zone (v_content ->> 'time_zone'),'YYYY-MM-DD"T"HH24:MI:SS'),
    'freshness',encode(extensions.digest(convert_to(v_content::text,'UTF8'),'sha256'),'hex')
  );
end;
$fn$;

revoke all on function private.debt_statement_content_v1(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.get_debt_statement_v1(text,uuid) from public,anon,authenticated;
grant execute on function public.get_debt_statement_v1(text,uuid) to authenticated;
commit;

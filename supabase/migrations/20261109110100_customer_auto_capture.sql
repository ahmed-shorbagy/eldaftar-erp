-- Automatic customer capture from a confirmed sale or purchase (ADR 0043).
-- The capture runs in the sale's transaction and cannot fail the sale.
-- Customer reads skip operations hidden by an edit or a delete.

begin;

create function private.customer_auto_capture(p_shop uuid, p_operation uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_kind text;
  v_actor uuid;
  v_payload jsonb;
  v_name text;
  v_raw text;
  v_phone text;
  v_name_ok boolean;
  v_customer public.customers%rowtype;
  v_matches integer;
  v_at timestamptz;
  v_actor_name text;
begin
  select operation.kind, operation.actor_user_id, detail.payload
    into v_kind, v_actor, v_payload
  from public.financial_operations as operation
  join public.financial_operation_details as detail
    on detail.shop_id = operation.shop_id
   and detail.operation_id = operation.id
  where operation.shop_id = p_shop and operation.id = p_operation;
  if v_kind is null or v_kind not in ('sale', 'purchase') then
    return;
  end if;
  if exists (
    select 1
    from public.customer_operation_links as link
    where link.shop_id = p_shop
      and link.operation_id = p_operation
      and link.status = 'active'
  ) then
    return;
  end if;

  v_name := pg_catalog.btrim(coalesce(v_payload ->> 'customer_name', ''));
  v_raw := pg_catalog.btrim(coalesce(v_payload ->> 'customer_phone', ''));
  v_phone := null;
  if v_raw <> '' then
    begin
      v_phone := private.customer_normalize_phone(v_raw);
    exception
      when others then
        v_phone := null;
    end;
  end if;
  v_name_ok := pg_catalog.char_length(v_name) between 1 and 200
    and v_name ~ '[ء-ي]';
  if v_phone is null and not v_name_ok then
    return;
  end if;

  if v_phone is not null then
    select customer.* into v_customer
    from public.customer_phones as phone
    join public.customers as customer
      on customer.shop_id = phone.shop_id
     and customer.id = phone.customer_id
    where phone.shop_id = p_shop
      and phone.normalized_number = v_phone
    for update of customer;
    if found and v_customer.status = 'archived' then
      return;
    end if;
  else
    select count(*) into v_matches
    from public.customers as customer
    where customer.shop_id = p_shop
      and customer.status = 'active'
      and customer.display_name = v_name;
    if v_matches > 1 then
      return;
    end if;
    if v_matches = 1 then
      select customer.* into v_customer
      from public.customers as customer
      where customer.shop_id = p_shop
        and customer.status = 'active'
        and customer.display_name = v_name
      for update;
    end if;
  end if;

  v_at := pg_catalog.clock_timestamp();
  v_actor_name := private.customer_actor_name(p_shop);
  if v_customer.id is null then
    insert into public.customers (
      shop_id, status, record_version, display_name, is_vip,
      has_open_request, created_at, updated_at, created_by
    ) values (
      p_shop, 'active', 1,
      case when v_name_ok then v_name else 'عميل ' || v_raw end,
      false, false, v_at, v_at, v_actor
    )
    returning * into v_customer;
    if v_phone is not null then
      insert into public.customer_phones (
        shop_id, customer_id, raw_number, normalized_number, is_primary, created_at
      ) values (
        p_shop, v_customer.id, pg_catalog.left(v_raw, 32), v_phone, true, v_at
      );
    end if;
    perform private.customer_event(
      p_shop, v_customer.id, 'created', v_actor, v_actor_name, v_at,
      pg_catalog.jsonb_build_object(
        'source', 'auto',
        'operation_id', p_operation,
        'record_version', '1'
      )
    );
  end if;

  insert into public.customer_operation_links (
    shop_id, customer_id, operation_id, status, linked_at, linked_by
  ) values (
    p_shop, v_customer.id, p_operation, 'active', v_at, v_actor
  );
  update public.customers
  set record_version = record_version + 1,
      updated_at = v_at
  where shop_id = p_shop and id = v_customer.id
  returning * into v_customer;
  perform private.customer_event(
    p_shop, v_customer.id, 'linked', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'source', 'auto',
      'operation_id', p_operation,
      'operation_kind', v_kind,
      'record_version', v_customer.record_version::text
    )
  );
  perform private.bump_shop_sync(p_shop, 'customer');
end;
$fn$;

create function private.financial_operation_details_customer_capture()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
begin
  perform private.customer_auto_capture(new.shop_id, new.operation_id);
  return new;
exception
  when others then
    raise warning 'customer_auto_capture_skipped: % %', new.operation_id, sqlerrm;
    return new;
end;
$fn$;

drop trigger if exists financial_operation_details_customer_capture
  on public.financial_operation_details;
create trigger financial_operation_details_customer_capture
  after insert on public.financial_operation_details
  for each row
  execute function private.financial_operation_details_customer_capture();

revoke all on function private.customer_auto_capture(uuid, uuid)
  from public, anon, authenticated;
revoke all on function private.financial_operation_details_customer_capture()
  from public, anon, authenticated;

create or replace function private.customer_last_operation_at(
  p_shop uuid, p_customer uuid
)
returns timestamptz
language sql
stable
security definer
set search_path = ''
as $fn$
  select max(operation.created_at)
  from public.customer_operation_links as link
  join public.financial_operations as operation
    on operation.shop_id = link.shop_id
   and operation.id = link.operation_id
  where link.shop_id = p_shop
    and link.customer_id = p_customer
    and link.status = 'active'
    and operation.kind in ('sale', 'purchase')
    and not private.ledger_trade_hidden(link.shop_id, link.operation_id);
$fn$;

revoke all on function private.customer_last_operation_at(uuid, uuid)
  from public, anon, authenticated;

create or replace function private.customer_statistics_activity(
  p_shop uuid, p_customer uuid
) returns setof public.financial_operations
language sql
stable
security definer
set search_path = ''
as $fn$
  with originals as materialized (
    select operation.*
    from public.customer_operation_links as link
    join public.financial_operations as operation
      on operation.shop_id = link.shop_id and operation.id = link.operation_id
    where link.shop_id = p_shop
      and link.customer_id = p_customer
      and link.status = 'active'
      and operation.kind in ('sale', 'purchase')
      and not private.ledger_trade_hidden(link.shop_id, link.operation_id)
      and not exists (
        select 1 from public.ledger_trade_changes as change
        where change.shop_id = link.shop_id
          and change.source_operation_id = operation.id
      )
      and exists (
        select 1 from public.financial_operation_details as detail
        where detail.shop_id = p_shop and detail.operation_id = operation.id
      )
      and exists (
        select 1 from public.financial_audit_events as audit
        where audit.shop_id = p_shop
          and audit.operation_id = operation.id
          and audit.action = operation.kind || '_confirmed'
      )
  )
  select * from originals
  union all
  select operation.*
  from originals as original
  join public.financial_operation_details as detail
    on detail.shop_id = p_shop
   and detail.payload ? 'original_operation_id'
   and detail.payload ->> 'original_operation_id' = original.id::text
  join public.financial_operations as operation
    on operation.shop_id = p_shop
   and operation.id = detail.operation_id
   and operation.kind = original.kind || '_return'
  where exists (
    select 1 from public.financial_audit_events as audit
    where audit.shop_id = p_shop
      and audit.operation_id = operation.id
      and audit.action = operation.kind || '_confirmed'
  );
$fn$;

revoke all on function private.customer_statistics_activity(uuid, uuid)
  from public, anon, authenticated;

-- get_customer_list_v3 reads last activity through customer_statistics_activity.
-- get_customer_v3 lists the links itself, so that join gains the same filter.
do $patch_customer_v3$
declare
  v_def text;
  v_anchor text := E'     and operation.id = link.operation_id\n    where link.shop_id = v_shop and link.customer_id = p_customer_id';
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.get_customer_v3(uuid,integer,text,integer,text,integer,text)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if pg_catalog.strpos(v_def, 'ledger_trade_hidden(link.shop_id, link.operation_id)') = 0 then
    if pg_catalog.strpos(v_def, v_anchor) = 0 then
      raise exception 'customer_v3_link_anchor_missing';
    end if;
    v_def := pg_catalog.replace(
      v_def,
      v_anchor,
      E'     and operation.id = link.operation_id\n     and not private.ledger_trade_hidden(link.shop_id, link.operation_id)\n    where link.shop_id = v_shop and link.customer_id = p_customer_id'
    );
    execute v_def;
  end if;
end;
$patch_customer_v3$;

-- Edit/delete replacements insert a new details row (auto-capture links it)
-- and then copy active links from the source. Skip the copy when capture
-- already linked the replacement.
do $patch_change_links$
declare
  v_def text;
  v_old text := $old$
    insert into public.customer_operation_links (
      shop_id, customer_id, operation_id, status, linked_at, linked_by
    )
    select
      link.shop_id, link.customer_id, v_replacement_id, 'active', v_at, v_actor
    from public.customer_operation_links as link
    where link.shop_id = v_shop
      and link.operation_id = p_operation_id
      and link.status = 'active';
$old$;
  v_new text := $new$
    insert into public.customer_operation_links (
      shop_id, customer_id, operation_id, status, linked_at, linked_by
    )
    select
      link.shop_id, link.customer_id, v_replacement_id, 'active', v_at, v_actor
    from public.customer_operation_links as link
    where link.shop_id = v_shop
      and link.operation_id = p_operation_id
      and link.status = 'active'
      and not exists (
        select 1
        from public.customer_operation_links as existing
        where existing.shop_id = v_shop
          and existing.operation_id = v_replacement_id
          and existing.status = 'active'
      );
$new$;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.post_ledger_trade_change_v1_before_paid_purchase(uuid,uuid,text,jsonb,uuid,bigint,text,text)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if pg_catalog.strpos(v_def, 'existing.operation_id = v_replacement_id') = 0 then
    if pg_catalog.strpos(v_def, v_old) = 0 then
      raise exception 'change_link_copy_anchor_missing';
    end if;
    execute pg_catalog.replace(v_def, v_old, v_new);
  end if;
end;
$patch_change_links$;

notify pgrst, 'reload schema';
commit;

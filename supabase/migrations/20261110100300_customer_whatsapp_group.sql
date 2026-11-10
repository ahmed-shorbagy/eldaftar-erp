-- Customer WhatsApp-group flag (ADR 0044 C-D9).

begin;

alter table public.customers
  add column if not exists in_whatsapp_group boolean not null default false;

do $patch_view$
declare
  v_def text;
  v_old text := $old$'is_vip', p_customer.is_vip,
    'has_open_request', p_customer.has_open_request,$old$;
  v_new text := $new$'is_vip', p_customer.is_vip,
    'has_open_request', p_customer.has_open_request,
    'in_whatsapp_group', p_customer.in_whatsapp_group,$new$;
  v_count integer;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'private.customer_view(public.customers, text)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if v_def ~ 'in_whatsapp_group' then
    return;
  end if;
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, ''))
  ) / pg_catalog.length(v_old);
  if v_count <> 1 then
    raise exception 'customer_view_whatsapp_anchor %', v_count;
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_view$;

create or replace function private.customer_status(p_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim jsonb;
  v_shop uuid;
  v_id uuid;
  v_expected bigint;
  v_vip boolean;
  v_open boolean;
  v_group boolean;
  v_row public.customers%rowtype;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_result jsonb;
begin
  v_claim := private.customer_claim(p_key, p_payload, 'customer_status');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  perform private.customer_require_keys(p_payload, array[
    'customer_id', 'expected_version', 'has_open_request', 'in_whatsapp_group',
    'is_vip', 'kind', 'version'
  ]);
  v_shop := (v_claim ->> 'shop_id')::uuid;
  v_id := private.customer_uuid(p_payload -> 'customer_id');
  v_expected := private.customer_expected_version(p_payload -> 'expected_version');
  v_vip := private.customer_bool(p_payload -> 'is_vip');
  v_open := private.customer_bool(p_payload -> 'has_open_request');
  v_group := private.customer_bool(p_payload -> 'in_whatsapp_group');
  v_row := private.customer_lock(v_shop, v_id, v_expected);
  v_actor := auth.uid();
  v_actor_name := private.customer_actor_name(v_shop);
  v_at := pg_catalog.clock_timestamp();
  update public.customers as customer
    set is_vip = v_vip,
        has_open_request = v_open,
        in_whatsapp_group = v_group,
        record_version = customer.record_version + 1,
        updated_at = v_at
  where customer.id = v_id
  returning customer.* into v_row;
  perform private.customer_event(
    v_shop, v_id, 'status_changed', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'is_vip', v_vip,
      'has_open_request', v_open,
      'in_whatsapp_group', v_group,
      'record_version', v_row.record_version::text
    )
  );
  v_result := private.customer_view(v_row, private.customer_zone(v_shop))
    || pg_catalog.jsonb_build_object(
      'ok', true, 'replayed', false, 'command_kind', 'customer_status'
    );
  return private.customer_finish(
    v_shop, p_key, 'customer_status', p_payload, v_claim ->> 'hash', v_id, v_result
  );
end;
$fn$;

revoke all on function private.customer_status(uuid, jsonb)
  from public, anon, authenticated;

do $patch_list$
declare
  v_def text;
  v_old text := $old$or (v_filter = 'open_request' and customer.has_open_request)$old$;
  v_new text := $new$or (v_filter = 'open_request' and customer.has_open_request)
          or (v_filter = 'whatsapp_group' and customer.in_whatsapp_group)$new$;
  v_count integer;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.get_customer_list_v3(text,text,text,integer,text)'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if v_def ~ 'whatsapp_group' then
    return;
  end if;
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, ''))
  ) / pg_catalog.length(v_old);
  if v_count <> 2 then
    raise exception 'customer_list_whatsapp_filter_anchor %', v_count;
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_list$;

do $patch_overview$
declare
  v_def text;
  v_old text := $old$return pg_catalog.jsonb_build_object(
    'active_count', v_active,
    'vip_count', v_vip,
    'active_30_days', v_recent,
    'open_request_count', v_open
  );$old$;
  v_new text := $new$return pg_catalog.jsonb_build_object(
    'active_count', v_active,
    'vip_count', v_vip,
    'active_30_days', v_recent,
    'open_request_count', v_open,
    'whatsapp_group_count', (
      select count(*)::text
      from public.customers as customer
      where customer.shop_id = v_shop
        and customer.status = 'active'
        and customer.in_whatsapp_group
    )
  );$new$;
  v_count integer;
begin
  v_def := pg_catalog.replace(
    pg_catalog.pg_get_functiondef(
      'public.get_customer_overview_v1()'::regprocedure
    ),
    E'\r\n',
    E'\n'
  );
  if v_def ~ 'whatsapp_group_count' then
    return;
  end if;
  v_count := (
    pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, ''))
  ) / pg_catalog.length(v_old);
  if v_count <> 1 then
    raise exception 'customer_overview_whatsapp_anchor %', v_count;
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_overview$;

notify pgrst, 'reload schema';
commit;

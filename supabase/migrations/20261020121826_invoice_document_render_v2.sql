-- New immutable editions use white paper or dark/gold render v2. Historical
-- render-v1 copies retain their original cream colors and layout.
begin;
alter table public.invoice_appearance_revisions drop constraint invoice_appearance_revisions_template_check;
alter table public.invoice_appearance_revisions add constraint invoice_appearance_revisions_template_check check(template in ('header','compact','dark'));
alter table public.invoice_presentation_revisions drop constraint invoice_presentation_revisions_template_check;
alter table public.invoice_presentation_revisions add constraint invoice_presentation_revisions_template_check check(template in ('header','compact','dark'));
alter table public.invoice_presentation_revisions drop constraint invoice_presentation_revisions_render_check;
alter table public.invoice_presentation_revisions add constraint invoice_presentation_revisions_render_check check(render_version in (1,2) and (render_version=2 or template<>'dark'));

create or replace function private.invoice_appearance_fields(p_shop uuid, p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_logo uuid;
  v_asset public.invoice_logo_assets%rowtype;
  v_slogan text;
  v_address text;
begin
  perform private.repair_require_keys(
    p_payload,
    array['version', 'kind', 'expected_revision', 'slogan', 'address', 'template', 'accent', 'logo_asset_id']
  );
  if p_payload -> 'version' is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'invoice_appearance'
    or p_payload ->> 'template' not in ('header', 'compact', 'dark')
    or p_payload ->> 'accent' not in ('brown', 'gold', 'neutral') then
    raise exception 'invalid_input';
  end if;
  v_slogan := private.invoice_optional_text(p_payload -> 'slogan', 120, 120);
  v_address := private.invoice_optional_text(p_payload -> 'address', 200, 4);
  if p_payload -> 'logo_asset_id' = 'null'::jsonb then
    v_logo := null;
  else
    v_logo := private.repair_uuid(p_payload -> 'logo_asset_id');
    select * into v_asset from public.invoice_logo_assets where id = v_logo;
    if not found then
      raise exception 'asset_missing';
    end if;
    if v_asset.shop_id is distinct from p_shop then
      raise exception 'cross_shop';
    end if;
  end if;
  return jsonb_build_object(
    'expected_revision', private.repair_money(p_payload -> 'expected_revision', true)::text,
    'template', p_payload ->> 'template',
    'accent', p_payload ->> 'accent',
    'slogan', v_slogan,
    'address', v_address,
    'logo_asset_id', v_logo,
    'logo_sha256', v_asset.sha256
  );
end;
$fn$;

create or replace function public.post_invoice_presentation_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_presentation_requests%rowtype;
  v_fields jsonb;
  v_operation uuid;
  v_facts jsonb;
  v_appearance jsonb;
  v_latest bigint;
  v_edition bigint;
  v_at timestamptz;
  v_actor uuid := auth.uid();
  v_logo uuid;
  v_result jsonb;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select * into v_request
  from public.invoice_presentation_requests
  where shop_id = v_shop and idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical is distinct from p_payload then
      raise exception 'payload_mismatch';
    end if;
    return v_request.result || pg_catalog.jsonb_build_object('replayed', true);
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  v_fields := private.invoice_presentation_fields(p_payload);
  v_operation := (v_fields ->> 'operation_id')::uuid;
  perform 1 from public.financial_operations
  where shop_id = v_shop and id = v_operation
  for update;
  v_facts := private.invoice_operation_facts(v_shop, v_operation);
  if (v_facts ->> 'content_sha256') is distinct from (v_fields ->> 'expected_content_sha256') then
    raise exception 'stale_operation';
  end if;
  v_appearance := private.invoice_current_appearance(v_shop);
  if v_appearance->>'template'='dark' then raise exception 'unsupported_render_version'; end if;
  if (v_appearance ->> 'revision') is distinct from (v_fields ->> 'expected_appearance_revision') then
    raise exception 'stale_appearance';
  end if;
  select coalesce(pg_catalog.max(edition), 0::bigint) into v_latest
  from public.invoice_presentation_revisions
  where shop_id = v_shop and operation_id = v_operation;
  if v_latest::text is distinct from (v_fields ->> 'expected_latest_edition') then
    raise exception 'stale_presentation';
  end if;
  v_edition := v_latest + 1;
  v_at := pg_catalog.clock_timestamp();
  v_logo := nullif(v_appearance ->> 'logo_asset_id', '')::uuid;
  insert into public.invoice_presentation_revisions (
    shop_id, operation_id, edition, content_sha256, appearance_revision,
    template, accent, slogan, address, logo_asset_id, logo_sha256,
    render_version, actor_user_id, created_at
  ) values (
    v_shop, v_operation, v_edition, v_facts ->> 'content_sha256',
    (v_appearance ->> 'revision')::bigint,
    v_appearance ->> 'template', v_appearance ->> 'accent',
    v_appearance ->> 'slogan', v_appearance ->> 'address',
    v_logo, v_appearance ->> 'logo_sha256',
    1, v_actor, v_at
  );
  v_result := pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'key', p_idempotency_key,
    'kind', 'invoice_presentation',
    'payload', p_payload,
    'operation_id', v_operation,
    'edition', v_edition::text,
    'content_sha256', v_facts ->> 'content_sha256',
    'appearance_revision', v_appearance ->> 'revision',
    'template', v_appearance ->> 'template',
    'accent', v_appearance ->> 'accent',
    'slogan', v_appearance ->> 'slogan',
    'address', v_appearance ->> 'address',
    'logo_asset_id', v_logo,
    'logo_sha256', v_appearance ->> 'logo_sha256',
    'render_version', 1,
    'actor_user_id', v_actor,
    'at', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'replayed', false,
    'cash_piastres', '0',
    'gold_milligrams', '0',
    'stock_milligrams', '0',
    'invoice_effect', false,
    'dispatch_effect', false
  );
  perform private.bump_shop_sync(v_shop, 'appearance');
  insert into public.invoice_presentation_requests (
    shop_id, idempotency_key, payload_canonical, result, created_at
  ) values (
    v_shop, p_idempotency_key, p_payload, v_result, v_at
  );
  return v_result;
end;
$fn$;

create function public.post_invoice_presentation_v2(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_presentation_requests%rowtype;
  v_fields jsonb;
  v_operation uuid;
  v_facts jsonb;
  v_appearance jsonb;
  v_latest bigint;
  v_edition bigint;
  v_at timestamptz;
  v_actor uuid := auth.uid();
  v_logo uuid;
  v_result jsonb;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select * into v_request
  from public.invoice_presentation_requests
  where shop_id = v_shop and idempotency_key = p_idempotency_key
  for update;
  if found then
    if v_request.payload_canonical is distinct from p_payload then
      raise exception 'payload_mismatch';
    end if;
    return v_request.result || pg_catalog.jsonb_build_object('replayed', true);
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  v_fields := private.invoice_presentation_fields(p_payload);
  v_operation := (v_fields ->> 'operation_id')::uuid;
  perform 1 from public.financial_operations
  where shop_id = v_shop and id = v_operation
  for update;
  v_facts := private.invoice_operation_facts(v_shop, v_operation);
  if (v_facts ->> 'content_sha256') is distinct from (v_fields ->> 'expected_content_sha256') then
    raise exception 'stale_operation';
  end if;
  v_appearance := private.invoice_current_appearance(v_shop);
  if (v_appearance ->> 'revision') is distinct from (v_fields ->> 'expected_appearance_revision') then
    raise exception 'stale_appearance';
  end if;
  select coalesce(pg_catalog.max(edition), 0::bigint) into v_latest
  from public.invoice_presentation_revisions
  where shop_id = v_shop and operation_id = v_operation;
  if v_latest::text is distinct from (v_fields ->> 'expected_latest_edition') then
    raise exception 'stale_presentation';
  end if;
  v_edition := v_latest + 1;
  v_at := pg_catalog.clock_timestamp();
  v_logo := nullif(v_appearance ->> 'logo_asset_id', '')::uuid;
  insert into public.invoice_presentation_revisions (
    shop_id, operation_id, edition, content_sha256, appearance_revision,
    template, accent, slogan, address, logo_asset_id, logo_sha256,
    render_version, actor_user_id, created_at
  ) values (
    v_shop, v_operation, v_edition, v_facts ->> 'content_sha256',
    (v_appearance ->> 'revision')::bigint,
    v_appearance ->> 'template', v_appearance ->> 'accent',
    v_appearance ->> 'slogan', v_appearance ->> 'address',
    v_logo, v_appearance ->> 'logo_sha256',
    2, v_actor, v_at
  );
  v_result := pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'key', p_idempotency_key,
    'kind', 'invoice_presentation',
    'payload', p_payload,
    'operation_id', v_operation,
    'edition', v_edition::text,
    'content_sha256', v_facts ->> 'content_sha256',
    'appearance_revision', v_appearance ->> 'revision',
    'template', v_appearance ->> 'template',
    'accent', v_appearance ->> 'accent',
    'slogan', v_appearance ->> 'slogan',
    'address', v_appearance ->> 'address',
    'logo_asset_id', v_logo,
    'logo_sha256', v_appearance ->> 'logo_sha256',
    'render_version', 2,
    'actor_user_id', v_actor,
    'at', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'replayed', false,
    'cash_piastres', '0',
    'gold_milligrams', '0',
    'stock_milligrams', '0',
    'invoice_effect', false,
    'dispatch_effect', false
  );
  perform private.bump_shop_sync(v_shop, 'appearance');
  insert into public.invoice_presentation_requests (
    shop_id, idempotency_key, payload_canonical, result, created_at
  ) values (
    v_shop, p_idempotency_key, p_payload, v_result, v_at
  );
  return v_result;
end;
$fn$;

revoke all on function public.post_invoice_presentation_v2(uuid,jsonb) from public,anon;
grant execute on function public.post_invoice_presentation_v2(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;

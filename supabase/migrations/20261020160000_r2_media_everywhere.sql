-- Cloudflare R2 is the only store for new images and documents.
--
-- Bytes move between clients and R2 through short-lived presigned URLs issued
-- by the authenticated r2-media Edge Function. After an upload, the function
-- downloads the object from R2, verifies size, type, and hash, and records the
-- verified facts here through a service-only RPC. Domain RPCs (shop image,
-- invoice logo, daily note) accept only objects present in this registry, so
-- Postgres keeps object keys and verified metadata but never new media bytes.
--
-- Legacy rows stay readable: inline Postgres logo/shop-image bytes and note
-- images already in the private Supabase Storage bucket. New writes to the
-- Supabase Storage buckets and the inline-bytes RPCs are closed.

begin;

-- 1. Verified R2 object registry -------------------------------------------

create table public.r2_media_objects (
  object_key text primary key,
  shop_id uuid not null references public.shops (id),
  kind text not null,
  mime text not null,
  byte_size bigint not null,
  sha256 text not null,
  width integer,
  height integer,
  uploaded_by uuid not null references auth.users (id),
  verified_at timestamptz not null,
  constraint r2_media_objects_kind_check
    check (kind in ('shop_image', 'invoice_logo', 'note_image')),
  constraint r2_media_objects_mime_check
    check (mime in ('image/jpeg', 'image/png', 'image/webp')),
  constraint r2_media_objects_sha_check check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint r2_media_objects_size_check check (
    (kind = 'note_image' and byte_size between 1 and 5242880)
    or (kind <> 'note_image' and byte_size between 1 and 2097152)
  ),
  constraint r2_media_objects_dimensions_check check (
    (kind = 'note_image' and width is null and height is null)
    or (kind <> 'note_image'
      and width between 1 and 2048 and height between 1 and 2048)
  ),
  constraint r2_media_objects_key_check check (
    (kind = 'shop_image' and mime <> 'image/webp' and object_key =
      'shop-image/' || shop_id::text || '/' || sha256 || '.'
        || case mime when 'image/png' then 'png' else 'jpg' end)
    or (kind = 'invoice_logo' and mime <> 'image/webp' and object_key =
      'invoice-logo/' || shop_id::text || '/' || sha256 || '.'
        || case mime when 'image/png' then 'png' else 'jpg' end)
    or (kind = 'note_image' and object_key ~ (
      '^note-image/' || shop_id::text
        || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        || '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.]'
        || case mime when 'image/png' then 'png'
             when 'image/webp' then 'webp' else 'jpg' end
        || '$'))
  )
);

create index r2_media_objects_shop_kind_idx
  on public.r2_media_objects (shop_id, kind);

alter table public.r2_media_objects enable row level security;
alter table public.r2_media_objects force row level security;
revoke all on public.r2_media_objects from public, anon, authenticated;

create trigger r2_media_objects_append_only
  before update or delete on public.r2_media_objects
  for each row execute function private.financial_audit_events_append_only();

do $r2_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.r2_media_objects from service_role';
  end if;
end;
$r2_revoke$;

-- Called only by the r2-media Edge Function (service role) after it has read
-- the object back from R2. p_actor is the user id from the verified bearer.
-- Content-addressed kinds pass the bytes so the strict image parser derives
-- mime and dimensions here; note images pass verified size and hash only.
create function public.record_r2_media_object_v1(
  p_actor uuid,
  p_shop uuid,
  p_kind text,
  p_object_key text,
  p_byte_size bigint,
  p_sha256 text,
  p_image_base64 text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_ext text;
  v_mime text;
  v_raw bytea;
  v_fact record;
  v_width integer;
  v_height integer;
  v_row public.r2_media_objects%rowtype;
  v_replayed boolean := false;
begin
  if p_actor is null or p_shop is null or p_kind is null or p_object_key is null
    or p_byte_size is null or p_sha256 is null
    or p_kind not in ('shop_image', 'invoice_logo', 'note_image')
    or p_sha256 !~ '^[0-9a-f]{64}$'
    or pg_catalog.length(p_object_key) > 512 then
    raise exception 'media_rejected';
  end if;
  if not exists (
    select 1 from public.shop_memberships as membership
    where membership.shop_id = p_shop
      and membership.user_id = p_actor
      and membership.role = 'owner'
      and membership.revoked_at is null
  ) then
    raise exception 'forbidden';
  end if;
  if not exists (
    select 1 from public.shop_entitlements as entitlement
    where entitlement.shop_id = p_shop
      and entitlement.starts_at <= pg_catalog.now()
      and pg_catalog.now() < entitlement.expires_at
  ) then
    raise exception 'shop_not_active';
  end if;
  v_ext := (pg_catalog.regexp_match(p_object_key, '[.]([a-z]+)$'))[1];
  v_mime := case v_ext
    when 'jpg' then 'image/jpeg'
    when 'png' then 'image/png'
    when 'webp' then 'image/webp'
    else null
  end;
  if v_mime is null then
    raise exception 'media_rejected';
  end if;
  if p_kind = 'note_image' then
    if p_image_base64 is not null or p_byte_size < 1 or p_byte_size > 5242880 then
      raise exception 'media_rejected';
    end if;
  else
    if p_image_base64 is null or p_byte_size < 1 or p_byte_size > 2097152 then
      raise exception 'media_rejected';
    end if;
    begin
      v_raw := pg_catalog.decode(p_image_base64, 'base64');
    exception
      when others then
        raise exception 'media_rejected';
    end;
    if pg_catalog.octet_length(v_raw) is distinct from p_byte_size
      or pg_catalog.encode(extensions.digest(v_raw, 'sha256'), 'hex') is distinct from p_sha256 then
      raise exception 'media_rejected';
    end if;
    select * into v_fact from private.invoice_logo_facts(v_raw, true);
    if v_fact.mime is distinct from v_mime then
      raise exception 'media_rejected';
    end if;
    v_width := v_fact.width;
    v_height := v_fact.height;
  end if;

  select * into v_row from public.r2_media_objects where object_key = p_object_key;
  if found then
    if v_row.shop_id is distinct from p_shop
      or v_row.kind is distinct from p_kind
      or v_row.sha256 is distinct from p_sha256
      or v_row.byte_size is distinct from p_byte_size
      or v_row.uploaded_by is distinct from p_actor then
      raise exception 'media_mismatch';
    end if;
    v_replayed := true;
  else
    begin
      insert into public.r2_media_objects (
        object_key, shop_id, kind, mime, byte_size, sha256, width, height,
        uploaded_by, verified_at
      ) values (
        p_object_key, p_shop, p_kind, v_mime, p_byte_size, p_sha256,
        v_width, v_height, p_actor, pg_catalog.clock_timestamp()
      )
      returning * into v_row;
    exception
      when check_violation then
        raise exception 'media_rejected';
    end;
  end if;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'object_key', v_row.object_key,
    'kind', v_row.kind,
    'mime', v_row.mime,
    'byte_size', v_row.byte_size,
    'sha256', v_row.sha256,
    'width', v_row.width,
    'height', v_row.height,
    'replayed', v_replayed
  );
end;
$fn$;

revoke all on function public.record_r2_media_object_v1(uuid, uuid, text, text, bigint, text, text)
  from public, anon, authenticated;
do $r2_grant$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.record_r2_media_object_v1(uuid, uuid, text, text, bigint, text, text) to service_role';
  end if;
end;
$r2_grant$;

-- 2. Shop images: require a verified R2 object; close inline bytes ----------

create or replace function public.record_shop_image_v1(
  p_object_key text,
  p_sha256 text,
  p_mime text,
  p_width integer,
  p_height integer,
  p_byte_size integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.require_owned_shop();
  v_media public.r2_media_objects%rowtype;
  v_asset public.shop_image_assets%rowtype;
  v_at timestamptz := pg_catalog.clock_timestamp();
  v_replayed boolean := false;
begin
  if p_object_key is null or p_sha256 is null or p_mime is null
    or p_width is null or p_height is null or p_byte_size is null then
    raise exception 'logo_rejected';
  end if;
  select * into v_media from public.r2_media_objects where object_key = p_object_key;
  if not found then
    raise exception 'logo_not_uploaded';
  end if;
  if v_media.shop_id is distinct from v_shop
    or v_media.kind is distinct from 'shop_image'
    or v_media.uploaded_by is distinct from auth.uid()
    or v_media.sha256 is distinct from p_sha256
    or v_media.mime is distinct from p_mime
    or v_media.width is distinct from p_width
    or v_media.height is distinct from p_height
    or v_media.byte_size is distinct from p_byte_size then
    raise exception 'logo_mismatch';
  end if;
  select * into v_asset
  from public.shop_image_assets
  where shop_id = v_shop and sha256 = v_media.sha256;
  if found then
    if v_asset.storage is distinct from 'r2'
      or v_asset.object_key is distinct from v_media.object_key then
      raise exception 'logo_mismatch';
    end if;
    v_replayed := true;
  else
    insert into public.shop_image_assets (
      shop_id, sha256, mime, width, height, byte_size,
      content, object_key, storage, actor_user_id, created_at
    ) values (
      v_shop, v_media.sha256, v_media.mime, v_media.width, v_media.height,
      v_media.byte_size, null, v_media.object_key, 'r2', auth.uid(), v_at
    )
    returning * into v_asset;
  end if;
  update public.shops
  set image_asset_id = v_asset.id
  where id = v_shop;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'asset_id', v_asset.id,
    'sha256', v_asset.sha256,
    'mime', v_asset.mime,
    'width', v_asset.width,
    'height', v_asset.height,
    'byte_size', v_asset.byte_size,
    'object_key', v_asset.object_key,
    'storage', 'r2',
    'replayed', v_replayed
  );
end;
$fn$;

revoke all on function public.set_shop_image_v1(text) from public, anon, authenticated;

-- 3. Invoice logos: R2-backed assets, verified confirm, R2 reads ------------

alter table public.invoice_logo_assets
  add column object_key text,
  add column storage text not null default 'postgres';
alter table public.invoice_logo_assets
  alter column content drop not null;
alter table public.invoice_logo_assets
  add constraint invoice_logo_assets_storage_check
    check (storage in ('postgres', 'r2')),
  add constraint invoice_logo_assets_backing_check check (
    (storage = 'postgres' and content is not null and object_key is null)
    or (storage = 'r2' and content is null and object_key is not null)
  ),
  add constraint invoice_logo_assets_object_key_check check (
    object_key is null
    or object_key = 'invoice-logo/' || shop_id::text || '/' || sha256 || '.'
      || case mime when 'image/png' then 'png' else 'jpg' end
  );

create or replace function private.invoice_logo_asset_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.storage = 'r2' then
    if new.content is not null or new.object_key is null or not exists (
      select 1 from public.r2_media_objects as media
      where media.object_key = new.object_key
        and media.shop_id = new.shop_id
        and media.kind = 'invoice_logo'
        and media.sha256 = new.sha256
        and media.byte_size = new.byte_size
    ) then
      raise exception 'logo_rejected';
    end if;
    return new;
  end if;
  if new.content is null
    or pg_catalog.encode(extensions.digest(new.content, 'sha256'), 'hex') is distinct from new.sha256
    or pg_catalog.octet_length(new.content) is distinct from new.byte_size then
    raise exception 'logo_rejected';
  end if;
  return new;
end;
$fn$;

create function public.confirm_invoice_logo_v2(p_object_key text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_media public.r2_media_objects%rowtype;
  v_asset public.invoice_logo_assets%rowtype;
  v_at timestamptz := pg_catalog.clock_timestamp();
  v_existed boolean := false;
begin
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  if p_object_key is null then
    raise exception 'logo_rejected';
  end if;
  select * into v_media from public.r2_media_objects where object_key = p_object_key;
  if not found then
    raise exception 'logo_not_uploaded';
  end if;
  if v_media.shop_id is distinct from v_shop
    or v_media.kind is distinct from 'invoice_logo'
    or v_media.uploaded_by is distinct from auth.uid() then
    raise exception 'logo_mismatch';
  end if;
  select * into v_asset
  from public.invoice_logo_assets
  where shop_id = v_shop and sha256 = v_media.sha256;
  if found then
    if v_asset.mime is distinct from v_media.mime
      or v_asset.width is distinct from v_media.width
      or v_asset.height is distinct from v_media.height then
      raise exception 'logo_mismatch';
    end if;
    v_existed := true;
  else
    insert into public.invoice_logo_assets (
      shop_id, sha256, mime, width, height, byte_size, content,
      object_key, storage, actor_user_id, created_at
    ) values (
      v_shop, v_media.sha256, v_media.mime, v_media.width, v_media.height,
      v_media.byte_size, null, v_media.object_key, 'r2', auth.uid(), v_at
    )
    returning * into v_asset;
  end if;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'asset_id', v_asset.id,
    'sha256', v_asset.sha256,
    'mime', v_asset.mime,
    'width', v_asset.width,
    'height', v_asset.height,
    'byte_size', v_asset.byte_size,
    'confirmed', true,
    'replayed', v_existed,
    'cash_piastres', '0',
    'gold_milligrams', '0',
    'stock_milligrams', '0',
    'invoice_effect', false,
    'dispatch_effect', false
  );
end;
$fn$;

revoke all on function public.confirm_invoice_logo_v2(text) from public, anon, authenticated;
grant execute on function public.confirm_invoice_logo_v2(text) to authenticated;
revoke all on function public.confirm_invoice_logo_v1(text) from public, anon, authenticated;

-- Branded copies: R2 logos return the object key; the client downloads it with
-- a presigned read and checks the bytes against logo_sha256 before rendering.
create or replace function public.get_invoice_presentation_v1(p_operation_id uuid, p_edition bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_row public.invoice_presentation_revisions%rowtype;
  v_facts jsonb;
  v_asset public.invoice_logo_assets%rowtype;
  v_zone text;
  v_logo_state text;
  v_logo text;
  v_logo_key text;
begin
  if p_operation_id is null or p_edition is null or p_edition < 1 then
    raise exception 'invalid_input';
  end if;
  select * into v_row
  from public.invoice_presentation_revisions
  where shop_id = v_shop and operation_id = p_operation_id and edition = p_edition;
  if not found then
    raise exception 'not_found';
  end if;
  v_facts := private.invoice_operation_facts(v_shop, p_operation_id);
  select time_zone into v_zone from public.shops where id = v_shop;
  v_logo_state := 'absent';
  v_logo := null;
  v_logo_key := null;
  if v_row.logo_asset_id is not null then
    select * into v_asset
    from public.invoice_logo_assets
    where shop_id = v_shop and id = v_row.logo_asset_id;
    if not found or v_asset.sha256 is distinct from v_row.logo_sha256 then
      v_logo_state := 'unverified';
    elsif v_asset.storage = 'r2' then
      if exists (
        select 1 from public.r2_media_objects as media
        where media.object_key = v_asset.object_key
          and media.shop_id = v_shop
          and media.sha256 = v_row.logo_sha256
      ) then
        v_logo_state := 'verified';
        v_logo_key := v_asset.object_key;
      else
        v_logo_state := 'unverified';
      end if;
    elsif pg_catalog.encode(extensions.digest(v_asset.content, 'sha256'), 'hex') is distinct from v_row.logo_sha256 then
      v_logo_state := 'unverified';
    else
      v_logo_state := 'verified';
      v_logo := pg_catalog.encode(v_asset.content, 'base64');
    end if;
  end if;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'operation_id', p_operation_id,
    'edition', v_row.edition::text,
    'content_sha256', v_row.content_sha256,
    'content_matches', (v_facts ->> 'content_sha256') = v_row.content_sha256,
    'appearance_revision', v_row.appearance_revision::text,
    'template', v_row.template,
    'accent', v_row.accent,
    'slogan', v_row.slogan,
    'address', v_row.address,
    'logo_asset_id', v_row.logo_asset_id,
    'logo_sha256', v_row.logo_sha256,
    'logo_state', v_logo_state,
    'logo_bytes', v_logo,
    'logo_object_key', v_logo_key,
    'render_version', v_row.render_version,
    'actor_user_id', v_row.actor_user_id,
    'created_at', pg_catalog.to_char(v_row.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'created_at_shop', pg_catalog.to_char(v_row.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'shop_name', v_facts ->> 'shop_name',
    'shop_sequence', v_facts ->> 'shop_sequence',
    'kind', v_facts ->> 'kind',
    'time_zone', v_zone,
    'occurred_at', v_facts ->> 'occurred_at',
    'occurred_at_shop', v_facts ->> 'occurred_at_shop',
    'payload', v_facts -> 'payload',
    'can_write', private.can_write_shop(v_shop)
  );
end;
$fn$;

-- 4. Daily note images: R2 attachments --------------------------------------

alter table public.daily_note_attachments
  drop constraint daily_note_attachments_bucket_check;
alter table public.daily_note_attachments
  add constraint daily_note_attachments_bucket_check
    check (bucket_id in ('eldafttar-private-notes', 'cloudflare-r2'));

create or replace function public.post_daily_note(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_recheck uuid;
  v_actor uuid;
  v_day uuid;
  v_requested_day uuid;
  v_text text;
  v_attachment jsonb;
  v_client uuid;
  v_mime text;
  v_extension text;
  v_size_text text;
  v_size bigint;
  v_canonical jsonb;
  v_hash bytea;
  v_request public.financial_command_requests%rowtype;
  v_existing_kind text;
  v_existing_sequence bigint;
  v_existing_day uuid;
  v_path text;
  v_media public.r2_media_objects%rowtype;
  v_at timestamptz;
  v_sequence bigint;
  v_operation uuid;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_idempotency_key is null or jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  if exists (
    select 1
    from jsonb_object_keys(p_payload) as key
    where key not in ('version', 'kind', 'business_day_id', 'text', 'attachment')
  ) then
    raise exception 'invalid_input';
  end if;
  if (p_payload -> 'version') is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'daily_note'
    or jsonb_typeof(p_payload -> 'text') is distinct from 'string'
    or jsonb_typeof(p_payload -> 'business_day_id') is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  begin
    v_requested_day := (p_payload ->> 'business_day_id')::uuid;
  exception
    when invalid_text_representation then
      raise exception 'invalid_input';
  end;
  v_text := btrim(p_payload ->> 'text');
  if char_length(v_text) > 4000 then
    raise exception 'overflow';
  end if;
  if translate(v_text, E'\n\r\t', '') ~ '[[:cntrl:]]' then
    raise exception 'invalid_input';
  end if;
  if jsonb_typeof(p_payload -> 'attachment') = 'null' then
    v_attachment := null;
  elsif jsonb_typeof(p_payload -> 'attachment') = 'object' then
    if exists (
      select 1
      from jsonb_object_keys(p_payload -> 'attachment') as key
      where key not in ('client_object_id', 'mime_type', 'byte_size', 'extension')
    ) then
      raise exception 'invalid_input';
    end if;
    if jsonb_typeof(p_payload -> 'attachment' -> 'client_object_id') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'attachment' -> 'mime_type') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'attachment' -> 'byte_size') is distinct from 'string'
      or jsonb_typeof(p_payload -> 'attachment' -> 'extension') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    begin
      v_client := (p_payload -> 'attachment' ->> 'client_object_id')::uuid;
    exception
      when invalid_text_representation then
        raise exception 'invalid_input';
    end;
    v_mime := p_payload -> 'attachment' ->> 'mime_type';
    v_extension := private.note_mime_extension(v_mime);
    if v_extension is null
      or p_payload -> 'attachment' ->> 'extension' is distinct from v_extension then
      raise exception 'attachment_rejected';
    end if;
    v_size_text := p_payload -> 'attachment' ->> 'byte_size';
    v_size := private.parse_optional_sequence(v_size_text);
    if v_size is null or v_size > 5242880 then
      raise exception 'attachment_rejected';
    end if;
    v_attachment := jsonb_build_object(
      'byte_size', v_size::text,
      'client_object_id', v_client::text,
      'extension', v_extension,
      'mime_type', v_mime
    );
  else
    raise exception 'invalid_input';
  end if;
  if v_text = '' and v_attachment is null then
    raise exception 'note_empty';
  end if;
  v_canonical := jsonb_build_object(
    'attachment', coalesce(v_attachment, 'null'::jsonb),
    'business_day_id', v_requested_day::text,
    'kind', 'daily_note',
    'text', v_text,
    'version', 1
  );
  v_shop := private.opening_require_reader_shop();
  perform 1
  from public.shops as shop
  where shop.id = v_shop
  for update;
  v_recheck := private.opening_require_reader_shop();
  if v_recheck is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select request.*
    into v_request
  from public.financial_command_requests as request
  where request.shop_id = v_shop
    and request.idempotency_key = p_idempotency_key
  for update;
  v_hash := extensions.digest(convert_to(v_canonical::text, 'UTF8'), 'sha256');
  if v_request.id is not null then
    select operation.kind, operation.shop_sequence, operation.business_day_id
      into v_existing_kind, v_existing_sequence, v_existing_day
    from public.financial_operations as operation
    where operation.shop_id = v_shop
      and operation.id = v_request.operation_id;
    if v_existing_kind is distinct from 'daily_note'
      or v_existing_day is null
      or v_request.payload_canonical is distinct from v_canonical
      or v_request.payload_sha256 is distinct from v_hash then
      raise exception 'payload_mismatch';
    end if;
    return jsonb_build_object(
      'ok', true,
      'note_id', v_request.operation_id,
      'operation_id', v_request.operation_id,
      'business_day_id', v_existing_day,
      'shop_sequence', v_existing_sequence::text,
      'replayed', true
    );
  end if;
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
  select day.id
    into v_day
  from public.business_days as day
  where day.shop_id = v_shop
    and day.status = 'open'
  for update;
  if v_day is null then
    raise exception 'day_closed';
  end if;
  if v_day is distinct from v_requested_day then
    raise exception 'stale_day';
  end if;
  v_actor := auth.uid();
  v_at := pg_catalog.clock_timestamp();
  if v_attachment is not null then
    v_path := v_shop::text || '/' || v_day::text || '/' || v_client::text || '.' || v_extension;
    select media.* into v_media
    from public.r2_media_objects as media
    where media.object_key = 'note-image/' || v_path;
    if not found then
      raise exception 'attachment_missing';
    end if;
    if v_media.shop_id is distinct from v_shop
      or v_media.kind is distinct from 'note_image'
      or v_media.uploaded_by is distinct from v_actor
      or v_media.mime is distinct from v_mime
      or v_media.byte_size is distinct from v_size then
      raise exception 'attachment_rejected';
    end if;
    if exists (
      select 1
      from public.daily_note_attachments as attachment
      where attachment.object_name = v_path
        or (attachment.shop_id = v_shop and attachment.client_object_id = v_client)
    ) then
      raise exception 'attachment_rejected';
    end if;
  end if;
  select coalesce(max(operation.shop_sequence), 0) + 1
    into v_sequence
  from public.financial_operations as operation
  where operation.shop_id = v_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (
    v_shop, v_sequence, 'daily_note', v_day, v_actor, v_at
  ) returning id into v_operation;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (
    v_operation, v_shop, v_canonical, v_at
  );
  if v_attachment is not null then
    insert into public.daily_note_attachments (
      operation_id, shop_id, business_day_id, bucket_id, object_name,
      mime_type, byte_size, client_object_id, created_at
    ) values (
      v_operation, v_shop, v_day, 'cloudflare-r2', v_path,
      v_mime, v_size, v_client, v_at
    );
  end if;
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    v_shop, v_actor, 'daily_note_recorded', v_operation, v_at,
    jsonb_build_object(
      'business_day_id', v_day,
      'operation_id', v_operation,
      'has_attachment', v_attachment is not null
    )
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (
    v_shop, v_operation, 'daily_note_recorded', v_at
  );
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (
    v_shop, p_idempotency_key, v_canonical, v_hash, v_operation, v_at
  );
  return jsonb_build_object(
    'ok', true,
    'note_id', v_operation,
    'operation_id', v_operation,
    'business_day_id', v_day,
    'shop_sequence', v_sequence::text,
    'replayed', false
  );
end;
$fn$;

-- 5. Close new Supabase Storage writes; legacy note reads keep their policy --

drop policy if exists eldafttar_private_notes_insert on storage.objects;
drop policy if exists eldafttar_private_invoice_logos_insert on storage.objects;

commit;

notify pgrst, 'reload schema';

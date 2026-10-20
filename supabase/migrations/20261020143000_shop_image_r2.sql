-- Move shop images to Cloudflare R2 (presigned uploads/reads via the r2-media
-- Edge Function). New saves store only the R2 object key and verified metadata;
-- bytes no longer travel through Postgres. Legacy rows that still hold inline
-- bytes remain readable so previously saved images keep showing.

alter table public.shop_image_assets
  add column if not exists object_key text,
  add column if not exists storage text not null default 'postgres';

alter table public.shop_image_assets
  alter column content drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'shop_image_assets_storage_check'
  ) then
    alter table public.shop_image_assets
      add constraint shop_image_assets_storage_check
      check (storage in ('postgres', 'r2'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'shop_image_assets_backing_check'
  ) then
    alter table public.shop_image_assets
      add constraint shop_image_assets_backing_check check (
        (storage = 'postgres' and content is not null and object_key is null)
        or (storage = 'r2' and content is null and object_key is not null)
      );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'shop_image_assets_object_key_check'
  ) then
    alter table public.shop_image_assets
      add constraint shop_image_assets_object_key_check check (
        object_key is null
        or object_key ~ ('^shop-image/' || shop_id::text
          || '/[0-9a-f]{64}[.](jpg|png)$')
      );
  end if;
end $$;

-- Append-only guard now accepts R2-backed rows (null content, present key).
create or replace function private.shop_image_assets_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    raise exception 'append_only';
  end if;
  if new.storage = 'postgres' then
    if new.content is null
      or new.byte_size is distinct from pg_catalog.octet_length(new.content) then
      raise exception 'logo_mismatch';
    end if;
  else
    if new.object_key is null or new.content is not null then
      raise exception 'logo_mismatch';
    end if;
  end if;
  return new;
end;
$fn$;

-- Record a confirmed R2 upload. The client has already PUT the bytes to the
-- content-addressed key issued by the r2-media function; this binds that key to
-- the owner's shop and makes it the current image. Idempotent per (shop, sha).
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
  v_asset public.shop_image_assets%rowtype;
  v_ext text;
  v_expected text;
  v_at timestamptz := pg_catalog.clock_timestamp();
  v_replayed boolean := false;
begin
  if p_object_key is null or p_sha256 is null or p_mime is null
    or p_width is null or p_height is null or p_byte_size is null then
    raise exception 'logo_rejected';
  end if;
  if p_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'logo_rejected';
  end if;
  if p_mime not in ('image/png', 'image/jpeg') then
    raise exception 'logo_rejected';
  end if;
  if p_width < 1 or p_width > 2048 or p_height < 1 or p_height > 2048 then
    raise exception 'logo_rejected';
  end if;
  if p_byte_size < 1 or p_byte_size > 2097152 then
    raise exception 'image_too_large';
  end if;
  v_ext := case when p_mime = 'image/png' then 'png' else 'jpg' end;
  v_expected := 'shop-image/' || v_shop::text || '/' || p_sha256 || '.' || v_ext;
  if p_object_key is distinct from v_expected then
    raise exception 'logo_mismatch';
  end if;
  select * into v_asset
  from public.shop_image_assets
  where shop_id = v_shop and sha256 = p_sha256;
  if found then
    if v_asset.storage is distinct from 'r2'
      or v_asset.object_key is distinct from p_object_key
      or v_asset.mime is distinct from p_mime
      or v_asset.width is distinct from p_width
      or v_asset.height is distinct from p_height then
      raise exception 'logo_mismatch';
    end if;
    v_replayed := true;
  else
    insert into public.shop_image_assets (
      shop_id, sha256, mime, width, height, byte_size,
      content, object_key, storage, actor_user_id, created_at
    ) values (
      v_shop, p_sha256, p_mime, p_width, p_height, p_byte_size,
      null, p_object_key, 'r2', auth.uid(), v_at
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

-- Reads expose the storage kind. R2 rows return the object key for a presigned
-- read; legacy Postgres rows still return inline base64.
create or replace function public.get_shop_image_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.require_owned_shop();
  v_asset public.shop_image_assets%rowtype;
  v_ref uuid;
begin
  select image_asset_id into v_ref from public.shops where id = v_shop;
  if v_ref is null then
    return pg_catalog.jsonb_build_object(
      'version', 1, 'shop_id', v_shop, 'present', false
    );
  end if;
  select * into v_asset
  from public.shop_image_assets
  where shop_id = v_shop and id = v_ref;
  if not found then
    return pg_catalog.jsonb_build_object(
      'version', 1, 'shop_id', v_shop, 'present', false
    );
  end if;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'present', true,
    'asset_id', v_asset.id,
    'sha256', v_asset.sha256,
    'mime', v_asset.mime,
    'width', v_asset.width,
    'height', v_asset.height,
    'byte_size', v_asset.byte_size,
    'storage', v_asset.storage,
    'object_key', v_asset.object_key,
    'content_base64', case
      when v_asset.storage = 'postgres'
      then pg_catalog.encode(v_asset.content, 'base64')
      else null
    end
  );
end;
$fn$;

revoke all on function public.record_shop_image_v1(text, text, text, integer, integer, integer)
  from public, anon;
grant execute on function public.record_shop_image_v1(text, text, text, integer, integer, integer)
  to authenticated;

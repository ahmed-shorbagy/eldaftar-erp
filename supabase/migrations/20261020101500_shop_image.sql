-- Optional shop image for the ledger header and owner profile.
-- Distinct from invoice logos (ADR 0021). Owner membership may write while
-- entitlement is still pending so signup can attach an image immediately.

create table public.shop_image_assets (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id) on delete cascade,
  sha256 text not null,
  mime text not null,
  width integer not null,
  height integer not null,
  byte_size integer not null,
  content bytea not null,
  actor_user_id uuid not null references auth.users (id),
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint shop_image_assets_shop_id_id_key unique (shop_id, id),
  constraint shop_image_assets_shop_sha_key unique (shop_id, sha256),
  constraint shop_image_assets_sha_check check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint shop_image_assets_mime_check check (mime in ('image/png', 'image/jpeg')),
  constraint shop_image_assets_dimensions_check check (
    width between 1 and 2048 and height between 1 and 2048
  ),
  constraint shop_image_assets_size_check check (byte_size between 1 and 2097152)
);

create index shop_image_assets_shop_created_idx
  on public.shop_image_assets (shop_id, created_at desc);

alter table public.shops
  add column if not exists image_asset_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'shops_image_asset_fkey'
  ) then
    alter table public.shops
      add constraint shops_image_asset_fkey
      foreign key (id, image_asset_id)
      references public.shop_image_assets (shop_id, id)
      deferrable initially deferred;
  end if;
end $$;

create function private.shop_image_assets_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'UPDATE' or tg_op = 'DELETE' then
    raise exception 'append_only';
  end if;
  if new.byte_size is distinct from pg_catalog.octet_length(new.content) then
    raise exception 'logo_mismatch';
  end if;
  return new;
end;
$fn$;

create trigger shop_image_assets_guard
  before insert or update or delete on public.shop_image_assets
  for each row execute function private.shop_image_assets_guard();

alter table public.shop_image_assets enable row level security;
alter table public.shop_image_assets force row level security;
revoke all on public.shop_image_assets from public, anon, authenticated;
grant select on public.shop_image_assets to authenticated;

create policy shop_image_assets_owner_read on public.shop_image_assets
  for select to authenticated
  using (
    private.caller_session_accepted()
    and exists (
      select 1
      from public.shop_memberships as membership
      where membership.shop_id = shop_image_assets.shop_id
        and membership.user_id = auth.uid()
        and membership.role = 'owner'
        and membership.revoked_at is null
    )
  );

create function private.require_owned_shop()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_user uuid := auth.uid();
  v_shop uuid;
begin
  if v_user is null then
    raise exception 'unauthenticated';
  end if;
  if not private.caller_session_accepted() then
    raise exception 'session_expired';
  end if;
  if not exists (
    select 1
    from auth.users as identity
    where identity.id = v_user
      and coalesce(identity.is_anonymous, false) = false
      and identity.deleted_at is null
  ) then
    raise exception 'forbidden';
  end if;
  select ownership.shop_id
    into v_shop
  from public.shop_memberships as ownership
  where ownership.user_id = v_user
    and ownership.role = 'owner'
    and ownership.revoked_at is null;
  if v_shop is null then
    raise exception 'forbidden';
  end if;
  return v_shop;
end;
$fn$;

revoke all on function private.require_owned_shop() from public, anon;
grant execute on function private.require_owned_shop() to authenticated;

create or replace function public.set_shop_image_v1(p_bytes text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.require_owned_shop();
  v_raw bytea;
  v_fact record;
  v_sha text;
  v_asset public.shop_image_assets%rowtype;
  v_at timestamptz := pg_catalog.clock_timestamp();
  v_replayed boolean := false;
begin
  if p_bytes is null then
    raise exception 'logo_rejected';
  end if;
  if pg_catalog.char_length(p_bytes) > 2796204 then
    raise exception 'image_too_large';
  end if;
  if pg_catalog.char_length(p_bytes) = 0
    or pg_catalog.char_length(p_bytes) % 4 <> 0
    or p_bytes !~ '^[A-Za-z0-9+/]*={0,2}$' then
    raise exception 'logo_rejected';
  end if;
  begin
    v_raw := pg_catalog.decode(p_bytes, 'base64');
  exception
    when others then
      raise exception 'logo_rejected';
  end;
  if v_raw is null
    or pg_catalog.octet_length(v_raw) = 0
    or pg_catalog.octet_length(v_raw) > 2097152 then
    raise exception 'image_too_large';
  end if;
  select * into v_fact from private.invoice_logo_facts(v_raw, true);
  v_sha := pg_catalog.encode(extensions.digest(v_raw, 'sha256'), 'hex');
  select * into v_asset
  from public.shop_image_assets
  where shop_id = v_shop and sha256 = v_sha;
  if found then
    if v_asset.content is distinct from v_raw
      or v_asset.mime is distinct from v_fact.mime
      or v_asset.width is distinct from v_fact.width
      or v_asset.height is distinct from v_fact.height then
      raise exception 'logo_mismatch';
    end if;
    v_replayed := true;
  else
    insert into public.shop_image_assets (
      shop_id, sha256, mime, width, height, byte_size, content, actor_user_id, created_at
    ) values (
      v_shop, v_sha, v_fact.mime, v_fact.width, v_fact.height,
      pg_catalog.octet_length(v_raw), v_raw, auth.uid(), v_at
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
    'replayed', v_replayed
  );
end;
$fn$;

create or replace function public.clear_shop_image_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.require_owned_shop();
begin
  update public.shops
  set image_asset_id = null
  where id = v_shop;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'cleared', true
  );
end;
$fn$;

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
      'version', 1,
      'shop_id', v_shop,
      'present', false
    );
  end if;
  select * into v_asset
  from public.shop_image_assets
  where shop_id = v_shop and id = v_ref;
  if not found then
    return pg_catalog.jsonb_build_object(
      'version', 1,
      'shop_id', v_shop,
      'present', false
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
    'content_base64', pg_catalog.encode(v_asset.content, 'base64')
  );
end;
$fn$;

revoke all on function public.set_shop_image_v1(text) from public, anon;
revoke all on function public.clear_shop_image_v1() from public, anon;
revoke all on function public.get_shop_image_v1() from public, anon;
grant execute on function public.set_shop_image_v1(text) to authenticated;
grant execute on function public.clear_shop_image_v1() to authenticated;
grant execute on function public.get_shop_image_v1() to authenticated;

drop function if exists public.list_my_shop_accounts();

create function public.list_my_shop_accounts()
returns table (
  shop_id uuid,
  shop_name text,
  member_role text,
  subscription_expires_at timestamptz,
  entitlement_status text,
  shop_image_sha256 text
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    shop.id,
    shop.name,
    'owner'::text,
    entitlement.expires_at,
    case
      when entitlement.shop_id is null or now() < entitlement.starts_at then 'pending'
      when entitlement.starts_at <= now() and now() < entitlement.expires_at then 'active'
      else 'expired'
    end,
    asset.sha256
  from public.shop_memberships as ownership
  join public.shops as shop on shop.id = ownership.shop_id
  left join public.shop_entitlements as entitlement on entitlement.shop_id = shop.id
  left join public.shop_image_assets as asset
    on asset.shop_id = shop.id
   and asset.id = shop.image_asset_id
  where ownership.user_id = auth.uid()
    and ownership.role = 'owner'
    and ownership.revoked_at is null
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
    )
  order by shop.created_at;
$function$;

revoke all on function public.list_my_shop_accounts() from public, anon;
grant execute on function public.list_my_shop_accounts() to authenticated;

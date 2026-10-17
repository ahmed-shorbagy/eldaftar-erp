-- SET-03 and the appearance portion of DOC-01.
-- Owner invoice appearance and immutable branded presentation copies.
-- Does not close wider D12, SET-04, DOC-04, legal or tax fields, or Milestone 4.
begin;

alter table public.shop_sync_signals
  add column appearance_revision bigint not null default 0
  check (appearance_revision >= 0);

create or replace function private.bump_shop_sync(p_shop_id uuid, p_scope text)
returns void
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if p_shop_id is null or p_scope is null then
    return;
  end if;
  if not exists (select 1 from public.shops as shop where shop.id = p_shop_id) then
    return;
  end if;
  insert into public.shop_sync_signals (
    shop_id, revision, ledger_revision, inventory_revision, trader_revision,
    invoice_revision, day_revision, location_revision, subscription_revision,
    repair_revision, debt_revision, customer_revision, appearance_revision, updated_at
  ) values (
    p_shop_id, 1,
    case when p_scope = 'ledger' then 1 else 0 end,
    case when p_scope = 'inventory' then 1 else 0 end,
    case when p_scope = 'trader' then 1 else 0 end,
    case when p_scope = 'invoice' then 1 else 0 end,
    case when p_scope = 'day' then 1 else 0 end,
    case when p_scope = 'location' then 1 else 0 end,
    case when p_scope = 'subscription' then 1 else 0 end,
    case when p_scope = 'repair' then 1 else 0 end,
    case when p_scope = 'debt' then 1 else 0 end,
    case when p_scope = 'customer' then 1 else 0 end,
    case when p_scope = 'appearance' then 1 else 0 end,
    pg_catalog.clock_timestamp()
  )
  on conflict (shop_id) do update
    set revision = public.shop_sync_signals.revision + 1,
        ledger_revision = public.shop_sync_signals.ledger_revision
          + case when p_scope = 'ledger' then 1 else 0 end,
        inventory_revision = public.shop_sync_signals.inventory_revision
          + case when p_scope = 'inventory' then 1 else 0 end,
        trader_revision = public.shop_sync_signals.trader_revision
          + case when p_scope = 'trader' then 1 else 0 end,
        invoice_revision = public.shop_sync_signals.invoice_revision
          + case when p_scope = 'invoice' then 1 else 0 end,
        day_revision = public.shop_sync_signals.day_revision
          + case when p_scope = 'day' then 1 else 0 end,
        location_revision = public.shop_sync_signals.location_revision
          + case when p_scope = 'location' then 1 else 0 end,
        subscription_revision = public.shop_sync_signals.subscription_revision
          + case when p_scope = 'subscription' then 1 else 0 end,
        repair_revision = public.shop_sync_signals.repair_revision
          + case when p_scope = 'repair' then 1 else 0 end,
        debt_revision = public.shop_sync_signals.debt_revision
          + case when p_scope = 'debt' then 1 else 0 end,
        customer_revision = public.shop_sync_signals.customer_revision
          + case when p_scope = 'customer' then 1 else 0 end,
        appearance_revision = public.shop_sync_signals.appearance_revision
          + case when p_scope = 'appearance' then 1 else 0 end,
        updated_at = pg_catalog.clock_timestamp();
end;
$fn$;

create or replace function private.shop_sync_touch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_scope text;
begin
  if tg_table_name = 'shops' then
    if tg_op = 'DELETE' then
      return old;
    end if;
    v_shop := new.id;
  elsif tg_op = 'DELETE' then
    v_shop := old.shop_id;
  else
    v_shop := new.shop_id;
  end if;
  v_scope := case tg_table_name
    when 'shops' then 'location'
    when 'shop_memberships' then 'location'
    when 'shop_entitlements' then 'subscription'
    when 'business_days' then 'day'
    when 'invoice_dispatch_confirmations' then 'invoice'
    when 'inventory_lots' then 'inventory'
    when 'inventory_lot_movements' then 'inventory'
    when 'inventory_receipts' then 'inventory'
    when 'inventory_lot_sync' then 'inventory'
    when 'inventory_products' then 'inventory'
    when 'bullion_denominations' then 'inventory'
    when 'coin_types' then 'inventory'
    when 'traders' then 'trader'
    when 'gold_obligations' then 'trader'
    when 'repairs' then 'repair'
    when 'repair_events' then 'repair'
    when 'repair_custody_events' then 'repair'
    when 'shop_debts' then 'debt'
    when 'debt_events' then 'debt'
    when 'customers' then 'customer'
    when 'customer_phones' then 'customer'
    when 'customer_notes' then 'customer'
    when 'customer_events' then 'customer'
    when 'customer_operation_links' then 'customer'
    when 'invoice_appearance_revisions' then 'appearance'
    when 'invoice_appearance_audits' then 'appearance'
    when 'invoice_appearance_requests' then 'appearance'
    when 'invoice_logo_assets' then 'appearance'
    when 'invoice_presentation_revisions' then 'appearance'
    when 'invoice_presentation_requests' then 'appearance'
    else 'ledger'
  end;
  perform private.bump_shop_sync(v_shop, v_scope);
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$fn$;

create table public.invoice_logo_assets (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  sha256 text not null,
  mime text not null,
  width integer not null,
  height integer not null,
  byte_size integer not null,
  content bytea not null,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  constraint invoice_logo_assets_shop_id_id_key unique (shop_id, id),
  constraint invoice_logo_assets_shop_sha_key unique (shop_id, sha256),
  constraint invoice_logo_assets_sha_check check (sha256 ~ '^[0-9a-f]{64}$'),
  constraint invoice_logo_assets_mime_check check (mime in ('image/png', 'image/jpeg')),
  constraint invoice_logo_assets_dimensions_check check (
    width between 1 and 2048 and height between 1 and 2048
  ),
  constraint invoice_logo_assets_size_check check (byte_size between 1 and 2097152),
  constraint invoice_logo_assets_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create table public.invoice_appearance_revisions (
  shop_id uuid not null references public.shops (id),
  revision bigint not null,
  template text not null,
  accent text not null,
  slogan text,
  address text,
  logo_asset_id uuid,
  logo_sha256 text,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  primary key (shop_id, revision),
  constraint invoice_appearance_revisions_revision_check check (revision >= 1),
  constraint invoice_appearance_revisions_template_check check (template in ('header', 'compact')),
  constraint invoice_appearance_revisions_accent_check check (accent in ('brown', 'gold', 'neutral')),
  constraint invoice_appearance_revisions_slogan_check check (
    slogan is null
    or (
      pg_catalog.char_length(slogan) between 1 and 120
      and slogan = pg_catalog.btrim(slogan)
      and slogan !~ E'[\\x00-\\x09\\x0B-\\x1F\\x7F]'
    )
  ),
  constraint invoice_appearance_revisions_address_check check (
    address is null
    or (
      pg_catalog.char_length(address) between 1 and 200
      and address = pg_catalog.btrim(address)
      and address !~ E'[\\x00-\\x09\\x0B-\\x1F\\x7F]'
      and (pg_catalog.length(address) - pg_catalog.length(pg_catalog.replace(address, E'\n', ''))) < 4
    )
  ),
  constraint invoice_appearance_revisions_logo_pair_check check (
    (logo_asset_id is null and logo_sha256 is null)
    or (logo_asset_id is not null and logo_sha256 ~ '^[0-9a-f]{64}$')
  ),
  constraint invoice_appearance_revisions_logo_fkey
    foreign key (shop_id, logo_asset_id)
    references public.invoice_logo_assets (shop_id, id),
  constraint invoice_appearance_revisions_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create table public.invoice_appearance_audits (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  revision bigint not null,
  before_json jsonb not null,
  after_json jsonb not null,
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  idempotency_key uuid not null,
  constraint invoice_appearance_audits_json_check check (
    pg_catalog.jsonb_typeof(before_json) = 'object'
    and pg_catalog.jsonb_typeof(after_json) = 'object'
  ),
  constraint invoice_appearance_audits_revision_fkey
    foreign key (shop_id, revision)
    references public.invoice_appearance_revisions (shop_id, revision),
  constraint invoice_appearance_audits_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);
create index invoice_appearance_audits_shop_idx
  on public.invoice_appearance_audits (shop_id, revision);

create table public.invoice_appearance_requests (
  shop_id uuid not null references public.shops (id),
  idempotency_key uuid not null,
  payload_canonical jsonb not null,
  result jsonb not null,
  created_at timestamptz not null,
  primary key (shop_id, idempotency_key),
  constraint invoice_appearance_requests_json_check check (
    pg_catalog.jsonb_typeof(payload_canonical) = 'object'
    and pg_catalog.jsonb_typeof(result) = 'object'
  )
);

create table public.invoice_presentation_revisions (
  shop_id uuid not null,
  operation_id uuid not null,
  edition bigint not null,
  content_sha256 text not null,
  appearance_revision bigint not null,
  template text not null,
  accent text not null,
  slogan text,
  address text,
  logo_asset_id uuid,
  logo_sha256 text,
  render_version integer not null,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  primary key (shop_id, operation_id, edition),
  constraint invoice_presentation_revisions_edition_check check (edition >= 1),
  constraint invoice_presentation_revisions_hash_check check (content_sha256 ~ '^[0-9a-f]{64}$'),
  constraint invoice_presentation_revisions_appearance_check check (appearance_revision >= 0),
  constraint invoice_presentation_revisions_template_check check (template in ('header', 'compact')),
  constraint invoice_presentation_revisions_accent_check check (accent in ('brown', 'gold', 'neutral')),
  constraint invoice_presentation_revisions_render_check check (render_version = 1),
  constraint invoice_presentation_revisions_slogan_check check (
    slogan is null
    or (
      pg_catalog.char_length(slogan) between 1 and 120
      and slogan = pg_catalog.btrim(slogan)
      and slogan !~ E'[\\x00-\\x09\\x0B-\\x1F\\x7F]'
    )
  ),
  constraint invoice_presentation_revisions_address_check check (
    address is null
    or (
      pg_catalog.char_length(address) between 1 and 200
      and address = pg_catalog.btrim(address)
      and address !~ E'[\\x00-\\x09\\x0B-\\x1F\\x7F]'
      and (pg_catalog.length(address) - pg_catalog.length(pg_catalog.replace(address, E'\n', ''))) < 4
    )
  ),
  constraint invoice_presentation_revisions_logo_pair_check check (
    (logo_asset_id is null and logo_sha256 is null)
    or (logo_asset_id is not null and logo_sha256 ~ '^[0-9a-f]{64}$')
  ),
  constraint invoice_presentation_revisions_operation_fkey
    foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint invoice_presentation_revisions_logo_fkey
    foreign key (shop_id, logo_asset_id)
    references public.invoice_logo_assets (shop_id, id),
  constraint invoice_presentation_revisions_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

create table public.invoice_presentation_requests (
  shop_id uuid not null references public.shops (id),
  idempotency_key uuid not null,
  payload_canonical jsonb not null,
  result jsonb not null,
  created_at timestamptz not null,
  primary key (shop_id, idempotency_key),
  constraint invoice_presentation_requests_json_check check (
    pg_catalog.jsonb_typeof(payload_canonical) = 'object'
    and pg_catalog.jsonb_typeof(result) = 'object'
  )
);

create function private.invoice_logo_asset_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if pg_catalog.encode(extensions.digest(new.content, 'sha256'), 'hex') is distinct from new.sha256
    or pg_catalog.octet_length(new.content) is distinct from new.byte_size then
    raise exception 'logo_rejected';
  end if;
  return new;
end;
$fn$;

create trigger invoice_logo_assets_guard
  before insert on public.invoice_logo_assets
  for each row execute function private.invoice_logo_asset_guard();

create function private.invoice_appearance_revision_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.logo_asset_id is null then
    if new.logo_sha256 is not null then
      raise exception 'invalid_input';
    end if;
  elsif not exists (
    select 1 from public.invoice_logo_assets as asset
    where asset.shop_id = new.shop_id
      and asset.id = new.logo_asset_id
      and asset.sha256 = new.logo_sha256
  ) then
    raise exception 'asset_missing';
  end if;
  return new;
end;
$fn$;

create trigger invoice_appearance_revisions_guard
  before insert on public.invoice_appearance_revisions
  for each row execute function private.invoice_appearance_revision_guard();

create function private.invoice_presentation_revision_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.appearance_revision > 0 and not exists (
    select 1 from public.invoice_appearance_revisions as appearance
    where appearance.shop_id = new.shop_id
      and appearance.revision = new.appearance_revision
  ) then
    raise exception 'stale_appearance';
  end if;
  if new.logo_asset_id is null then
    if new.logo_sha256 is not null then
      raise exception 'invalid_input';
    end if;
  elsif not exists (
    select 1 from public.invoice_logo_assets as asset
    where asset.shop_id = new.shop_id
      and asset.id = new.logo_asset_id
      and asset.sha256 = new.logo_sha256
  ) then
    raise exception 'asset_missing';
  end if;
  return new;
end;
$fn$;

create trigger invoice_presentation_revisions_guard
  before insert on public.invoice_presentation_revisions
  for each row execute function private.invoice_presentation_revision_guard();

create trigger invoice_logo_assets_append_only
  before update or delete on public.invoice_logo_assets
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_appearance_revisions_append_only
  before update or delete on public.invoice_appearance_revisions
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_appearance_audits_append_only
  before update or delete on public.invoice_appearance_audits
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_appearance_requests_append_only
  before update or delete on public.invoice_appearance_requests
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_presentation_revisions_append_only
  before update or delete on public.invoice_presentation_revisions
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_presentation_requests_append_only
  before update or delete on public.invoice_presentation_requests
  for each row execute function private.financial_audit_events_append_only();

alter table public.invoice_logo_assets enable row level security;
alter table public.invoice_logo_assets force row level security;
alter table public.invoice_appearance_revisions enable row level security;
alter table public.invoice_appearance_revisions force row level security;
alter table public.invoice_appearance_audits enable row level security;
alter table public.invoice_appearance_audits force row level security;
alter table public.invoice_appearance_requests enable row level security;
alter table public.invoice_appearance_requests force row level security;
alter table public.invoice_presentation_revisions enable row level security;
alter table public.invoice_presentation_revisions force row level security;
alter table public.invoice_presentation_requests enable row level security;
alter table public.invoice_presentation_requests force row level security;

revoke all on public.invoice_logo_assets, public.invoice_appearance_revisions,
  public.invoice_appearance_audits, public.invoice_appearance_requests,
  public.invoice_presentation_revisions, public.invoice_presentation_requests
  from public, anon, authenticated;
grant select on public.invoice_logo_assets, public.invoice_appearance_revisions,
  public.invoice_appearance_audits, public.invoice_appearance_requests,
  public.invoice_presentation_revisions, public.invoice_presentation_requests
  to authenticated;

create policy invoice_logo_assets_owner_read on public.invoice_logo_assets
  for select to authenticated using (private.opening_financial_visible(shop_id));
create policy invoice_appearance_revisions_owner_read on public.invoice_appearance_revisions
  for select to authenticated using (private.opening_financial_visible(shop_id));
create policy invoice_appearance_audits_owner_read on public.invoice_appearance_audits
  for select to authenticated using (private.opening_financial_visible(shop_id));
create policy invoice_appearance_requests_owner_read on public.invoice_appearance_requests
  for select to authenticated using (private.opening_financial_visible(shop_id));
create policy invoice_presentation_revisions_owner_read on public.invoice_presentation_revisions
  for select to authenticated using (private.opening_financial_visible(shop_id));
create policy invoice_presentation_requests_owner_read on public.invoice_presentation_requests
  for select to authenticated using (private.opening_financial_visible(shop_id));

do $appearance_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.invoice_logo_assets from service_role';
    execute 'revoke update, delete on table public.invoice_appearance_revisions from service_role';
    execute 'revoke update, delete on table public.invoice_appearance_audits from service_role';
    execute 'revoke update, delete on table public.invoice_appearance_requests from service_role';
    execute 'revoke update, delete on table public.invoice_presentation_revisions from service_role';
    execute 'revoke update, delete on table public.invoice_presentation_requests from service_role';
  end if;
end;
$appearance_revoke$;

create function private.invoice_optional_text(p_value jsonb, p_max integer, p_lines integer)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
begin
  if p_value is null or p_value = 'null'::jsonb then
    return null;
  end if;
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_text := pg_catalog.btrim(p_value #>> '{}');
  if v_text = ''
    or pg_catalog.regexp_replace(v_text, '[[:space:]]', '', 'g') = '' then
    return null;
  end if;
  if pg_catalog.char_length(v_text) > p_max
    or v_text ~ E'[\\x00-\\x09\\x0B-\\x1F\\x7F]'
    or (pg_catalog.length(v_text) - pg_catalog.length(pg_catalog.replace(v_text, E'\n', ''))) >= p_lines then
    raise exception 'invalid_input';
  end if;
  return v_text;
end;
$fn$;

create function private.invoice_logo_facts(p_bytes bytea, p_strict boolean)
returns table (mime text, width integer, height integer)
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_len integer := pg_catalog.octet_length(p_bytes);
  v_off integer;
  v_chunk bigint;
  v_dim bigint;
  v_type text;
  v_color integer := 0;
  v_depth integer;
  v_width integer := 0;
  v_height integer := 0;
  v_header boolean := false;
  v_data boolean := false;
  v_end boolean := false;
  v_palette boolean := false;
  v_frames integer := 0;
  v_marker integer;
  v_seg integer;
  v_at integer;
  v_entropy integer;
begin
  if p_bytes is null or v_len = 0 or v_len > 2097152 then
    raise exception 'image_too_large';
  end if;
  if v_len >= 8
    and pg_catalog.get_byte(p_bytes, 0) = 137
    and pg_catalog.get_byte(p_bytes, 1) = 80
    and pg_catalog.get_byte(p_bytes, 2) = 78
    and pg_catalog.get_byte(p_bytes, 3) = 71 then
    if pg_catalog.get_byte(p_bytes, 4) <> 13
      or pg_catalog.get_byte(p_bytes, 5) <> 10
      or pg_catalog.get_byte(p_bytes, 6) <> 26
      or pg_catalog.get_byte(p_bytes, 7) <> 10 then
      raise exception 'logo_rejected';
    end if;
    v_off := 8;
    while v_off < v_len loop
      if v_end or v_off + 12 > v_len then
        raise exception 'logo_rejected';
      end if;
      v_chunk := (pg_catalog.get_byte(p_bytes, v_off)::bigint << 24)
        + (pg_catalog.get_byte(p_bytes, v_off + 1)::bigint << 16)
        + (pg_catalog.get_byte(p_bytes, v_off + 2)::bigint << 8)
        + pg_catalog.get_byte(p_bytes, v_off + 3)::bigint;
      if v_chunk < 0 or v_off + 12 + v_chunk > v_len then
        raise exception 'logo_rejected';
      end if;
      v_type := pg_catalog.chr(pg_catalog.get_byte(p_bytes, v_off + 4))
        || pg_catalog.chr(pg_catalog.get_byte(p_bytes, v_off + 5))
        || pg_catalog.chr(pg_catalog.get_byte(p_bytes, v_off + 6))
        || pg_catalog.chr(pg_catalog.get_byte(p_bytes, v_off + 7));
      if v_type in ('acTL', 'fcTL', 'fdAT')
        or (p_strict and v_type not in ('IHDR', 'PLTE', 'tRNS', 'IDAT', 'IEND')) then
        raise exception 'logo_rejected';
      end if;
      if not v_header and v_type is distinct from 'IHDR' then
        raise exception 'logo_rejected';
      end if;
      if v_type = 'IHDR' then
        if v_header or v_chunk <> 13 then
          raise exception 'logo_rejected';
        end if;
        v_dim := (pg_catalog.get_byte(p_bytes, v_off + 8)::bigint << 24)
          + (pg_catalog.get_byte(p_bytes, v_off + 9)::bigint << 16)
          + (pg_catalog.get_byte(p_bytes, v_off + 10)::bigint << 8)
          + pg_catalog.get_byte(p_bytes, v_off + 11)::bigint;
        v_width := case when v_dim between 1 and 2048 then v_dim::integer else 0 end;
        v_dim := (pg_catalog.get_byte(p_bytes, v_off + 12)::bigint << 24)
          + (pg_catalog.get_byte(p_bytes, v_off + 13)::bigint << 16)
          + (pg_catalog.get_byte(p_bytes, v_off + 14)::bigint << 8)
          + pg_catalog.get_byte(p_bytes, v_off + 15)::bigint;
        v_height := case when v_dim between 1 and 2048 then v_dim::integer else 0 end;
        v_depth := pg_catalog.get_byte(p_bytes, v_off + 16);
        v_color := pg_catalog.get_byte(p_bytes, v_off + 17);
        if pg_catalog.get_byte(p_bytes, v_off + 18) <> 0
          or pg_catalog.get_byte(p_bytes, v_off + 19) <> 0
          or pg_catalog.get_byte(p_bytes, v_off + 20) not in (0, 1)
          or v_width < 1 or v_height < 1 or v_width > 2048 or v_height > 2048
          or (v_color = 0 and v_depth not in (1, 2, 4, 8, 16))
          or (v_color = 2 and v_depth not in (8, 16))
          or (v_color = 3 and v_depth not in (1, 2, 4, 8))
          or (v_color = 4 and v_depth not in (8, 16))
          or (v_color = 6 and v_depth not in (8, 16))
          or v_color not in (0, 2, 3, 4, 6) then
          raise exception 'logo_rejected';
        end if;
        v_header := true;
      elsif v_type = 'PLTE' then
        if v_palette or v_data or v_color not in (2, 3, 6)
          or v_chunk < 3 or v_chunk > 768 or v_chunk % 3 <> 0 then
          raise exception 'logo_rejected';
        end if;
        v_palette := true;
      elsif v_type = 'tRNS' then
        if not (
          (v_color = 0 and v_chunk = 2)
          or (v_color = 2 and v_chunk = 6)
          or (v_color = 3 and v_palette and v_chunk between 1 and 256)
        ) then
          raise exception 'logo_rejected';
        end if;
      elsif v_type = 'IDAT' then
        if v_chunk = 0 or (v_color = 3 and not v_palette) then
          raise exception 'logo_rejected';
        end if;
        v_data := true;
      elsif v_type = 'IEND' then
        if v_chunk <> 0 or not v_data then
          raise exception 'logo_rejected';
        end if;
        v_end := true;
      end if;
      v_off := v_off + 12 + v_chunk;
    end loop;
    if not v_end then
      raise exception 'logo_rejected';
    end if;
    mime := 'image/png';
    width := v_width;
    height := v_height;
    return next;
    return;
  end if;
  if v_len < 4
    or pg_catalog.get_byte(p_bytes, 0) <> 255
    or pg_catalog.get_byte(p_bytes, 1) <> 216 then
    raise exception 'logo_rejected';
  end if;
  v_off := 2;
  while v_off < v_len and not v_end loop
    if pg_catalog.get_byte(p_bytes, v_off) <> 255 then
      raise exception 'logo_rejected';
    end if;
    while v_off < v_len and pg_catalog.get_byte(p_bytes, v_off) = 255 loop
      v_off := v_off + 1;
    end loop;
    if v_off >= v_len then
      raise exception 'logo_rejected';
    end if;
    v_marker := pg_catalog.get_byte(p_bytes, v_off);
    v_off := v_off + 1;
    if v_marker = 216 then
      raise exception 'logo_rejected';
    end if;
    if v_marker = 217 then
      v_end := true;
      exit;
    end if;
    if v_marker = 1 or (v_marker between 208 and 215) then
      continue;
    end if;
    if v_off + 2 > v_len then
      raise exception 'logo_rejected';
    end if;
    v_seg := (pg_catalog.get_byte(p_bytes, v_off) << 8) + pg_catalog.get_byte(p_bytes, v_off + 1);
    if v_seg < 2 or v_off + v_seg > v_len then
      raise exception 'logo_rejected';
    end if;
    if v_marker = 225 and p_strict then
      raise exception 'logo_rejected';
    end if;
    if v_marker in (192, 194, 193, 195, 197, 198, 199, 201, 202, 203, 205, 206, 207) then
      if v_marker not in (192, 194) or v_frames > 0 or v_seg < 8 then
        raise exception 'logo_rejected';
      end if;
      v_height := (pg_catalog.get_byte(p_bytes, v_off + 3) << 8) + pg_catalog.get_byte(p_bytes, v_off + 4);
      v_width := (pg_catalog.get_byte(p_bytes, v_off + 5) << 8) + pg_catalog.get_byte(p_bytes, v_off + 6);
      if v_width < 1 or v_height < 1 or v_width > 2048 or v_height > 2048 then
        raise exception 'logo_rejected';
      end if;
      v_frames := v_frames + 1;
    end if;
    if v_marker = 218 then
      v_off := v_off + v_seg;
      while v_off < v_len loop
        if pg_catalog.get_byte(p_bytes, v_off) <> 255 then
          v_off := v_off + 1;
          continue;
        end if;
        v_at := v_off;
        while v_at < v_len and pg_catalog.get_byte(p_bytes, v_at) = 255 loop
          v_at := v_at + 1;
        end loop;
        if v_at >= v_len then
          raise exception 'logo_rejected';
        end if;
        v_entropy := pg_catalog.get_byte(p_bytes, v_at);
        if v_entropy = 0 then
          v_off := v_at + 1;
          continue;
        end if;
        if v_entropy = 217 then
          v_end := true;
          v_off := v_len;
          exit;
        end if;
        if v_entropy between 208 and 215 then
          v_off := v_at + 1;
          continue;
        end if;
        raise exception 'logo_rejected';
      end loop;
      exit;
    end if;
    v_off := v_off + v_seg;
  end loop;
  if not v_end or v_frames <> 1 then
    raise exception 'logo_rejected';
  end if;
  mime := 'image/jpeg';
  width := v_width;
  height := v_height;
  return next;
end;
$fn$;

create function private.invoice_appearance_fields(p_shop uuid, p_payload jsonb)
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
    or p_payload ->> 'template' not in ('header', 'compact')
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

create function private.invoice_current_appearance(p_shop uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce(
    (
      select jsonb_build_object(
        'revision', revision::text,
        'template', template,
        'accent', accent,
        'slogan', slogan,
        'address', address,
        'logo_asset_id', logo_asset_id,
        'logo_sha256', logo_sha256
      )
      from public.invoice_appearance_revisions
      where shop_id = p_shop
      order by revision desc
      limit 1
    ),
    jsonb_build_object(
      'revision', '0',
      'template', 'header',
      'accent', 'brown',
      'slogan', null,
      'address', null,
      'logo_asset_id', null,
      'logo_sha256', null
    )
  );
$fn$;

create function private.invoice_operation_facts(p_shop uuid, p_operation uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_op public.financial_operations%rowtype;
  v_payload jsonb;
  v_name text;
  v_zone text;
  v_canonical jsonb;
begin
  select * into v_op
  from public.financial_operations
  where shop_id = p_shop and id = p_operation;
  if not found then
    raise exception 'not_found';
  end if;
  if v_op.kind not in ('sale', 'purchase') then
    raise exception 'wrong_operation_kind';
  end if;
  select payload into v_payload
  from public.financial_operation_details
  where shop_id = p_shop and operation_id = p_operation;
  if v_payload is null or pg_catalog.jsonb_typeof(v_payload) is distinct from 'object' then
    raise exception 'not_found';
  end if;
  select name, time_zone into v_name, v_zone from public.shops where id = p_shop;
  v_canonical := pg_catalog.jsonb_build_object(
    'kind', v_op.kind,
    'occurred_at', pg_catalog.to_char(v_op.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'operation_id', v_op.id,
    'payload', v_payload,
    'shop_sequence', v_op.shop_sequence::text
  );
  return pg_catalog.jsonb_build_object(
    'operation_id', v_op.id,
    'kind', v_op.kind,
    'shop_sequence', v_op.shop_sequence::text,
    'shop_name', v_name,
    'time_zone', v_zone,
    'occurred_at', v_canonical ->> 'occurred_at',
    'occurred_at_shop', pg_catalog.to_char(v_op.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'payload', v_payload,
    'content_sha256', pg_catalog.encode(
      extensions.digest(pg_catalog.convert_to(v_canonical::text, 'UTF8'), 'sha256'),
      'hex'
    )
  );
end;
$fn$;

create function public.get_invoice_appearance_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_zone text;
  v_at timestamptz := pg_catalog.statement_timestamp();
  v_current jsonb;
begin
  select time_zone into v_zone from public.shops where id = v_shop;
  v_current := private.invoice_current_appearance(v_shop);
  return v_current || pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'can_write', private.can_write_shop(v_shop),
    'time_zone', v_zone,
    'read_at', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'read_at_shop', pg_catalog.to_char(v_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS')
  );
end;
$fn$;

create function public.review_invoice_appearance_v1(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_fields jsonb;
  v_current jsonb;
begin
  if pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  v_fields := private.invoice_appearance_fields(v_shop, p_payload);
  v_current := private.invoice_current_appearance(v_shop);
  if (v_fields ->> 'expected_revision') is distinct from (v_current ->> 'revision') then
    return pg_catalog.jsonb_build_object(
      'status', 'stale',
      'current_revision', v_current ->> 'revision',
      'can_write', private.can_write_shop(v_shop)
    );
  end if;
  if not private.can_write_shop(v_shop) then
    return pg_catalog.jsonb_build_object(
      'status', 'expired',
      'current_revision', v_current ->> 'revision',
      'can_write', false
    );
  end if;
  return pg_catalog.jsonb_build_object(
    'status', 'ready',
    'current_revision', v_current ->> 'revision',
    'can_write', true,
    'normalized', v_fields
  );
end;
$fn$;

create function public.post_invoice_appearance_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_appearance_requests%rowtype;
  v_fields jsonb;
  v_current jsonb;
  v_before jsonb;
  v_revision bigint;
  v_actor uuid := auth.uid();
  v_name text;
  v_at timestamptz;
  v_result jsonb;
  v_logo uuid;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select * into v_request
  from public.invoice_appearance_requests
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
  v_fields := private.invoice_appearance_fields(v_shop, p_payload);
  v_current := private.invoice_current_appearance(v_shop);
  if (v_fields ->> 'expected_revision') is distinct from (v_current ->> 'revision') then
    raise exception 'stale_appearance';
  end if;
  v_revision := (v_current ->> 'revision')::bigint + 1;
  v_at := pg_catalog.clock_timestamp();
  select owner_display_name into v_name from public.shops where id = v_shop;
  v_logo := nullif(v_fields ->> 'logo_asset_id', '')::uuid;
  v_before := v_current;
  insert into public.invoice_appearance_revisions (
    shop_id, revision, template, accent, slogan, address,
    logo_asset_id, logo_sha256, actor_user_id, created_at
  ) values (
    v_shop, v_revision, v_fields ->> 'template', v_fields ->> 'accent',
    v_fields ->> 'slogan', v_fields ->> 'address', v_logo, v_fields ->> 'logo_sha256',
    v_actor, v_at
  );
  v_result := pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'key', p_idempotency_key,
    'kind', 'invoice_appearance',
    'payload', p_payload,
    'revision', v_revision::text,
    'template', v_fields ->> 'template',
    'accent', v_fields ->> 'accent',
    'slogan', v_fields ->> 'slogan',
    'address', v_fields ->> 'address',
    'logo_asset_id', v_logo,
    'logo_sha256', v_fields ->> 'logo_sha256',
    'actor_user_id', v_actor,
    'at', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'replayed', false,
    'cash_piastres', '0',
    'gold_milligrams', '0',
    'stock_milligrams', '0',
    'invoice_effect', false,
    'dispatch_effect', false
  );
  insert into public.invoice_appearance_audits (
    shop_id, revision, before_json, after_json, actor_user_id,
    actor_display_name, created_at, idempotency_key
  ) values (
    v_shop, v_revision, v_before, v_result, v_actor, v_name, v_at, p_idempotency_key
  );
  perform private.bump_shop_sync(v_shop, 'appearance');
  insert into public.invoice_appearance_requests (
    shop_id, idempotency_key, payload_canonical, result, created_at
  ) values (
    v_shop, p_idempotency_key, p_payload, v_result, v_at
  );
  return v_result;
end;
$fn$;

create function public.get_invoice_appearance_status_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_appearance_requests%rowtype;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  select * into v_request
  from public.invoice_appearance_requests
  where shop_id = v_shop and idempotency_key = p_idempotency_key;
  if not found then
    return pg_catalog.jsonb_build_object('status', 'absent');
  end if;
  if v_request.payload_canonical is distinct from p_payload then
    raise exception 'payload_mismatch';
  end if;
  return pg_catalog.jsonb_build_object('status', 'completed', 'result', v_request.result);
end;
$fn$;

create function public.confirm_invoice_logo_v1(p_bytes text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_raw bytea;
  v_fact record;
  v_sha text;
  v_ext text;
  v_name text;
  v_object record;
  v_asset public.invoice_logo_assets%rowtype;
  v_at timestamptz := pg_catalog.clock_timestamp();
  v_existed boolean := false;
begin
  if not private.can_write_shop(v_shop) then
    raise exception 'shop_not_active';
  end if;
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
  if v_raw is null or pg_catalog.octet_length(v_raw) = 0 or pg_catalog.octet_length(v_raw) > 2097152 then
    raise exception 'image_too_large';
  end if;
  select * into v_fact from private.invoice_logo_facts(v_raw, true);
  v_sha := pg_catalog.encode(extensions.digest(v_raw, 'sha256'), 'hex');
  v_ext := case v_fact.mime when 'image/png' then 'png' else 'jpg' end;
  v_name := v_shop::text || '/' || v_sha || '.' || v_ext;
  select name, metadata into v_object
  from storage.objects
  where bucket_id = 'eldafttar-private-invoice-logos' and name = v_name;
  if not found then
    raise exception 'logo_not_uploaded';
  end if;
  if (v_object.metadata ->> 'mimetype') is distinct from v_fact.mime
    or (v_object.metadata ->> 'size') is distinct from pg_catalog.octet_length(v_raw)::text then
    raise exception 'logo_mismatch';
  end if;
  select * into v_asset
  from public.invoice_logo_assets
  where shop_id = v_shop and sha256 = v_sha;
  if found then
    if v_asset.content is distinct from v_raw
      or v_asset.mime is distinct from v_fact.mime
      or v_asset.width is distinct from v_fact.width
      or v_asset.height is distinct from v_fact.height then
      raise exception 'logo_mismatch';
    end if;
    v_existed := true;
  else
    insert into public.invoice_logo_assets (
      shop_id, sha256, mime, width, height, byte_size, content, actor_user_id, created_at
    ) values (
      v_shop, v_sha, v_fact.mime, v_fact.width, v_fact.height,
      pg_catalog.octet_length(v_raw), v_raw, auth.uid(), v_at
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

create function public.get_invoice_brand_source_v1(p_operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_facts jsonb;
  v_latest bigint;
begin
  if p_operation_id is null then
    raise exception 'invalid_input';
  end if;
  v_facts := private.invoice_operation_facts(v_shop, p_operation_id);
  select coalesce(pg_catalog.max(edition), 0::bigint) into v_latest
  from public.invoice_presentation_revisions
  where shop_id = v_shop and operation_id = p_operation_id;
  return v_facts || pg_catalog.jsonb_build_object(
    'version', 1,
    'appearance', private.invoice_current_appearance(v_shop),
    'latest_edition', v_latest::text,
    'can_write', private.can_write_shop(v_shop)
  );
end;
$fn$;

create function private.invoice_presentation_fields(p_payload jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_hash text;
begin
  perform private.repair_require_keys(
    p_payload,
    array['version', 'kind', 'operation_id', 'expected_content_sha256', 'expected_appearance_revision', 'expected_latest_edition']
  );
  if p_payload -> 'version' is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'invoice_presentation' then
    raise exception 'invalid_input';
  end if;
  v_hash := p_payload ->> 'expected_content_sha256';
  if v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_input';
  end if;
  return pg_catalog.jsonb_build_object(
    'operation_id', private.repair_uuid(p_payload -> 'operation_id'),
    'expected_content_sha256', v_hash,
    'expected_appearance_revision', private.repair_money(p_payload -> 'expected_appearance_revision', true)::text,
    'expected_latest_edition', private.repair_money(p_payload -> 'expected_latest_edition', true)::text
  );
end;
$fn$;

create function public.post_invoice_presentation_v1(p_idempotency_key uuid, p_payload jsonb)
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

create function public.get_invoice_presentation_status_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_presentation_requests%rowtype;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  select * into v_request
  from public.invoice_presentation_requests
  where shop_id = v_shop and idempotency_key = p_idempotency_key;
  if not found then
    return pg_catalog.jsonb_build_object('status', 'absent');
  end if;
  if v_request.payload_canonical is distinct from p_payload then
    raise exception 'payload_mismatch';
  end if;
  return pg_catalog.jsonb_build_object('status', 'completed', 'result', v_request.result);
end;
$fn$;

create function public.get_invoice_presentations_v1(p_operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_zone text;
  v_items jsonb;
begin
  if p_operation_id is null then
    raise exception 'invalid_input';
  end if;
  perform private.invoice_operation_facts(v_shop, p_operation_id);
  select time_zone into v_zone from public.shops where id = v_shop;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
    'edition', edition::text,
    'content_sha256', content_sha256,
    'appearance_revision', appearance_revision::text,
    'template', template,
    'accent', accent,
    'render_version', render_version,
    'created_at', pg_catalog.to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'created_at_shop', pg_catalog.to_char(created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'actor_user_id', actor_user_id,
    'has_logo', logo_asset_id is not null
  ) order by edition), '[]'::jsonb)
  into v_items
  from public.invoice_presentation_revisions
  where shop_id = v_shop and operation_id = p_operation_id;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'operation_id', p_operation_id,
    'time_zone', v_zone,
    'can_write', private.can_write_shop(v_shop),
    'items', v_items
  );
end;
$fn$;

create function public.get_invoice_presentation_v1(p_operation_id uuid, p_edition bigint)
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
  if v_row.logo_asset_id is not null then
    select * into v_asset
    from public.invoice_logo_assets
    where shop_id = v_shop and id = v_row.logo_asset_id;
    if not found
      or v_asset.sha256 is distinct from v_row.logo_sha256
      or pg_catalog.encode(extensions.digest(v_asset.content, 'sha256'), 'hex') is distinct from v_row.logo_sha256 then
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

insert into storage.buckets (id, name, "public", file_size_limit, allowed_mime_types)
values (
  'eldafttar-private-invoice-logos',
  'eldafttar-private-invoice-logos',
  false,
  2097152,
  array['image/png', 'image/jpeg']::text[]
)
on conflict (id) do update
set "public" = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types,
    name = excluded.name;

do $logo_storage_rls$
begin
  if not (select relrowsecurity from pg_catalog.pg_class where oid = 'storage.objects'::regclass) then
    alter table storage.objects enable row level security;
  end if;
end;
$logo_storage_rls$;

create function private.invoice_logo_storage_insert_allowed(p_name text, p_meta jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_ext text;
  v_size text;
  v_mime text;
begin
  if auth.uid() is null or p_name is null or pg_catalog.jsonb_typeof(p_meta) is distinct from 'object' then
    return false;
  end if;
  if p_name !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[0-9a-f]{64}\.(png|jpg)$' then
    return false;
  end if;
  if pg_catalog.strpos(p_name, '/') <> pg_catalog.length(pg_catalog.split_part(p_name, '/', 1)) + 1
    or pg_catalog.split_part(p_name, '/', 3) <> '' then
    return false;
  end if;
  begin
    v_shop := pg_catalog.split_part(p_name, '/', 1)::uuid;
  exception
    when others then
      return false;
  end;
  v_ext := pg_catalog.split_part(p_name, '.', 2);
  v_mime := p_meta ->> 'mimetype';
  if (v_ext = 'png' and v_mime is distinct from 'image/png')
    or (v_ext = 'jpg' and v_mime is distinct from 'image/jpeg') then
    return false;
  end if;
  v_size := p_meta ->> 'size';
  if v_size is null or v_size !~ '^[1-9][0-9]{0,7}$' or v_size::numeric > 2097152 then
    return false;
  end if;
  if not exists (
    select 1 from public.shop_memberships as membership
    where membership.user_id = auth.uid()
      and membership.shop_id = v_shop
      and membership.role = 'owner'
      and membership.revoked_at is null
  ) then
    return false;
  end if;
  return private.can_write_shop(v_shop);
end;
$fn$;

drop policy if exists eldafttar_private_invoice_logos_insert on storage.objects;
create policy eldafttar_private_invoice_logos_insert
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'eldafttar-private-invoice-logos'
    and (
      (owner = auth.uid() and (owner_id is null or owner_id = auth.uid()::text))
      or (owner is null and owner_id = auth.uid()::text)
    )
    and private.invoice_logo_storage_insert_allowed(name, metadata)
  );

revoke all on function private.bump_shop_sync(uuid, text) from public, anon, authenticated;
revoke all on function private.shop_sync_touch() from public, anon, authenticated;
revoke all on function private.invoice_logo_asset_guard() from public, anon, authenticated;
revoke all on function private.invoice_appearance_revision_guard() from public, anon, authenticated;
revoke all on function private.invoice_presentation_revision_guard() from public, anon, authenticated;
revoke all on function private.invoice_optional_text(jsonb, integer, integer) from public, anon, authenticated;
revoke all on function private.invoice_logo_facts(bytea, boolean) from public, anon, authenticated;
revoke all on function private.invoice_appearance_fields(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.invoice_current_appearance(uuid) from public, anon, authenticated;
revoke all on function private.invoice_operation_facts(uuid, uuid) from public, anon, authenticated;
revoke all on function private.invoice_presentation_fields(jsonb) from public, anon, authenticated;
revoke all on function private.invoice_logo_storage_insert_allowed(text, jsonb) from public, anon;
grant execute on function private.invoice_logo_storage_insert_allowed(text, jsonb) to authenticated;

revoke all on function public.get_invoice_appearance_v1() from public, anon, authenticated;
revoke all on function public.review_invoice_appearance_v1(jsonb) from public, anon, authenticated;
revoke all on function public.post_invoice_appearance_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.get_invoice_appearance_status_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.confirm_invoice_logo_v1(text) from public, anon, authenticated;
revoke all on function public.get_invoice_brand_source_v1(uuid) from public, anon, authenticated;
revoke all on function public.post_invoice_presentation_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.get_invoice_presentation_status_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.get_invoice_presentations_v1(uuid) from public, anon, authenticated;
revoke all on function public.get_invoice_presentation_v1(uuid, bigint) from public, anon, authenticated;
grant execute on function public.get_invoice_appearance_v1() to authenticated;
grant execute on function public.review_invoice_appearance_v1(jsonb) to authenticated;
grant execute on function public.post_invoice_appearance_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_invoice_appearance_status_v1(uuid, jsonb) to authenticated;
grant execute on function public.confirm_invoice_logo_v1(text) to authenticated;
grant execute on function public.get_invoice_brand_source_v1(uuid) to authenticated;
grant execute on function public.post_invoice_presentation_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_invoice_presentation_status_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_invoice_presentations_v1(uuid) to authenticated;
grant execute on function public.get_invoice_presentation_v1(uuid, bigint) to authenticated;

commit;

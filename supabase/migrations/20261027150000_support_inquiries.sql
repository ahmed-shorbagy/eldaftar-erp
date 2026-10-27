-- HELP-02: in-app support inquiries and platform-admin triage.
-- Explicit narrow audited support path (D21 approval rule); not the general
-- D21 shop-data access mechanism. Text-only; no R2 media kind. Zero
-- financial, entitlement, dispatch or business-audit effect. Owners may
-- submit regardless of entitlement state (expired readers included), so no
-- entitlement check belongs on this path. Revoked members, partners,
-- employees, count-only assignments, anonymous callers and revoked admins
-- are denied at the database.

begin;

create table public.support_inquiries (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops (id),
  owner_user_id uuid not null references auth.users (id),
  category text check (
    category in ('subscription', 'technical', 'financial_question', 'other')
  ),
  body_ar text not null,
  status text not null check (status in ('new', 'in_progress', 'answered', 'closed')),
  reply_ar text,
  idempotency_key uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  answered_at timestamptz,
  closed_at timestamptz,
  constraint support_inquiries_shop_owner_key unique (shop_id, idempotency_key),
  constraint support_inquiries_shop_owner_membership_fkey
    foreign key (shop_id, owner_user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint support_inquiries_body_length_check
    check (char_length(body_ar) between 1 and 2000),
  constraint support_inquiries_status_shape_check check (
    (status = 'new' and reply_ar is null and answered_at is null and closed_at is null)
    or (status = 'in_progress' and reply_ar is null and answered_at is null and closed_at is null)
    or (status = 'answered' and reply_ar is not null and answered_at is not null and closed_at is null)
    or (status = 'closed' and reply_ar is not null and answered_at is not null and closed_at is not null)
  )
);

create index support_inquiries_owner_list_idx
  on public.support_inquiries (owner_user_id, created_at desc, id desc);
create index support_inquiries_shop_list_idx
  on public.support_inquiries (shop_id, created_at desc, id desc);
create index support_inquiries_admin_order_idx
  on public.support_inquiries (created_at desc, id desc);
-- Rate-limit counting of non-closed inquiries per shop.
create index support_inquiries_open_shop_idx
  on public.support_inquiries (shop_id)
  where status <> 'closed';

create table public.support_inquiry_events (
  id uuid primary key default gen_random_uuid(),
  inquiry_id uuid not null references public.support_inquiries (id),
  from_status text,
  to_status text not null,
  reply_ar text,
  actor_user_id uuid not null references auth.users (id),
  idempotency_key uuid not null,
  created_at timestamptz not null default timezone('utc', now()),
  constraint support_inquiry_events_to_status_check
    check (to_status in ('new', 'in_progress', 'answered', 'closed')),
  constraint support_inquiry_events_key_key unique (inquiry_id, idempotency_key)
);

create index support_inquiry_events_inquiry_idx
  on public.support_inquiry_events (inquiry_id, created_at desc, id desc);

create function private.support_inquiry_events_append_only()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $fn$
begin
  raise exception 'append_only';
end;
$fn$;

revoke all on function private.support_inquiry_events_append_only()
  from public, anon, authenticated;

create trigger support_inquiry_events_append_only
  before update or delete on public.support_inquiry_events
  for each row execute function private.support_inquiry_events_append_only();

alter table public.support_inquiries enable row level security;
alter table public.support_inquiry_events enable row level security;

revoke all on table public.support_inquiries from anon, authenticated;
revoke all on table public.support_inquiry_events from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Shared helpers (not granted to clients)
-- ---------------------------------------------------------------------------

create function private.support_actor_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select auth.uid() is not null
    and private.caller_session_accepted()
    and exists (
      select 1
      from auth.users as identity
      where identity.id = auth.uid()
        and coalesce(identity.is_anonymous, false) = false
        and identity.deleted_at is null
        and (identity.banned_until is null or identity.banned_until <= now())
    );
$fn$;

revoke all on function private.support_actor_session() from public, anon, authenticated;

create function private.support_owner_shop()
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  if not private.support_actor_session() then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  select membership.shop_id into v_shop
  from public.shop_memberships as membership
  where membership.user_id = auth.uid()
    and membership.role = 'owner'
    and membership.revoked_at is null
  limit 1;
  if v_shop is null then
    raise exception 'unauthorized' using errcode = '42501';
  end if;
  return v_shop;
end;
$fn$;

revoke all on function private.support_owner_shop() from public, anon, authenticated;

create function private.support_inquiry_text(
  p_text text,
  p_min integer,
  p_max integer
)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
begin
  if p_text is null then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_text := p_text;
  -- Newline (LF) is the only accepted control character; CR and the rest
  -- are rejected.
  if position(chr(13) in v_text) > 0
    or position(chr(9) in v_text) > 0
    or translate(v_text, chr(10), '') ~ '[[:cntrl:]]' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_text := btrim(v_text);
  if char_length(v_text) not between p_min and p_max then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  return v_text;
end;
$fn$;

revoke all on function private.support_inquiry_text(text, integer, integer)
  from public, anon, authenticated;

-- Returns one inquiry as the owner/admin read shape. Shop name travels only
-- with admin lists, so the owner shape passes null.
create function private.support_inquiry_row(
  p_inquiry public.support_inquiries,
  p_shop_name text
)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
begin
  return jsonb_build_object(
    'id', p_inquiry.id,
    'shop_id', p_inquiry.shop_id,
    'shop_name', p_shop_name,
    'category', p_inquiry.category,
    'body_ar', p_inquiry.body_ar,
    'status', p_inquiry.status,
    'reply_ar', p_inquiry.reply_ar,
    'created_at', p_inquiry.created_at,
    'updated_at', p_inquiry.updated_at,
    'answered_at', p_inquiry.answered_at,
    'closed_at', p_inquiry.closed_at
  );
end;
$fn$;

revoke all on function private.support_inquiry_row(public.support_inquiries, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Owner RPCs
-- ---------------------------------------------------------------------------

create function public.create_support_inquiry_v1(
  p_idempotency_key uuid,
  p_category text,
  p_body_ar text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_body text;
  v_open integer;
  v_row public.support_inquiries%rowtype;
begin
  if p_idempotency_key is null
    or p_idempotency_key = '00000000-0000-0000-0000-000000000000' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_shop := private.support_owner_shop();

  if p_category is not null and p_category not in
    ('subscription', 'technical', 'financial_question', 'other') then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  v_body := private.support_inquiry_text(p_body_ar, 10, 1000);

  select * into v_row
  from public.support_inquiries
  where shop_id = v_shop
    and idempotency_key = p_idempotency_key
    and owner_user_id = auth.uid();
  if found then
    if v_row.category is distinct from p_category
      or v_row.body_ar is distinct from v_body then
      raise exception 'payload_mismatch';
    end if;
    return private.support_inquiry_row(v_row, null)
      || jsonb_build_object('result_status', 'replayed');
  end if;

  select count(*) into v_open
  from public.support_inquiries
  where shop_id = v_shop and status <> 'closed';
  if v_open >= 10 then
    raise exception 'inquiry_limit' using errcode = '22023';
  end if;

  insert into public.support_inquiries (
    shop_id, owner_user_id, category, body_ar, status, idempotency_key
  ) values (
    v_shop, auth.uid(), p_category, v_body, 'new', p_idempotency_key
  ) returning * into v_row;

  insert into public.support_inquiry_events (
    inquiry_id, from_status, to_status, reply_ar, actor_user_id, idempotency_key
  ) values (
    v_row.id, null, 'new', null, auth.uid(), p_idempotency_key
  );

  return private.support_inquiry_row(v_row, null)
    || jsonb_build_object('result_status', 'saved');
end;
$fn$;

revoke all on function public.create_support_inquiry_v1(uuid, text, text)
  from public, anon;
grant execute on function public.create_support_inquiry_v1(uuid, text, text)
  to authenticated;

create function public.list_my_support_inquiries_v1(
  p_cursor_at timestamptz default null,
  p_cursor_id uuid default null,
  p_page_size integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_size integer;
  v_result jsonb;
begin
  v_shop := private.support_owner_shop();

  if p_cursor_id is not null then
    if p_cursor_at is null then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.support_inquiries
      where shop_id = v_shop
        and id = p_cursor_id
        and created_at = p_cursor_at
    ) then
      raise exception 'stale_cursor' using errcode = 'P0001';
    end if;
  end if;

  v_size := least(greatest(coalesce(p_page_size, 20), 1), 50);

  with page as (
    select * from public.support_inquiries
    where shop_id = v_shop
      and (p_cursor_id is null
        or created_at < p_cursor_at
        or (created_at = p_cursor_at and id < p_cursor_id))
    order by created_at desc, id desc
    limit v_size + 1
  ),
  numbered as (
    select
      private.support_inquiry_row(entry, null) as entry,
      entry.created_at as created_at,
      entry.id as id,
      row_number() over (order by entry.created_at desc, entry.id desc) as rn
    from page as entry
  ),
  open_count as (
    select count(*) as count
    from public.support_inquiries
    where shop_id = v_shop and status <> 'closed'
  )
  select jsonb_build_object(
    'inquiries', coalesce((
      select jsonb_agg(entry order by rn desc)
      from numbered
      where rn <= v_size
    ), '[]'::jsonb),
    'next_cursor_at', case
      when exists (select 1 from numbered where rn = v_size + 1)
      then (select created_at from numbered where rn = v_size)
    end,
    'next_cursor_id', case
      when exists (select 1 from numbered where rn = v_size + 1)
      then (select id from numbered where rn = v_size)
    end,
    'open_count', (select count from open_count),
    'open_limit', 10,
    'time_zone', (select shop.time_zone from public.shops as shop where shop.id = v_shop),
    'snapshot_at', timezone('utc', now())
  ) into v_result;
  return v_result;
end;
$fn$;

revoke all on function public.list_my_support_inquiries_v1(timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.list_my_support_inquiries_v1(timestamptz, uuid, integer)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Platform-admin RPCs (gated by the existing admin subscriber gate)
-- ---------------------------------------------------------------------------

create function public.admin_list_support_inquiries_v1(
  p_status text default null,
  p_search text default null,
  p_cursor_at timestamptz default null,
  p_cursor_id uuid default null,
  p_page_size integer default 20
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_gate text;
  v_size integer;
  v_search text;
  v_shop_id uuid;
  v_result jsonb;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  if p_status is not null and p_status not in
    ('new', 'in_progress', 'answered', 'closed') then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if p_cursor_id is not null then
    if p_cursor_at is null then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
    if not exists (
      select 1 from public.support_inquiries
      where id = p_cursor_id and created_at = p_cursor_at
    ) then
      raise exception 'stale_cursor' using errcode = 'P0001';
    end if;
  end if;

  v_search := btrim(coalesce(p_search, ''));
  if char_length(v_search) > 120 or v_search ~ '[[:cntrl:]]' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  -- Only an exact shop identifier selects. Any other text selects nothing.
  v_shop_id := case
    when v_search ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
    then v_search::uuid
    when v_search <> '' then '00000000-0000-0000-0000-000000000000'::uuid
  end;

  v_size := least(greatest(coalesce(p_page_size, 20), 1), 50);

  with matched as (
    select
      inquiry as inv,
      shop.name as shop_name,
      shop.created_at as shop_created_at,
      shop.time_zone as shop_time_zone
    from public.support_inquiries as inquiry
    join public.shops as shop on shop.id = inquiry.shop_id
    where (p_status is null or inquiry.status = p_status)
      and (v_shop_id is null or inquiry.shop_id = v_shop_id)
  ),
  page as (
    select * from matched
    where (p_cursor_id is null
      or (inv).created_at < p_cursor_at
      or ((inv).created_at = p_cursor_at and (inv).id < p_cursor_id))
    order by (inv).created_at desc, (inv).id desc
    limit v_size + 1
  ),
  numbered as (
    select
      private.support_inquiry_row(entry.inv, entry.shop_name)
        || jsonb_build_object(
          'shop_created_at', entry.shop_created_at,
          'shop_time_zone', entry.shop_time_zone
        ) as entry,
      (entry.inv).created_at as created_at,
      (entry.inv).id as id,
      row_number() over (order by (entry.inv).created_at desc, (entry.inv).id desc) as rn
    from page as entry
  )
  select jsonb_build_object(
    'inquiries', coalesce((
      select jsonb_agg(entry order by rn desc)
      from numbered
      where rn <= v_size
    ), '[]'::jsonb),
    'next_cursor_at', case
      when exists (select 1 from numbered where rn = v_size + 1)
      then (select created_at from numbered where rn = v_size)
    end,
    'next_cursor_id', case
      when exists (select 1 from numbered where rn = v_size + 1)
      then (select id from numbered where rn = v_size)
    end,
    'snapshot_at', timezone('utc', now())
  ) into v_result;
  return v_result;
end;
$fn$;

revoke all on function public.admin_list_support_inquiries_v1(text, text, timestamptz, uuid, integer)
  from public, anon;
grant execute on function public.admin_list_support_inquiries_v1(text, text, timestamptz, uuid, integer)
  to authenticated;

create function public.admin_update_support_inquiry_status_v1(
  p_id uuid,
  p_to_status text,
  p_reply_ar text,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_gate text;
  v_from text;
  v_reply text;
  v_row public.support_inquiries%rowtype;
  v_prior public.support_inquiry_events%rowtype;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  if p_id is null
    or p_idempotency_key is null
    or p_idempotency_key = '00000000-0000-0000-0000-000000000000' then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if p_to_status not in ('in_progress', 'answered', 'closed') then
    raise exception 'invalid_input' using errcode = '22023';
  end if;
  if p_to_status = 'answered' then
    v_reply := private.support_inquiry_text(p_reply_ar, 10, 1000);
  elsif p_reply_ar is not null then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  select * into v_row
  from public.support_inquiries
  where id = p_id
  for update;
  if not found then
    raise exception 'not_found' using errcode = 'P0002';
  end if;

  select * into v_prior
  from public.support_inquiry_events
  where inquiry_id = p_id and idempotency_key = p_idempotency_key;
  if found then
    if v_prior.to_status is distinct from p_to_status
      or v_prior.reply_ar is distinct from v_reply then
      raise exception 'payload_mismatch';
    end if;
    return private.support_inquiry_row(v_row, null)
      || jsonb_build_object('result_status', 'replayed');
  end if;

  v_from := v_row.status;
  if not (
    (v_from = 'new' and p_to_status = 'in_progress')
    or (v_from = 'in_progress' and p_to_status = 'answered')
    or (v_from = 'answered' and p_to_status = 'closed')
  ) then
    raise exception 'invalid_transition' using errcode = 'P0001';
  end if;

  if p_to_status = 'answered' then
    update public.support_inquiries
    set status = 'answered',
        reply_ar = v_reply,
        answered_at = timezone('utc', now()),
        updated_at = timezone('utc', now())
    where id = p_id
    returning * into v_row;
  elsif p_to_status = 'closed' then
    update public.support_inquiries
    set status = 'closed',
        closed_at = timezone('utc', now()),
        updated_at = timezone('utc', now())
    where id = p_id
    returning * into v_row;
  else
    update public.support_inquiries
    set status = 'in_progress',
        updated_at = timezone('utc', now())
    where id = p_id
    returning * into v_row;
  end if;

  insert into public.support_inquiry_events (
    inquiry_id, from_status, to_status, reply_ar, actor_user_id, idempotency_key
  ) values (
    p_id, v_from, p_to_status, v_reply, auth.uid(), p_idempotency_key
  );

  return private.support_inquiry_row(v_row, null)
    || jsonb_build_object('result_status', 'saved');
end;
$fn$;

revoke all on function public.admin_update_support_inquiry_status_v1(uuid, text, text, uuid)
  from public, anon;
grant execute on function public.admin_update_support_inquiry_status_v1(uuid, text, text, uuid)
  to authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.create_support_inquiry_v1(uuid, text, text) from service_role';
    execute 'revoke all on function public.list_my_support_inquiries_v1(timestamptz, uuid, integer) from service_role';
    execute 'revoke all on function public.admin_list_support_inquiries_v1(text, text, timestamptz, uuid, integer) from service_role';
    execute 'revoke all on function public.admin_update_support_inquiry_status_v1(uuid, text, text, uuid) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';

commit;

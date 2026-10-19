-- SET-04 invoice message templates. Additive and separate from appearance.
-- Shared scalar set, mirrored by the client. SQL validates the template only.
-- It never substitutes tokens and never parses substituted output.
--
-- CRLF becomes LF first. Any remaining CR, including a leading or trailing CR
-- that Dart trim would remove, is rejected before trim.
-- Dart String.trim whitespace (Unicode 6.3 White_Space plus BOM): U+0009..U+000D,
-- U+0020, U+0085, U+00A0, U+1680, U+2000..U+200A, U+2028, U+2029, U+202F,
-- U+205F, U+3000, U+FEFF. U+180E is not trimmed. CR is in that Dart set and is
-- still not used as trim here, because a remaining CR has already been rejected.
--
-- Rejected after that trim: every other C0 control, DEL U+007F, C1
-- U+0080..U+009F, surrogates, noncharacters U+FDD0..U+FDEF and plane-ending
-- U+FFFE/U+FFFF, and format characters except U+200D ZWJ. Variation selectors
-- U+FE00..U+FE0F and U+E0100..U+E01EF stay allowed because they are marks,
-- not controls. Emoji tag characters U+E0020..U+E007F and ZWNJ U+200C are
-- rejected. Internal U+2028/U+2029 are not controls; only U+000A counts
-- toward the eight-newline cap. Literal URL or HTML text is ordinary text:
-- the placeholder language has no URL, HTML, expression, filter, or
-- conditional production, and this migration does not add a free-text denylist.
-- Ill-formed UTF-8 and unpaired JSON surrogates fail before this function.
begin;

alter table public.shop_sync_signals
  add column message_revision bigint not null default 0
  constraint shop_sync_signals_message_revision_check check (message_revision >= 0);

comment on column public.shop_sync_signals.message_revision is
  'Invoice message template scope. Independent from appearance_revision and invoice_revision.';

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
    repair_revision, debt_revision, customer_revision, appearance_revision,
    message_revision, updated_at
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
    case when p_scope = 'message' then 1 else 0 end,
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
        message_revision = public.shop_sync_signals.message_revision
          + case when p_scope = 'message' then 1 else 0 end,
        updated_at = pg_catalog.clock_timestamp();
end;
$fn$;

create table public.invoice_message_revisions (
  shop_id uuid not null references public.shops (id),
  revision bigint not null,
  template text,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  primary key (shop_id, revision),
  constraint invoice_message_revisions_revision_check check (revision >= 1),
  constraint invoice_message_revisions_template_check check (
    template is null
    or (
      pg_catalog.char_length(template) between 1 and 400
      and (
        pg_catalog.char_length(template)
        - pg_catalog.char_length(pg_catalog.replace(template, E'\n', ''))
      ) <= 8
      and pg_catalog.strpos(template, E'\r') = 0
    )
  ),
  constraint invoice_message_revisions_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);

comment on table public.invoice_message_revisions is
  'Append-only shop message templates. Null template means the unstored four-line default. Revision 0 is absence, not a row.';

create table public.invoice_message_audits (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  revision bigint not null,
  previous_revision bigint not null,
  idempotency_key uuid not null,
  actor_user_id uuid not null,
  created_at timestamptz not null,
  template_length integer,
  template_sha256 text,
  previous_length integer,
  previous_sha256 text,
  constraint invoice_message_audits_revision_check check (
    revision >= 1 and previous_revision >= 0 and revision = previous_revision + 1
  ),
  constraint invoice_message_audits_length_check check (
    (
      template_sha256 is null and template_length is null
      or template_sha256 ~ '^[0-9a-f]{64}$' and template_length between 1 and 400
    )
    and (
      previous_sha256 is null and previous_length is null
      or previous_sha256 ~ '^[0-9a-f]{64}$' and previous_length between 1 and 400
    )
  ),
  constraint invoice_message_audits_revision_fkey
    foreign key (shop_id, revision)
    references public.invoice_message_revisions (shop_id, revision),
  constraint invoice_message_audits_actor_fkey
    foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id),
  constraint invoice_message_audits_revision_key unique (shop_id, revision),
  constraint invoice_message_audits_key unique (shop_id, idempotency_key)
);

comment on table public.invoice_message_audits is
  'Metadata only: revisions, idempotency key, owner, server UTC, scalar length, and template sha256. No template text, rendered body, or recipient phone.';

create index invoice_message_audits_shop_idx
  on public.invoice_message_audits (shop_id, created_at);

create table public.invoice_message_requests (
  shop_id uuid not null references public.shops (id),
  idempotency_key uuid not null,
  payload_canonical jsonb not null,
  result jsonb not null,
  created_at timestamptz not null,
  primary key (shop_id, idempotency_key),
  constraint invoice_message_requests_payload_check check (
    pg_catalog.jsonb_typeof(payload_canonical) = 'object'
    and (payload_canonical - 'version' - 'kind' - 'expected_revision' - 'template') = '{}'::jsonb
    and payload_canonical ? 'version'
    and payload_canonical ? 'kind'
    and payload_canonical ? 'expected_revision'
    and payload_canonical ? 'template'
  ),
  constraint invoice_message_requests_result_check check (
    pg_catalog.jsonb_typeof(result) = 'object'
    and result ->> 'kind' = 'invoice_message'
    and result ->> 'cash_piastres' = '0'
    and result ->> 'gold_milligrams' = '0'
    and result ->> 'stock_milligrams' = '0'
    and result -> 'invoice_effect' = 'false'::jsonb
    and result -> 'dispatch_effect' = 'false'::jsonb
    and result -> 'replayed' = 'false'::jsonb
    and not (result ? 'phone')
    and not (result ? 'customer_phone')
    and not (result ? 'recipient')
    and not (result ? 'rendered')
  )
);

comment on table public.invoice_message_requests is
  'Durable recovery of the original command payload and receipt. Not a dispatch audit. The envelope may contain the owner-authored template and must not contain a recipient phone.';

create function private.invoice_message_dart_space(p_cp integer)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select p_cp in (9, 10, 11, 12, 13, 32, 133, 160, 5760, 8232, 8233, 8239, 8287, 12288, 65279)
    or p_cp between 8192 and 8202;
$fn$;

create function private.invoice_message_scalar_rejected(p_cp integer)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select p_cp is null
    or (p_cp between 0 and 31 and p_cp <> 10)
    or p_cp = 127
    or p_cp between 128 and 159
    or p_cp between 55296 and 57343
    or p_cp between 64976 and 65007
    or (p_cp % 65536) in (65534, 65535)
    or p_cp in (173, 1564, 1757, 1807, 2274, 6158, 8203, 8204, 8206, 8207, 65279)
    or p_cp between 1536 and 1541
    or p_cp between 2192 and 2193
    or p_cp between 8234 and 8238
    or p_cp between 8288 and 8303
    or p_cp between 65529 and 65531
    or p_cp in (69821, 69837)
    or p_cp between 78896 and 78911
    or p_cp between 113824 and 113827
    or p_cp between 119155 and 119162
    or p_cp = 917505
    or p_cp between 917536 and 917631;
$fn$;

comment on function private.invoice_message_scalar_rejected(integer) is
  'Shared rejection set. Allows U+000A and does not reject U+200D ZWJ or variation selectors U+FE00-U+FE0F and U+E0100-U+E01EF. Rejects other C0/C1/DEL, bidi and format characters, ZWNJ, BOM, surrogates, and noncharacters.';

create function private.invoice_message_token_allowed(p_token text)
returns boolean
language sql
immutable
security invoker
set search_path = ''
as $fn$
  select p_token in (
    'sequence', 'kind', 'shop_name', 'operation_time', 'total',
    'customer_name', 'item_count',
    'grams_14', 'grams_18', 'grams_21', 'grams_22', 'grams_24',
    'paid', 'obligation'
  );
$fn$;

create function private.invoice_message_assert_template(p_text text)
returns void
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_len integer := pg_catalog.char_length(p_text);
  v_i integer := 1;
  v_j integer;
  v_ch text;
  v_cp integer;
  v_token text;
  v_lines integer;
begin
  if p_text is null or v_len < 1 or v_len > 400 then
    raise exception 'invalid_input';
  end if;
  v_lines := v_len - pg_catalog.char_length(pg_catalog.replace(p_text, E'\n', ''));
  if v_lines > 8 then
    raise exception 'invalid_input';
  end if;
  while v_i <= v_len loop
    v_ch := pg_catalog.substring(p_text, v_i, 1);
    if v_ch = '{' then
      if v_i < v_len and pg_catalog.substring(p_text, v_i + 1, 1) = '{' then
        v_i := v_i + 2;
        continue;
      end if;
      v_j := v_i + 1;
      v_token := '';
      while v_j <= v_len loop
        v_ch := pg_catalog.substring(p_text, v_j, 1);
        if v_ch = '{' then
          raise exception 'invalid_input';
        end if;
        exit when v_ch = '}';
        if v_ch !~ '^[a-z0-9_]$' then
          raise exception 'invalid_input';
        end if;
        v_token := v_token || v_ch;
        v_j := v_j + 1;
      end loop;
      if v_j > v_len or v_token = '' or not private.invoice_message_token_allowed(v_token) then
        raise exception 'invalid_input';
      end if;
      v_i := v_j + 1;
      continue;
    end if;
    if v_ch = '}' then
      if v_i < v_len and pg_catalog.substring(p_text, v_i + 1, 1) = '}' then
        v_i := v_i + 2;
        continue;
      end if;
      raise exception 'invalid_input';
    end if;
    v_cp := pg_catalog.ascii(v_ch);
    if private.invoice_message_scalar_rejected(v_cp) then
      raise exception 'invalid_input';
    end if;
    v_i := v_i + 1;
  end loop;
end;
$fn$;

create function private.invoice_message_normalize(p_value jsonb)
returns text
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_text text;
  v_len integer;
  v_start integer;
  v_end integer;
  v_cp integer;
begin
  if p_value is null or p_value = 'null'::jsonb then
    return null;
  end if;
  if pg_catalog.jsonb_typeof(p_value) is distinct from 'string' then
    raise exception 'invalid_input';
  end if;
  v_text := pg_catalog.replace(p_value #>> '{}', E'\r\n', E'\n');
  if pg_catalog.strpos(v_text, E'\r') > 0 then
    raise exception 'invalid_input';
  end if;
  v_len := pg_catalog.char_length(v_text);
  v_start := 1;
  while v_start <= v_len loop
    v_cp := pg_catalog.ascii(pg_catalog.substring(v_text, v_start, 1));
    exit when not private.invoice_message_dart_space(v_cp);
    v_start := v_start + 1;
  end loop;
  v_end := v_len;
  while v_end >= v_start loop
    v_cp := pg_catalog.ascii(pg_catalog.substring(v_text, v_end, 1));
    exit when not private.invoice_message_dart_space(v_cp);
    v_end := v_end - 1;
  end loop;
  if v_start > v_end then
    return null;
  end if;
  v_text := pg_catalog.substring(v_text, v_start, v_end - v_start + 1);
  perform private.invoice_message_assert_template(v_text);
  return v_text;
end;
$fn$;

create function private.invoice_message_fields(p_payload jsonb)
returns jsonb
language plpgsql
immutable
security invoker
set search_path = ''
as $fn$
declare
  v_template text;
  v_revision text;
begin
  perform private.repair_require_keys(
    p_payload,
    array['version', 'kind', 'expected_revision', 'template']
  );
  if p_payload -> 'version' is distinct from '1'::jsonb
    or p_payload ->> 'kind' is distinct from 'invoice_message' then
    raise exception 'invalid_input';
  end if;
  v_revision := private.repair_money(p_payload -> 'expected_revision', true)::text;
  v_template := private.invoice_message_normalize(p_payload -> 'template');
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'kind', 'invoice_message',
    'expected_revision', v_revision,
    'template', v_template
  );
end;
$fn$;

create function private.invoice_message_revision_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.revision is distinct from coalesce((
    select pg_catalog.max(revision) + 1
    from public.invoice_message_revisions
    where shop_id = new.shop_id
  ), 1) then
    raise exception 'invalid_input';
  end if;
  if new.template is not null
    and private.invoice_message_normalize(pg_catalog.to_jsonb(new.template))
      is distinct from new.template then
    raise exception 'invalid_input';
  end if;
  return new;
end;
$fn$;

create trigger invoice_message_revisions_guard
  before insert on public.invoice_message_revisions
  for each row execute function private.invoice_message_revision_guard();

create trigger invoice_message_revisions_append_only
  before update or delete on public.invoice_message_revisions
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_message_audits_append_only
  before update or delete on public.invoice_message_audits
  for each row execute function private.financial_audit_events_append_only();
create trigger invoice_message_requests_append_only
  before update or delete on public.invoice_message_requests
  for each row execute function private.financial_audit_events_append_only();

alter table public.invoice_message_revisions enable row level security;
alter table public.invoice_message_revisions force row level security;
alter table public.invoice_message_audits enable row level security;
alter table public.invoice_message_audits force row level security;
alter table public.invoice_message_requests enable row level security;
alter table public.invoice_message_requests force row level security;

revoke all on public.invoice_message_revisions, public.invoice_message_audits,
  public.invoice_message_requests from public, anon, authenticated;
grant select on public.invoice_message_revisions, public.invoice_message_audits,
  public.invoice_message_requests to authenticated;

create policy invoice_message_revisions_owner_read
  on public.invoice_message_revisions
  for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy invoice_message_audits_owner_read
  on public.invoice_message_audits
  for select to authenticated
  using (private.opening_financial_visible(shop_id));
create policy invoice_message_requests_owner_read
  on public.invoice_message_requests
  for select to authenticated
  using (private.opening_financial_visible(shop_id));

do $message_revoke$
begin
  if exists (select 1 from pg_catalog.pg_roles where rolname = 'service_role') then
    execute 'revoke update, delete on table public.invoice_message_revisions from service_role';
    execute 'revoke update, delete on table public.invoice_message_audits from service_role';
    execute 'revoke update, delete on table public.invoice_message_requests from service_role';
  end if;
end;
$message_revoke$;

create function public.get_invoice_message_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_zone text;
  v_revision bigint;
  v_template text;
  v_at timestamptz;
begin
  select time_zone into v_zone from public.shops where id = v_shop;
  select revision, template, created_at
    into v_revision, v_template, v_at
  from public.invoice_message_revisions
  where shop_id = v_shop
  order by revision desc
  limit 1;
  if not found then
    v_revision := 0;
    v_template := null;
    v_at := null;
  end if;
  return pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'revision', v_revision::text,
    'template', v_template,
    'can_write', private.can_write_shop(v_shop),
    'time_zone', v_zone,
    'created_at', case
      when v_at is null then null
      else pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    end,
    'created_at_shop', case
      when v_at is null then null
      else pg_catalog.to_char(v_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS')
    end
  );
end;
$fn$;

create function public.review_invoice_message_v1(p_payload jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_fields jsonb;
  v_current text;
begin
  if pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  v_fields := private.invoice_message_fields(p_payload);
  select coalesce(pg_catalog.max(revision)::text, '0') into v_current
  from public.invoice_message_revisions
  where shop_id = v_shop;
  if (v_fields ->> 'expected_revision') is distinct from v_current then
    return pg_catalog.jsonb_build_object(
      'status', 'stale',
      'current_revision', v_current,
      'can_write', private.can_write_shop(v_shop)
    );
  end if;
  if not private.can_write_shop(v_shop) then
    return pg_catalog.jsonb_build_object(
      'status', 'expired',
      'current_revision', v_current,
      'can_write', false
    );
  end if;
  return pg_catalog.jsonb_build_object(
    'status', 'ready',
    'current_revision', v_current,
    'can_write', true,
    'normalized', v_fields
  );
end;
$fn$;

create function public.post_invoice_message_v1(p_idempotency_key uuid, p_payload jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_message_requests%rowtype;
  v_fields jsonb;
  v_current bigint := 0;
  v_previous text;
  v_template text;
  v_revision bigint;
  v_actor uuid := auth.uid();
  v_at timestamptz;
  v_result jsonb;
  v_length integer;
  v_hash text;
  v_previous_length integer;
  v_previous_hash text;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  perform 1 from public.shops where id = v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then
    raise exception 'forbidden';
  end if;
  select * into v_request
  from public.invoice_message_requests
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
  v_fields := private.invoice_message_fields(p_payload);
  select revision, template into v_current, v_previous
  from public.invoice_message_revisions
  where shop_id = v_shop
  order by revision desc
  limit 1;
  if not found then
    v_current := 0;
    v_previous := null;
  end if;
  if (v_fields ->> 'expected_revision') is distinct from v_current::text then
    raise exception 'stale_message';
  end if;
  v_template := v_fields ->> 'template';
  if v_fields -> 'template' = 'null'::jsonb then
    v_template := null;
  end if;
  v_revision := v_current + 1;
  v_at := pg_catalog.clock_timestamp();
  if v_template is null then
    v_length := null;
    v_hash := null;
  else
    v_length := pg_catalog.char_length(v_template);
    v_hash := pg_catalog.encode(
      extensions.digest(pg_catalog.convert_to(v_template, 'UTF8'), 'sha256'),
      'hex'
    );
  end if;
  if v_previous is null then
    v_previous_length := null;
    v_previous_hash := null;
  else
    v_previous_length := pg_catalog.char_length(v_previous);
    v_previous_hash := pg_catalog.encode(
      extensions.digest(pg_catalog.convert_to(v_previous, 'UTF8'), 'sha256'),
      'hex'
    );
  end if;
  insert into public.invoice_message_revisions (
    shop_id, revision, template, actor_user_id, created_at
  ) values (
    v_shop, v_revision, v_template, v_actor, v_at
  );
  v_result := pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'key', p_idempotency_key,
    'kind', 'invoice_message',
    'payload', p_payload,
    'revision', v_revision::text,
    'template', v_template,
    'actor_user_id', v_actor,
    'at', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'replayed', false,
    'cash_piastres', '0',
    'gold_milligrams', '0',
    'stock_milligrams', '0',
    'invoice_effect', false,
    'dispatch_effect', false
  );
  insert into public.invoice_message_audits (
    shop_id, revision, previous_revision, idempotency_key, actor_user_id,
    created_at, template_length, template_sha256, previous_length, previous_sha256
  ) values (
    v_shop, v_revision, v_current, p_idempotency_key, v_actor,
    v_at, v_length, v_hash, v_previous_length, v_previous_hash
  );
  perform private.bump_shop_sync(v_shop, 'message');
  insert into public.invoice_message_requests (
    shop_id, idempotency_key, payload_canonical, result, created_at
  ) values (
    v_shop, p_idempotency_key, p_payload, v_result, v_at
  );
  return v_result;
end;
$fn$;

create function public.get_invoice_message_status_v1(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid := private.opening_require_reader_shop();
  v_request public.invoice_message_requests%rowtype;
begin
  if p_idempotency_key is null or pg_catalog.jsonb_typeof(p_payload) is distinct from 'object' then
    raise exception 'invalid_input';
  end if;
  select * into v_request
  from public.invoice_message_requests
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

create function public.get_invoice_message_source_v1(p_operation_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_result jsonb;
begin
  if p_operation_id is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.opening_require_reader_shop();
  select pg_catalog.jsonb_build_object(
    'version', 1,
    'shop_id', v_shop,
    'operation_id', facts -> 'operation_id',
    'kind', facts ->> 'kind',
    'shop_sequence', facts ->> 'shop_sequence',
    'shop_name', facts ->> 'shop_name',
    'time_zone', facts ->> 'time_zone',
    'occurred_at', facts ->> 'occurred_at',
    'occurred_at_shop', facts ->> 'occurred_at_shop',
    'payload', facts -> 'payload',
    'content_sha256', facts ->> 'content_sha256',
    'message', message
  )
  into v_result
  from (
    select private.invoice_operation_facts(v_shop, p_operation_id) as facts,
           public.get_invoice_message_v1() as message
  ) as snapshot;
  return v_result;
end;
$fn$;

revoke all on function private.bump_shop_sync(uuid, text) from public, anon, authenticated;
revoke all on function private.invoice_message_dart_space(integer) from public, anon, authenticated;
revoke all on function private.invoice_message_scalar_rejected(integer) from public, anon, authenticated;
revoke all on function private.invoice_message_token_allowed(text) from public, anon, authenticated;
revoke all on function private.invoice_message_assert_template(text) from public, anon, authenticated;
revoke all on function private.invoice_message_normalize(jsonb) from public, anon, authenticated;
revoke all on function private.invoice_message_fields(jsonb) from public, anon, authenticated;
revoke all on function private.invoice_message_revision_guard() from public, anon, authenticated;

revoke all on function public.get_invoice_message_v1() from public, anon, authenticated;
revoke all on function public.review_invoice_message_v1(jsonb) from public, anon, authenticated;
revoke all on function public.post_invoice_message_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.get_invoice_message_status_v1(uuid, jsonb) from public, anon, authenticated;
revoke all on function public.get_invoice_message_source_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_invoice_message_v1() to authenticated;
grant execute on function public.review_invoice_message_v1(jsonb) to authenticated;
grant execute on function public.post_invoice_message_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_invoice_message_status_v1(uuid, jsonb) to authenticated;
grant execute on function public.get_invoice_message_source_v1(uuid) to authenticated;

commit;

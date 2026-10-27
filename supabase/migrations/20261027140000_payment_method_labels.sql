-- SET-02 / D24: rename + archive for the four cash methods; historical label snapshots.
begin;

alter table public.ledger_accounts
  add column if not exists display_label_ar text,
  add column if not exists archived_at timestamptz;

update public.ledger_accounts as account
set display_label_ar = case account.method_code
  when 'cash' then 'نقدي'
  when 'instant_transfer' then 'انستا'
  when 'wallet' then 'محفظة'
  when 'card' then 'فيزا'
  else account.display_label_ar
end
where account.account_kind = 'cash_method'
  and (
    account.display_label_ar is null
    or btrim(account.display_label_ar) = ''
  );

alter table public.ledger_accounts
  drop constraint if exists ledger_accounts_cash_label_check;

alter table public.ledger_accounts
  add constraint ledger_accounts_cash_label_check check (
    account_kind <> 'cash_method'
    or (
      display_label_ar is not null
      and length(btrim(display_label_ar)) between 1 and 40
      and display_label_ar !~ '[[:cntrl:]]'
    )
  );

create table if not exists private.payment_method_commands (
  shop_id uuid not null references public.shops (id),
  idempotency_key uuid not null,
  payload_sha256 bytea not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key (shop_id, idempotency_key)
);

revoke all on table private.payment_method_commands from public, anon, authenticated;

create or replace function private.default_cash_method_label(p_method text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case p_method
    when 'cash' then 'نقدي'
    when 'instant_transfer' then 'انستا'
    when 'wallet' then 'محفظة'
    when 'card' then 'فيزا'
    else null
  end;
$fn$;

revoke all on function private.default_cash_method_label(text) from public, anon;
grant execute on function private.default_cash_method_label(text) to authenticated;

create or replace function private.cash_method_label(p_shop uuid, p_method text)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_label text;
begin
  select nullif(btrim(account.display_label_ar), '') into v_label
  from public.ledger_accounts as account
  where account.shop_id = p_shop
    and account.account_kind = 'cash_method'
    and account.method_code = p_method;
  return coalesce(v_label, private.default_cash_method_label(p_method), p_method);
end;
$fn$;

revoke all on function private.cash_method_label(uuid, text) from public, anon;
grant execute on function private.cash_method_label(uuid, text) to authenticated;

create or replace function private.assert_active_cash_methods(p_shop uuid, p_payload jsonb)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_method text;
  v_tender jsonb;
begin
  if p_payload ? 'tenders' and jsonb_typeof(p_payload -> 'tenders') = 'array' then
    for v_tender in
      select value from jsonb_array_elements(p_payload -> 'tenders') as t(value)
    loop
      v_method := v_tender ->> 'method';
      if v_method is not null
        and exists (
          select 1
          from public.ledger_accounts as account
          where account.shop_id = p_shop
            and account.account_kind = 'cash_method'
            and account.method_code = v_method
            and account.archived_at is not null
        ) then
        raise exception 'method_archived';
      end if;
    end loop;
  end if;
  foreach v_method in array array[
    p_payload ->> 'from_method',
    p_payload ->> 'to_method',
    p_payload ->> 'method'
  ]
  loop
    if v_method is not null
      and exists (
        select 1
        from public.ledger_accounts as account
        where account.shop_id = p_shop
          and account.account_kind = 'cash_method'
          and account.method_code = v_method
          and account.archived_at is not null
      ) then
      raise exception 'method_archived';
    end if;
  end loop;
end;
$fn$;

revoke all on function private.assert_active_cash_methods(uuid, jsonb)
  from public, anon, authenticated;

create or replace function private.relabel_ledger_cash(p_shop uuid, p_cash jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_out jsonb := '[]'::jsonb;
  v_row jsonb;
  v_method text;
  v_piastres text;
  v_pounds text;
  v_label text;
  v_archived boolean;
  v_ord int;
begin
  if jsonb_typeof(p_cash) is distinct from 'array' then
    return p_cash;
  end if;
  for v_row in
    select value
    from jsonb_array_elements(p_cash) as c(value)
  loop
    v_method := v_row ->> 'method';
    v_piastres := v_row ->> 'piastres';
    v_pounds := v_row ->> 'pounds';
    select
      coalesce(nullif(btrim(account.display_label_ar), ''),
        private.default_cash_method_label(account.method_code), v_method),
      account.archived_at is not null,
      case account.method_code
        when 'cash' then 1
        when 'instant_transfer' then 2
        when 'wallet' then 3
        when 'card' then 4
        else 99
      end
    into v_label, v_archived, v_ord
    from public.ledger_accounts as account
    where account.shop_id = p_shop
      and account.account_kind = 'cash_method'
      and account.method_code = v_method;
    if v_label is null then
      v_label := coalesce(v_row ->> 'label_ar',
        private.default_cash_method_label(v_method), v_method);
      v_archived := false;
      v_ord := 99;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'method', v_method,
      'label_ar', v_label,
      'piastres', v_piastres,
      'pounds', v_pounds,
      'archived', coalesce(v_archived, false)
    ));
  end loop;
  return v_out;
end;
$fn$;

revoke all on function private.relabel_ledger_cash(uuid, jsonb)
  from public, anon, authenticated;

create or replace function private.snapshot_cash_labels_on_detail()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_tenders jsonb := '[]'::jsonb;
  v_tender jsonb;
  v_method text;
  v_label text;
  v_payload jsonb;
begin
  v_payload := NEW.payload;
  if v_payload ? 'tenders' and jsonb_typeof(v_payload -> 'tenders') = 'array' then
    for v_tender in
      select value from jsonb_array_elements(v_payload -> 'tenders') as t(value)
    loop
      v_method := v_tender ->> 'method';
      v_label := private.cash_method_label(NEW.shop_id, v_method);
      v_tenders := v_tenders || jsonb_build_array(
        (v_tender - 'label_ar') || jsonb_build_object('label_ar', v_label)
      );
    end loop;
    v_payload := v_payload || jsonb_build_object('tenders', v_tenders);
  end if;
  if v_payload ? 'from_method' then
    v_payload := v_payload || jsonb_build_object(
      'from_method_label_ar',
      private.cash_method_label(NEW.shop_id, v_payload ->> 'from_method')
    );
  end if;
  if v_payload ? 'to_method' then
    v_payload := v_payload || jsonb_build_object(
      'to_method_label_ar',
      private.cash_method_label(NEW.shop_id, v_payload ->> 'to_method')
    );
  end if;
  if v_payload ? 'method'
    and jsonb_typeof(v_payload -> 'method') = 'string'
    and not (v_payload ? 'method_label_ar') then
    v_payload := v_payload || jsonb_build_object(
      'method_label_ar',
      private.cash_method_label(NEW.shop_id, v_payload ->> 'method')
    );
  end if;
  NEW.payload := v_payload;
  return NEW;
end;
$fn$;

drop trigger if exists financial_operation_details_cash_labels
  on public.financial_operation_details;
create trigger financial_operation_details_cash_labels
before insert on public.financial_operation_details
for each row execute function private.snapshot_cash_labels_on_detail();

-- Ensure new cash_method rows get default labels (opening / financial_account create).
create or replace function private.financial_account(
  p_shop uuid, p_kind text, p_unit text, p_category text,
  p_karat smallint, p_method text, p_create boolean
)
returns uuid language plpgsql security definer set search_path = '' as $fn$
declare v_id uuid;
begin
  select account.id into v_id from public.ledger_accounts as account
  where account.shop_id = p_shop and account.account_kind = p_kind
    and account.unit_kind = p_unit
    and account.category_code is not distinct from p_category
    and account.karat is not distinct from p_karat
    and account.method_code is not distinct from p_method;
  if v_id is null and p_create then
    insert into public.ledger_accounts (
      shop_id, account_kind, unit_kind, currency_code,
      category_code, karat, method_code, display_label_ar
    ) values (
      p_shop, p_kind, p_unit,
      case when p_unit = 'money' then 'EGP' else null end,
      p_category, p_karat, p_method,
      case when p_kind = 'cash_method'
        then private.default_cash_method_label(p_method)
        else null
      end
    ) returning id into v_id;
  end if;
  return v_id;
end;
$fn$;

revoke all on function private.financial_account(
  uuid, text, text, text, smallint, text, boolean
) from public, anon, authenticated;

-- Allow historical tender snapshots (label_ar) through sum validation.
create or replace function private.validated_tender_sum(p_tenders jsonb)
returns numeric language plpgsql stable security invoker set search_path = '' as $fn$
declare
  v_tender jsonb;
  v_seen text[] := '{}';
  v_method text;
  v_amount bigint;
  v_sum numeric := 0;
begin
  if jsonb_typeof(p_tenders) is distinct from 'array'
    or jsonb_array_length(p_tenders) > 4 then
    raise exception 'invalid_input';
  end if;
  for v_tender in select value from jsonb_array_elements(p_tenders) loop
    if jsonb_typeof(v_tender) is distinct from 'object'
      or v_tender - 'method' - 'piastres' - 'label_ar' <> '{}'::jsonb
      or jsonb_typeof(v_tender -> 'method') is distinct from 'string'
      or jsonb_typeof(v_tender -> 'piastres') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any (v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := array_append(v_seen, v_method);
    v_amount := private.opening_checked_bigint(
      private.opening_parse_amount(v_tender ->> 'piastres'));
    if v_amount <= 0 then raise exception 'invalid_input'; end if;
    v_sum := v_sum + v_amount;
  end loop;
  return v_sum;
end;
$fn$;

revoke all on function private.validated_tender_sum(jsonb)
  from public, anon, authenticated;

create or replace function private.repair_tenders(p_tenders jsonb, p_expected bigint)
returns void
language plpgsql
stable
security invoker
set search_path = ''
as $fn$
declare
  v_tender jsonb;
  v_seen text[] := '{}';
  v_method text;
  v_sum bigint := 0;
begin
  if pg_catalog.jsonb_typeof(p_tenders) is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_tenders) not between 1 and 4 then
    raise exception 'invalid_input';
  end if;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_tenders) as tender(value)
  loop
    if pg_catalog.jsonb_typeof(v_tender) is distinct from 'object'
      or not (v_tender ?& array['method', 'piastres'])
      or v_tender - 'method' - 'piastres' - 'label_ar' <> '{}'::jsonb
      or pg_catalog.jsonb_typeof(v_tender -> 'method') is distinct from 'string' then
      raise exception 'invalid_input';
    end if;
    v_method := v_tender ->> 'method';
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any(v_seen) then
      raise exception 'invalid_input';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_method);
    v_sum := v_sum + private.repair_money(v_tender -> 'piastres', false);
  end loop;
  if v_sum <> p_expected then
    raise exception 'tender_mismatch';
  end if;
end;
$fn$;

revoke all on function private.repair_tenders(jsonb, bigint)
  from public, anon, authenticated;

-- Owner list / save
create or replace function public.list_shop_payment_methods_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_methods jsonb;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.require_shop_owner();
  select coalesce(jsonb_agg(jsonb_build_object(
    'account_id', account.id,
    'method', account.method_code,
    'label_ar', coalesce(
      nullif(btrim(account.display_label_ar), ''),
      private.default_cash_method_label(account.method_code)
    ),
    'archived', account.archived_at is not null,
    'archived_at', account.archived_at
  ) order by case account.method_code
    when 'cash' then 1
    when 'instant_transfer' then 2
    when 'wallet' then 3
    when 'card' then 4
    else 99
  end), '[]'::jsonb)
  into v_methods
  from public.ledger_accounts as account
  where account.shop_id = v_shop
    and account.account_kind = 'cash_method';
  return jsonb_build_object(
    'shop_id', v_shop,
    'methods', v_methods
  );
end;
$fn$;

revoke all on function public.list_shop_payment_methods_v1() from public, anon;
grant execute on function public.list_shop_payment_methods_v1() to authenticated;

create or replace function public.save_shop_payment_methods_v1(
  p_key uuid,
  p_methods jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_prior private.payment_method_commands%rowtype;
  v_hash bytea;
  v_item jsonb;
  v_method text;
  v_label text;
  v_archived boolean;
  v_seen text[] := '{}';
  v_active int := 0;
  v_account public.ledger_accounts%rowtype;
  v_result jsonb;
  v_at timestamptz := clock_timestamp();
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  if p_key is null or jsonb_typeof(p_methods) is distinct from 'array'
    or jsonb_array_length(p_methods) <> 4 then
    raise exception 'invalid_input';
  end if;
  v_shop := private.require_shop_owner();
  perform 1 from public.shops where id = v_shop for update;
  if not private.is_shop_owner(v_shop) then raise exception 'forbidden'; end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;

  v_hash := extensions.digest(convert_to(p_methods::text, 'UTF8'), 'sha256');
  select * into v_prior
  from private.payment_method_commands as cmd
  where cmd.shop_id = v_shop and cmd.idempotency_key = p_key;
  if found then
    if v_prior.payload_sha256 is distinct from v_hash then
      raise exception 'payload_mismatch';
    end if;
    return v_prior.result || jsonb_build_object('replayed', true);
  end if;

  for v_item in select value from jsonb_array_elements(p_methods) as m(value)
  loop
    if jsonb_typeof(v_item) is distinct from 'object'
      or jsonb_typeof(v_item -> 'method') is distinct from 'string'
      or jsonb_typeof(v_item -> 'label_ar') is distinct from 'string'
      or jsonb_typeof(v_item -> 'archived') is distinct from 'boolean'
      or v_item - 'method' - 'label_ar' - 'archived' <> '{}'::jsonb then
      raise exception 'invalid_input';
    end if;
    v_method := v_item ->> 'method';
    v_label := btrim(v_item ->> 'label_ar');
    v_archived := (v_item ->> 'archived')::boolean;
    if v_method not in ('cash', 'instant_transfer', 'wallet', 'card')
      or v_method = any (v_seen)
      or length(v_label) not between 1 and 40
      or v_label ~ '[[:cntrl:]]' then
      raise exception 'invalid_input';
    end if;
    v_seen := array_append(v_seen, v_method);
    if not v_archived then
      v_active := v_active + 1;
    end if;
  end loop;
  if cardinality(v_seen) <> 4 or v_active < 1 then
    raise exception 'invalid_input';
  end if;

  for v_item in select value from jsonb_array_elements(p_methods) as m(value)
  loop
    v_method := v_item ->> 'method';
    v_label := btrim(v_item ->> 'label_ar');
    v_archived := (v_item ->> 'archived')::boolean;
    select * into v_account
    from public.ledger_accounts as account
    where account.shop_id = v_shop
      and account.account_kind = 'cash_method'
      and account.method_code = v_method
    for update;
    if v_account.id is null then
      raise exception 'invalid_input';
    end if;
    update public.ledger_accounts as account
    set display_label_ar = v_label,
        archived_at = case
          when v_archived then coalesce(account.archived_at, v_at)
          else null
        end
    where account.id = v_account.id;
  end loop;

  v_result := public.list_shop_payment_methods_v1();
  insert into private.payment_method_commands (
    shop_id, idempotency_key, payload_sha256, result, created_at
  ) values (v_shop, p_key, v_hash, v_result, v_at);
  return v_result || jsonb_build_object('replayed', false);
end;
$fn$;

revoke all on function public.save_shop_payment_methods_v1(uuid, jsonb)
  from public, anon;
grant execute on function public.save_shop_payment_methods_v1(uuid, jsonb)
  to authenticated;

-- Live ledger cash labels + archive flag; reject archived on new trade/transfer.
create or replace function public.get_daily_ledger_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
begin
  perform private.allow_member_permission('ledger_read');
  v_result := public.get_daily_ledger_v2_before_staff();
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_role = 'employee' then
    if v_result ->> 'state' is distinct from 'confirmed' then
      return v_result;
    end if;
    return jsonb_build_object(
      'state', 'confirmed',
      'employee_ledger', true,
      'shop_id', v_shop,
      'balances_hidden', true
    );
  end if;
  if v_result ? 'cash' then
    v_result := v_result || jsonb_build_object(
      'cash', private.relabel_ledger_cash(v_shop, v_result -> 'cash')
    );
  end if;
  return v_result;
end;
$fn$;

revoke all on function public.get_daily_ledger_v2() from public, anon;
grant execute on function public.get_daily_ledger_v2() to authenticated;

create or replace function public.post_daily_ledger_trade_v2(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_kind text;
  v_perm text;
  v_shop uuid;
begin
  v_kind := p_payload ->> 'kind';
  v_perm := case
    when v_kind in ('sale', 'scrap_sale') then 'sale'
    when v_kind = 'purchase' then 'purchase'
    when v_kind = 'expense' then 'expense'
    else null
  end;
  if v_perm is null then raise exception 'invalid_input'; end if;
  perform private.allow_member_permission(v_perm);
  v_shop := private.opening_require_reader_shop();
  perform private.assert_active_cash_methods(v_shop, p_payload);
  return public.post_daily_ledger_trade_v2_before_staff(p_idempotency_key, p_payload);
end;
$fn$;

revoke all on function public.post_daily_ledger_trade_v2(uuid, jsonb) from public, anon;
grant execute on function public.post_daily_ledger_trade_v2(uuid, jsonb) to authenticated;

create or replace function public.post_daily_ledger_cash_transfer(
  p_idempotency_key uuid, p_payload jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
begin
  perform private.allow_member_permission('expense');
  v_shop := private.opening_require_reader_shop();
  perform private.assert_active_cash_methods(v_shop, p_payload);
  return public.post_daily_ledger_cash_transfer_before_staff(p_idempotency_key, p_payload);
end;
$fn$;

revoke all on function public.post_daily_ledger_cash_transfer(uuid, jsonb)
  from public, anon;
grant execute on function public.post_daily_ledger_cash_transfer(uuid, jsonb)
  to authenticated;

alter function public.settle_purchase_cash_payable(uuid, uuid, jsonb)
  rename to settle_purchase_cash_payable_before_methods;
revoke all on function public.settle_purchase_cash_payable_before_methods(
  uuid, uuid, jsonb
) from public, anon, authenticated;

create function public.settle_purchase_cash_payable(
  p_idempotency_key uuid,
  p_purchase_operation_id uuid,
  p_tenders jsonb
)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare
  v_shop uuid;
begin
  v_shop := private.opening_require_reader_shop();
  perform private.assert_active_cash_methods(
    v_shop,
    jsonb_build_object('tenders', p_tenders)
  );
  return public.settle_purchase_cash_payable_before_methods(
    p_idempotency_key, p_purchase_operation_id, p_tenders
  );
end;
$fn$;

revoke all on function public.settle_purchase_cash_payable(uuid, uuid, jsonb)
  from public, anon;
grant execute on function public.settle_purchase_cash_payable(uuid, uuid, jsonb)
  to authenticated;

commit;

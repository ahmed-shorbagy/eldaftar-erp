-- Repair revenue is in the day figures, and an outstanding fee can be
-- collected later on the open day (ADR 0042, A-D5, A-D6).
begin;

select private.compensation_extend_in_check(
  'public.financial_operations'::regclass,
  'financial_operations_kind_check',
  'kind',
  array['repair_fee_collection']
);
select private.compensation_extend_in_check(
  'public.financial_audit_events'::regclass,
  'financial_audit_events_action_check',
  'action',
  array['repair_fee_collection_confirmed']
);
select private.compensation_extend_in_check(
  'public.financial_outbox'::regclass,
  'financial_outbox_event_check',
  'event_type',
  array['repair_fee_collection_confirmed']
);
-- compensation_extend_in_check refuses an IN-list shorter than 8. These
-- two checks have five values, so they are extended with the same drop-and-add
-- the helper uses for the longer financial checks.
alter table public.repair_events drop constraint repair_events_type_check;
alter table public.repair_events add constraint repair_events_type_check check (
  event_type in (
    'repair_archive', 'repair_cancel', 'repair_collect', 'repair_handover',
    'repair_intake', 'repair_status'
  )
);
alter table public.repair_command_requests drop constraint repair_commands_kind_check;
alter table public.repair_command_requests add constraint repair_commands_kind_check check (
  command_kind in (
    'repair_archive', 'repair_cancel', 'repair_collect', 'repair_handover',
    'repair_intake', 'repair_status'
  )
);

-- A later collection after an unpaid handover keeps financial_operation_id
-- null. The first handover operation, when one exists, stays in that column.
alter table public.repairs drop constraint repairs_state_check;
alter table public.repairs add constraint repairs_state_check check (
  (
    status in ('received', 'in_progress', 'ready')
    and custody_held
    and final_fee_piastres is null
    and collected_piastres = 0
    and outstanding_piastres = 0
    and financial_operation_id is null
    and cancellation_reason is null
    and archived_from_status is null
  )
  or (
    status = 'delivered'
    and not custody_held
    and final_fee_piastres is not null
    and collected_piastres <= final_fee_piastres
    and outstanding_piastres = final_fee_piastres - collected_piastres
    and cancellation_reason is null
    and archived_from_status is null
    and (
      (collected_piastres = 0 and financial_operation_id is null)
      or collected_piastres > 0
    )
  )
  or (
    status = 'cancelled'
    and not custody_held
    and final_fee_piastres is null
    and collected_piastres = 0
    and outstanding_piastres = 0
    and financial_operation_id is null
    and cancellation_reason is not null
    and archived_from_status is null
  )
  or (
    status = 'archived'
    and not custody_held
    and (
      (
        archived_from_status = 'delivered'
        and final_fee_piastres is not null
        and collected_piastres <= final_fee_piastres
        and outstanding_piastres = final_fee_piastres - collected_piastres
        and (
          (collected_piastres = 0 and financial_operation_id is null)
          or collected_piastres > 0
        )
      )
      or (
        archived_from_status = 'cancelled'
        and final_fee_piastres is null
        and collected_piastres = 0
        and outstanding_piastres = 0
        and financial_operation_id is null
        and cancellation_reason is not null
      )
    )
  )
);

create table public.repair_fee_collections (
  id uuid primary key default pg_catalog.gen_random_uuid(),
  shop_id uuid not null,
  repair_id uuid not null,
  operation_id uuid not null,
  piastres bigint not null check (piastres > 0),
  actor_user_id uuid not null,
  created_at timestamptz not null,
  constraint repair_fee_collections_repair_fkey foreign key (shop_id, repair_id)
    references public.repairs (shop_id, id),
  constraint repair_fee_collections_operation_fkey foreign key (shop_id, operation_id)
    references public.financial_operations (shop_id, id),
  constraint repair_fee_collections_actor_fkey foreign key (shop_id, actor_user_id)
    references public.shop_memberships (shop_id, user_id)
);
create index repair_fee_collections_repair_idx
  on public.repair_fee_collections (shop_id, repair_id, created_at);
alter table public.repair_fee_collections enable row level security;
revoke all on table public.repair_fee_collections from public, anon, authenticated;

create trigger repair_fee_collections_append_only
  before update or delete on public.repair_fee_collections
  for each row execute function private.repair_reject_mutation();

create or replace function private.ledger_operation_label(p_kind text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case p_kind
    when 'opening_balances' then 'رصيد افتتاحي'
    when 'sale' then 'بيع'
    when 'purchase' then 'شراء'
    when 'expense' then 'مصروف'
    when 'purchase_settlement' then 'سداد شراء'
    when 'cash_transfer' then 'تحويل نقدية'
    when 'scrap_sale' then 'بيع كسر'
    when 'scrap_to_stock' then 'تحويل كسر إلى مخزون'
    when 'sale_return' then 'مرتجع بيع'
    when 'purchase_return' then 'مرتجع شراء'
    when 'customer_return' then 'مرتجع'
    when 'close_day' then 'تقفيل اليومية'
    when 'open_day' then 'فتح اليومية'
    when 'ledger_correction' then 'تسوية فرق الجرد'
    when 'exchange' then 'استبدال'
    when 'daily_note' then 'ملاحظة يومية'
    when 'repair_fee' then 'أجرة إصلاح'
    when 'repair_fee_collection' then 'تحصيل متبقي صيانة'
    when 'debt_settlement' then 'سداد دين'
    when 'gold_obligation_acquisition' then 'استلام ذهب مقابل التزام'
    when 'gold_obligation_settlement' then 'سداد التزام ذهب'
    else null
  end;
$fn$;
revoke all on function private.ledger_operation_label(text) from public, anon, authenticated;

-- Day summary gains repair cash. The live function already hides edited trades.
do $patch_date$
declare
  v_def text;
  v_old text := $old$v_summary := v_summary || jsonb_build_object('gold_by_bucket', coalesce(v_gold, '[]'::jsonb));$old$;
  v_new text := $new$v_summary := v_summary || jsonb_build_object('gold_by_bucket', coalesce(v_gold, '[]'::jsonb));
  v_summary := v_summary || (
    select pg_catalog.jsonb_build_object(
      'repair_piastres', coalesce(sum(posting.amount) filter (
        where account.account_kind = 'cash_method'), 0)::text,
      'repair_count', count(distinct operation.id)
    )
    from public.financial_operations as operation
    left join public.journal_postings as posting
      on posting.shop_id = operation.shop_id and posting.operation_id = operation.id
    left join public.ledger_accounts as account
      on account.shop_id = posting.shop_id and account.id = posting.account_id
    where operation.shop_id = v_shop
      and operation.business_day_id = any (v_day_ids)
      and operation.kind in ('repair_fee', 'repair_fee_collection')
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
  );$new$;
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.get_ledger_date_v1_before_staff(date, text, integer)'::regprocedure
  );
  if pg_catalog.strpos(v_def, v_old) <> 1
    and (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
      / pg_catalog.length(v_old) <> 1 then
    raise exception 'repair_day_summary_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_date$;

do $patch_report$
declare
  v_def text;
  v_old text := $old$'return_count',count(*) filter(where not hidden and kind in ('sale_return','purchase_return','customer_return'))::text,$old$;
  v_new text := $new$'return_count',count(*) filter(where not hidden and kind in ('sale_return','purchase_return','customer_return'))::text,
      'repair_piastres',coalesce(sum(cash) filter(where not hidden and kind in ('repair_fee','repair_fee_collection')),0)::text,
      'repair_count',count(*) filter(where not hidden and kind in ('repair_fee','repair_fee_collection'))::text,$new$;
begin
  v_def := pg_catalog.pg_get_functiondef(
    'public.get_financial_day_report_v1_before_staff(uuid)'::regprocedure
  );
  if (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
      / pg_catalog.length(v_old) <> 1 then
    raise exception 'repair_day_report_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_report$;

do $patch_detail$
declare
  v_def text;
  v_old text := $old$'custody_events', v_custody$old$;
  v_new text := $new$'collections', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'operation_id', collection.operation_id,
        'piastres', collection.piastres::text,
        'created_at_shop', pg_catalog.to_char(
          collection.created_at at time zone v_zone, 'YYYY-MM-DD"T"HH24:MI:SS'
        )
      ) order by collection.created_at, collection.id)
      from public.repair_fee_collections as collection
      where collection.shop_id = v_shop and collection.repair_id = v_repair.id
    ), '[]'::jsonb),
    'custody_events', v_custody$new$;
begin
  v_def := pg_catalog.pg_get_functiondef('public.get_repair_v1(uuid)'::regprocedure);
  if (pg_catalog.length(v_def) - pg_catalog.length(pg_catalog.replace(v_def, v_old, '')))
      / pg_catalog.length(v_old) <> 1 then
    raise exception 'repair_collections_anchor';
  end if;
  execute pg_catalog.replace(v_def, v_old, v_new);
end;
$patch_detail$;

create or replace function private.repair_guard()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'DELETE' then
    raise exception 'audit_append_only';
  end if;
  if tg_op = 'INSERT' then
    if new.status <> 'received'
      or new.record_version <> 1
      or not new.custody_held
      or new.final_fee_piastres is not null
      or new.collected_piastres <> 0
      or new.outstanding_piastres <> 0
      or new.financial_operation_id is not null
      or new.cancellation_reason is not null
      or new.archived_from_status is not null then
      raise exception 'invalid_input';
    end if;
    return new;
  end if;
  if new.id is distinct from old.id
    or new.shop_id is distinct from old.shop_id
    or new.customer_name is distinct from old.customer_name
    or new.customer_phone is distinct from old.customer_phone
    or new.item_description is distinct from old.item_description
    or new.measured_milligrams is distinct from old.measured_milligrams
    or new.karat is distinct from old.karat
    or new.issue is distinct from old.issue
    or new.intake_notes is distinct from old.intake_notes
    or new.estimated_fee_piastres is distinct from old.estimated_fee_piastres
    or new.intake_payload is distinct from old.intake_payload
    or new.intake_actor_user_id is distinct from old.intake_actor_user_id
    or new.intake_at is distinct from old.intake_at then
    raise exception 'audit_append_only';
  end if;
  if new.record_version is distinct from old.record_version + 1 then
    raise exception 'stale_repair';
  end if;
  if old.status in ('delivered', 'archived')
    and pg_catalog.current_setting('eldaftar.repair_collect', true) = 'on'
    and new.status is not distinct from old.status
    and new.collected_piastres > old.collected_piastres
    and new.outstanding_piastres >= 0
    and new.outstanding_piastres = old.outstanding_piastres
      - (new.collected_piastres - old.collected_piastres)
    and new.custody_held is not distinct from old.custody_held
    and new.final_fee_piastres is not distinct from old.final_fee_piastres
    and new.financial_operation_id is not distinct from old.financial_operation_id
    and new.cancellation_reason is not distinct from old.cancellation_reason
    and new.archived_from_status is not distinct from old.archived_from_status then
    return new;
  end if;
  if old.status = 'archived' or new.status = old.status then
    raise exception 'audit_append_only';
  end if;
  if old.status = 'received' and new.status = 'in_progress' then
    if new.custody_held
      and new.final_fee_piastres is null
      and new.collected_piastres = 0
      and new.outstanding_piastres = 0
      and new.financial_operation_id is null
      and new.cancellation_reason is null
      and new.archived_from_status is null then
      return new;
    end if;
  elsif old.status = 'in_progress' and new.status = 'ready' then
    if new.custody_held
      and new.final_fee_piastres is null
      and new.collected_piastres = 0
      and new.outstanding_piastres = 0
      and new.financial_operation_id is null
      and new.cancellation_reason is null
      and new.archived_from_status is null then
      return new;
    end if;
  elsif old.status = 'ready' and new.status = 'delivered' then
    if not new.custody_held
      and new.cancellation_reason is null
      and new.archived_from_status is null
      and new.final_fee_piastres is not null
      and new.collected_piastres between 0 and new.final_fee_piastres
      and new.outstanding_piastres = new.final_fee_piastres - new.collected_piastres
      and (
        (new.collected_piastres = 0 and new.financial_operation_id is null)
        or (new.collected_piastres > 0 and new.financial_operation_id is not null)
      ) then
      return new;
    end if;
  elsif old.status in ('received', 'in_progress', 'ready')
    and new.status = 'cancelled' then
    if not new.custody_held
      and new.final_fee_piastres is null
      and new.collected_piastres = 0
      and new.outstanding_piastres = 0
      and new.financial_operation_id is null
      and new.cancellation_reason is not null
      and new.archived_from_status is null then
      return new;
    end if;
  elsif old.status in ('delivered', 'cancelled') and new.status = 'archived' then
    if new.archived_from_status = old.status
      and new.custody_held = old.custody_held
      and new.final_fee_piastres is not distinct from old.final_fee_piastres
      and new.collected_piastres = old.collected_piastres
      and new.outstanding_piastres = old.outstanding_piastres
      and new.financial_operation_id is not distinct from old.financial_operation_id
      and new.cancellation_reason is not distinct from old.cancellation_reason then
      return new;
    end if;
  end if;
  raise exception 'invalid_input';
end;
$fn$;
revoke all on function private.repair_guard() from public, anon, authenticated;

create function private.repair_post_collection(
  p_shop uuid, p_repair uuid, p_key uuid, p_payload jsonb, p_hash text,
  p_actor uuid, p_at timestamptz, p_collected bigint, p_day uuid,
  p_day_version bigint
) returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_day public.business_days%rowtype;
  v_hash bytea := pg_catalog.decode(p_hash, 'hex');
  v_sequence bigint;
  v_op uuid;
  v_journal uuid;
  v_clear uuid;
  v_account uuid;
  v_tender jsonb;
  v_amount bigint;
begin
  perform 1 from public.financial_command_requests as request
  where request.shop_id = p_shop and request.idempotency_key = p_key
  for update;
  if found then
    raise exception 'payload_mismatch';
  end if;
  select day.* into v_day
  from public.business_days as day
  where day.shop_id = p_shop and day.id = p_day
  for update;
  if v_day.id is null or v_day.status <> 'open' then
    raise exception 'day_closed';
  end if;
  if v_day.day_version <> p_day_version then
    raise exception 'stale_day';
  end if;
  select coalesce(pg_catalog.max(operation.shop_sequence), 0) + 1
    into v_sequence
  from public.financial_operations as operation
  where operation.shop_id = p_shop;
  insert into public.financial_operations (
    shop_id, shop_sequence, kind, business_day_id, actor_user_id, created_at
  ) values (p_shop, v_sequence, 'repair_fee_collection', v_day.id, p_actor, p_at)
  returning id into v_op;
  insert into public.financial_operation_details (
    operation_id, shop_id, payload, created_at
  ) values (v_op, p_shop, p_payload || (
    select pg_catalog.jsonb_build_object(
      'total_piastres', p_collected::text,
      'outstanding_piastres', ((p_payload ->> 'final_fee_piastres')::bigint - p_collected)::text,
      'customer_name', repair.customer_name,
      'customer_phone', repair.customer_phone,
      'description', repair.item_description
    ) from public.repairs as repair
    where repair.id = p_repair and repair.shop_id = p_shop
  ), p_at);
  update public.business_days
    set day_version = day_version + 1
  where id = v_day.id;
  v_clear := private.financial_account(
    p_shop, 'movement_money_clearing', 'money', null, null, null, true
  );
  insert into public.journals (
    shop_id, operation_id, unit_kind, currency_code, bucket_key
  ) values (p_shop, v_op, 'money', 'EGP', 'money')
  returning id into v_journal;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') as tender(value)
  loop
    v_account := private.financial_account(
      p_shop, 'cash_method', 'money', null, null, v_tender ->> 'method', false
    );
    if v_account is null then
      raise exception 'invalid_input';
    end if;
    v_amount := private.repair_money(v_tender -> 'piastres', false);
    insert into public.journal_postings (
      shop_id, journal_id, account_id, operation_id, amount
    ) values (p_shop, v_journal, v_account, v_op, v_amount);
  end loop;
  insert into public.journal_postings (
    shop_id, journal_id, account_id, operation_id, amount
  ) values (p_shop, v_journal, v_clear, v_op, -p_collected);
  insert into public.financial_audit_events (
    shop_id, actor_user_id, action, operation_id, created_at, details
  ) values (
    p_shop, p_actor, 'repair_fee_collection_confirmed', v_op, p_at,
    pg_catalog.jsonb_build_object(
      'business_day_id', v_day.id,
      'operation_id', v_op,
      'repair_id', p_repair,
      'collected_piastres', p_collected::text
    )
  );
  insert into public.financial_outbox (
    shop_id, operation_id, event_type, created_at
  ) values (p_shop, v_op, 'repair_fee_collection_confirmed', p_at);
  insert into public.financial_command_requests (
    shop_id, idempotency_key, payload_canonical, payload_sha256,
    operation_id, created_at
  ) values (p_shop, p_key, p_payload, v_hash, v_op, p_at);
  return v_op;
end;
$fn$;
revoke all on function private.repair_post_collection(uuid, uuid, uuid, jsonb, text, uuid, timestamptz, bigint, uuid, bigint)
  from public, anon, authenticated;

create function public.post_repair_collect_v1(
  p_idempotency_key uuid, p_payload jsonb
) returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_claim_payload jsonb;
  v_claim jsonb;
  v_shop uuid;
  v_repair public.repairs%rowtype;
  v_expected bigint;
  v_amount bigint;
  v_day uuid;
  v_day_version bigint;
  v_actor uuid;
  v_actor_name text;
  v_at timestamptz;
  v_op uuid;
  v_version bigint;
  v_collected bigint;
  v_outstanding bigint;
  v_method text;
  v_seen text[] := '{}';
  v_tender jsonb;
  v_sum bigint := 0;
  v_result jsonb;
begin
  perform private.repair_allow_keys(
    p_payload,
    array['version', 'repair_id', 'expected_version', 'day_id', 'day_version', 'amount_piastres', 'tenders'],
    array[]::text[]
  );
  -- repair_claim requires kind. The public contract does not, so the stored
  -- command payload is the contract plus that one key.
  v_claim_payload := p_payload || pg_catalog.jsonb_build_object('kind', 'repair_collect');
  v_claim := private.repair_claim(p_idempotency_key, v_claim_payload, 'repair_collect');
  if (v_claim ->> 'continue') = 'false' then
    return v_claim -> 'result';
  end if;
  v_shop := (v_claim ->> 'shop_id')::uuid;
  if private.shop_member_role(v_shop) is distinct from 'owner' then
    raise exception 'forbidden';
  end if;
  v_expected := private.repair_money(p_payload -> 'expected_version', false);
  v_amount := private.repair_money(p_payload -> 'amount_piastres', false);
  v_day := private.repair_uuid(p_payload -> 'day_id');
  v_day_version := private.repair_money(p_payload -> 'day_version', false);
  if pg_catalog.jsonb_typeof(p_payload -> 'tenders') is distinct from 'array'
    or pg_catalog.jsonb_array_length(p_payload -> 'tenders') < 1
    or pg_catalog.jsonb_array_length(p_payload -> 'tenders') > 4 then
    raise exception 'tender_mismatch';
  end if;
  for v_tender in
    select value from pg_catalog.jsonb_array_elements(p_payload -> 'tenders') as tender(value)
  loop
    v_method := v_tender ->> 'method';
    if v_method is null or v_method = any (v_seen)
      or not exists (
        select 1 from public.ledger_accounts as account
        where account.shop_id = v_shop
          and account.account_kind = 'cash_method'
          and account.method_code = v_method
          and account.archived_at is null
      ) then
      raise exception 'tender_mismatch';
    end if;
    v_seen := pg_catalog.array_append(v_seen, v_method);
    v_sum := v_sum + private.repair_money(v_tender -> 'piastres', false);
  end loop;
  if v_sum <> v_amount then
    raise exception 'tender_mismatch';
  end if;
  perform private.repair_tenders(p_payload -> 'tenders', v_amount);
  v_repair := private.repair_lock(
    v_shop, private.repair_uuid(p_payload -> 'repair_id'), v_expected
  );
  if v_repair.status not in ('delivered', 'archived') then
    raise exception 'repair_not_delivered';
  end if;
  if v_amount > v_repair.outstanding_piastres then
    raise exception 'invalid_input';
  end if;
  v_actor := auth.uid();
  select shop.owner_display_name into v_actor_name
  from public.shops as shop where shop.id = v_shop;
  v_at := pg_catalog.clock_timestamp();
  v_op := private.repair_post_collection(
    v_shop, v_repair.id, p_idempotency_key, v_claim_payload, v_claim ->> 'hash',
    v_actor, v_at, v_amount, v_day, v_day_version
  );
  v_collected := v_repair.collected_piastres + v_amount;
  v_outstanding := v_repair.outstanding_piastres - v_amount;
  perform set_config('eldaftar.repair_collect', 'on', true);
  update public.repairs
    set collected_piastres = v_collected,
        outstanding_piastres = v_outstanding,
        record_version = record_version + 1,
        updated_at = v_at
  where id = v_repair.id
  returning record_version into v_version;
  perform set_config('eldaftar.repair_collect', 'off', true);
  insert into public.repair_fee_collections (
    shop_id, repair_id, operation_id, piastres, actor_user_id, created_at
  ) values (v_shop, v_repair.id, v_op, v_amount, v_actor, v_at);
  perform private.repair_event(
    v_shop, v_repair.id, 'repair_collect', v_actor, v_actor_name, v_at,
    pg_catalog.jsonb_build_object(
      'amount_piastres', v_amount::text,
      'collected_piastres', v_collected::text,
      'outstanding_piastres', v_outstanding::text,
      'operation_id', v_op
    )
  );
  perform private.bump_shop_sync(v_shop, 'repair');
  v_result := pg_catalog.jsonb_build_object(
    'ok', true,
    'replayed', false,
    'repair_id', v_repair.id,
    'status', v_repair.status,
    'record_version', v_version::text,
    'final_fee_piastres', v_repair.final_fee_piastres::text,
    'collected_piastres', v_collected::text,
    'outstanding_piastres', v_outstanding::text,
    'custody_released_milligrams', '0',
    'stock_milligrams', '0',
    'operation_id', v_op,
    'collection_operation_id', v_op,
    'business_day_id', v_day,
    'day_version', (v_day_version + 1)::text
  );
  return private.repair_finish(
    v_shop, p_idempotency_key, 'repair_collect', v_claim_payload,
    v_claim ->> 'hash', v_repair.id, v_result
  );
end;
$fn$;

revoke all on function public.post_repair_collect_v1(uuid, jsonb) from public, anon;
grant execute on function public.post_repair_collect_v1(uuid, jsonb) to authenticated;

-- 20261027140000 dropped the zero-collection branch. Unpaid handover still
-- sends an empty tender list, and later collection starts from that handover.
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
  if pg_catalog.jsonb_typeof(p_tenders) is distinct from 'array' then
    raise exception 'invalid_input';
  end if;
  if p_expected = 0 then
    if pg_catalog.jsonb_array_length(p_tenders) <> 0 then
      raise exception 'invalid_input';
    end if;
    return;
  end if;
  if pg_catalog.jsonb_array_length(p_tenders) not between 1 and 4 then
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

notify pgrst, 'reload schema';
commit;

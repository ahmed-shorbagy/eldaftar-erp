-- ADR 0033 employee ledger: the current app could not read an employee's
-- ledger at all (2026-11-15 end-to-end run).
--
-- * get_daily_ledger_home_v2 returned a five-field stub for employees, which
--   the app rejects (no read_model_version, cash, business_day or day_summary).
-- * get_ledger_date_v2 / get_ledger_day_v1 kept only feed items whose
--   `actor_user_id` matched, but feed items carry no actor id, so an employee
--   always got an empty day; the employee read also dropped `day_summary`,
--   which the app requires.
--
-- An employee now receives the same read model as the owner, built only from
-- the operations they recorded: their feed, their own day totals and gold
-- movement. Shop balances are never sent: cash lines keep the method labels
-- the sale form needs, with zero amounts, and stock and scrap are empty. The
-- app hides the cash tile for employees. Owners and partners are unchanged.

begin;

-- Day totals and gold movement for one actor's operations on the given days.
create or replace function private.ledger_actor_day_summary(
  p_shop uuid,
  p_days uuid[],
  p_actor uuid
)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  with own as (
    select operation.id, operation.kind, operation.shop_id
    from public.financial_operations as operation
    where operation.shop_id = p_shop
      and operation.business_day_id = any (coalesce(p_days, '{}'))
      and operation.actor_user_id = p_actor
      and not private.ledger_trade_hidden(operation.shop_id, operation.id)
  )
  select pg_catalog.jsonb_build_object(
    'sale_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where own.kind in ('sale', 'scrap_sale')), 0)::text,
    'purchase_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where own.kind = 'purchase'), 0)::text,
    'expense_piastres', coalesce(sum((detail.payload ->> 'total_piastres')::numeric)
      filter (where own.kind = 'expense'), 0)::text,
    'sale_count', count(*) filter (where own.kind in ('sale', 'scrap_sale')),
    'purchase_count', count(*) filter (where own.kind = 'purchase'),
    'expense_count', count(*) filter (where own.kind = 'expense'),
    'repair_piastres', '0',
    'repair_count', 0,
    'gold_by_bucket', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'kind', bucket.kind,
        'category', bucket.category,
        'karat', bucket.karat,
        'milligrams', bucket.milligrams::text,
        'count', bucket.pieces::text
      ) order by bucket.kind, bucket.category, bucket.karat)
      from (
        select case when gold.kind = 'scrap_sale' then 'sale' else gold.kind end as kind,
          item.value ->> 'category' as category,
          (item.value ->> 'karat')::smallint as karat,
          sum((item.value ->> 'milligrams')::numeric) as milligrams,
          sum(coalesce((item.value ->> 'count')::numeric, 0)) as pieces
        from own as gold
        join public.financial_operation_details as gold_detail
          on gold_detail.shop_id = gold.shop_id and gold_detail.operation_id = gold.id
        cross join lateral pg_catalog.jsonb_array_elements(
          case
            when pg_catalog.jsonb_typeof(gold_detail.payload -> 'items') = 'array'
              then gold_detail.payload -> 'items'
            else '[]'::jsonb
          end
        ) as item(value)
        where gold.kind in ('sale', 'purchase', 'scrap_sale')
        group by 1, 2, 3
      ) as bucket
    ), '[]'::jsonb)
  )
  from own
  left join public.financial_operation_details as detail
    on detail.shop_id = own.shop_id and detail.operation_id = own.id;
$fn$;
revoke all on function private.ledger_actor_day_summary(uuid, uuid[], uuid) from public, anon, authenticated;

-- The recorder's name: the shop's owner name for the owner (kept current by the
-- profile screen), the staff member's display name otherwise.
create or replace function private.ledger_actor_name(p_shop uuid, p_actor uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $fn$
  select case
    when membership.role = 'owner' then nullif(pg_catalog.btrim(shop.owner_display_name), '')
    else nullif(pg_catalog.btrim(identity.raw_user_meta_data ->> 'display_name'), '')
  end
  from public.shops as shop
  left join public.shop_memberships as membership
    on membership.shop_id = shop.id and membership.user_id = p_actor
  left join auth.users as identity on identity.id = p_actor
  where shop.id = p_shop;
$fn$;
revoke all on function private.ledger_actor_name(uuid, uuid) from public, anon, authenticated;

-- Feed rows named their recorder from `shops.owner_display_name`, a leftover
-- from owner-only shops: every staff operation showed the owner as recorder.
-- Name each row from its operation's actor, by role.
create or replace function private.feed_with_actor_names(p_shop uuid, p_items jsonb)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $fn$
  select case
    when pg_catalog.jsonb_typeof(p_items) is distinct from 'array' then p_items
    else coalesce((
      select pg_catalog.jsonb_agg(
        case
          when operation.actor_user_id is not null and item.value ? 'actor_display_name'
            then item.value || pg_catalog.jsonb_build_object(
              'actor_display_name',
              coalesce(
                private.ledger_actor_name(p_shop, operation.actor_user_id),
                item.value ->> 'actor_display_name'
              )
            )
          else item.value
        end
        order by item.ordinality
      )
      from pg_catalog.jsonb_array_elements(p_items) with ordinality as item(value, ordinality)
      left join public.financial_operations as operation
        on operation.shop_id = p_shop
       and operation.id = case
         when (item.value ->> 'operation_id') ~ '^[0-9a-f-]{36}$'
           then (item.value ->> 'operation_id')::uuid
       end
    ), '[]'::jsonb)
  end;
$fn$;
revoke all on function private.feed_with_actor_names(uuid, jsonb) from public, anon, authenticated;

-- Date reads: name each row by its recorder; filter an employee's page by the
-- recorded actor of each operation, and replace the shop summary with their own.
create or replace function public.get_ledger_date_v1_before_note_change(
  p_business_date date,
  p_before_sequence text,
  p_limit integer
)
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
  v_days uuid[];
begin
  perform private.allow_member_permission('ledger_read');
  v_result := public.get_ledger_date_v1_before_staff(
    p_business_date, p_before_sequence, p_limit
  );
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  if v_result #> '{feed_page,items}' is not null then
    v_result := pg_catalog.jsonb_set(
      v_result, '{feed_page,items}',
      private.feed_with_actor_names(v_shop, v_result #> '{feed_page,items}')
    );
  end if;
  if v_role = 'employee' and v_result ? 'feed_page' then
    v_result := pg_catalog.jsonb_set(
      v_result,
      '{feed_page,items}',
      coalesce((
        select pg_catalog.jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
        from pg_catalog.jsonb_array_elements(v_result #> '{feed_page,items}') as item
        join public.financial_operations as operation
          on operation.shop_id = v_shop
         and operation.id = (item ->> 'operation_id')::uuid
        where operation.actor_user_id = auth.uid()
      ), '[]'::jsonb)
    );
    select coalesce(pg_catalog.array_agg(day.value::uuid), '{}'::uuid[]) into v_days
    from pg_catalog.jsonb_array_elements_text(
      coalesce(v_result -> 'day_ids', '[]'::jsonb)
    ) as day(value);
    v_result := v_result || pg_catalog.jsonb_build_object(
      'day_summary', private.ledger_actor_day_summary(v_shop, v_days, auth.uid())
    );
  end if;
  return v_result;
end;
$fn$;
revoke all on function public.get_ledger_date_v1_before_note_change(date, text, integer)
  from public, anon, authenticated;

-- The closed-day read recomputes a shop-wide summary whenever the date read
-- carries one; an employee gets their own instead.
create or replace function public.get_ledger_day_v1(
  p_day_id uuid,
  p_before_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_prev text := private.begin_member_permission('ledger_read');
  v_result jsonb;
  v_shop uuid;
begin
  v_result := public.get_ledger_day_v1_before_grant_fix(p_day_id, p_before_sequence, p_limit);
  if private.caller_is_employee() and v_result ? 'day_summary' then
    v_shop := private.opening_require_reader_shop();
    v_result := v_result || pg_catalog.jsonb_build_object(
      'day_summary', private.ledger_actor_day_summary(v_shop, array[p_day_id], auth.uid())
    );
  end if;
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;

-- Operation pages (partners and owners) name rows by their recorder.
create or replace function public.get_ledger_operation_page_v2(
  p_day_id uuid,
  p_before_sequence text,
  p_after_sequence text,
  p_limit integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_prev text;
  v_result jsonb;
begin
  if private.caller_is_employee() then
    raise exception 'forbidden';
  end if;
  v_prev := private.begin_member_permission('ledger_read');
  v_result := public.get_ledger_operation_page_v2_before_grant_fix(
    p_day_id, p_before_sequence, p_after_sequence, p_limit
  );
  if pg_catalog.jsonb_typeof(v_result -> 'items') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{items}',
      private.feed_with_actor_names(private.opening_require_reader_shop(), v_result -> 'items')
    );
  end if;
  perform private.end_member_permission(v_prev);
  return v_result;
end;
$fn$;

-- Operation detail names its recorder (it used the owner's name).
create or replace function public.get_daily_ledger_operation(p_operation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_shop uuid;
  v_role text;
  v_actor uuid;
begin
  perform private.allow_member_permission('ledger_read');
  v_result := public.get_daily_ledger_operation_before_staff(p_operation_id);
  v_shop := private.opening_require_reader_shop();
  v_role := private.shop_member_role(v_shop);
  select operation.actor_user_id into v_actor
  from public.financial_operations as operation
  where operation.shop_id = v_shop and operation.id = p_operation_id;
  if v_role = 'employee' and v_actor is distinct from auth.uid() then
    raise exception 'forbidden';
  end if;
  if v_actor is not null and v_result ? 'actor_display_name' then
    v_result := v_result || pg_catalog.jsonb_build_object(
      'actor_display_name',
      coalesce(
        private.ledger_actor_name(v_shop, v_actor),
        v_result ->> 'actor_display_name'
      )
    );
  end if;
  return v_result;
end;
$fn$;

-- The employee home in the current read model (version 3).
create or replace function private.employee_ledger_home()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_base jsonb;
  v_date jsonb;
  v_zone text;
  v_open_days uuid[];
  v_open_date date;
  v_last_closed date;
  v_at timestamptz := pg_catalog.now();
  v_next timestamptz;
  v_feed jsonb;
  v_own_open bigint;
  v_cash jsonb;
begin
  v_shop := private.opening_require_reader_shop();
  v_base := public.get_daily_ledger_v2_before_staff();
  if v_base ->> 'state' is distinct from 'confirmed' then
    return v_base;
  end if;

  select private.shop_display_zone(shop.time_zone) into v_zone
  from public.shops as shop where shop.id = v_shop;
  v_next := (((v_at at time zone v_zone)::date + 1)::timestamp at time zone v_zone);
  select pg_catalog.array_agg(day.id) into v_open_days
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open';
  select day.business_date into v_open_date
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'open'
  order by day.opened_at desc, day.id desc
  limit 1;
  select day.business_date into v_last_closed
  from public.business_days as day
  where day.shop_id = v_shop and day.status = 'closed'
  order by day.opened_at desc, day.id desc
  limit 1;

  -- Method labels for the sale form; never the shop's balances.
  select coalesce(pg_catalog.jsonb_agg(
      line || pg_catalog.jsonb_build_object('piastres', '0', 'pounds', '0.00')
      order by ordinality
    ), '[]'::jsonb)
    into v_cash
  from pg_catalog.jsonb_array_elements(
    private.relabel_ledger_cash(v_shop, v_base -> 'cash')
  ) with ordinality as cash(line, ordinality);

  v_base := v_base || pg_catalog.jsonb_build_object(
    'read_model_version', 3,
    'cash', v_cash,
    'stock', '[]'::jsonb,
    'scrap', '[]'::jsonb,
    'last_closed_business_date', v_last_closed
  );

  -- get_ledger_date_v2 already limits the page to this employee's operations.
  v_date := public.get_ledger_date_v2(v_open_date, null, 100);

  if v_open_days is null then
    return v_base || pg_catalog.jsonb_build_object(
      'feed', '[]'::jsonb,
      'feed_page', pg_catalog.jsonb_build_object(
        'limit', 100, 'has_more', false, 'direction', 'desc',
        'next_before_sequence', null,
        'server_sequence', v_date #> '{feed_page,server_sequence}',
        'snapshot_sequence', v_date #> '{feed_page,snapshot_sequence}'
      ),
      'day_summary', private.ledger_actor_day_summary(v_shop, '{}', auth.uid()),
      'journal_context', pg_catalog.jsonb_build_object(
        'business_date', v_last_closed,
        'day_ids', '[]'::jsonb,
        'server_now', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'next_midnight_at', pg_catalog.to_char(v_next at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'return_count', 0,
        'note_count', 0
      ),
      'day_reset', true
    );
  end if;

  v_feed := coalesce((
    select pg_catalog.jsonb_agg(item order by (item ->> 'shop_sequence')::bigint desc)
    from pg_catalog.jsonb_array_elements(v_date #> '{feed_page,items}') as item
    join public.financial_operations as operation
      on operation.shop_id = v_shop
     and operation.id = (item ->> 'operation_id')::uuid
    where operation.business_day_id = any (v_open_days)
      and operation.actor_user_id = auth.uid()
  ), '[]'::jsonb);
  select count(*) into v_own_open
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = any (v_open_days)
    and operation.actor_user_id = auth.uid()
    and not private.ledger_trade_hidden(operation.shop_id, operation.id)
    and not private.daily_note_deleted(operation.shop_id, operation.id);

  return v_base || pg_catalog.jsonb_build_object(
    'feed', v_feed,
    'feed_page', pg_catalog.jsonb_build_object(
      'limit', 100,
      'has_more', v_own_open > pg_catalog.jsonb_array_length(v_feed)
        and pg_catalog.jsonb_array_length(v_feed) > 0,
      'direction', 'desc',
      'next_before_sequence', case
        when v_own_open > pg_catalog.jsonb_array_length(v_feed)
          and pg_catalog.jsonb_array_length(v_feed) > 0 then (
          select min((item ->> 'shop_sequence')::bigint)::text
          from pg_catalog.jsonb_array_elements(v_feed) as item
        )
        else null
      end,
      'server_sequence', v_date #> '{feed_page,server_sequence}',
      'snapshot_sequence', v_date #> '{feed_page,snapshot_sequence}'
    ),
    'day_summary', private.ledger_actor_day_summary(v_shop, v_open_days, auth.uid()),
    'journal_context', pg_catalog.jsonb_build_object(
      'business_date', v_date ->> 'business_date',
      'day_ids', to_jsonb(v_open_days),
      'server_now', pg_catalog.to_char(v_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'next_midnight_at', pg_catalog.to_char(v_next at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'return_count', (
        select count(*) from public.financial_operations as operation
        where operation.shop_id = v_shop
          and operation.business_day_id = any (v_open_days)
          and operation.actor_user_id = auth.uid()
          and operation.kind in ('sale_return', 'purchase_return', 'customer_return')
          and not private.ledger_trade_hidden(operation.shop_id, operation.id)
      ),
      'note_count', 0
    ),
    'day_reset', false
  );
end;
$fn$;
revoke all on function private.employee_ledger_home() from public, anon, authenticated;

-- The current app's home read routes employees to the builder above.
create or replace function public.get_daily_ledger_home_v2()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_result jsonb;
  v_prev text;
begin
  if private.caller_is_employee() then
    v_prev := private.begin_member_permission('ledger_read');
    v_result := private.employee_ledger_home();
    perform private.end_member_permission(v_prev);
    return v_result;
  end if;
  v_result := public.get_daily_ledger_home_v1_full();
  if pg_catalog.jsonb_typeof(v_result -> 'feed') = 'array' then
    v_result := pg_catalog.jsonb_set(
      v_result, '{feed}', private.feed_expense_descriptions(v_result -> 'feed')
    );
  end if;
  return v_result;
end;
$fn$;

notify pgrst, 'reload schema';
commit;

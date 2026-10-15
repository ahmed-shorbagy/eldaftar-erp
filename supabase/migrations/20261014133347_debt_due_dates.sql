-- ADR 0019. Additive calendar metadata only; source balances remain authoritative.
begin;

create table public.debt_due_dates (
  shop_id uuid not null references public.shops(id),
  source_kind text not null check (source_kind in ('standalone','purchase_cash_payable','gold_obligation')),
  source_id uuid not null,
  due_date date check (due_date between date '0001-01-01' and date '9999-12-31'),
  record_version bigint not null check (record_version > 0),
  actor_user_id uuid not null,
  updated_at timestamptz not null,
  primary key (shop_id,source_kind,source_id),
  foreign key (shop_id,actor_user_id) references public.shop_memberships(shop_id,user_id)
);
create index debt_due_dates_actor_idx on public.debt_due_dates(shop_id,actor_user_id);
create index debt_due_dates_calendar_idx on public.debt_due_dates(shop_id,due_date,source_kind,source_id) where due_date is not null;

create table public.debt_due_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  source_kind text not null,
  source_id uuid not null,
  old_date date,
  new_date date,
  record_version bigint not null check (record_version > 0),
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  foreign key (shop_id,source_kind,source_id) references public.debt_due_dates(shop_id,source_kind,source_id),
  foreign key (shop_id,actor_user_id) references public.shop_memberships(shop_id,user_id)
);
create index debt_due_events_source_idx on public.debt_due_events(shop_id,source_kind,source_id,record_version);
create index debt_due_events_actor_idx on public.debt_due_events(shop_id,actor_user_id);

create table public.debt_due_requests (
  shop_id uuid not null references public.shops(id),
  idempotency_key uuid not null,
  payload_canonical jsonb not null check (jsonb_typeof(payload_canonical)='object'),
  result jsonb not null check (jsonb_typeof(result)='object'),
  created_at timestamptz not null,
  primary key (shop_id,idempotency_key)
);
create trigger debt_due_events_append_only before update or delete on public.debt_due_events
  for each row execute function private.debt_reject_mutation();
create trigger debt_due_requests_append_only before update or delete on public.debt_due_requests
  for each row execute function private.debt_reject_mutation();

alter table public.debt_due_dates enable row level security;
alter table public.debt_due_dates force row level security;
alter table public.debt_due_events enable row level security;
alter table public.debt_due_events force row level security;
alter table public.debt_due_requests enable row level security;
alter table public.debt_due_requests force row level security;
revoke all on public.debt_due_dates,public.debt_due_events,public.debt_due_requests from public,anon,authenticated;
grant select on public.debt_due_dates,public.debt_due_events,public.debt_due_requests to authenticated;
create policy debt_due_dates_owner_read on public.debt_due_dates for select to authenticated using (private.opening_financial_visible(shop_id));
create policy debt_due_events_owner_read on public.debt_due_events for select to authenticated using (private.opening_financial_visible(shop_id));
create policy debt_due_requests_owner_read on public.debt_due_requests for select to authenticated using (private.opening_financial_visible(shop_id));

create function private.debt_calendar_date_v1(p_value jsonb)
returns date language plpgsql immutable security invoker set search_path='' as $fn$
declare v_text text; v_date date;
begin
  if p_value = 'null'::jsonb then return null; end if;
  if jsonb_typeof(p_value) is distinct from 'string' then raise exception 'invalid_date'; end if;
  v_text:=p_value #>> '{}';
  if v_text !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'invalid_date'; end if;
  begin v_date:=v_text::date; exception when others then raise exception 'invalid_date'; end;
  if v_date not between date '0001-01-01' and date '9999-12-31' or to_char(v_date,'YYYY-MM-DD')<>v_text then raise exception 'invalid_date'; end if;
  return v_date;
end;
$fn$;

-- Clock is injected only into the private pure classifier for DST/midnight tests.
create function private.debt_due_state_v1(p_date date,p_remaining bigint,p_status text,p_at timestamptz,p_zone text)
returns text language sql stable security invoker set search_path='' as $fn$
  select case when p_date is null then null
    when p_remaining<=0 or p_status<>'open' then 'inactive'
    when p_date<(p_at at time zone p_zone)::date then 'overdue'
    when p_date=(p_at at time zone p_zone)::date then 'today' else 'upcoming' end;
$fn$;

create function private.debt_due_rows_v1(p_shop uuid,p_at timestamptz)
returns table (row_data jsonb) language sql stable security definer set search_path='' as $fn$
  select j.content || jsonb_build_object('freshness',encode(extensions.digest(convert_to(j.content::text,'UTF8'),'sha256'),'hex'))
  from private.debt_balances(p_shop) b
  join public.shops s on s.id=p_shop
  left join public.debt_due_dates d on d.shop_id=p_shop and d.source_kind=b.source_kind and d.source_id=b.source_id
  cross join lateral (select jsonb_build_object(
    'shop_id',p_shop,'debt_key',b.debt_key,'source_kind',b.source_kind,'source_id',b.source_id,
    'direction',b.direction,'unit',b.unit,'karat',b.karat,'party_name',b.party_name,
    'contact_phone',nullif(b.contact_phone,''),'reason',b.reason,'external_reference',b.external_reference,
    'original_amount',b.original_amount::text,'settled_amount',b.settled_amount::text,
    'cancelled_amount',b.cancelled_amount::text,'remaining_amount',b.remaining_amount::text,
    'display_status',b.display_status,'record_version',b.record_version::text,
    'created_at',to_char(b.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'created_at_shop',to_char(b.created_at at time zone s.time_zone,'YYYY-MM-DD"T"HH24:MI:SS'),
    'time_zone',s.time_zone,'local_date',to_char((p_at at time zone s.time_zone)::date,'YYYY-MM-DD'),
    'due_date',to_char(d.due_date,'YYYY-MM-DD'),'due_version',coalesce(d.record_version,0)::text,
    'due_state',private.debt_due_state_v1(d.due_date,b.remaining_amount,b.display_status,p_at,s.time_zone),
    'updated_at',to_char(d.updated_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'actor_user_id',d.actor_user_id
  ) content) j
  where private.opening_financial_visible(p_shop);
$fn$;

create function public.get_debt_due_v1(p_source_kind text,p_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_shop uuid; v_row jsonb; v_at timestamptz:=statement_timestamp();
begin
  v_shop:=private.opening_require_reader_shop();
  select row_data into v_row from private.debt_due_rows_v1(v_shop,v_at)
    where row_data->>'source_kind'=p_source_kind and row_data->>'source_id'=p_source_id::text;
  if v_row is null then raise exception 'not_found'; end if;
  return v_row || jsonb_build_object('version',1,
    'can_schedule',private.can_write_shop(v_shop) and v_row->>'display_status'='open' and (v_row->>'remaining_amount')::bigint>0,
    'snapshot_at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'snapshot_at_shop',to_char(v_at at time zone (v_row->>'time_zone'),'YYYY-MM-DD"T"HH24:MI:SS'),
    'metadata_history',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'old_date',to_char(e.old_date,'YYYY-MM-DD'),
      'new_date',to_char(e.new_date,'YYYY-MM-DD'),'due_version',e.record_version::text,
      'actor_user_id',e.actor_user_id,'actor_display_name',e.actor_display_name,
      'at',to_char(e.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'at_shop',to_char(e.created_at at time zone (v_row->>'time_zone'),'YYYY-MM-DD"T"HH24:MI:SS')) order by e.record_version)
      from public.debt_due_events e where e.shop_id=v_shop and e.source_kind=p_source_kind and e.source_id=p_source_id),'[]'::jsonb));
end;
$fn$;

create function public.get_debt_reminders_v1(p_query text default '',p_filter text default 'all',p_limit integer default 20,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_shop uuid; v_at timestamptz:=statement_timestamp(); v_zone text; v_date text; v_rows jsonb;
  v_hash text; v_cursor jsonb; v_offset integer:=0; v_items jsonb; v_total integer;
begin
  v_shop:=private.opening_require_reader_shop();
  if p_query is null or char_length(p_query)>200 or p_query<>btrim(p_query)
    or p_filter is null or p_filter not in ('all','today','overdue','upcoming') or p_limit is null or p_limit not between 1 and 50 then raise exception 'invalid_input'; end if;
  select time_zone into v_zone from public.shops where id=v_shop;
  v_date:=to_char((v_at at time zone v_zone)::date,'YYYY-MM-DD');
  select coalesce(jsonb_agg(row_data order by row_data->>'due_date',row_data->>'debt_key'),'[]'::jsonb) into v_rows
  from private.debt_due_rows_v1(v_shop,v_at) where row_data->>'due_state' in ('today','overdue','upcoming')
    and (p_filter='all' or row_data->>'due_state'=p_filter)
    and (p_query='' or strpos(lower(concat_ws(' ',row_data->>'party_name',row_data->>'contact_phone',row_data->>'reason',row_data->>'external_reference',row_data->>'debt_key')),lower(p_query))>0);
  v_total:=jsonb_array_length(v_rows);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('shop',v_shop,'query',p_query,'filter',p_filter,
    'zone',v_zone,'date',v_date,'order','date_source_asc','rows',v_rows)::text,'UTF8'),'sha256'),'hex');
  if p_cursor is not null then
    begin
      v_cursor:=p_cursor::jsonb;
      if jsonb_typeof(v_cursor) is distinct from 'object' or jsonb_typeof(v_cursor->'offset') is distinct from 'number'
        or v_cursor->>'offset' is null or v_cursor->>'offset' !~ '^[1-9][0-9]{0,8}$'
        or v_cursor->>'freshness' is distinct from v_hash then raise exception 'stale_due_cursor'; end if;
      v_offset:=(v_cursor->>'offset')::integer;
      if v_offset>=v_total then raise exception 'stale_due_cursor'; end if;
    exception when others then raise exception 'stale_due_cursor'; end;
  end if;
  select coalesce(jsonb_agg(e order by n),'[]'::jsonb) into v_items from jsonb_array_elements(v_rows) with ordinality r(e,n)
    where n>v_offset and n<=v_offset+p_limit;
  return jsonb_build_object('version',1,'shop_id',v_shop,'time_zone',v_zone,'local_date',v_date,
    'snapshot_at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'snapshot_at_shop',to_char(v_at at time zone v_zone,'YYYY-MM-DD"T"HH24:MI:SS'),
    'freshness',v_hash,'items',v_items,'total',v_total,'offset',v_offset,
    'next_cursor',case when v_offset+p_limit<v_total then jsonb_build_object('offset',v_offset+p_limit,'freshness',v_hash)::text else null end);
end;
$fn$;

create function public.post_debt_due_v1(p_idempotency_key uuid,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $fn$
declare v_shop uuid; v_kind text; v_source uuid; v_date date; v_before jsonb; v_after jsonb;
  v_request public.debt_due_requests%rowtype; v_version bigint; v_at timestamptz; v_actor uuid; v_name text; v_result jsonb;
begin
  v_shop:=private.opening_require_reader_shop();
  if p_idempotency_key is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid_input'; end if;
  -- Same shop lock as settlement, return and archive. No financial command changes.
  perform 1 from public.shops where id=v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then raise exception 'forbidden'; end if;
  select * into v_request from public.debt_due_requests where shop_id=v_shop and idempotency_key=p_idempotency_key for update;
  if found then
    if v_request.payload_canonical is distinct from p_payload then raise exception 'payload_mismatch'; end if;
    return v_request.result || jsonb_build_object('replayed',true);
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  perform private.repair_require_keys(p_payload,array['version','kind','source_kind','source_id','due_date','expected_due_version','expected_freshness']);
  if p_payload->'version' is distinct from '1'::jsonb or p_payload->>'kind' is distinct from 'debt_due'
    or p_payload->>'source_kind' is null or p_payload->>'source_kind' not in ('standalone','purchase_cash_payable','gold_obligation')
    or jsonb_typeof(p_payload->'expected_freshness') is distinct from 'string' or p_payload->>'expected_freshness' !~ '^[0-9a-f]{64}$' then raise exception 'invalid_input'; end if;
  v_kind:=p_payload->>'source_kind'; v_source:=private.repair_uuid(p_payload->'source_id');
  v_version:=private.repair_money(p_payload->'expected_due_version',true);
  v_date:=private.debt_calendar_date_v1(p_payload->'due_date');
  if v_kind='standalone' then perform 1 from public.shop_debts where shop_id=v_shop and id=v_source for update;
  elsif v_kind='purchase_cash_payable' then perform 1 from public.purchase_cash_payables where shop_id=v_shop and operation_id=v_source for update;
  else perform 1 from public.gold_obligations where shop_id=v_shop and operation_id=v_source for update; end if;
  v_at:=clock_timestamp();
  select row_data into v_before from private.debt_due_rows_v1(v_shop,v_at) where row_data->>'source_kind'=v_kind and row_data->>'source_id'=v_source::text;
  if v_before is null then raise exception 'not_found'; end if;
  if v_before->>'freshness' is distinct from p_payload->>'expected_freshness' or (v_before->>'due_version')::bigint<>v_version then raise exception 'stale_due'; end if;
  if v_before->>'display_status'<>'open' or (v_before->>'remaining_amount')::bigint<=0 then raise exception 'due_not_active'; end if;
  v_actor:=auth.uid(); select owner_display_name into v_name from public.shops where id=v_shop;
  insert into public.debt_due_dates(shop_id,source_kind,source_id,due_date,record_version,actor_user_id,updated_at)
    values(v_shop,v_kind,v_source,v_date,v_version+1,v_actor,v_at)
    on conflict(shop_id,source_kind,source_id) do update set due_date=excluded.due_date,record_version=excluded.record_version,actor_user_id=excluded.actor_user_id,updated_at=excluded.updated_at;
  insert into public.debt_due_events(shop_id,source_kind,source_id,old_date,new_date,record_version,actor_user_id,actor_display_name,created_at)
    values(v_shop,v_kind,v_source,(v_before->>'due_date')::date,v_date,v_version+1,v_actor,v_name,v_at);
  perform private.bump_shop_sync(v_shop,'debt');
  select row_data into v_after from private.debt_due_rows_v1(v_shop,v_at) where row_data->>'source_kind'=v_kind and row_data->>'source_id'=v_source::text;
  v_result:=jsonb_build_object('version',1,'shop_id',v_shop,'key',p_idempotency_key,'kind','debt_due','source_kind',v_kind,'source_id',v_source,
    'payload',p_payload,'due_date',to_char(v_date,'YYYY-MM-DD'),'due_version',(v_version+1)::text,
    'actor_user_id',v_actor,'at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'freshness',v_after->>'freshness','replayed',false,'cash_piastres','0','gold_milligrams','0','stock_milligrams','0','custody_milligrams','0','invoice_effect',false);
  insert into public.debt_due_requests(shop_id,idempotency_key,payload_canonical,result,created_at) values(v_shop,p_idempotency_key,p_payload,v_result,v_at);
  return v_result;
end;
$fn$;

create function public.get_debt_due_status_v1(p_idempotency_key uuid,p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_shop uuid; v_request public.debt_due_requests%rowtype;
begin
  v_shop:=private.opening_require_reader_shop();
  if p_idempotency_key is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid_input'; end if;
  select * into v_request from public.debt_due_requests where shop_id=v_shop and idempotency_key=p_idempotency_key;
  if not found then return jsonb_build_object('status','absent'); end if;
  if v_request.payload_canonical is distinct from p_payload then raise exception 'payload_mismatch'; end if;
  return jsonb_build_object('status','completed','result',v_request.result);
end;
$fn$;

revoke all on function private.debt_calendar_date_v1(jsonb),private.debt_due_state_v1(date,bigint,text,timestamptz,text),private.debt_due_rows_v1(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.get_debt_due_v1(text,uuid),public.get_debt_reminders_v1(text,text,integer,text),public.post_debt_due_v1(uuid,jsonb),public.get_debt_due_status_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.get_debt_due_v1(text,uuid),public.get_debt_reminders_v1(text,text,integer,text),public.post_debt_due_v1(uuid,jsonb),public.get_debt_due_status_v1(uuid,jsonb) to authenticated;
commit;

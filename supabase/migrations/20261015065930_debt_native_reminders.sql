-- ADR 0020. Native intent only; financial and v1 date contracts stay intact.
begin;

create table public.debt_native_intents (
  shop_id uuid not null references public.shops(id),
  source_kind text not null check (source_kind in ('standalone','purchase_cash_payable','gold_obligation')),
  source_id uuid not null,
  reminder_time text check (reminder_time ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'),
  record_version bigint not null check (record_version > 0),
  actor_user_id uuid not null,
  updated_at timestamptz not null,
  primary key (shop_id,source_kind,source_id),
  foreign key (shop_id,actor_user_id) references public.shop_memberships(shop_id,user_id)
);
create index debt_native_intents_actor_idx on public.debt_native_intents(shop_id,actor_user_id);
create table public.debt_native_events (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  source_kind text not null,
  source_id uuid not null,
  old_time text,
  new_time text,
  due_date date,
  time_zone text not null,
  record_version bigint not null check (record_version > 0),
  actor_user_id uuid not null,
  actor_display_name text not null,
  created_at timestamptz not null,
  foreign key (shop_id,source_kind,source_id) references public.debt_native_intents(shop_id,source_kind,source_id),
  foreign key (shop_id,actor_user_id) references public.shop_memberships(shop_id,user_id)
);
create index debt_native_events_source_idx on public.debt_native_events(shop_id,source_kind,source_id,record_version);
create index debt_native_events_actor_idx on public.debt_native_events(shop_id,actor_user_id);
create table public.debt_native_requests (
  shop_id uuid not null references public.shops(id),
  idempotency_key uuid not null,
  payload_canonical jsonb not null check (jsonb_typeof(payload_canonical)='object'),
  result jsonb not null check (jsonb_typeof(result)='object'),
  created_at timestamptz not null,
  primary key (shop_id,idempotency_key)
);
create trigger debt_native_events_append_only before update or delete on public.debt_native_events
  for each row execute function private.debt_reject_mutation();
create trigger debt_native_requests_append_only before update or delete on public.debt_native_requests
  for each row execute function private.debt_reject_mutation();
alter table public.debt_native_intents enable row level security;
alter table public.debt_native_intents force row level security;
alter table public.debt_native_events enable row level security;
alter table public.debt_native_events force row level security;
alter table public.debt_native_requests enable row level security;
alter table public.debt_native_requests force row level security;
revoke all on public.debt_native_intents,public.debt_native_events,public.debt_native_requests from public,anon,authenticated;
grant select on public.debt_native_intents,public.debt_native_events,public.debt_native_requests to authenticated;
create policy debt_native_intents_owner_read on public.debt_native_intents for select to authenticated using (private.opening_financial_visible(shop_id));
create policy debt_native_events_owner_read on public.debt_native_events for select to authenticated using (private.opening_financial_visible(shop_id));
create policy debt_native_requests_owner_read on public.debt_native_requests for select to authenticated using (private.opening_financial_visible(shop_id));

-- Enumerate distinct offsets around the wall date, then round-trip every candidate.
-- PostgreSQL's default gap/fold choice is deliberately not accepted.
create function private.debt_native_instant_v1(p_date date,p_time text,p_zone text)
returns timestamptz language plpgsql stable security invoker set search_path='' as $fn$
declare v_wall timestamp; v_result timestamptz; v_count integer;
begin
  if p_time is null or p_date is null then return null; end if;
  if p_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'invalid_time'; end if;
  v_wall:=p_date+p_time::time;
  with offsets as (
    select distinct (t at time zone p_zone)-(t at time zone 'UTC') as delta
    from generate_series((v_wall at time zone 'UTC')-interval '48 hours',
      (v_wall at time zone 'UTC')+interval '48 hours',interval '1 hour') t
  ), candidates as (
    select distinct (v_wall at time zone 'UTC')-delta as instant from offsets
  ) select count(*),min(instant) into v_count,v_result from candidates where (instant at time zone p_zone)=v_wall;
  if v_count<>1 then raise exception 'unresolved_wall_time'; end if;
  return v_result;
end;
$fn$;

-- A zone/date edit may invalidate previously confirmed intent. Reads stay available.
create function private.debt_native_rows_v1(p_shop uuid,p_at timestamptz)
returns setof jsonb language plpgsql stable security definer set search_path='' as $fn$
declare r record; v_trigger timestamptz; v_valid boolean; v_content jsonb;
begin
  for r in select d.row_data,n.reminder_time,coalesce(n.record_version,0) native_version,
    n.actor_user_id native_actor,n.updated_at native_updated
    from private.debt_due_rows_v1(p_shop,p_at) d left join public.debt_native_intents n
    on n.shop_id=p_shop and n.source_kind=d.row_data->>'source_kind' and n.source_id=(d.row_data->>'source_id')::uuid
  loop
    v_valid:=true; v_trigger:=null;
    begin
      v_trigger:=private.debt_native_instant_v1((r.row_data->>'due_date')::date,r.reminder_time,r.row_data->>'time_zone');
    exception when raise_exception then v_valid:=false; end;
    v_content:=r.row_data||jsonb_build_object('reminder_time',r.reminder_time,'native_version',r.native_version::text,
      'native_actor_user_id',r.native_actor,'native_updated_at',to_char(r.native_updated at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'trigger_at',to_char(v_trigger at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'time_valid',v_valid);
    return next v_content||jsonb_build_object('native_freshness',encode(extensions.digest(convert_to(v_content::text,'UTF8'),'sha256'),'hex'));
  end loop;
end;
$fn$;

create function public.get_debt_native_v1(p_source_kind text,p_source_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_shop uuid; v_row jsonb; v_at timestamptz:=statement_timestamp();
begin
  v_shop:=private.opening_require_reader_shop();
  select r into v_row from private.debt_native_rows_v1(v_shop,v_at) r
    where r->>'source_kind'=p_source_kind and r->>'source_id'=p_source_id::text;
  if v_row is null then raise exception 'not_found'; end if;
  return v_row||jsonb_build_object('version',1,'snapshot_at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'can_write',private.can_write_shop(v_shop) and v_row->>'display_status'='open' and (v_row->>'remaining_amount')::bigint>0,
    'native_history',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'old_time',e.old_time,'new_time',e.new_time,
      'due_date',to_char(e.due_date,'YYYY-MM-DD'),'time_zone',e.time_zone,'native_version',e.record_version::text,
      'actor_user_id',e.actor_user_id,'actor_display_name',e.actor_display_name,
      'at',to_char(e.created_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
      'at_shop',to_char(e.created_at at time zone (v_row->>'time_zone'),'YYYY-MM-DD"T"HH24:MI:SS')) order by e.record_version)
      from public.debt_native_events e where e.shop_id=v_shop and e.source_kind=p_source_kind and e.source_id=p_source_id),'[]'::jsonb));
end;
$fn$;

create function public.review_debt_native_v1(p_source_kind text,p_source_id uuid,p_reminder_time text)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_detail jsonb; v_trigger timestamptz;
begin
  v_detail:=public.get_debt_native_v1(p_source_kind,p_source_id);
  if p_reminder_time is not null then
    if v_detail->>'due_date' is null then raise exception 'due_date_required'; end if;
    v_trigger:=private.debt_native_instant_v1((v_detail->>'due_date')::date,p_reminder_time,v_detail->>'time_zone');
  end if;
  return v_detail||jsonb_build_object('proposed_time',p_reminder_time,
    'proposed_trigger_at',to_char(v_trigger at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'));
end;
$fn$;

create function public.get_debt_native_queue_v1(p_limit integer default 50,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_shop uuid; v_at timestamptz:=statement_timestamp(); v_rows jsonb; v_hash text; v_cursor jsonb;
  v_offset integer:=0; v_total integer; v_items jsonb;
begin
  v_shop:=private.opening_require_reader_shop();
  if p_limit is null or p_limit not between 1 and 50 then raise exception 'invalid_input'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('source_kind',r->>'source_kind','source_id',r->>'source_id',
      'native_freshness',r->>'native_freshness','trigger_at',r->'trigger_at','time_valid',r->'time_valid')
      order by r->>'debt_key'),'[]'::jsonb) into v_rows
    from private.debt_native_rows_v1(v_shop,v_at) r where r->>'reminder_time' is not null
      and r->>'due_date' is not null and r->>'display_status'='open' and (r->>'remaining_amount')::bigint>0;
  v_total:=jsonb_array_length(v_rows);
  v_hash:=encode(extensions.digest(convert_to(jsonb_build_object('shop',v_shop,'rows',v_rows,'order','source_asc')::text,'UTF8'),'sha256'),'hex');
  if p_cursor is not null then
    begin
      v_cursor:=p_cursor::jsonb;
      if jsonb_typeof(v_cursor) is distinct from 'object' or jsonb_typeof(v_cursor->'offset') is distinct from 'number'
        or v_cursor->>'offset' is null or v_cursor->>'offset' !~ '^[1-9][0-9]{0,8}$'
        or v_cursor->>'freshness' is distinct from v_hash then raise exception 'stale_native_cursor'; end if;
      v_offset:=(v_cursor->>'offset')::integer;
      if v_offset>=v_total then raise exception 'stale_native_cursor'; end if;
    exception when others then raise exception 'stale_native_cursor'; end;
  end if;
  select coalesce(jsonb_agg(e order by n),'[]'::jsonb) into v_items from jsonb_array_elements(v_rows) with ordinality r(e,n)
    where n>v_offset and n<=v_offset+p_limit;
  return jsonb_build_object('version',1,'shop_id',v_shop,'snapshot_at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'freshness',v_hash,'items',v_items,'total',v_total,'offset',v_offset,
    'next_cursor',case when v_offset+p_limit<v_total then jsonb_build_object('offset',v_offset+p_limit,'freshness',v_hash)::text else null end);
end;
$fn$;

create function public.post_debt_native_v1(p_idempotency_key uuid,p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $fn$
declare v_shop uuid; v_kind text; v_source uuid; v_time text; v_before jsonb; v_after jsonb;
  v_request public.debt_native_requests%rowtype; v_version bigint; v_at timestamptz; v_actor uuid; v_name text; v_result jsonb;
begin
  v_shop:=private.opening_require_reader_shop();
  if p_idempotency_key is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid_input'; end if;
  perform 1 from public.shops where id=v_shop for update;
  if private.opening_require_reader_shop() is distinct from v_shop then raise exception 'forbidden'; end if;
  select * into v_request from public.debt_native_requests where shop_id=v_shop and idempotency_key=p_idempotency_key for update;
  if found then
    if v_request.payload_canonical is distinct from p_payload then raise exception 'payload_mismatch'; end if;
    return v_request.result||jsonb_build_object('replayed',true);
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  perform private.repair_require_keys(p_payload,array['version','kind','source_kind','source_id','reminder_time','expected_native_version','expected_freshness']);
  if p_payload->'version' is distinct from '1'::jsonb or p_payload->>'kind' is distinct from 'debt_native'
    or p_payload->>'source_kind' is null or p_payload->>'source_kind' not in ('standalone','purchase_cash_payable','gold_obligation')
    or jsonb_typeof(p_payload->'expected_freshness') is distinct from 'string' or p_payload->>'expected_freshness' !~ '^[0-9a-f]{64}$'
    or (p_payload->'reminder_time'<>'null'::jsonb and (jsonb_typeof(p_payload->'reminder_time')<>'string'
      or p_payload->>'reminder_time' !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$')) then raise exception 'invalid_input'; end if;
  v_kind:=p_payload->>'source_kind'; v_source:=private.repair_uuid(p_payload->'source_id');
  v_version:=private.repair_money(p_payload->'expected_native_version',true); v_time:=p_payload->>'reminder_time';
  if v_kind='standalone' then perform 1 from public.shop_debts where shop_id=v_shop and id=v_source for update;
  elsif v_kind='purchase_cash_payable' then perform 1 from public.purchase_cash_payables where shop_id=v_shop and operation_id=v_source for update;
  else perform 1 from public.gold_obligations where shop_id=v_shop and operation_id=v_source for update; end if;
  v_at:=clock_timestamp();
  select r into v_before from private.debt_native_rows_v1(v_shop,v_at) r where r->>'source_kind'=v_kind and r->>'source_id'=v_source::text;
  if v_before is null then raise exception 'not_found'; end if;
  if v_before->>'native_freshness' is distinct from p_payload->>'expected_freshness' or (v_before->>'native_version')::bigint<>v_version then raise exception 'stale_native'; end if;
  if v_before->>'display_status'<>'open' or (v_before->>'remaining_amount')::bigint<=0 then raise exception 'due_not_active'; end if;
  if v_time is not null then
    if v_before->>'due_date' is null then raise exception 'due_date_required'; end if;
    perform private.debt_native_instant_v1((v_before->>'due_date')::date,v_time,v_before->>'time_zone');
  end if;
  v_actor:=auth.uid(); select owner_display_name into v_name from public.shops where id=v_shop;
  insert into public.debt_native_intents(shop_id,source_kind,source_id,reminder_time,record_version,actor_user_id,updated_at)
    values(v_shop,v_kind,v_source,v_time,v_version+1,v_actor,v_at)
    on conflict(shop_id,source_kind,source_id) do update set reminder_time=excluded.reminder_time,record_version=excluded.record_version,actor_user_id=excluded.actor_user_id,updated_at=excluded.updated_at;
  insert into public.debt_native_events(shop_id,source_kind,source_id,old_time,new_time,due_date,time_zone,record_version,actor_user_id,actor_display_name,created_at)
    values(v_shop,v_kind,v_source,v_before->>'reminder_time',v_time,(v_before->>'due_date')::date,v_before->>'time_zone',v_version+1,v_actor,v_name,v_at);
  perform private.bump_shop_sync(v_shop,'debt');
  select r into v_after from private.debt_native_rows_v1(v_shop,v_at) r where r->>'source_kind'=v_kind and r->>'source_id'=v_source::text;
  v_result:=jsonb_build_object('version',1,'shop_id',v_shop,'key',p_idempotency_key,'kind','debt_native','source_kind',v_kind,'source_id',v_source,
    'payload',p_payload,'reminder_time',v_time,'native_version',(v_version+1)::text,'actor_user_id',v_actor,
    'at',to_char(v_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),'freshness',v_after->>'native_freshness',
    'replayed',false,'cash_piastres','0','gold_milligrams','0','stock_milligrams','0','custody_milligrams','0','invoice_effect',false);
  insert into public.debt_native_requests(shop_id,idempotency_key,payload_canonical,result,created_at) values(v_shop,p_idempotency_key,p_payload,v_result,v_at);
  return v_result;
end;
$fn$;
create function public.get_debt_native_status_v1(p_idempotency_key uuid,p_payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $fn$
declare v_shop uuid; v_request public.debt_native_requests%rowtype;
begin
  v_shop:=private.opening_require_reader_shop();
  if p_idempotency_key is null or jsonb_typeof(p_payload) is distinct from 'object' then raise exception 'invalid_input'; end if;
  select * into v_request from public.debt_native_requests where shop_id=v_shop and idempotency_key=p_idempotency_key;
  if not found then return jsonb_build_object('status','absent'); end if;
  if v_request.payload_canonical is distinct from p_payload then raise exception 'payload_mismatch'; end if;
  return jsonb_build_object('status','completed','result',v_request.result);
end;
$fn$;
revoke all on function private.debt_native_instant_v1(date,text,text),private.debt_native_rows_v1(uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.review_debt_native_v1(text,uuid,text) from public,anon,authenticated;
grant execute on function public.review_debt_native_v1(text,uuid,text) to authenticated;
revoke all on function public.get_debt_native_v1(text,uuid),public.get_debt_native_queue_v1(integer,text),public.post_debt_native_v1(uuid,jsonb),public.get_debt_native_status_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.get_debt_native_v1(text,uuid),public.get_debt_native_queue_v1(integer,text),public.post_debt_native_v1(uuid,jsonb),public.get_debt_native_status_v1(uuid,jsonb) to authenticated;
commit;

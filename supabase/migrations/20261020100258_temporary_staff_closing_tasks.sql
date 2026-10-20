-- Temporary physical counting only. Staff never become shop_memberships and
-- receive no grants on financial, inventory, customer, invoice or storage data.
begin;
create table public.closing_staff_accounts (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  user_id uuid not null unique references auth.users(id),
  display_name text not null check (length(btrim(display_name)) between 1 and 120),
  phone text not null,
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique (shop_id,id)
);
create table public.closing_count_tasks (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  staff_id uuid not null,
  business_day_id uuid not null references public.business_days(id),
  day_version bigint not null,
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  state text not null default 'assigned' check (state in ('assigned','submitted','revoked','closed')),
  observations jsonb,
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,
  closed_operation_id uuid references public.financial_operations(id),
  foreign key (shop_id,staff_id) references public.closing_staff_accounts(shop_id,id),
  check (expires_at > assigned_at and expires_at <= assigned_at + interval '24 hours'),
  check ((state in ('submitted','closed')) = (observations is not null and submitted_at is not null and submitted_by is not null))
);
create index closing_count_tasks_staff_idx on public.closing_count_tasks(staff_id,state,expires_at);
create index closing_count_tasks_shop_idx on public.closing_count_tasks(shop_id,assigned_at desc,id);
create table public.closing_delegation_audit (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops(id),
  actor_user_id uuid not null references auth.users(id),
  action text not null check (action in ('staff_created','staff_disabled','task_assigned','task_revoked','count_submitted','owner_closed')),
  staff_id uuid not null references public.closing_staff_accounts(id),
  task_id uuid references public.closing_count_tasks(id),
  operation_id uuid references public.financial_operations(id),
  created_at timestamptz not null default clock_timestamp()
);
create table private.closing_staff_creation_requests (
  shop_id uuid not null references public.shops(id),
  key uuid not null,
  owner_user_id uuid not null references auth.users(id),
  reserved_user_id uuid not null unique default gen_random_uuid(),
  display_name text not null,
  phone text not null unique,
  password_proof text not null,
  staff_id uuid references public.closing_staff_accounts(id),
  created_at timestamptz not null default clock_timestamp(),
  primary key(shop_id,key)
);
create table private.closing_delegation_commands (
  shop_id uuid not null references public.shops(id),
  actor_user_id uuid not null references auth.users(id),
  key uuid not null,
  payload jsonb not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp(),
  primary key(shop_id,key)
);
alter table public.closing_staff_accounts enable row level security;
alter table public.closing_count_tasks enable row level security;
alter table public.closing_delegation_audit enable row level security;
alter table private.closing_staff_creation_requests enable row level security;
alter table private.closing_delegation_commands enable row level security;
revoke all on public.closing_staff_accounts, public.closing_count_tasks, public.closing_delegation_audit,
  private.closing_staff_creation_requests, private.closing_delegation_commands from public, anon, authenticated;

create function public.begin_closing_staff_creation_v1(p_key uuid,p_name text,p_phone text,p_password_proof text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_request private.closing_staff_creation_requests%rowtype;
begin
  perform private.closing_actor_v1();
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops where id=v_shop for update;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if p_key is null or p_name is null or length(btrim(p_name)) not between 1 and 120
    or p_name ~ '[[:cntrl:]]' or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$'
    or p_password_proof is null or p_password_proof !~ '^[0-9a-f]{64}$' then raise exception 'invalid_input'; end if;
  select * into v_request from private.closing_staff_creation_requests where shop_id=v_shop and key=p_key;
  if found then
    if v_request.owner_user_id <> auth.uid() or v_request.display_name <> btrim(p_name)
      or v_request.phone <> p_phone or v_request.password_proof <> p_password_proof then raise exception 'payload_mismatch'; end if;
  else
    if exists(select 1 from auth.users where phone=p_phone and deleted_at is null)
      or exists(select 1 from private.closing_staff_creation_requests where phone=p_phone) then raise exception 'identifier_taken'; end if;
    if (select count(*) from private.closing_staff_creation_requests where shop_id=v_shop) >= 50 then raise exception 'staff_limit'; end if;
    insert into private.closing_staff_creation_requests(shop_id,key,owner_user_id,display_name,phone,password_proof)
    values(v_shop,p_key,auth.uid(),btrim(p_name),p_phone,p_password_proof) returning * into v_request;
  end if;
  return jsonb_build_object('shop_id',v_shop,'owner_user_id',v_request.owner_user_id,
    'reserved_user_id',v_request.reserved_user_id,'phone',v_request.phone,'staff_id',v_request.staff_id);
end; $fn$;

-- Only the server-side Auth administrator may finalize the reserved identity.
create function public.complete_closing_staff_creation_v1(p_owner uuid,p_key uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_request private.closing_staff_creation_requests%rowtype; v_staff uuid;
begin
  select * into v_request from private.closing_staff_creation_requests
  where owner_user_id=p_owner and key=p_key;
  if not found then raise exception 'not_found'; end if;
  perform 1 from public.shops where id=v_request.shop_id for update;
  select * into v_request from private.closing_staff_creation_requests
  where owner_user_id=p_owner and key=p_key for update;
  if not exists(select 1 from public.shop_memberships where shop_id=v_request.shop_id
    and user_id=p_owner and role='owner' and revoked_at is null)
    or not exists(select 1 from public.shop_entitlements where shop_id=v_request.shop_id
      and starts_at<=now() and expires_at>now())
    or not exists(select 1 from auth.users where id=p_owner and deleted_at is null and not coalesce(is_anonymous,false)
      and (banned_until is null or banned_until<=clock_timestamp())) then
    raise exception 'forbidden';
  end if;
  if v_request.staff_id is not null then return jsonb_build_object('ok',true,'staff_id',v_request.staff_id,'replayed',true); end if;
  if not exists(select 1 from auth.users where id=v_request.reserved_user_id and phone=v_request.phone
      and phone_confirmed_at is not null and deleted_at is null and not coalesce(is_anonymous,false))
    or exists(select 1 from public.shop_memberships where user_id=v_request.reserved_user_id) then raise exception 'identity_mismatch'; end if;
  insert into public.closing_staff_accounts(shop_id,user_id,display_name,phone,created_by)
  values(v_request.shop_id,v_request.reserved_user_id,v_request.display_name,v_request.phone,p_owner) returning id into v_staff;
  update private.closing_staff_creation_requests set staff_id=v_staff where shop_id=v_request.shop_id and key=p_key;
  insert into public.closing_delegation_audit(shop_id,actor_user_id,action,staff_id)
  values(v_request.shop_id,p_owner,'staff_created',v_staff);
  return jsonb_build_object('ok',true,'staff_id',v_staff,'replayed',false);
end; $fn$;

create function public.get_closing_staff_creation_status_v1(p_key uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_shop uuid; v_staff uuid;
begin
  perform private.closing_actor_v1();
  v_shop := private.opening_require_reader_shop();
  select staff_id into v_staff from private.closing_staff_creation_requests
  where shop_id=v_shop and key=p_key and owner_user_id=auth.uid();
  return jsonb_build_object('status',case when not found then 'absent' when v_staff is null then 'prepared' else 'confirmed' end,'staff_id',v_staff);
end; $fn$;

create function public.list_closing_staff_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $fn$
declare v_shop uuid; v_staff jsonb; v_tasks jsonb;
begin
  perform private.closing_actor_v1();
  v_shop := private.opening_require_reader_shop();
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',display_name,'phone',phone,'active',active) order by created_at,id),'[]'::jsonb)
  into v_staff from public.closing_staff_accounts where shop_id=v_shop;
  select coalesce(jsonb_agg(jsonb_build_object('id',task.id,'staff_id',task.staff_id,
      'business_day_id',task.business_day_id,'day_version',task.day_version::text,
      'business_date',day.business_date::text,'state',case when task.state='assigned' and task.expires_at<=now() then 'expired' else task.state end,
      'expires_at',task.expires_at,'observations',task.observations,'submitted_by',task.submitted_by,
      'submitted_at',task.submitted_at) order by task.assigned_at desc,task.id),'[]'::jsonb)
  into v_tasks from (select * from public.closing_count_tasks where shop_id=v_shop order by assigned_at desc,id limit 50) as task
  join public.business_days as day on day.shop_id=v_shop and day.id=task.business_day_id;
  return jsonb_build_object('shop_id',v_shop,'staff',v_staff,'tasks',v_tasks);
end; $fn$;

create function private.closing_actor_v1()
returns uuid language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor uuid := auth.uid();
begin
  if v_actor is null then raise exception 'unauthenticated'; end if;
  if not private.caller_session_accepted() then raise exception 'session_expired'; end if;
  if not exists(select 1 from auth.users where id=v_actor and deleted_at is null
    and not coalesce(is_anonymous,false) and (banned_until is null or banned_until<=clock_timestamp())) then raise exception 'forbidden'; end if;
  return v_actor;
end; $fn$;
create function private.closing_shop_available_v1(p_shop uuid)
returns boolean language sql volatile security definer set search_path = '' as $fn$
  select exists(select 1 from public.shop_memberships as member join auth.users as owner on owner.id=member.user_id
    where member.shop_id=p_shop and member.role='owner' and member.revoked_at is null
      and owner.deleted_at is null and not coalesce(owner.is_anonymous,false)
      and (owner.banned_until is null or owner.banned_until<=clock_timestamp()))
    and exists(select 1 from public.shop_entitlements where shop_id=p_shop and starts_at<=clock_timestamp() and expires_at>clock_timestamp());
$fn$;

create function public.mutate_closing_delegation_v1(p_key uuid,p_action text,p_target uuid,p_day_id uuid,p_day_version bigint)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_payload jsonb; v_prior private.closing_delegation_commands%rowtype;
  v_result jsonb; v_staff uuid; v_task uuid; v_at timestamptz; v_day public.business_days%rowtype;
begin
  perform private.closing_actor_v1();
  v_shop := private.opening_require_reader_shop();
  if p_key is null or p_target is null or p_action is null or p_action not in ('assign','disable','revoke') then raise exception 'invalid_input'; end if;
  perform 1 from public.shops where id=v_shop for update;
  v_payload := jsonb_build_object('action',p_action,'target',p_target,'day_id',p_day_id,'day_version',p_day_version);
  select * into v_prior from private.closing_delegation_commands where shop_id=v_shop and key=p_key;
  if found then
    if v_prior.actor_user_id<>auth.uid() or v_prior.payload<>v_payload then raise exception 'payload_mismatch'; end if;
    return v_prior.result || '{"replayed":true}'::jsonb;
  end if;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  v_at := clock_timestamp();
  if p_action in ('assign','disable') then
    select id into v_staff from public.closing_staff_accounts where shop_id=v_shop and id=p_target and active for update;
    if v_staff is null then raise exception 'not_found'; end if;
  else
    select staff_id,id into v_staff,v_task from public.closing_count_tasks where shop_id=v_shop and id=p_target and state='assigned' for update;
    if v_task is null then raise exception 'not_found'; end if;
  end if;
  if p_action='assign' then
    select * into v_day from public.business_days where shop_id=v_shop and id=p_day_id for update;
    if v_day.id is null or v_day.status<>'open' then raise exception 'day_closed'; end if;
    if p_day_version is null or v_day.day_version<>p_day_version then raise exception 'stale_day'; end if;
    -- Replacing an assignment revokes the former form immediately.
    with revoked as (update public.closing_count_tasks set state='revoked'
      where shop_id=v_shop and business_day_id=p_day_id and state='assigned' returning id,staff_id)
    insert into public.closing_delegation_audit(shop_id,actor_user_id,action,staff_id,task_id,created_at)
    select v_shop,auth.uid(),'task_revoked',staff_id,id,v_at from revoked;
    insert into public.closing_count_tasks(shop_id,staff_id,business_day_id,day_version,assigned_by,assigned_at,expires_at)
    values(v_shop,v_staff,p_day_id,p_day_version,auth.uid(),v_at,v_at+interval '4 hours') returning id into v_task;
  elsif p_action='disable' then
    update public.closing_staff_accounts set active=false where shop_id=v_shop and id=v_staff;
    with revoked as (update public.closing_count_tasks set state='revoked' where shop_id=v_shop and staff_id=v_staff and state='assigned' returning id)
    insert into public.closing_delegation_audit(shop_id,actor_user_id,action,staff_id,task_id,created_at)
    select v_shop,auth.uid(),'task_revoked',v_staff,id,v_at from revoked;
  else
    update public.closing_count_tasks set state='revoked' where id=v_task;
  end if;
  insert into public.closing_delegation_audit(shop_id,actor_user_id,action,staff_id,task_id,created_at)
  values(v_shop,auth.uid(),case p_action when 'assign' then 'task_assigned' when 'disable' then 'staff_disabled' else 'task_revoked' end,v_staff,v_task,v_at);
  v_result := jsonb_build_object('ok',true,'staff_id',v_staff,'task_id',v_task,'replayed',false);
  insert into private.closing_delegation_commands(shop_id,actor_user_id,key,payload,result,created_at)
  values(v_shop,auth.uid(),p_key,v_payload,v_result,v_at);
  return v_result;
end; $fn$;

create function public.get_closing_delegation_status_v1(p_key uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor uuid; v_result jsonb;
begin
  v_actor := private.closing_actor_v1();
  select result into v_result from private.closing_delegation_commands where actor_user_id=v_actor and key=p_key;
  return case when found then jsonb_build_object('status','confirmed','result',v_result)
    else jsonb_build_object('status','absent') end;
end; $fn$;

create function public.get_my_closing_task_v1()
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor uuid; v_staff public.closing_staff_accounts%rowtype; v_task public.closing_count_tasks%rowtype;
  v_spec jsonb; v_zone text; v_name text; v_date date; v_at timestamptz := clock_timestamp();
begin
  v_actor := private.closing_actor_v1();
  select * into v_staff from public.closing_staff_accounts where user_id=v_actor;
  if not found then return '{"state":"not_staff"}'::jsonb; end if;
  if not v_staff.active or not private.closing_shop_available_v1(v_staff.shop_id) then return '{"state":"unassigned"}'::jsonb; end if;
  select task.* into v_task from public.closing_count_tasks as task join public.business_days as day
    on day.id=task.business_day_id and day.shop_id=task.shop_id and day.status='open' and day.day_version=task.day_version
    where task.shop_id=v_staff.shop_id and task.staff_id=v_staff.id and task.state='assigned' and task.expires_at>v_at
    order by task.assigned_at desc,task.id desc limit 1;
  if v_task.id is null then return '{"state":"unassigned"}'::jsonb; end if;
  select private.daily_ledger_count_snapshot(v_staff.shop_id) into v_spec;
  select private.shop_display_zone(time_zone), name into v_zone,v_name from public.shops where id=v_staff.shop_id;
  select business_date into v_date from public.business_days where id=v_task.business_day_id;
  return jsonb_build_object('state','assigned','task_id',v_task.id,'shop_name',v_name,'staff_name',v_staff.display_name,
    'business_date',v_date::text,'expires_at',v_task.expires_at,'server_now',v_at,
    'stock',coalesce((select jsonb_agg(jsonb_build_object('category',item->>'category','karat',item->'karat') order by item->>'category',item->>'karat') from jsonb_array_elements(v_spec->'stock') item),'[]'::jsonb),
    'scrap_karats',coalesce((select jsonb_agg(item->'karat' order by item->>'karat') from jsonb_array_elements(v_spec->'scrap') item),'[]'::jsonb));
end; $fn$;

create function private.validate_closing_physical_v1(p_observations jsonb,p_book jsonb)
returns void language plpgsql immutable set search_path = '' as $fn$
declare v_synthetic jsonb; v_row jsonb;
begin
  if jsonb_typeof(p_observations) is distinct from 'object' or (select count(*) from jsonb_object_keys(p_observations))<>2
    or not p_observations ?& array['stock','scrap'] or jsonb_typeof(p_observations->'stock') is distinct from 'array'
    or jsonb_typeof(p_observations->'scrap') is distinct from 'array' then raise exception 'invalid_input'; end if;
  if jsonb_array_length(p_observations->'stock')>200 then raise exception 'invalid_input'; end if;
  if jsonb_array_length(p_observations->'scrap')<>jsonb_array_length(p_book->'scrap') then raise exception 'invalid_input'; end if;
  for v_row in select value from jsonb_array_elements(p_observations->'scrap') loop
    if jsonb_typeof(v_row) is distinct from 'object' or (select count(*) from jsonb_object_keys(v_row))<>2
      or not v_row ?& array['karat','milligrams'] or jsonb_typeof(v_row->'karat') is distinct from 'number'
      or (v_row->>'karat') not in ('14','18','21','22','24')
      or not exists(select 1 from jsonb_array_elements(p_book->'scrap') item where item->'karat'=v_row->'karat')
      or jsonb_typeof(v_row->'milligrams') is distinct from 'string'
      or (v_row->>'milligrams') !~ '^(0|[1-9][0-9]{0,18})$' or (v_row->>'milligrams')::numeric>9223372036854775807 then raise exception 'invalid_input'; end if;
  end loop;
  if exists(select 1 from jsonb_array_elements(p_observations->'scrap') item group by item->'karat' having count(*)>1) then raise exception 'invalid_input'; end if;
  -- Compare shape against allowed buckets, not the secret book quantities.
  select jsonb_build_object('cash','{}'::jsonb,'scrap',p_observations->'scrap','stock',
    coalesce(jsonb_agg(jsonb_build_object('category',bucket->'category','karat',bucket->'karat',
      'count',(select coalesce(sum((item->>'count')::numeric),0)::text from jsonb_array_elements(p_observations->'stock') item where item->'category'=bucket->'category' and item->'karat'=bucket->'karat'),
      'milligrams',(select coalesce(sum((item->>'milligrams')::numeric),0)::text from jsonb_array_elements(p_observations->'stock') item where item->'category'=bucket->'category' and item->'karat'=bucket->'karat'))),'[]'::jsonb))
    into v_synthetic from jsonb_array_elements(p_book->'stock') bucket;
  if not private.closing_counts_match_v2(p_observations || '{"version":2,"cash":{}}'::jsonb,v_synthetic) then raise exception 'invalid_input'; end if;
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'invalid_input';
end; $fn$;

create function public.submit_closing_count_v1(p_key uuid,p_task_id uuid,p_observations jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_actor uuid; v_staff public.closing_staff_accounts%rowtype; v_task public.closing_count_tasks%rowtype;
  v_payload jsonb; v_prior private.closing_delegation_commands%rowtype; v_result jsonb; v_at timestamptz; v_shop uuid;
begin
  v_actor := private.closing_actor_v1();
  if p_key is null or p_task_id is null or p_observations is null then raise exception 'invalid_input'; end if;
  select shop_id into v_shop from public.closing_staff_accounts where user_id=v_actor;
  if v_shop is null then raise exception 'forbidden'; end if;
  perform 1 from public.shops where id=v_shop for update;
  v_payload := jsonb_build_object('action','submit','task_id',p_task_id,'observations',p_observations);
  select * into v_prior from private.closing_delegation_commands where shop_id=v_shop and key=p_key;
  if found then
    if v_prior.actor_user_id<>v_actor or v_prior.payload<>v_payload then raise exception 'payload_mismatch'; end if;
    return v_prior.result || '{"replayed":true}'::jsonb;
  end if;
  select * into v_staff from public.closing_staff_accounts where user_id=v_actor and active for update;
  if not found or not private.closing_shop_available_v1(v_shop) then raise exception 'forbidden'; end if;
  select * into v_task from public.closing_count_tasks where shop_id=v_shop and staff_id=v_staff.id and id=p_task_id for update;
  v_at := clock_timestamp();
  if not found or v_task.state<>'assigned' or v_task.expires_at<=v_at then raise exception 'task_unavailable'; end if;
  if not exists(select 1 from public.business_days where shop_id=v_shop and id=v_task.business_day_id and status='open' and day_version=v_task.day_version) then raise exception 'stale_day'; end if;
  perform private.validate_closing_physical_v1(p_observations,private.daily_ledger_count_snapshot(v_shop));
  update public.closing_count_tasks set state='submitted',observations=p_observations,submitted_by=v_actor,submitted_at=v_at where id=p_task_id;
  insert into public.closing_delegation_audit(shop_id,actor_user_id,action,staff_id,task_id,created_at)
    values(v_shop,v_actor,'count_submitted',v_staff.id,p_task_id,v_at);
  v_result := jsonb_build_object('ok',true,'task_id',p_task_id,'replayed',false);
  insert into private.closing_delegation_commands(shop_id,actor_user_id,key,payload,result,created_at)
  values(v_shop,v_actor,p_key,v_payload,v_result,v_at);
  return v_result;
end; $fn$;

create function public.close_daily_ledger_from_staff_v1(p_key uuid,p_task_id uuid,p_cash jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $fn$
declare v_shop uuid; v_task public.closing_count_tasks%rowtype; v_counts jsonb; v_result jsonb;
begin
  perform private.closing_actor_v1();
  v_shop := private.opening_require_reader_shop();
  perform 1 from public.shops where id=v_shop for update;
  select * into v_task from public.closing_count_tasks where shop_id=v_shop and id=p_task_id and state in ('submitted','closed') for update;
  if not found then raise exception 'task_unavailable'; end if;
  v_counts := jsonb_build_object('version',2,'cash',p_cash,'stock',v_task.observations->'stock',
    'scrap',(select coalesce(jsonb_agg(item order by (item->>'karat')::integer),'[]'::jsonb) from jsonb_array_elements(v_task.observations->'scrap') item));
  v_result := public.close_daily_ledger_day_v2(p_key,v_task.business_day_id,v_task.day_version,v_counts);
  if v_result->>'ok'='true' and v_task.state='submitted' then
    update public.closing_count_tasks set state='closed',closed_operation_id=(v_result->>'operation_id')::uuid where id=p_task_id;
    insert into public.closing_delegation_audit(shop_id,actor_user_id,action,staff_id,task_id,operation_id)
      values(v_shop,auth.uid(),'owner_closed',v_task.staff_id,p_task_id,(v_result->>'operation_id')::uuid);
  end if;
  return v_result;
end; $fn$;

revoke all on function private.closing_actor_v1(),private.closing_shop_available_v1(uuid),private.validate_closing_physical_v1(jsonb,jsonb) from public,anon,authenticated;
revoke all on function public.mutate_closing_delegation_v1(uuid,text,uuid,uuid,bigint),public.get_closing_delegation_status_v1(uuid),
  public.get_my_closing_task_v1(),public.submit_closing_count_v1(uuid,uuid,jsonb),public.close_daily_ledger_from_staff_v1(uuid,uuid,jsonb) from public,anon;
grant execute on function public.mutate_closing_delegation_v1(uuid,text,uuid,uuid,bigint),public.get_closing_delegation_status_v1(uuid),
  public.get_my_closing_task_v1(),public.submit_closing_count_v1(uuid,uuid,jsonb),public.close_daily_ledger_from_staff_v1(uuid,uuid,jsonb) to authenticated;

revoke all on function public.begin_closing_staff_creation_v1(uuid,text,text,text),
  public.get_closing_staff_creation_status_v1(uuid),public.list_closing_staff_v1() from public,anon;
grant execute on function public.begin_closing_staff_creation_v1(uuid,text,text,text),
  public.get_closing_staff_creation_status_v1(uuid),public.list_closing_staff_v1() to authenticated;
revoke all on function public.complete_closing_staff_creation_v1(uuid,uuid) from public,anon,authenticated;
grant execute on function public.complete_closing_staff_creation_v1(uuid,uuid) to service_role;
notify pgrst,'reload schema';
commit;

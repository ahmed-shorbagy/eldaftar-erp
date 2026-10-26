-- Staff create / list / set grants / revoke. Owner-only.

begin;

create or replace function public.list_shop_staff_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
begin
  if auth.uid() is null then raise exception 'unauthenticated'; end if;
  v_shop := private.require_shop_owner();
  return jsonb_build_object(
    'shop_id', v_shop,
    'members', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', membership.user_id,
        'role', membership.role,
        'display_name', coalesce(
          (select meta.raw_user_meta_data ->> 'display_name'
           from auth.users as meta where meta.id = membership.user_id),
          ''
        ),
        'phone', (
          select case
            when identity.phone is null or identity.phone = '' then null
            else '+' || identity.phone
          end
          from auth.users as identity where identity.id = membership.user_id
        ),
        'joined_at', membership.joined_at,
        'grants', coalesce((
          select jsonb_agg(grant_row.permission order by grant_row.permission)
          from public.shop_member_grants as grant_row
          where grant_row.shop_id = membership.shop_id
            and grant_row.user_id = membership.user_id
        ), '[]'::jsonb)
      ) order by membership.joined_at, membership.user_id)
      from public.shop_memberships as membership
      where membership.shop_id = v_shop
        and membership.role in ('partner', 'employee')
        and membership.revoked_at is null
    ), '[]'::jsonb)
  );
end;
$fn$;

revoke all on function public.list_shop_staff_v1() from public, anon;
grant execute on function public.list_shop_staff_v1() to authenticated;

create or replace function public.begin_shop_staff_creation_v1(
  p_key uuid,
  p_name text,
  p_phone text,
  p_role text,
  p_grants text[],
  p_password_proof text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_request private.shop_staff_creation_requests%rowtype;
  v_grants text[];
  v_phone text;
begin
  perform private.closing_actor_v1();
  v_shop := private.require_shop_owner();
  perform 1 from public.shops where id = v_shop for update;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  if p_key is null or p_name is null or length(btrim(p_name)) not between 1 and 120
    or p_name ~ '[[:cntrl:]]'
    or p_phone is null or p_phone !~ '^[1-9][0-9]{6,14}$'
    or p_role is null or p_role not in ('partner', 'employee')
    or p_grants is null
    or p_password_proof is null or p_password_proof !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid_input';
  end if;
  select array_agg(distinct g order by g) into v_grants
  from unnest(p_grants) as g
  where g in ('sale', 'purchase', 'inventory', 'expense', 'reports', 'invoice_send');
  if v_grants is null or cardinality(v_grants) = 0
    or cardinality(v_grants) is distinct from cardinality(p_grants) then
    raise exception 'invalid_input';
  end if;
  if p_role = 'partner' and cardinality(v_grants) = 6 then
    null; -- full partner
  end if;
  v_phone := p_phone;
  select * into v_request
  from private.shop_staff_creation_requests
  where shop_id = v_shop and key = p_key;
  if found then
    if v_request.owner_user_id is distinct from auth.uid()
      or v_request.display_name is distinct from btrim(p_name)
      or v_request.phone is distinct from v_phone
      or v_request.role is distinct from p_role
      or v_request.grants is distinct from v_grants
      or v_request.password_proof is distinct from p_password_proof then
      raise exception 'payload_mismatch';
    end if;
  else
    if exists (select 1 from auth.users where phone = v_phone and deleted_at is null)
      or exists (
        select 1 from private.shop_staff_creation_requests where phone = v_phone
      )
      or exists (
        select 1 from private.closing_staff_creation_requests where phone = v_phone
      )
      or exists (
        select 1 from public.shops where phone = '+' || v_phone
      ) then
      raise exception 'identifier_taken';
    end if;
    if (
      select count(*) from public.shop_memberships
      where shop_id = v_shop and role in ('partner', 'employee') and revoked_at is null
    ) >= 40 then
      raise exception 'staff_limit';
    end if;
    insert into private.shop_staff_creation_requests (
      shop_id, key, owner_user_id, display_name, phone, role, grants, password_proof
    ) values (
      v_shop, p_key, auth.uid(), btrim(p_name), v_phone, p_role, v_grants, p_password_proof
    ) returning * into v_request;
  end if;
  return jsonb_build_object(
    'shop_id', v_shop,
    'owner_user_id', v_request.owner_user_id,
    'reserved_user_id', v_request.reserved_user_id,
    'phone', v_request.phone,
    'member_user_id', v_request.member_user_id
  );
end;
$fn$;

revoke all on function public.begin_shop_staff_creation_v1(uuid, text, text, text, text[], text)
  from public, anon;
grant execute on function public.begin_shop_staff_creation_v1(uuid, text, text, text, text[], text)
  to authenticated;

create or replace function public.complete_shop_staff_creation_v1(p_owner uuid, p_key uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_request private.shop_staff_creation_requests%rowtype;
  v_grant text;
begin
  select * into v_request
  from private.shop_staff_creation_requests
  where owner_user_id = p_owner and key = p_key;
  if not found then raise exception 'not_found'; end if;
  perform 1 from public.shops where id = v_request.shop_id for update;
  select * into v_request
  from private.shop_staff_creation_requests
  where owner_user_id = p_owner and key = p_key
  for update;
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = v_request.shop_id and user_id = p_owner
      and role = 'owner' and revoked_at is null
  ) or not exists (
    select 1 from public.shop_entitlements
    where shop_id = v_request.shop_id
      and starts_at <= now() and expires_at > now()
  ) or not exists (
    select 1 from auth.users
    where id = p_owner and deleted_at is null
      and not coalesce(is_anonymous, false)
      and (banned_until is null or banned_until <= clock_timestamp())
  ) then
    raise exception 'forbidden';
  end if;
  if v_request.member_user_id is not null then
    return jsonb_build_object(
      'ok', true, 'user_id', v_request.member_user_id, 'replayed', true
    );
  end if;
  if not exists (
    select 1 from auth.users
    where id = v_request.reserved_user_id
      and phone = v_request.phone
      and deleted_at is null
  ) then
    raise exception 'identity_missing';
  end if;
  update auth.users
  set raw_user_meta_data =
    coalesce(raw_user_meta_data, '{}'::jsonb)
      || jsonb_build_object('display_name', v_request.display_name)
  where id = v_request.reserved_user_id;
  insert into public.shop_memberships (shop_id, user_id, role)
  values (v_request.shop_id, v_request.reserved_user_id, v_request.role);
  foreach v_grant in array v_request.grants loop
    insert into public.shop_member_grants (shop_id, user_id, permission, granted_by)
    values (v_request.shop_id, v_request.reserved_user_id, v_grant, p_owner);
  end loop;
  update private.shop_staff_creation_requests
  set member_user_id = v_request.reserved_user_id
  where shop_id = v_request.shop_id and key = p_key;
  insert into public.shop_member_grant_audits (
    shop_id, actor_user_id, subject_user_id, action, details, request_key
  ) values (
    v_request.shop_id, p_owner, v_request.reserved_user_id, 'staff_created',
    jsonb_build_object(
      'role', v_request.role,
      'grants', to_jsonb(v_request.grants),
      'display_name', v_request.display_name
    ),
    p_key
  );
  return jsonb_build_object(
    'ok', true, 'user_id', v_request.reserved_user_id, 'replayed', false
  );
end;
$fn$;

revoke all on function public.complete_shop_staff_creation_v1(uuid, uuid)
  from public, anon;
grant execute on function public.complete_shop_staff_creation_v1(uuid, uuid)
  to service_role;

create or replace function public.get_shop_staff_creation_status_v1(p_key uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_request private.shop_staff_creation_requests%rowtype;
begin
  v_shop := private.require_shop_owner();
  select * into v_request
  from private.shop_staff_creation_requests
  where shop_id = v_shop and key = p_key and owner_user_id = auth.uid();
  if not found then
    return jsonb_build_object('status', 'absent');
  end if;
  if v_request.member_user_id is not null then
    return jsonb_build_object('status', 'confirmed', 'user_id', v_request.member_user_id);
  end if;
  return jsonb_build_object('status', 'prepared');
end;
$fn$;

revoke all on function public.get_shop_staff_creation_status_v1(uuid) from public, anon;
grant execute on function public.get_shop_staff_creation_status_v1(uuid) to authenticated;

create or replace function public.set_shop_staff_grants_v1(
  p_key uuid,
  p_user_id uuid,
  p_grants text[]
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_grants text[];
  v_prior public.shop_member_grant_audits%rowtype;
  v_details jsonb;
  v_grant text;
begin
  if p_key is null or p_user_id is null or p_grants is null then
    raise exception 'invalid_input';
  end if;
  v_shop := private.require_shop_owner();
  perform 1 from public.shops where id = v_shop for update;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select array_agg(distinct g order by g) into v_grants
  from unnest(p_grants) as g
  where g in ('sale', 'purchase', 'inventory', 'expense', 'reports', 'invoice_send');
  if v_grants is null or cardinality(v_grants) = 0
    or cardinality(v_grants) is distinct from cardinality(p_grants) then
    raise exception 'invalid_input';
  end if;
  v_details := jsonb_build_object('grants', to_jsonb(v_grants));
  select * into v_prior
  from public.shop_member_grant_audits
  where shop_id = v_shop and request_key = p_key;
  if found then
    if v_prior.action is distinct from 'grants_set'
      or v_prior.subject_user_id is distinct from p_user_id
      or v_prior.details is distinct from v_details then
      raise exception 'payload_mismatch';
    end if;
    return jsonb_build_object('ok', true, 'user_id', p_user_id, 'replayed', true);
  end if;
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = v_shop and user_id = p_user_id
      and role in ('partner', 'employee') and revoked_at is null
  ) then
    raise exception 'target_staff_unavailable';
  end if;
  delete from public.shop_member_grants
  where shop_id = v_shop and user_id = p_user_id;
  foreach v_grant in array v_grants loop
    insert into public.shop_member_grants (shop_id, user_id, permission, granted_by)
    values (v_shop, p_user_id, v_grant, auth.uid());
  end loop;
  insert into public.shop_member_grant_audits (
    shop_id, actor_user_id, subject_user_id, action, details, request_key
  ) values (
    v_shop, auth.uid(), p_user_id, 'grants_set', v_details, p_key
  );
  return jsonb_build_object('ok', true, 'user_id', p_user_id, 'replayed', false);
end;
$fn$;

revoke all on function public.set_shop_staff_grants_v1(uuid, uuid, text[])
  from public, anon;
grant execute on function public.set_shop_staff_grants_v1(uuid, uuid, text[])
  to authenticated;

create or replace function public.revoke_shop_staff_v1(p_key uuid, p_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_shop uuid;
  v_prior public.shop_member_grant_audits%rowtype;
begin
  if p_key is null or p_user_id is null then raise exception 'invalid_input'; end if;
  v_shop := private.require_shop_owner();
  perform 1 from public.shops where id = v_shop for update;
  if not private.can_write_shop(v_shop) then raise exception 'shop_not_active'; end if;
  select * into v_prior
  from public.shop_member_grant_audits
  where shop_id = v_shop and request_key = p_key;
  if found then
    if v_prior.action is distinct from 'staff_revoked'
      or v_prior.subject_user_id is distinct from p_user_id then
      raise exception 'payload_mismatch';
    end if;
    return jsonb_build_object('ok', true, 'user_id', p_user_id, 'replayed', true);
  end if;
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = v_shop and user_id = p_user_id
      and role in ('partner', 'employee') and revoked_at is null
  ) then
    raise exception 'target_staff_unavailable';
  end if;
  update public.shop_memberships
  set revoked_at = clock_timestamp()
  where shop_id = v_shop and user_id = p_user_id and revoked_at is null;
  delete from public.shop_member_grants
  where shop_id = v_shop and user_id = p_user_id;
  insert into public.shop_member_grant_audits (
    shop_id, actor_user_id, subject_user_id, action, details, request_key
  ) values (
    v_shop, auth.uid(), p_user_id, 'staff_revoked', '{}'::jsonb, p_key
  );
  return jsonb_build_object('ok', true, 'user_id', p_user_id, 'replayed', false);
end;
$fn$;

revoke all on function public.revoke_shop_staff_v1(uuid, uuid) from public, anon;
grant execute on function public.revoke_shop_staff_v1(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
commit;

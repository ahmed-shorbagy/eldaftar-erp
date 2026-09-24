-- Identity commands. Ordinary clients have no direct table write privileges.
alter table public.shop_invitations
  add column request_key uuid,
  add constraint shop_invitations_request_key_unique unique (shop_id, inviter_user_id, request_key);
alter table public.identity_audit_events
  add constraint identity_audit_events_request_unique unique (shop_id, correlation_id);

create function public.create_staff_invitation(
  p_shop_id uuid,
  p_email text,
  p_role text,
  p_request_key uuid,
  p_token uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_email text := lower(btrim(p_email));
  v_existing public.shop_invitations%rowtype;
begin
  if p_request_key is null or p_token is null or v_email is null or length(v_email) > 320
    or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    or p_role not in ('owner', 'partner', 'employee') then
    raise exception 'invalid_invitation' using errcode = '22023';
  end if;
  if not private.can_write_shop(p_shop_id)
    or not private.can_manage_staff(p_shop_id) then
    raise exception 'staff_management_denied' using errcode = '42501';
  end if;
  if p_role <> 'employee' and not exists (
    select 1 from public.shop_memberships
    where shop_id = p_shop_id and user_id = v_actor
      and role = 'owner' and revoked_at is null
  ) then
    raise exception 'owner_required_for_elevated_role' using errcode = '42501';
  end if;

  select * into v_existing from public.shop_invitations
  where shop_id = p_shop_id and inviter_user_id = v_actor
    and request_key = p_request_key;
  if found then
    if v_existing.invited_email <> v_email or v_existing.role <> p_role
      or v_existing.token_hash <> encode(sha256(convert_to(p_token::text, 'UTF8')), 'hex') then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return p_token;
  end if;

  update public.shop_invitations
  set revoked_at = now()
  where shop_id = p_shop_id and invited_email = v_email
    and accepted_at is null and revoked_at is null and expires_at <= now();
  insert into public.shop_invitations (
    shop_id, invited_email, role, token_hash, expires_at,
    inviter_user_id, request_key
  ) values (
    p_shop_id, v_email, p_role,
    encode(sha256(convert_to(p_token::text, 'UTF8')), 'hex'),
    now() + interval '7 days', v_actor, p_request_key
  );
  insert into public.identity_audit_events
    (shop_id, actor_user_id, action, correlation_id)
  values (p_shop_id, v_actor, 'staff_invited', p_request_key);
  return p_token;
end;
$function$;

revoke all on function public.create_staff_invitation(uuid,text,text,uuid,uuid) from public, anon;
grant execute on function public.create_staff_invitation(uuid,text,text,uuid,uuid) to authenticated;

create function public.accept_staff_invitation(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_email text;
  v_invitation public.shop_invitations%rowtype;
begin
  if v_actor is null or p_token is null then
    raise exception 'verified_email_required' using errcode = '42501';
  end if;
  select lower(btrim(email)) into v_email from auth.users
  where id = v_actor and email_confirmed_at is not null;
  if v_email is null then
    raise exception 'verified_email_required' using errcode = '42501';
  end if;
  select * into v_invitation from public.shop_invitations
  where token_hash = encode(sha256(convert_to(p_token::text, 'UTF8')), 'hex')
  for update;
  if not found or v_invitation.invited_email <> v_email
    or v_invitation.revoked_at is not null then
    raise exception 'invitation_unavailable' using errcode = '42501';
  end if;
  if v_invitation.accepted_at is not null then
    if exists (
      select 1 from public.shop_memberships
      where shop_id = v_invitation.shop_id and user_id = v_actor
        and revoked_at is null
    ) then
      return v_invitation.shop_id;
    end if;
    raise exception 'invitation_already_used' using errcode = '42501';
  end if;
  if v_invitation.expires_at <= now() or not exists (
    select 1 from public.shop_entitlements as entitlement
    where entitlement.shop_id = v_invitation.shop_id
      and entitlement.starts_at <= now()
      and now() < entitlement.expires_at
  ) then
    raise exception 'invitation_unavailable' using errcode = '42501';
  end if;

  insert into public.shop_memberships (shop_id, user_id, role)
  values (v_invitation.shop_id, v_actor, v_invitation.role)
  on conflict (shop_id, user_id) do update
    set role = excluded.role, revoked_at = null, joined_at = now();
  update public.shop_invitations set accepted_at = now()
  where id = v_invitation.id;
  insert into public.identity_audit_events
    (shop_id, actor_user_id, action, subject_user_id, correlation_id)
  values (v_invitation.shop_id, v_actor, 'staff_joined', v_actor, v_invitation.id);
  return v_invitation.shop_id;
end;
$function$;

revoke all on function public.accept_staff_invitation(uuid) from public, anon;
grant execute on function public.accept_staff_invitation(uuid) to authenticated;

create function public.set_staff_permission(
  p_shop_id uuid,
  p_user_id uuid,
  p_permission text,
  p_enabled boolean,
  p_request_key uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_prior public.identity_audit_events%rowtype;
  v_details jsonb := jsonb_build_object('permission', p_permission, 'enabled', p_enabled);
begin
  if p_request_key is null or p_user_id is null or p_enabled is null
    or p_permission not in (
      'sale','purchase','expense','close_day','inventory_edit',
      'invoice_dispatch','report_view','staff_manage','shop_settings'
    ) then
    raise exception 'invalid_permission_change' using errcode = '22023';
  end if;
  if not private.can_write_shop(p_shop_id) or not exists (
    select 1 from public.shop_memberships
    where shop_id = p_shop_id and user_id = v_actor
      and role = 'owner' and revoked_at is null
  ) then
    raise exception 'owner_required' using errcode = '42501';
  end if;
  perform 1 from public.shops where id = p_shop_id for update;
  select * into v_prior from public.identity_audit_events
  where shop_id = p_shop_id and correlation_id = p_request_key;
  if found then
    if v_prior.action <> 'staff_permission_changed'
      or v_prior.subject_user_id <> p_user_id
      or v_prior.details <> v_details then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return;
  end if;
  if not exists (
    select 1 from public.shop_memberships
    where shop_id = p_shop_id and user_id = p_user_id
      and revoked_at is null and role <> 'owner'
  ) then
    raise exception 'target_staff_unavailable' using errcode = '42501';
  end if;
  if p_enabled then
    insert into public.shop_member_grants (shop_id, user_id, permission)
    values (p_shop_id, p_user_id, p_permission)
    on conflict do nothing;
  else
    delete from public.shop_member_grants
    where shop_id = p_shop_id and user_id = p_user_id
      and permission = p_permission;
  end if;
  insert into public.identity_audit_events
    (shop_id, actor_user_id, action, subject_user_id, correlation_id, details)
  values (p_shop_id, v_actor, 'staff_permission_changed',
    p_user_id, p_request_key, v_details);
end;
$function$;

revoke all on function public.set_staff_permission(uuid,uuid,text,boolean,uuid) from public, anon;
grant execute on function public.set_staff_permission(uuid,uuid,text,boolean,uuid) to authenticated;

create function public.revoke_staff_member(
  p_shop_id uuid,
  p_user_id uuid,
  p_request_key uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := auth.uid();
  v_prior public.identity_audit_events%rowtype;
  v_role text;
begin
  if p_user_id is null or p_request_key is null then
    raise exception 'invalid_revocation' using errcode = '22023';
  end if;
  if not private.can_write_shop(p_shop_id) or not exists (
    select 1 from public.shop_memberships
    where shop_id = p_shop_id and user_id = v_actor
      and role = 'owner' and revoked_at is null
  ) then
    raise exception 'owner_required' using errcode = '42501';
  end if;
  perform 1 from public.shops where id = p_shop_id for update;
  select * into v_prior from public.identity_audit_events
  where shop_id = p_shop_id and correlation_id = p_request_key;
  if found then
    if v_prior.action <> 'staff_revoked'
      or v_prior.subject_user_id <> p_user_id then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return;
  end if;
  select role into v_role from public.shop_memberships
  where shop_id = p_shop_id and user_id = p_user_id
    and revoked_at is null;
  if v_role is null then
    raise exception 'target_staff_unavailable' using errcode = '42501';
  end if;
  if v_role = 'owner' and not exists (
    select 1 from public.shop_memberships
    where shop_id = p_shop_id and role = 'owner'
      and revoked_at is null and user_id <> p_user_id
  ) then
    raise exception 'last_owner' using errcode = '42501';
  end if;
  delete from public.shop_member_grants
  where shop_id = p_shop_id and user_id = p_user_id;
  update public.shop_memberships set revoked_at = now()
  where shop_id = p_shop_id and user_id = p_user_id;
  insert into public.identity_audit_events
    (shop_id, actor_user_id, action, subject_user_id, correlation_id)
  values (p_shop_id, v_actor, 'staff_revoked', p_user_id, p_request_key);
end;
$function$;

revoke all on function public.revoke_staff_member(uuid,uuid,uuid) from public, anon;
grant execute on function public.revoke_staff_member(uuid,uuid,uuid) to authenticated;

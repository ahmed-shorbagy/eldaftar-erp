-- ADM-04: minimum app version and forced-update policy.
-- Additive. No shop entitlement or financial function changes.

begin;

create table public.app_version_policies (
  platform text not null,
  min_version text,
  message_ar text not null default '',
  update_url text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id),
  constraint app_version_policies_platform_check
    check (platform in ('android', 'ios', 'windows')),
  constraint app_version_policies_pkey primary key (platform),
  constraint app_version_policies_min_version_check check (
    min_version is null
    or min_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'
  ),
  constraint app_version_policies_message_when_min check (
    (min_version is null and message_ar = '')
    or (min_version is not null and length(btrim(message_ar)) > 0)
  ),
  constraint app_version_policies_update_url_check check (
    update_url is null
    or (
      length(update_url) between 12 and 2048
      and lower(update_url) like 'https://%'
    )
  )
);

alter table public.app_version_policies enable row level security;

revoke all on table public.app_version_policies from anon, authenticated;

insert into public.app_version_policies (platform, min_version, message_ar, update_url)
values
  ('android', null, '', null),
  ('ios', null, '', null),
  ('windows', null, '', null);

create function private.app_version_compare(p_left text, p_right text)
returns integer
language plpgsql
immutable
set search_path = ''
as $function$
declare
  v_l text[];
  v_r text[];
  v_i integer;
  v_ln integer;
  v_rn integer;
begin
  if p_left is null or p_right is null
    or p_left !~ '^[0-9]+\.[0-9]+\.[0-9]+$'
    or p_right !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
    raise exception 'invalid_version' using errcode = '22023';
  end if;
  v_l := string_to_array(p_left, '.');
  v_r := string_to_array(p_right, '.');
  for v_i in 1..3 loop
    v_ln := v_l[v_i]::integer;
    v_rn := v_r[v_i]::integer;
    if v_ln < v_rn then
      return -1;
    elsif v_ln > v_rn then
      return 1;
    end if;
  end loop;
  return 0;
end;
$function$;

revoke all on function private.app_version_compare(text, text)
  from public, anon, authenticated;

create function public.get_app_version_policy_v1()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'platform', policy.platform,
        'min_version', policy.min_version,
        'message_ar', policy.message_ar,
        'update_url', policy.update_url
      )
      order by policy.platform
    ),
    '[]'::jsonb
  )
  from public.app_version_policies as policy;
$function$;

revoke all on function public.get_app_version_policy_v1() from public;
grant execute on function public.get_app_version_policy_v1() to anon, authenticated;

create function public.admin_get_app_version_policy_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_gate text;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;
  return public.get_app_version_policy_v1();
end;
$function$;

revoke all on function public.admin_get_app_version_policy_v1() from public, anon;
grant execute on function public.admin_get_app_version_policy_v1() to authenticated;

create function public.admin_set_app_version_policy_v1(
  p_platform text,
  p_min_version text,
  p_message_ar text,
  p_update_url text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_gate text;
  v_min text;
  v_message text;
  v_url text;
  v_row public.app_version_policies%rowtype;
begin
  v_gate := private.admin_subscriber_gate();
  if v_gate is distinct from 'ok' then
    raise exception '%', v_gate using errcode = '42501';
  end if;

  if p_platform is null or p_platform not in ('android', 'ios', 'windows') then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  v_min := nullif(btrim(coalesce(p_min_version, '')), '');
  v_message := btrim(coalesce(p_message_ar, ''));
  v_url := nullif(btrim(coalesce(p_update_url, '')), '');

  if v_min is null then
    v_message := '';
    v_url := null;
  else
    if v_min !~ '^[0-9]+\.[0-9]+\.[0-9]+$' then
      raise exception 'invalid_version' using errcode = '22023';
    end if;
    if length(v_message) = 0 then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
    if v_url is not null
      and (
        length(v_url) < 12
        or length(v_url) > 2048
        or lower(v_url) not like 'https://%'
      ) then
      raise exception 'invalid_input' using errcode = '22023';
    end if;
  end if;

  select * into v_row
  from public.app_version_policies as policy
  where policy.platform = p_platform
  for update;

  if not found then
    raise exception 'invalid_input' using errcode = '22023';
  end if;

  if v_row.min_version is not distinct from v_min
    and v_row.message_ar is not distinct from v_message
    and v_row.update_url is not distinct from v_url then
    return jsonb_build_object(
      'platform', v_row.platform,
      'min_version', v_row.min_version,
      'message_ar', v_row.message_ar,
      'update_url', v_row.update_url,
      'updated_at', v_row.updated_at,
      'status', 'unchanged'
    );
  end if;

  update public.app_version_policies as policy
  set
    min_version = v_min,
    message_ar = v_message,
    update_url = v_url,
    updated_at = now(),
    updated_by = auth.uid()
  where policy.platform = p_platform
  returning * into v_row;

  return jsonb_build_object(
    'platform', v_row.platform,
    'min_version', v_row.min_version,
    'message_ar', v_row.message_ar,
    'update_url', v_row.update_url,
    'updated_at', v_row.updated_at,
    'status', 'saved'
  );
end;
$function$;

revoke all on function public.admin_set_app_version_policy_v1(text, text, text, text)
  from public, anon;
grant execute on function public.admin_set_app_version_policy_v1(text, text, text, text)
  to authenticated;

do $revoke_service$
begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'revoke all on function public.admin_get_app_version_policy_v1() from service_role';
    execute 'revoke all on function public.admin_set_app_version_policy_v1(text, text, text, text) from service_role';
  end if;
end;
$revoke_service$;

notify pgrst, 'reload schema';

commit;

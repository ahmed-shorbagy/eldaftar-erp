-- Owner feedback: international profile registration and concise ledger cards.
-- Existing Egypt profiles/requests keep their identifiers and idempotency keys.
-- The existing governorate_code contract accepts ISO EG codes or CC:region labels.
begin;

create function private.registration_dial_code(p_region text)
returns text language sql immutable security invoker set search_path = '' as $fn$
select case left(p_region, 2)
  when 'EG' then '20'
  when 'SA' then '966'
  when 'AE' then '971'
  when 'MA' then '212'
  when 'LY' then '218'
  when 'YE' then '967'
  when 'JO' then '962'
  when 'KW' then '965'
  when 'QA' then '974'
  when 'BH' then '973'
  when 'OM' then '968'
  when 'IQ' then '964'
  when 'LB' then '961'
  when 'PS' then '970'
  when 'SY' then '963'
  when 'DZ' then '213'
  when 'TN' then '216'
  when 'SD' then '249'
  when 'MR' then '222'
  when 'SO' then '252'
  when 'DJ' then '253'
  when 'KM' then '269'
  else null end;
$fn$;
revoke all on function private.registration_dial_code(text) from public, anon, authenticated;

create function private.registration_region_valid(p_region text)
returns boolean language sql stable security definer set search_path = '' as $fn$
select coalesce(exists (select 1 from public.egypt_governorates where code = p_region)
  or (private.registration_dial_code(p_region) is not null
      and substring(p_region from 3 for 1) = ':'
      and char_length(substring(p_region from 4)) between 1 and 120
      and substring(p_region from 4) = btrim(substring(p_region from 4))
      and p_region !~ '[[:cntrl:]]'), false);
$fn$;
revoke all on function private.registration_region_valid(text) from public, anon, authenticated;

create function private.registration_phone(p_phone text, p_region text)
returns text language plpgsql immutable security invoker set search_path = '' as $fn$
declare v_dial text; v_value text;
begin
  v_dial := private.registration_dial_code(p_region);
  if v_dial is null or p_phone is null or p_phone ~ '[^0-9+ ()-]' then return null; end if;
  if v_dial = '20' then return private.normalize_egypt_mobile(p_phone); end if;
  v_value := regexp_replace(p_phone, '[ ()-]', '', 'g');
  if left(v_value, 2) = '00' then v_value := '+' || substring(v_value from 3); end if;
  if left(v_value, 1) = '+' then
    if left(v_value, char_length(v_dial) + 1) <> '+' || v_dial then return null; end if;
    v_value := substring(v_value from char_length(v_dial) + 2);
  elsif left(v_value, 1) = '0' then v_value := substring(v_value from 2);
  end if;
  if v_value !~ '^[1-9][0-9]{6,11}$' or char_length(v_dial || v_value) > 15 then return null; end if;
  return '+' || v_dial || v_value;
end;
$fn$;
revoke all on function private.registration_phone(text, text) from public, anon, authenticated;

create function private.registration_time_zone(p_region text)
returns text language sql immutable security invoker set search_path = '' as $fn$
select case left(p_region, 2)
  when 'EG' then 'Africa/Cairo'
  when 'SA' then 'Asia/Riyadh'
  when 'AE' then 'Asia/Dubai'
  when 'MA' then 'Africa/Casablanca'
  when 'LY' then 'Africa/Tripoli'
  when 'YE' then 'Asia/Aden'
  when 'JO' then 'Asia/Amman'
  when 'KW' then 'Asia/Kuwait'
  when 'QA' then 'Asia/Qatar'
  when 'BH' then 'Asia/Bahrain'
  when 'OM' then 'Asia/Muscat'
  when 'IQ' then 'Asia/Baghdad'
  when 'LB' then 'Asia/Beirut'
  when 'PS' then 'Asia/Hebron'
  when 'SY' then 'Asia/Damascus'
  when 'DZ' then 'Africa/Algiers'
  when 'TN' then 'Africa/Tunis'
  when 'SD' then 'Africa/Khartoum'
  when 'MR' then 'Africa/Nouakchott'
  when 'SO' then 'Africa/Mogadishu'
  when 'DJ' then 'Africa/Djibouti'
  when 'KM' then 'Indian/Comoro'
  else null end;
$fn$;
revoke all on function private.registration_time_zone(text) from public, anon, authenticated;

alter table public.shops drop constraint shops_governorate_code_fkey;
alter table public.shops drop constraint shops_registered_profile_check;
alter table public.shops add constraint shops_registered_profile_check check (
  (email is null and governorate_code is null) or
  (email is not null and governorate_code is not null and phone is not null
    and private.registration_region_valid(governorate_code)
    and phone = private.registration_phone(phone, governorate_code)
    and private.registration_phone(phone, governorate_code) is not null
    and owner_display_name is not null and length(btrim(owner_display_name)) between 1 and 120
    and time_zone = private.registration_time_zone(governorate_code))
);
alter table private.owner_registration_reservations
  drop constraint owner_registration_reservations_governorate_code_fkey,
  drop constraint owner_registration_phone_check;
alter table private.owner_registration_reservations add constraint owner_registration_phone_check check (
  private.registration_region_valid(governorate_code)
  and private.registration_phone(phone, governorate_code) is not null
  and phone = private.registration_phone(phone, governorate_code)
);
drop index public.shops_phone_canonical_key;
create unique index shops_phone_canonical_key on public.shops(phone)
where phone is not null and phone ~ '^\+[1-9][0-9]{7,14}$';

-- Stored profile properties are derived from the validated region contract.
alter table public.shops add column country_code text generated always as (left(governorate_code, 2)) stored;
alter table public.shops add column region_name text generated always as (
  case when substring(governorate_code from 3 for 1) = ':' then substring(governorate_code from 4) else null end
) stored;

create function private.registration_phone_digits(p_canonical text)
returns text language sql immutable security invoker set search_path = '' as $fn$
select case when p_canonical ~ '^\+[1-9][0-9]{7,14}$' then substring(p_canonical from 2) else null end;
$fn$;

revoke all on function private.registration_phone_digits(text) from public, anon, authenticated;
create or replace function private.auth_phone_matches(p_auth_phone text, p_canonical text)
returns boolean language sql immutable security invoker set search_path = '' as $fn$
  select private.registration_phone_digits(p_canonical) is not null
    and regexp_replace(coalesce(p_auth_phone, ''), '[^0-9]', '', 'g') = private.registration_phone_digits(p_canonical);
$fn$;

create or replace function public.begin_owner_registration(
  p_request_key uuid,
  p_owner_display_name text,
  p_business_name text,
  p_email text,
  p_phone text,
  p_governorate_code text
)
returns table (
  request_key uuid,
  reserved_user_id uuid,
  email text,
  phone text,
  auth_phone text,
  owner_display_name text,
  business_name text,
  governorate_code text,
  status text,
  shop_id uuid
)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_owner text;
  v_business text;
  v_email text;
  v_phone text;
  v_governorate text;
  v_existing private.owner_registration_reservations%rowtype;
begin
  v_owner := btrim(p_owner_display_name);
  v_business := btrim(p_business_name);
  if p_request_key is null
    or v_owner is null
    or char_length(v_owner) not between 1 and 120
    or v_business is null
    or char_length(v_business) not between 1 and 120
    or v_owner ~ '[[:cntrl:]]'
    or v_business ~ '[[:cntrl:]]' then
    raise exception 'invalid_registration' using errcode = '22023';
  end if;

  v_email := private.normalize_registration_email(p_email);
  if v_email is null then
    raise exception 'invalid_email' using errcode = '22023';
  end if;

  v_governorate := btrim(p_governorate_code);
  if v_governorate is null
    or v_governorate = ''
    or not private.registration_region_valid(v_governorate) then
    raise exception 'invalid_governorate' using errcode = '22023';
  end if;

  v_phone := private.registration_phone(p_phone, btrim(p_governorate_code));
  if v_phone is null then
    raise exception 'invalid_phone' using errcode = '22023';
  end if;

  -- Same order on every call: request key, then email, then phone.
  perform pg_advisory_xact_lock(840261, hashtext(p_request_key::text));
  perform pg_advisory_xact_lock(840262, hashtext(v_email));
  perform pg_advisory_xact_lock(840263, hashtext(v_phone));

  select * into v_existing
  from private.owner_registration_reservations as existing_reservation
  where existing_reservation.request_key = p_request_key
  for update;

  if found then
    if v_existing.email <> v_email
      or v_existing.phone <> v_phone
      or v_existing.owner_display_name <> v_owner
      or v_existing.business_name <> v_business
      or v_existing.governorate_code <> v_governorate then
      raise exception 'request_key_reused' using errcode = '23505';
    end if;
    return query
    select * from private.owner_registration_result(p_request_key);
    return;
  end if;

  if exists (
    select 1
    from private.owner_registration_reservations as reservation
    where reservation.email = v_email
      or reservation.phone = v_phone
  ) or exists (
    select 1
    from public.shops as shop
    where shop.email = v_email
      or shop.phone = v_phone
      or private.normalize_egypt_mobile(shop.phone) = v_phone
  ) or exists (
    select 1
    from auth.users as identity
    where lower(btrim(identity.email)) = v_email
      or private.auth_phone_matches(identity.phone, v_phone)
  ) then
    raise exception 'identifier_already_registered' using errcode = '23505';
  end if;

  begin
    insert into private.owner_registration_reservations (
      request_key,
      reserved_user_id,
      email,
      phone,
      owner_display_name,
      business_name,
      governorate_code,
      status,
      created_at
    ) values (
      p_request_key,
      gen_random_uuid(),
      v_email,
      v_phone,
      v_owner,
      v_business,
      v_governorate,
      'reserved',
      clock_timestamp()
    );
  exception
    when unique_violation then
      select * into v_existing
      from private.owner_registration_reservations as existing_reservation
      where existing_reservation.request_key = p_request_key;
      if found
        and v_existing.email = v_email
        and v_existing.phone = v_phone
        and v_existing.owner_display_name = v_owner
        and v_existing.business_name = v_business
        and v_existing.governorate_code = v_governorate then
        return query
        select * from private.owner_registration_result(p_request_key);
        return;
      end if;
      if found then
        raise exception 'request_key_reused' using errcode = '23505';
      end if;
      raise exception 'identifier_already_registered' using errcode = '23505';
  end;

  return query
  select * from private.owner_registration_result(p_request_key);
end;
$function$;
create or replace function public.complete_owner_registration(p_request_key uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_reservation private.owner_registration_reservations%rowtype;
  v_identity auth.users%rowtype;
  v_shop uuid;
begin
  if p_request_key is null then
    raise exception 'invalid_registration' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(840261, hashtext(p_request_key::text));

  select * into v_reservation
  from private.owner_registration_reservations
  where request_key = p_request_key
  for update;

  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;

  if v_reservation.status = 'completed' then
    return v_reservation.shop_id;
  end if;

  select * into v_identity
  from auth.users
  where id = v_reservation.reserved_user_id
  for update;

  if not found
    or coalesce(v_identity.is_anonymous, false)
    or v_identity.deleted_at is not null then
    raise exception 'auth_user_not_ready' using errcode = 'P0001';
  end if;

  if lower(btrim(coalesce(v_identity.email, ''))) <> v_reservation.email
    or not private.auth_phone_matches(v_identity.phone, v_reservation.phone) then
    raise exception 'auth_contact_mismatch' using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.shop_memberships as membership
    where membership.user_id = v_reservation.reserved_user_id
  ) then
    raise exception 'registration_conflict' using errcode = '23505';
  end if;

  begin
    insert into public.shops (
      name,
      owner_display_name,
      phone,
      email,
      governorate_code,
      time_zone,
      created_by,
      setup_request_key
    ) values (
      v_reservation.business_name,
      v_reservation.owner_display_name,
      v_reservation.phone,
      v_reservation.email,
      v_reservation.governorate_code,
      private.registration_time_zone(v_reservation.governorate_code),
      v_reservation.reserved_user_id,
      v_reservation.request_key
    )
    returning id into v_shop;

    insert into public.shop_memberships (shop_id, user_id, role)
    values (v_shop, v_reservation.reserved_user_id, 'owner');

    insert into public.identity_audit_events (
      shop_id,
      actor_user_id,
      action,
      subject_user_id,
      correlation_id,
      details
    ) values (
      v_shop,
      v_reservation.reserved_user_id,
      'owner_registered',
      v_reservation.reserved_user_id,
      v_reservation.request_key,
      jsonb_build_object('governorate_code', v_reservation.governorate_code)
    );

    update private.owner_registration_reservations
    set status = 'completed',
        shop_id = v_shop,
        completed_at = clock_timestamp()
    where request_key = v_reservation.request_key;
  exception
    when unique_violation then
      raise exception 'registration_conflict' using errcode = '23505';
  end;

  return v_shop;
end;
$function$;
create or replace function public.get_ledger_operation_page(
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
  v_shop uuid;
  v_day uuid;
  v_before bigint;
  v_after bigint;
  v_zone text;
  v_name text;
  v_server bigint;
  v_rows jsonb;
  v_count integer;
  v_has_more boolean;
  v_next text;
  v_direction text;
begin
  if auth.uid() is null then
    raise exception 'unauthenticated';
  end if;
  if p_before_sequence is not null and p_after_sequence is not null then
    raise exception 'invalid_input';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    raise exception 'invalid_input';
  end if;
  v_before := private.parse_optional_sequence(p_before_sequence);
  v_after := private.parse_optional_sequence(p_after_sequence);
  v_shop := private.opening_require_reader_shop();
  if p_day_id is null then
    select day.id
      into v_day
    from public.business_days as day
    where day.shop_id = v_shop
    order by day.opened_at desc, day.id desc
    limit 1;
  else
    select day.id
      into v_day
    from public.business_days as day
    where day.shop_id = v_shop
      and day.id = p_day_id;
    if v_day is null then
      raise exception 'invalid_input';
    end if;
  end if;
  select private.shop_display_zone(shop.time_zone), shop.owner_display_name
    into v_zone, v_name
  from public.shops as shop
  where shop.id = v_shop;
  if v_day is null then
    return jsonb_build_object(
      'shop_id', v_shop,
      'day_id', null,
      'direction', case when v_after is null then 'desc' else 'asc' end,
      'limit', p_limit,
      'has_more', false,
      'server_sequence', '0',
      'snapshot_sequence', '0',
      'next_before_sequence', null,
      'next_after_sequence', null,
      'items', '[]'::jsonb
    );
  end if;
  select coalesce(max(operation.shop_sequence), 0)
    into v_server
  from public.financial_operations as operation
  where operation.shop_id = v_shop
    and operation.business_day_id = v_day;
  -- Desc and asc are separate statements so the shop/day sequence index
  -- can stop after limit+1 rows. A CASE sort would read the whole day.
  v_direction := case when v_after is null then 'desc' else 'asc' end;
  if v_after is null then
    with fetched as materialized (
      select
        operation.id,
        operation.shop_id,
        operation.kind,
        operation.shop_sequence,
        operation.created_at
      from public.financial_operations as operation
      where operation.shop_id = v_shop
        and operation.business_day_id = v_day
        and (v_before is null or operation.shop_sequence < v_before)
      order by operation.shop_sequence desc
      limit (p_limit + 1)
    ),
    shaped as (
      select
        fetched.id,
        fetched.kind,
        fetched.shop_sequence,
        fetched.created_at,
        detail.payload as summary_payload,
        (
          coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
          or (
            fetched.kind = 'daily_note'
            and coalesce(length(btrim(detail.payload ->> 'text')) > 0, false)
          )
          or exists (
            select 1
            from public.daily_note_attachments as attachment
            where attachment.shop_id = fetched.shop_id
              and attachment.operation_id = fetched.id
          )
        ) as has_note
      from fetched
      left join public.financial_operation_details as detail
        on detail.shop_id = fetched.shop_id
       and detail.operation_id = fetched.id
    ),
    kept as (
      select shaped.*
      from shaped
      order by shaped.shop_sequence desc
      limit p_limit
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'kind', kept.kind,
        'label_ar', private.ledger_operation_label(kept.kind),
        'operation_id', kept.id,
        'actor_display_name', coalesce(v_name, ''),
        'occurred_at', pg_catalog.to_jsonb(kept.created_at),
        'occurred_at_cairo', to_char(
          kept.created_at at time zone 'Africa/Cairo',
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'occurred_at_shop', to_char(
          kept.created_at at time zone v_zone,
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'has_note', kept.has_note,
        'is_daily_note', kept.kind = 'daily_note',
        'is_return', kept.kind in ('sale_return', 'purchase_return'),
        'shop_sequence', kept.shop_sequence::text,
        'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),
        'total_pounds', case when kept.summary_payload ->> 'total_piastres' ~ '^[0-9]+$'
          then trunc((kept.summary_payload ->> 'total_piastres')::numeric / 100)::text || '.' ||
            lpad(mod((kept.summary_payload ->> 'total_piastres')::numeric, 100)::text, 2, '0') else null end,
        'weight_grams', (select case when sum((item ->> 'milligrams')::numeric) is null then null
          else trunc(sum((item ->> 'milligrams')::numeric) / 1000)::text || '.' ||
            lpad(mod(sum((item ->> 'milligrams')::numeric), 1000)::text, 3, '0') end
          from jsonb_array_elements(coalesce(kept.summary_payload -> 'items', '[]'::jsonb)) item),
        'karat', (select case when count(distinct item ->> 'karat') = 1
          then min((item ->> 'karat')::integer) else null end
          from jsonb_array_elements(coalesce(kept.summary_payload -> 'items', '[]'::jsonb)) item),
        'payment_label', (select string_agg(case tender ->> 'method'
          when 'cash' then 'كاش' when 'instant_transfer' then 'إنستا باي'
          when 'wallet' then 'محفظة' when 'card' then 'فيزا' end, ' + ' order by tender ->> 'method')
          from jsonb_array_elements(coalesce(kept.summary_payload -> 'tenders', '[]'::jsonb)) tender)
      ) order by kept.shop_sequence desc), '[]'::jsonb),
      (select count(*) from fetched) > p_limit,
      (select min(edge.shop_sequence)::text from kept as edge)
      into v_rows, v_has_more, v_next
    from kept;
  else
    with fetched as materialized (
      select
        operation.id,
        operation.shop_id,
        operation.kind,
        operation.shop_sequence,
        operation.created_at
      from public.financial_operations as operation
      where operation.shop_id = v_shop
        and operation.business_day_id = v_day
        and operation.shop_sequence > v_after
      order by operation.shop_sequence asc
      limit (p_limit + 1)
    ),
    shaped as (
      select
        fetched.id,
        fetched.kind,
        fetched.shop_sequence,
        fetched.created_at,
        detail.payload as summary_payload,
        (
          coalesce(length(btrim(detail.payload ->> 'note')) > 0, false)
          or (
            fetched.kind = 'daily_note'
            and coalesce(length(btrim(detail.payload ->> 'text')) > 0, false)
          )
          or exists (
            select 1
            from public.daily_note_attachments as attachment
            where attachment.shop_id = fetched.shop_id
              and attachment.operation_id = fetched.id
          )
        ) as has_note
      from fetched
      left join public.financial_operation_details as detail
        on detail.shop_id = fetched.shop_id
       and detail.operation_id = fetched.id
    ),
    kept as (
      select shaped.*
      from shaped
      order by shaped.shop_sequence asc
      limit p_limit
    )
    select
      coalesce(jsonb_agg(jsonb_build_object(
        'kind', kept.kind,
        'label_ar', private.ledger_operation_label(kept.kind),
        'operation_id', kept.id,
        'actor_display_name', coalesce(v_name, ''),
        'occurred_at', pg_catalog.to_jsonb(kept.created_at),
        'occurred_at_cairo', to_char(
          kept.created_at at time zone 'Africa/Cairo',
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'occurred_at_shop', to_char(
          kept.created_at at time zone v_zone,
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'has_note', kept.has_note,
        'is_daily_note', kept.kind = 'daily_note',
        'is_return', kept.kind in ('sale_return', 'purchase_return'),
        'shop_sequence', kept.shop_sequence::text,
        'party_name', nullif(kept.summary_payload ->> 'customer_name', ''),
        'total_pounds', case when kept.summary_payload ->> 'total_piastres' ~ '^[0-9]+$'
          then trunc((kept.summary_payload ->> 'total_piastres')::numeric / 100)::text || '.' ||
            lpad(mod((kept.summary_payload ->> 'total_piastres')::numeric, 100)::text, 2, '0') else null end,
        'weight_grams', (select case when sum((item ->> 'milligrams')::numeric) is null then null
          else trunc(sum((item ->> 'milligrams')::numeric) / 1000)::text || '.' ||
            lpad(mod(sum((item ->> 'milligrams')::numeric), 1000)::text, 3, '0') end
          from jsonb_array_elements(coalesce(kept.summary_payload -> 'items', '[]'::jsonb)) item),
        'karat', (select case when count(distinct item ->> 'karat') = 1
          then min((item ->> 'karat')::integer) else null end
          from jsonb_array_elements(coalesce(kept.summary_payload -> 'items', '[]'::jsonb)) item),
        'payment_label', (select string_agg(case tender ->> 'method'
          when 'cash' then 'كاش' when 'instant_transfer' then 'إنستا باي'
          when 'wallet' then 'محفظة' when 'card' then 'فيزا' end, ' + ' order by tender ->> 'method')
          from jsonb_array_elements(coalesce(kept.summary_payload -> 'tenders', '[]'::jsonb)) tender)
      ) order by kept.shop_sequence asc), '[]'::jsonb),
      (select count(*) from fetched) > p_limit,
      (select max(edge.shop_sequence)::text from kept as edge)
      into v_rows, v_has_more, v_next
    from kept;
  end if;
  if not found then
    v_rows := '[]'::jsonb;
    v_has_more := false;
    v_next := null;
  elsif not coalesce(v_has_more, false) then
    v_next := null;
  end if;
  return jsonb_build_object(
    'shop_id', v_shop,
    'day_id', v_day,
    'direction', v_direction,
    'limit', p_limit,
    'has_more', coalesce(v_has_more, false),
    'server_sequence', v_server::text,
    'snapshot_sequence', v_server::text,
    'next_before_sequence', case when v_direction = 'desc' and v_has_more then v_next else null end,
    'next_after_sequence', case when v_direction = 'asc' and v_has_more then v_next else null end,
    'items', coalesce(v_rows, '[]'::jsonb)
  );
end;
$fn$;

-- CREATE OR REPLACE preserves existing service-only/client-reader grants.
revoke all on function public.begin_owner_registration(uuid,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.begin_owner_registration(uuid,text,text,text,text,text) to service_role;
revoke all on function public.complete_owner_registration(uuid) from public, anon, authenticated;
grant execute on function public.complete_owner_registration(uuid) to service_role;
revoke all on function public.get_ledger_operation_page(uuid,text,text,integer) from public, anon;
grant execute on function public.get_ledger_operation_page(uuid,text,text,integer) to authenticated;
commit;

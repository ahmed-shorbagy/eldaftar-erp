-- Keep the selected country even when the owner omits the optional region.
-- Existing ISO Egyptian regions and CC:label profiles remain compatible.
create or replace function private.registration_region_valid(p_region text)
returns boolean language sql stable set search_path = '' as $fn$
select coalesce(exists (select 1 from public.egypt_governorates where code = p_region)
  or (private.registration_dial_code(p_region) is not null
      and substring(p_region from 3 for 1) = ':'
      and char_length(substring(p_region from 4)) between 0 and 120
      and substring(p_region from 4) = btrim(substring(p_region from 4))
      and p_region !~ '[[:cntrl:]]'), false);
$fn$;
revoke all on function private.registration_region_valid(text) from public, anon, authenticated;

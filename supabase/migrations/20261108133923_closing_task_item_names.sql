-- The assigned counter receives item names for the task's stock buckets only.
-- Counts, weights, and cash stay out of the payload.

begin;

alter function public.get_my_closing_task_v1()
  rename to get_my_closing_task_v1_before_item_names;

revoke all on function public.get_my_closing_task_v1_before_item_names()
  from public, anon, authenticated;

create function public.get_my_closing_task_v1()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $fn$
declare
  v_task jsonb;
  v_actor uuid;
  v_shop uuid;
  v_names jsonb;
begin
  v_task := public.get_my_closing_task_v1_before_item_names();
  if v_task ->> 'state' is distinct from 'assigned' then
    return v_task;
  end if;
  v_actor := private.closing_actor_v1();
  select account.shop_id into v_shop
  from public.closing_staff_accounts as account
  where account.user_id = v_actor;
  if v_shop is null then
    return v_task;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'name', limited.name,
    'category', limited.category_code,
    'karat', limited.karat
  ) order by limited.created_at, limited.id), '[]'::jsonb)
  into v_names
  from (
    select product.name, product.category_code, product.karat,
      product.created_at, product.id
    from public.inventory_products as product
    where product.shop_id = v_shop
      and (product.category_code, product.karat) in (
        select item ->> 'category', (item ->> 'karat')::smallint
        from jsonb_array_elements(coalesce(v_task -> 'stock', '[]'::jsonb)) as item
      )
    order by product.created_at, product.id
    limit 200
  ) as limited;
  return v_task || jsonb_build_object('item_names', v_names);
end;
$fn$;

revoke all on function public.get_my_closing_task_v1() from public, anon;
grant execute on function public.get_my_closing_task_v1() to authenticated;

notify pgrst, 'reload schema';
commit;

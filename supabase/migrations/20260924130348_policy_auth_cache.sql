-- Cache the request user ID once per policy statement, as recommended by the RLS advisor.
alter policy shop_memberships_select_self_or_staff_manager
  on public.shop_memberships
  using (
    private.is_active_shop_member(shop_id)
    and (
      user_id = (select auth.uid())
      or private.can_manage_staff(shop_id)
    )
  );

alter policy shop_member_grants_select_self_or_staff_manager
  on public.shop_member_grants
  using (
    private.is_active_shop_member(shop_id)
    and (
      user_id = (select auth.uid())
      or private.can_manage_staff(shop_id)
    )
  );
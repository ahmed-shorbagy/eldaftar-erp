-- Covers the composite operation FK introduced by the inventory projection.
begin;
create index inventory_lot_sync_shop_operation_idx
  on public.inventory_lot_sync (shop_id, operation_id);
commit;

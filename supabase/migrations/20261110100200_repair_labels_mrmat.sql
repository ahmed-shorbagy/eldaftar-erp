-- User-facing repair labels become «مرمة» (ADR 0044 C-D7). RPC names stay.

begin;

create or replace function private.ledger_operation_label(p_kind text)
returns text
language sql
immutable
set search_path = ''
as $fn$
  select case p_kind
    when 'opening_balances' then 'رصيد افتتاحي'
    when 'sale' then 'بيع'
    when 'purchase' then 'شراء'
    when 'expense' then 'مصروف'
    when 'purchase_settlement' then 'سداد شراء'
    when 'cash_transfer' then 'تحويل نقدية'
    when 'scrap_sale' then 'بيع كسر'
    when 'scrap_to_stock' then 'تحويل كسر إلى مخزون'
    when 'sale_return' then 'مرتجع بيع'
    when 'purchase_return' then 'مرتجع شراء'
    when 'customer_return' then 'مرتجع'
    when 'close_day' then 'تقفيل اليومية'
    when 'open_day' then 'فتح اليومية'
    when 'ledger_correction' then 'تسوية فرق الجرد'
    when 'exchange' then 'استبدال'
    when 'daily_note' then 'ملاحظة يومية'
    when 'repair_fee' then 'أجرة مرمة'
    when 'repair_fee_collection' then 'تحصيل متبقي مرمة'
    when 'debt_settlement' then 'سداد دين'
    when 'gold_obligation_acquisition' then 'استلام ذهب مقابل التزام'
    when 'gold_obligation_settlement' then 'سداد التزام ذهب'
    else null
  end;
$fn$;

revoke all on function private.ledger_operation_label(text)
  from public, anon, authenticated;

notify pgrst, 'reload schema';
commit;

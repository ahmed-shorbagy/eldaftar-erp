-- Fix: a new shop could not confirm opening balances.
-- 20261027140000_payment_method_labels made display_label_ar mandatory for
-- cash-method accounts (ledger_accounts_cash_label_check), but
-- public.confirm_opening_balances still inserts those accounts without a
-- label, so the check rejected every first opening. This trigger fills the
-- default Arabic label whenever a cash-method account is created without one.
-- An explicit label is kept. Existing rows are unchanged; none are unlabelled.

begin;

create function private.ledger_account_default_cash_label()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.account_kind = 'cash_method'
    and (new.display_label_ar is null or btrim(new.display_label_ar) = '') then
    new.display_label_ar := private.default_cash_method_label(new.method_code);
  end if;
  return new;
end;
$fn$;

revoke all on function private.ledger_account_default_cash_label()
  from public, anon, authenticated;

create trigger ledger_accounts_default_cash_label
  before insert on public.ledger_accounts
  for each row execute function private.ledger_account_default_cash_label();

commit;

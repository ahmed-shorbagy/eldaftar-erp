import { spawnSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
if (!connection) {
  console.error('Set SUPABASE_TEST_DATABASE_URL to a disposable local Supabase database.')
  process.exit(2)
}

let url
try {
  url = new URL(connection)
} catch {
  console.error('SUPABASE_TEST_DATABASE_URL is not a PostgreSQL URL.')
  process.exit(2)
}
if (!['postgres:', 'postgresql:'].includes(url.protocol) ||
    !['localhost', '127.0.0.1', '::1', '[::1]'].includes(url.hostname)) {
  console.error('Identity tests only run against a local disposable database.')
  process.exit(2)
}

for (const name of [
  'identity_rls.sql',
  'identity_commands.sql',
  'egypt_owner_registration.sql',
  'owner_feedback_registration.sql',
  'subscription_redemption.sql',
  'shop_sync_signals.sql',
  'opening_balances.sql',
  'cash_account_default_label.sql',
  'opening_rls.sql',
  'daily_ledger_trades.sql',
  'purchase_paid_and_scrap_routing.sql',
  'daily_note_changes.sql',
  'expense_return_change.sql',
  'customer_return.sql',
  'invoice_price_components.sql',
  'milestone_3_inventory.sql',
  'milestone_3_inventory_rls.sql',
  'ledger_compensation.sql',
  'ledger_compensation_edges.sql',
  'repairs_custody.sql',
  'pending_invoices_open_day.sql',
  'ledger_home_day_reset.sql',
  'repair_fee_collection.sql',
  'debts.sql',
  'customers.sql',
  'customers_edges.sql',
  'customer_statistics.sql',
  'customer_auto_capture.sql',
  'inventory_item_grid.sql',
  'day_close_keeps_customers_and_inventory.sql',
  'sale_named_item_and_day_read.sql',
]) {
  const file = fileURLToPath(new URL(`./tests/${name}`, import.meta.url))
  console.log(`Running ${name}`)
  const result = spawnSync('psql', [connection, '-X', '-v', 'ON_ERROR_STOP=1', '-f', file], {
    stdio: 'inherit',
    shell: false,
  })
  if (result.error) {
    console.error('psql is required to run local identity tests.')
    process.exit(2)
  }
  if (result.status !== 0) process.exit(result.status ?? 1)
}

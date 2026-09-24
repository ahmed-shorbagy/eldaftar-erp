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

for (const name of ['identity_rls.sql', 'identity_commands.sql']) {
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
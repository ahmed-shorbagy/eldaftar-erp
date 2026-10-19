// Dedicated disposable local database. Never accepts a hosted connection.
// Synthetic append-only rows stay. Cleanup only revokes the membership and ends the entitlement.
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
const database = decodeURIComponent(url.pathname.replace(/^\//, ''))
const ordinary = new Set([
  'postgres',
  'template0',
  'template1',
  'eldafttar_test',
  'eldafttar_backend_test',
  'eldafttar_notes_test',
])
const port = Number(url.port)
if (
  url.protocol !== 'postgresql:' ||
  url.hostname !== '127.0.0.1' ||
  !Number.isInteger(port) ||
  port < 1024 ||
  port === 5432 ||
  port === 54322 ||
  ordinary.has(database) ||
  !/^eldaftar_invoice_message[a-z0-9_]*$/.test(database)
) {
  throw Error('dedicated_local_database_required')
}

const executable = process.env.PSQL ?? 'psql'
const owner = randomUUID()
const shop = randomUUID()

function run(sql, allowFailure = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'], {
      stdio: ['pipe', 'pipe', 'pipe'],
    })
    let out = ''
    let err = ''
    child.stdout.on('data', (chunk) => { out += chunk })
    child.stderr.on('data', (chunk) => { err += chunk })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code && !allowFailure) reject(Error(err || out))
      else resolve({ code, out: out.trim(), err })
    })
    child.stdin.end(sql)
  })
}

const auth = `set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true); select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true);`
const payload = (revision, template = 'نص {sequence}') => JSON.stringify({
  version: 1,
  kind: 'invoice_message',
  expected_revision: String(revision),
  template,
})

let cleanupError = null
try {
  await run(`begin;
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at)
values ('${owner}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'message-race-${owner}@example.test', now(), false, now(), now());
insert into public.shops (id, name, owner_display_name, time_zone)
values ('${shop}', 'متجر التزامن', 'مالك التزامن', 'Africa/Cairo');
insert into public.shop_memberships (shop_id, user_id, role, revoked_at)
values ('${shop}', '${owner}', 'owner', null);
insert into public.shop_entitlements (shop_id, starts_at, expires_at)
values ('${shop}', now() - interval '1 day', now() + interval '30 days');
commit;`)

  const key = randomUUID()
  const same = await Promise.all([
    run(`begin; ${auth} select public.post_invoice_message_v1('${key}', '${payload(0)}'); commit;`),
    run(`begin; ${auth} select public.post_invoice_message_v1('${key}', '${payload(0)}'); commit;`),
  ])
  const bodies = same.map((result) => result.out.split('\n').filter((line) => line.startsWith('{')).at(-1))
  const parsed = bodies.map((line) => JSON.parse(line))
  if (parsed.filter((row) => row.replayed === true).length !== 1) throw Error('duplicate_message_replay')
  if (parsed.filter((row) => row.revision === '1').length !== 2) throw Error('duplicate_message_revision')
  if (parsed.some((row) => row.kind !== 'invoice_message' || row.invoice_effect !== false || row.dispatch_effect !== false)) {
    throw Error('duplicate_message_effect')
  }

  const current = JSON.parse((await run(`begin; ${auth} select public.get_invoice_message_v1(); commit;`)).out.split('\n').filter((line) => line.startsWith('{')).at(-1))
  const competing = await Promise.all([
    run(`begin; ${auth} select public.post_invoice_message_v1('${randomUUID()}', '${payload(current.revision)}'); commit;`, true),
    run(`begin; ${auth} select public.post_invoice_message_v1('${randomUUID()}', '${payload(current.revision, 'نص آخر {total}')}'); commit;`, true),
  ])
  if (competing.filter((result) => result.code === 0).length !== 1) throw Error('competing_message_versions')
  if (!competing.some((result) => result.err.includes('stale_message'))) throw Error('competing_message_stale')

  const mismatch = await run(
    `begin; ${auth} select public.post_invoice_message_v1('${key}', '${payload(9, 'payload changed')}'); commit;`,
    true,
  )
  if (!mismatch.err.includes('payload_mismatch')) throw Error('message_payload_mismatch')
} catch (error) {
  cleanupError = error
} finally {
  await run(`begin;
update public.shop_memberships
  set revoked_at = clock_timestamp()
  where shop_id = '${shop}' and user_id = '${owner}' and revoked_at is null;
update public.shop_entitlements
  set expires_at = clock_timestamp()
  where shop_id = '${shop}' and expires_at > clock_timestamp();
commit;`)
  const left = await run(`select
  (select count(*) from public.invoice_message_revisions where shop_id = '${shop}')::text
  || ',' || (select count(*) from public.invoice_message_audits where shop_id = '${shop}')::text
  || ',' || (select count(*) from public.invoice_message_requests where shop_id = '${shop}')::text
  || ',' || (select count(*) from public.shop_memberships where shop_id = '${shop}' and revoked_at is null)::text
  || ',' || (select count(*) from public.shop_entitlements where shop_id = '${shop}' and expires_at > clock_timestamp())::text;`)
  const [revisions, audits, requests, activeMembers, openEntitlements] = left.out.trim().split(',').map(Number)
  if (cleanupError === null && (revisions < 1 || audits < 1 || requests < 1)) {
    throw Error('message_history_missing_' + left.out.trim())
  }
  if (activeMembers !== 0 || openEntitlements !== 0) {
    throw Error('message_access_left_' + left.out.trim())
  }
}

if (cleanupError) throw cleanupError

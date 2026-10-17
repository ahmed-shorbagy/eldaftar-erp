// Dedicated disposable local database. Never accepts a hosted connection.
import { spawn } from 'node:child_process'
import { randomUUID } from 'node:crypto'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (
  url.protocol !== 'postgresql:' ||
  url.hostname !== '127.0.0.1' ||
  url.port !== '55454' ||
  url.pathname !== '/eldaftar_invoice_appearance'
) {
  throw Error('dedicated_local_database_required')
}

const executable = process.env.PSQL ?? 'psql'
const owner = 'c1111111-1111-4111-8111-111111111111'
const shop = 'c1222222-2222-4222-8222-222222222222'

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
const payload = (revision) => JSON.stringify({
  version: 1,
  kind: 'invoice_appearance',
  expected_revision: String(revision),
  slogan: null,
  address: null,
  template: 'header',
  accent: 'brown',
  logo_asset_id: null,
})

await run(`begin;
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, is_anonymous, created_at, updated_at)
values ('${owner}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'appearance-race@example.test', now(), false, now(), now())
on conflict (id) do nothing;
insert into public.shops (id, name, owner_display_name, time_zone)
values ('${shop}', 'متجر التزامن', 'مالك التزامن', 'Africa/Cairo')
on conflict (id) do nothing;
insert into public.shop_memberships (shop_id, user_id, role, revoked_at)
values ('${shop}', '${owner}', 'owner', null)
on conflict do nothing;
insert into public.shop_entitlements (shop_id, starts_at, expires_at)
select '${shop}', now() - interval '1 day', now() + interval '30 days'
where not exists (select 1 from public.shop_entitlements where shop_id = '${shop}' and expires_at > now());
commit;`)

const key = randomUUID()
const same = await Promise.all([
  run(`begin; ${auth} select public.post_invoice_appearance_v1('${key}', '${payload(0)}'); commit;`),
  run(`begin; ${auth} select public.post_invoice_appearance_v1('${key}', '${payload(0)}'); commit;`),
])
const bodies = same.map((result) => result.out.split('\n').filter((line) => line.startsWith('{')).at(-1))
const parsed = bodies.map((line) => JSON.parse(line))
if (parsed.filter((row) => row.replayed === true).length !== 1) throw Error('duplicate_appearance_replay')
if (parsed.filter((row) => row.revision === '1').length !== 2) throw Error('duplicate_appearance_revision')

const current = JSON.parse((await run(`begin; ${auth} select public.get_invoice_appearance_v1(); commit;`)).out.split('\n').filter((line) => line.startsWith('{')).at(-1))
const competing = await Promise.all([
  run(`begin; ${auth} select public.post_invoice_appearance_v1('${randomUUID()}', '${payload(current.revision)}'); commit;`, true),
  run(`begin; ${auth} select public.post_invoice_appearance_v1('${randomUUID()}', '${payload(current.revision)}'); commit;`, true),
])
if (competing.filter((result) => result.code === 0).length !== 1) throw Error('competing_appearance_versions')
if (!competing.some((result) => result.err.includes('stale_appearance'))) throw Error('competing_appearance_stale')

const mismatch = await run(
  `begin; ${auth} select public.post_invoice_appearance_v1('${key}', '${payload(9)}'); commit;`,
  true,
)
if (!mismatch.err.includes('payload_mismatch')) throw Error('appearance_payload_mismatch')

await run(`begin;
set local session_replication_role = replica;
delete from public.invoice_appearance_requests where shop_id = '${shop}';
delete from public.invoice_appearance_audits where shop_id = '${shop}';
delete from public.invoice_appearance_revisions where shop_id = '${shop}';
delete from public.shop_entitlements where shop_id = '${shop}';
delete from public.shop_memberships where shop_id = '${shop}';
delete from public.shops where id = '${shop}';
delete from auth.users where id = '${owner}';
commit;`)
const left = await run(`select
  (select count(*) from public.invoice_appearance_requests where shop_id = '${shop}')
  + (select count(*) from public.invoice_appearance_audits where shop_id = '${shop}')
  + (select count(*) from public.invoice_appearance_revisions where shop_id = '${shop}')
  + (select count(*) from public.shops where id = '${shop}')
  + (select count(*) from auth.users where id = '${owner}');`)
if (left.out.trim() !== '0') throw Error('appearance_fixture_left_' + left.out.trim())

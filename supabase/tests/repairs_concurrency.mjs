// Two real local connections. Synthetic rows stay in the disposable cluster.
import { spawn } from 'node:child_process'

const connection = process.env.SUPABASE_TEST_DATABASE_URL
const url = new URL(connection ?? 'http://invalid')
if (
  url.protocol !== 'postgresql:' ||
  url.hostname !== '127.0.0.1' ||
  !((url.port === '55445' && url.pathname === '/eldafttar_repairs') ||
    (url.port === '55446' && url.pathname === '/eldaftar_repairs_primary'))
) {
  throw new Error('dedicated_local_database_required')
}

const executable = process.env.PSQL ?? 'psql'
const owner = 'd1d1d1d1-d1d1-41d1-81d1-d1d1d1d1d1d1'
const shop = 'd2d2d2d2-d2d2-42d2-82d2-d2d2d2d2d2d2'

function run(sql, allowFailure = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(
      executable,
      [connection, '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1'],
      { stdio: ['pipe', 'pipe', 'pipe'] },
    )
    let output = ''
    let error = ''
    child.stdout.on('data', (chunk) => {
      output += chunk
    })
    child.stderr.on('data', (chunk) => {
      error += chunk
    })
    child.on('error', reject)
    child.on('close', (code) => {
      if (code && !allowFailure) reject(new Error(error || output))
      else resolve({ code, output: output.trim(), error })
    })
    child.stdin.end(sql)
  })
}

const auth = `set local role authenticated; select set_config('request.jwt.claim.sub','${owner}',true); select set_config('request.jwt.claims','{"sub":"${owner}","role":"authenticated","is_anonymous":false}',true);`
const setup = await run(`begin;
do $guard$ begin
  if exists(select 1 from auth.users where id='${owner}')
    or exists(select 1 from public.shops where id='${shop}') then
    raise exception 'fixture_collision';
  end if;
end; $guard$;
insert into auth.users(id,instance_id,aud,role,email,is_anonymous,created_at,updated_at)
values('${owner}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','repair-race@example.test',false,now(),now());
insert into public.shops(id,name,owner_display_name,time_zone)
values('${shop}','متجر سباق الإصلاح','مالك السباق','Africa/Cairo');
insert into public.shop_memberships(shop_id,user_id,role) values('${shop}','${owner}','owner');
insert into public.shop_entitlements(shop_id,starts_at,expires_at)
values('${shop}',now()-interval '1 day',now()+interval '1 day');
${auth}
select public.confirm_opening_balances('d3000000-0000-4000-8000-000000000001','{"version":1,"cash":{"cash":"500000","wallet":"100000"},"stock":[{"category":"worked_jewelry","karat":21,"milligrams":"5000","count":"1"}],"scrap":[]}');
select public.post_repair_intake_v1('d3000000-0000-4000-8000-000000000002','{"version":1,"kind":"repair_intake","customer_name":"سباق","customer_phone":"","item_description":"خاتم","measured_milligrams":"1255","karat":21,"issue":"مفصص","intake_notes":"","estimated_fee_piastres":"15000"}');
commit;`)
const intake = JSON.parse(setup.output.split('\n').filter((line) => line.startsWith('{')).at(-1))
const repairId = intake.repair_id

async function advance(key, version, status) {
  const result = await run(`begin;${auth}select public.post_repair_status_v1('${key}','{"version":1,"kind":"repair_status","repair_id":"${repairId}","expected_version":"${version}","status":"${status}"}');commit;`)
  return JSON.parse(result.output.split('\n').filter((line) => line.startsWith('{')).at(-1))
}
await advance('d3000000-0000-4000-8000-000000000003', '1', 'in_progress')
await advance('d3000000-0000-4000-8000-000000000004', '2', 'ready')

async function day() {
  const result = await run(`begin;${auth}select public.get_daily_ledger_day_state();rollback;`)
  return JSON.parse(result.output.split('\n').filter((line) => line.startsWith('{')).at(-1))
}
const openDay = await day()
const payload = {
  version: 1,
  kind: 'repair_handover',
  repair_id: repairId,
  expected_version: '3',
  final_fee_piastres: '20000',
  collection: 'all',
  collected_piastres: '20000',
  tenders: [
    { method: 'cash', piastres: '12000' },
    { method: 'wallet', piastres: '8000' },
  ],
  expected_day_id: openDay.business_day_id,
  expected_day_version: String(openDay.day_version),
}
function post(keyName, body) {
  return run(
    `begin;${auth}select public.post_repair_handover_v1('${keyName}','${JSON.stringify(body)}');commit;`,
    true,
  )
}
const sameKey = 'd3000000-0000-4000-8000-000000000005'
const same = await Promise.all([post(sameKey, payload), post(sameKey, payload)])
if (same.some((item) => item.code)) throw new Error(JSON.stringify(same))
const sameResults = same.map((item) =>
  JSON.parse(item.output.split('\n').filter((line) => line.startsWith('{')).at(-1)),
)
if (
  sameResults[0].repair_id !== sameResults[1].repair_id ||
  sameResults.filter((item) => item.replayed).length !== 1
) {
  throw new Error('same_key_duplicate')
}
const changed = await post(sameKey, { ...payload, final_fee_piastres: '10000', collected_piastres: '10000', tenders: [{ method: 'cash', piastres: '10000' }] })
if (!changed.code || !changed.error.includes('payload_mismatch')) {
  throw new Error('changed_payload_accepted')
}

const secondSetup = await run(`begin;${auth}
select public.post_repair_intake_v1('d3000000-0000-4000-8000-000000000006','{"version":1,"kind":"repair_intake","customer_name":"سباق ثان","customer_phone":"","item_description":"سلسلة","measured_milligrams":"2000","karat":18,"issue":"قص","intake_notes":"","estimated_fee_piastres":null}');
commit;`)
const second = JSON.parse(secondSetup.output.split('\n').filter((line) => line.startsWith('{')).at(-1)).repair_id
await run(`begin;${auth}select public.post_repair_status_v1('d3000000-0000-4000-8000-000000000007','{"version":1,"kind":"repair_status","repair_id":"${second}","expected_version":"1","status":"in_progress"}');commit;`)
await run(`begin;${auth}select public.post_repair_status_v1('d3000000-0000-4000-8000-000000000008','{"version":1,"kind":"repair_status","repair_id":"${second}","expected_version":"2","status":"ready"}');commit;`)
const nextDay = await day()
const competingBody = {
  ...payload,
  repair_id: second,
  expected_day_id: nextDay.business_day_id,
  expected_day_version: String(nextDay.day_version),
}
const competing = await Promise.all([
  post('d3000000-0000-4000-8000-000000000009', competingBody),
  post('d3000000-0000-4000-8000-000000000010', competingBody),
])
const winners = competing.filter((item) => !item.code)
const losers = competing.filter((item) => item.code)
if (winners.length !== 1 || !/stale_repair|repair_not_ready/.test(losers[0].error)) {
  throw new Error(`competing_handover:${JSON.stringify(competing)}`)
}
const check = await run(`begin;${auth}select jsonb_build_object(
  'releases', (select count(*) from public.repair_custody_events where shop_id='${shop}' and direction='release'),
  'fees', (select count(*) from public.financial_operations where shop_id='${shop}' and kind='repair_fee'),
  'requests', (select count(*) from public.repair_command_requests where shop_id='${shop}' and command_kind='repair_handover'),
  'lots', (select count(*) from public.inventory_lots where shop_id='${shop}'),
  'movements', (select count(*) from public.inventory_lot_movements where shop_id='${shop}'),
  'obligations', (select count(*) from public.gold_obligations where shop_id='${shop}')
);rollback;`)
const state = JSON.parse(check.output.split('\n').filter((line) => line.startsWith('{')).at(-1))
if (
  Number(state.releases) !== 2 ||
  Number(state.fees) !== 2 ||
  Number(state.requests) !== 2 ||
  Number(state.lots) !== 1 ||
  Number(state.movements) !== 1 ||
  Number(state.obligations) !== 0
) {
  throw new Error(`race_totals:${JSON.stringify(state)}`)
}
console.log('PASS: two connections, same-key handover replay, changed payload rejection, competing release once per repair. Local fixture retained.')
